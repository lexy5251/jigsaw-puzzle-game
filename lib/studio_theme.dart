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

  /// Soft warm shadow under painted cards (mockup: rgba(40,25,10,.35)).
  static const cardShadow = Color(0x5928190A);

  /// Light mat ring painted over framed artwork.
  static const matRing = Color(0x8CFFFFFF);

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

  /// Board outline for dark backdrops — cream at the same ~35%; the ink
  /// stroke composites to near-invisible on slate and charcoal.
  static const boardOutlineOnDark = Color(0x59FDF8EC);

  /// Piece tray wood; keeps a hint of translucency so dragged pieces
  /// passing under its edge stay faintly visible.
  static const tray = Color(0xF2E0CFA9);

  /// Card ground variants — some cards sit on blush or moss instead of
  /// linen ("cards may sit on cream/blush/moss grounds").
  static const blushGround = Color(0xFFF4DDCD);
  static const mossGround = Color(0xFFE5E4C8);
}

/// One selectable board backdrop. Dark fills need their own outline color:
/// the default ink stroke all but disappears on them.
@immutable
class BoardColorOption {
  const BoardColorOption({
    required this.id,
    required this.label,
    required this.background,
    required this.outline,
  });

  /// Persisted in the settings blob — never rename an existing id.
  final String id;

  /// Shown in the picker's Semantics labels; keep constant for e2e tests.
  final String label;

  final Color background;
  final Color outline;
}

/// The player-selectable board backdrops: a light→dark ramp of muted tones
/// so both dark and white-heavy photos can get contrast. Order is the
/// picker's display order.
const boardColorOptions = <BoardColorOption>[
  BoardColorOption(
    id: 'linen',
    label: 'Linen',
    background: Color(0xFFF3EBD9),
    outline: StudioColors.boardOutline,
  ),
  defaultBoardColorOption,
  BoardColorOption(
    id: 'taupe',
    label: 'Taupe',
    background: Color(0xFFBCAF99),
    outline: StudioColors.boardOutline,
  ),
  BoardColorOption(
    id: 'sage',
    label: 'Sage',
    background: Color(0xFFA5AB8B),
    outline: StudioColors.boardOutline,
  ),
  BoardColorOption(
    id: 'slate',
    label: 'Slate',
    background: Color(0xFF75808B),
    outline: StudioColors.boardOutlineOnDark,
  ),
  BoardColorOption(
    id: 'charcoal',
    label: 'Charcoal',
    // Near-black with a warm tint (owner's pick from the 11-10 pick sheet,
    // candidate C) — "not exact black, but darker".
    background: Color(0xFF221D17),
    outline: StudioColors.boardOutlineOnDark,
  ),
];

/// The classic warm tan the board has always used.
const defaultBoardColorOption = BoardColorOption(
  id: 'tan',
  label: 'Warm tan',
  background: StudioColors.board,
  outline: StudioColors.boardOutline,
);

/// Unknown ids (old installs, future removals) degrade to the default
/// instead of crashing the game screen.
BoardColorOption boardColorOptionFor(String id) => boardColorOptions
    .firstWhere((option) => option.id == id, orElse: () => defaultBoardColorOption);

/// Per-category personality (mockup section F): only two things change per
/// category — the accent and its tint. One table over the shared theme,
/// never six themes.
class StudioCategoryStyle {
  const StudioCategoryStyle({required this.accent, required this.tint});

  /// Saturated color for the category's swatch, kickers, and CTAs.
  final Color accent;

  /// Pale wash for the category's hero band (used by the category screens
  /// when their layout lands).
  final Color tint;
}

/// Keys match `PuzzleCategory.id` in puzzle_catalog.dart; a test keeps the
/// two in sync.
const studioCategoryStyles = <String, StudioCategoryStyle>{
  'landscapes': StudioCategoryStyle(
    accent: Color(0xFF7B8456),
    tint: Color(0xFFDFE3C9),
  ),
  'cozy': StudioCategoryStyle(
    accent: Color(0xFFC06A45),
    tint: Color(0xFFF0D9C8),
  ),
  'animals': StudioCategoryStyle(
    accent: Color(0xFFC98977),
    tint: Color(0xFFF4DDD3),
  ),
  'flowers': StudioCategoryStyle(
    accent: Color(0xFFC9962E),
    tint: Color(0xFFF0E4BC),
  ),
  'cities': StudioCategoryStyle(
    accent: Color(0xFF71908B),
    tint: Color(0xFFDAE3DF),
  ),
  'art': StudioCategoryStyle(
    accent: Color(0xFF9D6A80),
    tint: Color(0xFFEAD9E0),
  ),
};

/// Falls back to the app-wide accent so an unstyled new category degrades
/// gracefully instead of crashing the select screen.
StudioCategoryStyle categoryStyleFor(String categoryId) =>
    studioCategoryStyles[categoryId] ??
    const StudioCategoryStyle(
      accent: StudioColors.terracotta,
      tint: StudioColors.chip,
    );

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
        bodySmall: base.textTheme.bodySmall?.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.6),
        ),
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
