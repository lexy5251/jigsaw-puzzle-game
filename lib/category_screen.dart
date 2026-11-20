// One collection's page: its puzzles as a responsive grid of rounded,
// slightly hand-tilted photo cards under the category's mascot header — no
// titles and no torn frame, the picture is the whole pitch (owner's UI-6
// rulings: bare images get straight edges; names live in semantics only).
// Tapping a painting opens the shared size sheet → game flow.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'bonus_track.dart';
import 'puzzle_catalog.dart';
import 'puzzle_completion.dart';
import 'puzzle_launcher.dart';
import 'puzzle_save.dart';
import 'riso_markers.dart';
import 'studio_mascots.dart';
import 'studio_surfaces.dart';

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

  /// Best progress percent per image with a resumable save (the piece
  /// pill; the player must be able to spot a started puzzle — and how far
  /// it got — without opening its size sheet).
  var _progressPercents = <String, int>{};

  List<PuzzleImage> get _images =>
      imagesInCategory(widget.category.id, catalog: widget.catalog);

  @override
  void initState() {
    super.initState();
    _refreshPuzzleStates();
  }

  Future<void> _refreshPuzzleStates() async {
    // Two bulk reads instead of an image x size grid of lookups: the old
    // per-cell loop decoded 40 saves per visit on the UI isolate.
    final imageIds = {for (final image in _images) image.id};
    final completed = (await completedImageIds(
      _completionStore,
    )).intersection(imageIds);

    final sizesByGrid = {
      for (final size in puzzleSizes) (size.columns, size.rows): size,
    };
    final percents = <String, int>{};
    final loads = <Future<void>>[];
    for (final key in await _saveStore.listSavedKeys()) {
      final parsed = parsePuzzleSaveKey(key);
      if (parsed == null || !imageIds.contains(parsed.imageId)) {
        continue;
      }
      final size = sizesByGrid[(parsed.columns, parsed.rows)];
      if (size == null) {
        continue;
      }
      // Only keys that actually exist get decoded, concurrently.
      loads.add(
        _saveStore.load(key).then((save) {
          if (!(save?.isConsistentFor(size.pieceCount) ?? false)) {
            return;
          }
          // The pill shows the furthest run: the most advanced save of
          // any size speaks for the painting. Capped at 99: only the done
          // sticker may say "complete", and 224/225 would otherwise round
          // up to a lying 100%.
          final percent = math.min(
            99,
            (save!.lockedPieceIndexes.length * 100 / size.pieceCount).round(),
          );
          final best = percents[parsed.imageId];
          if (best == null || percent > best) {
            percents[parsed.imageId] = percent;
          }
        }),
      );
    }
    await Future.wait(loads);
    if (mounted &&
        (!setEquals(_completedImageIds, completed) ||
            !mapEquals(_progressPercents, percents))) {
      setState(() {
        _completedImageIds = completed;
        _progressPercents = percents;
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
      catalogs: PuzzleCatalogs(gallery: widget.catalog),
    );
    // The puzzle may have been started or finished while the game was open.
    await _refreshPuzzleStates();
  }

  @override
  Widget build(BuildContext context) {
    final images = _images;
    return Scaffold(
      // The shared riso bar (not a hand copy): same scaling rules and
      // halftone accent as the tab pages, with the mascot as prefix.
      appBar: risoAppBar(
        widget.category.title,
        fontSize: 24,
        titlePrefix: MascotArt(
          mascotForCategory(widget.category.id),
          height: 22,
        ),
      ),
      body: Column(
        children: [
          // The collection's own progress: one mini piece per painting,
          // filling tomato as the category completes.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: PieceMeter(
              done: images
                  .where((image) => _completedImageIds.contains(image.id))
                  .length,
              total: images.length,
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: photoGridPadding,
              // Max width instead of a fixed column count: 2 across on
              // phones so the photo is big enough to judge (UI-6 ruling),
              // more columns on tablets and the web build.
              gridDelegate: photoGridDelegate,
              itemCount: images.length,
              itemBuilder: (context, index) {
                final image = images[index];
                return _PuzzleCard(
                  image: image,
                  isCompleted: _completedImageIds.contains(image.id),
                  progressPercent: _progressPercents[image.id],
                  onTap: () => _open(image),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PuzzleCard extends StatelessWidget {
  const _PuzzleCard({
    required this.image,
    required this.isCompleted,
    required this.progressPercent,
    required this.onTap,
  });

  final PuzzleImage image;

  /// Finished at least once, at any size: wears the done piece sticker.
  final bool isCompleted;

  /// Best resumable progress at any size, or null when untouched: the
  /// piece pill (replaces the old sprout badge AND tells how far).
  final int? progressPercent;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TiltedPhotoCard(
      assetPath: image.assetPath,
      title: image.title,
      semanticsIdentifier: 'catalog-puzzle-${image.id}',
      onTap: onTap,
      cornerMarker: isCompleted ? const DonePieceSticker() : null,
      overlays: [
        if (progressPercent case final percent?)
          Positioned(
            right: 9,
            bottom: 10,
            child: ProgressPiecePill(percent: percent),
          ),
      ],
    );
  }
}
