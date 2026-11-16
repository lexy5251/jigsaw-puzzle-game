// The story track's rules (owner's design, 2026-11-14): scenes unlock as
// the longest finished prefix of the scene list — finishing something out
// of order never skips the gate — and scene finishes fund the gift track
// like any gallery painting.

import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/bonus_track.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/story_track.dart';

import 'test_helpers.dart';

/// The shared three-scene fixtures, read as a story (the chain and unlock
/// suites use the same [sceneFixtures], so the scene shape cannot drift).
final _fixtureStory = Story(
  id: 'fixture-story',
  title: 'Fixture Story',
  stops: [
    for (final (index, image) in sceneFixtures.indexed)
      StoryStop(image: image, text: 'Line ${index + 1}.'),
  ],
);

StoryState _state(Set<String> completedIds) =>
    storyStateFor(completedIds, story: _fixtureStory);

void main() {
  group('storyStateFor', () {
    test('a fresh reader starts at scene one', () {
      final state = _state(const {});
      expect(state.finishedStops, 0);
      expect(state.complete, isFalse);
      expect(state.nextStop?.image.id, 'scene-1');
    });

    test('each finished scene opens exactly the next one', () {
      expect(_state(const {'scene-1'}).nextStop?.image.id, 'scene-2');
      expect(
        _state(const {'scene-1', 'scene-2'}).nextStop?.image.id,
        'scene-3',
      );
    });

    test('a finish further down the list does not skip the gate', () {
      // Impossible through the app (locked scenes are not tappable), but
      // conceivable in storage — the prefix rule holds regardless.
      final state = _state(const {'scene-3'});
      expect(state.finishedStops, 0);
      expect(state.nextStop?.image.id, 'scene-1');
    });

    test('finishing every scene completes the story', () {
      final state = _state(const {'scene-1', 'scene-2', 'scene-3'});
      expect(state.complete, isTrue);
      expect(state.finishedStops, state.totalStops);
      expect(state.nextStop, isNull);
    });

    test('foreign finishes are ignored', () {
      final state = _state(const {'alpine-lakes-panorama', 'scene-1'});
      expect(state.finishedStops, 1);
    });

    test('defaults to the shipped story', () {
      expect(storyStateFor(const {}).story.id, 'how-the-jigsaw-was-born');
    });
  });

  group('nextSceneToRead', () {
    // The completion chain derives its "Next puzzle" offer from this —
    // it must mirror storyStateFor's prefix gate exactly.
    test('agrees with the page gate on prefix reads', () {
      expect(nextSceneToRead(const {}, sceneFixtures)?.id, 'scene-1');
      expect(nextSceneToRead(const {'scene-1'}, sceneFixtures)?.id, 'scene-2');
    });

    test('a gap points back at the open scene, not past it', () {
      // Scene 3 on record without scene 2 (a failed write mid-chain): the
      // offer is the scene the Story page shows open — never a wrapped one.
      expect(
        nextSceneToRead(const {'scene-1', 'scene-3'}, sceneFixtures)?.id,
        'scene-2',
      );
    });

    test('a fully read story offers nothing', () {
      expect(
        nextSceneToRead(const {'scene-1', 'scene-2', 'scene-3'}, sceneFixtures),
        isNull,
      );
    });
  });

  test('scene order is frozen', () {
    // Unlocks are positional AND the order is the narrative: anyone editing
    // the scene list must re-check this pin knowingly — inserting or
    // reordering shipped entries would re-lock scenes players already read.
    expect([for (final scene in storyPuzzleCatalog) scene.id], [
      'story-mapmakers-shop',
      'story-first-cut',
      'story-learning-the-world',
      'story-pictures-join-in',
      'story-swooping-saw',
      'story-cardboard-boom',
      'story-boxes-on-every-shelf',
      'story-your-table-today',
    ]);
  });

  test('every catalog scene has its story stop, in order, with text', () {
    // Texts are keyed by scene id: a missing entry fails jigsawStory's
    // construction loudly (null-check), and a reordered catalog keeps
    // every text under its own painting. This smoke check pins the rest.
    expect(jigsawStory.stops.length, storyPuzzleCatalog.length);
    for (final (index, stop) in jigsawStory.stops.indexed) {
      expect(stop.image, same(storyPuzzleCatalog[index]));
      expect(stop.text, isNotEmpty);
    }
  });

  test('scene finishes fund the gift track (owner ruling)', () {
    // Gifts are the ONLY exclusion in galleryFirstFinishCount — a story
    // first finish earns a gift piece like any gallery painting. Pinned on
    // the real catalogs: flipping this would retroactively shift every
    // player's derived gift progress.
    final storyIds = {for (final scene in storyPuzzleCatalog) scene.id};
    expect(galleryFirstFinishCount(storyIds), storyPuzzleCatalog.length);
  });
}
