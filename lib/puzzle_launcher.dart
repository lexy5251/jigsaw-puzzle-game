// The shared "tap a painting → pick a size → play" flow, used by the select
// screen's daily card and by every category screen.

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'daily_puzzle.dart';
import 'game_screen.dart';
import 'puzzle_catalog.dart';
import 'puzzle_completion.dart';
import 'puzzle_save.dart';
import 'studio_surfaces.dart';
import 'studio_theme.dart';

const _saveStore = SharedPreferencesSaveStore();
const _completionStore = SharedPreferencesCompletionStore();
const _settingsStore = SharedPreferencesAppSettingsStore();

/// Sizes of [image] that have a saved game to resume.
Future<Set<PuzzleSize>> _savedSizesFor(PuzzleImage image) async {
  final savedSizes = <PuzzleSize>{};
  for (final size in puzzleSizes) {
    final key = puzzleSaveKey(
      imageId: image.id,
      columns: size.columns,
      rows: size.rows,
    );
    final save = await _saveStore.load(key);
    if (save?.isConsistentFor(size.pieceCount) ?? false) {
      savedSizes.add(size);
    }
  }
  return savedSizes;
}

/// Sizes of [image] that were finished at least once.
Future<Set<PuzzleSize>> _completedSizesFor(PuzzleImage image) async {
  final completedSizes = <PuzzleSize>{};
  for (final size in puzzleSizes) {
    final completed = await _completionStore.isCompletedForGrid(
      imageId: image.id,
      columns: size.columns,
      rows: size.rows,
    );
    if (completed) {
      completedSizes.add(size);
    }
  }
  return completedSizes;
}

/// Resolves both status sets, then opens the size sheet. Returns the chosen
/// size, or null when the sheet was dismissed or the host screen removed.
Future<PuzzleSize?> _pickSizeFromSheet(
  BuildContext context,
  PuzzleImage image,
) async {
  // Resolve each size's state BEFORE opening the sheet, so the sheet
  // itself stays plain synchronous UI (an async lookup inside its build
  // would re-trigger itself on every rebuild).
  final inProgressSizes = await _savedSizesFor(image);
  final completedSizes = await _completedSizesFor(image);
  if (!context.mounted) {
    return null;
  }

  return showModalBottomSheet<PuzzleSize>(
    context: context,
    // Canvas ground behind the options' linen cards — the themed sheet
    // default is the same linen, which would make the cards invisible.
    backgroundColor: StudioColors.ground,
    builder: (_) => _PuzzleSizePicker(
      image: image,
      inProgressSizes: inProgressSizes,
      completedSizes: completedSizes,
    ),
  );
}

/// Opens the size sheet for [image] and, if a size is chosen, runs the game —
/// chaining straight into each "Next puzzle" pick at the same size until the
/// player exits. Returns once the player is truly back, so callers can
/// refresh their state.
Future<void> startPuzzleFlow(
  BuildContext context,
  PuzzleImage image, {
  DateTime Function()? clock,
  List<PuzzleImage> catalog = puzzleCatalog,
}) async {
  // The run belongs to the day the player tapped, even if the size sheet
  // below stays open across midnight.
  var startedDay = dayKey((clock ?? DateTime.now)());
  // Read once here so GameScreen stays synchronous; mid-game settings
  // changes apply from the next puzzle on.
  var settings = await _settingsStore.load();
  if (!context.mounted) {
    return;
  }

  final selectedSize = await _pickSizeFromSheet(context, image);
  // The sheet can be dismissed, or the host screen removed while it is open.
  if (selectedSize == null || !context.mounted) {
    return;
  }

  var current = image;
  while (true) {
    // The game screen pops with the painting the player chose via the
    // completion card's "Next puzzle" button, or null on a plain exit.
    final next = await Navigator.push<PuzzleImage>(
      context,
      MaterialPageRoute<PuzzleImage>(
        builder: (_) => GameScreen(
          image: current,
          size: selectedSize,
          clock: clock,
          startedDay: startedDay,
          settings: settings,
          catalog: catalog,
        ),
      ),
    );
    if (next == null || !context.mounted) {
      return;
    }
    current = next;
    // The player commits to the new run now, not when the chain began.
    startedDay = dayKey((clock ?? DateTime.now)());
    settings = await _settingsStore.load();
    if (!context.mounted) {
      return;
    }
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              image.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final (index, size) in puzzleSizes.indexed) ...[
            if (index > 0) const SizedBox(height: 10),
            _sizeCard(context, index, size),
          ],
        ],
      ),
    );
  }

  /// One size option on its own painted card (the sheet matches the
  /// Studio look instead of default Material rows).
  Widget _sizeCard(BuildContext context, int index, PuzzleSize size) {
    final status = _statusLabel(context, size);
    return PaintedCard(
      // List position, so stacked cards get different wobbles.
      variant: index,
      onTap: () => Navigator.pop(context, size),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  identifier:
                      'puzzle-size-${image.id}-${size.columns}x${size.rows}',
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${size.pieceCount}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const TextSpan(text: ' pieces'),
                      ],
                    ),
                  ),
                ),
                Text(
                  '${size.columns} × ${size.rows}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          ?status,
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
