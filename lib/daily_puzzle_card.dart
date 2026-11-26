import 'package:flutter/material.dart';

import 'bonus_track.dart';
import 'daily_puzzle.dart';
import 'home_hero_card.dart';
import 'puzzle_catalog.dart';
import 'riso_markers.dart';
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
      // Owner's v23 rulings: challenge wording, and no visible title.
      // Since 11-26 the status text is gone too — the card reads as
      // eyebrow + rule line + action.
      eyebrow: "TODAY'S CHALLENGE",
      showTitle: false,
      details: [
        // No bare status text in ANY state: the action is the status —
        // Begin, Continue, or the done sticker (owner rulings, UI-2 +
        // 11-26). The button is hidden from screen readers (the card is
        // one merged stop), so the pending states ride along here as an
        // invisible label, like the hidden title above.
        if (doneToday)
          // The rule line's promise, fulfilled in its own words — the
          // sticker alone read unclear on device (owner feedback 11-26).
          Text(
            "Today's piece clicked in.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          )
        else ...[
          Semantics(label: _statusText(), child: const SizedBox.shrink()),
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

  /// The catalog's own done mark (v21 status family): the rule line's
  /// piece, clicked in — the plant-era cactus retired with the pots
  /// (owner ruling, 11-26). The sticker's own 'Completed' label joins the
  /// merged card utterance.
  Widget _doneMarker() => const DonePieceSticker();

  /// Screen-reader-only: visually the Begin/Continue button carries the
  /// pending states, but it is excluded from semantics. The done state has
  /// its own visible line and sticker instead.
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
    required this.showBonusHook,
  });

  final DateTime now;
  final Set<String> completedDays;

  /// Whether the line may mention bonus pieces. False until the journey
  /// unlocks (5 first finishes): before the player has seen the bonus
  /// board in Collection, "bonus piece" would be an unexplained promise
  /// (owner ruling, 11-26). Pieces bank silently either way.
  final bool showBonusHook;

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
        const SizedBox(height: 8),
        _streakText(theme),
      ],
    );
  }

  /// One line under the pieces — a live streak speaks up in tomato bold,
  /// and the tail looks FORWARD: days until the run earns its next bonus
  /// piece, never more than [streakDaysPerPiece] away (owner ruling,
  /// 11-26 — "best/longest" was a backward stat that explained nothing;
  /// a near reward is the come-back-tomorrow hook).
  Widget _streakText(ThemeData theme) {
    final streak = currentStreak(completedDays, now);
    final style = theme.textTheme.bodyMedium;
    if (streak > 0) {
      final daysLeft = streakDaysPerPiece - streak % streakDaysPerPiece;
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: streakLabel(streak),
              style: style?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (showBonusHook)
              TextSpan(
                text:
                    ' · $daysLeft ${daysLeft == 1 ? 'day' : 'days'} '
                    'to a bonus piece',
              ),
          ],
        ),
        textAlign: TextAlign.center,
        style: style,
      );
    }
    final line = completedDays.isEmpty
        ? 'A piece clicks in for every quiet day.'
        : 'The pieces wait, no pressure.';
    return Text(line, textAlign: TextAlign.center, style: style);
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
            // 22/28, up from 16/21: the streak is the screen's retention
            // hook and earns hero-adjacent weight (owner ruling, 11-26).
            child: done
                ? FamilyPiece(
                    size: isToday ? 28 : 22,
                    fill: StudioColors.tomato,
                    // Today's win gets the print rim, like the sticker.
                    stroke: isToday ? StudioColors.structureDark : null,
                    strokeWidth: 3.5,
                  )
                : FamilyPiece(
                    size: isToday ? 28 : 22,
                    stroke: StudioColors.structureInk,
                    strokeWidth: 4,
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            _letters[day.weekday - 1],
            style: theme.textTheme.labelMedium?.copyWith(
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

