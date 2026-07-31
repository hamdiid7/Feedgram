/// Reduces the ways people write a channel reference down to the bare username
/// that `searchPublicChat` expects.
///
/// Accepts `name`, `@name`, `t.me/name`, `https://t.me/name`, and the
/// `telegram.me` variant. Returns `null` when nothing usable is left, so callers
/// can reject input before spending a TDLib request on it.
String? normalizeChannelUsername(String input) {
  var value = input.trim();
  if (value.isEmpty) return null;

  // Strip scheme and host if a link was pasted.
  value = value.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
  value = value.replaceFirst(
    RegExp(r'^(www\.)?(t|telegram)\.me/', caseSensitive: false),
    '',
  );

  // Private invite links resolve through joinChatByInviteLink, not
  // searchPublicChat — there is no username in them to extract.
  if (value.startsWith('+') || value.startsWith('joinchat/')) return null;

  value = value.replaceFirst('@', '');

  // Drop any query string or trailing path from a pasted link.
  value = value.split(RegExp(r'[/?#]')).first.trim();

  // Telegram usernames: 5-32 chars, letters/digits/underscore, must not start
  // with a digit. Checking here keeps obviously bad input off the network.
  if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]{3,31}$').hasMatch(value)) return null;

  return value;
}
