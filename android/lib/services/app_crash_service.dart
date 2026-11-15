// Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
// LGPL-3.0-only. Modified for Kalao.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kalao/services/platform_bridge.dart';
import 'package:kalao/utils/logger.dart';

const _log = AppLogger('Crash');

/// The last native crash, shown once on the next start. Kept on the device;
/// the user decides whether to copy it into a GitHub issue.
@immutable
class CrashReport {
  const CrashReport({required this.raw, required this.error, this.time});

  final String raw;
  final String error;
  final DateTime? time;

  /// Pretty, redacted text for the clipboard.
  String get shareText {
    try {
      final json = jsonDecode(raw);
      return redactDiagnosticText(
        const JsonEncoder.withIndent('  ').convert(json),
      );
    } on FormatException {
      return redactDiagnosticText(raw);
    }
  }
}

class AppCrashService {
  AppCrashService._();

  /// Saves context for a later confirmed process crash. A handled Flutter
  /// error alone must not produce an "app crashed" message on the next launch.
  static Future<void> recordRuntimeError(Object error, StackTrace? stack) async {
    _log.e('Unhandled error', error, stack);
    try {
      final entries = LogBuffer().entries;
      await PlatformBridge.recordAppRuntimeError(
        error: redactDiagnosticText(error.toString()),
        stack: redactDiagnosticText(stack?.toString() ?? ''),
        logs: formatLogEntries(
          entries.skip(entries.length > 40 ? entries.length - 40 : 0),
        ),
      );
    } catch (_) {
      // Never route a reporting failure back into the global error handler.
    }
  }

  static Future<CrashReport?> readLastCrash() async {
    try {
      final raw = await PlatformBridge.readLastCrashReport();
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final millis = json['time'];
      return CrashReport(
        raw: raw,
        error: json['error'] as String? ?? '',
        time: millis is int ? DateTime.fromMillisecondsSinceEpoch(millis) : null,
      );
    } catch (error) {
      _log.w('Could not read the last crash report', error);
      return null;
    }
  }

  static Future<void> clearLastCrash() async {
    try {
      await PlatformBridge.clearLastCrashReport();
    } catch (error) {
      _log.w('Could not clear the last crash report', error);
    }
  }
}
