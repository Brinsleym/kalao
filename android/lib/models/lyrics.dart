import 'package:flutter/foundation.dart';

/// Reading layers over lyric text (DATA_MODEL.md §1).
enum LyricLayerKind { pinyin, furigana, romaji, traditional, simplified }

/// Who produced a layer. `human` layers are never regenerated.
enum LayerOrigin { auto, human, translator }

/// A reading over the UTF-16 range [start, end) of a line's text.
@immutable
class RubySegment {
  const RubySegment(this.start, this.end, this.reading);

  factory RubySegment.fromJson(Map<String, dynamic> json) => RubySegment(
    (json['start'] as num).toInt(),
    (json['end'] as num).toInt(),
    json['reading'] as String? ?? '',
  );

  final int start;
  final int end;
  final String reading;

  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    'reading': reading,
  };

  @override
  bool operator ==(Object other) =>
      other is RubySegment &&
      other.start == start &&
      other.end == end &&
      other.reading == reading;

  @override
  int get hashCode => Object.hash(start, end, reading);
}

@immutable
class LyricLayer {
  const LyricLayer({required this.segments, this.origin = LayerOrigin.auto});

  final List<RubySegment> segments;
  final LayerOrigin origin;
}

/// One lyric line. `time` is zero for every line of an untimed document.
@immutable
class LyricLine {
  const LyricLine({
    required this.text,
    this.time = Duration.zero,
    this.end,
    this.section,
    this.sectionBreakBefore = false,
    this.layers = const {},
  });

  factory LyricLine.fromJson(Map<String, dynamic> json) => LyricLine(
    text: json['text'] as String? ?? '',
    time: Duration(milliseconds: (json['timeMs'] as num?)?.toInt() ?? 0),
    end: json['endMs'] == null
        ? null
        : Duration(milliseconds: (json['endMs'] as num).toInt()),
    section: json['section'] as String?,
    sectionBreakBefore: json['sectionBreakBefore'] as bool? ?? false,
  );

  final String text;
  final Duration time;
  final Duration? end;

  /// `verse`, `chorus`, `preChorus`, `bridge`, `intro`, `outro`, … or null.
  final String? section;
  final bool sectionBreakBefore;
  final Map<LyricLayerKind, LyricLayer> layers;

  LyricLine withLayer(LyricLayerKind kind, LyricLayer layer) => LyricLine(
    text: text,
    time: time,
    end: end,
    section: section,
    sectionBreakBefore: sectionBreakBefore,
    layers: {...layers, kind: layer},
  );

  Map<String, dynamic> toJson() => {
    'timeMs': time.inMilliseconds,
    if (end != null) 'endMs': end!.inMilliseconds,
    'text': text,
    if (section != null) 'section': section,
    'sectionBreakBefore': sectionBreakBefore,
  };
}

/// A lyric document: text and timing. Layers are stored separately
/// (`lyric_annotation`) and merged into [lines] when loaded.
@immutable
class LyricDocument {
  const LyricDocument({
    required this.lines,
    this.timed = false,
    this.offsetMs = 0,
    this.format = 'plain',
    this.sourceLang,
  });

  factory LyricDocument.fromJson(Map<String, dynamic> json) => LyricDocument(
    lines: [
      for (final line in json['lines'] as List<dynamic>? ?? const [])
        LyricLine.fromJson((line as Map).cast<String, dynamic>()),
    ],
    timed: json['timed'] as bool? ?? false,
    offsetMs: (json['offsetMs'] as num?)?.toInt() ?? 0,
    format: json['format'] as String? ?? 'plain',
    sourceLang: json['sourceLang'] as String?,
  );

  final List<LyricLine> lines;
  final bool timed;
  final int offsetMs;
  final String format;
  final String? sourceLang;

  bool get isEmpty => lines.isEmpty;

  /// Whether any line contains Han characters (pinyin applies).
  bool get hasHan => lines.any((line) => containsHan(line.text));

  Map<String, dynamic> toJson() => {
    'version': 1,
    'format': format,
    'timed': timed,
    'offsetMs': offsetMs,
    if (sourceLang != null) 'sourceLang': sourceLang,
    'lines': [for (final line in lines) line.toJson()],
  };

  LyricDocument withLines(List<LyricLine> next) => LyricDocument(
    lines: next,
    timed: timed,
    offsetMs: offsetMs,
    format: format,
    sourceLang: sourceLang,
  );

  /// The line playing at [position] for a timed document (binary search over
  /// start times, with the per-song offset), or null before the first line.
  int? activeLineAt(Duration position) {
    if (!timed || lines.isEmpty) return null;
    final ms = position.inMilliseconds + offsetMs;
    var low = 0;
    var high = lines.length - 1;
    var found = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (lines[mid].time.inMilliseconds <= ms) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found < 0 ? null : found;
  }
}

final _han = RegExp(r'[㐀-䶿一-鿿豈-﫿]');

bool containsHan(String text) => _han.hasMatch(text);
