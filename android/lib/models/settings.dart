// Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
// LGPL-3.0-only. Modified for Kalao.
import 'package:flutter/material.dart';

/// App preferences, stored as one JSON object in shared_preferences.
/// Unknown or missing keys fall back to defaults, so adding a field never
/// breaks an existing install. Secrets never go here (secure storage).
@immutable
class AppSettings {
  const AppSettings({
    this.setupCompleted = false,
    this.themeMode = ThemeMode.system,
    this.localeTag,
    this.verboseLogging = false,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    setupCompleted: json['setupCompleted'] as bool? ?? false,
    themeMode:
        ThemeMode.values.asNameMap()[json['themeMode']] ?? ThemeMode.system,
    localeTag: json['localeTag'] as String?,
    verboseLogging: json['verboseLogging'] as bool? ?? false,
  );

  /// The user finished the first-run setup.
  final bool setupCompleted;
  final ThemeMode themeMode;

  /// A BCP-47 tag from `supportedLocales`, or null to follow the system.
  final String? localeTag;

  /// Keep debug and info log entries (Dart and Rust).
  final bool verboseLogging;

  Map<String, dynamic> toJson() => {
    'setupCompleted': setupCompleted,
    'themeMode': themeMode.name,
    'localeTag': localeTag,
    'verboseLogging': verboseLogging,
  };

  AppSettings copyWith({
    bool? setupCompleted,
    ThemeMode? themeMode,
    String? Function()? localeTag,
    bool? verboseLogging,
  }) => AppSettings(
    setupCompleted: setupCompleted ?? this.setupCompleted,
    themeMode: themeMode ?? this.themeMode,
    localeTag: localeTag != null ? localeTag() : this.localeTag,
    verboseLogging: verboseLogging ?? this.verboseLogging,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.setupCompleted == setupCompleted &&
      other.themeMode == themeMode &&
      other.localeTag == localeTag &&
      other.verboseLogging == verboseLogging;

  @override
  int get hashCode => Object.hash(
    setupCompleted,
    themeMode,
    localeTag,
    verboseLogging,
  );
}
