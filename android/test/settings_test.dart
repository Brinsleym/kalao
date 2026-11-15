import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalao/l10n/supported_locales.dart';
import 'package:kalao/models/settings.dart';
import 'package:kalao/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings round-trip through JSON and ignore unknown keys', () {
    const settings = AppSettings(
      setupCompleted: true,
      themeMode: ThemeMode.dark,
      useDynamicColor: false,
      localeTag: 'zh-Hant',
      verboseLogging: true,
    );
    final json = {...settings.toJson(), 'futureKey': 1};
    expect(AppSettings.fromJson(json), settings);
    expect(AppSettings.fromJson(const {}), const AppSettings());
    expect(
      AppSettings.fromJson(const {'themeMode': 'sepia'}).themeMode,
      ThemeMode.system,
    );
  });

  test('copyWith can clear the locale', () {
    const settings = AppSettings(localeTag: 'ja');
    expect(settings.copyWith(localeTag: () => null).localeTag, isNull);
    expect(settings.copyWith().localeTag, 'ja');
  });

  test('notifier persists changes', () async {
    final backend = FakeBackend()..install();
    addTearDown(backend.uninstall);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(settingsProvider.notifier);
    await notifier.setThemeMode(ThemeMode.light);
    await notifier.setLocaleTag('ja');
    await notifier.setVerboseLogging(true);

    final reloaded = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(reloaded.dispose);
    final settings = reloaded.read(settingsProvider);
    expect(settings.themeMode, ThemeMode.light);
    expect(settings.localeTag, 'ja');
    expect(settings.verboseLogging, isTrue);
    expect(backend.calls.map((call) => call.method), contains('setLoggingEnabled'));
  });

  test('locale tags map to supported locales', () {
    for (final locale in kalaoSupportedLocales) {
      expect(localeForTag(localeTag(locale)), locale);
    }
    expect(localeForTag('zh-Hant')?.scriptCode, 'Hant');
    expect(localeForTag('xx'), isNull);
    expect(localeForTag(null), isNull);
  });
}
