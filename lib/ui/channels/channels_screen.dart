import 'package:flutter/material.dart';

import '../../config/seed_channels.dart';
import '../../data/app_database.dart';
import '../../data/channel_repository.dart';
import '../app_scope.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets/open_container_navigation.dart';
import '../widgets/tappable.dart';
import 'channel_feed_screen.dart';

/// Tracked channels: the ones the account follows, plus any added by username.
///
/// This is the seed list the whole feed grows from. There is no way to enumerate
/// or crawl public channels on the Telegram API, so it is always started by hand
/// and grown via the forward graph in Phase 7.
class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  final _usernameController = TextEditingController();

  var _syncing = false;
  var _adding = false;
  var _seeding = false;
  String? _notice;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  ChannelRepository get _repository => AppScope.channelsOf(context);

  Future<void> _syncSubscribed() async {
    setState(() {
      _syncing = true;
      _notice = null;
    });
    try {
      final count = await _repository.syncSubscribedChannels();
      if (!mounted) return;
      setState(() => _notice = 'Synced $count subscribed channels.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _notice = 'Sync failed: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  /// Registers everything in [seedChannels], then pulls their recent posts.
  Future<void> _addSeeds() async {
    final channels = _repository;
    final messages = AppScope.messagesOf(context);

    setState(() {
      _seeding = true;
      _notice = 'Resolving ${seedChannels.length} seed channels…';
    });

    try {
      final results = await channels.addSeedChannels(
        onProgress: (done, total) {
          if (mounted) {
            setState(() => _notice = 'Resolving seed channel $done of $total…');
          }
        },
      );

      final added = results.whereType<ChannelAdded>().toList();
      final failed = results.whereType<ChannelAddFailed>().toList();

      if (added.isNotEmpty) {
        // Guarded per channel — a seed that resolves can still be unreadable.
        await messages.backfillChannels(
          [for (final result in added) result.channel.id],
          perChannel: 40,
          onProgress: (done, total) {
            if (mounted) {
              setState(() => _notice = 'Pulling posts $done of $total…');
            }
          },
        );
      }

      if (!mounted) return;
      setState(() => _notice = [
            'Added ${added.length} of ${results.length}.',
            if (failed.isNotEmpty)
              'Skipped: ${failed.map((f) => f.input).join(', ')}',
          ].join(' '));
    } catch (e) {
      if (mounted) setState(() => _notice = 'Seeding failed: $e');
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  Future<void> _addCurated() async {
    final input = _usernameController.text;
    if (input.trim().isEmpty) return;

    setState(() {
      _adding = true;
      _notice = null;
    });

    final result = await _repository.addCuratedChannel(input);
    if (!mounted) return;

    setState(() {
      _adding = false;
      _notice = switch (result) {
        ChannelAdded(:final channel) => 'Added ${channel.title}.',
        ChannelAddFailed(:final reason) => reason,
      };
      if (result is ChannelAdded) _usernameController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Channels'),
        actions: [
          IconButton(
            icon: _seeding
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.playlist_add),
            tooltip: 'Add seed channels (lib/config/seed_channels.dart)',
            onPressed: _seeding ? null : _addSeeds,
          ),
          IconButton(
            icon: _syncing
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sync subscribed',
            onPressed: _syncing ? null : _syncSubscribed,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  // M3 SearchBar rather than a bordered TextField: this is a
                  // lookup, and the pill shape is what Android users expect for
                  // one.
                  child: SearchBar(
                    controller: _usernameController,
                    hintText: 'Add a public channel',
                    leading: const Icon(Icons.alternate_email),
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onSubmitted: (_) => _addCurated(),
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: FilledButton(
                    onPressed: _adding ? null : _addCurated,
                    child: _adding
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Add'),
                  ),
                ),
              ],
            ),
          ),
          // Grows in place. Seeding emits a new notice every second or two, and
          // a widget appearing and disappearing under the search bar makes the
          // whole list jump each time.
          AnimatedExpanded(
            expand: _notice != null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: AnimatedSizeSwitcher(
                child: Text(
                  _notice ?? '',
                  key: ValueKey(_notice),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<List<TrackedChannel>>(
              stream: _repository.watchChannels(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Database error: ${snapshot.error}'));
                }
                final channels = snapshot.data;
                if (channels == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (channels.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No channels yet.\n\nSync your subscriptions, or add a '
                        'public channel by username.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: channels.length,
                  itemBuilder: (context, index) => _ChannelTile(
                    tracked: channels[index],
                    onToggle: (list, member) => member
                        ? _repository.addToList(
                            channels[index].channel.id, list)
                        : _repository.removeFromList(
                            channels[index].channel.id, list),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One channel, with a toggle per list.
///
/// The full two-input management screen is Phase 8; these toggles exist now so
/// membership is actually reachable and the Phase 1 checkpoint is verifiable
/// rather than only true in the database.
class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.tracked, required this.onToggle});

  final TrackedChannel tracked;
  final void Function(ChannelList list, bool member) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channel = tracked.channel;

    // Same transition as the feed's post header: the row grows into the profile.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: OpenContainerNavigation(
        borderRadius: Shapes.card,
        closedColor: containerColor(context),
        openPage: ChannelFeedScreen(channel: channel),
        button: (open) => Tappable(
          onTap: open,
          borderRadius: Shapes.card,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.title.isEmpty ? 'Untitled' : channel.title,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (channel.username != null) channel.username!,
                    '${_compact(channel.subscriberCount)} subscribers',
                    // Provenance, not membership — worth distinguishing at a
                    // glance.
                    if (channel.source == ChannelSource.subscribed)
                      'subscribed',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final list in ChannelList.values)
                      FilterChip(
                        label: Text(_labelFor(list)),
                        labelStyle: theme.textTheme.labelSmall,
                        selected: tracked.inList(list),
                        onSelected: (value) => onToggle(list, value),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                    if (tracked.isOrphan)
                      Chip(
                        avatar: const Icon(Icons.inventory_2_outlined, size: 14),
                        label: const Text('cached only'),
                        labelStyle: theme.textTheme.labelSmall,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _labelFor(ChannelList list) => switch (list) {
      ChannelList.following => 'Following',
      ChannelList.forYou => 'For You',
    };

String _compact(int count) {
  if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
  if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
  return '$count';
}
