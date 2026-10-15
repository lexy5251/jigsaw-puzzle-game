import 'package:flutter/material.dart';

import 'puzzle_select_screen.dart';

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E3440), // matches the board background
          brightness: Brightness.dark,
        ),
      ),
      home: const PuzzleSelectScreen(),
    );
  }
}
