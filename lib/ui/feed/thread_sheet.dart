import 'package:flutter/material.dart';

import '../../data/message_repository.dart';
import '../app_scope.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets/bottom_sheet.dart';
import 'post_text.dart';

/// Opens the comments on a post.
///
/// Snaps open to 60% and drags to full height, with the handful of comments most
/// posts have visible without a second gesture — the budget app's sheet
/// proportions, and they suit a comment list for the same reason they suit a
/// picker: the content behind stays partly on screen, so the sheet reads as
/// attached to the post rather than as a new page.
Future<void> openThreadSheet(
  BuildContext context, {
  required int chatId,
  required int messageId,
  required int replyCount,
}) {
  return openBottomSheet<void>(
    context,
    builder: (context, controller) => ThreadSheet(
      chatId: chatId,
      messageId: messageId,
      replyCount: replyCount,
      scrollController: controller,
    ),
  );
}

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
    this.scrollController,
  });

  final int chatId;
  final int messageId;
  final int replyCount;

  /// The sheet's controller, so scrolling the list keeps dragging the sheet once
  /// it reaches the top.
  final ScrollController? scrollController;

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
    final count = widget.replyCount;

    return SheetFrame(
      title: 'Comments',
      subtitle: count == 1 ? '1 reply' : '$count replies',
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    final comments = _comments;
    final error = _error;

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load comments.\n\n$error',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    if (comments == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Springs in, because it arrives after a wait rather than being
            // there when the sheet opened.
            ScaleIn(
              child: Icon(
                Icons.mode_comment_outlined,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text('No comments yet.', style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: widget.scrollController,
      padding: EdgeInsets.fromLTRB(12, 10, 12, sheetBottomPadding(context)),
      itemCount: comments.length,
      itemBuilder: (context, index) {
        final comment = comments[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            // A shade off the sheet rather than a divider: comments vary from a
            // word to a paragraph, and rules between them make short ones read
            // as table rows.
            color: dynamicPastel(
              context,
              theme.colorScheme.secondaryContainer,
              amountLight: 0.35,
              amountDark: 0.15,
            ),
            borderRadius: BorderRadius.circular(Shapes.row),
          ),
          child: PostText(
            cacheKey: 'thread:${widget.chatId}:${comment.messageId}',
            spansJson: comment.fields.spansJson,
            fallbackText: comment.fields.text,
          ),
        );
      },
    );
  }
}
