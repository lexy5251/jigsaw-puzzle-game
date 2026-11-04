import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/daily_streak.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  const store = SharedPreferencesDailyStreakStore();
  const prefsKey = 'flutter.daily.days';
  late MockSharedPreferences prefs;

  setUp(() {
    prefs = MockSharedPreferences()..install();
  });

  test('stores days and reads them back after a cold start', () async {
    expect(await store.markCompleted('2026-11-01'), isTrue);
    expect(await store.markCompleted('2026-11-02'), isTrue);
    SharedPreferences.resetStatic();
    expect(await store.completedDays(), {'2026-11-01', '2026-11-02'});
  });

  test('marking the same day twice is a successful no-op', () async {
    expect(await store.markCompleted('2026-11-02'), isTrue);
    final writesAfterFirst = prefs.writes;
    expect(await store.markCompleted('2026-11-02'), isTrue);
    expect(prefs.writes, writesAfterFirst);
    expect(await store.completedDays(), {'2026-11-02'});
  });

  test('malformed stored data reads as no days', () async {
    prefs.storage[prefsKey] = 'not json';
    expect(await store.completedDays(), isEmpty);
    SharedPreferences.resetStatic();
    prefs.storage[prefsKey] = '{"not": "a list"}';
    expect(await store.completedDays(), isEmpty);
  });

  test('non-string list entries are ignored', () async {
    prefs.storage[prefsKey] = '[1, "2026-11-02", null]';
    expect(await store.completedDays(), {'2026-11-02'});
  });

  test('reports failure when the write is rejected', () async {
    prefs.onWrite = (_) => false;
    expect(await store.markCompleted('2026-11-02'), isFalse);
  });

  test('reports failure when the write throws', () async {
    prefs.onWrite = (_) => throw PlatformException(code: 'write_failed');
    expect(await store.markCompleted('2026-11-02'), isFalse);
  });

  test('a write merges days stored outside this cache', () async {
    expect(await store.markCompleted('2026-11-01'), isTrue);
    // Another cache over the same storage (a second tab on web) persisted
    // a day this runtime has not seen; the write must not clobber it.
    prefs.storage[prefsKey] = '["2026-11-01", "2026-11-02"]';

    expect(await store.markCompleted('2026-11-03'), isTrue);
    expect(await store.completedDays(), {
      '2026-11-01',
      '2026-11-02',
      '2026-11-03',
    });
  });

  test('a wrong-typed stored value is not destroyed by a failed read', () async {
    prefs.storage[prefsKey] = 12345; // getString throws before any write.

    expect(await store.markCompleted('2026-11-02'), isFalse);
    expect(prefs.storage[prefsKey], 12345);
  });

  test('a failed write leaves no ghost day in the live cache', () async {
    await store.completedDays(); // Warm the preferences singleton first.
    prefs.onWrite = (_) => false;
    // Reads fail too: the repair must not depend on re-reading storage.
    prefs.readError = PlatformException(code: 'read_failed');

    expect(await store.markCompleted('2026-11-02'), isFalse);
    expect(await store.completedDays(), isEmpty);
  });

  test('reads as empty when storage is unavailable', () async {
    prefs.readError = PlatformException(code: 'read_failed');
    expect(await store.completedDays(), isEmpty);
  });

  test('the in-memory fake matches the contract', () async {
    final fake = InMemoryDailyStreakStore();
    expect(await fake.completedDays(), isEmpty);
    expect(await fake.markCompleted('2026-11-02'), isTrue);
    expect(await fake.markCompleted('2026-11-02'), isTrue);
    expect(await fake.completedDays(), {'2026-11-02'});
  });
}
