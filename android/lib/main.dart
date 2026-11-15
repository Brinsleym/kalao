// Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
// LGPL-3.0-only. Modified for Kalao.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kalao/app.dart';
import 'package:kalao/providers/settings_provider.dart';
import 'package:kalao/services/app_crash_service.dart';
import 'package:kalao/services/platform_bridge.dart';
import 'package:kalao/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _log = AppLogger('App');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(AppCrashService.recordRuntimeError(details.exception, details.stack));
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(AppCrashService.recordRuntimeError(error, stack));
    return true;
  };

  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
  );
  final verbose = container.read(settingsProvider).verboseLogging;
  LogBuffer().verbose = verbose || kDebugMode;
  unawaited(_startBackend(verbose));

  runApp(UncontrolledProviderScope(container: container, child: const KalaoApp()));
}

/// The Android host initialises the Rust library before the first frame; this
/// syncs the logging preference and records the engine in the log.
Future<void> _startBackend(bool verbose) async {
  try {
    await PlatformBridge.setLoggingEnabled(verbose);
    final info = await PlatformBridge.getBackendInfo();
    _log.i(
      'Engine ${info.name} ${info.version} (${info.os}/${info.arch}), '
      '${info.methods.length} methods: ${jsonEncode(info.methods)}',
    );
  } catch (error, stack) {
    _log.e('Rust engine is unavailable', error, stack);
  }
}
