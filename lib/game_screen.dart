// Game screen overview:
// 1. Receives the selected puzzle image and grid size.
// 2. Holds the running game for as long as this puzzle screen is open.
// 3. Displays the puzzle using Flame's GameWidget.
// 4. Keeps a back button to return to puzzle selection.
// 5. When the game reports completion, records it permanently and shows a
//    celebration card timed to appear as the in-game glow fades out.
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
  });

  final PuzzleImage image;
  final PuzzleSize size;

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
  Timer? _completionTimer;
  bool _edgesOnly = false;
  late bool _showGhostPreview = widget.settings.ghostPreviewDefault;

  /// Null until the game finishes loading, then whether it resumed a save.
  bool? _resumed;

  late JigsawGame _game = _createGame();

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
      startedDay: widget.startedDay ?? dayKey((widget.clock ?? DateTime.now)()),
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
    setState(() {
      _restarting = true;
      _showCompletionCard = false;
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
    // Let the in-game glow (0.9s) finish before the card appears.
    _completionTimer?.cancel();
    _completionTimer = Timer(const Duration(milliseconds: 950), () {
      if (mounted && !_restarting && identical(_game, game)) {
        setState(() => _showCompletionCard = true);
      }
    });

    // The streak credits what the player saw happen, so it runs first and
    // unconditionally. Sequencing (not racing) the two writes also keeps
    // their reads from interleaving in the shared preferences cache.
    final dailyRecorded = await _recordDailyCompletion(game.runStartedDay);

    // The game keeps its progress save until BOTH records are stored, so a
    // failed daily credit gets the same retry as a failed completion write:
    // resume the save and finish again. A day-late retry still credits via
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

  /// Finishing a daily image at any size blooms the pot of the day the run
  /// began — the save's stamp (see [dailyCreditDay]).
  /// False means a credit was due but could not be stored.
  Future<bool> _recordDailyCompletion(String? startedDay) async {
    final day = dailyCreditDay(
      widget.image.id,
      (widget.clock ?? DateTime.now)(),
      startedDay: startedDay,
    );
    if (day == null) {
      return true;
    }
    return const SharedPreferencesDailyStreakStore().markCompleted(day);
  }

  @override
  void dispose() {
    _completionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Constant tooltips (they double as semantics labels for e2e tests);
      // the pressed state shows through the buttons' isSelected styling.
      appBar: AppBar(
        actions: [
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
        ],
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
            _CompletionCard(
              imageTitle: widget.image.title,
              pieceCount: widget.size.pieceCount,
              onBackToPuzzles: () => Navigator.pop(context),
            ),
        ],
      ),
    );
  }
}

/// The celebration shown over the finished image.
class _CompletionCard extends StatelessWidget {
  const _CompletionCard({
    required this.imageTitle,
    required this.pieceCount,
    required this.onBackToPuzzles,
  });

  final String imageTitle;
  final int pieceCount;
  final VoidCallback onBackToPuzzles;

  @override
  Widget build(BuildContext context) {
    return Center(
      // Scrollable so the card stays usable on short landscape screens
      // instead of overflowing.
      child: SingleChildScrollView(
        // Fade and scale in gently as the glow fades out.
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutBack,
          builder: (context, value, child) => Opacity(
            opacity: value.clamp(0, 1),
            child: Transform.scale(scale: 0.8 + 0.2 * value, child: child),
          ),
          child: Card(
            margin: const EdgeInsets.all(32),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Puzzle complete!',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$imageTitle · $pieceCount pieces',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: onBackToPuzzles,
                    child: const Text('Back to puzzles'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
