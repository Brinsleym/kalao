import 'package:flutter/material.dart';
import 'package:kalao/models/lyrics.dart';

/// One lyric line with readings (pinyin) above the characters they annotate
/// (IMPLEMENTATION.md §4 "Display"). The line is split into units: each ruby
/// segment is one unit (reading over its characters); unannotated text is
/// split at spaces so Latin words wrap normally. Every unit reserves the
/// reading row, so annotated and plain text share one baseline.
class RubyLyricLine extends StatelessWidget {
  const RubyLyricLine({
    super.key,
    required this.line,
    required this.style,
    this.layer,
    this.textAlign = TextAlign.center,
  });

  final LyricLine line;
  final TextStyle style;

  /// The layer to show above the text, or null for plain text.
  final LyricLayerKind? layer;
  final TextAlign textAlign;

  /// Units of [text] for [segments]: (base, reading?) pairs.
  @visibleForTesting
  static List<(String, String?)> units(
    String text,
    List<RubySegment> segments,
  ) {
    final out = <(String, String?)>[];
    void plain(String chunk) {
      // Keep each space with the word before it so wrapping happens at spaces.
      final words = RegExp(r'\S+\s*|\s+').allMatches(chunk);
      for (final word in words) {
        out.add((word.group(0)!, null));
      }
    }

    var cursor = 0;
    final sorted = [...segments]..sort((a, b) => a.start.compareTo(b.start));
    for (final segment in sorted) {
      if (segment.start < cursor || segment.end > text.length) continue;
      if (segment.start > cursor) plain(text.substring(cursor, segment.start));
      out.add((text.substring(segment.start, segment.end), segment.reading));
      cursor = segment.end;
    }
    if (cursor < text.length) plain(text.substring(cursor));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final segments = layer == null
        ? const <RubySegment>[]
        : line.layers[layer]?.segments ?? const <RubySegment>[];
    if (segments.isEmpty) {
      return Text(line.text, style: style, textAlign: textAlign);
    }
    final readingStyle = style.copyWith(
      fontSize: (style.fontSize ?? 20) * 0.5,
      fontWeight: FontWeight.w500,
      height: 1.1,
      color: style.color,
    );
    final readings = [
      for (final segment in segments) segment.reading,
    ].join(' ');
    return Semantics(
      label: '${line.text}, $readings',
      excludeSemantics: true,
      child: Wrap(
        alignment: switch (textAlign) {
          TextAlign.left || TextAlign.start => WrapAlignment.start,
          TextAlign.right || TextAlign.end => WrapAlignment.end,
          _ => WrapAlignment.center,
        },
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          for (final (base, reading) in units(line.text, segments))
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reading ?? ' ',
                  style: readingStyle,
                  maxLines: 1,
                  softWrap: false,
                ),
                Text(base, style: style, maxLines: 1, softWrap: false),
              ],
            ),
        ],
      ),
    );
  }
}
