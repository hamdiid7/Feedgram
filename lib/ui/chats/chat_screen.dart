import 'package:flutter/material.dart';

import '../../data/chat_repository.dart';
import '../app_scope.dart';
import '../feed/post_text.dart';
import '../theme.dart';

/// One conversation: history, and a box to reply.
///
/// Always writable. The list this is opened from is private chats only, so there
/// is no read-only case left to handle — a channel can no longer arrive here.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chat});

  final ChatSummary chat;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  List<ChatMessage>? _messages;
  Object? _error;
  var _started = false;
  var _sending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load(markRead: true);
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool markRead = false}) async {
    final chats = AppScope.chatsOf(context);
    try {
      final messages = await chats.history(widget.chat.id);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _error = null;
      });

      if (markRead && messages.isNotEmpty) {
        await chats.markRead(widget.chat.id, [for (final m in messages) m.id]);
      }
      _jumpToLatest();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// A conversation opens at the newest message, not the oldest.
  void _jumpToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await AppScope.chatsOf(context).send(widget.chat.id, text);
      // Cleared only once it is away, so a refusal does not eat what was typed.
      _composer.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.chat.title.isEmpty ? 'Untitled' : widget.chat.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _body(context)),
          _Composer(
            controller: _composer,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    final messages = _messages;
    final error = _error;

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            'Could not load this chat.\n\n$error',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    if (messages == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (messages.isEmpty) {
      return Center(
        child: Text('No messages yet.', style: theme.textTheme.bodyMedium),
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      itemCount: messages.length,
      itemBuilder: (context, index) => _Bubble(message: messages[index]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = message.isOutgoing;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        // Capped, so a long message still reads as a bubble rather than a
        // full-width block indistinguishable from the other side's.
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine
              ? theme.colorScheme.primaryContainer
              : containerColor(context),
          // Square off the corner nearest the sender, which is what makes the
          // two sides distinguishable at a glance without reading them.
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(Shapes.card),
            topRight: const Radius.circular(Shapes.card),
            bottomLeft: Radius.circular(mine ? Shapes.card : 4),
            bottomRight: Radius.circular(mine ? 4 : Shapes.card),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.fields.text.isNotEmpty)
              PostText(
                cacheKey: 'chat:${message.id}',
                spansJson: message.fields.spansJson,
                fallbackText: message.fields.text,
              )
            else
              Text(
                _mediaLabel(message),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 3),
            Text(
              _clockTime(message.date),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        // Clears the keyboard when up, the gesture bar when not.
        8 +
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Message…',
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

String _mediaLabel(ChatMessage message) => switch (message.fields.kind.name) {
      'photo' => 'Photo',
      'video' => 'Video',
      'animation' => 'GIF',
      'document' => 'File',
      'audio' => 'Audio',
      'voice' => 'Voice message',
      'poll' => 'Poll',
      _ => 'Unsupported message',
    };

String _clockTime(int unixSeconds) {
  final date = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  return '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}
