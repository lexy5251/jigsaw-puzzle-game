// The shared "tap a painting → pick a size → play" flow, used by the select
// screen's daily card and by every category screen.

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'daily_puzzle.dart';
import 'game_screen.dart';
import 'puzzle_catalog.dart';
import 'puzzle_completion.dart';
import 'puzzle_save.dart';

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
    if (await _saveStore.exists(key)) {
      savedSizes.add(size);
    }
  }
  return savedSizes;
}

/// Sizes of [image] that were finished at least once.
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

/// Opens the size sheet for [image] and, if a size is chosen, runs the game.
/// Returns once the player is back, so callers can refresh their state.
Future<void> startPuzzleFlow(
  BuildContext context,
  PuzzleImage image, {
  DateTime Function()? clock,
}) async {
  // The run belongs to the day the player tapped, even if the size sheet
  // below stays open across midnight.
  final startedDay = dayKey((clock ?? DateTime.now)());
  // Resolve each size's state BEFORE opening the sheet, so the sheet
  // itself stays plain synchronous UI (an async lookup inside its build
  // would re-trigger itself on every rebuild).
  final inProgressSizes = await _savedSizesFor(image);
  final completedSizes = await _completedSizesFor(image);
  // Read once here so GameScreen stays synchronous; mid-game settings
  // changes apply from the next puzzle on.
  final settings = await _settingsStore.load();
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

  // The sheet can be dismissed, or the host screen removed while it is open.
  if (selectedSize == null || !context.mounted) {
    return;
  }

  await Navigator.push<void>(
    context,
    MaterialPageRoute<void>(
      builder: (_) => GameScreen(
        image: image,
        size: selectedSize,
        clock: clock,
        startedDay: startedDay,
        settings: settings,
      ),
    ),
  );
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
