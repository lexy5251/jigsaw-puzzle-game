// Pins for the riso chrome's shared pieces: the page app bar, the category
// meter, and the two marker behaviors the code-review proved fragile — the
// done sticker must never eat taps, and the Edges-only toggle must announce
// its state on the labeled node.

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/game_screen.dart';
import 'package:jigsaw_puzzle/riso_markers.dart';
import 'package:jigsaw_puzzle/studio_surfaces.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';

void main() {
  group('risoAppBar', () {
    testWidgets('shows the title with the dots excluded from semantics', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          home: Scaffold(appBar: risoAppBar('Story')),
        ),
      );
      expect(find.text('Story'), findsOneWidget);
      // The halftone accent is decoration: no semantics node of its own.
      expect(
        tester
            .getSemantics(find.byType(AppBar))
            .getSemanticsData()
            .label,
        isNot(contains('Halftone')),
      );
      expect(find.byType(HalftoneDots), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('survives huge text on a narrow phone without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 3.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          home: Scaffold(appBar: risoAppBar('Choose a puzzle')),
        ),
      );
      // The FittedBox shrinks the title instead of bursting the bar.
      expect(tester.takeException(), isNull);
      expect(find.text('Choose a puzzle'), findsOneWidget);
    });
  });

  group('PieceMeter', () {
    testWidgets('fills one piece per finished painting and labels itself', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          home: const Scaffold(body: PieceMeter(done: 3, total: 10)),
        ),
      );
      expect(find.text(pieceMeterText(3, 10)), findsOneWidget);
      Finder pieces({required bool filled}) => find.byWidgetPredicate(
        (widget) =>
            widget is FamilyPiece &&
            (widget.fill == StudioColors.tomato) == filled,
      );
      expect(pieces(filled: true), findsNWidgets(3));
      expect(pieces(filled: false), findsNWidgets(7));
      // One merged announcement; the 10 mini pieces stay silent.
      expect(
        find.bySemanticsLabel('3 of 10 pieced together'),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  testWidgets('the done sticker never eats the card tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: Center(
          child: SizedBox(
            width: 180,
            height: 180,
            child: TiltedPhotoCard(
              assetPath: 'assets/images/test_photo.jpg',
              title: 'Test photo',
              semanticsIdentifier: 'test-photo',
              onTap: () => taps++,
              cornerMarker: const DonePieceSticker(),
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(TiltedPhotoCard));
    // On the sticker itself (in-bounds top-right corner of the card).
    await tester.tapAt(rect.topRight + const Offset(-15, 15));
    await tester.pump();
    expect(taps, 1, reason: 'the marker must be IgnorePointer-wrapped');
  });

  testWidgets('Edges only announces its state on the labeled node', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: Scaffold(
          body: EdgesOnlyToggle(selected: true, onChanged: (_) {}),
        ),
      ),
    );
    // The toggled flag must sit on the SAME node as the label — a separate
    // label-less toggle node is silent for screen readers.
    final node = tester.getSemantics(find.text('Edges only'));
    final data = node.getSemanticsData();
    expect(data.label, contains('Edges only'));
    expect(data.flagsCollection.isToggled, Tristate.isTrue);
    semantics.dispose();
  });
}
