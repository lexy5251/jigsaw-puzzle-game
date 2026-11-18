// Dev tool, not a test: renders the REAL game screen — live tray, real
// catalog photo cropped square (the decided 1:1 catalog shape) — once per
// tray-size candidate, then composes labeled pick sheets so the owner can
// judge tray piece size before a device build. Skipped unless
// TRAY_SIZE_PREVIEW=1:
//   TRAY_SIZE_PREVIEW=1 flutter test test/tray_size_preview_test.dart
//
// Sheet 1 (phone): column-density candidates; the shipped density is
// labeled "Today" straight from trayVisibleColumns so the baseline can
// never go stale. Sheets 2-4 (iPad portrait/landscape, tall web window):
// three large-screen piece-size policies for the owner's ruling.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/puzzle_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

void main() {
  final enabled = previewEnabled('TRAY_SIZE_PREVIEW');
  const sourcePhoto = 'assets/images/animals/pets_in_the_reading_nook.webp';

  testWidgets('render the phone tray density pick sheet', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      await loadStudioFonts();
      await loadMaterialIcons();

      final (width, height, _) = previewPhoneSizes.first;
      final square = await squareCatalogPhoto(sourcePhoto);
      final panels = <(ui.Image, String)>[];
      try {
        for (final columns in const [6, 5, 4, 3]) {
          // The shipped density labels itself — the baseline can't go stale.
          final label = columns == trayVisibleColumns
              ? 'Today - $columns across'
              : '$columns across';
          panels.add((
            await captureGameScreenPanel(
              tester,
              photo: square.clone(),
              panelId: 'tray-density-$columns',
              screenSize: Size(width, height),
              trayColumns: columns,
              // Uncapped: this sheet judges pure density; the shipped
              // phone-size ceiling would clamp the denser candidates.
              trayMaxThumbnailHeight: null,
            ),
            label,
          ));
        }
      } finally {
        square.dispose();
      }
      await composePreviewSheet(panels, 'docs/tray-size-preview.png');
    });
  }, skip: !enabled);

  testWidgets('render the large-screen tray policy sheets', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      await loadStudioFonts();
      await loadMaterialIcons();

      // The three policies up for the owner's ruling. B's 85px ceiling
      // reproduces the old static cap exactly on these surfaces (2 rows of
      // 85 + padding = the old 200px tray); C pins pieces to the height the
      // 5-column rule gives on his phone, so they feel the same everywhere.
      const policies = <(double?, String)>[
        (null, 'A - pieces grow'),
        (85.0, 'B - old 200 ceiling'),
        (74.0, 'C - phone-size pieces'),
      ];
      const screens = <(Size, String)>[
        (Size(820, 1180), 'ipad-portrait'),
        (Size(1180, 820), 'ipad-landscape'),
        (Size(800, 1200), 'web-tall'),
      ];

      final square = await squareCatalogPhoto(sourcePhoto);
      try {
        for (final (screenSize, screenName) in screens) {
          final panels = <(ui.Image, String)>[];
          for (final (maxThumbnail, label) in policies) {
            panels.add((
              await captureGameScreenPanel(
                tester,
                photo: square.clone(),
                panelId: 'tray-$screenName-${maxThumbnail ?? 'uncapped'}',
                screenSize: screenSize,
                trayColumns: trayVisibleColumns,
                trayMaxThumbnailHeight: maxThumbnail,
              ),
              label,
            ));
          }
          await composePreviewSheet(panels, 'docs/tray-size-$screenName.png');
        }
      } finally {
        square.dispose();
      }
    });
  }, skip: !enabled);
}
