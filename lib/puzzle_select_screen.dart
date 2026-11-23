// Puzzle selection overview:
// 0. When a puzzle is unfinished, a "Continue puzzle" card sits on top:
//    the most recently played run, resumed in one tap (no size sheet).
// 1. A "Today's painting" card shows the daily puzzle with the
//    streak row — a piece clicks in for every day the daily was finished.
// 2. Below them, the whole gallery as ONE grid of photo cards, narrowed in
//    place by a scrolling row of filter chips ("All" + one per category;
//    owner's layout-B ruling — covers and per-category pages are gone).
//    Started paintings wear the % piece pill, finished ones the done
//    sticker, exactly like the retired category grid did.
// 3. Starting a puzzle (daily card or grid) goes through the shared
//    size-sheet flow in puzzle_launcher.dart.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'analytics.dart';
import 'bonus_track.dart';
import 'continue_puzzle_card.dart';
import 'daily_puzzle.dart';
import 'daily_puzzle_card.dart';
import 'daily_streak.dart';
import 'my_puzzles.dart';
import 'puzzle_catalog.dart';
import 'puzzle_completion.dart';
import 'puzzle_launcher.dart';
import 'puzzle_save.dart';
import 'riso_markers.dart';
import 'studio_surfaces.dart';
import 'studio_theme.dart';
import 'tab_activation.dart';

class PuzzleSelectScreen extends StatefulWidget {
  const PuzzleSelectScreen({
    super.key,
    this.clock,
    this.isActive = true,
    this.catalog = puzzleCatalog,
  });

  /// Returns "now"; tests fix the date to make the daily puzzle
  /// deterministic. Defaults to [DateTime.now].
  final DateTime Function()? clock;

  /// Whether the shell currently shows this tab; the status reloads
  /// when the tab becomes visible again (a daily can be finished from the
  /// My Puzzles tab's flows).
  final bool isActive;

  /// Where the grid's images come from. Tests supply a small fixture
  /// catalog so grid tests stay independent of the real bundled photos.
  /// The daily card and continue card deliberately keep reading the real
  /// catalogs — fixture saves never produce either.
  final List<PuzzleImage> catalog;

  @override
  State<PuzzleSelectScreen> createState() => _PuzzleSelectScreenState();
}

