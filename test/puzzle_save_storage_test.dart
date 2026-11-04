import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';

import 'test_helpers.dart';

void main() {
  const store = SharedPreferencesSaveStore();
  const key = 'save.test.2x2';
  const state = PuzzleSaveState(
    trayPieceIndexes: [0, 1, 2, 3],
    lockedPieceIndexes: [],
    loosePiecePositions: {},
  );
  final messages = <String>[];
  late DebugPrintCallback originalDebugPrint;
  late MockSharedPreferences prefs;

  setUp(() {
    prefs = MockSharedPreferences()..install();
    messages.clear();
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        messages.add(message);
      }
    };
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
  });

  test('storage exceptions are logged without escaping to gameplay', () async {
    prefs.readError = PlatformException(code: 'storage_unavailable');

    expect(await store.load(key), isNull);
    await expectLater(store.save(key, state), completes);
    await expectLater(store.delete(key), completes);
    expect(await store.exists(key), isFalse);

    expect(messages, hasLength(4));
    for (final operation in ['load', 'save', 'delete', 'check existence']) {
      expect(
        messages,
        contains(
          allOf(
            contains('$operation failed'),
            contains(key),
            contains('storage_unavailable'),
          ),
        ),
      );
    }
  });

  test('rejected writes and deletions are logged without throwing', () async {
    prefs.onWrite = (_) => false;

    await expectLater(store.save(key, state), completes);
    await expectLater(store.delete(key), completes);

    expect(messages, hasLength(2));
    expect(messages[0], contains('save failed for "$key"'));
    expect(messages[1], contains('delete failed for "$key"'));
    expect(messages, everyElement(contains('Storage returned false.')));
  });

  test('missing saves are quiet and malformed saves are logged', () async {
    prefs.storage['flutter.$key'] = 'invalid JSON';

    expect(await store.load('save.missing.2x2'), isNull);
    expect(messages, isEmpty);

    expect(await store.load(key), isNull);
    expect(messages, hasLength(1));
    expect(messages.single, contains('load failed for "$key"'));
    expect(messages.single, contains('Saved data is malformed.'));
  });
}
