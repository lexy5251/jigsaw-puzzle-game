// Whimsy planning overview:
// 1. A WhimsyPlan says which cells of one puzzle are whimsy figures and
//    which figure each one is. It is never saved: it derives entirely from
//    the puzzle's seed, so resume and restart reproduce it exactly — the
//    same rule the knob cut already follows.
// 2. Counts scale with board size; shapes come from a per-image pool (scene
//    themed + the universal heart/star) with no shape dealt more than twice.
// 3. Whimsy cells are interior cells kept at Manhattan distance >= 3 from
//    each other, so no piece ever borders two whimsies — each neighbor
//    absorbs at most one figure flap.
//
// Pure and Flame-free so it unit-tests directly.

import 'dart:math';

import 'piece_shapes.dart';
import 'puzzle_catalog.dart';
import 'puzzle_logic.dart';
import 'whimsy_shapes.dart';

/// Which cells of a puzzle are whimsy figures, and which figure each is.
class WhimsyPlan {
  const WhimsyPlan(this.cells);

  /// The no-whimsies plan, used by every non-catalog grid (test fixtures,
  /// odd sizes) so existing behavior is untouched there.
  static const none = WhimsyPlan(<int, WhimsyShape>{});

  /// Piece index -> figure.
  final Map<int, WhimsyShape> cells;

  bool get isEmpty => cells.isEmpty;

  Set<int> get cellIndexes => cells.keys.toSet();

  /// If piece [index] borders a whimsy cell, that cell and which side the
  /// piece sits on.
  ///
  /// A piece may border at most ONE whimsy — the renderer grows one flap per
  /// piece, so a plan violating the Manhattan >= 3 spacing would leave part
  /// of the second whimsy's cell covered by no piece. [pickWhimsyCells]
  /// guarantees the spacing; the assert catches hand-built plans that don't.
  ({int whimsyIndex, WhimsySide side})? neighborOf(
    int index,
    int columns,
    int rows,
  ) {
    if (cells.isEmpty) return null;
    final row = index ~/ columns;
    final column = index % columns;
    final matches = [
      if (row + 1 < rows && cells.containsKey(index + columns))
        (whimsyIndex: index + columns, side: WhimsySide.above),
      if (row > 0 && cells.containsKey(index - columns))
        (whimsyIndex: index - columns, side: WhimsySide.below),
      if (column + 1 < columns && cells.containsKey(index + 1))
        (whimsyIndex: index + 1, side: WhimsySide.leftOf),
      if (column > 0 && cells.containsKey(index - 1))
        (whimsyIndex: index - 1, side: WhimsySide.rightOf),
    ];
    assert(
      matches.length <= 1,
      'piece $index borders ${matches.length} whimsies — '
      'whimsy cells must be at least Manhattan distance 3 apart',
    );
    return matches.firstOrNull;
  }
}

/// How many whimsies a board gets. One per ~25-30 pieces: frequent enough
/// to pace a long solve, rare enough that each find stays an event. Any
/// grid outside the shipped catalog sizes gets none.
int whimsyCountFor(int columns, int rows) => switch (columns * rows) {
  25 => 1,
  100 => 3,
  144 => 5,
  225 => 8,
  _ => 0,
};

/// Shapes allowed in any image, appended to every pool.
const universalWhimsyShapes = [WhimsyShape.heart, WhimsyShape.star];

/// Scene-themed shapes per catalog category. Two to three each: with the
/// universal pair that makes every pool 4-5 shapes, which is both enough
/// variety for 8 whimsies at two-of-a-kind max and few enough that a
/// repeated find reads as "found the pair".
const whimsyCategoryDefaults = <String, List<WhimsyShape>>{
  'landscapes': [WhimsyShape.sailboat, WhimsyShape.bird, WhimsyShape.leaf],
  'cozy': [WhimsyShape.cat, WhimsyShape.teacup, WhimsyShape.moon],
  'animals': [WhimsyShape.bird, WhimsyShape.fish, WhimsyShape.cat],
  'flowers': [WhimsyShape.butterfly, WhimsyShape.flower, WhimsyShape.leaf],
  'cities': [WhimsyShape.sailboat, WhimsyShape.bird, WhimsyShape.moon],
  'vintage_prints': [
    WhimsyShape.teacup,
    WhimsyShape.butterfly,
    WhimsyShape.flower,
  ],
  'food': [WhimsyShape.teacup, WhimsyShape.leaf, WhimsyShape.flower],
  'art': [WhimsyShape.snowflake, WhimsyShape.butterfly, WhimsyShape.flower],
  bonusCategoryId: [WhimsyShape.moon, WhimsyShape.snowflake],
  storyCategoryId: [WhimsyShape.sailboat, WhimsyShape.bird, WhimsyShape.flower],
};

