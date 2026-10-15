// Puzzle selection overview:
// 1. Shows the catalog images in a grid.
// 2. Tapping an image opens a sheet with the available puzzle sizes.
// 3. Choosing a size opens GameScreen with that image and size.
// 4. Dismissing the sheet leaves the user on the selection screen.

import 'package:flutter/material.dart';

import 'game_screen.dart';
import 'puzzle_catalog.dart';

/// Lets the user choose an image and grid size before starting a puzzle.
class PuzzleSelectScreen extends StatelessWidget {
  const PuzzleSelectScreen({super.key});

  Future<void> _selectSizeAndStartPuzzle(
    BuildContext context,
    PuzzleImage image,
  ) async {
    // Wait for the picker to return a size, or null if it is dismissed.
    final selectedSize = await showModalBottomSheet<PuzzleSize>(
      context: context,
      builder: (_) => _PuzzleSizePicker(image: image),
    );

    if (selectedSize == null) {
      return;
    }

    // The screen may have been removed while we waited for the choice.
    if (!context.mounted) {
      return;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(image: image, size: selectedSize),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a puzzle')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.85,
        ),
        itemCount: puzzleCatalog.length,
        itemBuilder: (context, index) {
          final image = puzzleCatalog[index];
          return _PuzzleCard(
            image: image,
            onTap: () => _selectSizeAndStartPuzzle(context, image),
          );
        },
      ),
    );
  }
}

/// Displays an image preview and title; the parent handles the tap.
class _PuzzleCard extends StatelessWidget {
  const _PuzzleCard({required this.image, required this.onTap});

  final PuzzleImage image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias, // Keeps the photo inside the rounded card.
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: Image.asset(image.assetPath, fit: BoxFit.cover)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                image.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the available grid sizes and returns the user's choice.
class _PuzzleSizePicker extends StatelessWidget {
  const _PuzzleSizePicker({required this.image});

  final PuzzleImage image;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // Fits its contents when there is room, and scrolls in short windows.
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              image.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final size in puzzleSizes)
            ListTile(
              title: Text('${size.pieceCount} pieces · ${size.label}'),
              subtitle: Text('${size.columns} × ${size.rows}'),
              // Close the sheet and return this size to the awaiting caller.
              onTap: () => Navigator.pop(context, size),
            ),
        ],
      ),
    );
  }
}
