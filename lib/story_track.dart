// Story track overview (owner's design, 2026-11-14):
// 1. One story in the MVP: eight scenes, each a puzzle, read in order.
//    Scene N+1 opens only when scene N is finished (any grid size, first
//    finish). Locked scenes show no art and no title — the tale stays a
//    surprise until pieced together.
// 2. Progress is DERIVED from the permanent completion records: the
//    longest finished prefix of the scene list. No counter is stored, so
//    progress can never drift, and finishes recorded before this feature
//    count at once.
// 3. Scene finishes also fund the gift track like any gallery painting
//    (owner ruling, 2026-11-14): 'story' is not the bonus category, so
//    galleryFirstFinishCount counts them with no extra code — pinned by
//    test so the rule cannot silently flip.
// 4. A holiday story later is new data — a Story plus catalog entries —
//    not a new screen.

import 'puzzle_catalog.dart';

/// A story told through puzzles: an ordered list of scenes.
class Story {
  const Story({required this.id, required this.title, required this.stops});

  final String id;
  final String title;

  /// Reading order — frozen once shipped, like [storyPuzzleCatalog].
  final List<StoryStop> stops;
}

/// One scene: its painting (whose title is the scene title), the lines it
/// reveals when finished, and the era tag it wears on the trail.
class StoryStop {
  const StoryStop({required this.image, required this.text, required this.era});

  final PuzzleImage image;
  final String text;

  /// Short era label ("1760s" … "TODAY") shown on the trail stop. Visible
  /// even on locked scenes — a year spoils nothing, and together the tags
  /// read as a timeline.
  final String era;
}

/// The scene texts, keyed by scene id so a catalog edit can never slide a
/// text under the wrong painting. [jigsawStory]'s lookup throws at first
/// access when an id has no entry — loudly, in every test run.
const _jigsawSceneTexts = <String, String>{
  'story-mapmakers-shop':
      'London, the 1760s. In a little shop of maps and engraving tools, a '
      'young mapmaker named John Spilsbury has an idea.',
  'story-first-cut':
      'Around 1766 he glues a map onto a thin sheet of mahogany and cuts '
      'it apart along the borders — the first jigsaw puzzle is born.',
  'story-learning-the-world':
      "He sells his 'dissected maps' as geography lessons: children piece "
      'Europe together country by country, and learn the world by hand.',
  'story-pictures-join-in':
      'Through the 1800s the maps make room for pictures — fairy tales, '
      'farms and ships — each one still cut from wood by hand.',
  'story-swooping-saw':
      'Late in the century a foot-pedaled fretsaw — cousin to the jig saw '
      "— cuts swooping, curly pieces. The name 'jigsaw' sticks forever.",
  'story-cardboard-boom':
      'In the 1930s, puzzles stamped from cheap cardboard sweep through '
      'the Great Depression — millions a week, traded, rented and shared.',
  'story-boxes-on-every-shelf':
      'Interlocking pieces, five hundred and a thousand to a box: the '
      'jigsaw settles in as a quiet evening friend around the world.',
  'story-your-table-today':
      'More than 250 years after that first cut map, the puzzle reaches '
      'your table — one piece at a time, just like always.',
};

/// Era tags, keyed like the texts so a catalog edit can never slide a tag
/// under the wrong scene.
const _jigsawSceneEras = <String, String>{
  'story-mapmakers-shop': '1760s',
  'story-first-cut': '1766',
  'story-learning-the-world': '1770s',
  'story-pictures-join-in': '1800s',
  'story-swooping-saw': '1880s',
  'story-cardboard-boom': '1930s',
  'story-boxes-on-every-shelf': '1950s',
  'story-your-table-today': 'TODAY',
};

/// The MVP story. Final, not const: stops borrow their images from the
/// catalog list so the two can never disagree.
final jigsawStory = Story(
  id: 'how-the-jigsaw-was-born',
  title: 'How the Jigsaw Was Born',
  stops: [
    for (final image in storyPuzzleCatalog)
      StoryStop(
        image: image,
        text: _jigsawSceneTexts[image.id]!,
        era: _jigsawSceneEras[image.id]!,
      ),
  ],
);

/// Where the reader stands, derived by [storyStateFor].
class StoryState {
  const StoryState({required this.story, required this.finishedStops});

  final Story story;

  /// Scenes read so far — the longest finished prefix of the stop list.
  /// A finish further down the list (impossible in the app, conceivable in
  /// storage) does not skip the gate.
  final int finishedStops;

  int get totalStops => story.stops.length;

  bool get complete => finishedStops == totalStops;

  /// The one scene open to play now; null once the story is complete.
  StoryStop? get nextStop => complete ? null : story.stops[finishedStops];
}

/// Folds a completion snapshot (see completedImageIds in bonus_track.dart)
/// into story progress.
StoryState storyStateFor(Set<String> completedIds, {Story? story}) {
  final resolved = story ?? jigsawStory;
  return StoryState(
    story: resolved,
    finishedStops: _finishedPrefixLength(
      completedIds,
      resolved.stops.map((stop) => stop.image.id),
    ),
  );
}

/// The one scene of [scenes] (in reading order) open to play now, or null
/// when every scene is read. This is the same prefix gate [storyStateFor]
/// renders — the completion chain derives its "Next puzzle" offer from it,
/// so the chain can never offer a scene the Story page still shows wrapped.
PuzzleImage? nextSceneToRead(
  Set<String> completedIds,
  List<PuzzleImage> scenes,
) {
  final finished = _finishedPrefixLength(
    completedIds,
    scenes.map((scene) => scene.id),
  );
  return finished == scenes.length ? null : scenes[finished];
}

/// The longest finished prefix of [sceneIds] — the single unlock rule. A
/// finish further down the list (impossible in the app, conceivable in
/// storage) does not skip the gate.
int _finishedPrefixLength(Set<String> completedIds, Iterable<String> sceneIds) {
  var finished = 0;
  for (final id in sceneIds) {
    if (!completedIds.contains(id)) {
      break;
    }
    finished++;
  }
  return finished;
}
