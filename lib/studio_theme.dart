// The approved "riso chrome" look (owner-locked 2026-11-14, built out through
// mock rounds v17–v26b; palette doc: docs/ui-theme-colors.md, icon reference:
// docs/design/icon-set-final.png). This file is the single source of truth for
// its tokens; screens read colors via Theme.of(context) and Flame code uses
// StudioColors directly.

import 'package:flutter/material.dart';

import 'riso_icons.dart';

/// Status wording shared by every surface that names a run's state (size
/// sheet, category badges, daily card). The Maestro e2e flows assert these
/// exact texts — change them here and in .maestro/ together.
const statusInProgressLabel = 'In progress';
const statusCompletedLabel = 'Completed';

/// Design tokens. Hex values come from the locked v17 riso palette
/// (docs/ui-theme-colors.md) and must stay in sync with it.
abstract final class StudioColors {
  /// THE structure ink: borders, hard offset shadows, big titles, doodles.
  /// Owner-locked electric violet; the official fallback is cobalt
  /// 0xFF2B4ECB (with [structureDark] 0xFF223FA6) — swapping these two
  /// constants is the entire violet→cobalt change.
  static const structureInk = Color(0xFF7A4BFF);

  /// Darker structure shade for small-caps labels (eyebrows, section
  /// kickers) and "Completed" status words.
  static const structureDark = Color(0xFF5A34D6);

  /// Cream page background the whole app sits on.
  static const ground = Color(0xFFF6EEDF);

  /// Card / hero fill, a half-step lighter than the ground.
  static const card = Color(0xFFFDF8EC);

  /// Hard sticker shadow under cards — same ink as the border, zero blur
  /// (rule 2 of the dials: border + shadow in ONE ink = printed shape).
  /// NEVER use with a blurRadius: an opaque ink under blur reads as a
  /// saturated glow — blurred surfaces take [warmShadow].
  static const cardShadow = structureInk;

  /// The translucent warm shadow for the few surfaces that legitimately
  /// keep a soft BLURRED shadow (gameplay chrome, the completion card's
  /// float) — these sit outside the sticker system by the board-calm gate.
  static const warmShadow = Color(0x5928190A);

  /// Near-black text ink for titles, names and body. Never structure ink.
  static const ink = Color(0xFF26231C);

  /// Secondary text (counts, captions, inactive labels).
  static const mutedInk = Color(0xFF6B6657);

  /// Action color — Play/Begin buttons, active-tab underline, streak-filled
  /// pieces, "In progress" words. ACTIONS AND PROGRESS ONLY.
  static const tomato = Color(0xFFE34A33);

  /// Same-hue press shadow under tomato buttons.
  static const tomatoPress = Color(0xFFB23420);

  /// Text/icons on tomato.
  static const onTomato = Color(0xFFFFF7EC);

  /// The one "slipped ink" accent: big-title misprint shadow only.
  static const salmon = Color(0xFFEFA08E);

  /// Warm blush fill for selected chip/control states (v26b tray-row pick).
  static const chip = Color(0xFFF8E3DE);

  // ---- migration aliases (old studio roles → riso values). Call sites
  // move to the named riso tokens as each page is restyled; these keep the
  // in-between states compiling with sane colors.

  /// Old primary accent slot — now the tomato action ink.
  static const terracotta = tomato;

  /// Text/icons on the primary accent.
  static const onTerracotta = onTomato;

  /// Old secondary accent (story trail, gift CTA) — structure ink now owns
  /// the decorative uses; action uses are being moved to tomato per page.
  static const moss = structureInk;

  /// Old tertiary accent (completed states) — completed is structure-dark
  /// in the riso chrome.
  static const sunflower = structureDark;

  // ---- gameplay surfaces: deliberately UNCHANGED. The board and tray stay
  // quiet warm neutrals so the riso chrome never competes with the puzzle
  // (owner's board-calm gate).

  /// Flame board backdrop — the classic warm tan.
  static const board = Color(0xFFE7DABD);

  /// Board outline stroke on light backdrops (warm near-black at ~35%).
  static const boardOutline = Color(0x59423528);

  /// Board outline for dark backdrops — cream at the same ~35%.
  static const boardOutlineOnDark = Color(0x59FDF8EC);

  /// Piece tray wood; keeps a hint of translucency so dragged pieces
  /// passing under its edge stay faintly visible.
  static const tray = Color(0xF2E0CFA9);
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

/// Per-category personality: only two things change per category — the
/// accent and its tint. One table over the shared theme, never eight themes.
/// Under the riso chrome these color only small in-page touches (mascot
/// motifs); cards sit plain on the ground.
class StudioCategoryStyle {
  const StudioCategoryStyle({required this.accent, required this.tint});

