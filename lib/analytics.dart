// Analytics overview:
// 1. Analytics is the tiny interface gameplay code calls to report that
//    something happened (a start, a finish, a control used). The default
//    instance is silent, so tests and plain local runs send nothing.
// 2. FirebaseGameAnalytics (analytics_firebase.dart) forwards events to
//    Firebase; main() installs it once Firebase is ready.
// 3. Analytics is decoration: implementations must never throw, and
//    gameplay never waits on a log call.

/// Where a run was launched from, carried on the puzzle_started event so
/// the dashboard can split plays by entry point.
enum LaunchSource {
  gallery,
  daily,
  continueCard,
  myPuzzles,
  story,
  nextChain,
  restart,
}

/// Gameplay events worth counting. Implementations must never throw.
abstract class Analytics {
  /// The app-wide sink. main() swaps in the Firebase-backed one; tests that
  /// assert events install a recording fake and restore the silent default.
  static Analytics instance = const NoopAnalytics();

  /// A run was launched (fresh or resumed).
  void puzzleStarted({
    required String puzzleId,
    required int pieceCount,
    required LaunchSource source,
  });

  /// The last piece locked; the board is finished.
  void puzzleCompleted({required String puzzleId, required int pieceCount});

  /// The completion card's "Next puzzle" chained into another run.
  void nextPuzzleAccepted({required String puzzleId});

  /// The tray's Edges-only filter was switched.
  void edgesOnlyToggled({required bool enabled});

  /// The Tidy sweep returned the loose pieces to the tray.
  void tidyUsed();

  /// The Options menu's Zoom-in stepped the camera.
  void zoomInUsed();

  /// A board color swatch was picked.
  void boardColorChanged({required String colorId});

  /// A story parcel was torn open, revealing scene number [scene] (1-based).
  void storySceneUnlocked({required int scene});
}

/// The silent default: nothing leaves the device.
class NoopAnalytics implements Analytics {
  const NoopAnalytics();

  @override
  void puzzleStarted({
    required String puzzleId,
    required int pieceCount,
    required LaunchSource source,
  }) {}

  @override
  void puzzleCompleted({required String puzzleId, required int pieceCount}) {}

  @override
  void nextPuzzleAccepted({required String puzzleId}) {}

  @override
  void edgesOnlyToggled({required bool enabled}) {}

  @override
  void tidyUsed() {}

  @override
  void zoomInUsed() {}

  @override
  void boardColorChanged({required String colorId}) {}

  @override
  void storySceneUnlocked({required int scene}) {}
}
