// Story screen overview:
// 1. One story told through puzzles: eight scenes, read strictly in order.
//    Read scenes (and the one open next) zigzag down the page as cards
//    joined by a dotted painted trail with little arrows — a journey, not
//    a list. Scenes still ahead sit below as wrapped kraft-paper parcels
//    (numbered tags, no art, no title), so nothing is spoiled early.
// 2. Tapping the open scene (or re-reading a finished one) runs the normal
//    size-sheet flow; progress reloads when the game closes and whenever
//    the shell makes this tab visible again.
// 3. Progress is derived in story_track.dart from the completion records;
//    this screen only renders the derived state.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'bonus_track.dart';
import 'puzzle_catalog.dart';
import 'puzzle_completion.dart';
import 'puzzle_launcher.dart';
import 'story_track.dart';
import 'studio_mascots.dart';
import 'tab_activation.dart';
import 'studio_surfaces.dart';
import 'studio_theme.dart';

/// Header progress line; shared with tests.
String storyProgressText(int found, int total) =>
    '$found of $total scenes found';

/// The playable card's invitation; shared with tests.
const storyNextHintText = 'Tap to piece this scene together.';

/// The header's closing line once every scene is read; shared with tests.
const storyEndText = 'The whole story is yours — it stays right here.';

/// Zigzag cards leave this much air on their open side, so the trail has
/// room to sweep past them.
const _sceneCardWidthFactor = 0.86;

class StoryScreen extends StatefulWidget {
  const StoryScreen({super.key, this.clock, this.isActive = true});

  /// Returns "now"; tests fix the date to make daily credit deterministic.
  /// Defaults to [DateTime.now].
  final DateTime Function()? clock;

  /// Whether the shell currently shows this tab. The shell keeps tabs
  /// alive, so becoming visible again — not being rebuilt — is the reload
  /// signal.
  final bool isActive;

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen>
    with TabActivationAware<StoryScreen> {
  /// Null until the store answers; the page renders nothing before that so
  /// it never flashes a locked list it is about to replace.
  StoryState? _story;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  bool isActiveOf(StoryScreen widget) => widget.isActive;

  // A scene may have been finished from another tab's flows.
  @override
  void onTabActivated() => _load();

  Future<void> _load() async {
    final completed = await completedImageIds(
      const SharedPreferencesCompletionStore(),
    );
    if (mounted) {
      setState(() => _story = storyStateFor(completed));
    }
  }

  Future<void> _open(PuzzleImage image) async {
    await startPuzzleFlow(context, image, clock: widget.clock);
    // The run may have read new scenes while the game was open.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final story = _story;
    return Scaffold(
      appBar: AppBar(title: const Text('Story')),
      body: story == null
          ? const SizedBox.shrink()
          : ListView(
              key: const PageStorageKey('story-page'),
              padding: photoGridPadding,
              children: [_HeaderCard(story: story), ..._journey(story)],
            ),
    );
  }

  /// The trail: scene cards zigzag left/right, each joined to the next by
  /// a dotted arrow; the still-wrapped scenes wait below as parcels.
  List<Widget> _journey(StoryState story) {
    final stops = story.story.stops;
    // Read scenes plus the one open to play; parcels cover the rest.
    final cardCount = story.complete
        ? stops.length
        : story.finishedStops + 1;
    return [
      for (var index = 0; index < cardCount; index++) ...[
        if (index == 0)
          const SizedBox(height: 12)
        else
          _TrailConnector(toRight: index.isOdd),
        Semantics(
          identifier: 'story-stop-${index + 1}',
          container: true,
          child: Align(
            // The alternation IS the journey: a straight column of cards
            // read as a plain list (owner's "boring" flag).
            alignment: index.isEven
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: _sceneCardWidthFactor,
              child: index < story.finishedStops
                  ? _FinishedSceneCard(
                      number: index + 1,
                      stop: stops[index],
                      onTap: () => _open(stops[index].image),
                    )
                  : _NextSceneCard(
                      number: index + 1,
                      onTap: () => _open(stops[index].image),
                    ),
            ),
          ),
        ),
      ],
      if (cardCount < stops.length) ...[
        const _TrailLead(),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 10,
          children: [
            for (var index = cardCount; index < stops.length; index++)
              _WrappedParcel(number: index + 1),
          ],
        ),
      ],
    ];
  }
}

