// Game screen overview:
// 1. Receives the selected puzzle image and grid size.
// 2. Holds the running game for as long as this puzzle screen is open.
// 3. Displays the puzzle using Flame's GameWidget.
// 4. Keeps a back button to return to puzzle selection.
// 5. When the game reports completion, records it permanently and hangs the
//    painting on a gallery wall, timed to appear as the in-game glow fades.
//    The wall offers the category's next unfinished painting as one-tap
//    "Next puzzle" (the screen pops with that painting as its result and
//    the launcher chains into it), with "Back to the gallery" as the exit.
// JigsawGame handles the puzzle gameplay.

import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'daily_puzzle.dart';
import 'daily_streak.dart';
import 'game_sounds.dart';
import 'jigsaw_game.dart';
import 'puzzle_catalog.dart';
import 'puzzle_completion.dart';
import 'puzzle_save.dart';
import 'studio_mascots.dart';
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

  /// Day key stamped on a FRESH board's save — the day the player committed
  /// to this run. The select screen passes the day its card was tapped, so
  /// a size sheet left open across midnight cannot shift the credited day.
  /// Defaults to the day this screen opens.
  final String? startedDay;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  static const _saveStore = SharedPreferencesSaveStore();

  bool _showCompletionCard = false;
  bool _restarting = false;

  /// The "Next puzzle" offer; null until completion resolves it (and stays
  /// null when the rest of the category is already done at this size).
  PuzzleImage? _nextImage;

  /// The gallery wall's bloom caption, resolved once at credit time; null
  /// when the run earned no NEW daily credit. The wall shows the bloom —
  /// the moment of finishing is where the reward must appear.
  String? _bloomCaption;
  Timer? _completionTimer;
  Timer? _revealFallbackTimer;
  bool _edgesOnly = false;
  late bool _showGhostPreview = widget.settings.ghostPreviewDefault;

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
      onCompleted: () => _onPuzzleCompleted(game),
      onBoardLoaded: (resumed) {
        if (mounted && !_restarting && identical(_game, game)) {
          setState(() => _resumed = resumed);
        }
      },
    );
    // Both setters are safe before the game loads: they store the flag,
    // and loading applies it.
    game.setEdgesOnlyFilter(_edgesOnly);
    game.setGhostPreview(_showGhostPreview);
    return game;
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
      _bloomCaption = null;
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
    // The card reveals when BOTH the glow delay and its data (next-puzzle
    // offer, bloom caption) are ready: the delay is armed first so storage
    // latency hides inside the 0.9s glow instead of stacking after it, and
    // the card still never appears with an unresolved hero button (the old
    // button-swap race).
    var delayElapsed = false;
    var dataReady = false;
    _completionTimer?.cancel();
    _revealFallbackTimer?.cancel();
    _completionTimer = Timer(const Duration(milliseconds: 950), () {
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
    // The record writes run UNCONDITIONALLY from here: a completion the
    // player saw must be stored even if a restart or a chained replacement
    // lands while the read above was in flight — only the UI fields are
    // guarded. The streak write stays sequenced ahead of the completion
    // write so their reads cannot interleave in the preferences cache.
    final daily = await _recordDailyCompletion(game.runStartedDay);
    if (!_restarting && identical(_game, game)) {
      _nextImage = next;
      _bloomCaption = daily.bloomCaption;
    }
    dataReady = true;
    if (delayElapsed) {
      _revealFallbackTimer?.cancel();
      _revealCompletionCard(game);
    }

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
    return daily.recorded && completionRecorded;
  }

  /// Reveals the gallery wall (idempotent: a fallback reveal followed by
  /// late-arriving data just rebuilds the wall with the data filled in).
  void _revealCompletionCard(JigsawGame game) {
    if (mounted && !_restarting && identical(_game, game)) {
      setState(() => _showCompletionCard = true);
    }
  }

  /// Finishing a daily image at any size blooms the pot of the day the run
  /// began — the save's stamp (see [dailyCreditDay]). `recorded` false means
  /// a credit was due but could not be stored. The caption is non-null only
  /// for a NEWLY credited day: a replay of an already-bloomed day (or a
  /// retried completion write) celebrates nothing again.
  Future<({bool recorded, String? bloomCaption})> _recordDailyCompletion(
    String? startedDay,
  ) async {
    final completedAt = _now;
    final day = dailyCreditDay(
      widget.image.id,
      completedAt,
      startedDay: startedDay,
    );
    if (day == null) {
      return (recorded: true, bloomCaption: null);
    }
    const store = SharedPreferencesDailyStreakStore();
    final days = await store.completedDays();
    if (days.contains(day)) {
      return (recorded: true, bloomCaption: null);
    }
    if (!await store.markCompleted(day)) {
      return (recorded: false, bloomCaption: null);
    }
    // Streak from the set just written: the caption can never contradict
    // the write it celebrates (a bloomed day always reads at least 1).
    final streak = currentStreak({...days, day}, completedAt);
    return (
      recorded: true,
      bloomCaption: dailyBloomCaption(day, completedAt, streak),
    );
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
        tooltip: 'Fit board to screen',
        icon: const Icon(Icons.fit_screen),
        onPressed: () => _game.resetView(),
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
    return Scaffold(
      // Constant tooltips (they double as semantics labels for e2e tests);
      // the pressed state shows through the buttons' isSelected styling.
      appBar: AppBar(
        toolbarHeight: counterHeight > kToolbarHeight
            ? counterHeight
            : kToolbarHeight,
        title: ValueListenableBuilder<int>(
          valueListenable: _game.placedCount,
          builder: (context, placed, _) =>
              _PaletteCounter(placed: placed, total: widget.size.pieceCount),
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
      body: Stack(
        children: [
          // Labeled so e2e tests (and screen readers) can identify the
          // game screen — Flame's canvas exposes no semantics of its own.
          Semantics(
            label: _boardSemanticsLabel,
            child: IgnorePointer(
              ignoring: _restarting,
              child: GameWidget(key: ObjectKey(_game), game: _game),
            ),
          ),
          if (_showCompletionCard)
            _GalleryWall(
              image: widget.image,
              pieceCount: widget.size.pieceCount,
              completedOn: _now,
              dailyBloom: _bloomCaption,
              onBackToGallery: () => Navigator.pop(context),
              // Popping with the painting hands the chain to the launcher's
              // flow loop, which pushes the next game at the same size.
              onNextPuzzle: switch (_nextImage) {
                null => null,
                final next => () => Navigator.pop(context, next),
              },
            ),
        ],
      ),
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

/// The celebration: the finished painting is hung on a gallery wall —
/// nail, gold frame, plaque, a potted sunflower (mockup "Done · hung in
/// your gallery").
class _GalleryWall extends StatelessWidget {
  const _GalleryWall({
    required this.image,
    required this.pieceCount,
    required this.completedOn,
    required this.dailyBloom,
    required this.onBackToGallery,
    required this.onNextPuzzle,
  });

  final PuzzleImage image;
  final int pieceCount;
  final DateTime completedOn;

  /// Caption for a run that bloomed a daily pot ("Today's pot bloomed ·
  /// 3-day streak"); null shows the plain sunflower sprig instead.
  final String? dailyBloom;

  final VoidCallback onBackToGallery;

  /// Starts the category's next unfinished painting; null hides the button
  /// (the rest of the category is done at this size).
  final VoidCallback? onNextPuzzle;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = '${_months[completedOn.month - 1]} ${completedOn.day}';
    final bloom = dailyBloom;
    // Fade the wall in as the in-game glow fades out.
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        builder: (context, value, child) =>
            Opacity(opacity: value, child: child),
        child: Container(
          color: StudioColors.galleryWall,
          child: Stack(
            children: [
              ..._paintSpecks(),
              SafeArea(
                // Scrollable so the scene stays usable on short landscape
                // screens instead of overflowing.
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _nail(),
                        const SizedBox(height: 8),
                        _hungFrame(context),
                        const SizedBox(height: 12),
                        _plaque(theme, date),
                        const SizedBox(height: 6),
                        // A daily run's reward appears HERE, at the moment
                        // of finishing — a bloomed pot beside the painting.
                        if (bloom == null)
                          const MascotArt(StudioMascot.sprig, height: 60)
                        else ...[
                          const MascotArt(StudioMascot.cactus, height: 60),
                          const SizedBox(height: 4),
                          Text(bloom, style: theme.textTheme.bodySmall),
                        ],
                        const SizedBox(height: 16),
                        // "One more" is the likely mood right after finishing,
                        // so the next puzzle is the hero action and the exit
                        // a quiet text button beneath it.
                        if (onNextPuzzle != null) ...[
                          FilledButton(
                            onPressed: onNextPuzzle,
                            child: const Text('Next puzzle'),
                          ),
                          TextButton(
                            onPressed: onBackToGallery,
                            child: const Text('Back to the gallery'),
                          ),
                        ] else
                          FilledButton(
                            onPressed: onBackToGallery,
                            child: const Text('Back to the gallery'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nail() => Container(
    width: 7,
    height: 7,
    decoration: const BoxDecoration(
      color: Color(0xFF8A6B43),
      shape: BoxShape.circle,
    ),
  );

  /// The finished painting in a gold frame with a pale inner mat line.
  Widget _hungFrame(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    // Bounded by both axes so the frame also fits short landscape screens.
    final artWidth = [
      screen.width * 0.72,
      screen.height * 0.62,
      320.0,
    ].reduce((a, b) => a < b ? a : b);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD9A33F), Color(0xFFC08437)],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80462D0F),
            offset: Offset(0, 14),
            blurRadius: 28,
            spreadRadius: -12,
          ),
        ],
      ),
      child: Container(
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: const Color(0xCCFFFAEB), width: 3),
          borderRadius: BorderRadius.circular(3),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Image.asset(
            image.assetPath,
            width: artWidth,
            // Catalog images are 3:2 (the grid-ladder invariant relies on it).
            height: artWidth / 1.5,
            fit: BoxFit.cover,
            cacheWidth: 640,
          ),
        ),
      ),
    );
  }

  Widget _plaque(ThemeData theme, String date) => PaintedCard(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
    child: Column(
      children: [
        Text(
          image.title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          '$pieceCount pieces · $date · hung in your gallery',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
    ),
  );

  /// Flecks of studio paint celebrating around the frame.
  List<Widget> _paintSpecks() {
    Widget speck(
      double size,
      int argb, {
      double? top,
      double? left,
      double? right,
    }) => Positioned(
      top: top,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: Color(argb), shape: BoxShape.circle),
      ),
    );
    return [
      speck(9, 0xFFD9A33F, top: 90, left: 48),
      speck(7, 0xFFC06A45, top: 60, right: 70),
      speck(8, 0xFF7B8456, top: 150, right: 36),
      speck(6, 0xFFD79B86, top: 170, left: 32),
    ];
  }
}
