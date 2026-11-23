// Story celebration overview:
// 1. The trail celebrates each unlock ONCE: the newly read scene snaps into
//    its frame, the fresh path dots pop in, and the parcel waits to be torn
//    open. Reading all eight scenes earns a one-time finale. Replaying any
//    of it on later visits would cheapen the moment, so what has already
//    played is persisted here.
// 2. Progress itself stays fully derived (story_track.dart); this store
//    remembers only which celebrations the player has SEEN. Losing it can
//    never lose progress — at worst a celebration plays again.
// 3. Decisions are pure functions over (finished, seen) so the rules are
//    unit-testable without a screen.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the trail should play when the page becomes visible.
enum StoryReveal {
  /// Nothing new — render the resting state.
  none,

  /// A new scene was finished since the last look: snap the read scene in,
  /// pop the fresh dots, land the parcel.
  unlock,

  /// Every scene is read and the finale has not played yet.
  finale,
}

/// What has already been celebrated, as stored.
@immutable
class StoryCelebrations {
  const StoryCelebrations({
    this.arrivals = 0,
    this.opened = 0,
    this.finaleShown = false,
  });

  /// Stops whose arrival sequence (snap-in + dots) has played. A value of
  /// N means the trail up to stop N (1-based) has been seen growing.
  final int arrivals;

  /// Parcels torn open so far. The current stop shows its mystery card
  /// once this passes it; until then it waits as a parcel.
  final int opened;

  /// Whether the all-scenes-read finale has played.
  final bool finaleShown;

  StoryCelebrations copyWith({int? arrivals, int? opened, bool? finaleShown}) {
    return StoryCelebrations(
      arrivals: arrivals ?? this.arrivals,
      opened: opened ?? this.opened,
      finaleShown: finaleShown ?? this.finaleShown,
    );
  }

  Map<String, Object> toJson() => {
    'arrivals': arrivals,
    'opened': opened,
    'finaleShown': finaleShown,
  };

  /// Malformed or missing data reads as "nothing celebrated": the worst
  /// outcome is a replayed celebration, never lost progress.
  factory StoryCelebrations.fromJson(String? raw) {
    if (raw == null) {
      return const StoryCelebrations();
    }
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) {
        return const StoryCelebrations();
      }
      final arrivals = data['arrivals'];
      final opened = data['opened'];
      final finaleShown = data['finaleShown'];
      return StoryCelebrations(
        arrivals: arrivals is int && arrivals >= 0 ? arrivals : 0,
        opened: opened is int && opened >= 0 ? opened : 0,
        finaleShown: finaleShown is bool && finaleShown,
      );
    } on Object {
      return const StoryCelebrations();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is StoryCelebrations &&
      other.arrivals == arrivals &&
      other.opened == opened &&
      other.finaleShown == finaleShown;

  @override
  int get hashCode => Object.hash(arrivals, opened, finaleShown);
}

/// What to play for a reader at [finished] of [total] scenes. The arrival
/// of the very first stop plays nothing — there is no previous scene to
/// snap in and no path yet, the parcel simply sits there.
StoryReveal revealToPlay(
  StoryCelebrations seen, {
  required int finished,
  required int total,
}) {
  if (finished >= total) {
    return seen.finaleShown ? StoryReveal.none : StoryReveal.finale;
  }
  if (finished > 0 && seen.arrivals < finished + 1) {
    return StoryReveal.unlock;
  }
  return StoryReveal.none;
}

/// Whether the current stop still waits as a tearable parcel (true) or has
/// already been torn open into its mystery card (false).
bool currentStopWrapped(StoryCelebrations seen, {required int finished}) =>
    seen.opened <= finished;

/// Reads and records which celebrations have played.
abstract class StoryCelebrationStore {
  Future<StoryCelebrations> read();

  Future<void> write(StoryCelebrations value);
}

/// Device-local storage. Celebration state is decoration — failures are
/// logged in debug builds and never thrown.
class SharedPreferencesStoryCelebrationStore implements StoryCelebrationStore {
  const SharedPreferencesStoryCelebrationStore();

  static const _key = 'story.celebrations';

  @override
  Future<StoryCelebrations> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return StoryCelebrations.fromJson(prefs.getString(_key));
    } on Object catch (error) {
      _logFailure('read', error);
      return const StoryCelebrations();
    }
  }

  @override
  Future<void> write(StoryCelebrations value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(value.toJson()));
    } on Object catch (error) {
      _logFailure('write', error);
    }
  }

  void _logFailure(String operation, Object error) {
    if (kDebugMode) {
      debugPrint('Story celebrations: $operation failed: $error');
    }
  }
}

/// Keeps celebrations in memory; used by tests.
class InMemoryStoryCelebrationStore implements StoryCelebrationStore {
  StoryCelebrations _value = const StoryCelebrations();

  @override
  Future<StoryCelebrations> read() async => _value;

  @override
  Future<void> write(StoryCelebrations value) async => _value = value;
}
