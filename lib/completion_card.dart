// The completion page (mockup, third phone): when the last piece locks,
// the finished board stays visible but blurs and dims behind a linen card
// holding the painting, a FINISHED kicker, the title, the piece count, and
// the "Next puzzle" pill with a quiet "Back to gallery" exit beneath it.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'puzzle_catalog.dart';
import 'studio_surfaces.dart';
import 'studio_theme.dart';

/// The celebration overlay. Stack it over the whole game screen (app bar
/// included): the backdrop blur is the "you're done playing" cue, and the
/// barrier beneath the card blocks everything under it — taps and
/// assistive tech alike.
class CompletionCard extends StatelessWidget {
  const CompletionCard({
    super.key,
    required this.image,
    required this.pieceCount,
    required this.onBackToGallery,
    required this.onNextPuzzle,
  });

  final PuzzleImage image;
  final int pieceCount;

  final VoidCallback onBackToGallery;

  /// Starts the category's next unfinished painting; null promotes
  /// "Back to gallery" to the hero button (the category is done).
  final VoidCallback? onNextPuzzle;

  /// How long the blur, scrim, and card take to fade in. Tests pump this
  /// exact duration, so keep them on this constant.
  static const fadeDuration = Duration(milliseconds: 350);

  /// Light warm scrim (owner's pick over the mockup's gray-brown): dims
  /// the board just enough that the finished painting still glows
  /// through the blur.
  static const _scrim = Color(0xFF937B52);

  /// Deeper than the resting card shadows: this card floats over a blur,
  /// so its edge only exists as shadow.
  static const _floatShadow = BoxShadow(
    color: StudioColors.cardShadow,
    offset: Offset(0, 10),
    blurRadius: 30,
    spreadRadius: -6,
  );

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: fadeDuration,
        curve: Curves.easeOut,
        // Blur, scrim, and card fade in on the same tween, so the board
        // recedes exactly as the card arrives.
        builder: (context, t, child) => ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 9 * t, sigmaY: 9 * t),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // A ModalBarrier, not a plain colored box: it wraps
                // BlockSemantics, so the board and app-bar controls
                // beneath are unreachable for screen readers too, not
                // just for fingers.
                ModalBarrier(
                  dismissible: false,
                  color: _scrim.withValues(alpha: 0.30 * t),
                ),
                // Intangible until fully faded in: Opacity never blocks
                // hit-tests, and a near-invisible hero button must not
                // swallow a late tap meant for the board.
                IgnorePointer(
                  ignoring: t < 1,
                  child: Opacity(opacity: t, child: child),
                ),
              ],
            ),
          ),
        ),
        child: Stack(
          children: [
            ..._paintSpecks(),
            SafeArea(
              // Scrollable so the card stays usable on viewports even
              // smaller than the adaptive layouts plan for.
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _card(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    // The scroll view's 24px padding each side is width the card never
    // actually gets.
    final maxCardWidth = screen.width - 48;
    // Short wide screens (landscape phones) put the photo beside the
    // text: stacked, the actions would land below the fold with no
    // scroll affordance (the old gallery wall bounded its art by height
    // for the same reason).
    final sideBySide = screen.height < 480 && screen.width > screen.height;
    if (!sideBySide) {
      return SizedBox(
        width: math.min(maxCardWidth, 360),
        child: PaintedCard(
          variant: 2,
          shadow: _floatShadow,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _photo(),
              const SizedBox(height: 18),
              ..._info(context),
              const SizedBox(height: 18),
              ..._actions(),
            ],
          ),
        ),
      );
    }
    // Photo sized from the viewport height so the actions stay on
    // screen; the text column takes the card's remaining width.
    final photoWidth = ((screen.height - 128) * 1.5).clamp(
      140.0,
      maxCardWidth * 0.45,
    );
    return SizedBox(
      width: math.min(maxCardWidth, 620),
      child: PaintedCard(
        variant: 2,
        shadow: _floatShadow,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(width: photoWidth, child: _photo()),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ..._info(context),
                  const SizedBox(height: 16),
                  ..._actions(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photo() => AspectRatio(
    // Catalog images are 3:2 (the grid-ladder invariant relies on it);
    // AspectRatio keeps that true whatever width the layout grants.
    aspectRatio: 3 / 2,
    child: FramedArt(
      child: Image.asset(image.assetPath, fit: BoxFit.cover, cacheWidth: 640),
    ),
  );

  List<Widget> _info(BuildContext context) {
    final theme = Theme.of(context);
    return [
      Text(
        'FINISHED',
        style: theme.textTheme.labelSmall?.copyWith(
          color: StudioColors.terracotta,
          fontWeight: FontWeight.w800,
          letterSpacing: 2.4,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        image.title,
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      Text(
        '$pieceCount pieces · no timer, no score',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall,
      ),
    ];
  }

  // "One more" is the likely mood right after finishing, so the next
  // puzzle is the hero action and the exit a quiet text button beneath it.
  List<Widget> _actions() => [
    if (onNextPuzzle != null) ...[
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onNextPuzzle,
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          iconAlignment: IconAlignment.end,
          label: const Text('Next puzzle'),
        ),
      ),
      const SizedBox(height: 2),
      TextButton(
        onPressed: onBackToGallery,
        style: TextButton.styleFrom(
          foregroundColor: StudioColors.ink,
          textStyle: const TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w700,
          ),
        ),
        child: const Text('Back to gallery'),
      ),
    ] else
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onBackToGallery,
          child: const Text('Back to gallery'),
        ),
      ),
  ];

  /// Flecks of studio paint celebrating around the card.
  List<Widget> _paintSpecks() {
    Widget speck(
      double size,
      int argb, {
      double? top,
      double? left,
      double? right,
    }) => Positioned(
      top: top,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: Color(argb), shape: BoxShape.circle),
      ),
    );
    return [
      speck(9, 0xFFD9A33F, top: 90, left: 48),
      speck(7, 0xFFC06A45, top: 60, right: 70),
      speck(8, 0xFF7B8456, top: 150, right: 36),
      speck(6, 0xFFD79B86, top: 170, left: 32),
    ];
  }
}
