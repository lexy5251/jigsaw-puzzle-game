// The bonus board: the current gift painting in the Collection tab. Every
// gift board is a 25-piece (5x5) puzzle — the same cut as the smallest
// playable size, so it needs no explanation. Earned pieces arrive LOOSE,
// scattered over the board (owner ruling, 2026-11-26): the player drags
// each one to its outlined spot, where it snaps in and reveals its
// jigsaw-shaped part of the real artwork. Spots follow a seeded scattered
// order so the subject stays a mystery longer; unearned cells stay
// canvas-ground with only their outlines drawn. Placing the last piece is
// the unlock moment: the painting clears, the title appears, and a Play
// button starts it.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'bonus_track.dart';
import 'game_haptics.dart';
import 'piece_shapes.dart';
import 'puzzle_catalog.dart';
import 'studio_surfaces.dart';
import 'studio_theme.dart';

/// The board's grid; columns x rows must equal [bonusBoardPieces].
const _boardColumns = 5;
const _boardRows = 5;

/// Plain-words line under the board. Shared with tests so the copy cannot
/// drift. "New painting", not "puzzle": replays and repeat sizes of a
/// finished painting earn nothing (the first-finish rule).
const bonusBoardHintText =
    'Every new painting you finish adds a piece — '
    'a 3-day streak adds one more.';

/// Replaces [bonusBoardHintText] while loose pieces wait on the board.
String bonusBoardLooseHintText(int loose) => loose == 1
    ? 'A new piece is here — drag it into place.'
    : '$loose new pieces are here — drag them into place.';

/// Caption under the finished board, beside the revealed title.
const bonusBoardCompletedCaption =
    'A new painting for your collection — yours to play.';

/// "N of 25 pieces" — the visible count and the board's semantics label.
String bonusBoardProgressText(int placedPieces) =>
    '$placedPieces of $bonusBoardPieces pieces';

/// The loose pieces the board offers right now: the next [count] cells of
/// the image's seeded reveal order that are not placed yet. The same rule
/// rebuilds the same loose set on every visit.
List<int> looseCellsFor({
  required PuzzleImage image,
  required Set<int> placedCells,
  required int count,
}) {
  final order = revealOrderFor(shapeSeedForKey('bonus-board.${image.id}'));
  return order.where((cell) => !placedCells.contains(cell)).take(count).toList();
}

/// Where a waiting piece rests, as an offset from its home cell in
/// fractions of the board's size. Seeded per cell so every piece keeps its
/// resting spot across visits, placements, and rebuilds.
@visibleForTesting
Offset bonusScatterFraction(int seed, int cell) {
  final rand = Xorshift32(seed ^ ((cell + 1) * 0x9E3779B9));
  double next() => rand.nextInt(10000) / 10000;
  final home = Offset(
    ((cell % _boardColumns) + 0.5) / _boardColumns,
    ((cell ~/ _boardColumns) + 0.5) / _boardRows,
  );
  for (var attempt = 0; attempt < 8; attempt++) {
    final rest = Offset(0.14 + 0.72 * next(), 0.14 + 0.72 * next());
    final offset = rest - home;
    // At least a cell away from home, so a fresh piece never reads as
    // already placed.
    if (offset.distance >= 0.22) {
      return offset;
    }
  }
  // Deterministic fallback: toward the opposite corner, clearly off-home.
  return Offset(home.dx < 0.5 ? 0.3 : -0.3, home.dy < 0.5 ? 0.3 : -0.3);
}

/// The Collection tab's hero card: kicker, the board in its frame, and
/// below it either progress + hint or — once the last piece is placed —
/// the revealed title with a Play button.
class BonusBoardCard extends StatefulWidget {
  const BonusBoardCard({
    super.key,
    required this.image,
    required this.placedCells,
    required this.looseCells,
    required this.onPlacementChanged,
    required this.onPlay,
    this.haptics,
  });

  final PuzzleImage image;

  /// Cells already snapped in; always below [bonusBoardPieces] on entry (a
  /// finished board rolled over before this card was built).
  final Set<int> placedCells;

  /// Earned pieces waiting on the board, in reveal order
  /// (see [looseCellsFor]).
  final List<int> looseCells;

  /// Fired after every snap with the full placed set, the 25th included —
  /// the owner of the stored record persists it (and rolls the board over).
  final ValueChanged<Set<int>> onPlacementChanged;

  /// Starts the finished gift painting from the celebration state.
  final VoidCallback onPlay;

  /// Snap/completion buzz; null keeps the device still (setting off).
  final GameHaptics? haptics;

