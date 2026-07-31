import 'dart:async';

import 'package:flutter/foundation.dart';

import 'media_repository.dart';

enum MediaStatus { idle, queued, downloading, done, failed }

/// How a caller names a file.
///
/// Two identifiers, because TDLib has two and they behave differently:
/// [fileId] is a local handle that is fast but only valid for the TDLib instance
/// that issued it, while [remoteId] survives restarts. State is keyed on the
/// stable one so that swapping a stale local id for a fresh one is invisible to
/// anything already listening.
@immutable
class MediaRef {
  const MediaRef({required this.fileId, this.remoteId});

  final int fileId;
  final String? remoteId;

  String get key => remoteId ?? 'local:$fileId';

  @override
  bool operator ==(Object other) => other is MediaRef && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

@immutable
class MediaState {
  const MediaState({
    this.status = MediaStatus.idle,
    this.progress = 0,
    this.downloadedSize = 0,
    this.path,
    this.error,
    this.attempts = 0,
    this.repaired = false,
  });

  final MediaStatus status;
  final double progress;
  final int downloadedSize;
  final String? path;
  final Object? error;

  /// Download attempts spent. Surfaced so the debug screen can explain a pending
  /// file rather than just showing a spinner.
  final int attempts;

  /// A stale local id was recovered through the persistent remote id.
  final bool repaired;

  bool get isDone => status == MediaStatus.done && path != null;

  /// Terminal failure. The UI must offer an explicit retry — a blur placeholder
  /// that will never resolve is indistinguishable from a bug.
  bool get isFailed => status == MediaStatus.failed;

  MediaState copyWith({
    MediaStatus? status,
    double? progress,
    int? downloadedSize,
    String? path,
    Object? error,
    int? attempts,
    bool? repaired,
  }) {
    return MediaState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadedSize: downloadedSize ?? this.downloadedSize,
      path: path ?? this.path,
      error: error ?? this.error,
      attempts: attempts ?? this.attempts,
      repaired: repaired ?? this.repaired,
    );
  }
}

/// Shared, bounded download scheduler for feed media.
///
/// A scrolling feed asks for the same file repeatedly and for far more files than
/// should ever be in flight, so this is the one place that decides what is
/// actually being fetched:
///
/// * **Shared per file** — many rebuilds for one post issue one download.
/// * **Bounded concurrency** — flicking through a hundred cards must not open a
///   hundred transfers. That is a bandwidth problem and the pattern that earns
///   FLOOD_WAIT.
/// * **LIFO with ageing** — newest first, because that is what just scrolled into
///   view; but anything waiting too long is promoted, or continuous scrolling
///   starves it forever.
/// * **Stale local ids are repaired**, not failed, via the persistent remote id.
/// * **Every path is terminal.** A file resolves or ends [MediaStatus.failed]
///   with a reason. Nothing sits pending indefinitely.
class MediaCache {
  MediaCache({required MediaRepository repository, this.maxConcurrent = 5})
      : _repository = repository;

  final MediaRepository _repository;

  /// Concurrent transfers. Higher than the original 3: photos are small and a
  /// feed scrolls faster than three-at-a-time keeps up with, while still staying
  /// well clear of rate limiting.
  final int maxConcurrent;

  /// How long a transfer may go **without new bytes** before its slot is
  /// reclaimed. Measured against `downloadedSize`, not elapsed time — the old
  /// wall-clock version killed large-but-healthy transfers on mobile data.
  static const stallTimeout = Duration(seconds: 45);

  static const maxAttempts = 3;

  static const _backoff = [
    Duration(seconds: 1),
    Duration(seconds: 4),
    Duration(seconds: 10),
  ];

  /// Roughly "older than the last N requests". Measured in enqueue events rather
  /// than seconds, which makes the ageing rule testable without a clock.
  static const promotionWindow = 24;

  final _states = <String, ValueNotifier<MediaState>>{};
  final _refs = <String, MediaRef>{};

  /// Local id currently in use for a key — replaced when a stale one is repaired.
  final _liveFileIds = <String, int>{};

