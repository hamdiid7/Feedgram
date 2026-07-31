import 'package:flutter_test/flutter_test.dart';

import 'package:feedgram/data/channel_username.dart';

void main() {
  group('normalizeChannelUsername', () {
    test('accepts the forms people actually paste', () {
      for (final input in [
        'durov',
        '@durov',
        ' @durov ',
        't.me/durov',
        'T.me/durov',
        'https://t.me/durov',
        'http://www.t.me/durov',
        'https://telegram.me/durov',
        'https://t.me/durov/',
        'https://t.me/durov?single',
      ]) {
        expect(normalizeChannelUsername(input), 'durov', reason: input);
      }
    });

    test('rejects private invite links', () {
      // These need joinChatByInviteLink and a real invite; searchPublicChat
      // cannot resolve them, so they must not reach the network.
      expect(normalizeChannelUsername('https://t.me/+AbCdEfGh'), isNull);
      expect(normalizeChannelUsername('t.me/joinchat/AbCdEfGh'), isNull);
    });

    test('rejects usernames Telegram cannot have', () {
      expect(normalizeChannelUsername(''), isNull);
      expect(normalizeChannelUsername('   '), isNull);
      expect(normalizeChannelUsername('abc'), isNull, reason: 'too short');
      expect(normalizeChannelUsername('1durov'), isNull,
          reason: 'cannot start with a digit');
      expect(normalizeChannelUsername('has-a-dash'), isNull);
      expect(normalizeChannelUsername('a' * 33), isNull, reason: 'too long');
    });

    test('keeps underscores and digits after the first character', () {
      expect(normalizeChannelUsername('@news_et2024'), 'news_et2024');
    });
  });
}
