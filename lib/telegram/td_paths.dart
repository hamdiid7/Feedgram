import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where TDLib keeps its database and downloaded files.
///
/// Both live under the app's own private storage. That is deliberate: anywhere
/// outside it would drag in external-storage permissions, and the database holds
/// the account session — it has no business being world-readable.
///
/// The session lives in [databaseDirectory]. Deleting it is what makes a dev
/// reset work; see [wipe].
class TdPaths {
  const TdPaths({required this.databaseDirectory, required this.filesDirectory});

  final String databaseDirectory;
  final String filesDirectory;

  static Future<TdPaths> resolve() async {
    final root = await getApplicationSupportDirectory();
    final database = Directory(p.join(root.path, 'tdlib', 'db'));
    final files = Directory(p.join(root.path, 'tdlib', 'files'));

    await database.create(recursive: true);
    await files.create(recursive: true);

    return TdPaths(
      databaseDirectory: database.path,
      filesDirectory: files.path,
    );
  }

  /// Deletes the local session and cache — the supported dev reset.
  ///
  /// Deliberately not `logOut`: that invalidates the session server-side and
  /// burns a fresh login code on the next attempt. Deleting the directory just
  /// makes this device forget.
  ///
  /// TDLib must be **closed** first (see `AuthController.resetLocalSession`) or
  /// it will still hold the files open and recreate them.
  Future<void> wipe() async {
    for (final dir in [Directory(databaseDirectory), Directory(filesDirectory)]) {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
  }
}