  @override
  State<BonusBoardCard> createState() => _BonusBoardCardState();
}

class _BonusBoardCardState extends State<BonusBoardCard> {
  /// Local truth between parent reloads: props can lag behind snaps the
  /// player just made (the parent only re-reads stores on tab activation).
  late final Set<int> _placed = {...widget.placedCells};
  late List<int> _loose = [...widget.looseCells];

  /// The cell under the finger, and its current offset from home in
  /// board-size fractions; null offset means "resting at its scatter spot".
  int? _dragging;
  Offset? _dragFraction;

  bool get _completed => _placed.length >= bonusBoardPieces;

  int get _seed => shapeSeedForKey('bonus-board.${widget.image.id}');

  @override
  void didUpdateWidget(BonusBoardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Merge, never overwrite: fresh props may carry newly earned loose
    // pieces, while local state may carry snaps the stores echo back only
    // on the next load. (A different image arrives under a different key,
    // so state never crosses boards.)
    _placed.addAll(widget.placedCells);
    _loose = [
      for (final cell in widget.looseCells)
        if (!_placed.contains(cell)) cell,
    ];
    if (_dragging != null && !_loose.contains(_dragging)) {
      _dragging = null;
      _dragFraction = null;
    }
  }

  void _startDrag(int cell) => setState(() {
    _dragging = cell;
    _dragFraction = bonusScatterFraction(_seed, cell);
  });

  void _updateDrag(int cell, Offset delta, Size boardSize) {
    final fraction = _dragFraction;
    if (_dragging != cell || fraction == null) {
      return;
    }
    final moved =
        fraction +
        Offset(delta.dx / boardSize.width, delta.dy / boardSize.height);
    // Keep the piece's center on the board: home + offset stays inside.
    final home = Offset(
      ((cell % _boardColumns) + 0.5) / _boardColumns,
      ((cell ~/ _boardColumns) + 0.5) / _boardRows,
    );
    final center = home + moved;
    final clamped = Offset(
      center.dx.clamp(0.04, 0.96),
      center.dy.clamp(0.04, 0.96),
    );
    setState(() => _dragFraction = clamped - home);
  }

  void _endDrag(int cell, Size boardSize) {
    final fraction = _dragFraction;
    if (_dragging != cell || fraction == null) {
      return;
    }
    final offsetPx = Offset(
      fraction.dx * boardSize.width,
      fraction.dy * boardSize.height,
    );
    final snapRadius = 0.45 * (boardSize.width / _boardColumns);
    if (offsetPx.distance <= snapRadius) {
      _place(cell);
    } else {
      // AnimatedSlide glides it back to its scatter spot.
      setState(() {
        _dragging = null;
        _dragFraction = null;
      });
    }
  }

