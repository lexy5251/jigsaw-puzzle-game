import 'package:flutter/material.dart';

import 'puzzle_select_screen.dart';
import 'studio_theme.dart';

void main() {
  runApp(const JigsawPuzzleApp());
}

/// App shell: theme + the puzzle-select home screen.
class JigsawPuzzleApp extends StatelessWidget {
  const JigsawPuzzleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jigsaw Puzzle',
      theme: studioTheme(),
      home: const PuzzleSelectScreen(),
    );
  }
}
