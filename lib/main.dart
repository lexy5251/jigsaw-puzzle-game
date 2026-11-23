import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'analytics.dart';
import 'analytics_firebase.dart';
import 'firebase_options.dart';
import 'home_shell.dart';
import 'studio_theme.dart';

/// Opt-in for DebugView sessions: development runs stay silent so the
/// owner's own testing never pollutes the metrics, except when launched with
/// --dart-define=ANALYTICS_IN_DEBUG=true to watch events arrive live.
const _analyticsInDebugBuilds = bool.fromEnvironment('ANALYTICS_IN_DEBUG');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Fire-and-forget: launch never waits on the network, and the handful of
  // events before the swap lands just stay silent.
  if (kReleaseMode || _analyticsInDebugBuilds) {
    unawaited(_connectAnalytics());
  }
  runApp(const JigsawPuzzleApp());
}

/// Swaps the silent analytics default for the Firebase-backed one. Analytics
/// is decoration: any init failure (offline first run, bad config) simply
/// leaves the silent default in place.
Future<void> _connectAnalytics() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    Analytics.instance = FirebaseGameAnalytics(FirebaseAnalytics.instance);
  } catch (_) {}
}

/// App shell: theme + the bottom-nav home (Gallery · My Puzzles · Settings).
class JigsawPuzzleApp extends StatelessWidget {
  const JigsawPuzzleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jigsaw Puzzle',
      theme: studioTheme(),
      home: const HomeShell(),
    );
  }
}
