// My Puzzles data overview:
// 1. InProgressRun / FinishedPhoto are what the My Puzzles screen lists:
//    each photo once per tab — in-progress photos represented by their
//    newest resumable save (the owner ruled against repeating a photo per
//    size; the size sheet disambiguates on tap).
// 2. buildMyPuzzlesSummary is pure — it folds raw store contents into two
//    sorted lists — so the rules (what to skip, how to sort) unit-test
//    without widgets or storage.
// 3. loadMyPuzzlesSummary is the thin async wrapper the screen calls.

import 'puzzle_catalog.dart';
import 'puzzle_completion.dart';
import 'puzzle_save.dart';

/// One resumable save: a photo at one grid size. The summary keeps only
/// the newest run per photo — it stands for the photo on the page.
class InProgressRun {
  const InProgressRun({
    required this.image,
    required this.size,
    required this.placedCount,
    this.startedDay,
    this.savedAt,
  });

  final PuzzleImage image;
  final PuzzleSize size;

  /// Pieces locked into place — the same count the in-game palette counter
  /// shows (loose pieces on the board are not placed yet). The page's
  /// "20/24 pieces" chip was removed for now (owner: sat heavy on the
  /// art); kept for when progress gets a better visual.
  final int placedCount;

  /// Day key ("2026-11-02") the run began; null for old saves. Ordering
  /// fallback for saves written before [savedAt] existed.
  final String? startedDay;

  /// When the run was last saved — the primary "most recently played"
  /// ordering key; null for saves from before the stamp existed.
  final DateTime? savedAt;

  // Value equality, so consumers (the home screen's rebuild-skip) can
  // compare summaries with == and a field added here can never silently
  // escape a hand-rolled comparison elsewhere.
  @override
  bool operator ==(Object other) =>
      other is InProgressRun &&
      other.image.id == image.id &&
      other.size.columns == size.columns &&
      other.size.rows == size.rows &&
      other.placedCount == placedCount &&
      other.startedDay == startedDay &&
      other.savedAt == savedAt;

  @override
  int get hashCode => Object.hash(
    image.id,
    size.columns,
    size.rows,
    placedCount,
    startedDay,
    savedAt,
  );
}

/// One photo finished at least once, at any size.
class FinishedPhoto {
  const FinishedPhoto({
    required this.image,
    required this.completedSizes,
    required this.lastCompletedAt,
  });

  final PuzzleImage image;

  /// Sizes finished at least once, in [puzzleSizes] order.
  final List<PuzzleSize> completedSizes;

  /// Newest completion across all sizes.
  final DateTime lastCompletedAt;
}

/// What the My Puzzles screen shows: both lists, already sorted.
class MyPuzzlesSummary {
  const MyPuzzlesSummary({required this.inProgress, required this.finished});

  final List<InProgressRun> inProgress;
  final List<FinishedPhoto> finished;
}

