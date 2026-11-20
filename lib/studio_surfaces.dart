// The sticker material of the riso chrome (docs/ui-theme-colors.md, icon
// reference docs/design/icon-set-final.png): cards are printed stickers — a
// structure-ink border with a hard SAME-ink offset shadow, zero blur (a
// different-color or blurred shadow reads as error, not print). Torn-paper
// edges retired with the chrome swap (v17 ruling supersedes UI-5).

import 'package:flutter/material.dart';

import 'studio_theme.dart';

/// A card printed as a sticker: card fill, structure-ink border, hard
/// same-ink offset shadow. Replaces [Card] on Studio screens.
class PaintedCard extends StatelessWidget {
  const PaintedCard({
    super.key,
    this.color,
    this.onTap,
    this.padding,
    this.shadow = softShadow,
    required this.child,
  });

  /// The standard sticker shadow (mock `.riso`: 5px 6px, no blur).
  static const softShadow = BoxShadow(
    color: StudioColors.cardShadow,
    offset: Offset(5, 6),
  );

  /// A step smaller, for grid-size tiles where the full offset reads
  /// oversized (mock photo cards: 4px 5px).
  static const groundShadow = BoxShadow(
    color: StudioColors.cardShadow,
    offset: Offset(4, 5),
  );

  /// Border weight shared by every sticker surface.
  static const borderWidth = 2.5;

  /// Corner rounding shared by every sticker card.
  static const cornerRadius = Radius.circular(16);

  /// Fill color; defaults to the theme's card surface.
  final Color? color;

  /// The card's offset shadow; [softShadow] unless the context needs less.
  final BoxShadow shadow;

  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: const BorderRadius.all(cornerRadius),
      side: const BorderSide(
        color: StudioColors.structureInk,
        width: borderWidth,
      ),
    );
    final content = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    return DecoratedBox(
      decoration: ShapeDecoration(shape: shape, shadows: [shadow]),
      child: Material(
        color: color ?? Theme.of(context).colorScheme.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// Artwork in its frame: a structure-ink border hugging a rounded clip
/// (mock `.img-frame`: 2.5px border, radius 12, no shadow of its own —
/// the card underneath carries the shadow). Wrap the image in this.
class FramedArt extends StatelessWidget {
  const FramedArt({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Foreground so the border overlaps the artwork's edge pixels.
      foregroundDecoration: BoxDecoration(
        borderRadius: const BorderRadius.all(TiltedPhotoCard.cornerRadius),
        border: Border.all(
          color: StudioColors.structureInk,
          width: PaintedCard.borderWidth,
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(TiltedPhotoCard.cornerRadius),
        child: child,
      ),
    );
  }
}

/// Artwork at thumbnail size in its frame: the shared decode width and a
/// visible-title fallback when the photo cannot decode. The completion
/// card's gift reveal and the Story page's scene cards read this one
/// recipe so the two cannot drift apart.
class FramedThumbnail extends StatelessWidget {
  const FramedThumbnail({
    super.key,
    required this.dimension,
    required this.assetPath,
    required this.title,
  });

  final double dimension;
  final String assetPath;

  /// Shown only if the photo fails to decode — a blank anonymous frame
  /// would otherwise hide which artwork went missing.
  final String title;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: dimension,
      child: FramedArt(
        child: Image.asset(
          assetPath,
          fit: BoxFit.cover,
          cacheWidth: TiltedPhotoCard.thumbnailCacheWidth,
          errorBuilder: (context, _, _) => ColoredBox(
            color: StudioColors.card,
            child: Center(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The photo grids' shared geometry (2 across on phones — UI-6 ruling):
/// the home grid and My Puzzles must render identically, so both read
/// this one spec.
const photoGridPadding = EdgeInsets.all(16);
const photoGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 200,
  mainAxisSpacing: 20,
  crossAxisSpacing: 20,
  // The catalog photos are square (1:1), so square cells crop nothing.
  childAspectRatio: 1.0,
);

/// A catalog photo as a sticker card: straight rounded edges (the tilt
/// retired with the riso chrome — owner's v19→v20 "no tilt" ruling), a
/// structure-ink border with the hard offset shadow, and no visible title
/// (names live on in the semantics label). Shared by the home grid
/// and My Puzzles so the two grids cannot drift apart.
class TiltedPhotoCard extends StatelessWidget {
  const TiltedPhotoCard({
    super.key,
    required this.assetPath,
    required this.title,
    required this.semanticsIdentifier,
    required this.onTap,
    this.overlays = const [],
    this.cornerMarker,
  });

  /// Corner rounding of the photo card.
  static const cornerRadius = Radius.circular(12);

  /// Decode width for every photo thumbnail surface. The ImageCache keys
  /// on this value, so all surfaces (and the preview harnesses' warm-up)
  /// must share it or the same photo decodes twice.
  static const thumbnailCacheWidth = 640;

  final String assetPath;

  /// Screen-reader name and decode-failure fallback; never painted.
  final String title;

  /// Lets e2e tests tap one specific photo without matching its title.
  final String semanticsIdentifier;

  final VoidCallback onTap;

  /// Stacked over the photo, under the tap ripple (badges, count chips).
  final List<Widget> overlays;

  /// Rendered OUTSIDE the photo clip, hanging over the top-right corner —
  /// the done piece sticker's slot. Overlays can't do this: they live
  /// inside the ClipRRect.
  final Widget? cornerMarker;

  @override
  Widget build(BuildContext context) {
    final card = Container(
        decoration: const BoxDecoration(
          // Opaque surface so the tile reads as a card while the photo is
          // still decoding (or if it ever fails), not a floating shadow.
          color: StudioColors.card,
          borderRadius: BorderRadius.all(cornerRadius),
          border: Border.fromBorderSide(
            BorderSide(
              color: StudioColors.structureInk,
              width: PaintedCard.borderWidth,
            ),
          ),
          boxShadow: [PaintedCard.groundShadow],
        ),
        child: ClipRRect(
          // Inside the border, so clip to the slightly smaller inner radius.
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                assetPath,
                fit: BoxFit.cover,
                // Decode smaller previews to reduce memory use.
                cacheWidth: thumbnailCacheWidth,
                // A photo that fails to decode would otherwise leave an
                // anonymous blank card — fall back to the visible title.
                errorBuilder: (context, _, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
              ),
              ...overlays,
              // Above the photo so the tap ripple shows on it.
              Material(
                type: MaterialType.transparency,
                child: InkWell(onTap: onTap),
              ),
            ],
          ),
        ),
      );
    return Semantics(
      identifier: semanticsIdentifier,
      label: title,
      button: true,
      child: cornerMarker == null
          ? card
          : Stack(
              clipBehavior: Clip.none,
              children: [
                card,
                Positioned(
                  top: -9,
                  right: -8,
                  // Decoration only: without this the marker's CustomPaint
                  // hit-tests opaque and eats taps meant for the card.
                  child: IgnorePointer(child: cornerMarker),
                ),
              ],
            ),
    );
  }
}

/// A page's big title in the riso voice: chunky Rokkitt in structure ink
/// with the one allowed salmon "misprint" shadow (dial rule 2 — the
/// misprint lives on big titles only; everything else gets same-ink
/// offset shadows).
class RisoPageTitle extends StatelessWidget {
  const RisoPageTitle(this.text, {super.key, this.fontSize = 30});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Rokkitt',
        fontWeight: FontWeight.w800,
        fontSize: fontSize,
        height: 1.1,
        color: StudioColors.structureInk,
        letterSpacing: 0.5,
        shadows: const [
          Shadow(offset: Offset(3, 3), color: StudioColors.salmon),
        ],
      ),
    );
  }
}

/// The halftone accent beside page titles: a field of structure-ink dots
/// fading in toward the right (dial rule 1 — the dots live ONLY beside
/// titles, never behind image grids).
class HalftoneDots extends StatelessWidget {
  const HalftoneDots({super.key, this.height = 34});

  final double height;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: const CustomPaint(painter: _HalftoneDotsPainter()),
      ),
    );
  }
}