  /// Saturated color for the category's swatch, kickers, and CTAs.
  // Nothing renders these since the category pages retired with layout B
  // (2026-11-19); the owner's curated palette and its catalog-sync test
  // stay for the next categorized surface.
  final Color accent;

  /// Pale wash for a category hero band, should one return.
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
  // Dusty rose — the vintage half of the approved sage/rose direction.
  'vintage_prints': StudioCategoryStyle(
    accent: Color(0xFFAD6A74),
    tint: Color(0xFFF2DCDC),
  ),
  // TEMP cinnamon, pending owner ruling — the warm ochre slot of the aged
  // palette, picked to stay distinct from cozy's terracotta and flowers'
  // mustard.
  'food': StudioCategoryStyle(
    accent: Color(0xFFA8784A),
    tint: Color(0xFFF0E3CF),
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
      accent: StudioColors.tomato,
      tint: StudioColors.chip,
    );

/// The app-wide theme: cream ground, violet structure, tomato actions.
/// Rokkitt (the shippable Rockwell cousin) carries headings and card names,
/// Nunito carries everything else.
ThemeData studioTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: StudioColors.tomato,
        brightness: Brightness.light,
      ).copyWith(
        primary: StudioColors.tomato,
        onPrimary: StudioColors.onTomato,
        secondary: StudioColors.structureInk,
        tertiary: StudioColors.structureDark,
        surface: StudioColors.card,
        onSurface: StudioColors.ink,
        surfaceContainerHighest: StudioColors.chip,
      );

  final base = ThemeData(colorScheme: scheme, fontFamily: 'Nunito');
  // Inactive nav/tab items: the muted text ink, one value for icons and
  // labels alike so the pieces can't drift apart. Active items are TEXT ink
  // with the tomato underline/icon doing the "on" work (the nav grammar).
  Color navItemColor(Set<WidgetState> states) =>
      states.contains(WidgetState.selected)
      ? StudioColors.ink
      : StudioColors.mutedInk;
  final textTheme = base.textTheme
      .apply(bodyColor: StudioColors.ink, displayColor: StudioColors.ink)
      .copyWith(
        bodySmall: base.textTheme.bodySmall?.copyWith(
          color: StudioColors.mutedInk,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontFamily: 'Rokkitt',
          fontWeight: FontWeight.w800,
          color: StudioColors.ink,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontFamily: 'Rokkitt',
          fontWeight: FontWeight.w700,
          color: StudioColors.ink,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontFamily: 'Rokkitt',
          fontWeight: FontWeight.w700,
          color: StudioColors.ink,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          fontFamily: 'Rokkitt',
          fontWeight: FontWeight.w700,
          color: StudioColors.ink,
        ),
      );

  return base.copyWith(
    scaffoldBackgroundColor: StudioColors.ground,
    textTheme: textTheme,
    // Every BackButton app-wide draws the hand-bent arrow instead of the
    // Material glyph (tests still find.byType(BackButton)).
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (context) => const RisoIcon(RisoGlyph.back),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: StudioColors.ground,
      foregroundColor: StudioColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: StudioColors.card,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: StudioColors.tomato,
        foregroundColor: StudioColors.onTomato,
        // Rounded rectangle, not a stadium — the mock's button shape; the
        // same-hue press shadow is painted by the sticker surfaces.
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    // Top tabs (My Puzzles): active word in text ink over a tomato
    // underline, the rest muted, no hairline divider on the wallpaper.
    tabBarTheme: TabBarThemeData(
      labelColor: StudioColors.ink,
      indicatorColor: StudioColors.tomato,
      unselectedLabelColor: StudioColors.mutedInk,
      dividerColor: Colors.transparent,
      labelStyle: const TextStyle(
        fontFamily: 'Nunito',
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
      unselectedLabelStyle: const TextStyle(
        fontFamily: 'Nunito',
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    ),
    // Bottom nav: items sit straight on the cream, no indicator pill — the
    // active item is the tomato-filled piece icon + ink label (home_shell
    // paints the underline), inactive ones in muted ink.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: StudioColors.ground,
      elevation: 0,
      indicatorColor: Colors.transparent,
      indicatorShape: const StadiumBorder(),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: navItemColor(states)),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: 'Nunito',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: navItemColor(states),
          // The active-tab grammar: a tomato underline under the word.
          decoration: states.contains(WidgetState.selected)
              ? TextDecoration.underline
              : TextDecoration.none,
          decorationColor: StudioColors.tomato,
          decorationThickness: 2.5,
        ),
      ),
    ),
  );
}
