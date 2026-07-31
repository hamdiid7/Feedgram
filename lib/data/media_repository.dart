import 'dart:async';
import 'dart:io';

import 'package:handy_tdlib/api.dart' as td;

import '../telegram/telegram_client.dart';

/// Progress of one file download.
class MediaDownload {
  const MediaDownload({
    required this.fileId,
    this.localPath,
    this.progress = 0,
    this.downloadedSize = 0,
  });

  final int fileId;

  /// Set once the file is fully on disk **and** verified to exist.
  final String? localPath;

  /// 0..1, best effort.
  final double progress;

  /// Bytes on disk so far. The scheduler watches this rather than the clock: a
  /// slow transfer is still a live one, and only a *stalled* byte count means
  /// nothing is happening.
  final int downloadedSize;

  bool get isComplete => localPath != null;
}

/// A file TDLib will never deliver, however long you wait.
///
/// Distinguishing this from a slow download matters: retrying it is pure waste,
/// and leaving it pending shows the user a placeholder that can never resolve.
class MediaUnavailableException implements Exception {
  const MediaUnavailableException(this.fileId, this.reason);

  final int fileId;
  final String reason;

  @override
  String toString() => 'MediaUnavailableException($fileId): $reason';
}

/// Downloads media on demand.
///
/// `file_reference` expiry is deliberately not handled here: TDLib refreshes
/// references internally, so it is not the client's problem.
class MediaRepository {
  MediaRepository({required TelegramClient client}) : _client = client;

  final TelegramClient _client;

  /// Resolves a persistent remote file id to a local id valid in this session.
  ///
  /// TDLib's local file ids belong to the instance that issued them. A id stored
  /// by an earlier run makes `downloadFile` answer `400: Invalid file
  /// identifier`, and the image is then stuck on its placeholder for good. The
  /// remote id survives restarts, so it is the one worth persisting.
  Future<int?> resolveRemote(String remoteId) async {
    try {
      final file = await _client.send<td.File>(
        td.GetRemoteFile(remoteFileId: remoteId, fileType: const td.FileTypePhoto()),
      );
      return file.id;
    } catch (_) {
      return null;
    }
  }

  /// Drops a download TDLib has not started yet.
  ///
  /// `onlyIfPending: true` is the important part — it never interrupts a transfer
  /// that is already streaming, so scrolling past a half-downloaded image does
  /// not throw away the bytes already paid for.
  Future<void> cancelPending(int fileId) async {
    try {
      await _client.send<td.Ok>(
        td.CancelDownloadFile(fileId: fileId, onlyIfPending: true),
      );
    } catch (_) {
      // Nothing pending, or already finished.
    }
  }

  /// Starts (or resumes) a download and reports progress until the file is on
  /// disk.
  ///
  /// Three things here are load-bearing, each fixing a way an image can hang on
  /// its placeholder forever:
  ///
  /// 1. **The update listener is attached before the request is sent.** TDLib can
  ///    answer and emit `updateFile` before `downloadFile` returns; registering
  ///    afterwards drops that update and the stream never completes.
  /// 2. **The `File` returned by `downloadFile` is inspected synchronously.** A
  ///    file TDLib already has is already in a terminal state, so it may emit no
  ///    `updateFile` at all. Waiting for the update stream on exactly those files
  ///    waits forever.
  /// 3. **A path is not proof the bytes exist.** TDLib or the OS can evict a
  ///    cached file while still reporting it complete, so existence is checked and
  ///    a missing file is deleted from TDLib's view and re-fetched — otherwise
  ///    re-requesting just returns "complete" again, forever.
  Stream<MediaDownload> download(int fileId) {
    final controller = StreamController<MediaDownload>();
    StreamSubscription<td.Update>? subscription;
    var settled = false;

    Future<void> close() async {
      await subscription?.cancel();
      if (!controller.isClosed) await controller.close();
    }

    Future<void> finish(MediaDownload value) async {
      if (settled || controller.isClosed) return;
      settled = true;
      controller.add(value);
      await close();
    }

    Future<void> fail(Object error) async {
      if (settled || controller.isClosed) return;
      settled = true;
      controller.addError(error);
      await close();
    }

    /// Resolves a file TDLib reports as complete, re-fetching it if the bytes
    /// have gone missing from disk.
    Future<void> resolveCompleted(td.File file, {required bool mayRepair}) async {
      final path = file.local.path;
      if (path.isNotEmpty && File(path).existsSync()) {
        await finish(MediaDownload(
          fileId: fileId,
          localPath: path,
          progress: 1,
          downloadedSize: file.local.downloadedSize,
        ));
        return;
      }

      if (!mayRepair) {
        await fail(MediaUnavailableException(
          fileId,
          'reported complete but the file is not on disk',
        ));
        return;
      }

      // Clear TDLib's belief that it holds the file, then ask again. Without the
      // delete, `downloadFile` keeps answering "already complete" and the image
      // can never recover.
      try {
        await _client.send<td.Ok>(td.DeleteFile(fileId: fileId));
      } catch (_) {
        // Not deletable; the retry below is still worth attempting.
      }

      try {
        final refetched = await _client.send<td.File>(td.DownloadFile(
          fileId: fileId,
          priority: _priority,
          offset: 0,
          limit: 0,
          synchronous: false,
        ));
        if (refetched.local.isDownloadingCompleted) {
          await resolveCompleted(refetched, mayRepair: false);
        }
        // Otherwise the update stream carries it from here.
      } catch (e) {
        await fail(e);
      }
    }

    controller.onListen = () async {
      // Before the request — see (1) above.
      subscription = _client.updates.listen((update) {
        if (update is! td.UpdateFile) return;
        final file = update.file;
        if (file.id != fileId) return;

        if (file.local.isDownloadingCompleted) {
          resolveCompleted(file, mayRepair: true);
        } else if (!controller.isClosed && !settled) {
          controller.add(MediaDownload(
            fileId: fileId,
            progress: _progressOf(file),
            downloadedSize: file.local.downloadedSize,
          ));
        }
      });

      try {
        final file = await _client.send<td.File>(td.DownloadFile(
          fileId: fileId,
          priority: _priority,
          offset: 0,
          limit: 0,
          // Asynchronous, so progress can be reported while it streams.
          synchronous: false,
        ));

        // See (2) above.
        if (file.local.isDownloadingCompleted) {
          await resolveCompleted(file, mayRepair: true);
          return;
        }

        // Nothing will ever arrive for this one, so say so now rather than
        // leaving a placeholder pending forever.
        if (!file.local.canBeDownloaded) {
          await fail(const MediaUnavailableException(
            0,
            'TDLib reports the file cannot be downloaded',
          ).withFileId(fileId));
          return;
        }

        // Seed an initial progress event so the scheduler's stall watchdog has a
        // byte count to compare against.
        if (!controller.isClosed && !settled) {
          controller.add(MediaDownload(
            fileId: fileId,
            progress: _progressOf(file),
            downloadedSize: file.local.downloadedSize,
          ));
        }
      } catch (e) {
        await fail(e);
      }
    };

    controller.onCancel = close;

    return controller.stream;
  }

  /// Lowest priority. Feed images should never outrank a sync already in flight.
  static const _priority = 1;
}

extension on MediaUnavailableException {
  MediaUnavailableException withFileId(int fileId) =>
      MediaUnavailableException(fileId, reason);
}

double _progressOf(td.File file) {
  final total = file.size > 0 ? file.size : file.expectedSize;
  if (total <= 0) return 0;
  return (file.local.downloadedSize / total).clamp(0, 1);
}
