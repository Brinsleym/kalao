// Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
// LGPL-3.0-only. Modified for Kalao.
import 'dart:collection';

import 'package:flutter/foundation.dart';

const int _maxBufferedLogMessageLength = 4000;
const int _bufferCapacity = 500;
const String _redactedValue = '[REDACTED]';

final RegExp _authorizationBearerPattern = RegExp(
  r'\bAuthorization\b\s*[:=]\s*Bearer\s+[A-Za-z0-9._~+/\-]+=*',
  caseSensitive: false,
);

final RegExp _genericSensitiveKeyValuePattern = RegExp(
  r'("?(?:access[_\s-]?token|refresh[_\s-]?token|id[_\s-]?token|client[_\s-]?secret|authorization|password|api[_\s-]?key|session[_\s-]?secret|cookie|set-cookie)"?)(\s*[:=]\s*)("(?:\\.|[^"\\])*"|[^\s,;}\]]+)',
  caseSensitive: false,
);

final RegExp _sensitiveQueryPattern = RegExp(
  r'([?&](?:access_token|refresh_token|id_token|token|client_secret|api_key|apikey|password|code|sig|signature|de)=)[^&\s]+',
  caseSensitive: false,
);

final RegExp _bearerTokenPattern = RegExp(
  r'\bBearer\s+[A-Za-z0-9._~+/\-]+=*',
  caseSensitive: false,
);

/// Removes tokens, keys and passwords before text is logged or exported.
/// (`de=` is MyMemory's contact email parameter.)
String redactDiagnosticText(String value) => value
    .replaceAllMapped(
      _authorizationBearerPattern,
      (_) => 'Authorization: Bearer $_redactedValue',
    )
    .replaceAllMapped(
      _genericSensitiveKeyValuePattern,
      (match) => '${match.group(1)}${match.group(2)}$_redactedValue',
    )
    .replaceAllMapped(
      _sensitiveQueryPattern,
      (match) => '${match.group(1)}$_redactedValue',
    )
    .replaceAllMapped(_bearerTokenPattern, (_) => 'Bearer $_redactedValue');

String _truncate(String value) => value.length <= _maxBufferedLogMessageLength
    ? value
    : '${value.substring(0, _maxBufferedLogMessageLength)}...[truncated]';

enum LogLevel { debug, info, warn, error }

@immutable
class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.isFromNative = false,
  });

  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final String? error;
  final bool isFromNative;

  String get formattedTime {
    String two(int value) => value.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '${two(timestamp.hour)}:${two(timestamp.minute)}:${two(timestamp.second)}.$ms';
  }

  String get levelLabel => level.name.toUpperCase();

  @override
  String toString() {
    final errorPart = error != null ? ' | $error' : '';
    final nativePart = isFromNative ? ' [Native]' : '';
    return '[$formattedTime] [$levelLabel]$nativePart [$tag] $message$errorPart';
  }
}

String formatLogEntries(Iterable<LogEntry> entries) =>
    entries.map((entry) => entry.toString()).join('\n');

/// The app-wide in-memory log ring. Debug and info entries are kept only while
/// verbose logging is enabled; warnings and errors are always kept.
class LogBuffer extends ChangeNotifier {
  factory LogBuffer() => _instance;
  LogBuffer._();

  static final LogBuffer _instance = LogBuffer._();

  final _entries = ListQueue<LogEntry>();
  bool _verbose = kDebugMode;

  bool get verbose => _verbose;
  set verbose(bool value) {
    _verbose = value;
    notifyListeners();
  }

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void add(LogEntry entry) {
    if (!_verbose && entry.level.index < LogLevel.warn.index) return;
    if (_entries.length == _bufferCapacity) _entries.removeFirst();
    _entries.addLast(entry);
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}

/// Tagged logger, as in Mornye: `final _log = AppLogger('Player');`.
class AppLogger {
  const AppLogger(this.tag);

  final String tag;

  void d(String message) => _log(LogLevel.debug, message);
  void i(String message) => _log(LogLevel.info, message);
  void w(String message, [Object? error]) =>
      _log(LogLevel.warn, message, error);
  void e(String message, [Object? error, StackTrace? stack]) =>
      _log(LogLevel.error, message, error, stack);

  void _log(
    LogLevel level,
    String message, [
    Object? error,
    StackTrace? stack,
  ]) {
    final text = _truncate(redactDiagnosticText(message));
    final errorText = error == null
        ? null
        : _truncate(
            redactDiagnosticText(
              stack == null ? '$error' : '$error\n$stack',
            ),
          );
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: text,
      error: errorText,
    );
    LogBuffer().add(entry);
    if (kDebugMode) debugPrint(entry.toString());
  }
}
