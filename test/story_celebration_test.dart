// The one-time celebration rules: what plays when, what a torn parcel
// remembers, and how storage failures degrade (replays, never lost
// progress).

import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/story_celebration.dart';

void main() {
  group('revealToPlay', () {
    test('a fresh reader gets no fanfare — there is nothing to arrive', () {
      expect(
        revealToPlay(const StoryCelebrations(), finished: 0, total: 8),
        StoryReveal.none,
      );
    });

    test('an unseen unlock plays once, then goes quiet', () {
      const beforeSeen = StoryCelebrations(arrivals: 1, opened: 1);
      expect(
        revealToPlay(beforeSeen, finished: 1, total: 8),
        StoryReveal.unlock,
      );
      final afterSeen = beforeSeen.copyWith(arrivals: 2);
      expect(revealToPlay(afterSeen, finished: 1, total: 8), StoryReveal.none);
    });

    test('several scenes finished in one game session celebrate once', () {
      // Chained next-puzzle runs can finish scenes 2 AND 3 before the tab
      // is looked at again — one arrival for the furthest stop.
      const seen = StoryCelebrations(arrivals: 2, opened: 2);
      expect(revealToPlay(seen, finished: 3, total: 8), StoryReveal.unlock);
      expect(
        revealToPlay(seen.copyWith(arrivals: 4), finished: 3, total: 8),
        StoryReveal.none,
      );
    });

    test('the finale plays once when every scene is read', () {
      const seen = StoryCelebrations(arrivals: 8, opened: 8);
      expect(revealToPlay(seen, finished: 8, total: 8), StoryReveal.finale);
      expect(
        revealToPlay(
          seen.copyWith(finaleShown: true),
          finished: 8,
          total: 8,
        ),
        StoryReveal.none,
      );
    });
  });

  group('currentStopWrapped', () {
    test('the parcel waits until torn, and a finish rewraps the next', () {
      const fresh = StoryCelebrations();
      expect(currentStopWrapped(fresh, finished: 0), isTrue);
      // Torn open: scene 1's card shows.
      expect(
        currentStopWrapped(fresh.copyWith(opened: 1), finished: 0),
        isFalse,
      );
      // Scene 1 finished → stop 2 is current and wrapped again, with no
      // extra bookkeeping.
      expect(
        currentStopWrapped(fresh.copyWith(opened: 1), finished: 1),
        isTrue,
      );
    });
  });

  group('StoryCelebrations json', () {
    test('round-trips', () {
      const value = StoryCelebrations(
        arrivals: 5,
        opened: 4,
        finaleShown: true,
      );
      expect(
        StoryCelebrations.fromJson('{"arrivals":5,"opened":4,'
            '"finaleShown":true}'),
        value,
      );
    });

    test('missing or malformed data reads as nothing celebrated', () {
      expect(StoryCelebrations.fromJson(null), const StoryCelebrations());
      expect(StoryCelebrations.fromJson('not json'), const StoryCelebrations());
      expect(StoryCelebrations.fromJson('[]'), const StoryCelebrations());
      expect(
        StoryCelebrations.fromJson('{"arrivals":"x","opened":-2}'),
        const StoryCelebrations(),
      );
    });
  });

  test('the in-memory store round-trips for suites', () async {
    final store = InMemoryStoryCelebrationStore();
    expect(await store.read(), const StoryCelebrations());
    const value = StoryCelebrations(arrivals: 3, opened: 2);
    await store.write(value);
    expect(await store.read(), value);
  });
}
