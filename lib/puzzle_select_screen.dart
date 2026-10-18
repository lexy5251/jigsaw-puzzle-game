// Puzzle selection overview:
// 1. Shows the catalog grouped into themed categories; categories with no
//    images yet are hidden.
// 2. Tapping an image opens a sheet with the available puzzle sizes.
// 3. Choosing a size opens GameScreen with that image and size.
// 4. Dismissing the sheet leaves the user on the selection screen.

import 'package:flutter/material.dart';

import 'game_screen.dart';
import 'puzzle_catalog.dart';

class PuzzleSelectScreen extends StatelessWidget {
  const PuzzleSelectScreen({super.key});

  Future<void> _startPuzzle(BuildContext context, PuzzleImage image) async {
    final selectedSize = await showModalBottomSheet<PuzzleSize>(
      context: context,
      builder: (_) => _PuzzleSizePicker(image: image),
    );

    // The sheet can be dismissed, or this screen removed while it is open.
    if (selectedSize == null || !context.mounted) {
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final category in puzzleCategories)
            _CategorySection(
              category: category,
              onImageTap: (image) => _startPuzzle(context, image),
            ),
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({required this.category, required this.onImageTap});

  final PuzzleCategory category;
  final ValueChanged<PuzzleImage> onImageTap;

  @override
  Widget build(BuildContext context) {
    final images = imagesInCategory(category.id);
    if (images.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 12),
          child: Text(
            category.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        GridView.builder(
          // The outer ListView scrolls; this grid only sizes itself.
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.85,
          ),
          itemCount: images.length,
          itemBuilder: (context, index) {
            final image = images[index];
            return _PuzzleCard(image: image, onTap: () => onImageTap(image));
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _PuzzleCard extends StatelessWidget {
  const _PuzzleCard({required this.image, required this.onTap});

  final PuzzleImage image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Image.asset(
                image.assetPath,
                fit: BoxFit.cover,
                // Decode smaller previews to reduce memory use.
                cacheWidth: 640,
              ),
            ),
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
              onTap: () => Navigator.pop(context, size),
            ),
        ],
      ),
    );
  }
}
