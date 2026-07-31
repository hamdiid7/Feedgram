import 'package:flutter_test/flutter_test.dart';
import 'package:handy_tdlib/api.dart' as td;

import 'package:feedgram/data/text_segments.dart';

td.TextEntity entity(int offset, int length, td.TextEntityType type) =>
    td.TextEntity(offset: offset, length: length, type: type);

void main() {
  group('buildTextSegments', () {
    test('returns one plain segment when there are no entities', () {
      final segments = buildTextSegments('hello world', []);
      expect(segments, hasLength(1));
      expect(segments.single.text, 'hello world');
      expect(segments.single.styles, isEmpty);
    });

    test('splits a single entity out of surrounding text', () {
      final segments = buildTextSegments('a bold b', [
        entity(2, 4, const td.TextEntityTypeBold()),
      ]);
      expect(segments.map((s) => s.text).toList(), ['a ', 'bold', ' b']);
      expect(segments[1].styles, {SegmentStyle.bold});
      expect(segments[0].styles, isEmpty);
    });

    test('reassembles to exactly the original text', () {
      const text = 'bold italic both plain';
      final segments = buildTextSegments(text, [
        entity(0, 4, const td.TextEntityTypeBold()),
        entity(5, 6, const td.TextEntityTypeItalic()),
        entity(12, 4, const td.TextEntityTypeBold()),
        entity(12, 4, const td.TextEntityTypeItalic()),
      ]);
      expect(segments.map((s) => s.text).join(), text);
    });

    // Telegram entities nest freely — a bold link is two overlapping entities
    // over the same range, which cannot map onto one TextSpan each.
    test('merges styles where entities overlap', () {
      final segments = buildTextSegments('click here now', [
        entity(6, 4, const td.TextEntityTypeBold()),
        entity(6, 4, const td.TextEntityTypeTextUrl(url: 'https://x.test')),
      ]);
      final here = segments.firstWhere((s) => s.text == 'here');
      expect(here.styles, containsAll([SegmentStyle.bold, SegmentStyle.link]));
      expect(here.url, 'https://x.test');
    });

    test('handles partially overlapping entities', () {
      // "abcdef" with bold over 0-4 and italic over 2-6 must yield
      // ab(bold) cd(bold+italic) ef(italic).
      final segments = buildTextSegments('abcdef', [
        entity(0, 4, const td.TextEntityTypeBold()),
        entity(2, 4, const td.TextEntityTypeItalic()),
      ]);
      expect(segments.map((s) => s.text).toList(), ['ab', 'cd', 'ef']);
      expect(segments[0].styles, {SegmentStyle.bold});
      expect(segments[1].styles, {SegmentStyle.bold, SegmentStyle.italic});
      expect(segments[2].styles, {SegmentStyle.italic});
    });

    // The offsets TDLib sends are UTF-16 code units. Dart strings are UTF-16, so
    // they index directly — but any emoji is a surrogate pair occupying two
    // units, and treating offsets as runes would slice one in half.
    test('respects UTF-16 offsets across a surrogate pair', () {
      const text = '🎉 party';
      // The emoji is 2 code units + 1 space + 5 letters. If offsets were treated
      // as runes this would be 7, and every offset after the emoji would be off
      // by one.
      expect(text.length, 8);
      expect(text.runes.length, 7);
      final segments = buildTextSegments(text, [
        entity(3, 5, const td.TextEntityTypeBold()),
      ]);
      expect(segments.map((s) => s.text).join(), text);
      expect(segments.last.text, 'party');
      expect(segments.last.styles, {SegmentStyle.bold});
      expect(segments.first.text, '🎉 ');
    });

    test('clamps entities that run past the end of the text', () {
      final segments = buildTextSegments('short', [
        entity(2, 999, const td.TextEntityTypeBold()),
      ]);
      expect(segments.map((s) => s.text).join(), 'short');
    });

    test('uses the visible text as the target for a bare url', () {
      final segments = buildTextSegments('go to example.test ok', [
        entity(6, 12, const td.TextEntityTypeUrl()),
      ]);
      final link = segments.firstWhere((s) => s.styles.contains(SegmentStyle.link));
      expect(link.url, 'example.test');
    });
  });

  group('encode/decode round trip', () {
    test('survives persistence unchanged', () {
      final original = buildTextSegments('bold link', [
        entity(0, 4, const td.TextEntityTypeBold()),
        entity(5, 4, const td.TextEntityTypeTextUrl(url: 'https://y.test')),
      ]);
      final restored = decodeSegments(encodeSegments(original));

      expect(restored, hasLength(original.length));
      for (var i = 0; i < original.length; i++) {
        expect(restored[i].text, original[i].text);
        expect(restored[i].styles, original[i].styles);
        expect(restored[i].url, original[i].url);
      }
    });

    test('decodes null and empty to nothing', () {
      expect(decodeSegments(null), isEmpty);
      expect(decodeSegments(''), isEmpty);
    });
  });
}
