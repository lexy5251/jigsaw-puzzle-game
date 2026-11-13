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
    // Canvas ground behind the linen size rows — the themed sheet default
    // is the same linen, which would make them invisible.
    backgroundColor: StudioColors.ground,
    // The default half-screen cap would crowd out the framed preview. The
    // height cap moves inside the sheet (a LayoutBuilder), so it tracks
    // rotation and window resizes while the sheet is open — a constraint
    // passed here is frozen at open time.
    isScrollControlled: true,
    // Passing constraints at all discards Material 3's defaults, so the
    // 640 width cap must come along explicitly or wide screens get an
    // edge-to-edge sheet.
    constraints: const BoxConstraints(maxWidth: 640),
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

/// The size the sheet opens on: a resumable run first (resuming is the
/// likeliest next action), else the smallest size not finished yet, else
/// the smallest size.
@visibleForTesting
PuzzleSize initialSheetSize({
  required Set<PuzzleSize> inProgress,
  required Set<PuzzleSize> completed,
}) {
  for (final size in puzzleSizes) {
    if (inProgress.contains(size)) {
      return size;
    }
  }
  for (final size in puzzleSizes) {
    if (!completed.contains(size)) {
      return size;
    }
  }
  return puzzleSizes.first;
}

/// What launching a size will do. Derived once per size so the row's
/// status word and the launch button's verb can never disagree.
enum _SizeStatus { resume, replay, fresh }

/// The redesigned size sheet (owner's pick, 2026-11-13): the painting in
/// its cream-mat frame, a list of size rows, and a single launch button
/// that states what it will do — so replaying a finished size is always an
/// explicit "Play again" press, never a silent restart.
class _PuzzleSizePicker extends StatefulWidget {
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
  State<_PuzzleSizePicker> createState() => _PuzzleSizePickerState();
}

class _PuzzleSizePickerState extends State<_PuzzleSizePicker> {
  late PuzzleSize _selected = initialSheetSize(
    inProgress: widget.inProgressSizes,
    completed: widget.completedSizes,
  );

  /// Marks the pre-selected row so it can be revealed on open.
  final _selectedRowKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // The list always opens at the top, but the pre-selected size (the one
    // the launch button already names) can sit below the fold in a short
    // window — reveal it. showOnScreen scrolls minimally and is a no-op
    // when the row is already visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectedRowKey.currentContext?.findRenderObject()?.showOnScreen();
    });
  }

  _SizeStatus _statusFor(PuzzleSize size) {
    // "In progress" wins over "Completed" (owner's call): resuming is the
    // next action, and a resume can never silently restart anything.
    if (widget.inProgressSizes.contains(size)) {
      return _SizeStatus.resume;
    }
    if (widget.completedSizes.contains(size)) {
      return _SizeStatus.replay;
    }
    return _SizeStatus.fresh;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      // Measured here, not at showModalBottomSheet time, so the cap tracks
      // rotation and window resizes while the sheet is open.
      child: LayoutBuilder(
        builder: (context, viewport) {
          final maxSheetHeight = viewport.maxHeight * 0.75;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxSheetHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title, preview, and rows all share one scroll view, so
                  // even enormous accessibility text can only push content
                  // behind the fold — never out of existence. The launch
                  // button stays pinned below.
                  Flexible(
                    // Not a lazy ListView: offscreen rows must exist up
                    // front for the open-time reveal and screen readers
                    // (a shrink-wrapped list ignores cacheExtent and
                    // builds only visible rows), and the list is tiny.
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            widget.image.title,
                            style: theme.textTheme.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          // A glance at the photo is enough (owner's call);
                          // on short screens it cedes space to the rows.
                          Center(
                            child: _framedPreview(
                              theme,
                              side: (maxSheetHeight * 0.25).clamp(0.0, 120.0),
                            ),
                          ),
                          const SizedBox(height: 14),
                          // One row per size (owner's pick over chips) —
                          // extra catalog sizes later just mean more rows.
                          for (final (index, size) in puzzleSizes.indexed) ...[
                            if (index > 0) const SizedBox(height: 8),
                            _SizeOption(
                              key: size == _selected ? _selectedRowKey : null,
                              image: widget.image,
                              size: size,
                              selected: size == _selected,
                              status: _statusFor(size),
                              onTap: () => setState(() => _selected = size),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    identifier: 'puzzle-start',
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, _selected),
                      child: Text(_actionLabel()),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _framedPreview(ThemeData theme, {required double side}) {
    // A fixed square, not a Flexible slot: flex shares would leave the
    // frame below its cap on phones and strand blank space around it on
    // tablets. Square matches the catalog; anything else is cover-cropped.
    return SizedBox.square(
      dimension: side,
      child: FramedArt(
        child: ColoredBox(
          color: StudioColors.card,
          child: Image.asset(
            widget.image.assetPath,
            fit: BoxFit.cover,
            cacheWidth: TiltedPhotoCard.thumbnailCacheWidth,
            // Same fallback as the photo grids: a failed decode shows the
            // title instead of an anonymous blank frame.
            errorBuilder: (context, _, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  widget.image.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _actionLabel() {
    final pieces = '${_selected.pieceCount} pieces';
    return switch (_statusFor(_selected)) {
      _SizeStatus.resume => 'Resume · $pieces',
      _SizeStatus.replay => 'Play again · $pieces',
      _SizeStatus.fresh => 'Start · $pieces',
    };
  }
}

/// One size row: piece count on the left, status in a plain word on the
/// right (owner's call — icon marks read as vague).
class _SizeOption extends StatelessWidget {
  const _SizeOption({
    super.key,
    required this.image,
    required this.size,
    required this.selected,
    required this.status,
    required this.onTap,
  });

  final PuzzleImage image;
  final PuzzleSize size;
  final bool selected;
  final _SizeStatus status;
  final VoidCallback onTap;

  static const _radius = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: StudioColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: _radius,
        side: selected
            ? const BorderSide(color: StudioColors.ink, width: 2)
            : const BorderSide(color: StudioColors.boardOutline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: _radius,
        // The labeled node below owns the activation; without this the
        // InkWell adds a second, unlabeled tap stop per row for screen
        // readers and switch access.
        excludeFromSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  // The stable e2e hook. The labeled node must own the
                  // activation too — screen readers send their tap here.
                  identifier:
                      'puzzle-size-${image.id}-${size.columns}x${size.rows}',
                  label: '${size.pieceCount} pieces',
                  button: true,
                  selected: selected,
                  onTap: onTap,
                  child: ExcludeSemantics(
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
                ),
              ),
              // The Maestro e2e flow (resume_after_restart.yaml) asserts
              // these exact status texts — change them together.
              if (status == _SizeStatus.resume)
                Semantics(
                  // Identify this size's status independently of the daily
                  // card's status text.
                  identifier:
                      'puzzle-in-progress-${image.id}-'
                      '${size.columns}x${size.rows}',
                  child: Text(
                    statusInProgressLabel,
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                )
              else if (status == _SizeStatus.replay)
                Text(
                  statusCompletedLabel,
                  style: TextStyle(color: theme.colorScheme.tertiary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
