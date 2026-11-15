// Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
// LGPL-3.0-only. Modified for Kalao.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kalao/l10n/app_localizations.dart';
import 'package:kalao/providers/settings_provider.dart';
import 'package:kalao/screens/settings/settings_tab.dart';
import 'package:kalao/theme/app_tokens.dart';

/// First-run setup: language and theme. Later milestones add permission
/// steps (notifications, microphone) where those features need them.
class SetupScreen extends ConsumerWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppTokens.maxContentWidth,
            ),
            child: ListView(
              padding: const EdgeInsets.all(AppTokens.space24),
              children: [
                const SizedBox(height: AppTokens.space32),
                ExcludeSemantics(
                  child: Icon(
                    Icons.mic,
                    size: 72,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: AppTokens.space24),
                Text(
                  l10n.setupWelcomeTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: AppTokens.space12),
                Text(
                  l10n.setupWelcomeBody,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppTokens.space32),
                const Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [LanguageTile(), ThemeModeTile()]),
                ),
                const SizedBox(height: AppTokens.space32),
                FilledButton(
                  onPressed: () =>
                      ref.read(settingsProvider.notifier).completeSetup(),
                  child: Text(l10n.setupGetStarted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
