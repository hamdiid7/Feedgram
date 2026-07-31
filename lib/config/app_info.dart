/// Identity this app reports to Telegram in `setTdlibParameters`.
abstract final class AppInfo {
  /// Shown in Telegram's *Active sessions* list. Keep in sync with `version:`
  /// in pubspec.yaml.
  static const String version = '0.1.0';

  /// Telegram's API ToS forbids "Telegram" in a third-party client name unless
  /// prefixed with "Unofficial". Only relevant if this is ever published, but
  /// the name is baked in here, so keep it compliant from the start.
  static const String name = 'Feedgram';
}
