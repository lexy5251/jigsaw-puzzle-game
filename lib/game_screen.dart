// Game screen overview:
// 1. Receives the selected puzzle image and grid size.
// 2. Holds the running game for as long as this puzzle screen is open.
// 3. Displays the puzzle using Flame's GameWidget.
// 4. Keeps a back button to return to puzzle selection.
// 5. When the game reports completion, records it permanently and blurs
//    the finished board behind the completion card, timed to appear as the
//    in-game glow fades. The card offers the category's next unfinished
//    painting as one-tap "Next puzzle" (the screen pops with that painting
//    as its result and the launcher chains into it), with "Back to
//    gallery" as the exit.
// JigsawGame handles the puzzle gameplay.

import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'analytics.dart';
import 'app_settings.dart';
import 'bonus_track.dart';
import 'completion_card.dart';
import 'daily_puzzle.dart';
import 'daily_streak.dart';
import 'game_haptics.dart';
import 'game_sounds.dart';
import 'jigsaw_game.dart';
import 'puzzle_catalog.dart';
import 'puzzle_completion.dart';
import 'puzzle_logic.dart';
import 'puzzle_save.dart';
import 'riso_icons.dart';
import 'story_track.dart';
import 'studio_surfaces.dart';
import 'studio_theme.dart';
import 'whimsy_plan.dart';

/// The game route's pop result when the player taps "See the collection"
/// on the journey-unlock card: the launcher ends its chain and reports it,
/// and the host screen asks the shell to open My Puzzles → Collection.
/// Lives here (not in the launcher) so importing it never cycles — the
/// launcher already imports this file.
class OpenCollectionRequest {
  const OpenCollectionRequest();
}