  void _place(int cell) {
    setState(() {
      _placed.add(cell);
      _loose.remove(cell);
      _dragging = null;
      _dragFraction = null;
    });
    // The last piece gets the completion pulse, like the game board.
    if (_completed) {
      widget.haptics?.complete();
    } else {
      widget.haptics?.snap();
    }
    widget.onPlacementChanged({..._placed});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PaintedCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'BONUS PUZZLE',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: StudioColors.structureDark,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            identifier: 'bonus-board-${widget.image.id}',
            container: true,
            // The title stays out of the label until the board completes:
            // the picture is a surprise for screen-reader players too.
            label: _completed
                ? 'Bonus picture finished: ${widget.image.title}'
                : 'Bonus picture: ${bonusBoardProgressText(_placed.length)}'
                      '${_loose.isEmpty ? '' : ', ${_loose.length} to place'}',
            child: AspectRatio(
              aspectRatio: 1,
              child: FramedArt(child: _board()),
            ),
          ),
          const SizedBox(height: 12),
          if (_completed) ..._completedInfo(theme) else ..._progressInfo(theme),
        ],
      ),
    );
  }

  List<Widget> _progressInfo(ThemeData theme) => [
    ExcludeSemantics(
      // The board's label already reads the counts.
      child: Text(
        bonusBoardProgressText(_placed.length),
        textAlign: TextAlign.center,
        style: theme.textTheme.titleSmall,
      ),
    ),
    const SizedBox(height: 2),
    Text(
      _loose.isEmpty ? bonusBoardHintText : bonusBoardLooseHintText(_loose.length),
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall,
    ),
  ];

  List<Widget> _completedInfo(ThemeData theme) => [
    Text(
      widget.image.title,
      textAlign: TextAlign.center,
      style: theme.textTheme.titleMedium,
    ),
    const SizedBox(height: 2),
    Text(
      bonusBoardCompletedCaption,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall,
    ),
    const SizedBox(height: 10),
    Semantics(
      identifier: 'bonus-board-play',
      child: FilledButton(
        onPressed: widget.onPlay,
        child: const Text('Play this painting'),
      ),
    ),
  ];

  Widget _board() => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final seed = _seed;
      // The dragged piece renders last, so it rides over its siblings.
      final looseOnTop = [
        for (final cell in _loose)
          if (cell != _dragging) cell,
        ?_dragging,
      ];
      return Stack(
        fit: StackFit.expand,
        children: [
          // The art layers say nothing a screen reader needs: the board's
          // own label carries the progress.
          ExcludeSemantics(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: StudioColors.ground),
                // Each layer draws the full image clipped to its piece, so
                // a knob reaching into a neighbor cell shows exactly that
                // neighbor's bit of artwork.
                for (final cell in _placed)
                  ClipPath(
                    clipper: _BonusPieceClipper(pieceIndex: cell, seed: seed),
                    child: _pieceImage(),
                  ),
                CustomPaint(
                  painter: _PieceOutlinePainter(revealed: _placed, seed: seed),
                ),
                for (final cell in looseOnTop)
                  AnimatedSlide(
                    offset: _offsetFraction(cell),
                    // Zero while dragging: the piece must track the finger,
                    // not chase it.
                    duration: _dragging == cell
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: CustomPaint(
                      painter: _LoosePieceShadowPainter(cell: cell, seed: seed),
                      foregroundPainter: _LoosePieceEdgePainter(
                        cell: cell,
                        seed: seed,
                      ),
                      child: ClipPath(
                        clipper: _BonusPieceClipper(pieceIndex: cell, seed: seed),
                        child: _pieceImage(),
                      ),
                    ),
                  ),
                // The unlock moment: the seams fade away and the clean
                // painting takes the frame.
                AnimatedOpacity(
                  opacity: _completed ? 1 : 0,
                  duration: const Duration(milliseconds: 600),
                  child: _completed ? _pieceImage() : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          if (!_completed)
            for (final cell in looseOnTop) _looseHitBox(cell, size),
        ],
      );
    },
  );

  /// The piece's current offset from home in board fractions.
  Offset _offsetFraction(int cell) => _dragging == cell
      ? _dragFraction ?? Offset.zero
      : bonusScatterFraction(_seed, cell);

  /// An invisible draggable region over the loose piece. Visuals stay in
  /// the art stack; this layer owns gestures and semantics. Touches are
  /// gated by the piece's real outline — scattered pieces overlap, and a
  /// box that swallowed its whole bounds would steal its neighbors' drags.
  Widget _looseHitBox(int cell, Size boardSize) {
    final cellWidth = boardSize.width / _boardColumns;
    final cellHeight = boardSize.height / _boardRows;
    final fraction = _offsetFraction(cell);
    final overhang = knobOverhangFraction * cellWidth;
    final rect = Rect.fromLTWH(
      (cell % _boardColumns) * cellWidth + fraction.dx * boardSize.width,
      (cell ~/ _boardColumns) * cellHeight + fraction.dy * boardSize.height,
      cellWidth,
      cellHeight,
    ).inflate(overhang);
    return Positioned.fromRect(
      rect: rect,
      child: _PathHitRegion(
        path: _pieceCellPath(
          Size(cellWidth, cellHeight),
          cell,
          _seed,
        ).shift(Offset(overhang, overhang)),
        child: Semantics(
        identifier: 'bonus-loose-piece-$cell',
        button: true,
        label: 'New bonus piece — drag it to its empty spot',
          // The assistive-tech path: a double-tap places the piece
          // outright, so the board never demands a drag gesture.
          onTap: () => _place(cell),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => _startDrag(cell),
            onPanUpdate: (details) =>
                _updateDrag(cell, details.delta, boardSize),
            onPanEnd: (_) => _endDrag(cell, boardSize),
            onPanCancel: () => _endDrag(cell, boardSize),
          ),
        ),
      ),
    );
  }

  Widget _pieceImage() => Image.asset(
    widget.image.assetPath,
    fit: BoxFit.cover,
    cacheWidth: TiltedPhotoCard.thumbnailCacheWidth,
    // No title fallback here — a failed decode must not spoil the
    // surprise; the ground simply stays bare.
    errorBuilder: (context, _, _) => const SizedBox.shrink(),
  );
}

