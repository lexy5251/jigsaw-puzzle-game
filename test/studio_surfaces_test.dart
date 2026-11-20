// Riso chrome: every card is a printed sticker — structure-ink border with
// a hard SAME-ink zero-blur offset shadow (dial rule 2). These pins make a
// silent revert to soft/blurred shadows or borderless cards fail, and tie
// the pieces that must agree (border ink == shadow ink) to each other.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/studio_surfaces.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';

void main() {
  testWidgets('PaintedCard: sticker border and shadow share one ink', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: const PaintedCard(child: SizedBox(width: 200, height: 100)),
      ),
    );
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(PaintedCard),
        matching: find.byType(Material),
      ),
    );
    final shape = material.shape as RoundedRectangleBorder;
    expect(shape.side.color, StudioColors.structureInk);
    expect(shape.side.width, PaintedCard.borderWidth);

    // The shadow silhouette must be the same shape as the visible edge,
    // in the SAME ink, with zero blur — the printed-sticker rule.
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byType(PaintedCard),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as ShapeDecoration;
    expect(decoration.shape, same(material.shape));
    final shadow = decoration.shadows!.single;
    expect(shadow.color, StudioColors.structureInk);
    expect(shadow.blurRadius, 0);
    expect(shadow.offset, isNot(Offset.zero));
  });

  testWidgets('FramedArt: border ink hugs the clipped artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FramedArt(child: SizedBox(width: 200, height: 100)),
      ),
    );
    // Border is a foreground so it overlaps the artwork's edge pixels.
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(FramedArt),
        matching: find.byType(Container),
      ),
    );
    final foreground = container.foregroundDecoration as BoxDecoration;
    final border = foreground.border as Border;
    expect(border.top.color, StudioColors.structureInk);
    expect(border.top.width, PaintedCard.borderWidth);
    // And the artwork is clipped to the same rounding as the border.
    final clip = tester.widget<ClipRRect>(
      find.descendant(
        of: find.byType(FramedArt),
        matching: find.byType(ClipRRect),
      ),
    );
    expect(clip.borderRadius, foreground.borderRadius);
  });

  testWidgets('a tiny card paints without throwing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: const Center(
          child: SizedBox(
            width: 10,
            height: 10,
            child: PaintedCard(child: SizedBox.expand()),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('TiltedPhotoCard sits straight with the sticker border', (
    tester,
  ) async {
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
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    // The tilt is retired (owner's v20 ruling): no rotation transform in
    // the card's subtree.
    expect(
      find.descendant(
        of: find.byType(TiltedPhotoCard),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(TiltedPhotoCard),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.border!.top.color, StudioColors.structureInk);
    final shadow = decoration.boxShadow!.single;
    expect(shadow.color, StudioColors.structureInk);
    expect(shadow.blurRadius, 0);
  });

  testWidgets('RisoPageTitle: structure ink with the salmon misprint', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: studioTheme(), home: const RisoPageTitle('Gallery')),
    );
    final text = tester.widget<Text>(find.text('Gallery'));
    expect(text.style!.color, StudioColors.structureInk);
    expect(text.style!.fontFamily, 'Rokkitt');
    final misprint = text.style!.shadows!.single;
    expect(misprint.color, StudioColors.salmon);
    expect(misprint.blurRadius, 0);
  });

  test('the structure ink is one constant (the cobalt-swap guarantee)', () {
    // The violet→cobalt fallback must stay a two-value change in
    // studio_theme.dart; every sticker surface derives from these.
    expect(PaintedCard.softShadow.color, StudioColors.structureInk);
    expect(PaintedCard.groundShadow.color, StudioColors.structureInk);
    expect(StudioColors.cardShadow, StudioColors.structureInk);
  });
}