  final _queue = <_QueueEntry>[];
  final _active = <String>{};
  final _subscriptions = <String, StreamSubscription<MediaDownload>>{};
  final _watchdogs = <String, Timer>{};
  final _retryTimers = <String, Timer>{};
  final _lastBytes = <String, int>{};
  final _repairAttempted = <String>{};

  var _sequence = 0;

  ValueListenable<MediaState> stateOf(MediaRef ref) => _ensure(ref.key);

  ValueNotifier<MediaState> _ensure(String key) =>
      _states.putIfAbsent(key, () => ValueNotifier(const MediaState()));

  /// Snapshot for the debug screen.
  Map<String, MediaState> snapshot() =>
      {for (final entry in _states.entries) entry.key: entry.value.value};

  int? liveFileId(String key) => _liveFileIds[key];

  int get activeCount => _active.length;
  int get queuedCount => _queue.length;

  /// Idempotent for anything already queued, downloading or done.
  ///
  /// A [MediaStatus.failed] file is deliberately **not** retried automatically —
  /// that is what tap-to-retry is for. Re-requesting on every rebuild would
  /// hammer a file that is genuinely unavailable.
  void request(MediaRef ref) {
    final notifier = _ensure(ref.key);
    _refs[ref.key] = ref;
    _liveFileIds.putIfAbsent(ref.key, () => ref.fileId);

    switch (notifier.value.status) {
      case MediaStatus.done:
      case MediaStatus.queued:
      case MediaStatus.downloading:
      case MediaStatus.failed:
        return;
      case MediaStatus.idle:
        break;
    }
    _enqueue(ref.key);
  }

  /// Explicit user retry: clears the terminal state and starts over, including
  /// another attempt at repairing a stale id.
  void retry(MediaRef ref) {
    _retryTimers.remove(ref.key)?.cancel();
    _repairAttempted.remove(ref.key);
    _refs[ref.key] = ref;
    _liveFileIds[ref.key] = ref.fileId;
    _states[ref.key]?.value = const MediaState(status: MediaStatus.queued);
    _enqueue(ref.key, resetAttempts: true);
  }

  void _enqueue(String key, {bool resetAttempts = false}) {
    final notifier = _ensure(key);
    notifier.value = notifier.value.copyWith(
      status: MediaStatus.queued,
      attempts: resetAttempts ? 0 : notifier.value.attempts,
    );
    _queue
      ..removeWhere((e) => e.key == key)
      ..add(_QueueEntry(key, _sequence++));
    _pump();
  }

  /// Called when a card leaves the tree.
  ///
  /// Only drops still-queued work; an in-flight download finishes, because bytes
  /// already paid for are worth keeping if the user scrolls back.
  void release(MediaRef ref) {
    final before = _queue.length;
    _queue.removeWhere((e) => e.key == ref.key);
    if (_queue.length == before) return;

    final notifier = _states[ref.key];
    if (notifier != null && notifier.value.status == MediaStatus.queued) {
      notifier.value = notifier.value.copyWith(status: MediaStatus.idle);
    }
    _repository.cancelPending(_liveFileIds[ref.key] ?? ref.fileId);
  }

  void _pump() {
    while (_active.length < maxConcurrent && _queue.isNotEmpty) {
      _start(_takeNext());
    }
  }

  /// LIFO, except anything waiting longer than [promotionWindow] goes first.
  ///
  /// Without the ageing rule a user who keeps scrolling permanently outbids the
  /// entries behind them, and those images never load at all.
  String _takeNext() {
    final cutoff = _sequence - promotionWindow;
    final aged = _queue.indexWhere((e) => e.sequence < cutoff);
    final index = aged >= 0 ? aged : _queue.length - 1;
    return _queue.removeAt(index).key;
  }

