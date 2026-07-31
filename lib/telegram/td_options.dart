import 'package:handy_tdlib/api.dart' as td;

import 'telegram_client.dart';

/// Typed access to TDLib options, so callers get plain Dart values instead of
/// `OptionValue` subclasses. Part of keeping TDLib objects out of the UI layer.
extension TelegramClientOptions on TelegramClient {
  /// Reads a string option. `null` when the option is unset
  /// (`optionValueEmpty`) rather than throwing.
  Future<String?> optionString(String name) async {
    final value = await send<td.OptionValue>(td.GetOption(name: name));
    return switch (value) {
      td.OptionValueString(:final value) => value,
      _ => null,
    };
  }

  Future<int?> optionInt(String name) async {
    final value = await send<td.OptionValue>(td.GetOption(name: name));
    return switch (value) {
      td.OptionValueInteger(:final value) => value,
      _ => null,
    };
  }

  Future<bool?> optionBool(String name) async {
    final value = await send<td.OptionValue>(td.GetOption(name: name));
    return switch (value) {
      td.OptionValueBoolean(:final value) => value,
      _ => null,
    };
  }

  /// The TDLib version the linked native library reports. Callable before
  /// `setTdlibParameters`, which is what makes it a good end-to-end smoke test
  /// of the isolate wiring.
  Future<String?> tdlibVersion() => optionString('version');

  /// Git commit of the linked TDLib build.
  Future<String?> tdlibCommitHash() => optionString('commit_hash');
}
