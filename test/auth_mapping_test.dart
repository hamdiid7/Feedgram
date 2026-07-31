import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;

import 'package:feedgram/telegram/auth/auth_mapping.dart';
import 'package:feedgram/telegram/auth/auth_status.dart';
import 'package:feedgram/telegram/td_exception.dart';

void main() {
  group('codeLengthOf', () {
    test('reads the length from types that publish one', () {
      expect(
        codeLengthOf(const td.AuthenticationCodeTypeSms(length: 5)),
        5,
      );
      expect(
        codeLengthOf(const td.AuthenticationCodeTypeTelegramMessage(length: 6)),
        6,
      );
    });

    // The code screen auto-submits once the expected length is reached, so a
    // wrong non-null answer here would fire a request on a half-typed code.
    test('is null for types with no fixed length', () {
      expect(
        codeLengthOf(const td.AuthenticationCodeTypeFlashCall(pattern: '*12*')),
        isNull,
      );
      expect(
        codeLengthOf(
          const td.AuthenticationCodeTypeSmsWord(firstLetter: 'a'),
        ),
        isNull,
      );
      expect(
        codeLengthOf(
          const td.AuthenticationCodeTypeSmsPhrase(firstWord: 'alpha'),
        ),
        isNull,
      );
    });
  });

  group('deliveryOf', () {
    test('distinguishes in-app messages from SMS', () {
      // Worth being exact about: a telegramMessage code never arrives as an
      // SMS, and telling the user to check their texts is a dead end.
      expect(
        deliveryOf(const td.AuthenticationCodeTypeTelegramMessage(length: 5)),
        CodeDelivery.telegramMessage,
      );
      expect(
        deliveryOf(const td.AuthenticationCodeTypeSms(length: 5)),
        CodeDelivery.sms,
      );
    });

    test('falls back to other for unmapped types', () {
      expect(
        deliveryOf(const td.AuthenticationCodeTypeSmsWord(firstLetter: 'a')),
        CodeDelivery.other,
      );
    });
  });

  group('humanizeAuthError', () {
    test('surfaces the flood wait duration ahead of the raw message', () {
      final message = humanizeAuthError(TdException(
        code: 429,
        message: 'Too Many Requests: retry after 120',
      ));
      expect(message, contains('120 seconds'));
    });

    test('translates known auth errors', () {
      expect(
        humanizeAuthError(
            TdException(code: 400, message: 'PHONE_CODE_INVALID')),
        'Wrong code. Check it and try again.',
      );
      expect(
        humanizeAuthError(
            TdException(code: 400, message: 'PASSWORD_HASH_INVALID')),
        'Wrong password.',
      );
    });

    test('keeps the raw message and code for unknown errors', () {
      final message = humanizeAuthError(
        TdException(code: 400, message: 'SOMETHING_NEW'),
      );
      expect(message, contains('SOMETHING_NEW'));
      expect(message, contains('400'));
    });
  });

  group('AuthStatus.copyWith', () {
    test('clearMessage wins over an inherited message', () {
      const status = AuthStatus(
        stage: AuthStage.needCode,
        message: 'Wrong code. Check it and try again.',
      );
      expect(status.copyWith(busy: true, clearMessage: true).message, isNull);
    });

    test('preserves the step details it does not take as parameters', () {
      const status = AuthStatus(
        stage: AuthStage.needCode,
        phoneNumber: '+251 91 234 5678',
        codeLength: 5,
        delivery: CodeDelivery.sms,
      );
      final busy = status.copyWith(busy: true);
      expect(busy.phoneNumber, '+251 91 234 5678');
      expect(busy.codeLength, 5);
      expect(busy.delivery, CodeDelivery.sms);
    });
  });
}