/// Hosts one running puzzle.
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.image,
    required this.size,
    this.soundsFactory,
    this.haptics,
    this.clock,
    this.startedDay,
    this.settings = const AppSettings(),
    this.catalogs = const PuzzleCatalogs(),
    this.trayColumns = trayVisibleColumns,
    this.trayMaxThumbnailHeight = trayThumbnailHeightCap,
  });

  final PuzzleImage image;
  final PuzzleSize size;

  /// Where "Next puzzle" looks for what to offer — the gallery track for
  /// the category walk, the story track for scene order — and where the
  /// bonus compare finds its gift list. Tests supply fixture tracks; see
  /// [PuzzleCatalogs] for why the tracks must stay separate.
  final PuzzleCatalogs catalogs;

  /// Player preferences, read by the caller before this screen opens.
  final AppSettings settings;

  /// Each game owns its audio, so restarts need a fresh instance.
  /// When omitted the screen uses the real app sounds; tests supply fakes.
  final GameSounds Function()? soundsFactory;

  /// When omitted the screen uses the real device haptics; tests supply a
  /// recording fake. The vibration setting gates its use.
  final GameHaptics? haptics;

  /// Returns "now"; tests fix the date to make the daily puzzle
  /// deterministic. Defaults to [DateTime.now].
  final DateTime Function()? clock;

  /// Tray piece density, forwarded to the game; the preview harness renders
  /// candidate densities with it.
  final int trayColumns;

  /// Optional tray piece height ceiling, forwarded to the game; the preview
  /// harness renders the large-screen candidates with it.
  final double? trayMaxThumbnailHeight;

  /// Day key stamped on a FRESH board's save — the day the player committed
  /// to this run. The select screen passes the day its card was tapped, so
  /// a size sheet left open across midnight cannot shift the credited day.
  /// Defaults to the day this screen opens.
  final String? startedDay;

  /// Delay between the last piece locking and the completion card's
  /// reveal — the in-game glow (0.9s) plays out first. Tests pump this
  /// exact duration, so keep them on this constant.
  static const completionRevealDelay = Duration(milliseconds: 950);

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  static const _saveStore = SharedPreferencesSaveStore();
  static const _settingsStore = SharedPreferencesAppSettingsStore();

  bool _showCompletionCard = false;
  bool _restarting = false;

  /// Drives the Options menu so the screen can close it on system back
  /// and when the completion card reveals (the menu is an overlay, not a
  /// route — nothing else would).
  final MenuController _optionsController = MenuController();
  bool _optionsMenuOpen = false;

  /// The "Next puzzle" offer; null until completion resolves it (and stays
  /// null when the rest of the category is already done at this size).
  PuzzleImage? _nextImage;

  /// The gift painting this completion just unlocked; null when no bonus
  /// board finished (or the player pressed "Save for later").
  PuzzleImage? _bonusUnlock;

  /// Pieces already on the bonus board when THIS finish opened the journey
  /// (the 5th first finish); null hides the journey section — the usual
  /// case. Set at most once per install by nature of the boundary.
  int? _journeyPieces;

  Timer? _completionTimer;
  Timer? _revealFallbackTimer;
  bool _edgesOnly = false;
  late bool _showGhostPreview = widget.settings.ghostPreviewDefault;
  late BoardColorOption _boardColor = boardColorOptionFor(
    widget.settings.boardColorId,
  );

  /// Null until the game finishes loading, then whether it resumed a save.
  bool? _resumed;

  late JigsawGame _game = _createGame();

  /// Toggles the tray's edges-only filter from the app bar's tools pill.
  void _setEdgesOnly(bool edgesOnly) {
    // A finished frame makes the filter pointless — it would show an
    // empty tray with the interior pieces hidden, and no further lock
    // could trigger the auto-off below. Same rule, applied up front.
    if (edgesOnly && _game.frameComplete) {
      return;
    }
    Analytics.instance.edgesOnlyToggled(enabled: edgesOnly);
    setState(() => _edgesOnly = edgesOnly);
    _game.setEdgesOnlyFilter(edgesOnly);
  }

  /// The filter dismisses itself the moment the frame is complete — an
  /// edges-only tray with nothing left in it helps nobody (the genre
  /// leaders do the same). Deliberately no analytics event: the player
  /// didn't act.
  void _onPlacedCountChanged() {
    if (_edgesOnly && _game.frameComplete) {
      setState(() => _edgesOnly = false);
      _game.setEdgesOnlyFilter(false);
    }
  }

  DateTime get _now => (widget.clock ?? DateTime.now)();

  String get _saveKey => puzzleSaveKey(
    imageId: widget.image.id,
    columns: widget.size.columns,
    rows: widget.size.rows,
  );

  JigsawGame _createGame() {
    late final JigsawGame game;
    game = JigsawGame(
      imageAsset: widget.image.fileName,
      columns: widget.size.columns,
      rows: widget.size.rows,
      // The game owns and disposes its sounds, so a restart needs a fresh
      // instance — hence created here, not stored on the state.
      sounds:
          widget.soundsFactory?.call() ??
          FlameAudioSounds(volumeScale: widget.settings.effectsVolume),
      haptics: widget.settings.hapticsEnabled
          ? (widget.haptics ?? const SystemGameHaptics())
          : null,
      saveStore: _saveStore,
      saveKey: _saveKey,
      startedDay: widget.startedDay ?? dayKey(_now),
      clock: widget.clock,
      trayColumns: widget.trayColumns,
      trayMaxThumbnailHeight: widget.trayMaxThumbnailHeight,
      // The hidden figures this image can carry, matched to its scene.
      whimsyPool: whimsyPoolFor(widget.image),
      onCompleted: () => _onPuzzleCompleted(game),
      onBoardLoaded: (resumed) {
        if (mounted && !_restarting && identical(_game, game)) {
          setState(() => _resumed = resumed);
        }
      },
    );
    // All three setters are safe before the game loads: they store the
    // value, and loading applies it. Setting the color here is what keeps
    // it across restarts and "Next puzzle" chains (each builds a new game).
    game.setEdgesOnlyFilter(_edgesOnly);
    game.setGhostPreview(_showGhostPreview);
    game.setBoardColor(_boardColor);
    // Every new game gets the auto-off watcher here, so no construction
    // path can forget it; the matching removeListener lives in
    // _confirmRestart (old instance) and dispose.
    game.placedCount.addListener(_onPlacedCountChanged);
    return game;
  }

  /// The top bar's Options (…) drop-down: board color swatches, step zoom,
  /// and restart. Scrim-free, so the board keeps its true colors while the
  /// player compares swatches against it — the reason color taps and zoom
  /// taps keep the menu open.
  Widget _optionsMenu() {
    final theme = Theme.of(context);
    return MenuAnchor(
      controller: _optionsController,
      onOpen: () => setState(() => _optionsMenuOpen = true),
      onClose: () => setState(() => _optionsMenuOpen = false),
      // The closing tap must not also hit what's beneath it — the back
      // button or a puzzle piece.
      consumeOutsideTap: true,
      // Dressed like the app's sticker cards: the structure-ink border
      // carries the edge. Elevation stays low — higher values wrap the
      // shadow around the panel and it reads as a thick border (owner's
      // 11-17 menu-shadow ruling).
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(StudioColors.card),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(StudioColors.warmShadow),
        elevation: WidgetStatePropertyAll(3),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            side: BorderSide(color: StudioColors.structureInk, width: 2.5),
          ),
        ),
      ),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Board color',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: StudioColors.structureDark,
                ),
              ),
              const SizedBox(height: 10),
              // Three swatches per row; an open menu rebuilds on setState,
              // so the check mark follows the selection live.
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 3 * _swatchCell + 2 * _swatchGap,
                ),
                child: Wrap(
                  spacing: _swatchGap,
                  runSpacing: _swatchGap,
                  children: [
                    for (final option in boardColorOptions)
                      _BoardColorSwatch(
                        option: option,
                        selected: option.id == _boardColor.id,
                        onTap: () => _selectBoardColor(option),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 16),
        MenuItemButton(
          // Stays open: zoom is one step per tap, and the board visibly
          // zooming behind the menu is the feedback.
          closeOnActivate: false,
          leadingIcon: const RisoIcon(RisoGlyph.zoomIn, size: 22),
          onPressed: () => _game.zoomInStep(),
          child: const Text('Zoom in'),
        ),
        MenuItemButton(
          leadingIcon: const RisoIcon(RisoGlyph.startOver, size: 22),
          onPressed: _restarting ? null : _confirmRestart,
          child: const Text('Start over'),
        ),
      ],
      builder: (context, controller, child) => IconButton(
        tooltip: 'Options',
        visualDensity: VisualDensity.compact,
        icon: const RisoIcon(RisoGlyph.options),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  void _selectBoardColor(BoardColorOption option) {
    // Re-picking the active swatch changes nothing and is not an event.
    if (option.id != _boardColor.id) {
      Analytics.instance.boardColorChanged(colorId: option.id);
    }
    // setState so the GameWidget rebuilds — Flame only re-reads
    // backgroundColor() during the widget build (see setBoardColor).
    setState(() {
      _boardColor = option;
      _game.setBoardColor(option);
    });
    unawaited(_persistBoardColor(option.id));
  }

  Future<void> _persistBoardColor(String id) async {
    // Fresh read before writing: the blob also carries volume/ghost prefs,
    // and widget.settings may be stale against SettingsScreen edits.
    final current = await _settingsStore.load();
    await _settingsStore.save(current.copyWith(boardColorId: id));
  }

  /// Confirms, forgets the stored progress, and boots a fresh board.
  Future<void> _confirmRestart() async {
    if (_restarting) return;
    final restart = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start over?'),
        content: const Text("This puzzle's progress will be cleared."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start over'),
          ),
        ],
      ),
    );
    if (restart != true || !mounted || _restarting) {
      return;
    }
    _completionTimer?.cancel();
    _revealFallbackTimer?.cancel();
    setState(() {
      _restarting = true;
      _showCompletionCard = false;
      _nextImage = null;
      _bonusUnlock = null;
      _journeyPieces = null;
    });
    // Stop new writes before awaiting any old ones. An already-held finger
    // can still deliver a release after the dialog closes.
    await _game.discardProgress();
    if (!mounted) {
      return;
    }
    // The auto-off watcher must not outlive its game: unhook the old
    // notifier before _createGame hooks the new one.
    _game.placedCount.removeListener(_onPlacedCountChanged);
    setState(() {
      _resumed = null;
      _restarting = false;
      // The GameWidget's ObjectKey ensures the old widget is disposed too.
      _game = _createGame();
    });
    // A restart is a new run the launcher never sees — without this, the
    // start/complete funnel would show completions with no matching start.
    Analytics.instance.puzzleStarted(
      puzzleId: widget.image.id,
      pieceCount: widget.size.pieceCount,
      source: LaunchSource.restart,
    );
  }

  /// "resumed" vs "new puzzle" lets the Maestro flow verify that reopening
  /// actually restored the save instead of silently starting over.
  String get _boardSemanticsLabel => switch (_resumed) {
    null => 'Puzzle board',
    true => 'Puzzle board, resumed',
    false => 'Puzzle board, new puzzle',
  };

  Future<bool> _onPuzzleCompleted(JigsawGame game) async {
    if (!mounted || _restarting || !identical(_game, game)) return false;
    // Logged synchronously, BEFORE the awaits below and before the game
    // persists the finished board (which happens after this callback's
    // first suspension) — so a finished save can never exist whose event
    // didn't fire, and an exit mid-flow can't lose the count. The gate:
    // a board that loaded already finished is a replay of a recorded
    // finish (its celebration re-runs only so the record writes get their
    // retry) — counting it again would inflate completions for exactly
    // the players whose first write failed.
    if (!game.completedOnLoad) {
      Analytics.instance.puzzleCompleted(
        puzzleId: widget.image.id,
        pieceCount: widget.size.pieceCount,
      );
    }
    // The card reveals when BOTH the glow delay and its data (the
    // next-puzzle offer) are ready: the delay is armed first so storage
    // latency hides inside the 0.9s glow instead of stacking after it, and
    // the card still never appears with an unresolved hero button (the old
    // button-swap race).
    var delayElapsed = false;
    var dataReady = false;
    _completionTimer?.cancel();
    _revealFallbackTimer?.cancel();
    _completionTimer = Timer(GameScreen.completionRevealDelay, () {
      delayElapsed = true;
      if (dataReady) {
        _revealCompletionCard(game);
      } else {
        // Storage answers in microseconds normally; if it wedges, still
        // give the player the card (and its exit) instead of a dead end.
        _revealFallbackTimer = Timer(
          const Duration(seconds: 2),
          () => _revealCompletionCard(game),
        );
      }
    });

    // The persisted ids BEFORE this completion's writes, read ONCE per
    // finish: the story offer derives from them, and the bonus unlock is
    // "did these writes cross a board boundary", so both sides of that
    // compare must come from storage, not memory. Reading ahead of the
    // writes below keeps it from interleaving with them in the preferences
    // cache; the parse hides inside the glow delay armed above.
    const completionStore = SharedPreferencesCompletionStore();
    final idsBefore = await completedImageIds(completionStore);

    final next = await _findNextPuzzle(idsBefore);
    // The reveal depends only on the next-puzzle offer — it must not wait
    // on the record writes below, or a wedged write would hold the card
    // (and reassign _nextImage late, resurrecting the button-swap race on
    // the fallback path).
    if (!_restarting && identical(_game, game)) {
      _nextImage = next;
    }
    dataReady = true;
    if (delayElapsed) {
      _revealFallbackTimer?.cancel();
      _revealCompletionCard(game);
    }

    final daysBefore = await const SharedPreferencesDailyStreakStore()
        .completedDays();

    // The record writes run UNCONDITIONALLY from here: a completion the
    // player saw must be stored even if a restart or a chained replacement
    // lands while the read above was in flight — only the UI fields are
    // guarded. The streak write stays sequenced ahead of the completion
    // write so their reads cannot interleave in the preferences cache.
    final dailyRecorded = await _recordDailyCompletion(game.runStartedDay);

    // The game keeps its progress save until BOTH records are stored, so a
    // failed daily credit gets the same retry as a failed completion write:
    // resuming the finished save retries it. A day-late retry still credits via
    // the resumed-save grace, and re-marking an already-stored day is a
    // no-op success.
    final completionRecorded = await completionStore.markCompleted(
      puzzleCompletionKey(
        imageId: widget.image.id,
        columns: widget.size.columns,
        rows: widget.size.rows,
      ),
    );
    if (completionRecorded) {
      await _offerBonusUnlock(game, idsBefore: idsBefore, daysBefore: daysBefore);
    }
    return dailyRecorded && completionRecorded;
  }

  /// Shows the "Bonus puzzle unlocked" section on the completion card when
  /// the writes that just landed crossed a 25-piece boundary. Pieces come
  /// from first finishes (gift paintings filtered out — owner ruling) plus
  /// streak pieces, so a replay's set union is a no-op and nothing unlocks.
  /// If the completion write failed, the caller skips this entirely: the
  /// retained save retries the write (and this offer) on resume. A write
  /// that LANDS but whose card is never seen (exit before the reveal, or
  /// the late-write guard below) unlocks silently in Collection instead,
  /// like historic progress — the gift itself is never lost.
  Future<void> _offerBonusUnlock(
    JigsawGame game, {
    required Set<String> idsBefore,
    required Set<String> daysBefore,
  }) async {
    final firstFinishesBefore = galleryFirstFinishCount(
      idsBefore,
      bonusCatalog: widget.catalogs.gifts,
    );
    final firstFinishesAfter = galleryFirstFinishCount(
      {...idsBefore, widget.image.id},
      bonusCatalog: widget.catalogs.gifts,
    );
    // The streak write sequenced just before the completion write may have
    // added a day, so the after-side day set is re-read from storage.
    final daysAfter = await const SharedPreferencesDailyStreakStore()
        .completedDays();
    final piecesBefore = firstFinishesBefore + streakPieces(daysBefore);
    final piecesAfter = firstFinishesAfter + streakPieces(daysAfter);
    // THIS finish crossing the 5-finish line is the journey's one unlock
    // moment. It outranks a (rare) simultaneous gift unlock: the card
    // sends the player to Collection, where that gift already hangs.
    final journeyOpened =
        firstFinishesBefore < journeyUnlockFinishes &&
        firstFinishesAfter >= journeyUnlockFinishes;
    final unlocked = journeyOpened
        ? null
        : newlyUnlockedBonus(
            piecesBefore: piecesBefore,
            piecesAfter: piecesAfter,
            bonusCatalog: widget.catalogs.gifts,
          );
    // The !_showCompletionCard guard: on wedged storage the card can reveal
    // (via its fallback timer) before the writes land — inserting the gift
    // section into an already-interactive card would shove the action
    // buttons mid-tap. The late gift stays silent here and waits in
    // Collection; the reveal itself must never wait on writes (UI-4 rule).
    if ((unlocked != null || journeyOpened) &&
        mounted &&
        !_restarting &&
        !_showCompletionCard &&
        identical(_game, game)) {
      setState(() {
        _bonusUnlock = unlocked;
        if (journeyOpened) {
          // The count the Collection board will actually show — banked
          // streak pieces surface here as a head start.
          _journeyPieces = bonusTrackStateFor(
            firstFinishes: firstFinishesAfter,
            streakPieces: streakPieces(daysAfter),
            bonusCatalog: widget.catalogs.gifts,
          ).piecesOnCurrentBoard;
        }
      });
    }
  }

  /// Reveals the completion card (idempotent: a fallback reveal followed by
  /// late-arriving data just rebuilds the card with the data filled in).
  void _revealCompletionCard(JigsawGame game) {
    if (mounted && !_restarting && identical(_game, game)) {
      // A menu left open would float above the card (it lives in the app
      // overlay, which paints over this screen's whole stack).
      _optionsController.close();
      // The board is static by now (the glow self-removed at 0.9s), but a
      // running Flame loop repaints every frame, forcing the card's
      // backdrop blur to re-blur the whole screen each vsync. No resume
      // needed: every exit pops the route, and restart boots a fresh game.
      game.pauseEngine();
      setState(() => _showCompletionCard = true);
    }
  }

  /// Finishing a daily image at any size blooms the pot of the day the run
  /// began — the save's stamp (see [dailyCreditDay]). Returns false when a
  /// credit was due but could not be stored. The bloom itself is only shown
  /// on the home windowsill — the completion card stays celebration-free
  /// (owner's UI-4 ruling).
  Future<bool> _recordDailyCompletion(String? startedDay) async {
    final day = dailyCreditDay(
      widget.image.id,
      _now,
      startedDay: startedDay,
      catalog: widget.catalogs.gallery,
    );
    if (day == null) {
      return true;
    }
    const store = SharedPreferencesDailyStreakStore();
    if ((await store.completedDays()).contains(day)) {
      return true;
    }
    return store.markCompleted(day);
  }

  /// The category's next painting not yet completed at this grid size.
  /// Candidates are probed lazily in [nextPuzzleAfter]'s own order —
  /// typically one read — instead of prefetching the whole category, which
  /// also keeps the candidate-ordering rule in a single place.
  ///
  /// After a GIFT puzzle this is null by design: the bonus category is not
  /// in the gallery catalog, so the run ends on the exit button — never
  /// chain here with [fullPuzzleCatalog], or a finished gift would offer
  /// still-locked gifts as the next puzzle.
  ///
  /// After a STORY scene the offer IS the Story page's gate:
  /// [nextSceneToRead]'s longest-finished-prefix walk, with the just-solved
  /// scene counted as read ([completedBefore] predates this finish's
  /// write). One shared rule means the chain can never offer a scene the
  /// page still shows wrapped — a skip-completed walk would leap past the
  /// open scene on gapped records (a failed write mid-chain). A fully read
  /// story returns null and the run ends on the exit button.
  Future<PuzzleImage?> _findNextPuzzle(Set<String> completedBefore) async {
    if (widget.image.isStory) {
      return nextSceneToRead(
        {...completedBefore, widget.image.id},
        widget.catalogs.story,
      );
    }
    const store = SharedPreferencesCompletionStore();
    final completed = <String>{};
    while (true) {
      final candidate = nextPuzzleAfter(
        widget.image,
        completed,
        catalog: widget.catalogs.gallery,
      );
      if (candidate == null) {
        return null;
      }
      final done = await store.isCompletedForGrid(
        imageId: candidate.id,
        columns: widget.size.columns,
        rows: widget.size.rows,
      );
      if (!done) {
        return candidate;
      }
      completed.add(candidate.id);
    }
  }

  @override
  void dispose() {
    _game.placedCount.removeListener(_onPlacedCountChanged);
    _completionTimer?.cancel();
    _revealFallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The counter honors enlarged text up to the shared cap, then clamps:
    // with the two action buttons beside it the title slot is fixed-width,
    // and the tested width/scale matrix proves 2x is the widest that fits.
    final titleScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: _titleMaxTextScale);
    final counterHeight =
        19 + titleScaler.scale(16) * 1.1 + titleScaler.scale(9) * 1.1;
    return Stack(
      children: [
        // System back with the menu open must close the menu, not leave
        // the puzzle — the menu is an overlay, not a route, so no route
        // pop would dismiss it.
        PopScope(
          canPop: !_optionsMenuOpen,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              _optionsController.close();
            }
          },
          // The card's ModalBarrier blocks taps and semantics beneath it,
          // but not keyboard traversal — focus is excluded here so Tab on
          // web/desktop cannot reach the blurred-out controls either.
          child: ExcludeFocus(
            excluding: _showCompletionCard,
            child: Scaffold(
              // Constant tooltips and button texts double as semantics
              // labels for e2e tests.
              appBar: AppBar(
                toolbarHeight: counterHeight > kToolbarHeight
                    ? counterHeight
                    : kToolbarHeight,
                // The counter pill carries its own visual padding, and the
                // tools pill leaves the title slot tight on narrow
                // screens — default title spacing would only shrink the
                // counter further.
                titleSpacing: 0,
                title: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: _titleMaxTextScale,
                  // The tools pill leaves the title slot narrower than the
                  // tested width/scale matrix assumed; the FittedBox is the
                  // last-resort shrink for narrow screens at large scale.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ValueListenableBuilder<int>(
                      valueListenable: _game.placedCount,
                      builder: (context, placed, _) => _PaletteCounter(
                        placed: placed,
                        total: widget.size.pieceCount,
                      ),
                    ),
                  ),
                ),
                actions: [
                  _ToolsPill(
                    edgesOnly: _edgesOnly,
                    onEdgesOnlyChanged: _setEdgesOnly,
                    onReturnToTray: _game.returnLoosePiecesToTray,
                    ghostPreview: _showGhostPreview,
                    onGhostPreviewChanged: (enabled) {
                      setState(() => _showGhostPreview = enabled);
                      _game.setGhostPreview(enabled);
                    },
                    optionsMenu: _optionsMenu(),
                  ),
                ],
              ),
              // Labeled so e2e tests (and screen readers) can identify
              // the game screen — Flame's canvas exposes no semantics of
              // its own. No overlays: every play tool lives in the app
              // bar, so nothing can sit under a carried piece.
              body: IgnorePointer(
                ignoring: _restarting,
                child: Semantics(
                  label: _boardSemanticsLabel,
                  child: GameWidget(key: ObjectKey(_game), game: _game),
                ),
              ),
            ),
          ),
        ),
        // Above the Scaffold, not inside its body: the card's backdrop
        // blur must cover the app bar and its tools too.
        if (_showCompletionCard)
          CompletionCard(
            image: widget.image,
            pieceCount: widget.size.pieceCount,
            // A scene pops back to the Story tab, so the exit says so
            // instead of promising a gallery it won't show.
            exitLabel: widget.image.isStory
                ? 'Back to the story'
                : 'Back to gallery',
            onBackToGallery: () => Navigator.pop(context),
            // Popping with the painting hands the chain to the launcher's
            // flow loop, which pushes the next game at the same size.
            onNextPuzzle: switch (_nextImage) {
              null => null,
              final next => () => Navigator.pop(context, next),
            },
            // "Play now" rides the same chain; the gift is already earned,
            // so "Save for later" just tucks the section away — the painting
            // waits in My Puzzles → Collection either way.
            bonusUnlock: _bonusUnlock,
            onPlayBonus: switch (_bonusUnlock) {
              null => null,
              final bonus => () => Navigator.pop(context, bonus),
            },
            onSaveBonusForLater: () => setState(() => _bonusUnlock = null),
            // The journey's one unlock moment: popping with the request
            // ends the launcher's chain, and the host screen asks the
            // shell for My Puzzles → Collection.
            journeyPieces: _journeyPieces,
            onSeeCollection: () =>
                Navigator.pop(context, const OpenCollectionRequest()),
          ),
      ],
    );
  }
}

