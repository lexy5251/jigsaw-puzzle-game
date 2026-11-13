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

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/game_screen.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_logic.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// Decodes a bundled catalog photo and center-crops it square, matching the
/// decided 1:1 catalog shape before the regenerated images land.
Future<ui.Image> _squareCatalogPhoto(String assetPath) async {
  final source = await decodeAssetImage(assetPath);
  try {
    final side = min(source.width, source.height);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      source,
      Rect.fromLTWH(
        (source.width - side) / 2,
        (source.height - side) / 2,
        side.toDouble(),
        side.toDouble(),
      ),
      Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(side, side);
    } finally {
      picture.dispose();
    }
  } finally {
    source.dispose();
  }
}

/// Boots the real GameScreen on [photo] (ownership transfers: the panel's
/// game disposes it via the image cache) and returns the captured screen.
Future<ui.Image> _captureGamePanel(
  WidgetTester tester, {
  required ui.Image photo,
  required String panelId,
  required Size screenSize,
  required int trayColumns,
  double? trayMaxThumbnailHeight,
}) async {
  final assetName = '$panelId.webp';
  Flame.images.add(assetName, photo);
  final boundaryKey = GlobalKey();
  await pumpPhoneApp(
    tester,
    GameScreen(
      image: PuzzleImage(
        id: panelId,
        title: 'Tray preview',
        categoryId: 'animals',
        fileName: assetName,
      ),
      // Square cells on the square photo, like the migrated catalog.
      size: const PuzzleSize(columns: 5, rows: 5),
      soundsFactory: SilentGameSounds.new,
      trayColumns: trayColumns,
      trayMaxThumbnailHeight: trayMaxThumbnailHeight,
    ),
    size: screenSize,
    boundaryKey: boundaryKey,
  );
  await currentGame(tester).loaded;
  // Same settle window as the tray pixel tests: lets the cut pieces mount
  // and the tray lay out its thumbnails.
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return capturePreviewImage(boundaryKey);
}

/// Draws the captured panels side by side with a label band on top and
/// writes the sheet. Takes ownership of the panel images.
Future<void> _composeSheet(
  List<(ui.Image, String)> panels,
  String path,
) async {
  const margin = 48.0;
  const gap = 48.0;
  const labelBand = 120.0;
  try {
    final sheetWidth =
        margin * 2 +
        panels.fold(0.0, (sum, p) => sum + p.$1.width) +
        (panels.length - 1) * gap;
    final sheetHeight =
        margin * 2 +
        labelBand +
        panels.map((p) => p.$1.height).reduce(max).toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(
        Rect.fromLTWH(0, 0, sheetWidth, sheetHeight),
        Paint()..color = StudioColors.ground,
      );
    var left = margin;
    for (final (panel, label) in panels) {
      final text = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w800,
            fontSize: 56,
            color: StudioColors.ink,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(
        canvas,
        Offset(
          left + (panel.width - text.width) / 2,
          margin + (labelBand - text.height) / 2,
        ),
      );
      text.dispose();
      canvas.drawImage(panel, Offset(left, margin + labelBand), Paint());
      left += panel.width + gap;
    }
    final picture = recorder.endRecording();
    final sheet = await picture.toImage(sheetWidth.ceil(), sheetHeight.ceil());
    picture.dispose();
    try {
      await writePreviewPng(sheet, path);
    } finally {
      sheet.dispose();
    }
  } finally {
    for (final (panel, _) in panels) {
      panel.dispose();
    }
  }
}

void main() {
  final enabled = previewEnabled('TRAY_SIZE_PREVIEW');
  const sourcePhoto = 'assets/images/animals/pets_in_the_reading_nook.webp';

  testWidgets('render the phone tray density pick sheet', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      await loadStudioFonts();
      await loadMaterialIcons();

      final (width, height, _) = previewPhoneSizes.first;
      final square = await _squareCatalogPhoto(sourcePhoto);
      final panels = <(ui.Image, String)>[];
      try {
        for (final columns in const [6, 5, 4, 3]) {
          // The shipped density labels itself — the baseline can't go stale.
          final label = columns == trayVisibleColumns
              ? 'Today - $columns across'
              : '$columns across';
          panels.add((
            await _captureGamePanel(
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
      await _composeSheet(panels, 'docs/tray-size-preview.png');
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

      final square = await _squareCatalogPhoto(sourcePhoto);
      try {
        for (final (screenSize, screenName) in screens) {
          final panels = <(ui.Image, String)>[];
          for (final (maxThumbnail, label) in policies) {
            panels.add((
              await _captureGamePanel(
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
          await _composeSheet(panels, 'docs/tray-size-$screenName.png');
        }
      } finally {
        square.dispose();
      }
    });
  }, skip: !enabled);
}
