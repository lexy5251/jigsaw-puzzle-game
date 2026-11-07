import 'package:flutter/material.dart';

import 'daily_puzzle.dart';
import 'puzzle_catalog.dart';
import 'studio_mascots.dart';
import 'studio_surfaces.dart';

/// The daily-puzzle "Begin card": today's image, its status, and the one
/// action. Deliberately no tracker elements — the streak lives in the
/// quieter [DailyWindowsill] strip below it, so the home screen reads as an
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
    // Enlarged text or a narrow phone: the action moves under the text
    // instead of crushing the title (same breakpoint idea as the game
    // screen's separateTools).
    final stacked =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(16) > 24;
    // The button is a visual affordance only: the card itself is the one
    // semantic tap target (merged below), so screen readers hear a single
    // stop instead of the card and then a redundant 'Begin'.
    final action = doneToday
        ? null
        : ExcludeSemantics(
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onPlay,
              child: Text(inProgress ? 'Continue' : 'Begin'),
            ),
          );

    return Semantics(
      button: true,
      child: MergeSemantics(
        child: PaintedCard(
          onTap: onPlay,
          padding: const EdgeInsets.all(16),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _info(theme, trailing: doneToday ? _doneIcon(theme) : null),
                    if (action != null) ...[
                      const SizedBox(height: 10),
                      Align(alignment: Alignment.centerRight, child: action),
                    ],
                  ],
                )
              : _info(
                  theme,
                  trailing: doneToday ? _doneIcon(theme) : action,
                ),
        ),
      ),
    );
  }

  Widget _doneIcon(ThemeData theme) =>
      Icon(Icons.check_circle, color: theme.colorScheme.secondary);

  Widget _info(ThemeData theme, {required Widget? trailing}) {
    return Row(
      children: [
        FramedArt(
          child: Image.asset(
            image.assetPath,
            width: 72,
            height: 72,
            fit: BoxFit.cover,
            // Same decode width as the catalog tiles, so the daily
            // image shares their ImageCache entry instead of
            // decoding the asset a second time.
            cacheWidth: 640,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "TODAY'S PAINTING",
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                image.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(_statusText(), style: theme.textTheme.bodySmall),
              if (!doneToday && bloomsToday)
                // The rule players otherwise trip over: only this painting
                // blooms a pot.
                Text(
                  "Finish it and today's pot blooms.",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    );
  }

  /// The e2e tests assert on these texts.
  String _statusText() {
    if (doneToday) {
      return 'Done today ✓';
    }
    return inProgress ? 'In progress' : 'Not started';
  }
}

/// The streak, demoted to ambient decor: the current week as a small row of
/// pots on a shelf, Monday to Sunday, with one compact text line. A
/// completed daily blooms, today's empty pot waits in terracotta, other
/// days stay faint.
class DailyWindowsill extends StatelessWidget {
  const DailyWindowsill({
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
              _pot(theme, monday.add(Duration(days: i)), today),
          ],
        ),
        // The wooden shelf the pots stand on (mockup .shelfline).
        Container(
          height: 5,
          margin: const EdgeInsets.fromLTRB(24, 3, 24, 0),
          decoration: const BoxDecoration(
            color: Color(0xFFC9A36A),
            borderRadius: BorderRadius.all(Radius.circular(3)),
            boxShadow: [
              BoxShadow(
                color: Color(0x405A3C1E),
                offset: Offset(0, 2),
                blurRadius: 4,
              ),
            ],
          ),
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
      return 'longest: $longest · pots regrow, no pressure';
    }
    return 'A pot blooms for every quiet day.';
  }

  Widget _pot(ThemeData theme, DateTime day, DateTime today) {
    final done = completedDays.contains(dayKey(day));
    final isToday = day == today;
    // The painted motifs carry their own colors, so day states live in the
    // motif (bloomed cactus vs empty pot), size, and opacity instead of tint.
    final opacity = done
        ? (isToday ? 1.0 : 0.75)
        : isToday
        ? 1.0
        // Days still to come sit fainter than missed ones.
        : day.isAfter(today)
        ? 0.25
        : 0.45;
    // The pot's state is invisible to screen readers. One label per day
    // replaces the bare weekday letter; container keeps each day its own
    // announcement instead of merging into the strip.
    return Semantics(
      container: true,
      label: _potSemantics(day, today, done),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: opacity,
            child: MascotArt(
              done ? StudioMascot.cactus : StudioMascot.pot,
              height: isToday ? 30 : 24,
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

  String _potSemantics(DateTime day, DateTime today, bool done) {
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