/// The order pieces appear in: a seeded shuffle of the board's cells, so
/// early pieces land scattered across the picture instead of filling it
/// row by row (which would hand over the subject too early). Stable across
/// sessions — same xorshift as the piece cutter, for the same reason
/// dart:math Random is banned for anything persistent-feeling.
@visibleForTesting
List<int> revealOrderFor(int seed) {
  // Shares the cutter's generator and shuffle on purpose: this order is
  // persistent-feeling (a board that re-shuffled between visits would read
  // as broken), and seededShuffle draws exactly like the inline loop this
  // replaced — existing boards keep their reveal order.
  final order = [for (var i = 0; i < bonusBoardPieces; i++) i];
  seededShuffle(order, Xorshift32(seed));
  return order;
}

/// Builds the outline of piece [index] in its own cell's coordinates
/// (knobs reach outside the [cellSize] rectangle).
Path _pieceCellPath(Size cellSize, int index, int seed) {
  final grid = PieceShapeGrid.generate(
    columns: _boardColumns,
    rows: _boardRows,
    seed: seed,
  );
  return buildPiecePath(
    shape: grid.shapeAtIndex(index),
    width: cellSize.width,
    height: cellSize.height,
  );
}

/// Builds the outline of piece [index] on the 5x5 board filling [size].
Path _piecePath(Size size, int index, int seed) {
  final cellWidth = size.width / _boardColumns;
  final cellHeight = size.height / _boardRows;
  return _pieceCellPath(Size(cellWidth, cellHeight), index, seed).shift(
    Offset(
      (index % _boardColumns) * cellWidth,
      (index ~/ _boardColumns) * cellHeight,
    ),
  );
}

/// Confines a child's hit tests to [path] (in this box's coordinates):
/// touches outside it fall through to whatever lies beneath — a sibling
/// piece, or the scrollable around the board.
class _PathHitRegion extends SingleChildRenderObjectWidget {
  const _PathHitRegion({required this.path, super.child});

  final Path path;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPathHitRegion(path);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPathHitRegion renderObject,
  ) => renderObject.path = path;
}

class _RenderPathHitRegion extends RenderProxyBox {
  _RenderPathHitRegion(this._path);

  Path _path;

  set path(Path value) => _path = value;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_path.contains(position)) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}

class _BonusPieceClipper extends CustomClipper<Path> {
  const _BonusPieceClipper({required this.pieceIndex, required this.seed});

  final int pieceIndex;
  final int seed;

  @override
  Path getClip(Size size) => _piecePath(size, pieceIndex, seed);

  @override
  bool shouldReclip(_BonusPieceClipper oldClipper) =>
      oldClipper.pieceIndex != pieceIndex || oldClipper.seed != seed;
}

class _PieceOutlinePainter extends CustomPainter {
  const _PieceOutlinePainter({required this.revealed, required this.seed});

  final Set<int> revealed;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    // Waiting pieces get a soft ink wash so they read as empty slots, not
    // bare mat; every piece gets its outline so the cut is visible.
    final slotFill = Paint()
      ..color = StudioColors.ink.withValues(alpha: 0.06);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = StudioColors.ink.withValues(alpha: 0.18);
    for (var piece = 0; piece < bonusBoardPieces; piece++) {
      final path = _piecePath(size, piece, seed);
      if (!revealed.contains(piece)) {
        canvas.drawPath(path, slotFill);
      }
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(_PieceOutlinePainter oldDelegate) =>
      oldDelegate.seed != seed ||
      oldDelegate.revealed.length != revealed.length;
}

/// A soft drop under a loose piece, so it floats over the board instead of
/// reading as already placed.
class _LoosePieceShadowPainter extends CustomPainter {
  const _LoosePieceShadowPainter({required this.cell, required this.seed});

  final int cell;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawShadow(
      _piecePath(size, cell, seed),
      StudioColors.ink,
      5,
      false,
    );
  }

  @override
  bool shouldRepaint(_LoosePieceShadowPainter oldDelegate) =>
      oldDelegate.cell != cell || oldDelegate.seed != seed;
}

/// A firm edge on a loose piece — the placed pieces only wear the board's
/// soft shared seams.
class _LoosePieceEdgePainter extends CustomPainter {
  const _LoosePieceEdgePainter({required this.cell, required this.seed});

  final int cell;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = StudioColors.ink.withValues(alpha: 0.5);
    canvas.drawPath(_piecePath(size, cell, seed), stroke);
  }

  @override
  bool shouldRepaint(_LoosePieceEdgePainter oldDelegate) =>
      oldDelegate.cell != cell || oldDelegate.seed != seed;
}