/// The placed-piece counter dressed as the painter's palette (mockup:
/// "the counter is a palette") — a linen daub with paint dots in the corner.
class _PaletteCounter extends StatelessWidget {
  const _PaletteCounter({required this.placed, required this.total});

  final int placed;
  final int total;

  /// The four studio paint colors, as on the mockup's palette.
  static const _paintDots = [
    Color(0xFFC06A45),
    Color(0xFF7B8456),
    Color(0xFFD9A33F),
    Color(0xFFD79B86),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$placed of $total pieces placed',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: const BoxDecoration(
          color: StudioColors.card,
          // Uneven ellipses make the chip read as a palette-shaped daub.
          borderRadius: BorderRadius.only(
            topLeft: Radius.elliptical(26, 20),
            topRight: Radius.elliptical(20, 26),
            bottomLeft: Radius.elliptical(22, 24),
            bottomRight: Radius.elliptical(28, 18),
          ),
          boxShadow: [_appBarCardShadow],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final color in _paintDots)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '$placed / $total',
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            Text(
              'pieces placed',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 9,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The soft warm lift shared by the app bar's two floating cards — the
/// palette counter and the tools pill. One source so the deliberately
/// matched surfaces cannot drift apart.
const _appBarCardShadow = BoxShadow(
  color: StudioColors.warmShadow,
  offset: Offset(0, 3),
  blurRadius: 10,
  spreadRadius: -5,
);

/// One cream pill holds every play tool (the genre leaders' layout,
/// owner's pick over buttons by the tray): piece tools left of the
/// divider, view/menu right. It mirrors the counter's card surface.
class _ToolsPill extends StatelessWidget {
  const _ToolsPill({
    required this.edgesOnly,
    required this.onEdgesOnlyChanged,
    required this.onReturnToTray,
    required this.ghostPreview,
    required this.onGhostPreviewChanged,
    required this.optionsMenu,
  });

  final bool edgesOnly;
  final ValueChanged<bool> onEdgesOnlyChanged;
  final VoidCallback onReturnToTray;
  final bool ghostPreview;
  final ValueChanged<bool> onGhostPreviewChanged;
  final Widget optionsMenu;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: const BoxDecoration(
          color: StudioColors.card,
          borderRadius: BorderRadius.all(Radius.circular(24)),
          boxShadow: [_appBarCardShadow],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            EdgesOnlyToggle(
              selected: edgesOnly,
              onChanged: onEdgesOnlyChanged,
            ),
            IconButton(
              tooltip: 'Return to tray',
              visualDensity: VisualDensity.compact,
              icon: const RisoIcon(RisoGlyph.broom),
              onPressed: onReturnToTray,
            ),
            Container(
              width: 1,
              height: 22,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              color: StudioColors.boardOutline,
            ),
            IconButton(
              tooltip: 'Image preview',
              visualDensity: VisualDensity.compact,
              isSelected: ghostPreview,
              icon: const RisoIcon(RisoGlyph.imagePreview),
              selectedIcon: const RisoIcon(
                RisoGlyph.imagePreview,
                color: StudioColors.tomato,
              ),
              onPressed: () => onGhostPreviewChanged(!ghostPreview),
            ),
            optionsMenu,
          ],
        ),
      ),
    );
  }
}

