import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/app_settings.dart';
import 'package:jigsaw_puzzle/home_shell.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// Pins how the shell drives the ambient loop: boot, lifecycle, the
/// browser-autoplay nudge, and teardown.
void main() {
  Future<RecordingBackgroundMusic> bootShell(
    WidgetTester tester, {
    double musicVolume = 1,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final music = RecordingBackgroundMusic();
    final store = InMemorySettingsStore()
      ..settings = AppSettings(musicVolume: musicVolume);
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: HomeShell(
          clock: () => DateTime(2026, 11, 6, 14),
          settingsStore: store,
          musicFactory: () => music,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return music;
  }

  testWidgets('boots the loop once with the stored volume', (tester) async {
    final music = await bootShell(tester, musicVolume: 0.3);

    expect(music.startVolumes, [0.3]);
    expect(music.resumes, 0);
    expect(music.pauses, 0);
  });

  testWidgets('pauses in the background, resumes in front', (tester) async {
    final music = await bootShell(tester);

    // The binding synthesizes the in-between states (inactive, hidden), so
    // assert direction rather than exact counts.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(music.pauses, greaterThan(0));
    expect(music.resumes, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(music.resumes, 1);

    // A control-center pull (inactive) must not touch the loop.
    final pausesBefore = music.pauses;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(music.pauses, pausesBefore);
    expect(music.resumes, 1);

    // Leave the binding where every other test expects it.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('the first tap nudges the loop exactly once', (tester) async {
    final music = await bootShell(tester);
    expect(music.resumes, 0);

    await tester.tap(find.byTooltip('Settings tab'));
    await tester.pumpAndSettle();
    expect(music.resumes, 1);

    await tester.tap(find.byTooltip('Gallery tab'));
    await tester.pumpAndSettle();
    expect(music.resumes, 1);
  });

  testWidgets('disposes the loop with the shell', (tester) async {
    final music = await bootShell(tester);

    await tester.pumpWidget(const SizedBox());
    expect(music.disposals, 1);
  });
}
