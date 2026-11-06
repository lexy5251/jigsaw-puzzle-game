import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/app_settings.dart';

import 'test_helpers.dart';

void main() {
  group('AppSettings json', () {
    test('round-trips both fields', () {
      const settings = AppSettings(
        effectsVolume: 0.3,
        ghostPreviewDefault: true,
      );
      expect(AppSettings.fromJsonString(settings.toJsonString()), settings);
    });

    test('malformed text falls back to defaults', () {
      expect(AppSettings.fromJsonString('not json'), const AppSettings());
      expect(AppSettings.fromJsonString('[1, 2]'), const AppSettings());
    });

    test('a bad field falls back alone, keeping the good one', () {
      final settings = AppSettings.fromJsonString(
        '{"effectsVolume": "loud", "ghostPreviewDefault": true}',
      );
      expect(settings.effectsVolume, 1);
      expect(settings.ghostPreviewDefault, isTrue);
    });

    test('out-of-range volume is clamped', () {
      expect(
        AppSettings.fromJsonString('{"effectsVolume": 3.5}').effectsVolume,
        1,
      );
      expect(
        AppSettings.fromJsonString('{"effectsVolume": -2}').effectsVolume,
        0,
      );
    });
  });

  group('SharedPreferencesAppSettingsStore', () {
    // The channel-backed mock is used for every test in this group: mixing
    // it with setMockInitialValues in one file would silently swap the
    // storage backend mid-suite.
    const store = SharedPreferencesAppSettingsStore();
    late MockSharedPreferences prefs;

    setUp(() {
      prefs = MockSharedPreferences()..install();
    });

    test('empty storage yields defaults', () async {
      expect(await store.load(), const AppSettings());
    });

    test('saves and loads back', () async {
      const settings = AppSettings(
        effectsVolume: 0.6,
        ghostPreviewDefault: true,
      );
      await store.save(settings);
      expect(prefs.storage, contains('flutter.settings.v1'));
      expect(await store.load(), settings);
    });

    test('a read error yields defaults instead of throwing', () async {
      prefs.readError = StateError('storage unavailable');
      expect(await store.load(), const AppSettings());
    });

    test('a failed write stays silent', () async {
      prefs.onWrite = (_) => false;
      await store.save(const AppSettings(effectsVolume: 0.2));
      expect(prefs.storage, isEmpty);
    });
  });
}
