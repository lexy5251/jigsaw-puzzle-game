import 'package:flutter/material.dart';

import 'home_shell.dart';
import 'studio_theme.dart';

void main() {
  runApp(const JigsawPuzzleApp());
}

/// App shell: theme + the bottom-nav home (Gallery · My Puzzles · Settings).
class JigsawPuzzleApp extends StatelessWidget {
  const JigsawPuzzleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jigsaw Puzzle',
      theme: studioTheme(),
      home: const HomeShell(),
    );
  }
}
