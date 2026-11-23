// Story screen overview:
// 1. One story told through puzzles: eight scenes, read strictly in order,
//    laid out as a winding dotted trail (owner's pick, 2026-11-22). Read
//    scenes sit on the trail as small framed stops wearing era tags; the
//    next scene arrives as a bow-tied parcel on a dashed missing-piece
//    slot; scenes further ahead are empty slots — nothing is spoiled.
// 2. Celebrations play ONCE each (story_celebration.dart): a new unlock
//    snaps the read scene in and pops the fresh path dots; the player
//    tears the parcel open themselves; reading all eight lights the whole
//    trail and blooms THE END plaque.
// 3. Tapping the open scene's card runs the normal size-sheet flow;
//    tapping a read stop opens its story lines for rereading. Progress is
//    derived in story_track.dart; this screen renders and celebrates it.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'analytics.dart';
import 'app_settings.dart';
import 'bonus_track.dart';
import 'game_haptics.dart';
import 'game_sounds.dart';
import 'puzzle_catalog.dart';
import 'puzzle_completion.dart';
import 'puzzle_launcher.dart';
import 'story_celebration.dart';
import 'story_track.dart';
import 'story_trail_art.dart';
import 'studio_mascots.dart';
import 'studio_surfaces.dart';
import 'studio_theme.dart';
import 'tab_activation.dart';

/// Header progress line; shared with tests.
String storyProgressText(int found, int total) =>
    '$found of $total scenes found';

/// The mystery card's invitation; shared with tests.
const storyNextHintText = 'Tap to piece this scene together.';

/// The closing line on THE END plaque once every scene is read; shared
/// with tests.
const storyEndText = 'The whole story is yours — it stays right here.';

/// The pill over the waiting parcel; shared with tests.
const storyTapToOpenText = 'Tap to open';

/// Caption under the first not-yet-reachable slot; shared with tests.
const storyNotFoundYetText = 'Not found yet';

class StoryScreen extends StatefulWidget {
  const StoryScreen({
    super.key,
    this.clock,
    this.isActive = true,
    this.celebrationStore = const SharedPreferencesStoryCelebrationStore(),
    this.sounds,
    this.haptics,
  });

  /// Returns "now"; tests fix the date to make daily credit deterministic.
  /// Defaults to [DateTime.now].
  final DateTime Function()? clock;

  /// Whether the shell currently shows this tab. The shell keeps tabs
  /// alive, so becoming visible again — not being rebuilt — is the reload
  /// signal.
  final bool isActive;

  /// Remembers which one-time celebrations have played.
  final StoryCelebrationStore celebrationStore;

