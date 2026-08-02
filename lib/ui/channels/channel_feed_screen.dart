import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../data/channel_repository.dart';
import '../app_scope.dart';
import '../feed/chronological_feed.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets/collapsing_header.dart';
import '../widgets/pull_to_dismiss.dart';

/// One channel's posts, under a profile header that folds up as you scroll.
///
/// Reuses [ChronologicalFeed] scoped to a single chat rather than reimplementing
/// it — same keyset pagination, same live head, same album grouping, same content
/// filters, same index. Opens with 50 posts and pages 50 more.
class ChannelFeedScreen extends StatefulWidget {
  const ChannelFeedScreen({super.key, required this.channel});

  final Channel channel;

  @override
  State<ChannelFeedScreen> createState() => _ChannelFeedScreenState();
}

class _ChannelFeedScreenState extends State<ChannelFeedScreen> {
  var _pulling = false;
  String? _notice;

  /// Pulls more history for just this channel, so a channel with nothing cached is
  /// one tap from being readable instead of needing a whole-library backfill.
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
      // NestedScrollView, not a CustomScrollView: it lets the header be a sliver
      // while the body stays the ordinary ListView the feed already is. Turning
      // the feed itself into slivers would mean reworking its keyset paging and
      // album buffering for a purely visual change.
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          CollapsingHeader(
            title: channel.title.isEmpty ? 'Untitled' : channel.title,
            // Title only. The avatar row used to live in here as the header's
            // `detail`, which meant the title had to be lifted clear of it by a
            // hand-measured amount — and any mismatch between that number and
            // the row's real height showed up as a stretch of empty space
            // between the two. Room for one large title and nothing else.
            expandedHeight: 112,
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
        ],
        body: Column(
          children: [
            // Sits directly under the title rather than inside the header, so
            // its height is whatever it needs to be instead of a constant the
            // header has to be told about. Pulling down on it goes back.
            PullToDismiss(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
                child: _ProfileDetail(channel: channel),
              ),
            ),
            // Grows and shrinks rather than appearing: this sits directly above
            // the feed, so a hard insert would shove the posts down a line.
            AnimatedExpanded(
              expand: _notice != null,
              child: Container(
                width: double.infinity,
                color: containerColor(context),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: AnimatedSizeSwitcher(
                  child: Text(
                    _notice ?? '',
                    key: ValueKey(_notice),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
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
      ),
    );
  }
}

/// Avatar, handle and subscriber count.
///
/// No membership controls: list membership is managed on the Channels screen,
/// where every channel's chips sit together and can be compared. Duplicating
/// them here bought a second place for the same state to be wrong.
class _ProfileDetail extends StatelessWidget {
  const _ProfileDetail({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channels = AppScope.channelsOf(context);

    return StreamBuilder<List<TrackedChannel>>(
      stream: channels.watchChannels(),
      builder: (context, snapshot) {
        // Watched rather than passed in, so a subscriber count refreshed by a
        // sync shows up without reopening the screen.
        final current = snapshot.data
                ?.where((t) => t.channel.id == channel.id)
                .firstOrNull
                ?.channel ??
            channel;

        return Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                initialsOf(current.title),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                [
                  // No "@", matching the feed cards.
                  if (current.username != null) current.username!,
                  '${compactCount(current.subscriberCount)} subscribers',
                  current.source.name,
                ].join(' · '),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Up to two initials from a channel title, for the placeholder avatar.
///
/// Channel photos are not cached locally, so there is no image to show; initials
/// at least make channels distinguishable at a glance.
String initialsOf(String title) {
  final words = title.trim().split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  return words
      .take(2)
      .map((w) => w.substring(0, 1))
      .join()
      .toUpperCase();
}

String compactCount(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return '$value';
}
