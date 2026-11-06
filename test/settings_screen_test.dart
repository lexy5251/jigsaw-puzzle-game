import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/app_settings.dart';
import 'package:jigsaw_puzzle/settings_screen.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

Future<InMemorySettingsStore> pumpSettings(
  WidgetTester tester, {
  AppSettings initial = const AppSettings(),
}) async {
  final store = InMemorySettingsStore()..settings = initial;
  await tester.pumpWidget(
    MaterialApp(
      theme: studioTheme(),
      home: SettingsScreen(store: store),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('shows the stored settings', (tester) async {
    await pumpSettings(
      tester,
      initial: const AppSettings(effectsVolume: 0.4, ghostPreviewDefault: true),
    );

    expect(tester.widget<Slider>(find.byType(Slider)).value, 0.4);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
  });

  testWidgets('dragging the volume slider persists once', (tester) async {
    final store = await pumpSettings(tester);

    await tester.drag(find.byType(Slider), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(store.settings.effectsVolume, lessThan(1));
    expect(store.saves, 1);
  });

  testWidgets('muting shows the muted icon', (tester) async {
    await pumpSettings(tester, initial: const AppSettings(effectsVolume: 0));
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
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

  testWidgets('the select screen gear opens settings', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSelectScreen(tester, clock: () => DateTime(2026, 11, 6, 14));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });
}