/// Title card: kicker, story title, and the progress line — which gives
/// way to the closing line (and the sunflower) once the story is read.
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
              color: StudioColors.terracotta,
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
          const SizedBox(height: 4),
          if (story.complete) ...[
            MascotArt(StudioMascot.sunflower, height: 28),
            const SizedBox(height: 4),
            Text(
              storyEndText,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ] else
            Semantics(
              identifier: 'story-progress',
              child: Text(
                storyProgressText(story.finishedStops, story.totalStops),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// A read scene: its painting in a small frame, the scene title, and the
/// lines it revealed. Tapping re-opens the usual size sheet (a re-read
/// earns nothing — replays add no new completion id).
class _FinishedSceneCard extends StatelessWidget {
  const _FinishedSceneCard({
    required this.number,
    required this.stop,
    required this.onTap,
  });

  final int number;
  final StoryStop stop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PaintedCard(
      variant: number,
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FramedThumbnail(
            dimension: 64,
            seed: number,
            assetPath: stop.image.assetPath,
            title: stop.image.title,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scene $number · ${stop.image.title}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(stop.text, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The one scene open to play: a mystery frame instead of art — the
/// painting (and its title) stays unseen until the size sheet opens.
class _NextSceneCard extends StatelessWidget {
  const _NextSceneCard({required this.number, required this.onTap});

  final int number;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PaintedCard(
      variant: number,
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 64,
            child: FramedArt(
              seed: number,
              child: const ColoredBox(
                color: StudioColors.ground,
                child: Icon(Icons.extension, color: StudioColors.terracotta),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Scene $number', style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(storyNextHintText, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The dotted arrow joining one scene card to the next. Pure decoration —
/// it adds no semantics node.
class _TrailConnector extends StatelessWidget {
  const _TrailConnector({required this.toRight});

  /// Whether the next card sits on the right (the trail sweeps that way).
  final bool toRight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      width: double.infinity,
      child: CustomPaint(painter: _TrailPainter(toRight: toRight)),
    );
  }
}

class _TrailPainter extends CustomPainter {
  const _TrailPainter({required this.toRight});

  final bool toRight;

  static const _dotSpacing = 9.0;
  static const _dotRadius = 1.7;
  static const _arrowLength = 9.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = StudioColors.moss;
    final startX = size.width * (toRight ? 0.30 : 0.70);
    final endX = size.width * (toRight ? 0.68 : 0.32);
    final sweep = toRight ? 70.0 : -70.0;
    final path = Path()
      ..moveTo(startX, 2)
      ..cubicTo(
        startX + sweep,
        size.height * 0.45,
        endX - sweep,
        size.height * 0.55,
        endX,
        size.height - 6,
      );
    final metric = path.computeMetrics().first;
    // Dots up to (not into) the arrowhead.
    for (var d = 0.0; d < metric.length - _arrowLength; d += _dotSpacing) {
      canvas.drawCircle(metric.getTangentForOffset(d)!.position, _dotRadius, paint);
    }
    final tip = metric.getTangentForOffset(metric.length)!;
    final angle = math.atan2(tip.vector.dy, tip.vector.dx);
    final stroke = Paint()
      ..color = StudioColors.moss
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (final side in const [0.55, -0.55]) {
      canvas.drawLine(
        tip.position,
        tip.position -
            Offset(math.cos(angle + side), math.sin(angle + side)) *
                _arrowLength,
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_TrailPainter oldDelegate) =>
      oldDelegate.toRight != toRight;
}

/// The short fading dots between the open scene and the parcels — the
/// trail continuing into the not-yet part of the story. No arrow: it
/// points at nothing the player can do yet.
class _TrailLead extends StatelessWidget {
  const _TrailLead();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      width: double.infinity,
      child: CustomPaint(painter: _TrailLeadPainter()),
    );
  }
}

class _TrailLeadPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(
        Offset(size.width / 2, 6.0 + i * 9),
        1.7,
        // Fades out walking down — the story trails off into the wrapped
        // scenes below.
        Paint()..color = StudioColors.moss.withValues(alpha: 1 - i * 0.22),
      );
    }
  }

  @override
  bool shouldRepaint(_TrailLeadPainter oldDelegate) => false;
}

/// A scene still ahead: a kraft-paper parcel tied with string, wearing
/// only its number tag. Not tappable — the prefix rule in story_track.dart
/// is the single gate, the parcel just offers no way around it.
class _WrappedParcel extends StatelessWidget {
  const _WrappedParcel({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'story-stop-$number',
      label: 'Scene $number, still wrapped',
      container: true,
      // The label replaces the tag's bare number — without this, screen
      // readers announce a context-free second node per parcel.
      excludeSemantics: true,
      child: Transform.rotate(
        angle: TiltedPhotoCard.tiltFor(number),
        child: SizedBox.square(
          dimension: 76,
          child: Stack(
            children: [
              const Positioned.fill(
                child: CustomPaint(painter: _ParcelPainter()),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: const BoxDecoration(
                    color: StudioColors.card,
                    borderRadius: BorderRadius.all(Radius.circular(7)),
                  ),
                  child: Text(
                    '$number',
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: StudioColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParcelPainter extends CustomPainter {
  const _ParcelPainter();

  /// Kraft wrapping paper; file-local like the completion scrim hexes —
  /// no other surface wraps anything in paper.
  static const _paper = Color(0xFFC9A87C);
  static const _paperEdge = Color(0x33423528);
  static const _string = Color(0xFFF9F3E3);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(5);
    final parcel = RRect.fromRectAndRadius(rect, const Radius.circular(11));
    canvas
      ..drawRRect(parcel, Paint()..color = _paper)
      ..drawRRect(
        parcel,
        Paint()
          ..color = _paperEdge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    final string = Paint()
      ..color = _string
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final center = rect.center;
    canvas
      ..drawLine(
        Offset(center.dx, rect.top + 2),
        Offset(center.dx, rect.bottom - 2),
        string,
      )
      ..drawLine(
        Offset(rect.left + 2, center.dy),
        Offset(rect.right - 2, center.dy),
        string,
      )
      // The bow: two little loops and a knot where the strings cross.
      ..drawOval(
        Rect.fromCenter(
          center: center - const Offset(7, 3),
          width: 11,
          height: 7,
        ),
        string,
      )
      ..drawOval(
        Rect.fromCenter(
          center: center + const Offset(7, -3),
          width: 11,
          height: 7,
        ),
        string,
      )
      ..drawCircle(center, 2.6, Paint()..color = _string);
  }

  @override
  bool shouldRepaint(_ParcelPainter oldDelegate) => false;
}