  /// Cue overrides for tests; the screen otherwise plays the bundled cues
  /// at the player's effects volume and honors the vibrate setting.
  final GameSounds? sounds;
  final GameHaptics? haptics;

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen>
    with TickerProviderStateMixin, TabActivationAware<StoryScreen> {
  static const _settingsStore = SharedPreferencesAppSettingsStore();

  /// Null until the store answers; the page renders nothing before that so
  /// it never flashes a locked list it is about to replace.
  StoryState? _story;
  StoryCelebrations _seen = const StoryCelebrations();
  AppSettings _settings = const AppSettings();

  GameSounds? _ownedSounds;

  /// The volume [_ownedSounds] was built with; a settings change rebuilds
  /// the cues so the tab-long screen never plays at a stale volume.
  double? _ownedVolume;

  /// The one-time unlock reveal: the newly read scene snaps into its frame
  /// (first fifth), then the fresh path dots pop in, then the hint fades.
  late final AnimationController _arrival = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2300),
  );

  /// The tap-driven open: parcel shakes and tears, the card springs out.
  late final AnimationController _tear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  /// A short "I'm waiting" wobble on the parcel. Finite on purpose: a
  /// repeating ticker would hang every pumpAndSettle in the suite.
  late final AnimationController _wiggle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  /// The one-time all-read finale: trail lights top to bottom, the plaque
  /// blooms, specks pop.
  late final AnimationController _finale = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  );

  /// Scene index whose reread lines are open, if any.
  int? _openBubble;

  /// A reveal is queued or running; _load must not queue another and the
  /// parcel must not be torn over it.
  bool _celebrating = false;

  /// A tear is in flight — from the tap until the opened state is both
  /// shown and persisted. Closes the re-tap window after the animation
  /// ends but before the write lands.
  bool _tearing = false;

  bool _finaleCuePlayed = false;

  final _currentStopKey = GlobalKey();
  final _trailEndKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _finale.addListener(_onFinaleTick);
    _load();
  }

  @override
  void dispose() {
    _arrival.dispose();
    _tear.dispose();
    _wiggle.dispose();
    _finale.dispose();
    _ownedSounds?.dispose();
    super.dispose();
  }

  @override
  bool isActiveOf(StoryScreen widget) => widget.isActive;

  // A scene may have been finished from another tab's flows.
  @override
  void onTabActivated() => _load();

  @override
  void didUpdateWidget(covariant StoryScreen oldWidget) {
    // The mixin's rising-edge reload runs first.
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive && oldWidget.isActive) {
      _abortCelebration();
    }
  }

  /// Leaving the tab mid-celebration must not burn the one-time moment:
  /// stop the reveal UNPERSISTED so the next visit replays it from the
  /// top (the IndexedStack would otherwise let it finish unseen).
  void _abortCelebration() {
    if (_arrival.isAnimating) {
      _arrival.stop(canceled: true);
    }
    if (_finale.isAnimating) {
      _finale.stop(canceled: true);
    }
    if (_wiggle.isAnimating) {
      _wiggle.stop();
    }
  }

  Future<void> _load() async {
    final completed = await completedImageIds(
      const SharedPreferencesCompletionStore(),
    );
    final seen = await widget.celebrationStore.read();
    final settings = await _settingsStore.load();
    if (!mounted) {
      return;
    }
    final story = storyStateFor(completed);
    setState(() {
      _story = story;
      _seen = seen;
      _settings = settings;
    });
    _refreshOwnedSounds(settings);
    // A fresh current stop must not inherit the previous tear's finished
    // controller — scenes 2+ would render pre-torn for the whole session.
    if (!_tearing &&
        !_tear.isAnimating &&
        !story.complete &&
        currentStopWrapped(seen, finished: story.finishedStops)) {
      _tear.value = 0;
    }
    _maybeCelebrate();
  }

  /// (Re)builds the owned cues at the player's current effects volume and
  /// warms them, so the first rip lands WITH the tear instead of after an
  /// asset load. Injected test cues are left alone.
  void _refreshOwnedSounds(AppSettings settings) {
    if (widget.sounds != null || _ownedVolume == settings.effectsVolume) {
      return;
    }
    final previous = _ownedSounds;
    _ownedSounds = FlameAudioSounds(volumeScale: settings.effectsVolume);
    _ownedVolume = settings.effectsVolume;
    unawaited(previous?.dispose());
    unawaited(_ownedSounds!.preload());
  }

  GameSounds get _sounds =>
      widget.sounds ??
      (_ownedSounds ??= FlameAudioSounds(volumeScale: _settings.effectsVolume));

  GameHaptics? get _haptics =>
      widget.haptics ??
      (_settings.hapticsEnabled ? const SystemGameHaptics() : null);

  /// Queues the pending one-time reveal, if any, once the frame with the
  /// new state is on screen.
  void _maybeCelebrate() {
    final story = _story;
    if (story == null || _celebrating || !widget.isActive) {
      return;
    }
    final reveal = revealToPlay(
      _seen,
      finished: story.finishedStops,
      total: story.totalStops,
    );
    if (reveal == StoryReveal.none) {
      // Nothing new to celebrate — but a waiting parcel still gives one
      // finite "I'm here" wobble per visit.
      if (!story.complete &&
          currentStopWrapped(_seen, finished: story.finishedStops)) {
        _startWiggle();
      }
      return;
    }
    // Rewind BEFORE the first frame of the new state renders: a controller
    // resting at 1.0 from an earlier reveal would otherwise flash the new
    // dots/plaque fully landed, then blank them when the replay starts.
    switch (reveal) {
      case StoryReveal.unlock:
        _arrival.value = 0;
      case StoryReveal.finale:
        _finale.value = 0;
      case StoryReveal.none:
        break;
    }
    _celebrating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _celebrating = false;
        return;
      }
      switch (reveal) {
        case StoryReveal.unlock:
          _playUnlock(story.finishedStops);
        case StoryReveal.finale:
          _playFinale();
        case StoryReveal.none:
          _celebrating = false;
      }
    });
  }

  Future<void> _playUnlock(int finished) async {
    await _scrollTo(_currentStopKey);
    if (!mounted || !widget.isActive) {
      _celebrating = false;
      return;
    }
    _sounds.playSnap();
    final played = await _playThrough(_arrival);
    if (!mounted) {
      return;
    }
    _celebrating = false;
    if (!played) {
      // Aborted (tab left mid-reveal): persist nothing — the arrival
      // replays from the top on the next visit.
      return;
    }
    final seen = _seen.copyWith(arrivals: finished + 1);
    setState(() => _seen = seen);
    _startWiggle();
    await widget.celebrationStore.write(seen);
  }

  Future<void> _playFinale() async {
    await _scrollTo(_trailEndKey);
    if (!mounted || !widget.isActive) {
      _celebrating = false;
      return;
    }
    _finaleCuePlayed = false;
    final played = await _playThrough(_finale);
    if (!mounted) {
      return;
    }
    _celebrating = false;
    if (!played) {
      return;
    }
    final seen = _seen.copyWith(finaleShown: true);
    setState(() => _seen = seen);
    await widget.celebrationStore.write(seen);
  }

  /// Runs [controller] from the top; false when the play was cut short
  /// (tab switch or teardown) and its moment should not count as seen.
  Future<bool> _playThrough(AnimationController controller) async {
    try {
      await controller.forward(from: 0).orCancel;
      return true;
    } on TickerCanceled {
      return false;
    }
  }

  /// The chime lands when the plaque pops, not at the start of the sweep.
  void _onFinaleTick() {
    if (!_finaleCuePlayed && _finale.value >= 0.55) {
      _finaleCuePlayed = true;
      _sounds.playComplete();
      _haptics?.complete();
    }
  }

  // A plain forward() TickerFuture never throws — only .orCancel opts in.
  void _startWiggle() => _wiggle.forward(from: 0);

  Future<void> _scrollTo(GlobalKey key) async {
    final context = key.currentContext;
    if (context == null) {
      return;
    }
    await Scrollable.ensureVisible(
      context,
      alignment: 0.4,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  void _tearParcel() {
    final story = _story;
    // No tearing over a running celebration (the reveals play separately,
    // and concurrent _seen writers would clobber each other), and none
    // once a tear is already in flight — including the post-animation
    // frames before the opened state lands.
    if (story == null ||
        _tearing ||
        _celebrating ||
        _arrival.isAnimating ||
        !currentStopWrapped(_seen, finished: story.finishedStops)) {
      return;
    }
    _tearing = true;
    _sounds.playRip();
    _haptics?.snap();
    unawaited(_finishTear(story.finishedStops));
  }

  Future<void> _finishTear(int finished) async {
    final played = await _playThrough(_tear);
    if (!mounted) {
      return;
    }
    if (!played) {
      _tearing = false;
      return;
    }
    Analytics.instance.storySceneUnlocked(scene: finished + 1);
    // Show first, persist after: the in-memory state flips before the
    // guard reopens, so no tap can slip in and replay the tear.
    final seen = _seen.copyWith(opened: finished + 1);
    setState(() => _seen = seen);
    _tearing = false;
    await widget.celebrationStore.write(seen);
  }

  Future<void> _openScene(PuzzleImage image) async {
    await startPuzzleFlow(
      context,
      image,
      source: LaunchSource.story,
      clock: widget.clock,
    );
    // The run may have read new scenes while the game was open.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final story = _story;
    return Scaffold(
      appBar: risoAppBar('Story'),
      // Not a ListView: the trail is a handful of cheap rows, and lazy
      // building would hide offscreen stops from the semantics tree.
      body: story == null
          ? const SizedBox.shrink()
          : SingleChildScrollView(
              key: const PageStorageKey('story-page'),
              padding: photoGridPadding,
              child: Column(
                children: [
                  _HeaderCard(story: story),
                  const SizedBox(height: 22),
                  ..._trail(story),
                  const SizedBox(height: 12),
                ],
              ),
            ),
    );
  }

  // ---- trail assembly ---------------------------------------------------

  /// Horizontal stop position as a fraction of the row width. The side
  /// rhythm flips after the current stop: it sits centered and consumes
  /// one beat of the alternation (matches the approved mock).
  double _stopX(int index, StoryState story) {
    if (!story.complete && index == story.finishedStops) {
      return 0.5;
    }
    final left = index < story.finishedStops ? index.isEven : index.isOdd;
    return left ? 0.26 : 0.74;
  }

  List<Widget> _trail(StoryState story) {
    final total = story.totalStops;
    return [
      for (var index = 0; index < total; index++) ...[
        if (index > 0) _connector(index - 1, story),
        _stopRow(index, story),
      ],
      _connector(total - 1, story, toEnd: true),
      _endMarker(story),
    ];
  }

  /// One per stretch of history, placed by connector index so the scenery
  /// never moves as progress advances.
  static const _doodads = <int, (TrailDoodad, bool)>{
    0: (TrailDoodad.map, false),
    2: (TrailDoodad.globe, false),
    3: (TrailDoodad.fretsaw, false),
    4: (TrailDoodad.box, true),
    6: (TrailDoodad.teacup, false),
  };

  Widget _connector(int index, StoryState story, {bool toEnd = false}) {
    final finished = story.finishedStops;
    final intoCurrent = !story.complete && index == finished - 1;
    final done = index < finished;
    final height = toEnd
        ? 90.0
        : intoCurrent
        ? 140.0
        : index >= finished
        ? 90.0
        : 64.0;
    final arrivalsSeen = finished == 0 || _seen.arrivals >= finished + 1;
    final doodad = toEnd ? null : _doodads[index];
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([_arrival, _finale]),
              builder: (context, _) {
                final pop = !intoCurrent || arrivalsSeen
                    ? 1.0
                    : Interval(
                        0.2,
                        0.85,
                        curve: Curves.linear,
                      ).transform(_arrival.value);
                // The finale sweep walks the whole trail top to bottom.
                final bands = story.totalStops + 1;
                final lit = _finale.isAnimating || _finale.value > 0
                    ? ((_finale.value / 0.5) * bands - index).clamp(0.0, 1.0)
                    : 0.0;
                return CustomPaint(
                  painter: TrailSegmentPainter(
                    fromX: _stopX(index, story),
                    toX: toEnd ? 0.5 : _stopX(index + 1, story),
                    opacity: done || toEnd && story.complete ? 1 : 0.22,
                    dotRadius: intoCurrent ? 4 : 2.5,
                    spacing: intoCurrent ? 24 : 15,
                    pop: pop,
                    lit: lit,
                  ),
                );
              },
            ),
          ),
          if (doodad != null)
            Positioned(
              left: doodad.$2 ? 14 : null,
              right: doodad.$2 ? null : 14,
              top: (height - 56) / 2,
              child: Transform.rotate(
                angle: (doodad.$2 ? -5 : 7) * math.pi / 180,
                child: SizedBox.square(
                  dimension: 56,
                  child: CustomPaint(painter: DoodadPainter(doodad.$1)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stopRow(int index, StoryState story) {
    if (index < story.finishedStops || story.complete) {
      return _readStop(index, story);
    }
    if (index == story.finishedStops) {
      return _currentStop(index, story);
    }
    return _lockedStop(index, story);
  }

  Widget _readStop(int index, StoryState story) {
    final stop = story.story.stops[index];
    final isNewest = index == story.finishedStops - 1;
    final arrivalsSeen =
        story.finishedStops == 0 || _seen.arrivals >= story.finishedStops + 1;
    final open = _openBubble == index;
    void toggleLines() => setState(() => _openBubble = open ? null : index);
    final thumb = AnimatedBuilder(
      animation: _arrival,
      builder: (context, child) {
        // The snap-in: the freshly read scene lands into its frame first.
        final t = isNewest && !arrivalsSeen && !story.complete
            ? Interval(
                0,
                0.18,
                curve: Curves.easeOutBack,
              ).transform(_arrival.value)
            : 1.0;
        return Transform.scale(scale: 1.4 - 0.4 * t, child: child);
      },
      child: _StopThumb(stop: stop, number: index + 1, outerLeft: index.isEven),
    );
    return Column(
      children: [
        Align(
          alignment: Alignment(index.isEven ? -0.55 : 0.55, 0),
          child: Semantics(
            identifier: 'story-stop-${index + 1}',
            button: true,
            label: 'Scene ${index + 1} · ${stop.image.title}',
            container: true,
            // The label IS the announcement; without this the tag number
            // and title text merge in as noise. Excluding descendants also
            // drops the GestureDetector's tap ACTION, so the Semantics
            // must carry its own onTap for screen readers.
            excludeSemantics: true,
            onTap: toggleLines,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: toggleLines,
              child: Transform.rotate(
                angle: (index.isEven ? -2 : 2) * math.pi / 180,
                child: Column(
                  children: [
                    thumb,
                    const SizedBox(height: 10),
                    SizedBox(
                      width: 132,
                      child: Text(
                        stop.image.title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: open
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                  child: _RereadBubble(
                    number: index + 1,
                    stop: stop,
                    onPlayAgain: () => _openScene(stop.image),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _currentStop(int index, StoryState story) {
    final wrapped = currentStopWrapped(_seen, finished: story.finishedStops);
    final arrivalsSeen =
        story.finishedStops == 0 || _seen.arrivals >= story.finishedStops + 1;
    void activate() {
      if (wrapped) {
        _tearParcel();
      } else {
        _openScene(story.story.stops[index].image);
      }
    }

    return KeyedSubtree(
      key: _currentStopKey,
      child: Semantics(
        identifier: 'story-stop-${index + 1}',
        button: true,
        label: wrapped
            ? 'Scene ${index + 1}, a wrapped parcel. Tap to open.'
            : 'Scene ${index + 1}. $storyNextHintText',
        container: true,
        // The label carries the whole state; the tag, hint and card text
        // would otherwise merge in as noise. Excluding descendants also
        // drops the GestureDetector's tap ACTION, so the Semantics must
        // carry its own onTap for screen readers.
        excludeSemantics: true,
        onTap: activate,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: activate,
          child: AnimatedBuilder(
            animation: Listenable.merge([_arrival, _tear, _wiggle]),
            builder: (context, _) {
              final tearT = wrapped ? _tear.value : 1.0;
              final shake = const Interval(0, 0.18).transform(tearT);
              final gone = const Interval(0.18, 0.45).transform(tearT);
              final cardT = const Interval(
                0.5,
                0.85,
                curve: Curves.easeOutBack,
              ).transform(tearT);
              final playT = const Interval(0.85, 1).transform(tearT);
              // The waiting wobble plus the pre-tear shake, both as plain
              // rotations so they compose.
              final wobble =
                  math.sin(_wiggle.value * math.pi * 6) *
                  (1 - _wiggle.value) *
                  2.5;
              final shakeAngle = tearT == 0
                  ? wobble
                  : math.sin(shake * math.pi * 4) * 6 * (1 - gone);
              final hintT = !wrapped || tearT > 0
                  ? 0.0
                  : arrivalsSeen
                  ? 1.0
                  : const Interval(0.88, 1).transform(_arrival.value);
              // Natural sizing throughout: the stack takes the largest
              // child's own height (parcel at rest, the card once it
              // springs), so scaled text can never overflow a tuned
              // reserve; AnimatedSize glides between the two.
              return AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // The empty slot the story delivers its piece onto,
                          // peeking out under the tilted parcel.
                          Transform.translate(
                            offset: const Offset(5, 9),
                            child: Transform.rotate(
                              angle: 4 * math.pi / 180,
                              child: Opacity(
                                opacity: 0.9,
                                child: SizedBox.square(
                                  dimension: 112,
                                  child: const CustomPaint(
                                    painter: MissingPieceSlotPainter(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (gone < 1)
                            Opacity(
                              opacity: 1 - gone,
                              child: Transform.rotate(
                                angle: (shakeAngle - 2) * math.pi / 180,
                                child: Transform.scale(
                                  scale: 1 - 0.75 * gone,
                                  child: _ParcelFace(number: index + 1),
                                ),
                              ),
                            ),
                          if (cardT > 0)
                            Transform.scale(
                              scale: 0.6 + 0.4 * cardT,
                              child: Opacity(
                                opacity: cardT.clamp(0, 1),
                                child: _MysteryCard(
                                  number: index + 1,
                                  era: story.story.stops[index].era,
                                  playPop: playT,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (hintT > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Opacity(
                          opacity: hintT,
                          child: const _HintPill(text: storyTapToOpenText),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _lockedStop(int index, StoryState story) {
    final depth = (index - story.finishedStops - 1).clamp(0, 3);
    final size = [86.0, 78.0, 70.0, 64.0][depth];
    final opacity = [0.95, 0.85, 0.72, 0.62][depth];
    final stop = story.story.stops[index];
    final first = index == story.finishedStops + 1;
    return Semantics(
      identifier: 'story-stop-${index + 1}',
      label: 'Scene ${index + 1}, not found yet',
      container: true,
      excludeSemantics: true,
      child: Align(
        alignment: Alignment(index.isOdd ? -0.55 : 0.55, 0),
        child: Opacity(
          opacity: opacity,
          child: Column(
            children: [
              Transform.rotate(
                angle: (index.isOdd ? -3 : 3) * math.pi / 180,
                child: SizedBox.square(
                  dimension: size,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Positioned.fill(
                        child: CustomPaint(painter: MissingPieceSlotPainter()),
                      ),
                      Positioned(
                        left: 0,
                        top: size * 0.12,
                        child: _NumberTag(number: index + 1),
                      ),
                      Positioned(
                        left: index.isOdd ? -26 : null,
                        right: index.isOdd ? null : -26,
                        bottom: -2,
                        child: _EraTag(era: stop.era),
                      ),
                    ],
                  ),
                ),
              ),
              if (first)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    storyNotFoundYetText,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: StudioColors.mutedInk),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _endMarker(StoryState story) {
    if (!story.complete) {
      return const Center(child: _EndCircle());
    }
    final resting = _seen.finaleShown;
    return KeyedSubtree(
      key: _trailEndKey,
      child: AnimatedBuilder(
        animation: _finale,
        builder: (context, _) {
          final plaqueT = resting
              ? 1.0
              : const Interval(
                  0.55,
                  0.8,
                  curve: Curves.easeOutBack,
                ).transform(_finale.value);
          final speckT = resting ? 1.0 : _finale.value;
          // The plaque sizes itself (scaled text can need three lines);
          // the specks ride its center via Positioned.fill.
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Always laid out (invisible until the pop): the plaque is
                // the stack's one non-positioned child, so dropping it
                // would leave only Positioned.fill specks and an unbounded
                // stack in the scroll column.
                Opacity(
                  opacity: plaqueT.clamp(0, 1),
                  child: Transform.scale(
                    scale: (0.3 + 0.7 * plaqueT).clamp(0.0, 1.1),
                    child: const _EndPlaque(),
                  ),
                ),
                for (final (i, speck) in _speckSpots.indexed)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.center,
                      child: Transform.translate(
                        offset: Offset(speck.$1, speck.$2),
                        child: Transform.scale(
                          scale: resting
                              ? 1
                              : Interval(
                                  (0.8 + i * 0.04).clamp(0.0, 0.96),
                                  (0.9 + i * 0.04).clamp(0.0, 1.0),
                                  curve: Curves.easeOutBack,
                                ).transform(speckT),
                          child: Transform.rotate(
                            angle: speck.$3,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: speck.$4,
                                borderRadius: BorderRadius.circular(speck.$5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Confetti around the plaque: offsets from center, rotation, ink, and
  /// corner rounding (one is a dot).
  static const _speckSpots = <(double, double, double, Color, double)>[
    (-120, -56, 0.25, StudioColors.structureInk, 3),
    (105, -44, -0.18, StudioColors.tomato, 6),
    (-128, 32, 0.35, StudioColors.salmon, 3),
    (112, 40, -0.28, StudioColors.structureInk, 3),
    (-6, -72, 0.14, StudioColors.tomato, 3),
  ];
}

// ---- header -------------------------------------------------------------

/// Title card: kicker, story title, and the progress line. Once the story
/// is read the kicker flips to THE END; the closing line lives on the
/// trail's plaque.
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.story});

  final StoryState story;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PaintedCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            story.complete ? 'THE END' : 'A TRUE STORY',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              // Tomato by name: the story kicker is the one eyebrow the
              // approved mock keeps in the action ink.
              color: StudioColors.tomato,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            story.story.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          if (!story.complete) ...[
            const SizedBox(height: 4),
            Semantics(
              identifier: 'story-progress',
              child: Text(
                storyProgressText(story.finishedStops, story.totalStops),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---- trail pieces -------------------------------------------------------

/// A read scene's framed painting with its number, done check and era tag.
class _StopThumb extends StatelessWidget {
  const _StopThumb({
    required this.stop,
    required this.number,
    required this.outerLeft,
  });

  final StoryStop stop;
  final int number;

  /// Which side faces away from the trail — the era tag hangs there.
  final bool outerLeft;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 92,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The shared framed-photo recipe (decode width, border, radius,
          // visible-title decode fallback); only the trail's hard sticker
          // shadow is layered on here.
          DecoratedBox(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(TiltedPhotoCard.cornerRadius),
              boxShadow: [
                BoxShadow(
                  color: StudioColors.structureInk,
                  offset: Offset(3, 3),
                ),
              ],
            ),
            child: FramedThumbnail(
              dimension: 92,
              assetPath: stop.image.assetPath,
              title: stop.image.title,
            ),
          ),
          Positioned(left: -8, top: -8, child: _NumberTag(number: number)),
          const Positioned(right: -7, top: -7, child: _DoneCheck()),
          Positioned(
            left: outerLeft ? -26 : null,
            right: outerLeft ? null : -26,
            bottom: -10,
            child: _EraTag(era: stop.era),
          ),
        ],
      ),
    );
  }
}

/// The reread card a tapped stop opens: scene kicker, its lines, and a
/// quiet replay offer.
class _RereadBubble extends StatelessWidget {
  const _RereadBubble({
    required this.number,
    required this.stop,
    required this.onPlayAgain,
  });

  final int number;
  final StoryStop stop;
  final VoidCallback onPlayAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PaintedCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SCENE $number · ${stop.image.title.toUpperCase()}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: StudioColors.structureDark,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(stop.text, style: theme.textTheme.bodySmall),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onPlayAgain,
              child: const Text('Play again'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The parcel body with its number tag; transforms live in the screen.
class _ParcelFace extends StatelessWidget {
  const _ParcelFace({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 114,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: TiedParcelPainter()),
          ),
          Positioned(left: 1, top: 1, child: _NumberTag(number: number)),
        ],
      ),
    );
  }
}

/// The torn-open reveal: a mystery frame (the painting stays unseen until
/// the size sheet), the scene number, the invitation, and PLAY.
class _MysteryCard extends StatelessWidget {
  const _MysteryCard({
    required this.number,
    required this.era,
    required this.playPop,
  });

  final int number;
  final String era;
  final double playPop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 250,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PaintedCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 120,
                  child: CustomPaint(
                    painter: _MysteryFramePainter(),
                    child: Center(
                      child: Text(
                        '?',
                        style: TextStyle(
                          fontFamily: 'Rokkitt',
                          fontWeight: FontWeight.w700,
                          fontSize: 54,
                          color: StudioColors.structureInk,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text('Scene $number', style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(storyNextHintText, style: theme.textTheme.bodySmall),
                const SizedBox(height: 10),
                Transform.scale(
                  scale: playPop,
                  child: Transform.rotate(
                    angle: -1 * math.pi / 180,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: StudioColors.tomato,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'PLAY',
                        style: TextStyle(
                          fontFamily: 'Rokkitt',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          letterSpacing: 1.5,
                          color: StudioColors.onTomato,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(left: -8, top: -8, child: _NumberTag(number: number)),
          Positioned(right: -10, top: -12, child: _EraTag(era: era)),
        ],
      ),
    );
  }
}

/// Dashed inner frame behind the question mark.
class _MysteryFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    canvas.drawRRect(rect, Paint()..color = StudioColors.ground);
    canvas.drawPath(
      dashPath(Path()..addRRect(rect.deflate(1)), dash: 8, gap: 6),
      Paint()
        ..color = StudioColors.structureInk.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_MysteryFramePainter oldDelegate) => false;
}

class _HintPill extends StatelessWidget {
  const _HintPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
      decoration: BoxDecoration(
        color: StudioColors.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: StudioColors.structureInk, width: 1.5),
        boxShadow: const [
          BoxShadow(color: StudioColors.structureInk, offset: Offset(2, 2)),
        ],
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: StudioColors.structureDark,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NumberTag extends StatelessWidget {
  const _NumberTag({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: StudioColors.card,
        shape: BoxShape.circle,
        border: Border.all(color: StudioColors.structureInk, width: 2),
        boxShadow: const [
          BoxShadow(color: StudioColors.structureInk, offset: Offset(2, 2)),
        ],
      ),
      child: Text(
        '$number',
        style: const TextStyle(
          fontFamily: 'Rokkitt',
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: StudioColors.ink,
        ),
      ),
    );
  }
}

class _DoneCheck extends StatelessWidget {
  const _DoneCheck();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: StudioColors.card,
        shape: BoxShape.circle,
        border: Border.all(color: StudioColors.structureInk, width: 2),
        boxShadow: const [
          BoxShadow(color: StudioColors.structureInk, offset: Offset(2, 2)),
        ],
      ),
      child: const CustomPaint(painter: _CheckPainter()),
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = StudioColors.tomato
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.26, size.height * 0.52)
        ..lineTo(size.width * 0.44, size.height * 0.7)
        ..lineTo(size.width * 0.76, size.height * 0.32),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) => false;
}

class _EraTag extends StatelessWidget {
  const _EraTag({required this.era});

  final String era;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: StudioColors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: StudioColors.structureInk, width: 1.5),
        boxShadow: const [
          BoxShadow(color: StudioColors.structureInk, offset: Offset(2, 2)),
        ],
      ),
      child: Text(
        era,
        style: const TextStyle(
          fontFamily: 'Rokkitt',
          fontWeight: FontWeight.w700,
          fontSize: 10,
          letterSpacing: 0.5,
          color: StudioColors.structureDark,
        ),
      ),
    );
  }
}

/// Where the trail will end one day: a quiet dashed ring.
class _EndCircle extends StatelessWidget {
  const _EndCircle();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // Without a curated label the inner text announces a bare "THE END"
      // to screen readers mid-story, right after "0 of 8 scenes found".
      label: "The story's end — not reached yet",
      container: true,
      excludeSemantics: true,
      child: _ring(),
    );
  }

  Widget _ring() {
    return Opacity(
      opacity: 0.75,
      child: SizedBox.square(
        dimension: 66,
        child: CustomPaint(
          painter: const _EndRingPainter(),
          child: Center(
            child: Text(
              'THE\nEND',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Rokkitt',
                fontWeight: FontWeight.w700,
                fontSize: 12,
                height: 1.1,
                color: StudioColors.mutedInk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EndRingPainter extends CustomPainter {
  const _EndRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      dashPath(
        Path()..addOval((Offset.zero & size).deflate(2)),
        dash: 7,
        gap: 6,
      ),
      Paint()
        ..color = StudioColors.mutedInk.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_EndRingPainter oldDelegate) => false;
}

/// The finale's keepsake: THE END, the sunflower, and the closing line.
class _EndPlaque extends StatelessWidget {
  const _EndPlaque();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 230,
      child: PaintedCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'THE END',
              style: TextStyle(
                fontFamily: 'Rokkitt',
                fontWeight: FontWeight.w700,
                fontSize: 22,
                letterSpacing: 1,
                color: StudioColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            MascotArt(StudioMascot.sunflower, height: 26),
            const SizedBox(height: 4),
            Text(
              storyEndText,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
