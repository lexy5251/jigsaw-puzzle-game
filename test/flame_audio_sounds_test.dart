import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/game_sounds.dart';

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
  _FakePlayer({
    this.prepareGate,
    this.failPreparation = false,
    this.failDisposal = false,
  });

  final Completer<void>? prepareGate;
  final bool failPreparation;
  final bool failDisposal;
  final prepared = Completer<void>();
  String? file;
  double? configuredVolume;
  int resumes = 0;
  int disposals = 0;
  int commandsAfterDisposal = 0;

  @override
  set audioCache(AudioCache value) {}

  @override
  set positionUpdater(PositionUpdater? value) {}

  @override
  Future<void> setAudioContext(AudioContext context) async {}

  @override
  Future<void> setPlayerMode(PlayerMode mode) async {}

  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {}

  @override
  Future<void> setVolume(double volume) async => configuredVolume = volume;

  @override
  Future<void> setSource(Source source) async {
    file = (source as AssetSource).path;
    prepared.complete();
    await prepareGate?.future;
    if (failPreparation) throw StateError('Audio unavailable');
  }

  @override
  Future<void> stop() async {
    if (disposals > 0) commandsAfterDisposal++;
  }

  @override
  Future<void> resume() async {
    resumes++;
    if (disposals > 0) commandsAfterDisposal++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    if (failDisposal) throw StateError('Audio plugin closed');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('cache failures stay silent without creating players', () async {
    var playersCreated = 0;
    final sounds = FlameAudioSounds(
      audioCache: _FakeCache(fail: true),
      playerFactory: () {
        playersCreated++;
        return _FakePlayer();
      },
    );
    await sounds.preload();
    sounds.playDrop();
    sounds.playSnap();
    sounds.playComplete();
    await sounds.preload();
    await sounds.dispose();
    expect(playersCreated, 0);
  });

  test('repeated cues reuse three players and preserve cue volumes', () async {
    final players = <_FakePlayer>[];
    final sounds = FlameAudioSounds(
      audioCache: _FakeCache(),
      playerFactory: () {
        final player = _FakePlayer();
        players.add(player);
        return player;
      },
    );
    addTearDown(sounds.dispose);
    await sounds.preload();

    for (var i = 0; i < 12; i++) {
      sounds.playDrop();
      sounds.playSnap();
      sounds.playComplete();
    }
    // Wait for each player's already queued playback requests.
    await sounds.preload();
    expect(players.length, 3);
    expect(
      {for (final p in players) p.file: p.configuredVolume},
      {
        'piece_drop.wav': 0.4,
        'piece_snap.wav': 0.55,
        'puzzle_complete.wav': 0.8,
      },
    );
    expect(players.map((p) => p.resumes), everyElement(12));

    await sounds.dispose();
    expect(players.map((p) => p.disposals), everyElement(1));
    sounds.playDrop();
    sounds.playSnap();
    sounds.playComplete();
    await sounds.preload();
    await sounds.dispose();
    expect(players.length, 3);
    expect(players.map((p) => p.resumes), everyElement(12));
    expect(players.map((p) => p.disposals), everyElement(1));
    expect(players.map((p) => p.commandsAfterDisposal), everyElement(0));
  });

  test(
    'disposal waits for pending preparation and prevents queued playback',
    () async {
      final gate = Completer<void>();
      final players = List.generate(3, (_) => _FakePlayer(prepareGate: gate));
      var nextPlayer = 0;
      final sounds = FlameAudioSounds(
        playerFactory: () => players[nextPlayer++],
        audioCache: _FakeCache(),
      );
      final loading = sounds.preload();
      await Future.wait(players.map((p) => p.prepared.future));
      sounds.playSnap();
      final disposing = sounds.dispose();
      gate.complete();
      await Future.wait([loading, disposing]);

      expect(players.map((p) => p.resumes), everyElement(0));
      expect(players.map((p) => p.disposals), everyElement(1));
      expect(players.map((p) => p.commandsAfterDisposal), everyElement(0));
    },
  );

  test(
    'failed preparation and disposal remain silent and release other players',
    () async {
      final players = [
        _FakePlayer(failPreparation: true, failDisposal: true),
        _FakePlayer(),
        _FakePlayer(),
      ];
      var nextPlayer = 0;
      final sounds = FlameAudioSounds(
        playerFactory: () => players[nextPlayer++],
        audioCache: _FakeCache(),
      );
      await sounds.preload();
      sounds.playDrop();
      sounds.playSnap();
      sounds.playComplete();
      await sounds.preload();
      expect(players.map((p) => p.resumes), [0, 1, 1]);
      await sounds.dispose();
      expect(players.map((p) => p.disposals), everyElement(1));
    },
  );
}
