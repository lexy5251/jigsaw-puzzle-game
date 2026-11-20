// My Puzzles screen overview:
// 1. Three top tabs, one card per photo on each (owner ruling: never repeat
//    a photo per size). "In progress" cards are bare photos — the owner
//    dropped the progress chip for now, it sat heavy on the art;
//    "Finished" chips name the piece counts done (his explicit pick).
// 2. Tapping any card opens the usual size sheet — the same flow as the
//    home grid — where every size shows its own In progress /
//    Completed status.
// 3. Cards are picture-only like the home grid (names live in the
//    semantics labels); the lists reload after a game closes and whenever
//    the shell makes this tab visible again.
// 4. "Collection" is the bonus track: the current gift painting assembling
//    piece by piece, then the earned gifts as ordinary playable cards. The
//    first two tabs track gift paintings too once they are played — the
//    summary reads the full catalog, gallery and gifts alike.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'bonus_board.dart';
import 'bonus_track.dart';
import 'daily_streak.dart';
import 'my_puzzles.dart';
import 'puzzle_catalog.dart';
import 'puzzle_completion.dart';
import 'puzzle_launcher.dart';
import 'studio_mascots.dart';
import 'riso_markers.dart';
import 'studio_surfaces.dart';
import 'studio_theme.dart';
import 'tab_activation.dart';

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

class _MyPuzzlesScreenState extends State<MyPuzzlesScreen>
    with TabActivationAware<MyPuzzlesScreen> {
  /// Null until the stores answer; the page renders nothing before that so
  /// it never flashes an empty state it is about to replace.
  MyPuzzlesSummary? _summary;

  /// Loaded together with [_summary], so the body gate below covers both.
  BonusTrackState? _bonus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  bool isActiveOf(MyPuzzlesScreen widget) => widget.isActive;

  // A run may have started or finished from another tab's flows.
  @override
  void onTabActivated() => _load();

  Future<void> _load() async {
    // ONE completion snapshot feeds both the summary tabs and the bonus
    // track, so the two can never disagree within a single load.
    final completions = await const SharedPreferencesCompletionStore()
        .loadAllCompletionRecords();
    // The full catalog, so played gift paintings reach the first two tabs.
    final summary = await loadMyPuzzlesSummary(
      catalog: fullPuzzleCatalog,
      completions: completions,
    );
    final days = await const SharedPreferencesDailyStreakStore()
        .completedDays();
    final bonus = bonusTrackStateFor(
      firstFinishes: galleryFirstFinishCount(
        imageIdsFromCompletions(completions),
      ),
      streakPieces: streakPieces(days),
    );
    if (mounted) {
      setState(() {
        _summary = summary;
        _bonus = bonus;
      });
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
    final bonus = _bonus;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: risoAppBar(
          'My Puzzles',
          bottom: const TabBar(
            tabs: [
              Tab(text: 'In progress'),
              Tab(text: 'Finished'),
              Tab(text: 'Collection'),
            ],
          ),
        ),
        body: summary == null || bonus == null
            ? const SizedBox.shrink()
            : TabBarView(
                children: [
                  _inProgressTab(summary),
                  _finishedTab(summary),
                  _collectionTab(bonus),
                ],
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
        onTap: () => _open(run.image),
        overlays: [
          // The tab already means "started"; the pill adds how far.
          Positioned(
            right: 9,
            bottom: 10,
            child: ProgressPiecePill(
              // Capped at 99 like the category pill: 100% is the done
              // sticker's word, and near-finishes would round up to it.
              percent: math.min(
                99,
                (run.placedCount * 100 / run.size.pieceCount).round(),
              ),
            ),
          ),
        ],
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

  Widget _collectionTab(BonusTrackState bonus) {
    // Before the fifth finished painting the journey stays a quiet promise
    // (owner's design): no board, no gift wall, just the invitation.
    if (!bonus.journeyUnlocked) {
      final remaining = bonus.finishesUntilJourney;
      return ListView(
        key: const PageStorageKey('my-puzzles-collection'),
        padding: photoGridPadding,
        children: [
          Semantics(
            identifier: 'journey-teaser',
            container: true,
            child: _MessageCard(
              mascot: StudioMascot.pot,
              message: remaining == 1
                  ? 'Finish 1 more puzzle to open the journey.'
                  : 'Finish $remaining more puzzles to open the journey.',
            ),
          ),
        ],
      );
    }
    final board = bonus.currentBoard;
    return ListView(
      key: const PageStorageKey('my-puzzles-collection'),
      padding: photoGridPadding,
      children: [
        if (board != null)
          BonusBoardCard(
            image: board,
            earnedPieces: bonus.piecesOnCurrentBoard,
          )
        else
          const _MessageCard(
            mascot: StudioMascot.sunflower,
            message:
                'Every bonus picture is yours — more are on the way.',
          ),
        if (bonus.unlocked.isNotEmpty) ...[
          const SizedBox(height: 16),
          GridView.builder(
            // Scrolls with the ListView around it; the gift wall stays a
            // handful of cards, so building them all at once is fine.
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: photoGridDelegate,
            itemCount: bonus.unlocked.length,
            itemBuilder: (context, index) {
              final image = bonus.unlocked[index];
              return TiltedPhotoCard(
                assetPath: image.assetPath,
                title: image.title,
                semanticsIdentifier: 'my-puzzles-collection-${image.id}',
                onTap: () => _open(image),
              );
            },
          ),
        ],
      ],
    );
  }

  /// The home grid's geometry; the storage key keeps each tab's scroll
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
      children: [_MessageCard(mascot: mascot, message: message)],
    );
  }
}

/// Mascot + one friendly line on a painted card; the empty tabs and the
/// Collection's all-earned state share it.
class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.mascot, required this.message});

  final StudioMascot mascot;
  final String message;

  @override
  Widget build(BuildContext context) {
    return PaintedCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          MascotArt(mascot, height: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
