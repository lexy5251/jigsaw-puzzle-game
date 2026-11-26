import 'package:flutter/material.dart';

import 'puzzle_catalog.dart';
import 'studio_surfaces.dart';
import 'studio_theme.dart';

/// The home screen's hero-card scaffold, shared by the daily Begin card and
/// the continue card. The two sit stacked on the home screen and must read
/// as one family — sharing the scaffold (framed thumbnail, small-caps
/// eyebrow, one-line title, detail lines, trailing action) makes drift
/// impossible instead of merely unlikely.
class HomeHeroCard extends StatelessWidget {
  const HomeHeroCard({
    super.key,
    required this.image,
    required this.eyebrow,
    required this.details,
    required this.onTap,
    this.action,
    this.marker,
    this.semanticsIdentifier,
    this.showTitle = true,
  });

  /// The painting on the card; also provides the title line and the
  /// thumbnail's decode-failure fallback text.
  final PuzzleImage image;

  /// Small-caps kicker above the title ("TODAY'S PAINTING").
  final String eyebrow;

  /// Lines under the title (status, rule hints), styled by the caller.
  final List<Widget> details;

  final VoidCallback onTap;

  /// The card's button, if it has one. Trailing on wide layouts; dropped
  /// under the text on narrow phones or enlarged text. The scaffold hides
  /// it from screen readers — the card itself is the one semantic tap
  /// target (merged below), so they hear a single stop instead of the
  /// card and then a redundant button.
  final Widget? action;

  /// Non-interactive trailing ornament (the daily card's done sticker).
  /// Always keeps the row slot; callers pass [marker] or [action], not
  /// both.
  final Widget? marker;

  /// Stable e2e hook; null for cards found by their texts.
  final String? semanticsIdentifier;

  /// The daily card hides its visible title (owner's v23 "three info"
  /// ruling — the photo speaks); the painting's name stays in the merged
  /// screen-reader utterance either way.
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Enlarged text or a narrow phone: the action moves under the text
    // instead of crushing the title.
    final stacked =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(16) > 24;
    final rowTrailing = marker ?? (stacked ? null : action);
    final actionBelow = stacked ? action : null;

    return Semantics(
      identifier: semanticsIdentifier,
      button: true,
      child: MergeSemantics(
        child: PaintedCard(
          onTap: onTap,
          padding: const EdgeInsets.all(16),
          child: actionBelow == null
              ? _info(theme, trailing: rowTrailing)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _info(theme, trailing: rowTrailing),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ExcludeSemantics(child: actionBelow),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _info(ThemeData theme, {required Widget? trailing}) {
    return Row(
      children: [
        FramedThumbnail(
          dimension: 72,
          assetPath: image.assetPath,
          title: image.title,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: theme.textTheme.labelSmall?.copyWith(
                  // Eyebrows are structure-dark small caps (riso spec);
                  // tomato stays reserved for actions and the rule line.
                  color: StudioColors.structureDark,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              if (showTitle) ...[
                const SizedBox(height: 2),
                Text(
                  image.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ] else
                // Keeps the painting's name in the merged utterance while
                // the visible card stays title-less.
                Semantics(label: image.title, child: const SizedBox.shrink()),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 2),
                ...details,
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          // A marker carries its own semantics; an action is hidden (the
          // merged card is the tap target).
          identical(trailing, marker)
              ? trailing
              : ExcludeSemantics(child: trailing),
        ],
      ],
    );
  }
}

/// The hero cards' compact action button — one definition, one look.
class HeroCardButton extends StatelessWidget {
  const HeroCardButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
