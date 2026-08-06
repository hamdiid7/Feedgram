import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:handy_tdlib/api.dart' as td;

import '../../config/app_info.dart';
import '../../config/td_credentials.dart';
import '../td_exception.dart';
import '../td_paths.dart';
import '../telegram_client.dart';
import 'auth_mapping.dart';
import 'auth_status.dart';

/// The login state machine, driven purely by `updateAuthorizationState`.
///
/// Nothing here decides what comes next — TDLib does. Every submit method sends
/// one request and then goes quiet; the next screen appears because TDLib
/// emitted the next state, not because this class advanced anything. That is
/// what keeps a restart on an existing session (which jumps straight to
/// `authorizationStateReady`) on exactly the same code path as a fresh login.
class AuthController extends ChangeNotifier {
  AuthController({required TelegramClient client, required TdPaths paths})
      : _client = client,
        _paths = paths;

  final TelegramClient _client;
  final TdPaths _paths;

  StreamSubscription<td.Update>? _subscription;

  /// `setTdlibParameters` must be sent exactly once. Both the update stream and
  /// the explicit `getAuthorizationState` below can report
  /// `waitTdlibParameters`, and sending it twice makes the second call error.
  var _parametersSent = false;

  AuthStatus _status = AuthStatus.connecting;
  AuthStatus get status => _status;

  Future<void> start() async {
    // Subscribe before the first request so no state transition is missed.
    _subscription ??= _client.updates.listen((update) {
      if (update is td.UpdateAuthorizationState) {
        _apply(update.authorizationState);
      }
    });

    try {
      await _client.start();
      // Doubles as the request that wakes the client and as a guard against
      // having subscribed too late: TDLib returns the current state directly.
      final state =
          await _client.send<td.AuthorizationState>(td.GetAuthorizationState());
      _apply(state);
    } catch (e) {
      _set(AuthStatus(stage: AuthStage.failed, message: '$e'));
    }
  }

  /// Applies one TDLib authorization state. Must be idempotent — see the
  /// `waitTdlibParameters` case.
  @visibleForTesting
  void applyAuthorizationState(td.AuthorizationState state) => _apply(state);

  /// Sets an error message the way a failed submit would, for tests.
  @visibleForTesting
  void debugSetMessage(String message) {
    _set(_status.copyWith(message: message));
  }

  void _apply(td.AuthorizationState state) {
    switch (state) {
      case td.AuthorizationStateWaitTdlibParameters():
        // TDLib delivers this state twice — once as an update, once as the
        // `getAuthorizationState` response — and `_sendParameters` can move the
        // stage off `connecting` (to `failed`) before the second one lands.
        // Re-applying it then would wipe that result and strand the app on the
        // connecting spinner with the real error thrown away. Once we have acted
        // on this state, ignore repeats.
        if (_parametersSent) return;
        _transition(AuthStatus.connecting);
        _sendParameters();

      case td.AuthorizationStateWaitPhoneNumber():
        _transition(const AuthStatus(stage: AuthStage.needPhone));

      case td.AuthorizationStateWaitCode(:final codeInfo):
        _transition(AuthStatus(
          stage: AuthStage.needCode,
          phoneNumber: codeInfo.phoneNumber,
          delivery: deliveryOf(codeInfo.type),
          codeLength: codeLengthOf(codeInfo.type),
          resendTimeout: codeInfo.timeout,
        ));

      case td.AuthorizationStateWaitPassword(
          :final passwordHint,
          :final hasRecoveryEmailAddress,
          :final recoveryEmailAddressPattern,
        ):
        _transition(AuthStatus(
          stage: AuthStage.needPassword,
          passwordHint: passwordHint.isEmpty ? null : passwordHint,
          hasRecoveryEmail: hasRecoveryEmailAddress,
          recoveryEmailPattern: recoveryEmailAddressPattern.isEmpty
              ? null
              : recoveryEmailAddressPattern,
        ));

      case td.AuthorizationStateReady():
        _transition(const AuthStatus(stage: AuthStage.ready));

      case td.AuthorizationStateLoggingOut():
        _transition(const AuthStatus(
          stage: AuthStage.loggedOut,
          message: 'Signing out…',
        ));

      case td.AuthorizationStateClosing():
      case td.AuthorizationStateClosed():
        // A closed TDLib client cannot be reopened in-process.
        _transition(const AuthStatus(
          stage: AuthStage.closed,
          message: 'Local session cleared. Restart the app to sign in again.',
        ));

      // Reachable states this feed reader does not implement. Surfaced rather
      // than ignored — silently ignoring one looks like a hang.
      case td.AuthorizationStateWaitRegistration():
        _transition(const AuthStatus(
          stage: AuthStage.unsupported,
          message: 'That number has no Telegram account. Sign up in the '
              'official Telegram app first, then come back.',
        ));

      case td.AuthorizationStateWaitEmailAddress():
      case td.AuthorizationStateWaitEmailCode():
        _transition(const AuthStatus(
          stage: AuthStage.unsupported,
          message: 'This account requires email login, which this client does '
              'not support yet.',
        ));

      case td.AuthorizationStateWaitOtherDeviceConfirmation():
        _transition(const AuthStatus(
          stage: AuthStage.unsupported,
          message: 'QR code login is not supported. Use a phone number.',
        ));
    }
  }

