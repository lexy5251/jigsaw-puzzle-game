// The approved "Studio — Linen & Terracotta" look (see the APPROVED style
// section in docs/puzzle-game-mvp-plan.md). This file is the single source
// of truth for its tokens; screens read colors via Theme.of(context) and
// Flame code uses StudioColors directly.

import 'package:flutter/material.dart';

/// Design tokens. Hex values come from the approved mockup
/// (docs/design/brushwork-mockup.html) and must stay in sync with the plan.
abstract final class StudioColors {
  /// Warm canvas the whole app sits on.
  static const ground = Color(0xFFF0E7D2);

  /// Linen card surface.
  static const card = Color(0xFFF9F3E3);

  /// Warm near-black used for all text and icons.
  static const ink = Color(0xFF423528);

  /// Primary accent.
  static const terracotta = Color(0xFFBD6A48);

  /// Text/icons on terracotta.
  static const onTerracotta = Color(0xFFFDF8EC);

  /// Secondary accent.
  static const moss = Color(0xFF7D8A5A);

  /// Tertiary accent (completed states, highlights).
  static const sunflower = Color(0xFFD9A33F);

  /// Soft fill for chips and selected states.
  static const chip = Color(0xFFE4D7BA);

  /// Flame board backdrop — a step below [ground] so the play area reads
  /// as its own zone without a hard border.
  static const board = Color(0xFFE7DABD);

  /// Board outline stroke: ink at ~35%, visible on the light backdrop
  /// (the old translucent white disappeared on it).
  static const boardOutline = Color(0x59423528);

  /// Piece tray wood; keeps a hint of translucency so dragged pieces
  /// passing under its edge stay faintly visible.
  static const tray = Color(0xF2E0CFA9);
}

/// The app-wide theme: light, warm, rounded. Fredoka carries headings,
/// Nunito carries everything else.
ThemeData studioTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: StudioColors.terracotta,
        brightness: Brightness.light,
      ).copyWith(
        primary: StudioColors.terracotta,
        onPrimary: StudioColors.onTerracotta,
        secondary: StudioColors.moss,
        tertiary: StudioColors.sunflower,
        surface: StudioColors.card,
        onSurface: StudioColors.ink,
        surfaceContainerHighest: StudioColors.chip,
      );

  final base = ThemeData(colorScheme: scheme, fontFamily: 'Nunito');
  final textTheme = base.textTheme
      .apply(bodyColor: StudioColors.ink, displayColor: StudioColors.ink)
      .copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontFamily: 'Fredoka',
          fontWeight: FontWeight.w600,
          color: StudioColors.ink,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontFamily: 'Fredoka',
          fontWeight: FontWeight.w600,
          color: StudioColors.ink,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: StudioColors.ink,
        ),
      );

  return base.copyWith(
    scaffoldBackgroundColor: StudioColors.ground,
    textTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: StudioColors.ground,
      foregroundColor: StudioColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: StudioColors.card,
      elevation: 1,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: StudioColors.terracotta,
        foregroundColor: StudioColors.onTerracotta,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: StudioColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}
