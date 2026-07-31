import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/media_cache.dart';
import '../app_scope.dart';

/// Per-file view of the media scheduler.
///
/// The first attempt at fixing stuck images was made blind, which is most of why
/// it took several passes. Every state that can strand a placeholder is visible
/// here: queued but never started, downloading with a byte count that is not
/// moving, retry count, and the terminal reason for a failure.
class MediaDebugScreen extends StatefulWidget {
  const MediaDebugScreen({super.key});

  @override
  State<MediaDebugScreen> createState() => _MediaDebugScreenState();
}

class _MediaDebugScreenState extends State<MediaDebugScreen> {
  Timer? _poll;
  MediaCache? _cache;

  @override
  void initState() {
    super.initState();
    // Polled rather than pushed: the cache holds one notifier per file, and a
    // screen that only exists for diagnosis should not make the hot path pay for
    // an aggregate listener.
    _poll = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => setState(() {}),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _cache = AppScope.mediaCacheOf(context));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cache = _cache;
    final snapshot = cache?.snapshot() ?? const <String, MediaState>{};

    // Problems first: failures, then things in flight, then the resolved bulk.
    final entries = snapshot.entries.toList()
      ..sort((a, b) {
        final rank = _rank(a.value.status).compareTo(_rank(b.value.status));
        return rank != 0 ? rank : a.key.compareTo(b.key);
      });

    final counts = <MediaStatus, int>{};
    for (final state in snapshot.values) {
      counts[state.status] = (counts[state.status] ?? 0) + 1;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Media scheduler')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'active ${cache?.activeCount ?? 0} / '
                  '${cache?.maxConcurrent ?? 0}   ·   '
                  'queued ${cache?.queuedCount ?? 0}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    for (final status in MediaStatus.values)
                      '${status.name} ${counts[status] ?? 0}',
                  ].join('  ·  '),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'stall ${MediaCache.stallTimeout.inSeconds}s (no new bytes) · '
                  'max ${MediaCache.maxAttempts} attempts',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text('No media requested yet',
                        style: theme.textTheme.bodySmall),
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return _FileRow(
                        fileKey: entry.key,
                        liveFileId: cache?.liveFileId(entry.key),
                        state: entry.value,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

int _rank(MediaStatus status) => switch (status) {
      MediaStatus.failed => 0,
      MediaStatus.downloading => 1,
      MediaStatus.queued => 2,
      MediaStatus.idle => 3,
      MediaStatus.done => 4,
    };

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.fileKey,
    required this.liveFileId,
    required this.state,
  });

  final String fileKey;
  final int? liveFileId;
  final MediaState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      dense: true,
      leading: Icon(_iconFor(state.status), size: 18, color: _colorFor(state.status, theme)),
      title: Text(
        'file ${liveFileId ?? '?'} · ${state.status.name}'
        '${state.repaired ? ' · id repaired' : ''}',
        style: theme.textTheme.bodySmall,
      ),
      subtitle: Text(
        [
          if (state.attempts > 0) 'attempt ${state.attempts}',
          if (state.downloadedSize > 0) '${_bytes(state.downloadedSize)} on disk',
          if (state.status == MediaStatus.downloading)
            '${(state.progress * 100).toStringAsFixed(0)}%',
          if (state.path != null) state.path!.split('/').last,
          if (state.error != null) '${state.error}',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall,
      ),
      trailing: state.status == MediaStatus.failed && liveFileId != null
          ? IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: 'Retry',
              onPressed: () => AppScope.mediaCacheOf(context).retry(
                MediaRef(
                  fileId: liveFileId!,
                  remoteId: fileKey.startsWith('local:') ? null : fileKey,
                ),
              ),
            )
          : null,
    );
  }
}

IconData _iconFor(MediaStatus status) => switch (status) {
      MediaStatus.idle => Icons.circle_outlined,
      MediaStatus.queued => Icons.schedule,
      MediaStatus.downloading => Icons.downloading,
      MediaStatus.done => Icons.check_circle_outline,
      MediaStatus.failed => Icons.error_outline,
    };

Color _colorFor(MediaStatus status, ThemeData theme) => switch (status) {
      MediaStatus.failed => theme.colorScheme.error,
      MediaStatus.done => theme.colorScheme.primary,
      _ => theme.colorScheme.onSurfaceVariant,
    };

String _bytes(int value) {
  if (value >= 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (value >= 1024) return '${(value / 1024).toStringAsFixed(0)} KB';
  return '$value B';
}
