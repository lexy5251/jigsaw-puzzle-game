import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  const store = SharedPreferencesCompletionStore();
  const key = 'done.test.6x4';
  late MockSharedPreferences prefs;

  setUp(() {
    prefs = MockSharedPreferences()..install();
    // Completion records are permanent ("never deleted"); any remove from
    // this store is a regression and must fail the suite.
    prefs.allowRemoves = false;
  });

  test('reports success and increments the stored completion count', () async {
    expect(await store.markCompleted(key), isTrue);
    expect(await store.markCompleted(key), isTrue);
    SharedPreferences.resetStatic();
    expect((await store.record(key))!.count, 2);
  });

  for (final throwsError in [false, true]) {
    test(
      'a ${throwsError ? 'throwing' : 'rejected'} write can be retried without counting twice',
      () async {
        expect(await store.markCompleted(key), isTrue);
        final previous = prefs.storage['flutter.$key'];
        prefs.onWrite = (_) {
          if (throwsError) {
            throw PlatformException(code: 'write_failed');
          }
          return false;
        };

        expect(await store.markCompleted(key), isFalse);
        expect(prefs.storage['flutter.$key'], previous);
        expect((await store.record(key))!.count, 1);

        prefs.onWrite = null;
        expect(await store.markCompleted(key), isTrue);
        SharedPreferences.resetStatic();
        expect((await store.record(key))!.count, 2);
      },
    );
  }

  test(
    'a read failure does not overwrite the existing completion history',
    () async {
      expect(await store.markCompleted(key), isTrue);
      final previous = prefs.storage['flutter.$key'];
      prefs.readError = PlatformException(code: 'read_failed');

      expect(await store.markCompleted(key), isFalse);
      expect(prefs.writes, 1);
      expect(prefs.storage['flutter.$key'], previous);
    },
  );
}
