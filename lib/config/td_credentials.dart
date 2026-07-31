/// Telegram API credentials, supplied at build time and never committed.
///
/// Get your own pair from https://my.telegram.org → API development tools and
/// pass them to the build:
///
/// ```
/// flutter run --dart-define-from-file=td_credentials.json
/// flutter build apk --release --target-platform android-arm64 \
///     --dart-define-from-file=td_credentials.json
/// ```
///
/// `td_credentials.json` sits at the repo root, is gitignored, and looks like:
/// `{"TG_API_ID": "1234567", "TG_API_HASH": "..."}`.
///
/// Never hardcode a fallback here, and never use the sample `api_id` from the
/// TDLib source tree — that one is public and earns an `API_ID_PUBLISHED_FLOOD`
/// ban. These values must also never be logged; nothing in this file has a
/// `toString` that exposes them.
abstract final class TdCredentials {
  static const String _rawApiId = String.fromEnvironment('TG_API_ID');
  static const String apiHash = String.fromEnvironment('TG_API_HASH');

  static int get apiId => int.parse(_rawApiId);

  /// True when both values were supplied at build time. Phase 1 does not need
  /// them — `getOption` works on an unconfigured client — but auth does, so the
  /// UI can warn early instead of failing at `setTdlibParameters`.
  /// `> 0` rather than just parseable: the example file ships `"0"`, and letting
  /// that through would surface as a confusing `API_ID_INVALID` from Telegram
  /// instead of a clear "fill in your credentials".
  static bool get isConfigured =>
      (int.tryParse(_rawApiId) ?? 0) > 0 && apiHash.isNotEmpty;
}
