// Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
// LGPL-3.0-only. Modified for Kalao.
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kalao/constants/app_info.dart';
import 'package:kalao/l10n/app_localizations.dart';
import 'package:kalao/l10n/supported_locales.dart';
import 'package:kalao/providers/settings_provider.dart';
import 'package:kalao/screens/main_shell.dart';
import 'package:kalao/screens/settings/log_screen.dart';
import 'package:kalao/screens/setup_screen.dart';
import 'package:kalao/theme/app_theme.dart';

/// First screen for the current app state, as in Mornye's
/// `initialLocationForAppState`. Later milestones add the tutorial and
/// What's New steps between setup and the shell.
String initialLocationForAppState({required bool setupCompleted}) =>
    setupCompleted ? '/' : '/setup';

final routerProvider = Provider<GoRouter>((ref) {
  final setupCompleted = ref.watch(
    settingsProvider.select((settings) => settings.setupCompleted),
  );
  final router = GoRouter(
    initialLocation: initialLocationForAppState(setupCompleted: setupCompleted),
    routes: [
      GoRoute(path: '/', builder: (context, state) => const MainShell()),
      GoRoute(path: '/setup', builder: (context, state) => const SetupScreen()),
      GoRoute(
        path: '/settings/logs',
        builder: (context, state) => const LogScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class KalaoApp extends ConsumerWidget {
  const KalaoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final useDynamic = settings.useDynamicColor;
        final ColorScheme light = useDynamic && lightDynamic != null
            ? lightDynamic
            : AppTheme.seededScheme(Brightness.light);
        final ColorScheme dark = useDynamic && darkDynamic != null
            ? darkDynamic
            : AppTheme.seededScheme(Brightness.dark);
        return MaterialApp.router(
          title: AppInfo.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(light),
          darkTheme: AppTheme.build(dark),
          themeMode: settings.themeMode,
          locale: localeForTag(settings.localeTag),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          routerConfig: router,
        );
      },
    );
  }
}
