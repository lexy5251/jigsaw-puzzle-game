// Haptics overview:
// 1. GameHaptics is the tiny interface gameplay code calls. The game treats
//    it as optional: passing none keeps the device still (the player turned
//    vibration off, or a test).
// 2. SystemGameHaptics forwards to the platform haptic engine.
// 3. Haptics are decoration, so failures never interrupt gameplay: a device
//    without a vibration motor just stays still.

import 'package:flutter/services.dart';

/// Gameplay haptic cues. Implementations must never throw.
abstract class GameHaptics {
  /// A piece locked into its correct spot.
  void snap();

  /// The last piece locked; the puzzle is finished.
  void complete();
}

/// Forwards cues to the device's haptic engine.
class SystemGameHaptics implements GameHaptics {
  const SystemGameHaptics();

  // The snap happens constantly — keep it light. Completion is the reward
  // moment and gets the heavy pulse.
  @override
  void snap() => HapticFeedback.lightImpact().ignore();

  @override
  void complete() => HapticFeedback.heavyImpact().ignore();
}
