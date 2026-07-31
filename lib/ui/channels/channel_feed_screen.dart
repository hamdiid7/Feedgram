import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../app_scope.dart';
import '../feed/chronological_feed.dart';

/// One channel's posts.
///
/// Reuses [ChronologicalFeed] scoped to a single chat rather than reimplementing
/// same keyset pagination, same live head, same album grouping, same index.
class ChannelFeedScreen extends StatefulWidget {
  const ChannelFeedScreen({super.key, required this.channel});

  final Channel channel;

  @override
  State<ChannelFeedScreen> createState() => _ChannelFeedScreenState();
}

class _ChannelFeedScreenState extends State<ChannelFeedScreen> {
  var _pulling = false;
  String? _notice;

  /// Pulls more history for just this channel, so a channel with nothing cached
  /// is one tap from being readable instead of needing a whole-library backfill.
  Future<void> _pull() async {
    final messages = AppScope.messagesOf(context);

    setState(() {
      _pulling = true;
      _notice = 'Pulling posts…';
    });

    try {
      final count = await messages.backfillChannel(
        widget.channel.id,
        target: 100,
      );
      if (mounted) setState(() => _notice = 'Pulled $count posts.');
    } catch (e) {
      if (mounted) setState(() => _notice = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _pulling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              channel.title.isEmpty ? 'Untitled' : channel.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              [
                if (channel.username != null) '@${channel.username}',
                channel.source.name,
              ].join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _pulling
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            tooltip: 'Pull more posts',
            onPressed: _pulling ? null : _pull,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_notice != null)
            Container(
              width: double.infinity,
              color: theme.colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(_notice!, style: theme.textTheme.bodySmall),
            ),
          Expanded(
            child: ChronologicalFeed(
              chatId: channel.id,
              emptyMessage: 'No posts cached for this channel yet.\n\n'
                  'Tap the download button to pull its history.',
            ),
          ),
        ],
      ),
    );
  }
}
