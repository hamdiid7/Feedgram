import 'dart:convert';

import 'package:handy_tdlib/api.dart' as td;

/// Styles a segment can carry. Names are stable — they are persisted in
/// `messages.spans_json`, so renaming one is a schema change.
enum SegmentStyle {
  bold,
  italic,
  underline,
  strikethrough,
  code,
  pre,
  spoiler,
  quote,
  link,
  mention,
  hashtag;

  static SegmentStyle? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// A run of text with one fixed set of styles — flat, never nested.
class TextSegment {
  const TextSegment({required this.text, this.styles = const {}, this.url});

  final String text;
  final Set<SegmentStyle> styles;

  /// Target for [SegmentStyle.link] / [SegmentStyle.mention] / hashtags.
  final String? url;

  Map<String, dynamic> toJson() => {
        't': text,
        if (styles.isNotEmpty) 's': [for (final s in styles) s.name],
        if (url != null) 'u': url,
      };

  static TextSegment fromJson(Map<String, dynamic> json) => TextSegment(
        text: json['t'] as String? ?? '',
        styles: {
          for (final name in (json['s'] as List<dynamic>? ?? const []))
            ?SegmentStyle.byName(name as String),
        },
        url: json['u'] as String?,
      );
}

/// Flattens TDLib entities into non-overlapping [TextSegment]s.
///
/// Telegram entities **overlap and nest** — a link can be bold, a code span can
/// sit inside a quote — so they cannot map one-to-one onto `TextSpan`s. This
/// sweeps every entity boundary and emits one segment per gap, carrying the
/// union of the styles covering it.
///
/// Offsets are UTF-16 code units and Dart strings are UTF-16, so they index
/// directly with no conversion. That matters: any codepoint outside the BMP —
/// every emoji — occupies two units, and treating offsets as runes would slice
/// text mid-surrogate.
List<TextSegment> buildTextSegments(String text, List<td.TextEntity> entities) {
  if (text.isEmpty) return const [];
  if (entities.isEmpty) return [TextSegment(text: text)];

  // Every point where the style set can change.
  final boundaries = <int>{0, text.length};
  for (final entity in entities) {
    final start = entity.offset.clamp(0, text.length);
    final end = (entity.offset + entity.length).clamp(0, text.length);
    if (start >= end) continue;
    boundaries..add(start)..add(end);
  }

  final points = boundaries.toList()..sort();
  final segments = <TextSegment>[];

  for (var i = 0; i < points.length - 1; i++) {
    final start = points[i];
    final end = points[i + 1];
    if (start >= end) continue;

    final styles = <SegmentStyle>{};
    String? url;

    for (final entity in entities) {
      final entityStart = entity.offset;
      final entityEnd = entity.offset + entity.length;
      // Covers this whole gap, by construction of the boundary set.
      if (entityStart > start || entityEnd < end) continue;

      final style = _styleOf(entity.type);
      if (style != null) styles.add(style);

      url ??= _urlOf(entity.type, text.substring(start, end));
    }

    segments.add(TextSegment(
      text: text.substring(start, end),
      styles: styles,
      url: url,
    ));
  }

  return segments;
}

String encodeSegments(List<TextSegment> segments) =>
    jsonEncode([for (final s in segments) s.toJson()]);

List<TextSegment> decodeSegments(String? json) {
  if (json == null || json.isEmpty) return const [];
  final decoded = jsonDecode(json);
  if (decoded is! List) return const [];
  return [
    for (final entry in decoded)
      if (entry is Map<String, dynamic>) TextSegment.fromJson(entry),
  ];
}

SegmentStyle? _styleOf(td.TextEntityType type) => switch (type) {
      td.TextEntityTypeBold() => SegmentStyle.bold,
      td.TextEntityTypeItalic() => SegmentStyle.italic,
      td.TextEntityTypeUnderline() => SegmentStyle.underline,
      td.TextEntityTypeStrikethrough() => SegmentStyle.strikethrough,
      td.TextEntityTypeCode() => SegmentStyle.code,
      td.TextEntityTypePre() => SegmentStyle.pre,
      td.TextEntityTypePreCode() => SegmentStyle.pre,
      td.TextEntityTypeSpoiler() => SegmentStyle.spoiler,
      td.TextEntityTypeBlockQuote() => SegmentStyle.quote,
      td.TextEntityTypeExpandableBlockQuote() => SegmentStyle.quote,
      td.TextEntityTypeTextUrl() => SegmentStyle.link,
      td.TextEntityTypeUrl() => SegmentStyle.link,
      td.TextEntityTypeEmailAddress() => SegmentStyle.link,
      td.TextEntityTypePhoneNumber() => SegmentStyle.link,
      td.TextEntityTypeMention() => SegmentStyle.mention,
      td.TextEntityTypeMentionName() => SegmentStyle.mention,
      td.TextEntityTypeHashtag() => SegmentStyle.hashtag,
      td.TextEntityTypeCashtag() => SegmentStyle.hashtag,
      _ => null,
    };

/// The tappable target for a segment.
///
/// `textUrl` carries an explicit href; `url`/`email`/`phone` use the visible
/// text itself, which is why [content] is passed in.
String? _urlOf(td.TextEntityType type, String content) => switch (type) {
      td.TextEntityTypeTextUrl(:final url) => url,
      td.TextEntityTypeUrl() => content,
      td.TextEntityTypeEmailAddress() => 'mailto:$content',
      td.TextEntityTypePhoneNumber() => 'tel:$content',
      td.TextEntityTypeMention() => 'https://t.me/${content.replaceFirst('@', '')}',
      _ => null,
    };
