// Game screen overview:
// 1. Receives the selected puzzle image and grid size.
// 2. Holds the running game for as long as this puzzle screen is open.
// 3. Displays the puzzle using Flame's GameWidget.
// 4. Keeps a back button to return to puzzle selection.
// 5. When the game reports completion, records it permanently and blurs
//    the finished board behind the completion card, timed to appear as the
//    in-game glow fades. The card offers the category's next unfinished
//    painting as one-tap "Next puzzle" (the screen pops with that painting
//    as its result and the launcher chains into it), with "Back to
//    gallery" as the exit.
// JigsawGame handles the puzzle gameplay.

import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'completion_card.dart';
import 'daily_puzzle.dart';
import 'daily_streak.dart';
import 'game_sounds.dart';
import 'jigsaw_game.dart';
import 'puzzle_catalog.dart';
import 'puzzle_completion.dart';
import 'puzzle_logic.dart';
import 'puzzle_save.dart';
import 'studio_surfaces.dart';
import 'studio_theme.dart';

/// Hosts one running puzzle.
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.image,
    required this.size,
    this.soundsFactory,
    this.clock,
    this.startedDay,
    this.settings = const AppSettings(),
    this.catalog = puzzleCatalog,
    this.trayColumns = trayVisibleColumns,
    this.trayMaxThumbnailHeight = trayThumbnailHeightCap,
  });

  final PuzzleImage image;
  final PuzzleSize size;

  /// Where "Next puzzle" looks for the category's other paintings; tests
  /// supply a small fixture catalog.
  final List<PuzzleImage> catalog;

  /// Player preferences, read by the caller before this screen opens.
  final AppSettings settings;

  /// Each game owns its audio, so restarts need a fresh instance.
  /// When omitted the screen uses the real app sounds; tests supply fakes.
  final GameSounds Function()? soundsFactory;

  /// Returns "now"; tests fix the date to make the daily puzzle
  /// deterministic. Defaults to [DateTime.now].
  final DateTime Function()? clock;

  /// Tray piece density, forwarded to the game; the preview harness renders
  /// candidate densities with it.
  final int trayColumns;

  /// Optional tray piece height ceiling, forwarded to the game; the preview
  /// harness renders the large-screen candidates with it.
  final double? trayMaxThumbnailHeight;

  /// Day key stamped on a FRESH board's save — the day the player committed
  /// to this run. The select screen passes the day its card was tapped, so
  /// a size sheet left open across midnight cannot shift the credited day.
  /// Defaults to the day this screen opens.
  final String? startedDay;

  /// Delay between the last piece locking and the completion card's
  /// reveal — the in-game glow (0.9s) plays out first. Tests pump this
  /// exact duration, so keep them on this constant.
  static const completionRevealDelay = Duration(milliseconds: 950);

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  static const _saveStore = SharedPreferencesSaveStore();
  static const _settingsStore = SharedPreferencesAppSettingsStore();

  bool _showCompletionCard = false;
  bool _restarting = false;

  /// The "Next puzzle" offer; null until completion resolves it (and stays
  /// null when the rest of the category is already done at this size).
  PuzzleImage? _nextImage;

  Timer? _completionTimer;
  Timer? _revealFallbackTimer;
  bool _edgesOnly = false;
  late bool _showGhostPreview = widget.settings.ghostPreviewDefault;
  late BoardColorOption _boardColor = boardColorOptionFor(
    widget.settings.boardColorId,
  );

  /// Null until the game finishes loading, then whether it resumed a save.
  bool? _resumed;

  late JigsawGame _game = _createGame();

  DateTime get _now => (widget.clock ?? DateTime.now)();

  String get _saveKey => puzzleSaveKey(
    imageId: widget.image.id,
    columns: widget.size.columns,
    rows: widget.size.rows,
  );

  JigsawGame _createGame() {
    late final JigsawGame game;
    game = JigsawGame(
      imageAsset: widget.image.fileName,
      columns: widget.size.columns,
      rows: widget.size.rows,
      // The game owns and disposes its sounds, so a restart needs a fresh
      // instance — hence created here, not stored on the state.
      sounds:
          widget.soundsFactory?.call() ??
          FlameAudioSounds(volumeScale: widget.settings.effectsVolume),
      saveStore: _saveStore,
      saveKey: _saveKey,
      startedDay: widget.startedDay ?? dayKey(_now),
      trayColumns: widget.trayColumns,
      trayMaxThumbnailHeight: widget.trayMaxThumbnailHeight,
      onCompleted: () => _onPuzzleCompleted(game),
      onBoardLoaded: (resumed) {
        if (mounted && !_restarting && identical(_game, game)) {
          setState(() => _resumed = resumed);
        }
      },
    );
    // All three setters are safe before the game loads: they store the
    // value, and loading applies it. Setting the color here is what keeps
    // it across restarts and "Next puzzle" chains (each builds a new game).
    game.setEdgesOnlyFilter(_edgesOnly);
    game.setGhostPreview(_showGhostPreview);
    game.setBoardColor(_boardColor);
    return game;
  }

  Future<void> _showBoardColorPicker() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: StudioColors.ground,
    // No scrim: the sheet exists to compare swatches against the live
    // board, so the board must keep its true colors while it's open.
    barrierColor: Colors.transparent,
    builder: (_) => _BoardColorPicker(
      selectedId: _boardColor.id,
      onSelected: _selectBoardColor,
    ),
  );

  void _selectBoardColor(BoardColorOption option) {
    // setState so the GameWidget rebuilds — Flame only re-reads
    // backgroundColor() during the widget build (see setBoardColor).
    setState(() {
      _boardColor = option;
      _game.setBoardColor(option);
    });
    unawaited(_persistBoardColor(option.id));
  }

  Future<void> _persistBoardColor(String id) async {
    // Fresh read before writing: the blob also carries volume/ghost prefs,
    // and widget.settings may be stale against SettingsScreen edits.
    final current = await _settingsStore.load();
    await _settingsStore.save(current.copyWith(boardColorId: id));
  }

  /// Confirms, forgets the stored progress, and boots a fresh board.
  Future<void> _confirmRestart() async {
    if (_restarting) return;
    final restart = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start over?'),
        content: const Text("This puzzle's progress will be cleared."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start over'),
          ),
        ],
      ),
    );
    if (restart != true || !mounted || _restarting) {
      return;
    }
    _completionTimer?.cancel();
    _revealFallbackTimer?.cancel();
    setState(() {
      _restarting = true;
      _showCompletionCard = false;
      _nextImage = null;
    });
    // Stop new writes before awaiting any old ones. An already-held finger
    // can still deliver a release after the dialog closes.
    await _game.discardProgress();
    if (!mounted) {
      return;
    }
    setState(() {
      _resumed = null;
      _restarting = false;
      // The GameWidget's ObjectKey ensures the old widget is disposed too.
      _game = _createGame();
    });
  }

  /// "resumed" vs "new puzzle" lets the Maestro flow verify that reopening
  /// actually restored the save instead of silently starting over.
  String get _boardSemanticsLabel => switch (_resumed) {
    null => 'Puzzle board',
    true => 'Puzzle board, resumed',
    false => 'Puzzle board, new puzzle',
  };

  Future<bool> _onPuzzleCompleted(JigsawGame game) async {
    if (!mounted || _restarting || !identical(_game, game)) return false;
    // The card reveals when BOTH the glow delay and its data (the
    // next-puzzle offer) are ready: the delay is armed first so storage
    // latency hides inside the 0.9s glow instead of stacking after it, and
    // the card still never appears with an unresolved hero button (the old
    // button-swap race).
    var delayElapsed = false;
    var dataReady = false;
    _completionTimer?.cancel();
    _revealFallbackTimer?.cancel();
    _completionTimer = Timer(GameScreen.completionRevealDelay, () {
      delayElapsed = true;
      if (dataReady) {
        _revealCompletionCard(game);
      } else {
        // Storage answers in microseconds normally; if it wedges, still
        // give the player the card (and its exit) instead of a dead end.
        _revealFallbackTimer = Timer(
          const Duration(seconds: 2),
          () => _revealCompletionCard(game),
        );
      }
    });

    final next = await _findNextPuzzle();
    // The reveal depends only on the next-puzzle offer — it must not wait
    // on the record writes below, or a wedged write would hold the card
    // (and reassign _nextImage late, resurrecting the button-swap race on
    // the fallback path).
    if (!_restarting && identical(_game, game)) {
      _nextImage = next;
    }
    dataReady = true;
    if (delayElapsed) {
      _revealFallbackTimer?.cancel();
      _revealCompletionCard(game);
    }

    // The record writes run UNCONDITIONALLY from here: a completion the
    // player saw must be stored even if a restart or a chained replacement
    // lands while the read above was in flight — only the UI fields are
    // guarded. The streak write stays sequenced ahead of the completion
    // write so their reads cannot interleave in the preferences cache.
    final dailyRecorded = await _recordDailyCompletion(game.runStartedDay);

    // The game keeps its progress save until BOTH records are stored, so a
    // failed daily credit gets the same retry as a failed completion write:
    // resuming the finished save retries it. A day-late retry still credits via
    // the resumed-save grace, and re-marking an already-stored day is a
    // no-op success.
    final completionRecorded = await const SharedPreferencesCompletionStore()
        .markCompleted(
          puzzleCompletionKey(
            imageId: widget.image.id,
            columns: widget.size.columns,
            rows: widget.size.rows,
          ),
        );
    return dailyRecorded && completionRecorded;
  }

  /// Reveals the completion card (idempotent: a fallback reveal followed by
  /// late-arriving data just rebuilds the card with the data filled in).
  void _revealCompletionCard(JigsawGame game) {
    if (mounted && !_restarting && identical(_game, game)) {
      // The board is static by now (the glow self-removed at 0.9s), but a
      // running Flame loop repaints every frame, forcing the card's
      // backdrop blur to re-blur the whole screen each vsync. No resume
      // needed: every exit pops the route, and restart boots a fresh game.
      game.pauseEngine();
      setState(() => _showCompletionCard = true);
    }
  }

  /// Finishing a daily image at any size blooms the pot of the day the run
  /// began — the save's stamp (see [dailyCreditDay]). Returns false when a
  /// credit was due but could not be stored. The bloom itself is only shown
  /// on the home windowsill — the completion card stays celebration-free
  /// (owner's UI-4 ruling).
  Future<bool> _recordDailyCompletion(String? startedDay) async {
    final day = dailyCreditDay(
      widget.image.id,
      _now,
      startedDay: startedDay,
      catalog: widget.catalog,
    );
    if (day == null) {
      return true;
    }
    const store = SharedPreferencesDailyStreakStore();
    if ((await store.completedDays()).contains(day)) {
      return true;
    }
    return store.markCompleted(day);
  }

  /// The category's next painting not yet completed at this grid size.
  /// Candidates are probed lazily in [nextPuzzleAfter]'s own order —
  /// typically one read — instead of prefetching the whole category, which
  /// also keeps the candidate-ordering rule in a single place.
  Future<PuzzleImage?> _findNextPuzzle() async {
    const store = SharedPreferencesCompletionStore();
    final completed = <String>{};
    while (true) {
      final candidate = nextPuzzleAfter(
        widget.image,
        completed,
        catalog: widget.catalog,
      );
      if (candidate == null) {
        return null;
      }
      final done = await store.isCompletedForGrid(
        imageId: candidate.id,
        columns: widget.size.columns,
        rows: widget.size.rows,
      );
      if (!done) {
        return candidate;
      }
      completed.add(candidate.id);
    }
  }

  @override
  void dispose() {
    _completionTimer?.cancel();
    _revealFallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final separateTools =
        MediaQuery.sizeOf(context).width < 480 || textScaler.scale(16) > 24;
    final counterHeight =
        19 + textScaler.scale(16) * 1.1 + textScaler.scale(9) * 1.1;
    final tools = <Widget>[
      IconButton(
        tooltip: 'Board color',
        icon: const Icon(Icons.format_color_fill),
        onPressed: _showBoardColorPicker,
      ),
      IconButton(
        tooltip: 'Restart puzzle',
        icon: const Icon(Icons.replay),
        onPressed: _restarting ? null : _confirmRestart,
      ),
      IconButton(
        tooltip: 'Edge pieces only',
        isSelected: _edgesOnly,
        icon: const Icon(Icons.border_outer),
        onPressed: () {
          setState(() => _edgesOnly = !_edgesOnly);
          _game.setEdgesOnlyFilter(_edgesOnly);
        },
      ),
      IconButton(
        tooltip: 'Image preview',
        isSelected: _showGhostPreview,
        icon: const Icon(Icons.image_outlined),
        selectedIcon: const Icon(Icons.image),
        onPressed: () {
          setState(() => _showGhostPreview = !_showGhostPreview);
          _game.setGhostPreview(_showGhostPreview);
        },
      ),
    ];
    return Stack(
      children: [
        // The card's ModalBarrier blocks taps and semantics beneath it,
        // but not keyboard traversal — focus is excluded here so Tab on
        // web/desktop cannot reach the blurred-out controls either.
        ExcludeFocus(
          excluding: _showCompletionCard,
          child: Scaffold(
            // Constant tooltips (they double as semantics labels for e2e
            // tests); the pressed state shows through the buttons'
            // isSelected styling.
            appBar: AppBar(
              toolbarHeight: counterHeight > kToolbarHeight
                  ? counterHeight
                  : kToolbarHeight,
              title: ValueListenableBuilder<int>(
                valueListenable: _game.placedCount,
                builder: (context, placed, _) => _PaletteCounter(
                  placed: placed,
                  total: widget.size.pieceCount,
                ),
              ),
              actions: separateTools ? null : tools,
              // Preserve direct access to every tool while giving the count room
              // alongside the back button on phones and with enlarged text.
              bottom: separateTools
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(48),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: tools,
                      ),
                    )
                  : null,
            ),
            // Labeled so e2e tests (and screen readers) can identify the
            // game screen — Flame's canvas exposes no semantics of its own.
            body: Semantics(
              label: _boardSemanticsLabel,
              child: IgnorePointer(
                ignoring: _restarting,
                child: GameWidget(key: ObjectKey(_game), game: _game),
              ),
            ),
          ),
        ),
        // Above the Scaffold, not inside its body: the card's backdrop
        // blur must cover the app bar and its tools too.
        if (_showCompletionCard)
          CompletionCard(
            image: widget.image,
            pieceCount: widget.size.pieceCount,
            onBackToGallery: () => Navigator.pop(context),
            // Popping with the painting hands the chain to the launcher's
            // flow loop, which pushes the next game at the same size.
            onNextPuzzle: switch (_nextImage) {
              null => null,
              final next => () => Navigator.pop(context, next),
            },
          ),
      ],
    );
  }
}

