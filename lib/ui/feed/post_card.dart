import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../domain/feed_grouping.dart';
import '../app_scope.dart';
import 'media_viewer.dart';
import 'post_video.dart';
import 'post_album.dart';
import 'post_media.dart';
import 'post_text.dart';
import 'thread_sheet.dart';

/// One card in the feed — a single post or an album carousel.
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.item, this.reason});

  final FeedItem item;

  /// Why For You surfaced this, e.g. "3 channels you follow shared this".
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // For an album the caption lives on whichever member carries it, so text and
    // media come from different entries.
    final entry = switch (item) {
      SinglePost(:final entry) => entry,
      AlbumPost(:final captioned) => captioned,
    };
    final message = entry.message;
    final channel = entry.channel;
    final media = item is SinglePost
        ? PostMedia.decode(message.mediaJson)
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reason != null) ...[
            Row(
              children: [
                Icon(Icons.auto_awesome,
                    size: 13, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reason!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          _Header(channel: channel, message: item.lead.message),
          if (message.forwardedFromChatId != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.forward,
                    size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('forwarded', style: theme.textTheme.bodySmall),
              ],
            ),
          ],
          if (message.body.isNotEmpty) ...[
            const SizedBox(height: 8),
            PostText(
              cacheKey: '${message.chatId}:${message.messageId}',
              spansJson: message.spansJson,
              fallbackText: message.body,
              maxLines: 12,
            ),
          ],
          if (item case AlbumPost album) ...[
            const SizedBox(height: 8),
            PostAlbum(album: album),
          ],
          if (media != null) ...[
            const SizedBox(height: 8),
            // Video and GIF get the player; everything else is a still.
            if (media.isPlayable)
              PostVideoView(
                media: media,
                postKey: item.key,
                onTap: media.fileId == null
                    ? null
                    : () => _openViewer(context, media),
              )
            else
              PostMediaView(
                media: media,
                // Full-size download happens here and only here — never during
                // backfill.
                onTap: media.fileId == null
                    ? null
                    : () => _openViewer(context, media),
              ),
          ],
          const SizedBox(height: 4),
          _Actions(message: item.lead.message),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.channel, required this.message});

  final Channel channel;
  final Message message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            _initials(channel.title),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                channel.title.isEmpty ? 'Untitled' : channel.title,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                [
                  if (channel.username != null) '@${channel.username}',
                  _relativeTime(message.date),
                  if (message.editDate != null) 'edited',
                ].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final liked = message.chosenReaction != null;

    return Row(
      children: [
        _StatIcon(icon: Icons.visibility_outlined, value: message.viewCount),
        const SizedBox(width: 8),
        TextButton.icon(
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            foregroundColor: liked
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          icon: Icon(liked ? Icons.favorite : Icons.favorite_border, size: 16),
          label: Text(
            message.reactionCount > 0 ? _compact(message.reactionCount) : '',
          ),
          onPressed: () async {
            try {
              await AppScope.messagesOf(context)
                  .toggleReaction(message.chatId, message.messageId);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Reaction failed: $e')),
                );
              }
            }
          },
        ),
        if (message.replyCount > 0)
          TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: theme.colorScheme.onSurfaceVariant,
            ),
            icon: const Icon(Icons.mode_comment_outlined, size: 16),
            label: Text(_compact(message.replyCount)),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => ThreadSheet(
                chatId: message.chatId,
                messageId: message.messageId,
                replyCount: message.replyCount,
              ),
            ),
          ),
        const Spacer(),
        _StatIcon(icon: Icons.forward_outlined, value: message.forwardCount),
      ],
    );
  }
}

class _StatIcon extends StatelessWidget {
  const _StatIcon({required this.icon, required this.value});

  final IconData icon;
  final int value;

  @override
  Widget build(BuildContext context) {
    if (value <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(_compact(value), style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Up to two initials for the avatar.
///
/// Only words that actually start with a letter or digit count — channel titles
/// are full of brackets, emoji and punctuation, and naively taking the first
/// character of the first two words turns "Afriwork (Freelance Ethiopia)" into
/// "A(".
String _initials(String title) {
  final words = title
      .trim()
      .split(RegExp(r'\s+'))
      .map((word) => word.characters.skipWhile(_isNotAlphanumeric))
      .where((word) => word.isNotEmpty)
      .toList();

  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.first.toUpperCase();
  return (words[0].first + words[1].first).toUpperCase();
}

bool _isNotAlphanumeric(String character) =>
    !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(character);

String _compact(int count) {
  if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
  if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
  return '$count';
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

/// Opens fullscreen playback/viewing.
///
/// The coordinator is told before and after so the fullscreen player owns the
/// whole decoder budget while it is up — otherwise an inline video keeps a decoder
/// and its audio session alive behind it.
Future<void> _openViewer(BuildContext context, PostMedia media) async {
  final playback = AppScope.playbackOf(context);
  playback.fullscreen = true;
  try {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MediaViewer(media: media)),
    );
  } finally {
    playback.fullscreen = false;
  }
}
