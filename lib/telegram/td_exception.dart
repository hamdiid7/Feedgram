/// Failure of a single TDLib request, raised by `TelegramClient.send`.
///
/// TDLib reports errors as a normal `error` response rather than by any
/// out-of-band channel, so this is the boundary that turns them back into Dart
/// exceptions.
class TdException implements Exception {
  TdException({required this.code, required this.message, this.request});

  final int code;
  final String message;

  /// `@type` of the request that failed, for logging.
  final String? request;

  /// Seconds TDLib wants us to wait before retrying, parsed from a
  /// `Too Many Requests: retry after N` message (error code 429).
  ///
  /// The retry itself is deliberately not automatic: the repository layer
  /// decides what is safe to replay. Callers must sleep the **full** duration.
  Duration? get floodWait {
    if (code != 429) return null;
    final match = RegExp(r'retry after (\d+)').firstMatch(message);
    if (match == null) return null;
    return Duration(seconds: int.parse(match.group(1)!));
  }

  bool get isFloodWait => floodWait != null;

  @override
  String toString() =>
      'TdException($code${request == null ? '' : ' on $request'}): $message';
}

/// No response with the matching `@extra` arrived in time. TDLib gives no
/// guarantee that every request is answered, so every pending completer needs a
/// deadline or the map leaks.
class TdTimeoutException implements Exception {
  TdTimeoutException(this.request, this.timeout);

  final String request;
  final Duration timeout;

  @override
  String toString() =>
      'TdTimeoutException: $request got no response in ${timeout.inSeconds}s';
}

/// TDLib answered, but not with the type the call site expected.
class TdUnexpectedResponse implements Exception {
  TdUnexpectedResponse({required this.request, required this.received});

  final String request;
  final String received;

  @override
  String toString() =>
      'TdUnexpectedResponse: $request returned $received';
}
