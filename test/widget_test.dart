import 'package:flutter_test/flutter_test.dart';

import 'package:feedgram/telegram/td_exception.dart';

// Widget tests cannot cover TelegramClient: it opens libtdjson.so, which only
// exists on the device. What is testable off-device is the error mapping the
// whole sync layer depends on.
void main() {
  group('TdException.floodWait', () {
    test('parses the retry duration from a 429', () {
      final e = TdException(
        code: 429,
        message: 'Too Many Requests: retry after 47',
      );
      expect(e.isFloodWait, isTrue);
      expect(e.floodWait, const Duration(seconds: 47));
    });

    test('is null for non-429 errors', () {
      final e = TdException(code: 400, message: 'USERNAME_NOT_OCCUPIED');
      expect(e.isFloodWait, isFalse);
      expect(e.floodWait, isNull);
    });

    test('is null when a 429 carries no duration', () {
      final e = TdException(code: 429, message: 'Too Many Requests');
      expect(e.floodWait, isNull);
    });
  });
}
