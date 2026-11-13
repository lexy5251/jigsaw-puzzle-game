// One collection's page: its puzzles as a responsive grid of rounded,
// slightly hand-tilted photo cards under the category's mascot header — no
// titles and no torn frame, the picture is the whole pitch (owner's UI-6
// rulings: bare images get straight edges; names live in semantics only).
// Tapping a painting opens the shared size sheet → game flow.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'puzzle_catalog.dart';
import 'puzzle_completion.dart';
import 'puzzle_launcher.dart';
import 'puzzle_save.dart';
import 'studio_mascots.dart';
import 'studio_surfaces.dart';
import 'studio_theme.dart';

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({
    super.key,
    required this.category,
    this.clock,
    this.catalog = puzzleCatalog,
  });

  final PuzzleCategory category;

  /// Returns "now"; tests fix the date to make daily credit deterministic.
  /// Defaults to [DateTime.now].
  final DateTime Function()? clock;

  /// Where this category's images come from. Tests supply a small fixture
  /// catalog so grid tests stay independent of the real bundled photos.
  final List<PuzzleImage> catalog;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  static const _completionStore = SharedPreferencesCompletionStore();
  static const _saveStore = SharedPreferencesSaveStore();

  /// Images in this category finished at least once, at any size.
  var _completedImageIds = <String>{};

  /// Images with a resumable save at any size (the sprout badge; the player
  /// must be able to spot a started puzzle without opening its size sheet).
  var _inProgressImageIds = <String>{};

  List<PuzzleImage> get _images =>
      imagesInCategory(widget.category.id, catalog: widget.catalog);

  @override
  void initState() {
    super.initState();
    _refreshPuzzleStates();
  }

  Future<void> _refreshPuzzleStates() async {
    final completed = <String>{};
    final inProgress = <String>{};
    for (final image in _images) {
      for (final size in puzzleSizes) {
        // One size in either state is enough for that badge.
        if (!completed.contains(image.id) &&
            await _completionStore.isCompletedForGrid(
              imageId: image.id,
              columns: size.columns,
              rows: size.rows,
            )) {
          completed.add(image.id);
        }
        final saveKey = puzzleSaveKey(
          imageId: image.id,
          columns: size.columns,
          rows: size.rows,
        );
        if (!inProgress.contains(image.id)) {
          final save = await _saveStore.load(saveKey);
          if (save?.isConsistentFor(size.pieceCount) ?? false) {
            inProgress.add(image.id);
          }
        }
      }
    }
    if (mounted &&
        (!setEquals(_completedImageIds, completed) ||
            !setEquals(_inProgressImageIds, inProgress))) {
      setState(() {
        _completedImageIds = completed;
        _inProgressImageIds = inProgress;
      });
    }
  }

  Future<void> _open(PuzzleImage image) async {
    // Forward this screen's catalog so "Next puzzle" picks from the same
    // set the grid shows (a fixture catalog in tests, the global one live).
    await startPuzzleFlow(
      context,
      image,
      clock: widget.clock,
      catalog: widget.catalog,
    );
    // The puzzle may have been started or finished while the game was open.
    await _refreshPuzzleStates();
  }

  @override
  Widget build(BuildContext context) {
    final images = _images;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MascotArt(mascotForCategory(widget.category.id), height: 22),
            const SizedBox(width: 10),
            // Flexible: long titles ellipsize on narrow phones instead of
            // overflowing the AppBar.
            Flexible(
              child: Text(
                widget.category.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: GridView.builder(
        padding: photoGridPadding,
        // Max width instead of a fixed column count: 2 across on phones so
        // the photo is big enough to judge (UI-6 ruling, amending #4's ~3),
        // more columns on tablets and the web build.
        gridDelegate: photoGridDelegate,
        itemCount: images.length,
        itemBuilder: (context, index) {
          final image = images[index];
          return _PuzzleCard(
            image: image,
            // Grid position, so side-by-side cards get different wobbles.
            variant: index,
            isCompleted: _completedImageIds.contains(image.id),
            isInProgress: _inProgressImageIds.contains(image.id),
            onTap: () => _open(image),
          );
        },
      ),
    );
  }
}

class _PuzzleCard extends StatelessWidget {
  const _PuzzleCard({
    required this.image,
    required this.variant,
    required this.isCompleted,
    required this.isInProgress,
    required this.onTap,
  });

  final PuzzleImage image;

  /// Grid item index: drives the alternating tilt direction.
  final int variant;

  /// Finished at least once, at any size: shows the check badge.
  final bool isCompleted;

  /// Has a resumable save at any size: shows the sprout badge.
  final bool isInProgress;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TiltedPhotoCard(
      assetPath: image.assetPath,
      title: image.title,
      semanticsIdentifier: 'catalog-puzzle-${image.id}',
      variant: variant,
      onTap: onTap,
      overlays: [
        if (isCompleted)
          const Positioned(top: 8, right: 8, child: _CompletedBadge()),
        if (isInProgress)
          const Positioned(top: 8, left: 8, child: _InProgressBadge()),
      ],
    );
  }
}

/// The growing stem — the "continue progress" costume: a started puzzle's
/// painting has a young sprout on its corner until it blooms (completion).
class _InProgressBadge extends StatelessWidget {
  const _InProgressBadge();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // Own node: without this the label merges into the card's
      // title-labelled node (UI-6 wrapper) and disappears for a11y/e2e.
      container: true,
      label: statusInProgressLabel,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          shape: BoxShape.circle,
        ),
        child: const MascotArt(StudioMascot.sprout, height: 20),
      ),
    );
  }
}

class _CompletedBadge extends StatelessWidget {
  const _CompletedBadge();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // Own node, like the sprout badge: without it the label would merge
      // into the card's title-labelled node and completed state would be
      // inaudible to screen readers.
      container: true,
      label: statusCompletedLabel,
      child: Container(
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
      ),
    );
  }
}