/// Per-image replacements for the category default, for scenes whose theme
/// is finer than their category (a pond in `animals` wants fish, not cat).
/// An entry replaces the themed set; heart/star still join automatically.
const whimsyImageOverrides = <String, List<WhimsyShape>>{};

/// The shapes this image may hide: its themed set plus the universal pair.
List<WhimsyShape> whimsyPoolFor(PuzzleImage image) {
  final themed =
      whimsyImageOverrides[image.id] ??
      whimsyCategoryDefaults[image.categoryId] ??
      const <WhimsyShape>[];
  return [
    ...themed,
    for (final shape in universalWhimsyShapes)
      if (!themed.contains(shape)) shape,
  ];
}

/// Picks [count] interior cells, pairwise Manhattan distance >= 3 (no two
/// whimsies share a neighbor), spread by a seeded shuffle.
///
/// Two passes over the same shuffled order: first accept only cells at
/// Chebyshev distance >= 3 (a visually even spread), then top up accepting
/// Manhattan >= 3. The top-up always reaches the shipped quotas: every
/// accepted cell excludes at most the 13 cells of its Manhattan-2 ball, so
/// when no cell can be added the picked set has at least ceil(interior/13)
/// members — 1 / 5 / 8 / 13 for the 5x5 / 10x10 / 12x12 / 15x15 boards,
/// each at or above its quota of 1 / 3 / 5 / 8.
List<int> pickWhimsyCells({
  required int columns,
  required int rows,
  required int count,
  required Xorshift32 random,
}) {
  final interior = [
    for (var index = 0; index < columns * rows; index++)
      if (!isEdgePiece(index, columns, rows)) index,
  ];
  seededShuffle(interior, random);

  final picked = <int>[];
  bool accepts(int candidate, bool Function(int dr, int dc) farEnough) {
    for (final cell in picked) {
      final dr = (candidate ~/ columns - cell ~/ columns).abs();
      final dc = (candidate % columns - cell % columns).abs();
      if (!farEnough(dr, dc)) return false;
    }
    return true;
  }

  for (final cell in interior) {
    if (picked.length == count) return picked;
    if (accepts(cell, (dr, dc) => (dr > dc ? dr : dc) >= 3)) picked.add(cell);
  }
  for (final cell in interior) {
    if (picked.length == count) return picked;
    if (!picked.contains(cell) && accepts(cell, (dr, dc) => dr + dc >= 3)) {
      picked.add(cell);
    }
  }
  return picked;
}

/// Deals [count] shapes from [pool]: every shape once in shuffled order,
/// then seconds in the same order — so no shape appears more than twice.
List<WhimsyShape> dealWhimsyShapes({
  required List<WhimsyShape> pool,
  required int count,
  required Xorshift32 random,
}) {
  assert(count <= 2 * pool.length, 'pool too small for $count whimsies');
  final order = List.of(pool);
  seededShuffle(order, random);
  return [for (var i = 0; i < count; i++) order[i % order.length]];
}

/// The seed for a board's whimsy plan: the cut key on its own namespaced
/// stream. The 'whimsy.' prefix is what keeps figure placement independent
/// of the knob cut (which hashes the bare key) — it lives here, beside the
/// plan derivation, so no caller can re-derive a plan with the prefix
/// forgotten or misspelled. Changing it would relocate every existing
/// board's figures on resume.
int whimsySeedForKey(String cutKey) => shapeSeedForKey('whimsy.$cutKey');

/// The complete whimsy plan for one puzzle. Deterministic from [seed]
/// (see [whimsySeedForKey]): derive it from the save key (like the knob
/// cut) and resume, restart and the next-puzzle chain all see the same
/// figures with nothing persisted.
///
/// [countOverride] exists for preview harnesses that want to show more
/// figures than a real board would get.
WhimsyPlan whimsyPlanFor({
  required int columns,
  required int rows,
  required int seed,
  required List<WhimsyShape> pool,
  int? countOverride,
}) {
  // A small pool caps the count instead of over-dealing: no shape may
  // appear more than twice, so a two-shape pool can fill at most four
  // cells. Real catalog pools hold 4+ shapes (tested), so shipped boards
  // always reach their full quota — this guard is for direct constructions
  // and future images with unmapped categories.
  final quota = countOverride ?? whimsyCountFor(columns, rows);
  final count = min(quota, 2 * pool.length);
  if (count == 0) return WhimsyPlan.none;
  final random = Xorshift32(seed);
  final cells = pickWhimsyCells(
    columns: columns,
    rows: rows,
    count: count,
    random: random,
  );
  final shapes = dealWhimsyShapes(
    pool: pool,
    count: cells.length,
    random: random,
  );
  return WhimsyPlan({
    for (var i = 0; i < cells.length; i++) cells[i]: shapes[i],
  });
}
