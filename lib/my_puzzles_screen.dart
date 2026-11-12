// My Puzzles screen overview:
// 1. Two top tabs, one card per photo on each (owner ruling: never repeat
//    a photo per size). "In progress" cards are bare photos — the owner
//    dropped the progress chip for now, it sat heavy on the art;
//    "Finished" chips name the piece counts done (his explicit pick).
// 2. Tapping any card opens the usual size sheet — the same flow as the
//    category pages — where every size shows its own In progress /
//    Completed status.
// 3. Cards are picture-only like the category grids (names live in the
//    semantics labels); the lists reload after a game closes and whenever
//    the shell makes this tab visible again.

import 'package:flutter/material.dart';

import 'my_puzzles.dart';
import 'puzzle_catalog.dart';
import 'puzzle_launcher.dart';
import 'studio_mascots.dart';
import 'studio_surfaces.dart';
import 'studio_theme.dart';

class MyPuzzlesScreen extends StatefulWidget {
  const MyPuzzlesScreen({super.key, this.clock, this.isActive = true});

  /// Returns "now"; tests fix the date to make daily credit deterministic.
  /// Defaults to [DateTime.now].
  final DateTime Function()? clock;

  /// Whether the shell currently shows this tab. The shell keeps tabs
  /// alive (scroll and tab selection survive switches), so becoming
  /// visible again — not being rebuilt — is the reload signal.
  final bool isActive;

  @override
  State<MyPuzzlesScreen> createState() => _MyPuzzlesScreenState();
}

class _MyPuzzlesScreenState extends State<MyPuzzlesScreen> {
  /// Null until the stores answer; the page renders nothing before that so
  /// it never flashes an empty state it is about to replace.
  MyPuzzlesSummary? _summary;

  /// Tilt by catalog position, not list index: these lists reorder by
  /// recency, and an index-based tilt would flip cards between visits.
  static final _tiltVariants = {
    for (final (index, image) in puzzleCatalog.indexed) image.id: index,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MyPuzzlesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A run may have started or finished from another tab's flows.
    if (widget.isActive && !oldWidget.isActive) {
      _load();
    }
  }

  Future<void> _load() async {
    final summary = await loadMyPuzzlesSummary();
    if (mounted) {
      setState(() => _summary = summary);
    }
  }

  Future<void> _open(PuzzleImage image) async {
    await startPuzzleFlow(context, image, clock: widget.clock);
    // The run may have moved tabs (or new ones begun) while the game was
    // open.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Puzzles'),
          bottom: const TabBar(
            tabs: [Tab(text: 'In progress'), Tab(text: 'Finished')],
          ),
        ),
        body: summary == null
            ? const SizedBox.shrink()
            : TabBarView(
                children: [_inProgressTab(summary), _finishedTab(summary)],
              ),
      ),
    );
  }

  Widget _inProgressTab(MyPuzzlesSummary summary) {
    if (summary.inProgress.isEmpty) {
      return const _EmptyTab(
        mascot: StudioMascot.sprout,
        message: 'Nothing on the easel yet — pick a painting in the Gallery.',
      );
    }
    return _photoGrid('in-progress', summary.inProgress.length, (index) {
      final run = summary.inProgress[index];
      return TiltedPhotoCard(
        assetPath: run.image.assetPath,
        title: run.image.title,
        semanticsIdentifier: 'my-puzzles-in-progress-${run.image.id}',
        variant: _tiltVariants[run.image.id] ?? 0,
        onTap: () => _open(run.image),
      );
    });
  }

  Widget _finishedTab(MyPuzzlesSummary summary) {
    if (summary.finished.isEmpty) {
      return const _EmptyTab(
        mascot: StudioMascot.cactus,
        message: "No finished paintings yet — they'll hang here.",
      );
    }
    return _photoGrid('finished', summary.finished.length, (index) {
      final photo = summary.finished[index];
      final counts = photo.completedSizes
          .map((size) => '${size.pieceCount}')
          .join(' · ');
      return TiltedPhotoCard(
        assetPath: photo.image.assetPath,
        title: photo.image.title,
        semanticsIdentifier: 'my-puzzles-finished-${photo.image.id}',
        variant: _tiltVariants[photo.image.id] ?? 0,
        onTap: () => _open(photo.image),
        overlays: [
          // Anchored strip, not a bare bottom/right Positioned: an
          // unconstrained chip would run off the card's left edge once a
          // photo is finished at three or four sizes.
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Align(
              alignment: Alignment.centerRight,
              child: _CountChip('$counts pieces'),
            ),
          ),
        ],
      );
    });
  }

  /// The category pages' grid; the storage key keeps each tab's scroll
  /// offset alive across tab switches (TabBarView disposes hidden tabs).
  Widget _photoGrid(
    String name,
    int itemCount,
    Widget Function(int index) item,
  ) {
    return GridView.builder(
      key: PageStorageKey('my-puzzles-$name'),
      padding: photoGridPadding,
      gridDelegate: photoGridDelegate,
      itemCount: itemCount,
      itemBuilder: (context, index) => item(index),
    );
  }
}

/// Count pill on a photo corner: "24 · 96 pieces" on the finished wall.
class _CountChip extends StatelessWidget {
  const _CountChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: const BoxDecoration(
        color: StudioColors.card,
        borderRadius: BorderRadius.all(Radius.circular(999)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          // Full-strength ink: the theme's softened bodySmall washes out
          // on busy photos.
          color: StudioColors.ink,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// A tab with nothing to list yet: mascot + one friendly line.
class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.mascot, required this.message});

  final StudioMascot mascot;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PaintedCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              MascotArt(mascot, height: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