/// Folds raw store contents into the two sorted lists.
///
/// Entries are skipped when their photo left the catalog or their grid is no
/// longer offered (nothing tappable could open them), and saves that fail
/// [PuzzleSaveState.isConsistentFor] (same rule as the sprout badge and the
/// size sheet). A save written against a different image resolution stays
/// listed: the game's own scale guard already starts it fresh on open.
MyPuzzlesSummary buildMyPuzzlesSummary({
  required Map<String, PuzzleSaveState> saves,
  required Map<String, CompletionRecord> completions,
  List<PuzzleImage> catalog = puzzleCatalog,
  List<PuzzleSize> sizes = puzzleSizes,
}) {
  final imagesById = {for (final image in catalog) image.id: image};
  final sizesByGrid = {
    for (final size in sizes) (size.columns, size.rows): size,
  };
  // Catalog position breaks date ties, so equal days keep the familiar
  // gallery order instead of map-iteration order.
  final catalogOrder = {
    for (final (index, image) in catalog.indexed) image.id: index,
  };
  int byCatalog(PuzzleImage a, PuzzleImage b) =>
      catalogOrder[a.id]!.compareTo(catalogOrder[b.id]!);

  final inProgress = <InProgressRun>[];
  for (final entry in saves.entries) {
    final parsed = parsePuzzleSaveKey(entry.key);
    if (parsed == null) {
      continue;
    }
    final image = imagesById[parsed.imageId];
    final size = sizesByGrid[(parsed.columns, parsed.rows)];
    if (image == null || size == null) {
      continue;
    }
    if (!entry.value.isConsistentFor(size.pieceCount)) {
      continue;
    }
    // An interrupted final snap can leave a fully locked save behind; once
    // its completion record landed, the run belongs to the Finished wall
    // only (without the record, the save is the retry vehicle — keep it).
    if (entry.value.lockedPieceIndexes.length == size.pieceCount &&
        completions.containsKey(
          puzzleCompletionKey(
            imageId: image.id,
            columns: size.columns,
            rows: size.rows,
          ),
        )) {
      continue;
    }
    inProgress.add(
      InProgressRun(
        image: image,
        size: size,
        placedCount: entry.value.lockedPieceIndexes.length,
        startedDay: entry.value.startedDay,
        savedAt: entry.value.savedAt,
      ),
    );
  }
  // Hoisted: the comparator runs O(n log n) times per summary build.
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  inProgress.sort((a, b) {
    // Most recently played first. The epoch floor sinks stamp-less (pre-
    // savedAt) saves behind every stamped one; among themselves they fall
    // through to the started-day rule below.
    final bySaved = (b.savedAt ?? epoch).compareTo(a.savedAt ?? epoch);
    if (bySaved != 0) {
      return bySaved;
    }
    // Newest start first; day keys are ISO dates, so string order IS date
    // order, and '' sinks day-less (pre-field) saves to the end.
    final byDay = (b.startedDay ?? '').compareTo(a.startedDay ?? '');
    if (byDay != 0) {
      return byDay;
    }
    final byImage = byCatalog(a.image, b.image);
    return byImage != 0
        ? byImage
        : a.size.pieceCount.compareTo(b.size.pieceCount);
  });
  // One card per photo (owner ruling): the newest run stands for it — it
  // decides the sort position — and the size sheet disambiguates on tap.
  final seenImages = <String>{};
  final newestRunPerPhoto = [
    for (final run in inProgress)
      if (seenImages.add(run.image.id)) run,
  ];

  final completedByImage = <String, List<(PuzzleSize, CompletionRecord)>>{};
  for (final entry in completions.entries) {
    final parsed = parsePuzzleCompletionKey(entry.key);
    if (parsed == null) {
      continue;
    }
    final image = imagesById[parsed.imageId];
    final size = sizesByGrid[(parsed.columns, parsed.rows)];
    if (image == null || size == null) {
      continue;
    }
    completedByImage.putIfAbsent(image.id, () => []).add((size, entry.value));
  }
  final finished = <FinishedPhoto>[];
  for (final entry in completedByImage.entries) {
    final doneSizes = {for (final (size, _) in entry.value) size};
    finished.add(
      FinishedPhoto(
        image: imagesById[entry.key]!,
        completedSizes: [
          for (final size in sizes)
            if (doneSizes.contains(size)) size,
        ],
        lastCompletedAt: entry.value
            .map((pair) => pair.$2.lastCompletedAt)
            .reduce((a, b) => a.isAfter(b) ? a : b),
      ),
    );
  }
  finished.sort((a, b) {
    final byDate = b.lastCompletedAt.compareTo(a.lastCompletedAt);
    return byDate != 0 ? byDate : byCatalog(a.image, b.image);
  });

  return MyPuzzlesSummary(inProgress: newestRunPerPhoto, finished: finished);
}

/// Every stored save by key. The home screen reads this once per refresh
/// and derives both the daily-credit check and the continue card from it.
Future<Map<String, PuzzleSaveState>> loadAllSaves(
  PuzzleSaveStore saveStore,
) async {
  final saves = <String, PuzzleSaveState>{};
  for (final key in await saveStore.listSavedKeys()) {
    final state = await saveStore.load(key);
    if (state != null) {
      saves[key] = state;
    }
  }
  return saves;
}

/// Reads both stores and builds the summary. The screen passes its injected
/// stores; defaults are the device-local ones. A caller that already loaded
/// a store's snapshot passes it ([completions] — the My Puzzles screen
/// shares one read with the bonus track; [saves] — the home screen shares
/// one read with the daily card's credit check) so each store is scanned
/// once per refresh.
Future<MyPuzzlesSummary> loadMyPuzzlesSummary({
  PuzzleSaveStore saveStore = const SharedPreferencesSaveStore(),
  PuzzleCompletionStore completionStore =
      const SharedPreferencesCompletionStore(),
  Map<String, CompletionRecord>? completions,
  Map<String, PuzzleSaveState>? saves,
  List<PuzzleImage> catalog = puzzleCatalog,
  List<PuzzleSize> sizes = puzzleSizes,
}) async {
  return buildMyPuzzlesSummary(
    saves: saves ?? await loadAllSaves(saveStore),
    completions:
        completions ?? await completionStore.loadAllCompletionRecords(),
    catalog: catalog,
    sizes: sizes,
  );
}
