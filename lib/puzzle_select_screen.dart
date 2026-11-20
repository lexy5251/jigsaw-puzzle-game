// Puzzle selection overview:
// 0. When a puzzle is unfinished, a "Continue puzzle" card sits on top:
//    the most recently played run, resumed in one tap (no size sheet).
// 1. A "Today's painting" card shows the daily puzzle with the
//    streak windowsill — a pot blooms for every day the daily was finished.
// 2. Below it, one painted card per themed category (owner-made cover art
//    from assets/covers/, accent tint, painting count); categories with no
//    images yet are hidden. Tapping a card opens that category's own
//    screen with its puzzle grid.
// 3. Starting a puzzle (daily card or category screen) goes through the
//    shared size-sheet flow in puzzle_launcher.dart.

import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'category_screen.dart';
import 'continue_puzzle_card.dart';
import 'daily_puzzle.dart';
import 'daily_puzzle_card.dart';
import 'daily_streak.dart';
import 'my_puzzles.dart';
import 'puzzle_catalog.dart';
import 'puzzle_launcher.dart';
import 'puzzle_save.dart';
import 'studio_surfaces.dart';
import 'studio_theme.dart';
import 'tab_activation.dart';

class PuzzleSelectScreen extends StatefulWidget {
  const PuzzleSelectScreen({super.key, this.clock, this.isActive = true});

  /// Returns "now"; tests fix the date to make the daily puzzle
  /// deterministic. Defaults to [DateTime.now].
  final DateTime Function()? clock;

  /// Whether the shell currently shows this tab; the daily status reloads
  /// when the tab becomes visible again (a daily can be finished from the
  /// My Puzzles tab's flows).
  final bool isActive;

  @override
  State<PuzzleSelectScreen> createState() => _PuzzleSelectScreenState();
}

