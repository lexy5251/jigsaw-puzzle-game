// Game screen overview:
// 1. Receives the selected puzzle image and grid size.
// 2. Holds the running game for as long as this puzzle screen is open.
// 3. Displays the puzzle using Flame's GameWidget.
// 4. Keeps a back button to return to puzzle selection.
// 5. When the game reports completion, records it permanently and shows a
//    celebration card timed to appear as the in-game glow fades out.
// JigsawGame handles the puzzle gameplay.

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'jigsaw_game.dart';
import 'puzzle_catalog.dart';
import 'puzzle_completion.dart';
import 'puzzle_save.dart';

/// Hosts one running puzzle.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.image, required this.size});

  final PuzzleImage image;
  final PuzzleSize size;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  bool _showCompletionCard = false;

  /// Null until the game finishes loading, then whether it resumed a save.
  bool? _resumed;

  late final JigsawGame _game = JigsawGame(
    imageAsset: widget.image.fileName,
    columns: widget.size.columns,
    rows: widget.size.rows,
    saveStore: const SharedPreferencesSaveStore(),
    saveKey: puzzleSaveKey(
      imageId: widget.image.id,
      columns: widget.size.columns,
      rows: widget.size.rows,
    ),
    onCompleted: _onPuzzleCompleted,
    onBoardLoaded: (resumed) {
      if (mounted) {
        setState(() => _resumed = resumed);
      }
    },
  );

  /// "resumed" vs "new puzzle" lets the Maestro flow verify that reopening
  /// actually restored the save instead of silently starting over.
  String get _boardSemanticsLabel => switch (_resumed) {
    null => 'Puzzle board',
    true => 'Puzzle board, resumed',
    false => 'Puzzle board, new puzzle',
  };

  Future<bool> _onPuzzleCompleted() {
    // Let the in-game glow (0.9s) finish before the card appears.
    Future.delayed(const Duration(milliseconds: 950), () {
      if (mounted) {
        setState(() => _showCompletionCard = true);
      }
    });

    // The game keeps its progress save until this write reports success.
    return const SharedPreferencesCompletionStore().markCompleted(
      puzzleCompletionKey(
        imageId: widget.image.id,
        columns: widget.size.columns,
        rows: widget.size.rows,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Stack(
        children: [
          // Labeled so e2e tests (and screen readers) can identify the
          // game screen — Flame's canvas exposes no semantics of its own.
          Semantics(
            label: _boardSemanticsLabel,
            child: GameWidget(game: _game),
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
