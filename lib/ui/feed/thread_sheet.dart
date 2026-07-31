import 'package:flutter/material.dart';

import '../../data/message_repository.dart';
import '../app_scope.dart';
import 'post_text.dart';

/// Comments on a post, pulled from the channel's linked discussion group.
///
/// This is as close as Telegram gets to replies on a channel post — there is no
/// separate comment primitive, only a linked group whose thread mirrors the post.
class ThreadSheet extends StatefulWidget {
  const ThreadSheet({
    super.key,
    required this.chatId,
    required this.messageId,
    required this.replyCount,
  });

  final int chatId;
  final int messageId;
  final int replyCount;

  @override
  State<ThreadSheet> createState() => _ThreadSheetState();
}

class _ThreadSheetState extends State<ThreadSheet> {
  List<ThreadComment>? _comments;
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
      final comments = await AppScope.messagesOf(context)
          .threadComments(widget.chatId, widget.messageId);
      if (mounted) setState(() => _comments = comments);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comments = _comments;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text('${widget.replyCount} comments',
                      style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: switch ((comments, _error)) {
                (_, final Object error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load comments.\n\n$error',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                (null, _) => const Center(child: CircularProgressIndicator()),
                (final list, _) when list!.isEmpty => Center(
                    child: Text('No comments yet.',
                        style: theme.textTheme.bodySmall),
                  ),
                (final list, _) => ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: list!.length,
                    separatorBuilder: (_, _) => const Divider(height: 20),
                    itemBuilder: (context, index) {
                      final comment = list[index];
                      return PostText(
                        cacheKey: 'thread:${widget.chatId}:${comment.messageId}',
                        spansJson: comment.fields.spansJson,
                        fallbackText: comment.fields.text,
                      );
                    },
                  ),
              },
            ),
          ],
        );
      },
    );
  }
}
