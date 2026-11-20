import 'package:flutter/material.dart';

import 'daily_puzzle.dart';
import 'home_hero_card.dart';
import 'puzzle_catalog.dart';
import 'riso_markers.dart';
import 'studio_mascots.dart';
import 'studio_theme.dart';

/// The daily-puzzle "Begin card": today's image, its status, and the one
/// action. Deliberately no tracker elements — the streak lives in the
/// quieter [DailyStreakRow] strip below it, so the home screen reads as an
/// invitation to play, not a check-in app (owner ruling, UI-1).
class DailyPuzzleCard extends StatelessWidget {
  const DailyPuzzleCard({
    super.key,
    required this.image,
    required this.doneToday,
    required this.inProgress,
    required this.bloomsToday,
    required this.onPlay,
  });

  final PuzzleImage image;

  /// Whether today's pot has already bloomed.
  final bool doneToday;

  /// Whether a resumable run of this image still credits a pot.
  final bool inProgress;

  /// Whether finishing (a fresh start, or the resumable run) blooms TODAY's
  /// pot. False for a run begun yesterday — its bloom belongs to yesterday,
  /// so the rule line must not promise today's.
  final bool bloomsToday;

  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HomeHeroCard(
      image: image,
      // Owner's v23 rulings: challenge wording, and no visible title —
      // eyebrow + status + rule line are the card's three info.
      eyebrow: "TODAY'S CHALLENGE",
      showTitle: false,
      details: [
        // The done state has no status text: the bloomed cactus alone
        // marks it (owner ruling, UI-2 follow-up).
        if (!doneToday) ...[
          Text(_statusText(), style: theme.textTheme.bodySmall),
          if (bloomsToday)
            // The rule players otherwise trip over: only this painting
            // clicks today's streak piece in.
            Text(
              "Finish it and today's piece clicks in.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
        ],
      ],
      onTap: onPlay,
      action: doneToday
          ? null
          : HeroCardButton(
              label: inProgress ? 'Continue' : 'Begin',
              onPressed: onPlay,
            ),
      marker: doneToday ? _doneMarker() : null,
    );
  }

  /// Today's pot, bloomed — the rule line ("Finish it and today's pot
  /// blooms.") coming true on the card itself, echoing the windowsill
  /// below (owner ruling, UI-2).
  // The label keeps the done state in the card's merged screen-reader
  // utterance now that no visible text carries it.
  Widget _doneMarker() => Semantics(
    label: 'Done today',
    child: const MascotArt(StudioMascot.cactus, height: 40),
  );

  /// The e2e tests assert on these texts. There is no done text: the
  /// bloomed pot alone marks a finished day.
  String _statusText() => inProgress ? statusInProgressLabel : 'Not started';
}

/// The streak, demoted to ambient decor: the current week as a small row
/// of family pieces, Monday to Sunday, with one compact text line. A
/// completed daily clicks its piece in (tomato); today waits bigger;
/// other days stay faint outlines.
class DailyStreakRow extends StatelessWidget {
  const DailyStreakRow({
    super.key,
    required this.now,
    required this.completedDays,
  });

  final DateTime now;
  final Set<String> completedDays;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = utcMidnight(now);
    final monday = today.subtract(Duration(days: now.weekday - 1));
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 7; i++)
              _dayPiece(theme, monday.add(Duration(days: i)), today),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _streakLine(),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  /// One quiet line instead of a headline — the streak is decor, not score.
  String _streakLine() {
    final streak = currentStreak(completedDays, now);
    final longest = longestStreak(completedDays);
    if (streak > 0) {
      return '${streakLabel(streak)} · longest: $longest';
    }
    if (longest > 0) {
      return 'longest: $longest · the pieces wait, no pressure';
    }
    return 'A piece clicks in for every quiet day.';
  }

  Widget _dayPiece(ThemeData theme, DateTime day, DateTime today) {
    final done = completedDays.contains(dayKey(day));
    final isToday = day == today;
    final opacity = done || isToday
        ? 1.0
        // Days still to come sit fainter than missed ones.
        : day.isAfter(today)
        ? 0.35
        : 0.55;
    // A piece's state is invisible to screen readers. One label per day
    // replaces the bare weekday letter; container keeps each day its own
    // announcement instead of merging into the strip.
    return Semantics(
      container: true,
      label: _daySemantics(day, today, done),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: opacity,
            child: done
                ? FamilyPiece(
                    size: isToday ? 21 : 16,
                    fill: StudioColors.tomato,
                    // Today's win gets the print rim, like the sticker.
                    stroke: isToday ? StudioColors.structureDark : null,
                    strokeWidth: 3,
                  )
                : FamilyPiece(
                    size: isToday ? 21 : 16,
                    stroke: StudioColors.structureInk,
                    strokeWidth: 3.5,
                  ),
          ),
          const SizedBox(height: 2),
          Text(
            _letters[day.weekday - 1],
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(
                alpha: isToday ? 1 : 0.55,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _daySemantics(DateTime day, DateTime today, bool done) {
    final name = _names[day.weekday - 1];
    if (done) {
      return '$name: done';
    }
    if (day == today) {
      return '$name: today, not done yet';
    }
    return day.isAfter(today) ? '$name: upcoming' : '$name: not done';
  }
}

