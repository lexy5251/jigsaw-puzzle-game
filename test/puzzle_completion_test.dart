import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';

/// Completion records: the permanent "finished this puzzle" facts.
void main() {
  test('a record round-trips through JSON', () {
    final record = CompletionRecord(
      count: 3,
      lastCompletedAt: DateTime(2026, 10, 19, 12, 30),
    );

    final restored = CompletionRecord.fromJsonString(record.toJsonString())!;

    expect(restored.count, 3);
    expect(restored.lastCompletedAt, DateTime(2026, 10, 19, 12, 30));
  });

  test('malformed data reads as "never completed"', () {
    expect(CompletionRecord.fromJsonString('not json'), isNull);
    expect(CompletionRecord.fromJsonString('{}'), isNull);
    expect(CompletionRecord.fromJsonString('{"count":"x","last":1}'), isNull);
  });

  test('puzzleCompletionKey is unique per image and grid size', () {
    final a = puzzleCompletionKey(imageId: 'cat', columns: 6, rows: 4);
    final b = puzzleCompletionKey(imageId: 'cat', columns: 10, rows: 6);
    final c = puzzleCompletionKey(imageId: 'dog', columns: 6, rows: 4);
    expect({a, b, c}, hasLength(3));
  });

  test('marking twice increments the count and updates the date', () async {
    final store = InMemoryCompletionStore();
    const key = 'done.test.6x4';

    expect(await store.isCompleted(key), isFalse);
    expect(await store.record(key), isNull);

    await store.markCompleted(key, completedAt: DateTime(2026, 10, 18));
    await store.markCompleted(key, completedAt: DateTime(2026, 10, 19));

    expect(await store.isCompleted(key), isTrue);
    final record = (await store.record(key))!;
    expect(record.count, 2);
    expect(record.lastCompletedAt, DateTime(2026, 10, 19));
  });
}
