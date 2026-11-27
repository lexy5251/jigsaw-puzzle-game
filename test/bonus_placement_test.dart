// The hand-placed bonus record: a whole-state JSON overwrite whose
// failures always degrade to "place it again" — corrupt reads fall back to
// nothing placed, and a refused write repairs the preferences cache so a
// later load never shows unpersisted progress.

import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/bonus_placement.dart';

import 'test_helpers.dart';

void main() {
  const store = SharedPreferencesBonusPlacementStore();

  // One mock for the whole file: mixing it with setMockInitialValues in a
  // single suite would leave a store override that bypasses the channel.
  late MockSharedPreferences prefs;

  setUp(() {
    prefs = MockSharedPreferences()..install();
  });

  test('round-trips boards and cells', () async {
    final saved = await store.save(
      const BonusPlacement(completedBoards: 1, placedCells: {19, 0, 7}),
    );
    final loaded = await store.load();

    expect(saved, isTrue);
    expect(
      prefs.storage['flutter.bonus.placed'],
      '{"boards":1,"cells":[0,7,19]}',
    );
    expect(loaded.completedBoards, 1);
    expect(loaded.placedCells, {0, 7, 19});
    expect(loaded.placedTotal, 28);
  });

  test('missing or corrupt storage reads as nothing placed', () async {
    for (final stored in [
      null,
      '{broken',
      '[]',
      '{"boards":"two","cells":[1]}',
      '{"boards":-1,"cells":[1]}',
      '{"boards":0,"cells":"all"}',
    ]) {
      prefs = MockSharedPreferences()..install();
      if (stored != null) {
        prefs.storage['flutter.bonus.placed'] = stored;
      }

      final loaded = await store.load();

      expect(loaded.completedBoards, 0, reason: 'stored: $stored');
      expect(loaded.placedCells, isEmpty, reason: 'stored: $stored');
    }
  });

  test('out-of-range cells are dropped, valid ones kept', () async {
    prefs.storage['flutter.bonus.placed'] = '{"boards":0,"cells":[-1,3,25,"x",24]}';

    final loaded = await store.load();

    expect(loaded.placedCells, {3, 24});
  });

  test('a refused write reports false and repairs the cache', () async {
    prefs.storage['flutter.bonus.placed'] = '{"boards":0,"cells":[2]}';
    prefs.onWrite = (key) => false;

    final saved = await store.save(
      const BonusPlacement(placedCells: {2, 9}),
    );
    final loaded = await store.load();

    expect(saved, isFalse);
    // The load must show what storage holds, not the refused value.
    expect(loaded.placedCells, {2});
    expect(prefs.storage['flutter.bonus.placed'], '{"boards":0,"cells":[2]}');
  });
}
