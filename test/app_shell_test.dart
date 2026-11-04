import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/main.dart';
import 'package:jigsaw_puzzle/puzzle_select_screen.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pins the app shell's wiring. Every other test builds its own MaterialApp
/// (to inject a clock), so without this one a broken theme or home screen
/// in main.dart would keep the whole suite green.
void main() {
  testWidgets('boots into the puzzle-select screen under the studio theme', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const JigsawPuzzleApp());
    await tester.pumpAndSettle();

    expect(find.byType(PuzzleSelectScreen), findsOneWidget);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.colorScheme.primary, studioTheme().colorScheme.primary);
  });
}