class _PuzzleSelectScreenState extends State<PuzzleSelectScreen>
    with WidgetsBindingObserver, TabActivationAware<PuzzleSelectScreen> {
  static const _saveStore = SharedPreferencesSaveStore();
  static const _dailyStore = SharedPreferencesDailyStreakStore();
  static const _completionStore = SharedPreferencesCompletionStore();

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

  /// Grid images finished at least once, at any size (done sticker).
  var _completedImageIds = <String>{};

  /// Best progress percent per grid image with a resumable save (the piece
  /// pill; the player must be able to spot a started puzzle — and how far
  /// it got — without opening its size sheet).
  var _progressPercents = <String, int>{};

  /// The selected filter chip; null shows the whole catalog ("All").
  String? _selectedCategoryId;

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

  /// Best progress percent per grid image, from the refresh's one shared
  /// save-store snapshot. The pill shows the furthest run: the most
  /// advanced save of any size speaks for the painting. Capped at 99: only
  /// the done sticker may say "complete", and 224/225 would otherwise
  /// round up to a lying 100%.
  Map<String, int> _progressPercentsFrom(
    Map<String, PuzzleSaveState> saves,
    Map<String, CompletionRecord> completions,
    Set<String> gridIds,
  ) {
    final sizesByGrid = {
      for (final size in puzzleSizes) (size.columns, size.rows): size,
    };
    final percents = <String, int>{};
    for (final MapEntry(:key, value: save) in saves.entries) {
      final parsed = parsePuzzleSaveKey(key);
      if (parsed == null || !gridIds.contains(parsed.imageId)) {
        continue;
      }
      final size = sizesByGrid[(parsed.columns, parsed.rows)];
      if (size == null || !save.isConsistentFor(size.pieceCount)) {
        continue;
      }
      // Same rule as buildMyPuzzlesSummary: an interrupted final snap can
      // leave a fully locked save behind; once its completion record
      // landed, the painting is done — a 99% pill next to the done sticker
      // would lie (without the record, the save is the retry vehicle and
      // the pill rightly stays).
      if (save.lockedPieceIndexes.length == size.pieceCount &&
          completions.containsKey(
            puzzleCompletionKey(
              imageId: parsed.imageId,
              columns: size.columns,
              rows: size.rows,
            ),
          )) {
        continue;
      }
      final percent = math.min(
        99,
        (save.lockedPieceIndexes.length * 100 / size.pieceCount).round(),
      );
      final best = percents[parsed.imageId];
      if (best == null || percent > best) {
        percents[parsed.imageId] = percent;
      }
    }
    return percents;
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
    // ONE scan per store feeds everything on this page: the saves snapshot
    // serves the daily credit check, the continue card AND the grid pills;
    // the completions snapshot serves the continue card AND the done
    // stickers. Nothing below re-reads a store.
    final saves = await loadAllSaves(_saveStore);
    final completions = await _completionStore.loadAllCompletionRecords();
    final runCredit = _dailyRunCreditDay(daily, now, saves);
    // The FULL catalog: a bonus gift or story scene can be the most
    // recently played run, and this card must agree with My Puzzles
    // (which reads the full catalog for the same reason) about it.
    final summary = await loadMyPuzzlesSummary(
      saves: saves,
      completions: completions,
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
    final gridIds = {for (final image in widget.catalog) image.id};
    final completed = imageIdsFromCompletions(completions)
        .intersection(gridIds);
    final percents = _progressPercentsFrom(saves, completions, gridIds);
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
        _continueRun == continueRun &&
        setEquals(_completedImageIds, completed) &&
        mapEquals(_progressPercents, percents)) {
      return;
    }
    setState(() {
      _statusLoaded = true;
      _dailyDate = now;
      _completedDailyDays = days;
      _dailyRunCredit = runCredit;
      _continueRun = continueRun;
      _completedImageIds = completed;
      _progressPercents = percents;
    });
  }

  Future<void> _resumeRun(InProgressRun run) async {
    await startPuzzleFlow(
      context,
      run.image,
      source: LaunchSource.continueCard,
      clock: widget.clock,
      resumeSize: run.size,
    );
    // The run may have advanced, finished, or chained into another puzzle.
    await _refreshDailyStatus();
  }

  Future<void> _playDaily(PuzzleImage daily) async {
    await startPuzzleFlow(
      context,
      daily,
      source: LaunchSource.daily,
      clock: widget.clock,
    );
    // Finishing it changes the streak row; refresh when the player returns.
    await _refreshDailyStatus();
  }

  Future<void> _openPuzzle(PuzzleImage image) async {
    // Forward this screen's catalog so "Next puzzle" picks from the same
    // set the grid shows (a fixture catalog in tests, the global one live).
    await startPuzzleFlow(
      context,
      image,
      source: LaunchSource.gallery,
      clock: widget.clock,
      catalogs: PuzzleCatalogs(gallery: widget.catalog),
    );
    // The puzzle may have been started or finished while the game was open.
    await _refreshDailyStatus();
  }

  @override
  Widget build(BuildContext context) {
    final daily = dailyPuzzleFor(_dailyDate);
    final categories = [
      for (final category in puzzleCategories)
        if (imagesInCategory(category.id, catalog: widget.catalog).isNotEmpty)
          category,
    ];
    final gridImages = _selectedCategoryId == null
        ? widget.catalog
        : imagesInCategory(_selectedCategoryId!, catalog: widget.catalog);
    return PopScope(
      // A selected filter is not a route, but Android back should still
      // "leave the category" the way it left the old pushed pages: first
      // back clears the filter to All, only then does back exit the app.
      canPop: _selectedCategoryId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(() => _selectedCategoryId = null);
        }
      },
      child: Scaffold(
        // Settings moved from a gear here to its own bottom-nav tab.
        appBar: risoAppBar('Choose a puzzle'),
        // Nothing until the first status load: see [_statusLoaded]. The new
        // grid state rides the same load, so the first painted frame already
        // wears its pills and stickers — nothing pops in later.
        body: !_statusLoaded
            ? const SizedBox.shrink()
            : CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_continueRun case final run?) ...[
                            ContinuePuzzleCard(
                              run: run,
                              onResume: () => _resumeRun(run),
                            ),
                            const SizedBox(height: 10),
                          ],
                          DailyPuzzleCard(
                            image: daily,
                            doneToday: _completedDailyDays.contains(
                              dayKey(_dailyDate),
                            ),
                            inProgress: _dailyRunCredit != null,
                            // A fresh start always credits today; an in-progress
                            // run only when it was begun today (a
                            // yesterday-begun run blooms yesterday's pot, so the
                            // card must not promise today's).
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
                        ],
                      ),
                    ),
                  ),
                  // Full-bleed so chips scroll under the screen edge; the row
                  // carries the 16dp gutters itself.
                  SliverToBoxAdapter(
                    child: _CategoryChipRow(
                      categories: categories,
                      selectedId: _selectedCategoryId,
                      onSelect: (id) =>
                          setState(() => _selectedCategoryId = id),
                    ),
                  ),
                  SliverPadding(
                    padding: photoGridPadding,
                    sliver: SliverGrid.builder(
                      // Max width instead of a fixed column count: 2 across on
                      // phones so the photo is big enough to judge (UI-6
                      // ruling), more columns on tablets and the web build.
                      gridDelegate: photoGridDelegate,
                      itemCount: gridImages.length,
                      itemBuilder: (context, index) {
                        final image = gridImages[index];
                        return _PuzzleCard(
                          image: image,
                          isCompleted: _completedImageIds.contains(image.id),
                          progressPercent: _progressPercents[image.id],
                          onTap: () => _openPuzzle(image),
                        );
                      },
                    ),
                  ),
                ],
              ),
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

