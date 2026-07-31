import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feedgram/data/media_cache.dart';
import 'package:feedgram/data/media_repository.dart';

/// Stands in for TDLib so download behaviour — including transfers that go quiet,
/// fail, or arrive already complete — can be driven deterministically.
class FakeMediaRepository implements MediaRepository {
  final started = <int>[];
  final cancelled = <int>[];
  final _controllers = <int, StreamController<MediaDownload>>{};

  @override
  Stream<MediaDownload> download(int fileId) {
    started.add(fileId);
    final controller = StreamController<MediaDownload>();
    _controllers[fileId] = controller;
    return controller.stream;
  }

  @override
  Future<void> cancelPending(int fileId) async {
    cancelled.add(fileId);
  }

  /// Remote-id lookups, and what each resolves to. `null` means unresolvable.
  final resolveCalls = <String>[];
  final Map<String, int?> remoteResolutions = {};

  @override
  Future<int?> resolveRemote(String remoteId) async {
    resolveCalls.add(remoteId);
    return remoteResolutions[remoteId];
  }

  /// Reports bytes on disk. The scheduler treats *increasing* bytes as liveness.
  void bytes(int fileId, int downloadedSize, {double progress = 0.5}) {
    _controllers[fileId]?.add(MediaDownload(
      fileId: fileId,
      progress: progress,
      downloadedSize: downloadedSize,
    ));
  }

  void complete(int fileId) {
    final controller = _controllers[fileId];
    if (controller == null) return;
    controller.add(MediaDownload(
      fileId: fileId,
      localPath: '/tmp/$fileId.jpg',
      progress: 1,
    ));
    controller.close();
  }

  void fail(int fileId, Object error) {
    final controller = _controllers[fileId];
    if (controller == null) return;
    controller.addError(error);
    controller.close();
  }

  /// Stream ends with no file — the silent-drop case.
  void endWithoutFile(int fileId) => _controllers[fileId]?.close();

  bool isOpen(int fileId) {
    final controller = _controllers[fileId];
    return controller != null && !controller.isClosed;
  }
}

/// Lets the cache's stream listeners run. Stream events are delivered in a
/// microtask, so asserting immediately after emitting one sees stale state.
Future<void> settle() => Future<void>.delayed(Duration.zero);

/// A plain local-only reference, which is what most of these tests care about.
MediaRef ref(int fileId, {String? remoteId}) =>
    MediaRef(fileId: fileId, remoteId: remoteId);