class _HalftoneDotsPainter extends CustomPainter {
  const _HalftoneDotsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 10.0;
    const radius = 1.7;
    final paint = Paint();
    for (var x = size.width - spacing / 2; x > 0; x -= spacing) {
      // Fade out leftward, toward the title.
      final strength = (x / size.width).clamp(0.0, 1.0);
      if (strength < 0.15) {
        continue;
      }
      paint.color = StudioColors.structureInk.withValues(alpha: strength);
      for (var y = spacing / 2; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The shared page app bar: the big riso title on the left (after an
/// optional [titlePrefix] like a category mascot) with the halftone accent
/// filling the rest of the row. Accessibility text sizes scale the title
/// freely; the FittedBox only shrinks it once it would burst the bar, so
/// large-text users keep as much growth as the width allows.
AppBar risoAppBar(
  String title, {
  Widget? titlePrefix,
  PreferredSizeWidget? bottom,
  double fontSize = 26,
}) {
  return AppBar(
    centerTitle: false,
    titleSpacing: 16,
    title: Row(
      children: [
        if (titlePrefix != null) ...[titlePrefix, const SizedBox(width: 10)],
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: RisoPageTitle(title, fontSize: fontSize),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: HalftoneDots()),
      ],
    ),
    bottom: bottom,
  );
}

/// A small organic-edged dot of accent paint (board-color swatches).
class PaintedSwatch extends StatelessWidget {
  const PaintedSwatch({super.key, required this.color, this.size = 14});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    // The elliptical radii scale with the size so a larger daub keeps the
    // same organic silhouette instead of looking rounder.
    final unit = size / 14;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.only(
          topLeft: Radius.elliptical(7 * unit, 6 * unit),
          topRight: Radius.elliptical(6 * unit, 8 * unit),
          bottomLeft: Radius.elliptical(6 * unit, 7 * unit),
          bottomRight: Radius.elliptical(8 * unit, 6 * unit),
        ),
      ),
    );
  }
}
