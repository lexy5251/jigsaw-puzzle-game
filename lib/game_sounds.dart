// Sound overview:
// 1. GameSounds is the tiny interface gameplay code calls. The game treats
//    it as optional: passing none keeps everything silent (tests do this).
// 2. FlameAudioSounds plays the bundled WAVs from assets/audio/. All three
//    are synthesized sound effects.
// 3. Sound is decoration, so failures never interrupt gameplay: a muted
//    device, a simulator without audio, or a test environment without the
//    audio plugin just stays silent.

import 'dart:async';

import 'package:flame_audio/flame_audio.dart';

/// Gameplay sound cues. Implementations must never throw.
abstract class GameSounds {
  /// Loads the files into memory so the first cue plays without a delay.
  Future<void> preload();

  /// A piece was dropped on the board without locking.
  void playDrop();

  /// A piece locked into its correct spot.
  void playSnap();

  /// The last piece locked; the puzzle is finished.
  void playComplete();

  /// Releases playback resources and ignores any later cue requests.
  Future<void> dispose();
}

/// Plays the bundled synthesized WAVs via flame_audio.
class FlameAudioSounds implements GameSounds {
  FlameAudioSounds({
    AudioPlayer Function()? playerFactory,
    AudioCache? audioCache,
  }) : _drop = _SoundCue(
         'piece_drop.wav',
         0.4,
         playerFactory ?? AudioPlayer.new,
         audioCache ?? FlameAudio.audioCache,
       ),
       _snap = _SoundCue(
         'piece_snap.wav',
         0.55,
         playerFactory ?? AudioPlayer.new,
         audioCache ?? FlameAudio.audioCache,
       ),
       _complete = _SoundCue(
         'puzzle_complete.wav',
         0.8,
         playerFactory ?? AudioPlayer.new,
         audioCache ?? FlameAudio.audioCache,
       );

  final _SoundCue _drop;
  final _SoundCue _snap;
  final _SoundCue _complete;

  @override
  Future<void> preload() async {
    await Future.wait([_drop.preload(), _snap.preload(), _complete.preload()]);
  }

  // Dropping happens constantly — keep it quietest. The completion chime is
  // the reward moment and gets the most presence.
  @override
  void playDrop() => _drop.play();

  @override
  void playSnap() => _snap.play();

  @override
  void playComplete() => _complete.play();

  @override
  Future<void> dispose() async {
    await Future.wait([_drop.dispose(), _snap.dispose(), _complete.dispose()]);
  }
}

/// One reusable player per cue. Replaying a cue restarts it; different cues
/// can overlap (the last snap and the completion sound, for example).
class _SoundCue {
  _SoundCue(this.file, this.volume, this.playerFactory, this.audioCache);

  final String file;
  final double volume;
  final AudioPlayer Function() playerFactory;
  final AudioCache audioCache;
  AudioPlayer? _player;
  Future<void>? _preparing;
  Future<void> _pending = Future.value();
  Future<void>? _disposing;
  bool _disposed = false;

  Future<void> _prepare() => _preparing ??= _initialize();

  Future<void> _initialize() async {
    // Resolve the asset before allocating native playback resources. An absent
    // cache/path plugin or a missing file should leave the game silent.
    await audioCache.load(file);
    if (_disposed) return;
    final player = _player = playerFactory();
    player.audioCache = audioCache;
    // Short effects need no position polling, including on low-latency players
    // that do not emit completion events on Android.
    player.positionUpdater = null;
    await player.setAudioContext(
      AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
    );
    await player.setPlayerMode(PlayerMode.lowLatency);
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setVolume(volume);
    await player.setSource(AssetSource(file));
  }

  Future<void> preload() => _enqueue(_prepare);

  void play() {
    unawaited(
      _enqueue(() async {
        await _prepare();
        if (_disposed) return;
        await _player!.stop();
        if (!_disposed) await _player!.resume();
      }),
    );
  }

  // Serialize commands on each player so rapid taps cannot race with playback
  // or disposal. Failures remain local to the sound, never to gameplay.
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