class _PuzzleSelectScreenState extends State<PuzzleSelectScreen>
    with WidgetsBindingObserver, TabActivationAware<PuzzleSelectScreen> {
  static const _saveStore = SharedPreferencesSaveStore();
  static const _dailyStore = SharedPreferencesDailyStreakStore();

  /// Days on which the daily puzzle was finished (streak input).
  var _completedDailyDays = <String>{};

  /// The day a resumable run of today's daily would credit when finished
  /// (today, or yesterday for a run begun before midnight); null when no
  /// save would bloom anything.
  String? _dailyRunCredit;

  /// What the continue card reopens: the most recently played unfinished
  /// run across the FULL catalog (gallery, gifts, story). Today's daily
  /// painting is excluded only while the daily card already offers
  /// Continue for it. Null hides the card.
  InProgressRun? _continueRun;

  /// False until the first status load lands. The body renders nothing
  /// before that: painting defaults first would let the continue card pop
  /// in a frame later at the TOP of the list, shifting every control
  /// downward under an already-aimed tap — onto the one launcher with no
  /// size-sheet step. The load is a few prefs reads, so holding the first
  /// frame is imperceptible.
  bool _statusLoaded = false;

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
    // Only while this tab is showing — a resume on another tab is covered
    // by onTabActivated when the player comes back here.
    if (state == AppLifecycleState.resumed && widget.isActive) {
      unawaited(_refreshDailyStatus());
    }
  }

  @override
  bool isActiveOf(PuzzleSelectScreen widget) => widget.isActive;

  @override
  void onTabActivated() => unawaited(_refreshDailyStatus());

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  /// The day a resumable run of today's daily would credit when finished
  /// now — decided by [dailyCreditDay], the same rule the completion flow
  /// applies, so the card can never promise a bloom a finish won't deliver.
  /// A save that credits nothing (abandoned, or started on a day when this
  /// image was not the daily) does not count: showing "In progress" for it
  /// would mislead. Reads the refresh's one shared save-store snapshot.
  String? _dailyRunCreditDay(
    PuzzleImage daily,
    DateTime now,
    Map<String, PuzzleSaveState> saves,
  ) {
    for (final size in puzzleSizes) {
      final save =
          saves[puzzleSaveKey(
            imageId: daily.id,
            columns: size.columns,
            rows: size.rows,
          )];
      if (save == null || !save.isConsistentFor(size.pieceCount)) {
        continue;
      }
      final creditDay = dailyCreditDay(
        daily.id,
        now,
        startedDay: save.startedDay,
      );
      if (creditDay != null) {
        return creditDay;
      }
    }
    return null;
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
    // ONE save-store scan feeds both the daily credit check and the
    // continue card, instead of each re-reading the same keys.
    final saves = await loadAllSaves(_saveStore);
    final runCredit = _dailyRunCreditDay(daily, now, saves);
    // The FULL catalog: a bonus gift or story scene can be the most
    // recently played run, and this card must agree with My Puzzles
    // (which reads the full catalog for the same reason) about it.
    final summary = await loadMyPuzzlesSummary(
      saves: saves,
      catalog: fullPuzzleCatalog,
    );
    final continueRun = continueRunFrom(
      summary.inProgress,
      // The daily painting is left to the daily card ONLY while that card
      // actually offers Continue for its run (the run credits a pot). A
      // non-crediting run of the same painting would otherwise lose its
      // resume surface on the whole home screen for the day.
      excludedDailyId: runCredit != null ? daily.id : null,
    );
    // A read started before midnight must not overwrite the next day's data.
    if (!mounted || dayKey(now) != dayKey(_now)) {
      return;
    }
    // This runs on every app resume; skip the rebuild when nothing changed.
    // Never on the first load — that one must flip [_statusLoaded] even
    // when everything matches the field defaults.
    if (_statusLoaded &&
        dayKey(_dailyDate) == dayKey(now) &&
        setEquals(_completedDailyDays, days) &&
        _dailyRunCredit == runCredit &&
        _continueRun == continueRun) {
      return;
    }
    setState(() {
      _statusLoaded = true;
      _dailyDate = now;
      _completedDailyDays = days;
      _dailyRunCredit = runCredit;
      _continueRun = continueRun;
    });
  }

  Future<void> _resumeRun(InProgressRun run) async {
    await startPuzzleFlow(
      context,
      run.image,
      clock: widget.clock,
      resumeSize: run.size,
    );
    // The run may have advanced, finished, or chained into another puzzle.
    await _refreshDailyStatus();
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
      // Settings moved from a gear here to its own bottom-nav tab.
      appBar: risoAppBar('Choose a puzzle'),
      // Nothing until the first status load: see [_statusLoaded].
      body: !_statusLoaded
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_continueRun case final run?) ...[
                  ContinuePuzzleCard(run: run, onResume: () => _resumeRun(run)),
                  const SizedBox(height: 10),
                ],
                DailyPuzzleCard(
                  image: daily,
                  doneToday: _completedDailyDays.contains(dayKey(_dailyDate)),
                  inProgress: _dailyRunCredit != null,
                  // A fresh start always credits today; an in-progress run only
                  // when it was begun today (a yesterday-begun run blooms
                  // yesterday's pot, so the card must not promise today's).
                  bloomsToday:
                      _dailyRunCredit == null ||
                      _dailyRunCredit == dayKey(_dailyDate),
                  onPlay: () => _playDaily(daily),
                ),
                const SizedBox(height: 10),
                DailyStreakRow(
                  now: _dailyDate,
                  completedDays: _completedDailyDays,
                ),
                const SizedBox(height: 16),
                // Small-caps section kicker over the category cards (the
                // v17 mock's COLLECTIONS label).
                const Padding(
                  padding: EdgeInsets.only(left: 2, bottom: 10),
                  child: Text(
                    'COLLECTIONS',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.2,
                      color: StudioColors.structureDark,
                    ),
                  ),
                ),
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
                        (constraints.maxWidth - spacing * (columns - 1)) /
                        columns;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        for (final category in categories)
                          SizedBox(
                            width: cardWidth,
                            child: _CategoryCard(
                              category: category,
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

/// The run the home continue card shows: the newest unfinished run, under
/// two page rules. [excludedDailyId] — today's painting, passed ONLY while
/// the daily card above already offers Continue for it — is skipped so one
/// painting never wears two action cards. Fully placed runs (a finish
/// whose completion record never landed; opening one just replays the
/// recording) are skipped so the card never advertises "N of N pieces" as
/// something to continue.
@visibleForTesting
InProgressRun? continueRunFrom(
  List<InProgressRun> runs, {
  String? excludedDailyId,
}) {
  for (final run in runs) {
    if (run.image.id == excludedDailyId) {
      continue;
    }
    if (run.placedCount >= run.size.pieceCount) {
      continue;
    }
    return run;
  }
  return null;
}

/// One tappable collection on the home screen: cover painting, title,
/// count. No corner mascot chip — the owner ruled it clutter (UI-3).
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.onOpen,
  });

  final PuzzleCategory category;

  /// Wobble preset for [PaintedCard]; the grid passes its item index.

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final images = imagesInCategory(category.id);
    return PaintedCard(
      // One background for every card — the wallpaper color; the shadow
      // alone makes it read as a card, so it runs a touch deeper here
      // (owner ruling, UI-3 follow-up: the per-category tints are gone
      // on the main page).
      color: StudioColors.ground,
      shadow: PaintedCard.groundShadow,
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
              child: FramedArt(
                // The owner-made cover for this category (UI-3 ruling: the
                // "first catalog image" covers didn't sell the categories).
                child: Image.asset(
                  categoryCoverPath(category.id),
                  fit: BoxFit.cover,
                  // Decode smaller previews to reduce memory use.
                  cacheWidth: TiltedPhotoCard.thumbnailCacheWidth,
                  // A category without a cover file yet (e.g. a freshly
                  // added one) degrades to the old rule: first catalog
                  // painting.
                  errorBuilder: (context, _, _) => Image.asset(
                    images.first.assetPath,
                    fit: BoxFit.cover,
                    cacheWidth: TiltedPhotoCard.thumbnailCacheWidth,
                  ),
                ),
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
                '${images.length} paintings'.toUpperCase(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
