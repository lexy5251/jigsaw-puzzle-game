// The root shell: the approved mockup's bottom nav, grown to four tabs —
// Gallery · Story · My Puzzles · Settings. Category and game screens are
// pushed on the root navigator, so they cover the bar while playing. The
// shell also owns the ambient music loop, which therefore outlives every
// pushed screen.

import 'dart:async';

import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'background_music.dart';
import 'my_puzzles_screen.dart';
import 'puzzle_select_screen.dart';
import 'settings_screen.dart';
import 'story_screen.dart';

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

  /// One record per tab: the nav entry and the screen come from the same
  /// list, so the IndexedStack child, the destination, and the isActive
  /// wire can never fall out of step when a tab is added or moved.
  List<_Tab> _tabs() => [
    _Tab(
      destination: const NavigationDestination(
        icon: Icon(Icons.collections_outlined),
        selectedIcon: Icon(Icons.collections),
        label: 'Gallery',
        tooltip: 'Gallery tab',
      ),
      builder: (isActive) =>
          PuzzleSelectScreen(clock: widget.clock, isActive: isActive),
    ),
    _Tab(
      destination: const NavigationDestination(
        icon: Icon(Icons.auto_stories_outlined),
        selectedIcon: Icon(Icons.auto_stories),
        label: 'Story',
        tooltip: 'Story tab',
      ),
      builder: (isActive) =>
          StoryScreen(clock: widget.clock, isActive: isActive),
    ),
    _Tab(
      destination: const NavigationDestination(
        icon: Icon(Icons.extension_outlined),
        selectedIcon: Icon(Icons.extension),
        label: 'My Puzzles',
        tooltip: 'My Puzzles tab',
      ),
      builder: (isActive) =>
          MyPuzzlesScreen(clock: widget.clock, isActive: isActive),
    ),
    _Tab(
      destination: const NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: 'Settings',
        tooltip: 'Settings tab',
      ),
      builder: (_) =>
          SettingsScreen(store: widget.settingsStore, music: _music),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs();
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _nudgeMusic,
      child: Scaffold(
        // IndexedStack keeps all four tabs alive, so scroll positions, the
        // My Puzzles tab selection, and mid-gesture state survive switches.
        // Freshness comes from the isActive flags: a tab reloads its stores
        // when it becomes the visible one (TabActivationAware), not by
        // being torn down and rebuilt.
        body: IndexedStack(
          index: _index,
          children: [
            for (final (i, tab) in tabs.indexed) tab.builder(_index == i),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (index) => setState(() => _index = index),
          // Constant tooltips double as unique e2e hooks: the labels alone
          // repeat the open tab's AppBar title ('Settings' twice on screen).
          destinations: [for (final tab in tabs) tab.destination],
        ),
      ),
    );
  }
}

/// A bottom-nav tab: its destination chip and the screen it shows. The
/// builder receives whether this tab is the visible one.
class _Tab {
  const _Tab({required this.destination, required this.builder});

  final NavigationDestination destination;
  final Widget Function(bool isActive) builder;
}
