// The one file that touches the Firebase SDK — the convention that platform
// plugins never reach gameplay code directly (see GameSounds, SaveStore).

import 'package:firebase_analytics/firebase_analytics.dart';

import 'analytics.dart';

/// Forwards gameplay events to Firebase Analytics.
class FirebaseGameAnalytics implements Analytics {
  const FirebaseGameAnalytics(this._firebase);

  final FirebaseAnalytics _firebase;

  /// Fire-and-forget: losing an event is always better than surfacing an
  /// error in gameplay, so both sync and async failures are swallowed.
  void _log(String name, [Map<String, Object>? parameters]) {
    try {
      _firebase.logEvent(name: name, parameters: parameters).ignore();
    } catch (_) {}
  }

  // Firebase wants snake_case strings; the enum stays Dart-cased in the app.
  static String _wireSource(LaunchSource source) => switch (source) {
    LaunchSource.gallery => 'gallery',
    LaunchSource.daily => 'daily',
    LaunchSource.continueCard => 'continue_card',
    LaunchSource.myPuzzles => 'my_puzzles',
    LaunchSource.story => 'story',
    LaunchSource.nextChain => 'next_chain',
    LaunchSource.restart => 'restart',
  };

  @override
  void puzzleStarted({
    required String puzzleId,
    required int pieceCount,
    required LaunchSource source,
  }) => _log('puzzle_started', {
    'puzzle_id': puzzleId,
    'piece_count': pieceCount,
    'source': _wireSource(source),
  });

  @override
  void puzzleCompleted({required String puzzleId, required int pieceCount}) =>
      _log('puzzle_completed', {
        'puzzle_id': puzzleId,
        'piece_count': pieceCount,
      });

  @override
  void nextPuzzleAccepted({required String puzzleId}) =>
      _log('next_puzzle_accepted', {'puzzle_id': puzzleId});

  @override
  void edgesOnlyToggled({required bool enabled}) =>
      _log('edges_only_toggled', {'enabled': enabled ? 'on' : 'off'});

  @override
  void tidyUsed() => _log('tidy_used');

  @override
  void zoomInUsed() => _log('zoom_in_used');

  @override
  void boardColorChanged({required String colorId}) =>
      _log('board_color_changed', {'color_id': colorId});

  @override
  void storySceneUnlocked({required int scene}) =>
      _log('story_scene_unlocked', {'scene': scene});
}
