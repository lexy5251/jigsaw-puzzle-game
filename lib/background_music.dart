// Background music overview:
// 1. BackgroundMusic is the tiny interface the shell drives; tests pass a
//    recording fake, and a null player keeps a screen silent.
// 2. FlameAudioMusic loops the bundled track from assets/audio/ for the
//    whole session; the Settings slider adjusts it live.
// 3. Music is decoration, so failures never interrupt the app: a missing
//    audio plugin, a blocked browser autoplay, or a test environment just
//    stays silent.

import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

/// The ambient loop. Implementations must never throw.
abstract class BackgroundMusic {
  /// Begins looping at [volume], the 0–1 slider value. Idempotent.
  Future<void> start({required double volume});

  /// Applies a new slider volume (0–1) to the loop immediately.
  void setVolume(double volume);

  /// Halts the loop while the app is out of the foreground.
  void pause();

  /// Continues the loop after [pause]; a no-op while already playing.
  void resume();

  /// Releases the player and ignores any later requests.
  Future<void> dispose();
}

/// Loops the bundled music track via flame_audio.
class FlameAudioMusic implements BackgroundMusic {
  FlameAudioMusic({
    AudioPlayer Function()? playerFactory,
    AudioCache? audioCache,
  }) : _playerFactory = playerFactory ?? AudioPlayer.new,
       _audioCache = audioCache ?? FlameAudio.audioCache;

  static const _file = 'background_music.mp3';

  /// A full slider still sits under the completion chime (0.8): the music
  /// is a bed behind the effect cues, never the foreground.
  static const _baseVolume = 0.6;

  final AudioPlayer Function() _playerFactory;
  final AudioCache _audioCache;

  AudioPlayer? _player;
  double _volume = 1;
  Future<void>? _starting;
  Future<void> _pending = Future.value();
  Future<void>? _disposing;
  bool _disposed = false;

  @override
  Future<void> start({required double volume}) {
    _volume = volume.clamp(0, 1);
    return _enqueue(() => _starting ??= _initialize());
  }

  Future<void> _initialize() async {
    // Resolve the asset before allocating native playback resources. An
    // absent cache/path plugin or a missing file should leave the app
    // silent, exactly like the effect cues.
    await _audioCache.load(_file);
    if (_disposed) return;
    final player = _player = _playerFactory();
    player.audioCache = _audioCache;
    // A looping bed needs no position polling; skipping it avoids a
    // periodic timer for events nobody listens to.
    player.positionUpdater = null;
    await player.setAudioContext(
      AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
    );
    // mediaPlayer, not lowLatency: the low-latency path is built for short
    // clips and cannot loop a full-length track reliably.
    await player.setPlayerMode(PlayerMode.mediaPlayer);
    await player.setReleaseMode(ReleaseMode.loop);
    await player.setVolume(_volume * _baseVolume);
    await player.setSource(AssetSource(_file));
    // Re-check: a disposal that raced the awaits above must win — the
    // released player may never start playing.
    if (_disposed) return;
    await player.resume();
  }

  @override
  void setVolume(double volume) {
    // Record the target before queueing, so a slider drag that races a slow
    // start still lands on the final value once both commands have run.
    _volume = volume.clamp(0, 1);
    unawaited(
      _enqueue(() async => _player?.setVolume(_volume * _baseVolume)),
    );
  }

  @override
  void pause() => unawaited(_enqueue(() async => _player?.pause()));

  @override
  void resume() => unawaited(_enqueue(() async => _player?.resume()));

  /// The tail of the command queue; tests await it to observe the effect
  /// of fire-and-forget calls. Disposal drops still-queued commands.
  @visibleForTesting
  Future<void> get pending => _pending;

  // Serialize commands on the player so slider drags, lifecycle changes,
  // and disposal cannot race. Failures stay local to the music.
  Future<void> _enqueue(Future<void> Function() action) {
    return _pending = _pending.then((_) async {
      if (_disposed) return;
      try {
        await action();
      } on Object {
        // Stay silent.
      }
    });
  }

  @override
  Future<void> dispose() {
    _disposed = true;
    return _disposing ??= _releasePlayer();
  }

  Future<void> _releasePlayer() async {
    await _pending;
    final player = _player;
    _player = null;
    if (player != null) {
      try {
        await player.dispose();
      } on Object {
        // Missing or unavailable audio plugins must not interrupt teardown.
      }
    }
  }
}
