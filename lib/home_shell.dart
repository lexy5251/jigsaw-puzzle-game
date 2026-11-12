// The root shell: the approved mockup's bottom nav, built as three tabs —
// Gallery · My Puzzles · Settings. Category and game screens are pushed on
// the root navigator, so they cover the bar while playing.

import 'package:flutter/material.dart';

import 'my_puzzles_screen.dart';
import 'puzzle_select_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.clock});

  /// Returns "now"; forwarded to the tabs so tests can fix the date.
  /// Defaults to [DateTime.now].
  final DateTime Function()? clock;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          const SettingsScreen(),
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
    );
  }
}
