import 'package:flutter/material.dart';

import 'daily_puzzle.dart';
import 'puzzle_catalog.dart';

/// The daily-puzzle card: today's image, its status, and the windowsill.
class DailyPuzzleCard extends StatelessWidget {
  const DailyPuzzleCard({
    super.key,
    required this.image,
    required this.now,
    required this.completedDays,
    required this.inProgress,
    required this.onPlay,
  });

  final PuzzleImage image;
  final DateTime now;
  final Set<String> completedDays;

  /// Whether today's daily has a resumable run that still credits a pot.
  final bool inProgress;

  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doneToday = completedDays.contains(dayKey(now));
    final streak = currentStreak(completedDays, now);
    final longest = longestStreak(completedDays);
    final fadedInk = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Card(
      child: InkWell(
        onTap: onPlay,
        // Match the card's rounded shape so the tap ripple clips to it.
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
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
                        Text(
                          _statusText(doneToday),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: fadedInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    doneToday ? Icons.check_circle : Icons.arrow_forward,
                    color: doneToday
                        ? theme.colorScheme.secondary
                        : theme.colorScheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Windowsill(now: now, completedDays: completedDays),
              const SizedBox(height: 10),
              Text(
                streak == 0
                    ? 'A pot blooms for every quiet day.'
                    : '$streak-day streak',
                textAlign: TextAlign.center,
                style: streak == 0
                    ? theme.textTheme.bodySmall?.copyWith(color: fadedInk)
                    : theme.textTheme.titleMedium,
              ),
              if (longest > 0)
                Text(
                  'longest: $longest · pots regrow, no pressure',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: fadedInk),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The e2e tests assert on these texts.
  String _statusText(bool doneToday) {
    if (doneToday) {
      return 'Done today ✓';
    }
    return inProgress ? 'In progress' : 'Not started';
  }
}

/// The current week as a row of pots, Monday to Sunday: a completed daily
/// blooms, today's empty pot waits in terracotta, other days stay faint.
class _Windowsill extends StatelessWidget {
  const _Windowsill({required this.now, required this.completedDays});

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
    final today = utcMidnight(now);
    final monday = today.subtract(Duration(days: now.weekday - 1));
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var i = 0; i < 7; i++)
          _pot(Theme.of(context), monday.add(Duration(days: i)), today),
      ],
    );
  }

  Widget _pot(ThemeData theme, DateTime day, DateTime today) {
    final done = completedDays.contains(dayKey(day));
    final isToday = day == today;
    final color = done
        ? theme.colorScheme.secondary
        : isToday
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(
            // Days still to come sit fainter than missed ones.
            alpha: day.isAfter(today) ? 0.15 : 0.3,
          );
    // The pot's state lives in icon fill, size, and color — invisible to
    // screen readers. One label per day replaces the bare weekday letter.
    return Semantics(
      label: _potSemantics(day, today, done),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.local_florist : Icons.local_florist_outlined,
            size: isToday ? 30 : 24,
            color: color,
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