  /// Applies a state reported by TDLib.
  ///
  /// Carries the current message forward when the stage has not changed: TDLib
  /// re-emitting the state we are already on must not wipe a fresh "wrong code"
  /// off the screen. A genuine stage change does clear it, because by then it
  /// describes a step the user has left behind.
  void _transition(AuthStatus next) {
    if (next.stage == _status.stage && next.message == null) {
      _set(next.copyWith(message: _status.message));
      return;
    }
    _set(next);
  }

  Future<void> _sendParameters() async {
    if (_parametersSent) return;
    _parametersSent = true;

    if (!TdCredentials.isConfigured) {
      _set(const AuthStatus(
        stage: AuthStage.failed,
        message: 'Missing api_id / api_hash. Copy '
            'td_credentials.example.json to td_credentials.json, fill it in, '
            'and rebuild with --dart-define-from-file=td_credentials.json.',
      ));
      return;
    }

    try {
      await _client.send<td.Ok>(td.SetTdlibParameters(
        useTestDc: false,
        databaseDirectory: _paths.databaseDirectory,
        filesDirectory: _paths.filesDirectory,
        // Empty = unencrypted local database. It sits in app-private storage,
        // and a key would need somewhere safe of its own to live — losing it
        // bricks the session with a 401.
        databaseEncryptionKey: '',
        useFileDatabase: true,
        useChatInfoDatabase: true,
        // The whole point: message history survives restarts, so the feed has
        // something to show before any network round trip.
        useMessageDatabase: true,
        useSecretChats: false,
        apiId: TdCredentials.apiId,
        apiHash: TdCredentials.apiHash,
        systemLanguageCode: _systemLanguageCode(),
        deviceModel: await _deviceModel(),
        // Empty lets TDLib detect the OS version itself.
        systemVersion: '',
        applicationVersion: AppInfo.version,
      ));
    } on TdException catch (e) {
      _parametersSent = false;
      // Never interpolate the parameters themselves into a message — api_hash
      // must not reach a log or a screen.
      _set(AuthStatus(
        stage: AuthStage.failed,
        message: 'setTdlibParameters failed (${e.code}): ${e.message}',
      ));
    }
  }

  Future<void> submitPhoneNumber(String phoneNumber) async {
    await _guard(() => _client.send<td.Ok>(
          td.SetAuthenticationPhoneNumber(phoneNumber: phoneNumber.trim()),
        ));
  }

  Future<void> submitCode(String code) async {
    await _guard(() => _client.send<td.Ok>(
          td.CheckAuthenticationCode(code: code.trim()),
        ));
  }

  Future<void> submitPassword(String password) async {
    // Not trimmed: a 2FA password may legitimately start or end with a space.
    await _guard(() => _client.send<td.Ok>(
          td.CheckAuthenticationPassword(password: password),
        ));
  }

