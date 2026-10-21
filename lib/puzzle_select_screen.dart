// Puzzle selection overview:
// 1. Shows the catalog grouped into themed categories; categories with no
//    images yet are hidden. Images finished at any size get a check badge.
// 2. Tapping an image opens a sheet with the available puzzle sizes, marking
//    sizes that are in progress or already completed.
// 3. Choosing a size opens GameScreen with that image and size.
// 4. Dismissing the sheet leaves the user on the selection screen.

import 'package:flutter/material.dart';

import 'game_screen.dart';
import 'puzzle_catalog.dart';
import 'puzzle_completion.dart';
import 'puzzle_save.dart';

class PuzzleSelectScreen extends StatefulWidget {
  const PuzzleSelectScreen({super.key});

  @override
  State<PuzzleSelectScreen> createState() => _PuzzleSelectScreenState();
}

class _PuzzleSelectScreenState extends State<PuzzleSelectScreen> {
  static const _saveStore = SharedPreferencesSaveStore();
  static const _completionStore = SharedPreferencesCompletionStore();

  /// Images finished at least once, at any size.
  var _completedImageIds = <String>{};

  @override
  void initState() {
    super.initState();
    _refreshCompletedImages();
  }

  Future<void> _refreshCompletedImages() async {
    final completed = <String>{};
    for (final image in puzzleCatalog) {
      for (final size in puzzleSizes) {
        final key = puzzleCompletionKey(
          imageId: image.id,
          columns: size.columns,
          rows: size.rows,
        );
        if (await _completionStore.isCompleted(key)) {
          completed.add(image.id);
          break; // One completed size is enough for the badge.
        }
      }
    }
    if (mounted) {
      setState(() => _completedImageIds = completed);
    }
  }

  Future<void> _startPuzzle(BuildContext context, PuzzleImage image) async {
    // Resolve each size's state BEFORE opening the sheet, so the sheet
    // itself stays plain synchronous UI (an async lookup inside its build
    // would re-trigger itself on every rebuild).
    final inProgressSizes = <PuzzleSize>{};
    final completedSizes = <PuzzleSize>{};
    for (final size in puzzleSizes) {
      final saveKey = puzzleSaveKey(
        imageId: image.id,
        columns: size.columns,
        rows: size.rows,
      );
      final completionKey = puzzleCompletionKey(
        imageId: image.id,
        columns: size.columns,
        rows: size.rows,
      );
      if (await _saveStore.exists(saveKey)) {
        inProgressSizes.add(size);
      }
      if (await _completionStore.isCompleted(completionKey)) {
        completedSizes.add(size);
      }
    }
    if (!context.mounted) {
      return;
    }

    final selectedSize = await showModalBottomSheet<PuzzleSize>(
      context: context,
      builder: (_) => _PuzzleSizePicker(
        image: image,
        inProgressSizes: inProgressSizes,
        completedSizes: completedSizes,
      ),
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

    // A puzzle may have been finished while the game screen was open.
    await _refreshCompletedImages();
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
              completedImageIds: _completedImageIds,
              onImageTap: (image) => _startPuzzle(context, image),
            ),
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.category,
    required this.completedImageIds,
    required this.onImageTap,
  });

  final PuzzleCategory category;
  final Set<String> completedImageIds;
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
            return _PuzzleCard(
              image: image,
              isCompleted: completedImageIds.contains(image.id),
              onTap: () => onImageTap(image),
            );
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _PuzzleCard extends StatelessWidget {
  const _PuzzleCard({
    required this.image,
    required this.isCompleted,
    required this.onTap,
  });

  final PuzzleImage image;

  /// Finished at least once, at any size: shows the check badge.
  final bool isCompleted;

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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    image.assetPath,
                    fit: BoxFit.cover,
                    // Decode smaller previews to reduce memory use.
                    cacheWidth: 640,
                  ),
                  if (isCompleted)
                    const Positioned(top: 8, right: 8, child: _CompletedBadge()),
                ],
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

class _CompletedBadge extends StatelessWidget {
  const _CompletedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.check_circle,
        size: 20,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _PuzzleSizePicker extends StatelessWidget {
  const _PuzzleSizePicker({
    required this.image,
    required this.inProgressSizes,
    required this.completedSizes,
  });

  final PuzzleImage image;

  /// Sizes of this image that have a saved game to resume.
  final Set<PuzzleSize> inProgressSizes;

  /// Sizes of this image that were finished at least once.
  final Set<PuzzleSize> completedSizes;

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
              trailing: _statusLabel(context, size),
              onTap: () => Navigator.pop(context, size),
            ),
        ],
      ),
    );
  }

  /// "In progress" wins over "Completed ✓": resuming is the next action.
  /// The e2e tests assert on these texts.
  Widget? _statusLabel(BuildContext context, PuzzleSize size) {
    if (inProgressSizes.contains(size)) {
      return Text(
        'In progress',
        style: TextStyle(color: Theme.of(context).colorScheme.primary),
      );
    }
    if (completedSizes.contains(size)) {
      return Text(
        'Completed ✓',
        style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
      );
    }
    return null;
  }
}
