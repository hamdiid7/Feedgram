/// App-side view of TDLib's authorization state.
///
/// The UI routes on this, not on `AuthorizationState` — TDLib types stop at the
/// repository boundary.
enum AuthStage {
  /// Isolates starting, or `setTdlibParameters` in flight.
  connecting,

  needPhone,
  needCode,
  needPassword,

  /// Authorized. Everything from Phase 3 on requires this.
  ready,

  /// A state this client does not implement — see [AuthStatus.message].
  /// Registration, email login and QR login all land here.
  unsupported,

  /// Session ended, either by a dev reset or a server-side logout.
  loggedOut,

  /// TDLib is shutting down; the process needs a restart to use it again.
  closed,

  /// Startup failed outright.
  failed,
}

/// How Telegram delivered the login code, so the code screen can say where to
/// look instead of just "enter your code".
enum CodeDelivery {
  /// In-app message to another logged-in Telegram client.
  telegramMessage,
  sms,
  call,
  flashCall,
  missedCall,
  fragment,
  other,
}

class AuthStatus {
  const AuthStatus({
    required this.stage,
    this.busy = false,
    this.message,
    this.phoneNumber,
    this.delivery,
    this.codeLength,
    this.resendTimeout,
    this.passwordHint,
    this.hasRecoveryEmail = false,
    this.recoveryEmailPattern,
  });

  static const connecting = AuthStatus(stage: AuthStage.connecting);

  final AuthStage stage;

  /// A request is in flight; submit buttons should be disabled.
  final bool busy;

  /// Last actionable problem, e.g. an invalid code. Cleared on the next submit.
  final String? message;

  /// Number the code was sent to, as Telegram formatted it.
  final String? phoneNumber;

  final CodeDelivery? delivery;

  /// Expected code length, when Telegram tells us. `null` means unknown.
  final int? codeLength;

  /// Seconds until a resend is allowed.
  final int? resendTimeout;

  /// 2FA hint the user chose when setting their password.
  final String? passwordHint;
  final bool hasRecoveryEmail;
  final String? recoveryEmailPattern;

  bool get isAuthorized => stage == AuthStage.ready;

  AuthStatus copyWith({
    AuthStage? stage,
    bool? busy,
    String? message,
    bool clearMessage = false,
  }) {
    return AuthStatus(
      stage: stage ?? this.stage,
      busy: busy ?? this.busy,
      message: clearMessage ? null : (message ?? this.message),
      phoneNumber: phoneNumber,
      delivery: delivery,
      codeLength: codeLength,
      resendTimeout: resendTimeout,
      passwordHint: passwordHint,
      hasRecoveryEmail: hasRecoveryEmail,
      recoveryEmailPattern: recoveryEmailPattern,
    );
  }
}
