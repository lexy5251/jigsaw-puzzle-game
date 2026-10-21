import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const store = SharedPreferencesCompletionStore();
  const key = 'done.test.6x4';
  late Map<String, Object> storage;
  var rejectWrite = false;
  var throwOnWrite = false;
  var throwOnRead = false;
  var writes = 0;

  setUp(() {
    SharedPreferences.resetStatic();
    storage = {};
    rejectWrite = false;
    throwOnWrite = false;
    throwOnRead = false;
    writes = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') {
        if (throwOnRead) {
          throw PlatformException(code: 'read_failed');
        }
        return Map<String, Object>.of(storage);
      }
      if (call.method == 'setString') {
        writes++;
        if (throwOnWrite) {
          throw PlatformException(code: 'write_failed');
        }
        if (rejectWrite) {
          return false;
        }
        final arguments = call.arguments as Map;
        storage[arguments['key'] as String] = arguments['value'] as String;
        return true;
      }
      throw StateError('Unexpected storage call: ${call.method}');
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    SharedPreferences.resetStatic();
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
        final previous = storage['flutter.$key'];
        rejectWrite = !throwsError;
        throwOnWrite = throwsError;

        expect(await store.markCompleted(key), isFalse);
        expect(storage['flutter.$key'], previous);
        expect((await store.record(key))!.count, 1);

        rejectWrite = false;
        throwOnWrite = false;
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
      final previous = storage['flutter.$key'];
      throwOnRead = true;

      expect(await store.markCompleted(key), isFalse);
      expect(writes, 1);
      expect(storage['flutter.$key'], previous);
    },
  );
}
