import 'package:flutter/material.dart';

import '../../data/app_database.dart';
import '../../domain/feed_grouping.dart';
import '../app_scope.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets/count_number.dart';
import '../widgets/open_container_navigation.dart';
import '../widgets/tappable.dart';
import '../channels/channel_feed_screen.dart';
import 'media_viewer.dart';
import 'post_video.dart';
import 'post_album.dart';
import 'post_media.dart';
import 'post_text.dart';
import 'post_screen.dart';

/// One card in the feed — a single post or an album carousel.
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.item,
    this.reason,
    this.linkChannel = true,
    this.openable = true,
  });

  final FeedItem item;

  /// Why For You surfaced this, e.g. "3 channels you follow shared this".
  final String? reason;

  /// Whether the header opens the channel's profile.
  ///
  /// Off inside that profile: the post is already on the channel's own page, so
  /// the link would push a second copy of the screen you are standing on.
  final bool linkChannel;

  /// Whether tapping the card opens the post with its comments.
  ///
  /// Off for the copy shown at the top of that very screen, which would
  /// otherwise open itself, forever.
  final bool openable;

  @override
  Widget build(BuildContext context) {
    if (!openable) return _card(context);

    // The gap between cards stays outside the transform. Inside it, the growing
    // container would paint its fill across the margin and the cards would meet.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: OpenContainerNavigation(
        borderRadius: Shapes.card,
        closedColor: containerColor(context),
        openPage: PostScreen(item: item),
        // The card grows into the post the same way a channel header grows into
        // its profile. Inner controls — media, the reaction, the header link —
        // sit deeper in the tree and take their taps first.
        button: (open) => Tappable(
          onTap: open,
          borderRadius: Shapes.card,
          // The comment count opens the same page through the same transform,
          // rather than pushing a second route that looks different.
          child: _card(context, flat: true, onOpen: open),
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    bool flat = false,
    VoidCallback? onOpen,
  }) {
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

    // A rounded tinted container per post, rather than full-width rows split by
    // dividers. Separation comes from the gap between cards, which survives a
    // wall of photos where a hairline rule does not.
    //
    // When the card is wrapped for opening, the transform paints the fill and
    // the rounding, so painting them again here would double the corners.
    return Container(
      margin: flat
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      decoration: flat
          ? null
          : BoxDecoration(
              color: containerColor(context),
              borderRadius: BorderRadius.circular(Shapes.card),
            ),
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
          _ChannelLine(
            channel: channel,
            message: item.lead.message,
            link: linkChannel,
          ),
          // Everything below the name is inset past the avatar, so the post reads
          // as one block hanging off the channel rather than a header sitting on
          // top of full-width text.
          Padding(
            padding: const EdgeInsets.only(left: _contentInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                _Actions(
                  message: item.lead.message,
                  onOpen: onOpen,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar column width plus its gap — the inset every part of the post body
/// shares, so text, media and actions all line up under the channel name.
const _contentInset = 42.0;

class _ChannelLine extends StatelessWidget {
  const _ChannelLine({
    required this.channel,
    required this.message,
    required this.link,
  });

  final Channel channel;
  final Message message;

  /// Whether the row opens the channel's profile.
  final bool link;

  @override
  Widget build(BuildContext context) {
    final row = _row(context);
    if (!link) return row;

    // The header is the way into a channel from anywhere in the feed, and it
    // grows into the profile rather than being replaced by it — the header is
    // literally a compressed version of that page.
    //
    // This replaces a Hero on the avatar. The two cannot coexist: the container
    // transform keeps the source subtree mounted for the whole flight, so a hero
    // in it and a matching one on the destination are two live widgets sharing a
    // tag, which is an assertion failure rather than a nicer animation.
    return OpenContainerNavigation(
      borderRadius: Shapes.row,
      openPage: ChannelFeedScreen(channel: channel),
      button: (open) => Tappable(
        onTap: open,
        borderRadius: Shapes.row,
        child: row,
      ),
    );
  }

  Widget _row(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
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
          const SizedBox(width: _contentInset - 32),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    channel.title.isEmpty ? 'Untitled' : channel.title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                // Handle without the "@": the name already says whose it is, and
                // the sigil is noise at this size.
                if (channel.username != null)
                  Flexible(
                    child: Text(
                      channel.username!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                Text(
                  ' · ${_relativeTime(message.date)}'
                  '${message.editDate != null ? ' · edited' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.message, this.onOpen});

  final Message message;

  /// Opens the post with its comments. Null on the post screen itself, where
  /// the comment count is already the thing you are looking at.
  final VoidCallback? onOpen;

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
          icon: TapBounce(
            active: liked,
            child: Icon(liked ? Icons.favorite : Icons.favorite_border, size: 16),
          ),
          // Rolls to the new total when a reaction lands, so the count visibly
          // acknowledges the tap instead of silently being one higher.
          label: AnimatedSizeSwitcher(
            child: CountNumber(
              value: message.reactionCount,
              builder: (context, value) =>
                  Text(value > 0 ? _compact(value) : ''),
            ),
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
        if (message.replyCount > 0 && onOpen != null)
          TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: theme.colorScheme.onSurfaceVariant,
            ),
            icon: const Icon(Icons.mode_comment_outlined, size: 16),
            label: Text(_compact(message.replyCount)),
            // Same destination as tapping the card: one place for comments,
            // and the only one with a box to add your own.
            onPressed: onOpen,
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
