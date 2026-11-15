// Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
// LGPL-3.0-only. Modified for Kalao.
import 'package:flutter/material.dart';

/// Design tokens shared by every screen. Widgets read spacing and radii from
/// here and colours from `Theme.of(context).colorScheme`, never literals.
class AppTokens {
  AppTokens._();

  /// Kalao coral; the seed when Material You colours are off or unavailable.
  static const Color brandSeed = Color(0xFFE8505B);

  static const double space2 = 2;
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space24 = 24;
  static const double space32 = 32;

  static const double radiusSmall = 8;
  static const double radiusMedium = 12;
  static const double radiusLarge = 20;
  static const double radiusFull = 999;

  /// Readable line length for long text on tablets.
  static const double maxContentWidth = 720;

  static const Duration motionShort = Duration(milliseconds: 150);
  static const Duration motionMedium = Duration(milliseconds: 250);
}