  void _start(String key) {
    final notifier = _ensure(key);
    final fileId = _liveFileIds[key];
    if (fileId == null) return;

    _active.add(key);
    _lastBytes[key] = notifier.value.downloadedSize;
    notifier.value = notifier.value.copyWith(
      status: MediaStatus.downloading,
      attempts: notifier.value.attempts + 1,
    );
    _armWatchdog(key);

    _subscriptions[key] = _repository.download(fileId).listen(
      (download) {
        if (download.isComplete) {
          notifier.value = notifier.value.copyWith(
            status: MediaStatus.done,
            progress: 1,
            downloadedSize: download.downloadedSize,
            path: download.localPath,
          );
          _finish(key);
          return;
        }

        notifier.value = notifier.value.copyWith(
          progress: download.progress,
          downloadedSize: download.downloadedSize,
        );

        // Only *new bytes* count as alive. Repeated updates at the same size mean
        // the transfer is not moving.
        if (download.downloadedSize > (_lastBytes[key] ?? 0)) {
          _lastBytes[key] = download.downloadedSize;
          _armWatchdog(key);
        }
      },
      onError: (Object error) => _handleFailure(key, error),
      onDone: () {
        if (_active.contains(key)) {
          _handleFailure(key, StateError('download ended without a file'));
        }
      },
    );
  }

  void _armWatchdog(String key) {
    _watchdogs[key]?.cancel();
    _watchdogs[key] = Timer(stallTimeout, () {
      if (!_active.contains(key)) return;
      _handleFailure(
        key,
        StateError('no progress for ${stallTimeout.inSeconds}s'),
      );
    });
  }

  /// Frees the slot, then repairs, retries, or fails terminally.
  ///
  /// Reclaiming a slot is *always* paired with one of those three. The earlier
  /// version could reclaim without re-queueing, which is exactly how a
  /// placeholder became permanent.
  void _handleFailure(String key, Object error) {
    final notifier = _ensure(key);
    _finish(key);

    final remoteId = _refs[key]?.remoteId;
    if (remoteId != null &&
        !_repairAttempted.contains(key) &&
        _looksStale(error)) {
      _repairAttempted.add(key);
      _repository.resolveRemote(remoteId).then((live) {
        if (live == null) {
          notifier.value = notifier.value.copyWith(
            status: MediaStatus.failed,
            error: error,
          );
          return;
        }
        // Same key, new local handle — nothing listening has to know.
        _liveFileIds[key] = live;
        notifier.value = notifier.value.copyWith(repaired: true, attempts: 0);
        _enqueue(key);
      });
      return;
    }

    // Nothing will ever arrive for an unavailable file, so do not spend retries.
    if (error is MediaUnavailableException ||
        notifier.value.attempts >= maxAttempts) {
      notifier.value = notifier.value.copyWith(
        status: MediaStatus.failed,
        error: error,
      );
      return;
    }

    notifier.value = notifier.value.copyWith(status: MediaStatus.idle);
    final delay =
        _backoff[(notifier.value.attempts - 1).clamp(0, _backoff.length - 1)];
    _retryTimers[key] = Timer(delay, () {
      _retryTimers.remove(key);
      if (_states[key]?.value.status == MediaStatus.idle) _enqueue(key);
    });
  }

  void _finish(String key) {
    _watchdogs.remove(key)?.cancel();
    _active.remove(key);
    _lastBytes.remove(key);
    _subscriptions.remove(key)?.cancel();
    _pump();
  }

  void dispose() {
    for (final timer in [..._watchdogs.values, ..._retryTimers.values]) {
      timer.cancel();
    }
    _watchdogs.clear();
    _retryTimers.clear();
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
    for (final notifier in _states.values) {
      notifier.dispose();
    }
    _states.clear();
    _queue.clear();
    _active.clear();
    _lastBytes.clear();
    _refs.clear();
    _liveFileIds.clear();
    _repairAttempted.clear();
  }
}

/// A stale local id, as opposed to a transient network problem.
///
/// TDLib reports it as a 400 on `downloadFile`; matching on the message is ugly
/// but it is the only signal available, and getting it wrong only costs one extra
/// `getRemoteFile` lookup.
bool _looksStale(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('invalid file identifier') ||
      text.contains('file_id_invalid');
}

class _QueueEntry {
  const _QueueEntry(this.key, this.sequence);

  final String key;
  final int sequence;
}
