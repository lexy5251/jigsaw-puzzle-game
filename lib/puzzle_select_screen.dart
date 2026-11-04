// Puzzle selection overview:
// 1. A "Today's painting" card on top shows the daily puzzle with the
//    streak windowsill — a pot blooms for every day the daily was finished.
// 2. Below it, the catalog grouped into themed categories; categories with
//    no images yet are hidden. Images finished at any size get a check badge.
// 3. Tapping an image opens a sheet with the available puzzle sizes, marking
//    sizes that are in progress or already completed.
// 4. Choosing a size opens GameScreen with that image and size.
// 5. Dismissing the sheet leaves the user on the selection screen.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'daily_puzzle.dart';
import 'daily_puzzle_card.dart';
import 'daily_streak.dart';
import 'game_screen.dart';
import 'puzzle_catalog.dart';
import 'puzzle_completion.dart';
import 'puzzle_save.dart';
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
  static const _completionStore = SharedPreferencesCompletionStore();
  static const _dailyStore = SharedPreferencesDailyStreakStore();

  /// Images finished at least once, at any size.
  var _completedImageIds = <String>{};

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
    _refreshCompletedImages();
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
        puzzleSaveKey(imageId: daily.id, columns: size.columns, rows: size.rows),
      );
      if (creditableDays.contains(save?.startedDay)) {
        return true;
      }
    }
    return false;
  }

  Future<Set<PuzzleSize>> _savedSizesFor(PuzzleImage image) async {
    final savedSizes = <PuzzleSize>{};
    for (final size in puzzleSizes) {
      final key = puzzleSaveKey(
        imageId: image.id,
        columns: size.columns,
        rows: size.rows,
      );
      if (await _saveStore.exists(key)) {
        savedSizes.add(size);
      }
    }
    return savedSizes;
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
    if (mounted && !setEquals(_completedImageIds, completed)) {
      setState(() => _completedImageIds = completed);
    }
  }

  Future<Set<PuzzleSize>> _completedSizesFor(PuzzleImage image) async {
    final completedSizes = <PuzzleSize>{};
    for (final size in puzzleSizes) {
      final key = puzzleCompletionKey(
        imageId: image.id,
        columns: size.columns,
        rows: size.rows,
      );
      if (await _completionStore.isCompleted(key)) {
        completedSizes.add(size);
      }
    }
    return completedSizes;
  }

  Future<void> _startPuzzle(BuildContext context, PuzzleImage image) async {
    // The run belongs to the day the player tapped, even if the size sheet
    // below stays open across midnight.
    final startedDay = dayKey(_now);
    // Resolve each size's state BEFORE opening the sheet, so the sheet
    // itself stays plain synchronous UI (an async lookup inside its build
    // would re-trigger itself on every rebuild).
    final inProgressSizes = await _savedSizesFor(image);
    final completedSizes = await _completedSizesFor(image);
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
        builder: (_) => GameScreen(
          image: image,
          size: selectedSize,
          clock: widget.clock,
          startedDay: startedDay,
        ),
      ),
    );

    // A puzzle (possibly today's daily) may have been finished while the
    // game screen was open. The two reads are independent.
    await Future.wait([_refreshCompletedImages(), _refreshDailyStatus()]);
  }

  @override
  Widget build(BuildContext context) {
    final daily = dailyPuzzleFor(_dailyDate);
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a puzzle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DailyPuzzleCard(
            image: daily,
            now: _dailyDate,
            completedDays: _completedDailyDays,
            inProgress: _dailyInProgress,
            onPlay: () => _startPuzzle(context, daily),
          ),
          const SizedBox(height: 16),
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
          child: Row(
            children: [
              PaintedSwatch(color: categoryStyleFor(category.id).accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
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
              // Grid position, so side-by-side cards get different wobbles.
              variant: index,
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
    required this.variant,
    required this.isCompleted,
    required this.onTap,
  });

  final PuzzleImage image;

  /// Wobble preset for [PaintedCard]; the grid passes its item index.
  final int variant;

  /// Finished at least once, at any size: shows the check badge.
  final bool isCompleted;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PaintedCard(
      variant: variant,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(9, 9, 9, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                FramedArt(
                  child: Image.asset(
                    image.assetPath,
                    fit: BoxFit.cover,
                    // Decode smaller previews to reduce memory use.
                    cacheWidth: 640,
                  ),
                ),
                if (isCompleted)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: _CompletedBadge(),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
            child: Semantics(
              // Distinguish this catalog tile from the daily card in e2e tests.
              identifier: 'catalog-puzzle-${image.id}',
              child: Text(
                image.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ],
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
              title: Semantics(
                identifier:
                    'puzzle-size-${image.id}-${size.columns}x${size.rows}',
                child: Text('${size.pieceCount} pieces · ${size.label}'),
              ),
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
      return Semantics(
        // Identify this size's status independently of the daily card's status.
        identifier:
            'puzzle-in-progress-${image.id}-${size.columns}x${size.rows}',
        child: Text(
          'In progress',
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
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
