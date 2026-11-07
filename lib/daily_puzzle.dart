// Daily puzzle + streak overview:
// 1. Every calendar day maps to one catalog image — the "daily puzzle".
//    The pick is seeded from the date so it is identical after a restart
//    and across platforms (no server involved).
// 2. Streak math works on day keys ("2026-11-02"): consecutive completed
//    days ending today (or yesterday — an unplayed today never shows a
//    broken streak before the day is over).
// Pure date/selection logic; storage lives in daily_streak.dart.

import 'piece_shapes.dart';
import 'puzzle_catalog.dart';

/// Calendar-day identity: "2026-11-02". Uses the device's local date and
/// zero-pads so keys sort chronologically as plain strings.
String dayKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

/// [date]'s calendar day as a UTC midnight. All day arithmetic happens on
/// these values: adding or subtracting Durations on local DateTimes can
/// land on the wrong day around daylight-saving changes.
DateTime utcMidnight(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

/// The one puzzle image assigned to [date]'s calendar day.
///
/// Seeded with [shapeSeedForKey] (stable across platforms — the same repo
/// rule as piece shapes). Adding or removing catalog images reshuffles
/// every day's pick, past ones included — harmless, because credit keys
/// off the day a run began (see [dailyCreditDay]), so only a run resumed
/// across an app update can see a different pick.
PuzzleImage dailyPuzzleFor(
  DateTime date, {
  List<PuzzleImage> catalog = puzzleCatalog,
}) {
  final seed = shapeSeedForKey('daily.${dayKey(date)}');
  return catalog[seed % catalog.length];
}

/// The day a finished run of [imageId] credits: [startedDay] — the day the
/// run was BEGUN, stamped into its save — when the image was that day's
/// daily and the run finished within one day of starting. Null otherwise.
///
/// Keying off the stamped start day keeps the streak honest: a daily begun
/// at 23:50 and finished at 00:05 (live, or saved and resumed next morning)
/// blooms the pot of the day it belonged to, a fresh play of yesterday's
/// image credits nothing, and when the same image is the daily two days
/// running each run credits the day it actually began. A null [startedDay]
/// (a save from before the stamp existed) credits nothing.
String? dailyCreditDay(
  String imageId,
  DateTime completedAt, {
  required String? startedDay,
  List<PuzzleImage> catalog = puzzleCatalog,
}) {
  if (startedDay == null) {
    return null;
  }
  final started = DateTime.tryParse('${startedDay}T00:00:00Z');
  // Round-trip check: tryParse NORMALIZES malformed dates ("2026-11-31"
  // becomes Dec 1), which must not manufacture a creditable day.
  if (started == null || dayKey(started) != startedDay) {
    return null;
  }
  // One-day grace: finishing the day after the run began still blooms its
  // pot; any later (or a clock running backwards) credits nothing.
  final daysLate = utcMidnight(completedAt).difference(started).inDays;
  if (daysLate < 0 || daysLate > 1) {
    return null;
  }
  return dailyPuzzleFor(started, catalog: catalog).id == imageId
      ? startedDay
      : null;
}

/// The streak phrase shared by the windowsill and the completion wall, so
/// the two surfaces cannot drift apart in wording.
String streakLabel(int streak) => '$streak-day streak';

/// The completion wall's bloom caption for a run credited to [creditDay]
/// and finished at [completedAt]. [dailyCreditDay] only ever credits the
/// finish day or the day before it, so the pot is today's or yesterday's —
/// resolved once, here, against the completion moment (a caption computed
/// against a later clock would flip words when a rebuild crosses midnight).
String dailyBloomCaption(String creditDay, DateTime completedAt, int streak) {
  final pot = creditDay == dayKey(completedAt) ? "Today's" : "Yesterday's";
  return "$pot pot bloomed · ${streakLabel(streak)}";
}

/// Consecutive completed days ending at [today] — or ending yesterday when
/// today is not done yet, so the streak reads "alive" until midnight.
int currentStreak(Set<String> completedDays, DateTime today) {
  var day = utcMidnight(today);
  const oneDay = Duration(days: 1);
  if (!completedDays.contains(dayKey(day))) {
    day = day.subtract(oneDay);
  }
  var streak = 0;
  while (completedDays.contains(dayKey(day))) {
    streak++;
    day = day.subtract(oneDay);
  }
  return streak;
}

/// The longest run of consecutive completed days, ever.
int longestStreak(Set<String> completedDays) {
  // Parse at UTC midnight so daylight-saving changes never shorten a day.
  final days =
      completedDays
          .map((key) => DateTime.tryParse('${key}T00:00:00Z'))
          .nonNulls
          .toList()
        ..sort();
  var longest = 0;
  var run = 0;
  DateTime? previous;
  for (final day in days) {
    run = previous != null && day.difference(previous).inDays == 1
        ? run + 1
        : 1;
    if (run > longest) {
      longest = run;
    }
    previous = day;
  }
  return longest;
}
