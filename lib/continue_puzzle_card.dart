import 'package:flutter/material.dart';

import 'home_hero_card.dart';
import 'my_puzzles.dart';

/// The home screen's "welcome back" strip: the most recently played
/// unfinished puzzle with a one-tap Resume. A [HomeHeroCard], so it and
/// the daily card below it always read as one family; hidden entirely (by
/// the select screen) when nothing is in progress.
class ContinuePuzzleCard extends StatelessWidget {
  const ContinuePuzzleCard({
    super.key,
    required this.run,
    required this.onResume,
  });

  /// The run the card reopens — the newest resumable save, resolved by the
  /// select screen.
  final InProgressRun run;

  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HomeHeroCard(
      image: run.image,
      eyebrow: 'CONTINUE PUZZLE',
      details: [
        // Locked pieces only — the same count the in-game palette counter
        // shows; loose pieces on the board are progress too but are not
        // "placed".
        Text(
          '${run.placedCount} of ${run.size.pieceCount} pieces',
          style: theme.textTheme.bodySmall,
        ),
      ],
      onTap: onResume,
      action: HeroCardButton(label: 'Resume', onPressed: onResume),
      // The stable e2e hook; the texts inside stay free to change.
      semanticsIdentifier: 'continue-puzzle',
    );
  }
}
