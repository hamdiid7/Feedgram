import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../data/text_segments.dart';

/// Renders the precomputed segments of a post.
///
/// Everything expensive already happened at insert time: the segments come out
/// of the database flat and non-overlapping, so this is a straight map onto
/// `TextSpan`s with no entity logic, no offset arithmetic, and no sorting.
///
/// The built spans are memoised in [_spanCache] because a virtualized list
/// rebuilds the same visible rows constantly — parsing the stored JSON on every
/// frame would undo the point of precomputing it.
class PostText extends StatelessWidget {
  const PostText({
    super.key,
    required this.cacheKey,
    required this.spansJson,
    required this.fallbackText,
    this.maxLines,
    this.onLinkTap,
  });

  /// Stable identity for the memo — `(chatId, messageId)`.
  final String cacheKey;

  final String? spansJson;

  /// Used when a post has no stored segments (older rows, or plain media).
  final String fallbackText;

  final int? maxLines;
  final void Function(String url)? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segments = _segmentsFor(cacheKey, spansJson);

    if (segments.isEmpty) {
      if (fallbackText.isEmpty) return const SizedBox.shrink();
      return Text(fallbackText, maxLines: maxLines, overflow: _overflow);
    }

    return Text.rich(
      TextSpan(
        children: [
          for (final segment in segments)
            _spanFor(context, theme, segment),
        ],
      ),
      maxLines: maxLines,
      overflow: _overflow,
    );
  }

  TextOverflow get _overflow =>
      maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis;

  InlineSpan _spanFor(
    BuildContext context,
    ThemeData theme,
    TextSegment segment,
  ) {
    final styles = segment.styles;
    final isLink = styles.contains(SegmentStyle.link) ||
        styles.contains(SegmentStyle.mention) ||
        styles.contains(SegmentStyle.hashtag);

    var style = theme.textTheme.bodyMedium ?? const TextStyle();

    if (styles.contains(SegmentStyle.bold)) {
      style = style.copyWith(fontWeight: FontWeight.bold);
    }
    if (styles.contains(SegmentStyle.italic)) {
      style = style.copyWith(fontStyle: FontStyle.italic);
    }
    if (styles.contains(SegmentStyle.underline)) {
      style = style.copyWith(decoration: TextDecoration.underline);
    }
    if (styles.contains(SegmentStyle.strikethrough)) {
      style = style.copyWith(decoration: TextDecoration.lineThrough);
    }
    if (styles.contains(SegmentStyle.code) || styles.contains(SegmentStyle.pre)) {
      style = style.copyWith(
        fontFamily: 'monospace',
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
      );
    }
    if (isLink) {
      style = style.copyWith(color: theme.colorScheme.primary);
    }
    if (styles.contains(SegmentStyle.spoiler)) {
      // Not interactive yet; hidden rather than shown by mistake.
      style = style.copyWith(
        color: Colors.transparent,
        backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.25),
      );
    }
    if (styles.contains(SegmentStyle.quote)) {
      style = style.copyWith(color: theme.colorScheme.onSurfaceVariant);
    }

    final url = segment.url;
    if (url == null || onLinkTap == null) {
      return TextSpan(text: segment.text, style: style);
    }

    return TextSpan(
      text: segment.text,
      style: style,
      recognizer: TapGestureRecognizer()..onTap = () => onLinkTap!(url),
    );
  }
}

/// Small bounded memo of decoded segments, keyed by message identity.
final _spanCache = <String, List<TextSegment>>{};
const _spanCacheLimit = 400;

List<TextSegment> _segmentsFor(String key, String? json) {
  final cached = _spanCache[key];
  if (cached != null) return cached;

  final segments = decodeSegments(json);

  if (_spanCache.length >= _spanCacheLimit) {
    // Cheap eviction: the feed only ever needs the rows near the viewport, so
    // dropping the oldest insertions is enough.
    _spanCache.remove(_spanCache.keys.first);
  }
  _spanCache[key] = segments;
  return segments;
}
