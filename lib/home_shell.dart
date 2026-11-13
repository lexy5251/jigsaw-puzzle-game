// The root shell: the approved mockup's bottom nav, built as three tabs —
// Gallery · My Puzzles · Settings. Category and game screens are pushed on
// the root navigator, so they cover the bar while playing. The shell also
// owns the ambient music loop, which therefore outlives every pushed screen.

import 'dart:async';

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'background_music.dart';
import 'my_puzzles_screen.dart';
import 'puzzle_select_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    this.clock,
    this.settingsStore = const SharedPreferencesAppSettingsStore(),
    this.musicFactory,
  });

  /// Returns "now"; forwarded to the tabs so tests can fix the date.
  /// Defaults to [DateTime.now].
  final DateTime Function()? clock;

  /// Read once at boot for the music volume, then handed to the Settings
  /// tab. Tests pass an in-memory store.
  final AppSettingsStore settingsStore;

  /// Tests pass a recording fake; null plays the real ambient loop.
  final BackgroundMusic Function()? musicFactory;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  var _index = 0;
  late final BackgroundMusic _music;

  /// One nudge per session: it exists only to satisfy browser autoplay
  /// rules, which unblock audio after the first user gesture.
  var _musicNudged = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _music = widget.musicFactory?.call() ?? FlameAudioMusic();
    unawaited(_startMusic());
  }

  Future<void> _startMusic() async {
    final settings = await widget.settingsStore.load();
    await _music.start(volume: settings.musicVolume);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_music.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` is left alone — a control-center pull or permission dialog
    // should not stop the music. `hidden` covers a web tab switch and also
    // fires on the way to `paused`; the duplicate pause is a no-op.
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _music.pause();
      case AppLifecycleState.resumed:
        _music.resume();
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  void _nudgeMusic(PointerDownEvent _) {
    if (_musicNudged) return;
    _musicNudged = true;
    // Browsers block the boot-time play until the first gesture, so the
    // first tap anywhere retries it. Where boot already succeeded this
    // resumes an already-playing loop — a no-op. Don't simplify it away.
    _music.resume();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _nudgeMusic,
      child: Scaffold(
        // IndexedStack keeps all three tabs alive, so scroll positions, the
        // My Puzzles tab selection, and mid-gesture state survive switches.
        // Freshness comes from the isActive flags: a tab reloads its stores
        // when it becomes the visible one (didUpdateWidget), not by being
        // torn down and rebuilt.
        body: IndexedStack(
          index: _index,
          children: [
            PuzzleSelectScreen(clock: widget.clock, isActive: _index == 0),
            MyPuzzlesScreen(clock: widget.clock, isActive: _index == 1),
            SettingsScreen(store: widget.settingsStore, music: _music),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (index) => setState(() => _index = index),
          // Constant tooltips double as unique e2e hooks: the labels alone
          // repeat the open tab's AppBar title ('Settings' twice on screen).
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.collections_outlined),
              selectedIcon: Icon(Icons.collections),
              label: 'Gallery',
              tooltip: 'Gallery tab',
            ),
            NavigationDestination(
              icon: Icon(Icons.extension_outlined),
              selectedIcon: Icon(Icons.extension),
              label: 'My Puzzles',
              tooltip: 'My Puzzles tab',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
              tooltip: 'Settings tab',
            ),
          ],
        ),
      ),
    );
  }
}
