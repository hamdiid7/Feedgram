import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;

import 'package:feedgram/telegram/auth/auth_controller.dart';
import 'package:feedgram/telegram/auth/auth_status.dart';
import 'package:feedgram/telegram/td_paths.dart';
import 'package:feedgram/telegram/telegram_client.dart';

/// These run off-device, which works because the paths exercised here never
/// reach TDLib: constructing a [TelegramClient] spawns nothing (only `start()`
/// does), and with no `--dart-define` credentials `TdCredentials.isConfigured` is
/// false, so `_sendParameters` bails out before touching the client.
AuthController newController() => AuthController(
      client: TelegramClient(),
      paths: const TdPaths(
        databaseDirectory: '/tmp/feedgram-test/db',
        filesDirectory: '/tmp/feedgram-test/files',
      ),
    );

void main() {
  group('applyAuthorizationState', () {
    // Regression: TDLib delivers waitTdlibParameters twice — once as an update,
    // once as the getAuthorizationState response. Handling it sets the stage to
    // `failed` when credentials are missing; re-handling the duplicate used to
    // reset the stage back to `connecting`, throwing the real error away and
    // leaving the app on the connecting spinner forever.
    test('a duplicate waitTdlibParameters does not clobber the outcome', () {
      final auth = newController();
      addTearDown(auth.dispose);

      auth.applyAuthorizationState(
        const td.AuthorizationStateWaitTdlibParameters(),
      );
      expect(auth.status.stage, AuthStage.failed,
          reason: 'missing credentials should surface immediately');
      final firstMessage = auth.status.message;

      auth.applyAuthorizationState(
        const td.AuthorizationStateWaitTdlibParameters(),
      );
      expect(auth.status.stage, AuthStage.failed);
      expect(auth.status.message, firstMessage);
    });

    test('surfaces unsupported states instead of sitting silent', () {
      final auth = newController();
      addTearDown(auth.dispose);

      auth.applyAuthorizationState(
        const td.AuthorizationStateWaitRegistration(
          termsOfService: td.TermsOfService(
            text: td.FormattedText(text: '', entities: []),
            minUserAge: 0,
            showPopup: false,
          ),
        ),
      );
      expect(auth.status.stage, AuthStage.unsupported);
      expect(auth.status.message, isNotNull);
    });

    test('carries a pending error across a same-stage re-delivery', () {
      final auth = newController();
      addTearDown(auth.dispose);

      auth.applyAuthorizationState(
        const td.AuthorizationStateWaitCode(
          codeInfo: td.AuthenticationCodeInfo(
            phoneNumber: '+251911234567',
            type: td.AuthenticationCodeTypeSms(length: 5),
            timeout: 60,
          ),
        ),
      );
      auth.debugSetMessage('Wrong code. Check it and try again.');

      // TDLib re-reporting the step we are already on must not wipe the error.
      auth.applyAuthorizationState(
        const td.AuthorizationStateWaitCode(
          codeInfo: td.AuthenticationCodeInfo(
            phoneNumber: '+251911234567',
            type: td.AuthenticationCodeTypeSms(length: 5),
            timeout: 60,
          ),
        ),
      );
      expect(auth.status.stage, AuthStage.needCode);
      expect(auth.status.message, 'Wrong code. Check it and try again.');
      expect(auth.status.codeLength, 5);
    });

    test('a real stage change clears a stale error', () {
      final auth = newController();
      addTearDown(auth.dispose);

      auth.applyAuthorizationState(
        const td.AuthorizationStateWaitPhoneNumber(),
      );
      auth.debugSetMessage('That phone number is not valid.');

      auth.applyAuthorizationState(
        const td.AuthorizationStateWaitCode(
          codeInfo: td.AuthenticationCodeInfo(
            phoneNumber: '+251911234567',
            type: td.AuthenticationCodeTypeSms(length: 5),
            timeout: 60,
          ),
        ),
      );
      expect(auth.status.stage, AuthStage.needCode);
      expect(auth.status.message, isNull);
    });
  });
}
