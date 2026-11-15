import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/background_music.dart';

class _FakeCache implements AudioCache {
  _FakeCache({this.fail = false});

  final bool fail;

  @override
  Future<Uri> load(String file) async {
    if (fail) throw StateError('Asset cache unavailable');
    return Uri.file(file);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlayer implements AudioPlayer {
  _FakePlayer({this.prepareGate, this.failPreparation = false});

  /// Held inside setSource, after [prepared] completes, to freeze a start
  /// mid-flight.
  final Completer<void>? prepareGate;
  final bool failPreparation;
  final prepared = Completer<void>();
  String? file;
  PlayerMode? configuredMode;
  ReleaseMode? configuredRelease;
  final volumes = <double>[];
  int resumes = 0;
  int pauses = 0;
  int disposals = 0;
  int commandsAfterDisposal = 0;

  void _command() {
    if (disposals > 0) commandsAfterDisposal++;
  }

  @override
  set audioCache(AudioCache value) {}

  @override
  set positionUpdater(PositionUpdater? value) {}

  @override
  Future<void> setAudioContext(AudioContext context) async {}

  @override
  Future<void> setPlayerMode(PlayerMode value) async => configuredMode = value;

  @override
  Future<void> setReleaseMode(ReleaseMode value) async =>
      configuredRelease = value;

  @override
  Future<void> setVolume(double volume) async {
    _command();
    volumes.add(volume);
  }

  @override
  Future<void> setSource(Source source) async {
    file = (source as AssetSource).path;
    prepared.complete();
    await prepareGate?.future;
    if (failPreparation) throw StateError('Audio unavailable');
  }

  @override
  Future<void> pause() async {
    _command();
    pauses++;
  }

  @override
  Future<void> resume() async {
    _command();
    resumes++;
  }

  @override
  Future<void> dispose() async => disposals++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('start loops the track at the slider volume scaled to bed level', () async {
    final player = _FakePlayer();
    final music = FlameAudioMusic(
      playerFactory: () => player,
      audioCache: _FakeCache(),
    );
    await music.start(volume: 0.5);

    expect(player.file, 'background_music.mp3');
    expect(player.configuredMode, PlayerMode.mediaPlayer);
    expect(player.configuredRelease, ReleaseMode.loop);
    expect(player.volumes, [0.5 * 0.6]);
    expect(player.resumes, 1);
    await music.dispose();
  });

  test('start is idempotent: one player, one playback', () async {
    var created = 0;
    final player = _FakePlayer();
    final music = FlameAudioMusic(
      playerFactory: () {
        created++;
        return player;
      },
      audioCache: _FakeCache(),
    );
    await music.start(volume: 1);
    await music.start(volume: 1);

    expect(created, 1);
    expect(player.resumes, 1);
    await music.dispose();
  });

  test('a cache failure stays silent and never creates a player', () async {
    var created = 0;
    final music = FlameAudioMusic(
      playerFactory: () {
        created++;
        return _FakePlayer();
      },
      audioCache: _FakeCache(fail: true),
    );
    await music.start(volume: 1);
    music.setVolume(0.5);
    music.pause();
    music.resume();
    await music.dispose();

    expect(created, 0);
  });

  test('setVolume adjusts the playing loop live and clamps', () async {
    final player = _FakePlayer();
    final music = FlameAudioMusic(
      playerFactory: () => player,
      audioCache: _FakeCache(),
    );
    await music.start(volume: 1);
    // Flush between calls: back-to-back drags coalesce to the latest
    // target by design, so only the final value would reach the player.
    music.setVolume(0.5);
    await music.pending;
    music.setVolume(2);
    await music.pending;
    music.setVolume(-1);
    await music.pending;

    expect(player.volumes, [0.6, 0.5 * 0.6, 0.6, 0]);
    await music.dispose();
  });

  test('a drag that races a slow start lands on the final volume', () async {
    final gate = Completer<void>();
    final player = _FakePlayer(prepareGate: gate);
    final music = FlameAudioMusic(
      playerFactory: () => player,
      audioCache: _FakeCache(),
    );
    final starting = music.start(volume: 1);
    // The boot volume is applied, then the start freezes inside setSource;
    // the user drags the slider while it is stuck.
    await player.prepared.future;
    music.setVolume(0.2);
    gate.complete();
    await starting;
    await music.pending;

    expect(player.volumes, [0.6, 0.2 * 0.6]);
    await music.dispose();
  });

  test('pause and resume forward to the player', () async {
    final player = _FakePlayer();
    final music = FlameAudioMusic(
      playerFactory: () => player,
      audioCache: _FakeCache(),
    );
    await music.start(volume: 1);
    music.pause();
    music.resume();
    await music.pending;

    expect(player.pauses, 1);
    expect(player.resumes, 2);
    await music.dispose();
  });

  test('a playback failure stays silent and later commands still run', () async {
    final player = _FakePlayer(failPreparation: true);
    final music = FlameAudioMusic(
      playerFactory: () => player,
      audioCache: _FakeCache(),
    );
    await music.start(volume: 1);
    expect(player.resumes, 0);

    music.resume();
    await music.pending;
    expect(player.resumes, 1);
    await music.dispose();
  });

  test('disposal mid-start prevents playback and later calls', () async {
    final gate = Completer<void>();
    final player = _FakePlayer(prepareGate: gate);
    final music = FlameAudioMusic(
      playerFactory: () => player,
      audioCache: _FakeCache(),
    );
    final starting = music.start(volume: 1);
    await player.prepared.future;
    final disposing = music.dispose();
    gate.complete();
    await Future.wait([starting, disposing]);

    music.resume();
    music.setVolume(0.5);
    await music.dispose();

    expect(player.resumes, 0);
    expect(player.disposals, 1);
    expect(player.commandsAfterDisposal, 0);
  });

  test('start after dispose is ignored', () async {
    var created = 0;
    final music = FlameAudioMusic(
      playerFactory: () {
        created++;
        return _FakePlayer();
      },
      audioCache: _FakeCache(),
    );
    await music.dispose();
    await music.start(volume: 1);

    expect(created, 0);
  });
}
