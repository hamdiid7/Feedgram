/// A post's permanent identity.
///
/// Used as the key for "already seen": row ids and TDLib file handles are local
/// and disposable, whereas this survives a cache wipe and a re-backfill.
///
/// Public channels get their real `t.me` link. Private ones have no public URL, so
/// they fall back to the numeric chat id — still stable, just not shareable.
String postLink({
  required int chatId,
  required int messageId,
  String? username,
}) {
  if (username != null && username.isNotEmpty) {
    return 't.me/$username/$messageId';
  }
  return 'c/$chatId/$messageId';
}