/// The horizontally scrolling filter row: "All" + one chip per non-empty
/// category. The selected chip wears the sticker treatment (owner's
/// style-C ruling): blush fill plus the hard violet offset shadow.
class _CategoryChipRow extends StatelessWidget {
  const _CategoryChipRow({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
  });

  final List<PuzzleCategory> categories;

  /// The selected category id; null means "All".
  final String? selectedId;

  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      // Mouse drag is off Flutter's default dragDevices and horizontal
      // scrollables get no scrollbar on web/desktop — without this, chips
      // past the right edge are unreachable for mouse-only users.
      behavior: ScrollConfiguration.of(context)
          .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // Bottom padding leaves room for the selected chip's offset shadow.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 5),
        child: Row(
          children: [
            _FilterChip(
              label: 'All',
              identifier: 'category-all',
              selected: selectedId == null,
              onTap: () => onSelect(null),
            ),
            for (final category in categories) ...[
              const SizedBox(width: 8),
              _FilterChip(
                label: category.title,
                // The same identifier the category cards wore, so the Maestro
                // flow's selectors keep working unchanged.
                identifier: 'category-${category.id}',
                selected: selectedId == category.id,
                onTap: () => onSelect(category.id),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.identifier,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String identifier;
  final bool selected;
  final VoidCallback onTap;

  static const _radius = BorderRadius.all(Radius.circular(999));

  /// The chip's own hard shadow: smaller than [PaintedCard.groundShadow]
  /// so the lift reads at pill size.
  static const _selectedShadow = BoxShadow(
    color: StudioColors.cardShadow,
    offset: Offset(3, 3),
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      // Side-less shape: this box exists only to carry the hard offset
      // shadow — the Material below paints the border (same split as the
      // size sheet's rows, and for the same double-stroke reason).
      decoration: ShapeDecoration(
        shape: const RoundedRectangleBorder(borderRadius: _radius),
        shadows: selected ? const [_selectedShadow] : const [],
      ),
      child: Material(
        color: selected ? StudioColors.chip : StudioColors.card,
        shape: const RoundedRectangleBorder(
          borderRadius: _radius,
          // Thinner than PaintedCard.borderWidth on purpose: 2.5 reads
          // heavy at pill size (the approved filter-row mock uses 2).
          side: BorderSide(color: StudioColors.structureInk, width: 2),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: _radius,
          // The labeled node below owns the activation; without this the
          // InkWell adds a second, unlabeled tap stop per chip for screen
          // readers and switch access.
          excludeFromSemantics: true,
          child: Padding(
            // Vertical padding brings the tap target to 48dp at default
            // text size (20dp text line + 2x14; measured — the 2px border
            // paints inside and adds nothing); large text grows it further.
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Semantics(
              // The stable e2e hook. The labeled node must own the
              // activation too — screen readers send their tap here.
              identifier: identifier,
              label: label,
              button: true,
              selected: selected,
              onTap: onTap,
              child: ExcludeSemantics(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One painting in the grid: picture-only photo card; started runs wear
/// the % piece pill, finished ones the overhanging done sticker.
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
