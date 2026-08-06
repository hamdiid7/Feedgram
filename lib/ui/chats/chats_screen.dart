import 'package:flutter/material.dart';

import '../../data/chat_repository.dart';
import '../app_scope.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets/floating_nav_bar.dart';
import '../widgets/open_container_navigation.dart';
import '../widgets/tappable.dart';
import 'chat_screen.dart';

/// The chats list.
///
/// Read straight from TDLib rather than the feed database: a chat list is a live
/// ordering that Telegram maintains for you, and mirroring it into SQLite would
/// mean owning that ordering — and getting it wrong the moment a message arrives
/// while the app is closed.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<ChatSummary>? _chats;
  Object? _error;
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final chats = await AppScope.chatsOf(context).chats();
      if (mounted) {
        setState(() {
          _chats = chats;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final theme = Theme.of(context);
    final chats = _chats;
    final error = _error;

    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: switch ((chats, error)) {
          (_, final Object e) => _Filler(
              icon: Icons.error_outline,
              text: 'Could not load chats.\n\n$e',
            ),
          (null, _) => const Center(child: CircularProgressIndicator()),
          (final list, _) when list!.isEmpty => const _Filler(
              icon: Icons.forum_outlined,
              text: 'No chats yet.',
            ),
          (final list, _) => ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              // Clears the floating nav bar, so the last chat is reachable.
              padding: EdgeInsets.only(
                top: 4,
                bottom: FloatingNavBar.spaceFor(context),
              ),
              itemCount: list!.length,
              itemBuilder: (context, index) => FeedItemEntrance(
                key: ValueKey(list[index].id),
                index: index,
                child: _ChatRow(chat: list[index], onReturn: _load),
              ),
            ),
        },
      ),
      backgroundColor: theme.colorScheme.surface,
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.chat, required this.onReturn});

  final ChatSummary chat;

  /// Re-reads the list on the way back, so a message just sent shows as the new
  /// preview and the unread badge clears.
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: OpenContainerNavigation(
        borderRadius: Shapes.card,
        closedColor: containerColor(context),
        openPage: ChatScreen(chat: chat),
        onClosed: onReturn,
        button: (open) => Tappable(
          onTap: open,
          borderRadius: Shapes.card,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    _initials(chat.title),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              chat.title.isEmpty ? 'Untitled' : chat.title,
                              style: theme.textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (chat.lastMessageDate > 0)
                            Text(
                              _relativeTime(chat.lastMessageDate),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              chat.lastMessage.isEmpty
                                  ? 'No messages'
                                  : chat.lastMessage,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (chat.unreadCount > 0) ...[
                            const SizedBox(width: 8),
                            // A count, not a dot: with hundreds of channel posts
                            // arriving, "how many" is the only part that helps
                            // you decide whether to open it.
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius:
                                    BorderRadius.circular(Shapes.pill),
                              ),
                              child: Text(
                                chat.unreadCount > 999
                                    ? '999+'
                                    : '${chat.unreadCount}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Filler extends StatelessWidget {
  const _Filler({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Inside a scroll view so pull-to-refresh still works with nothing in it.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.6,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleIn(
                    child: Icon(
                      icon,
                      size: 42,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _initials(String title) {
  final words = title.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return '?';
  return words.take(2).map((w) => w.characters.first).join().toUpperCase();
}

String _relativeTime(int unixSeconds) {
  final date = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  final delta = DateTime.now().difference(date);

  if (delta.inMinutes < 1) return 'now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m';
  if (delta.inHours < 24) return '${delta.inHours}h';
  if (delta.inDays < 7) return '${delta.inDays}d';
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