/// The "Edges only" toggle in the app bar's tools pill: the edge-piece
/// glyph alone, wearing a tomato circle while the filter is live (the
/// pill's strongest signal — the filter hides pieces, so its on-state
/// must not be missable). Visible only so tests can read [selected] where
/// they used to read the FilterChip's — not part of the screen's real API.
@visibleForTesting
class EdgesOnlyToggle extends StatelessWidget {
  const EdgesOnlyToggle({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    // MergeSemantics folds the button's own node into this one — without
    // it the toggled flag sits on a label-less ancestor and screen readers
    // announce the button with no on/off state.
    return MergeSemantics(
      child: Semantics(
        toggled: selected,
        child: IconButton(
          tooltip: 'Edges only',
          visualDensity: VisualDensity.compact,
          isSelected: selected,
          style: IconButton.styleFrom(
            backgroundColor: selected
                ? StudioColors.tomato
                : Colors.transparent,
            foregroundColor: selected
                ? StudioColors.onTomato
                : StudioColors.ink,
          ),
          icon: const RisoIcon(RisoGlyph.edgePiece),
          onPressed: () => onChanged(!selected),
        ),
      ),
    );
  }
}

/// Swatch cell edge and gap — the menu's "three per row" band width
/// derives from these, so resizing a swatch cannot break the wrap.
const _swatchCell = 48.0;
const _swatchGap = 12.0;

/// The title counter's text-scale cap. The AppBar height math and the
/// rendered title must clamp at the same point, or the bar's height is
/// computed for a different scale than its content draws at.
const _titleMaxTextScale = 2.0;

class _BoardColorSwatch extends StatelessWidget {
  const _BoardColorSwatch({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final BoardColorOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The check must read on any fill, so pick ink or cream by luminance.
    final checkColor = option.background.computeLuminance() < 0.35
        ? StudioColors.onTerracotta
        : StudioColors.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Board color: ${option.label}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: _swatchCell,
          height: _swatchCell,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                PaintedSwatch(color: option.background, size: 40),
                if (selected) Icon(Icons.check, size: 22, color: checkColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
