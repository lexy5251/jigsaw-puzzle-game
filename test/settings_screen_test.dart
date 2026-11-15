import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/app_settings.dart';
import 'package:jigsaw_puzzle/background_music.dart';
import 'package:jigsaw_puzzle/home_shell.dart';
import 'package:jigsaw_puzzle/settings_screen.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

Future<InMemorySettingsStore> pumpSettings(
  WidgetTester tester, {
  AppSettings initial = const AppSettings(),
  BackgroundMusic? music,
}) async {
  final store = InMemorySettingsStore()..settings = initial;
  await tester.pumpWidget(
    MaterialApp(
      theme: studioTheme(),
      home: SettingsScreen(store: store, music: music),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

/// The card holds two sliders; the semantics identifiers tell them apart.
Finder sliderOf(String identifier) => find.descendant(
  of: find.bySemanticsIdentifier(identifier),
  matching: find.byType(Slider),
);

void main() {
  testWidgets('shows the stored settings', (tester) async {
    await pumpSettings(
      tester,
      initial: const AppSettings(
        effectsVolume: 0.4,
        musicVolume: 0.7,
        ghostPreviewDefault: true,
      ),
    );

    expect(tester.widget<Slider>(sliderOf('settings-effects-volume')).value, 0.4);
    expect(tester.widget<Slider>(sliderOf('settings-music-volume')).value, 0.7);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
  });

  testWidgets('dragging the volume slider persists once', (tester) async {
    final store = await pumpSettings(tester);

    await tester.drag(sliderOf('settings-effects-volume'), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(store.settings.effectsVolume, lessThan(1));
    expect(store.saves, 1);
  });

  testWidgets('dragging the music slider drives the loop live', (tester) async {
    final music = RecordingBackgroundMusic();
    final store = await pumpSettings(tester, music: music);

    await tester.drag(sliderOf('settings-music-volume'), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(store.settings.musicVolume, lessThan(1));
    expect(store.saves, 1);
    // The loop followed the drag and ended on the stored value.
    expect(music.setVolumes, isNotEmpty);
    expect(music.setVolumes.last, store.settings.musicVolume);
  });

  testWidgets('muting shows the muted icon', (tester) async {
    await pumpSettings(tester, initial: const AppSettings(effectsVolume: 0));
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
  });

  testWidgets('muting the music shows its muted icon', (tester) async {
    await pumpSettings(tester, initial: const AppSettings(musicVolume: 0));
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
    expect(find.byIcon(Icons.music_note), findsNothing);
  });

  testWidgets('toggling the preview default persists', (tester) async {
    final store = await pumpSettings(tester);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(store.settings.ghostPreviewDefault, isTrue);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(store.settings.ghostPreviewDefault, isFalse);
    expect(store.saves, 2);
  });

  testWidgets('the Settings tab opens settings', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: HomeShell(clock: () => DateTime(2026, 11, 6, 14)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Settings'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
    // Exactly one title: the nav label must not leak into the AppBar.
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Settings')),
      findsOneWidget,
    );
    expect(find.byType(Slider), findsNWidgets(2));
  });

}
