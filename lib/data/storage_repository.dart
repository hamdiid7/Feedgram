import 'package:handy_tdlib/api.dart' as td;

import '../telegram/telegram_client.dart';

/// What the cache is using.
class StorageUsage {
  const StorageUsage({
    required this.mediaBytes,
    required this.fileCount,
    required this.databaseBytes,
  });

  /// Downloaded photos, videos, animations and documents.
  final int mediaBytes;

  final int fileCount;

  /// TDLib's own database — the session and message cache. Never cleared here:
  /// deleting it is a sign-out, not a cleanup.
  final int databaseBytes;

  static const empty =
      StorageUsage(mediaBytes: 0, fileCount: 0, databaseBytes: 0);
}

/// Reads and reclaims TDLib's on-disk cache.
///
/// Everything goes through TDLib rather than touching its directories directly.
/// It keeps its own index of what it has downloaded, and files deleted behind its
/// back leave that index claiming they are still there — which shows up later as
/// media that never loads because TDLib believes it is already local.
class StorageRepository {
  StorageRepository({required TelegramClient client}) : _client = client;

  final TelegramClient _client;

  /// The *fast* variant on purpose: the full `getStorageStatistics` walks every
  /// file and groups them by chat, which on a library this size takes long enough
  /// to need a spinner. A settings screen only needs the totals.
  Future<StorageUsage> usage() async {
    final stats = await _client
        .send<td.StorageStatisticsFast>(const td.GetStorageStatisticsFast());

    return StorageUsage(
      mediaBytes: stats.filesSize,
      fileCount: stats.fileCount,
      databaseBytes: stats.databaseSize,
    );
  }

  /// Deletes downloaded media, keeping the session and the message database.
  ///
  /// Returns the number of bytes reclaimed.
  Future<int> clearMedia() async {
    final before = await usage();

    await _client.send<td.StorageStatistics>(
      td.OptimizeStorage(
        // 0 = keep nothing. `ttl` and `count` are left wide open so the size
        // limit is the only rule in play; a ttl here would silently spare
        // recent files and make "clear" a lie.
        size: 0,
        ttl: 0,
        count: 0,
        // Files touched in the last few seconds are likely mid-render on screen
        // right now. Pulling one out from under an active decoder is how you get
        // a broken image where a photo used to be.
        immunityDelay: 60,
        // Empty means every type. Photos come back on the next scroll; profile
        // photos and thumbnails are small and regenerate immediately.
        fileTypes: const [],
        chatIds: const [],
        excludeChatIds: const [],
        returnDeletedFileStatistics: false,
        chatLimit: 0,
      ),
    );

    final after = await usage();
    // Measured rather than taken from the response: OptimizeStorage reports what
    // it decided to delete, which is not the same as what is now gone once the
    // immunity window has spared some of it.
    final reclaimed = before.mediaBytes - after.mediaBytes;
    return reclaimed < 0 ? 0 : reclaimed;
  }
}

/// Bytes as something readable. Binary units, matching what Android's own
/// storage screens report, so the two do not appear to disagree.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
}