/// The placed-piece counter dressed as the painter's palette (mockup:
/// "the counter is a palette") — a linen daub with paint dots in the corner.
class _PaletteCounter extends StatelessWidget {
  const _PaletteCounter({required this.placed, required this.total});

  final int placed;
  final int total;

  /// The four studio paint colors, as on the mockup's palette.
  static const _paintDots = [
    Color(0xFFC06A45),
    Color(0xFF7B8456),
    Color(0xFFD9A33F),
    Color(0xFFD79B86),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$placed of $total pieces placed',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: const BoxDecoration(
          color: StudioColors.card,
          // Uneven ellipses make the chip read as a palette-shaped daub.
          borderRadius: BorderRadius.only(
            topLeft: Radius.elliptical(26, 20),
            topRight: Radius.elliptical(20, 26),
            bottomLeft: Radius.elliptical(22, 24),
            bottomRight: Radius.elliptical(28, 18),
          ),
          boxShadow: [
            BoxShadow(
              color: StudioColors.cardShadow,
              offset: Offset(0, 3),
              blurRadius: 10,
              spreadRadius: -5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final color in _paintDots)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '$placed / $total',
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            Text(
              'pieces placed',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 9,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Swatch row for picking the board backdrop. The sheet stays open after a
/// tap so the player can compare colors against the live board above it;
/// swipe or the scrim dismisses it.
class _BoardColorPicker extends StatefulWidget {
  const _BoardColorPicker({required this.selectedId, required this.onSelected});

  final String selectedId;
  final ValueChanged<BoardColorOption> onSelected;

  @override
  State<_BoardColorPicker> createState() => _BoardColorPickerState();
}

class _BoardColorPickerState extends State<_BoardColorPicker> {
  late String _selectedId = widget.selectedId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      // Scrollable so enlarged text can't overflow the sheet's height cap;
      // the min-sized Column keeps the sheet hugging its content otherwise.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Board color', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final option in boardColorOptions)
                  _BoardColorSwatch(
                    option: option,
                    selected: option.id == _selectedId,
                    onTap: () {
                      setState(() => _selectedId = option.id);
                      widget.onSelected(option);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardColorSwatch extends StatelessWidget {
  const _BoardColorSwatch({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final BoardColorOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The check must read on any fill, so pick ink or cream by luminance.
    final checkColor = option.background.computeLuminance() < 0.35
        ? StudioColors.onTerracotta
        : StudioColors.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Board color: ${option.label}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                PaintedSwatch(color: option.background, size: 40),
                if (selected) Icon(Icons.check, size: 22, color: checkColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
