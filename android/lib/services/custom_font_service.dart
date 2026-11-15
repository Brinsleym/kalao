// Pattern from Mornye's custom_font_service.dart (Copyright 2026 zarzet,
// LGPL-3.0-only): the picked font is copied into app storage and registered
// with FontLoader under a family name derived from its path.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kalao/providers/settings_provider.dart';
import 'package:kalao/utils/logger.dart';
import 'package:path/path.dart' as p;

const _log = AppLogger('Font');

const customFontExtensions = ['ttf', 'otf'];

/// The lyric font family, or null for the theme font. Each file gets its own
/// family name because a loaded family cannot be replaced.
final customFontFamilyProvider = FutureProvider<String?>((ref) async {
  final path = ref.watch(settingsProvider.select((s) => s.customFontPath));
  if (path == null) return null;
  final file = File(path);
  if (!file.existsSync()) return null;
  final family = 'KalaoCustom_${p.basenameWithoutExtension(path)}';
  try {
    final loader = FontLoader(family)
      ..addFont(file.readAsBytes().then(ByteData.sublistView));
    await loader.load();
    return family;
  } catch (error) {
    _log.w('Custom font could not be loaded', error);
    return null;
  }
});

/// Copies [bytes] (a picked font) into [fontsDir] and returns the new path.
Future<String> storeCustomFont(
  Directory fontsDir,
  String name,
  List<int> bytes,
) async {
  await fontsDir.create(recursive: true);
  final extension = p.extension(name).toLowerCase();
  final target = File(
    p.join(
      fontsDir.path,
      'font_${DateTime.now().millisecondsSinceEpoch}$extension',
    ),
  );
  await target.writeAsBytes(bytes, flush: true);
  return target.path;
}
