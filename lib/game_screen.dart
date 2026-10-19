// Game screen overview:
// 1. Receives the selected puzzle image and grid size.
// 2. Holds the running game for as long as this puzzle screen is open.
// 3. Displays the puzzle using Flame's GameWidget.
// 4. Keeps a back button to return to puzzle selection.
// JigsawGame handles the puzzle gameplay.

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'jigsaw_game.dart';
import 'puzzle_catalog.dart';
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
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: GameWidget(game: _game),
    );
  }
}
