import 'package:flutter/material.dart';

import '../../data/message_repository.dart';
import '../../domain/feed_grouping.dart';
import '../app_scope.dart';
import '../motion.dart';
import '../theme.dart';
import 'post_card.dart';
import 'post_text.dart';

/// One post, its comments, and a box to add one.
///
/// Comments come from the channel's linked discussion group — Telegram has no
/// comment primitive of its own, only a group whose thread mirrors the post.
class PostScreen extends StatefulWidget {
  const PostScreen({super.key, required this.item});

  final FeedItem item;

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  List<ThreadComment>? _comments;
  Object? _error;
  var _started = false;
  var _sending = false;

  int get _chatId => widget.item.lead.message.chatId;
  int get _messageId => widget.item.lead.message.messageId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // A post with no replies has no thread at all, and asking for the history of
    // one answers `500: Receive messages in an unexpected chat`. Skipping the
    // call turns a raw TDLib error into the empty state it actually means, and
    // saves a round trip on the commonest case.
    if (widget.item.lead.message.replyCount == 0 && _comments == null) {
      setState(() => _comments = const []);
      return;
    }

    try {
      final comments =
          await AppScope.messagesOf(context).threadComments(_chatId, _messageId);
      if (mounted) {
        setState(() {
          _comments = comments;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await AppScope.messagesOf(context).sendComment(_chatId, _messageId, text);
      // Cleared only after the send succeeds. Wiping it first would lose what
      // was typed the moment the network refuses it.
      _composer.clear();
      await _load();
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: Motion.fade,
          curve: Motion.standard,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not post: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final replies = widget.item.lead.message.replyCount;

    return Scaffold(
      appBar: AppBar(
        title: Text(replies == 1 ? '1 comment' : '$replies comments'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                // The post itself, with its own header not linking anywhere:
                // you arrived here from that card, so offering to open it again
                // is a loop.
                PostCard(item: widget.item, linkChannel: false, openable: false),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 6, 22, 8),
                  child: Text(
                    'Comments',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                _commentList(context),
              ],
            ),
          ),
          _Composer(
            controller: _composer,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _commentList(BuildContext context) {
    final theme = Theme.of(context);
    final comments = _comments;
    final error = _error;

    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        child: Text(
          'Could not load comments.\n\n$error',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    if (comments == null) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (comments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Column(
            children: [
              ScaleIn(
                child: Icon(
                  Icons.mode_comment_outlined,
                  size: 36,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Text('No comments yet.', style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final comment in comments)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              // A shade off the page rather than a divider: comments run from a
              // word to a paragraph, and rules between them make short ones read
              // as table rows.
              color: containerColor(context),
              borderRadius: BorderRadius.circular(Shapes.row),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: PostText(
                cacheKey: 'thread:$_chatId:${comment.messageId}',
                spansJson: comment.fields.spansJson,
                fallbackText: comment.fields.text,
              ),
            ),
          ),
      ],
    );
  }
}

/// The comment box, pinned above the keyboard.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.surface,
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        // Clears the keyboard when it is up and the gesture bar when it is not.
        8 + MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              // Grows with the comment instead of scrolling a one-line box, but
              // stops before it eats the thread it belongs to.
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: 'Write a comment…',
                filled: true,
                fillColor: containerColor(context),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Shapes.pill),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Disabled while in flight rather than hidden: a send button that
          // vanishes mid-post reads as the app having lost the comment.
          IconButton.filled(
            onPressed: sending ? null : onSend,
            icon: sending
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}
