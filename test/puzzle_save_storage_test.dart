import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const store = SharedPreferencesSaveStore();
  const key = 'save.test.2x2';
  const state = PuzzleSaveState(
    trayPieceIndexes: [0, 1, 2, 3],
    lockedPieceIndexes: [],
    loosePiecePositions: {},
  );
  final messages = <String>[];
  late DebugPrintCallback originalDebugPrint;

  setUp(() {
    SharedPreferences.resetStatic();
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
    messenger.setMockMethodCallHandler(channel, null);
    SharedPreferences.resetStatic();
  });

  test('storage exceptions are logged without escaping to gameplay', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'storage_unavailable');
    });

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
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') {
        return <String, Object>{};
      }
      return false;
    });

    await expectLater(store.save(key, state), completes);
    await expectLater(store.delete(key), completes);

    expect(messages, hasLength(2));
    expect(messages[0], contains('save failed for "$key"'));
    expect(messages[1], contains('delete failed for "$key"'));
    expect(messages, everyElement(contains('Storage returned false.')));
  });

  test('missing saves are quiet and malformed saves are logged', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      return <String, Object>{'flutter.$key': 'invalid JSON'};
    });

    expect(await store.load('save.missing.2x2'), isNull);
    expect(messages, isEmpty);

    expect(await store.load(key), isNull);
    expect(messages, hasLength(1));
    expect(messages.single, contains('load failed for "$key"'));
    expect(messages.single, contains('Saved data is malformed.'));
  });
}