  Future<void> resendCode() async {
    await _guard(() => _client.send<td.Ok>(td.ResendAuthenticationCode()));
  }

  /// Goes back to the phone entry screen after a mistyped number.
  ///
  /// TDLib has no "cancel code" call; re-sending the phone number from
  /// `waitCode` is the supported way back, so the UI just re-renders the phone
  /// screen and the next `setAuthenticationPhoneNumber` supersedes the old one.
  void restartPhoneEntry() {
    _set(const AuthStatus(stage: AuthStage.needPhone));
  }

  /// Signs out of Telegram for real.
  ///
  /// `logOut` ends the session **server-side**: this device disappears from the
  /// account's active-session list and the next launch needs a fresh login code.
  /// That is deliberately not the same as [resetLocalSession], which only clears
  /// this device and leaves the session valid.
  ///
  /// Not reversible, and not free — each new login burns an SMS code, and doing
  /// it repeatedly is exactly what trips Telegram's flood limits. The UI asks
  /// before calling this.
  ///
  /// TDLib drives the rest itself: `logOut` makes it emit
  /// `authorizationStateLoggingOut` and then `authorizationStateClosed`, so the
  /// state machine walks back to the login screen without this method steering
  /// it — the same principle as every other transition here.
  Future<void> signOut() async {
    _set(_status.copyWith(busy: true, clearMessage: true));
    try {
      await _client.send<td.Ok>(const td.LogOut());
    } on TdException catch (e) {
      _set(AuthStatus(stage: AuthStage.failed, message: 'Sign out failed: $e'));
    }
  }

  /// Dev reset: closes TDLib, then deletes the local database and files.
  ///
  /// Not `logOut` — that invalidates the session server-side and burns a fresh
  /// login code. The process must be restarted afterwards; a closed TDLib
  /// client cannot be reopened.
  Future<void> resetLocalSession() async {
    _set(_status.copyWith(busy: true, clearMessage: true));
    try {
      await _client.send<td.Ok>(td.Close());
      // Give TDLib a moment to flush and release its file handles, otherwise
      // the delete below races it.
      await Future<void>.delayed(const Duration(seconds: 2));
    } catch (_) {
      // Already closed or unresponsive — the delete is what matters.
    }

    try {
      await _paths.wipe();
      _set(const AuthStatus(
        stage: AuthStage.closed,
        message: 'Local session deleted. Restart the app to sign in again.',
      ));
    } catch (e) {
      _set(AuthStatus(stage: AuthStage.failed, message: 'Reset failed: $e'));
    }
  }

  /// Runs one auth request, mapping TDLib errors onto [AuthStatus.message]
  /// without changing the stage: on a bad code or password TDLib stays in the
  /// same state, so the user should stay on the same screen with an error.
  Future<void> _guard(Future<void> Function() action) async {
    _set(_status.copyWith(busy: true, clearMessage: true));
    try {
      await action();
      // Deliberately no stage change here — the next updateAuthorizationState
      // drives that.
      _set(_status.copyWith(busy: false));
    } on TdException catch (e) {
      _set(_status.copyWith(busy: false, message: humanizeAuthError(e)));
    } catch (e) {
      _set(_status.copyWith(busy: false, message: '$e'));
    }
  }

  void _set(AuthStatus status) {
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// IETF tag for the device locale; TDLib requires it to be non-empty.
String _systemLanguageCode() {
  final locale = Platform.localeName; // e.g. en_US.UTF-8
  final tag = locale.split('.').first.replaceAll('_', '-');
  return tag.isEmpty ? 'en' : tag;
}

/// Shown in Telegram's *Active sessions* list, so it should be recognisable
/// enough that the user can spot and revoke this session.
Future<String> _deviceModel() async {
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    final model = '${info.manufacturer} ${info.model}'.trim();
    return model.isEmpty ? 'Android' : model;
  } catch (_) {
    return 'Android';
  }
}