void main() {
  group('dedup and concurrency', () {
    test('one download per file however many times it is requested', () {
      final repo = FakeMediaRepository();
      final cache = MediaCache(repository: repo);
      addTearDown(cache.dispose);

      cache.request(ref(7));
      cache.request(ref(7));
      cache.request(ref(7));

      expect(repo.started, [7]);
    });

    test('never exceeds maxConcurrent', () async {
      final repo = FakeMediaRepository();
      final cache = MediaCache(repository: repo, maxConcurrent: 2);
      addTearDown(cache.dispose);

      for (var id = 1; id <= 6; id++) {
        cache.request(ref(id));
      }
      expect(repo.started, hasLength(2));
      expect(cache.queuedCount, 4);

      repo.complete(repo.started.last);
      await settle();
      expect(repo.started, hasLength(3), reason: 'a freed slot starts the next');
    });

    test('a completed file resolves and never downloads again', () async {
      final repo = FakeMediaRepository();
      final cache = MediaCache(repository: repo);
      addTearDown(cache.dispose);

      cache.request(ref(1));
      repo.complete(1);
      await settle();

      expect(cache.stateOf(ref(1)).value.isDone, isTrue);
      expect(cache.stateOf(ref(1)).value.path, '/tmp/1.jpg');

      cache.request(ref(1));
      expect(repo.started, [1], reason: 'already done, so no second request');
    });
  });

  group('stall detection is byte-based, not clock-based', () {
    test('a slow but progressing transfer is never reclaimed', () {
      fakeAsync((async) {
        final repo = FakeMediaRepository();
        final cache = MediaCache(repository: repo);
        addTearDown(cache.dispose);

        cache.request(ref(1));

        // Far longer than the stall timeout in total, but bytes keep arriving.
        // The old wall-clock version killed exactly this case.
        for (var i = 1; i <= 6; i++) {
          async.elapse(const Duration(seconds: 30));
          repo.bytes(1, i * 1000);
          async.flushMicrotasks();
        }

        expect(cache.stateOf(ref(1)).value.status, MediaStatus.downloading);
        expect(cache.stateOf(ref(1)).value.attempts, 1,
            reason: 'no retry should have been needed');
      });
    });

    test('repeated updates at the same byte count still count as stalled', () {
      fakeAsync((async) {
        final repo = FakeMediaRepository();
        final cache = MediaCache(repository: repo);
        addTearDown(cache.dispose);

        cache.request(ref(1));
        repo.bytes(1, 5000);
        async.flushMicrotasks();

        // Chatty but not moving — the transfer is dead and must be treated so.
        for (var i = 0; i < 5; i++) {
          async.elapse(const Duration(seconds: 10));
          repo.bytes(1, 5000);
          async.flushMicrotasks();
        }

        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();

        expect(cache.stateOf(ref(1)).value.attempts, greaterThan(1),
            reason: 'a stalled transfer must be retried');
      });
    });

    test('a reclaimed slot is always freed for the next file', () {
      fakeAsync((async) {
        final repo = FakeMediaRepository();
        final cache = MediaCache(repository: repo, maxConcurrent: 1);
        addTearDown(cache.dispose);

        cache.request(ref(1));
        cache.request(ref(2));
        expect(repo.started, [1]);

        async.elapse(MediaCache.stallTimeout + const Duration(seconds: 1));
        async.flushMicrotasks();

        // The whole point: reclaiming must hand the slot on, not leak it.
        expect(repo.started, contains(2));
      });
    });
  });

  group('retry and terminal failure', () {
    test('retries with backoff, then fails terminally', () {
      fakeAsync((async) {
        final repo = FakeMediaRepository();
        final cache = MediaCache(repository: repo);
        addTearDown(cache.dispose);

        cache.request(ref(1));
        for (var attempt = 0; attempt < MediaCache.maxAttempts; attempt++) {
          repo.fail(1, StateError('boom'));
          async.elapse(const Duration(seconds: 30));
          async.flushMicrotasks();
        }

        final state = cache.stateOf(ref(1)).value;
        expect(state.status, MediaStatus.failed);
        expect(state.attempts, MediaCache.maxAttempts);
        // A placeholder that never resolves must become an explicit error.
        expect(state.isFailed, isTrue);
      });
    });

    test('an unavailable file fails at once without spending retries', () {
      fakeAsync((async) {
        final repo = FakeMediaRepository();
        final cache = MediaCache(repository: repo);
        addTearDown(cache.dispose);

        cache.request(ref(1));
        repo.fail(1, const MediaUnavailableException(1, 'cannot be downloaded'));
        async.elapse(const Duration(minutes: 1));
        async.flushMicrotasks();

        expect(cache.stateOf(ref(1)).value.status, MediaStatus.failed);
        expect(repo.started, [1], reason: 'retrying this is pure waste');
      });
    });

    test('a stream that ends with no file is not silently dropped', () {
      fakeAsync((async) {
        final repo = FakeMediaRepository();
        final cache = MediaCache(repository: repo);
        addTearDown(cache.dispose);

        cache.request(ref(1));
        repo.endWithoutFile(1);
        async.flushMicrotasks();

        // Either retried or failed — never left sitting in `downloading`.
        expect(cache.stateOf(ref(1)).value.status,
            isNot(MediaStatus.downloading));
      });
    });

    test('a failed file is not auto-requested again on rebuild', () {
      fakeAsync((async) {
        final repo = FakeMediaRepository();
        final cache = MediaCache(repository: repo);
        addTearDown(cache.dispose);

        cache.request(ref(1));
        repo.fail(1, const MediaUnavailableException(1, 'gone'));
        async.flushMicrotasks();

        // Every scroll rebuilds the card; hammering a dead file would be a loop.
        cache.request(ref(1));
        cache.request(ref(1));
        expect(repo.started, [1]);
      });
    });

    test('explicit retry clears the terminal state and starts over', () {
      fakeAsync((async) {
        final repo = FakeMediaRepository();
        final cache = MediaCache(repository: repo);
        addTearDown(cache.dispose);

        cache.request(ref(1));
        repo.fail(1, const MediaUnavailableException(1, 'gone'));
        async.flushMicrotasks();
        expect(cache.stateOf(ref(1)).value.isFailed, isTrue);

        cache.retry(ref(1));
        async.flushMicrotasks();

        expect(repo.started, [1, 1]);
        expect(cache.stateOf(ref(1)).value.attempts, 1, reason: 'counter resets');
      });
    });
  });

  group('queue ordering', () {
    test('newest request is served first', () async {
      final repo = FakeMediaRepository();
      final cache = MediaCache(repository: repo, maxConcurrent: 1);
      addTearDown(cache.dispose);

      cache.request(ref(1));
      cache.request(ref(2));
      cache.request(ref(3));
      repo.complete(1);
      await settle();

      // LIFO: 3 is what just scrolled into view, not 2.
      expect(repo.started, [1, 3]);
    });

    test('an entry left behind by continuous scrolling is promoted', () async {
      final repo = FakeMediaRepository();
      final cache = MediaCache(repository: repo, maxConcurrent: 1);
      addTearDown(cache.dispose);

      // Occupy the only slot, so everything after this queues.
      cache.request(ref(1));
      // The straggler: queued first, therefore oldest.
      cache.request(ref(999));
      // Continuous scrolling piles newer requests on top of it.
      for (var id = 2; id < 40; id++) {
        cache.request(ref(id));
      }

      repo.complete(1);
      await settle();

      // Pure LIFO would serve 39 here and leave 999 waiting forever.
      expect(repo.started[1], 999);
    });

    test('release drops a queued entry but not one in flight', () async {
      final repo = FakeMediaRepository();
      final cache = MediaCache(repository: repo, maxConcurrent: 1);
      addTearDown(cache.dispose);

      cache.request(ref(1));
      cache.request(ref(2));

      cache.release(ref(2));
      expect(cache.queuedCount, 0);
      expect(repo.cancelled, [2]);

      // The in-flight one keeps going: bytes already paid for are worth keeping.
      cache.release(ref(1));
      expect(repo.cancelled, [2]);
    });
  });

  group('stale local ids are repaired via the persistent remote id', () {
    // TDLib local file ids belong to the instance that issued them. Rows written
    // by an earlier run hold dead handles, and `downloadFile` answers
    // "Invalid file identifier" — which presented as a permanent blur on almost
    // every cached post.
    final staleError = Exception('400: Invalid file identifier');

    test('resolves to a live id and downloads that instead', () async {
      final repo = FakeMediaRepository();
      repo.remoteResolutions['abc'] = 9001;
      final cache = MediaCache(repository: repo);
      addTearDown(cache.dispose);

      final subject = ref(5416, remoteId: 'abc');
      cache.request(subject);
      repo.fail(5416, staleError);
      await settle();
      await settle();

      expect(repo.resolveCalls, ['abc']);
      expect(repo.started, [5416, 9001]);
      expect(cache.stateOf(subject).value.repaired, isTrue);
      expect(cache.liveFileId(subject.key), 9001);
    });

    test('the repaired download resolves under the original key', () async {
      final repo = FakeMediaRepository();
      repo.remoteResolutions['abc'] = 9001;
      final cache = MediaCache(repository: repo);
      addTearDown(cache.dispose);

      final subject = ref(5416, remoteId: 'abc');
      cache.request(subject);
      repo.fail(5416, staleError);
      await settle();
      await settle();

      repo.complete(9001);
      await settle();

      // Widgets listen on the key, so the swap must be invisible to them.
      expect(cache.stateOf(subject).value.isDone, isTrue);
      expect(cache.stateOf(subject).value.path, '/tmp/9001.jpg');
    });

    test('fails terminally when the remote id cannot be resolved', () async {
      final repo = FakeMediaRepository();
      repo.remoteResolutions['gone'] = null;
      final cache = MediaCache(repository: repo);
      addTearDown(cache.dispose);

      final subject = ref(5416, remoteId: 'gone');
      cache.request(subject);
      repo.fail(5416, staleError);
      await settle();
      await settle();

      expect(cache.stateOf(subject).value.isFailed, isTrue);
    });

    test('repair is attempted once, not on every retry cycle', () async {
      final repo = FakeMediaRepository();
      repo.remoteResolutions['abc'] = 9001;
      final cache = MediaCache(repository: repo);
      addTearDown(cache.dispose);

      final subject = ref(5416, remoteId: 'abc');
      cache.request(subject);
      repo.fail(5416, staleError);
      await settle();
      await settle();
      // The replacement id is stale too — a resolve loop would be the bug here.
      repo.fail(9001, staleError);
      await settle();
      await settle();

      expect(repo.resolveCalls, ['abc']);
    });

    test('a non-stale error is retried, not resolved', () async {
      final repo = FakeMediaRepository();
      repo.remoteResolutions['abc'] = 9001;
      final cache = MediaCache(repository: repo);
      addTearDown(cache.dispose);

      cache.request(ref(1, remoteId: 'abc'));
      repo.fail(1, StateError('network hiccup'));
      await settle();

      expect(repo.resolveCalls, isEmpty,
          reason: 'a flaky connection is not a dead identifier');
    });

    test('without a remote id there is nothing to repair with', () async {
      final repo = FakeMediaRepository();
      final cache = MediaCache(repository: repo);
      addTearDown(cache.dispose);

      cache.request(ref(5416));
      repo.fail(5416, staleError);
      await settle();

      expect(repo.resolveCalls, isEmpty);
    });
  });

  test('snapshot reports every known file for the debug screen', () async {
    final repo = FakeMediaRepository();
    final cache = MediaCache(repository: repo, maxConcurrent: 1);
    addTearDown(cache.dispose);

    cache.request(ref(1));
    cache.request(ref(2));
    repo.complete(1);
    await settle();

    final snapshot = cache.snapshot();
    expect(snapshot.keys, containsAll(['local:1', 'local:2']));
    expect(snapshot['local:1']!.status, MediaStatus.done);
  });
}
