import 'package:handy_tdlib/api.dart' as td;

import '../td_exception.dart';
import 'auth_status.dart';

/// Pure TDLib-to-app translations used by `AuthController`. Split out so they
/// can be tested without a live client.

/// Turns a TDLib auth error into something worth showing a user.
///
/// FLOOD_WAIT is checked first: its message carries the wait, and telling
/// someone to retry immediately after one is the fastest way to earn a longer
/// one.
String humanizeAuthError(TdException e) {
  final flood = e.floodWait;
  if (flood != null) {
    return 'Too many attempts. Wait ${flood.inSeconds} seconds before trying '
        'again.';
  }
  return switch (e.message) {
    'PHONE_NUMBER_INVALID' => 'That phone number is not valid.',
    'PHONE_CODE_INVALID' => 'Wrong code. Check it and try again.',
    'PHONE_CODE_EMPTY' => 'Enter the code.',
    'PHONE_CODE_EXPIRED' => 'That code expired. Request a new one.',
    'PASSWORD_HASH_INVALID' => 'Wrong password.',
    'PHONE_NUMBER_BANNED' => 'This number is banned from Telegram.',
    'API_ID_INVALID' => 'api_id / api_hash are not a valid pair.',
    'API_ID_PUBLISHED_FLOOD' =>
      'This api_id is publicly known and rate-limited. Register your own at '
          'my.telegram.org.',
    _ => '${e.message} (${e.code})',
  };
}

CodeDelivery deliveryOf(td.AuthenticationCodeType type) => switch (type) {
      td.AuthenticationCodeTypeTelegramMessage() =>
        CodeDelivery.telegramMessage,
      td.AuthenticationCodeTypeSms() => CodeDelivery.sms,
      td.AuthenticationCodeTypeCall() => CodeDelivery.call,
      td.AuthenticationCodeTypeFlashCall() => CodeDelivery.flashCall,
      td.AuthenticationCodeTypeMissedCall() => CodeDelivery.missedCall,
      td.AuthenticationCodeTypeFragment() => CodeDelivery.fragment,
      _ => CodeDelivery.other,
    };

/// Expected code length, where Telegram states one.
///
/// `null` is a real answer, not a fallback: word and phrase codes have no fixed
/// length and flash-call gives a dial pattern instead. The code screen must not
/// auto-submit in those cases.
int? codeLengthOf(td.AuthenticationCodeType type) => switch (type) {
      td.AuthenticationCodeTypeTelegramMessage(:final length) => length,
      td.AuthenticationCodeTypeSms(:final length) => length,
      td.AuthenticationCodeTypeCall(:final length) => length,
      td.AuthenticationCodeTypeMissedCall(:final length) => length,
      td.AuthenticationCodeTypeFragment(:final length) => length,
      td.AuthenticationCodeTypeFirebaseAndroid(:final length) => length,
      td.AuthenticationCodeTypeFirebaseIos(:final length) => length,
      _ => null,
    };
