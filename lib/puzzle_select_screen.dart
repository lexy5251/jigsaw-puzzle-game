// Puzzle selection overview:
// 1. A "Today's painting" card on top shows the daily puzzle with the
//    streak windowsill — a pot blooms for every day the daily was finished.
// 2. Below it, one painted card per themed category (accent, mascot,
//    painting count); categories with no images yet are hidden. Tapping a
//    card opens that category's own screen with its puzzle grid.
// 3. Starting a puzzle (daily card or category screen) goes through the
//    shared size-sheet flow in puzzle_launcher.dart.

import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'category_screen.dart';
import 'daily_puzzle.dart';
import 'daily_puzzle_card.dart';
import 'daily_streak.dart';
import 'puzzle_catalog.dart';
import 'puzzle_launcher.dart';
import 'puzzle_save.dart';
import 'settings_screen.dart';
import 'studio_mascots.dart';
import 'studio_surfaces.dart';
import 'studio_theme.dart';

class PuzzleSelectScreen extends StatefulWidget {
  const PuzzleSelectScreen({super.key, this.clock});

  /// Returns "now"; tests fix the date to make the daily puzzle
  /// deterministic. Defaults to [DateTime.now].
  final DateTime Function()? clock;

  @override
  State<PuzzleSelectScreen> createState() => _PuzzleSelectScreenState();
}

class _PuzzleSelectScreenState extends State<PuzzleSelectScreen>
    with WidgetsBindingObserver {
  static const _saveStore = SharedPreferencesSaveStore();
  static const _dailyStore = SharedPreferencesDailyStreakStore();

  /// Days on which the daily puzzle was finished (streak input).
  var _completedDailyDays = <String>{};

  /// Whether today's daily image has a resumable save at any size.
  var _dailyInProgress = false;

  /// Keep the displayed date and its asynchronously loaded status together.
  late DateTime _dailyDate;
  Timer? _midnightTimer;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _dailyDate = _now;
    WidgetsBinding.instance.addObserver(this);
    _refreshDailyStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshDailyStatus());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  /// Whether today's daily has a resumable run that would still credit a
  /// pot: a save of its image whose stamped start day is inside the one-day
  /// credit window. An old abandoned save of the same image does not count —
  /// finishing it would not bloom anything, so showing "In progress" for it
  /// would mislead.
  Future<bool> _dailyRunInProgress(PuzzleImage daily, DateTime now) async {
    final today = utcMidnight(now);
    final creditableDays = {
      dayKey(today),
      dayKey(today.subtract(const Duration(days: 1))),
    };
    for (final size in puzzleSizes) {
      final save = await _saveStore.load(
        puzzleSaveKey(
          imageId: daily.id,
          columns: size.columns,
          rows: size.rows,
        ),
      );
      if (save != null &&
          save.isConsistentFor(size.pieceCount) &&
          creditableDays.contains(save.startedDay)) {
        return true;
      }
    }
    return false;
  }

  void _scheduleMidnightRefresh(DateTime now) {
    // Construct the next calendar midnight instead of adding 24 hours:
    // local days can be shorter or longer around daylight-saving changes.
    final nextMidnight = now.isUtc
        ? DateTime.utc(now.year, now.month, now.day + 1)
        : DateTime(now.year, now.month, now.day + 1);
    _midnightTimer?.cancel();
    _midnightTimer = Timer(
      nextMidnight.difference(now),
      () => unawaited(_refreshDailyStatus()),
    );
  }

  Future<void> _refreshDailyStatus() async {
    if (!mounted) {
      return;
    }
    final now = _now;
    _scheduleMidnightRefresh(now);

    final days = await _dailyStore.completedDays();
    final daily = dailyPuzzleFor(now);
    final inProgress = await _dailyRunInProgress(daily, now);
    // A read started before midnight must not overwrite the next day's data.
    if (!mounted || dayKey(now) != dayKey(_now)) {
      return;
    }
    // This runs on every app resume; skip the rebuild when nothing changed.
    if (dayKey(_dailyDate) == dayKey(now) &&
        setEquals(_completedDailyDays, days) &&
        _dailyInProgress == inProgress) {
      return;
    }
    setState(() {
      _dailyDate = now;
      _completedDailyDays = days;
      _dailyInProgress = inProgress;
    });
  }

  Future<void> _playDaily(PuzzleImage daily) async {
    await startPuzzleFlow(context, daily, clock: widget.clock);
    // Finishing it changes the windowsill; refresh when the player returns.
    await _refreshDailyStatus();
  }

  Future<void> _openCategory(PuzzleCategory category) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CategoryScreen(category: category, clock: widget.clock),
      ),
    );
    // Today's daily may have been finished from inside the category.
    await _refreshDailyStatus();
  }

  @override
  Widget build(BuildContext context) {
    final daily = dailyPuzzleFor(_dailyDate);
    final categories = [
      for (final category in puzzleCategories)
        if (imagesInCategory(category.id).isNotEmpty) category,
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a puzzle'),
        actions: [
          IconButton(
            // Constant tooltip doubles as the semantics label for e2e tests.
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DailyPuzzleCard(
            image: daily,
            now: _dailyDate,
            completedDays: _completedDailyDays,
            inProgress: _dailyInProgress,
            onPlay: () => _playDaily(daily),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 16.0;
              // Keep the responsive columns, but let card heights follow
              // their content when enlarged text wraps onto extra lines.
              final columns = max(
                1,
                (constraints.maxWidth / (260 + spacing)).ceil(),
              );
              final cardWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final (index, category) in categories.indexed)
                    SizedBox(
                      width: cardWidth,
                      child: _CategoryCard(
                        category: category,
                        variant: index,
                        onOpen: () => _openCategory(category),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The category's mascot on a small painted disc over the cover's corner.
class _MascotChip extends StatelessWidget {
  const _MascotChip({required this.mascot});

  final StudioMascot mascot;

  @override
  Widget build(BuildContext context) {
    return Container(
      // A fixed disc, so wide mascots (mountains, houses) and tall ones
      // (daisy) all read as the same-size chip; FittedBox scales each into it.
      width: 30,
      height: 30,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: BoxShape.circle,
      ),
      child: FittedBox(child: MascotArt(mascot, height: 64)),
    );
  }
}

/// One tappable collection on the home screen: cover painting, mascot
/// chip, title, count.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.variant,
    required this.onOpen,
  });

  final PuzzleCategory category;

  /// Wobble preset for [PaintedCard]; the grid passes its item index.
  final int variant;

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final style = categoryStyleFor(category.id);
    final images = imagesInCategory(category.id);
    // The first catalog image is the cover: stable between visits, so
    // players can find a collection by its picture, and curated simply by
    // ordering the catalog.
    final cover = images.first;
    return PaintedCard(
      variant: variant,
      color: style.tint,
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(9, 9, 9, 10),
      child: Semantics(
        // Lets e2e tests open a category without matching on its title.
        identifier: 'category-${category.id}',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 3 / 2,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FramedArt(
                    child: Image.asset(
                      cover.assetPath,
                      fit: BoxFit.cover,
                      // Decode smaller previews to reduce memory use.
                      cacheWidth: 640,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _MascotChip(mascot: mascotForCategory(category.id)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
              child: Text(
                category.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                '${images.length} paintings',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
