// The shared "tap a painting → play" flow: normally tap → size sheet →
// game, used by the select screen's daily card, every category screen, and
// My Puzzles. The home continue card enters with [startPuzzleFlow]'s
// `resumeSize` and skips the sheet — the one sheet-less launch path.

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

/// The intact save of [image] at [size], or null for a missing or corrupt
/// one — "intact" is the size sheet's bar for an "In progress" row.
Future<PuzzleSaveState?> _intactSaveFor(
  PuzzleImage image,
  PuzzleSize size,
) async {
  final save = await _saveStore.load(
    puzzleSaveKey(imageId: image.id, columns: size.columns, rows: size.rows),
  );
  return (save?.isConsistentFor(size.pieceCount) ?? false) ? save : null;
}

/// Whether one tap may reopen [image]'s run at [size] WITHOUT the sheet.
/// Stricter than the sheet's bar: the save must also be stamped against the
/// current catalog resolution, because the game's scale guard starts any
/// other width fresh — and a button that said Resume must never do that.
/// Width-mismatched (or pre-stamp) saves fall back to the sheet instead.
Future<bool> _canResumeDirectly(PuzzleImage image, PuzzleSize size) async {
  final save = await _intactSaveFor(image, size);
  return save != null && save.boardWidth == catalogImageWidth;
}

/// Sizes of [image] that have a saved game to resume.
Future<Set<PuzzleSize>> _savedSizesFor(PuzzleImage image) async {
  final savedSizes = <PuzzleSize>{};
  for (final size in puzzleSizes) {
    if (await _intactSaveFor(image, size) != null) {
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

/// True while a launch is between its first tap and its blocking route
/// being up — the size sheet, or the game route itself on a direct resume.
/// The store reads before either yield to the event loop, so a double-tap
/// (or a two-finger tap on two cards) would otherwise pass that gap twice
/// and stack a second sheet or game. Each path clears the flag in the same
/// synchronous step that pushes its route (no await can come between), so
/// the hand-over from flag to route barrier has no gap; it is NOT held for
/// the whole flow — a flow abandoned mid-route (tests tear screens down
/// constantly) must not jam the guard for every later launch.
var _launchInFlight = false;

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

  final choice = showModalBottomSheet<PuzzleSize>(
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
  // The sheet's route is pushed; its barrier now owns re-entry blocking.
  _launchInFlight = false;
  return choice;
}

/// Opens the size sheet for [image] and, if a size is chosen, runs the game —
/// chaining straight into each "Next puzzle" pick at the same size until the
/// player exits. Returns once the player is truly back, so callers can
/// refresh their state.
///
/// [resumeSize] (the home continue card) skips the sheet and reopens that
/// size's run in one tap — but only while its save is intact AND written at
/// the current photo resolution; anything else falls back to the sheet, so
/// the tap can never silently restart.
Future<void> startPuzzleFlow(
  BuildContext context,
  PuzzleImage image, {
  DateTime Function()? clock,
  // One bundle so fixture-driven flows stay fixtures across every chained
  // hop, not just the first screen.
  PuzzleCatalogs catalogs = const PuzzleCatalogs(),
  PuzzleSize? resumeSize,
}) async {
  if (_launchInFlight) {
    return;
  }
  _launchInFlight = true;
  try {
    // The run belongs to the day the player tapped, even if the size sheet
    // below stays open across midnight.
    var startedDay = dayKey((clock ?? DateTime.now)());
    // Read once here so GameScreen stays synchronous; mid-game settings
    // changes apply from the next puzzle on.
    var settings = await _settingsStore.load();
    if (!context.mounted) {
      return;
    }
    final PuzzleSize? pickedSize;
    if (resumeSize != null && await _canResumeDirectly(image, resumeSize)) {
      pickedSize = resumeSize;
    } else {
      if (!context.mounted) {
        return;
      }
      pickedSize = await _pickSizeFromSheet(context, image);
    }
    // The sheet can be dismissed, or the host screen removed while it is
    // open.
    if (pickedSize == null || !context.mounted) {
      return;
    }
    // Rebound: [pickedSize]'s promotion does not carry into the route
    // builder closure below (it is assigned inside this try), but an
    // initialized final local's does.
    final selectedSize = pickedSize;

    var current = image;
    while (true) {
      // The game screen pops with the painting the player chose via the
      // completion card's "Next puzzle" button, or null on a plain exit.
      final pushed = Navigator.push<PuzzleImage>(
        context,
        MaterialPageRoute<PuzzleImage>(
          builder: (_) => GameScreen(
            image: current,
            size: selectedSize,
            clock: clock,
            startedDay: startedDay,
            settings: settings,
            catalogs: catalogs,
          ),
        ),
      );
      // push inserted the route synchronously; the game screen now owns
      // re-entry blocking. A no-op after the sheet path (already cleared
      // when its sheet went up), load-bearing for the direct-resume path.
      _launchInFlight = false;
      final next = await pushed;
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
  } finally {
    _launchInFlight = false;
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
    final shape = RoundedRectangleBorder(
      borderRadius: _radius,
      side: selected
          // The sticker treatment marks the picked row (riso chrome).
          ? const BorderSide(color: StudioColors.structureInk, width: 2.5)
          : const BorderSide(color: StudioColors.boardOutline),
    );
    return DecoratedBox(
      // Side-less shape: this box exists only to carry the hard offset
      // shadow — the Material below paints the border, and giving both
      // the sided shape would stroke it twice (visibly darkening the
      // translucent unselected outline).
      decoration: ShapeDecoration(
        shape: const RoundedRectangleBorder(borderRadius: _radius),
        shadows: selected ? const [PaintedCard.groundShadow] : const [],
      ),
      child: Material(
        color: StudioColors.card,
        shape: shape,
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
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
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
      ),
    );
  }
}
