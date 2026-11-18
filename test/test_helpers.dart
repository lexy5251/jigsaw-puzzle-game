import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/app_settings.dart';
import 'package:jigsaw_puzzle/background_music.dart';
import 'package:jigsaw_puzzle/completion_card.dart';
import 'package:jigsaw_puzzle/daily_puzzle.dart';
import 'package:jigsaw_puzzle/game_haptics.dart';
import 'package:jigsaw_puzzle/game_screen.dart';
import 'package:jigsaw_puzzle/game_sounds.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:jigsaw_puzzle/puzzle_logic.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';
import 'package:jigsaw_puzzle/puzzle_select_screen.dart';
import 'package:jigsaw_puzzle/story_track.dart';
import 'package:jigsaw_puzzle/studio_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small fixture shared by game-screen, settings, and restart tests.
const singlePieceImage = PuzzleImage(
  id: 'test',
  title: 'Test puzzle',
  categoryId: 'test',
  fileName: 'test_photo.jpg',
);
const singlePieceSize = PuzzleSize(columns: 1, rows: 1);

/// [MockSharedPreferences.storage] key for [image]'s save at a grid — the
/// channel-backed mock needs the plugin's `flutter.` prefix, which is easy
/// to forget inline: a save seeded without it is silently ignored and the
/// test stays green against a fresh board.
String saveKeyFor(PuzzleImage image, {int columns = 1, int rows = 1}) =>
    'flutter.${puzzleSaveKey(imageId: image.id, columns: columns, rows: rows)}';

/// [saveKeyFor]'s twin for completion records.
String completionKeyFor(PuzzleImage image, {int columns = 1, int rows = 1}) =>
    'flutter.${puzzleCompletionKey(imageId: image.id, columns: columns, rows: rows)}';

/// UNPREFIXED save key for [SharedPreferences.setMockInitialValues] seeding
/// (which adds the `flutter.` prefix itself — seeding a [saveKeyFor] key
/// there double-prefixes and the save is silently ignored). One shared
/// recipe so suites stop growing private clones of it.
String seedSaveKey(PuzzleImage image, PuzzleSize size) =>
    puzzleSaveKey(imageId: image.id, columns: size.columns, rows: size.rows);

/// Catalog paintings that are NOT [now]'s daily — the continue-card suites'
/// fixture pool, in one place so the test and the owner's preview harness
/// can never encode different exclusion rules.
List<PuzzleImage> nonDailyCatalogImages(DateTime now) {
  final daily = dailyPuzzleFor(now);
  return [
    for (final image in puzzleCatalog)
      if (image.id != daily.id) image,
  ];
}

// The shared single-piece fixture's keys, through the same recipe.
final singlePieceProgressKey = saveKeyFor(singlePieceImage);
final singlePieceCompletionKey = completionKeyFor(singlePieceImage);

/// Width of assets/images/test_photo.jpg. Injected saves must stamp it as
/// [PuzzleSaveState.boardWidth] or the game discards them as written against
/// a different image resolution.
const testPhotoWidth = 1600;

/// Height of assets/images/test_photo.jpg.
const testPhotoHeight = 1067;

/// Cell size of the standard 6x4 grid cut from the test photo — shared so
/// a future photo swap updates every suite's home positions in one place.
const grid6x4PieceWidth = testPhotoWidth / 6;
const grid6x4PieceHeight = testPhotoHeight / 4;

/// World position of piece [index]'s correct cell on the 6x4 test grid.
Vector2 grid6x4Home(int index) => Vector2(
  index % 6 * grid6x4PieceWidth,
  index ~/ 6 * grid6x4PieceHeight,
);

/// One loose piece at its target; a settle completes the puzzle.
PuzzleSaveState singleLoosePieceSave({String? startedDay}) => PuzzleSaveState(
  trayPieceIndexes: const [],
  lockedPieceIndexes: const [],
  loosePiecePositions: {0: Vector2.zero()},
  startedDay: startedDay,
  boardWidth: testPhotoWidth,
);

/// A mid-way snapshot: the first [placed] pieces locked in place, the rest
/// in the tray.
PuzzleSaveState partiallyPlacedSave(
  int pieceCount, {
  required int placed,
  String? startedDay,
  int? boardWidth,
  DateTime? savedAt,
}) => PuzzleSaveState(
  trayPieceIndexes: [for (var i = placed; i < pieceCount; i++) i],
  lockedPieceIndexes: [for (var i = 0; i < placed; i++) i],
  loosePiecePositions: const {},
  startedDay: startedDay,
  boardWidth: boardWidth,
  savedAt: savedAt,
);

/// Every piece still in the tray — the standard "just started, resumable"
/// fixture. Stamp [boardWidth] with [testPhotoWidth] when the game itself
/// must accept the save (the scale guard discards other widths).
PuzzleSaveState fullTraySave(
  int pieceCount, {
  String? startedDay,
  int? boardWidth,
  DateTime? savedAt,
}) => partiallyPlacedSave(
  pieceCount,
  placed: 0,
  startedDay: startedDay,
  boardWidth: boardWidth,
  savedAt: savedAt,
);

/// A completion record finished [count] times, newest on [day].
CompletionRecord completionOn(DateTime day, {int count = 1}) =>
    CompletionRecord(count: count, lastCompletedAt: day);

/// [completionOn] in the stored form prefs seeds need.
String completionJson(DateTime day, {int count = 1}) =>
    completionOn(day, count: count).toJsonString();

/// The frozen clock every preview harness renders at — one clock, so the
/// daily pick and "recent vs old" completion states match across harnesses
/// and a verdict made on one holds on the others.
DateTime previewNow() => DateTime(2026, 11, 12, 14);

/// Settles a game launched through the UI (tap → route → Flame boot).
/// pumpAndSettle never settles against Flame's ticker, so fixed pumps
/// cover the sheet-close + route animations and the photo decode, then the
/// game's load future and a few frames to mount the pieces. Call inside
/// [WidgetTester.runAsync] — the decode needs real async. The pump counts
/// are tuned; change them here, not at a call site.
Future<void> settleLaunchedGame(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await currentGame(tester).loaded;
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Extracts the game currently hosted by the screen, including after restart.
JigsawGame currentGame(WidgetTester tester) => tester
    .widget<GameWidget<JigsawGame>>(find.byType(GameWidget<JigsawGame>))
    .game!;

/// The category page's photo card for one catalog image — the same semantics
/// identifier the Maestro flows tap.
Finder catalogPuzzleCard(String id) =>
    find.bySemanticsIdentifier('catalog-puzzle-$id');

/// Gift-track fixtures shared by the bonus suites (track math and unlock
/// UI must test the same two-gift catalog).
const giftImageOne = PuzzleImage(
  id: 'gift-1',
  title: 'Gift One',
  categoryId: bonusCategoryId,
  fileName: 'test_photo.jpg',
);
const giftImageTwo = PuzzleImage(
  id: 'gift-2',
  title: 'Gift Two',
  categoryId: bonusCategoryId,
  fileName: 'test_photo.jpg',
);
const giftFixtures = [giftImageOne, giftImageTwo];

/// Story-scene fixtures for the chain tests: three scenes, so a replay can
/// skip an already-finished middle scene.
const sceneImageOne = PuzzleImage(
  id: 'scene-1',
  title: 'Scene One',
  categoryId: storyCategoryId,
  fileName: 'test_photo.jpg',
);
const sceneImageTwo = PuzzleImage(
  id: 'scene-2',
  title: 'Scene Two',
  categoryId: storyCategoryId,
  fileName: 'test_photo.jpg',
);
const sceneImageThree = PuzzleImage(
  id: 'scene-3',
  title: 'Scene Three',
  categoryId: storyCategoryId,
  fileName: 'test_photo.jpg',
);
const sceneFixtures = [sceneImageOne, sceneImageTwo, sceneImageThree];

/// Completion entries marking the first [count] scenes of the real story
/// read (one 5x5 finish each), in the unprefixed form
/// [SharedPreferences.setMockInitialValues] expects. The story suites all
/// seed through here so the recipe cannot drift between them.
Map<String, Object> finishedSceneEntries(int count) => {
  for (var i = 0; i < count; i++)
    puzzleCompletionKey(
      imageId: jigsawStory.stops[i].image.id,
      columns: 5,
      rows: 5,
    ): completionJson(
      DateTime(2026, 11, 1 + i),
    ),
};

/// The pop result of a [GameScreen] opened through a real pushed route —
/// the completion card's chain buttons ("Next puzzle", "Play now") pop
/// with a painting, and these fields capture it.
class PushedGameRoute {
  PuzzleImage? popResult;
  bool popped = false;
}

/// Pumps a host app, pushes a [GameScreen] route, and settles the launched
/// game — the one harness for chain-button tests, so the launch recipe
/// cannot drift between suites.
Future<PushedGameRoute> pushGameScreen(
  WidgetTester tester, {
  required PuzzleImage image,
  required PuzzleSize size,
  PuzzleCatalogs catalogs = const PuzzleCatalogs(),
}) async {
  final route = PushedGameRoute();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              route.popResult = await Navigator.push<PuzzleImage>(
                context,
                MaterialPageRoute<PuzzleImage>(
                  builder: (_) =>
                      GameScreen(image: image, size: size, catalogs: catalogs),
                ),
              );
              route.popped = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.runAsync(() => settleLaunchedGame(tester));
  return route;
}

/// True when the named preview harness was explicitly requested, e.g.
/// CATEGORY_GRID_PREVIEW=1 flutter test test/category_grid_preview_test.dart
bool previewEnabled(String envVar) => Platform.environment[envVar] == '1';

/// Loads every bundled font so previews and pixel tests render in the real
/// studio type instead of the test-default Ahem boxes.
Future<void> loadStudioFonts() async {
  const families = {
    'Fredoka': ['Fredoka-Medium', 'Fredoka-SemiBold'],
    'Nunito': [
      'Nunito-Regular',
      'Nunito-SemiBold',
      'Nunito-Bold',
      'Nunito-ExtraBold',
    ],
  };
  for (final family in families.entries) {
    final loader = FontLoader(family.key);
    for (final file in family.value) {
      loader.addFont(rootBundle.load('assets/fonts/$file.ttf'));
    }
    await loader.load();
  }
}

/// Loads the SDK's Material icon glyphs — the test environment renders
/// every Icons.* as a box otherwise. Only previews need the real glyphs.
Future<void> loadMaterialIcons() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
  final bytes = await File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ).readAsBytes();
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

/// Encodes a captured preview to PNG and announces the absolute path (the
/// owner's preview harnesses all land under docs/, which stays out of Git).
Future<void> writePreviewPng(ui.Image shot, String path) async {
  final png = await shot.toByteData(format: ui.ImageByteFormat.png);
  final out = File(path);
  await out.parent.create(recursive: true);
  await out.writeAsBytes(png!.buffer.asUint8List());
  debugPrint('preview written to ${out.absolute.path}');
}

/// The owner's judging sizes — his phone-ish portrait plus the narrowest
/// supported width. Every preview harness renders this same set so a
/// layout verdict made on one harness holds on the others.
const previewPhoneSizes = [
  (390.0, 844.0, 'phone-390'),
  (320.0, 568.0, 'narrow-320'),
];

/// The one pixel ratio every preview render uses, so a size verdict made on
/// one harness's output holds on the others.
const previewPixelRatio = 3.0;

/// Captures [boundaryKey]'s RepaintBoundary at [previewPixelRatio]. The
/// caller owns (and must dispose) the returned image.
Future<ui.Image> capturePreviewImage(GlobalKey boundaryKey) {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return boundary.toImage(pixelRatio: previewPixelRatio);
}

/// Captures [boundaryKey]'s RepaintBoundary at the shared preview pixel
/// ratio and writes the PNG to [path]. All preview harnesses go through
/// here so the owner's renders always use the same scale.
Future<void> capturePreviewPng(GlobalKey boundaryKey, String path) async {
  final shot = await capturePreviewImage(boundaryKey);
  try {
    await writePreviewPng(shot, path);
  } finally {
    shot.dispose();
  }
}

/// Decodes a bundled asset image to pixels. Preview harnesses only — the
/// app itself always goes through Flame's image cache or Image.asset.
Future<ui.Image> decodeAssetImage(String assetPath) async {
  final bytes = await rootBundle.load(assetPath);
  final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

/// Decodes a bundled catalog photo and center-crops it square, matching the
/// decided 1:1 catalog shape. Preview harnesses only.
Future<ui.Image> squareCatalogPhoto(String assetPath) async {
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
/// [beforeCapture] runs after the board settles — e.g. [openOptionsMenu]
/// for a menu-open panel. Shared by the preview harnesses so the tuned
/// boot-and-settle pump recipe cannot drift between them.
Future<ui.Image> captureGameScreenPanel(
  WidgetTester tester, {
  required ui.Image photo,
  required String panelId,
  required Size screenSize,
  PuzzleSize grid = const PuzzleSize(columns: 5, rows: 5),
  int trayColumns = trayVisibleColumns,
  double? trayMaxThumbnailHeight = trayThumbnailHeightCap,
  Future<void> Function(WidgetTester tester)? beforeCapture,
}) async {
  final assetName = '$panelId.webp';
  Flame.images.add(assetName, photo);
  final boundaryKey = GlobalKey();
  await pumpPhoneApp(
    tester,
    GameScreen(
      image: PuzzleImage(
        id: panelId,
        title: 'Preview panel',
        categoryId: 'animals',
        fileName: assetName,
      ),
      size: grid,
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
  await beforeCapture?.call(tester);
  return capturePreviewImage(boundaryKey);
}

/// Draws captured preview panels side by side with a label band on top and
/// writes the sheet to [path]. Takes ownership of the panel images.
Future<void> composePreviewSheet(
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

/// Shared no-op sounds for suites that only need silence; tests that count
/// cues keep their own recording fakes.
class SilentGameSounds implements GameSounds {
  @override
  Future<void> preload() async {}
  @override
  void playDrop() {}
  @override
  void playSnap() {}
  @override
  void playComplete() {}
  @override
  Future<void> dispose() async {}
}

/// Counts haptic cues so gameplay tests can assert the vibration setting
/// actually gates them.
class RecordingGameHaptics implements GameHaptics {
  int snaps = 0;
  int completes = 0;

  @override
  void snap() => snaps++;

  @override
  void complete() => completes++;
}

/// Records every call so shell and settings tests can assert how the app
/// drives the ambient loop.
class RecordingBackgroundMusic implements BackgroundMusic {
  final startVolumes = <double>[];
  final setVolumes = <double>[];
  int pauses = 0;
  int resumes = 0;
  int disposals = 0;

  @override
  Future<void> start({required double volume}) async =>
      startVolumes.add(volume);

  @override
  void setVolume(double volume) => setVolumes.add(volume);

  @override
  void pause() => pauses++;

  @override
  void resume() => resumes++;

  @override
  Future<void> dispose() async => disposals++;
}

/// Warms the exact image-cache entries `Image.asset(cacheWidth: width)`
/// resolves — [width] must match the widget's cacheWidth or the preview
/// paints before the real decode lands and shows gray thumbnails.
Future<void> precachePreviewImages(
  BuildContext context,
  Iterable<String> assetPaths, {
  required int width,
}) async {
  for (final path in assetPaths) {
    await precacheImage(ResizeImage(AssetImage(path), width: width), context);
  }
}

/// Sizes the test surface like a phone (the owner's 390x844 portrait by
/// default) and pumps [home] under the studio theme. [boundaryKey], when
/// given, wraps the app in a RepaintBoundary for preview captures.
Future<void> pumpPhoneApp(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(390, 844),
  Key? boundaryKey,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = MaterialApp(
    theme: studioTheme(),
    debugShowCheckedModeBanner: false,
    home: home,
  );
  await tester.pumpWidget(
    boundaryKey == null ? app : RepaintBoundary(key: boundaryKey, child: app),
  );
}

/// Channel-backed preferences with controllable storage failures.
class MockSharedPreferences {
  static const _channel = MethodChannel(
    'plugins.flutter.io/shared_preferences',
  );

  /// Platform keys include the `flutter.` prefix.
  final storage = <String, Object>{};
  int writes = 0;
  Object? readError;

  /// Suites for stores whose records must never be deleted set this false,
  /// so an unexpected `remove` fails loudly instead of passing silently.
  bool allowRemoves = true;

  /// Runs before a set or removal. Return false, throw, or delay to simulate
  /// a failed or pending write without changing the stored data.
  FutureOr<bool> Function(String key)? onWrite;

  /// Call from setUp; the handler and preferences cache are cleared afterwards.
  void install() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.resetStatic();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, _handle);
    addTearDown(() {
      messenger.setMockMethodCallHandler(_channel, null);
      SharedPreferences.resetStatic();
    });
  }

  Future<Object> _handle(MethodCall call) async {
    if (call.method == 'getAll') {
      final error = readError;
      if (error != null) {
        throw error;
      }
      return Map<String, Object>.of(storage);
    }
    if (call.method != 'setString' && call.method != 'remove') {
      throw StateError('Unexpected storage call: ${call.method}');
    }
    if (call.method == 'remove' && !allowRemoves) {
      throw StateError('Unexpected storage call: remove');
    }
    final arguments = call.arguments as Map;
    final key = arguments['key'] as String;
    writes++;
    final write = onWrite;
    if (write != null && !await write(key)) {
      return false;
    }
    if (call.method == 'setString') {
      storage[key] = arguments['value'] as String;
    } else {
      storage.remove(key);
    }
    return true;
  }
}

/// Pumps the selection screen under the app's real theme with a fixed
/// clock and, by default, settles it past the first status load — the body
/// renders nothing until that lands (the continue card must never pop in
/// above already-painted content). Pass [settle] false to observe the
/// gated first frame.
Future<void> pumpSelectScreen(
  WidgetTester tester, {
  required DateTime Function() clock,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: studioTheme(),
      home: PuzzleSelectScreen(clock: clock),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  }
}

/// Scrolls the selection screen until [finder] is fully visible — needed
/// because the daily card can repeat a catalog tile's title above the fold.
/// Tapping stays with the caller: some tests assert semantics first.
Future<void> scrollSelectScreenTo(
  WidgetTester tester,
  Finder finder, {
  double delta = 120,
}) async {
  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

/// Loads the real game and advances enough frames to mount its pieces.
Future<JigsawGame> bootGameScreen(
  WidgetTester tester, {
  required PuzzleImage image,
  required PuzzleSize size,
  DateTime Function()? clock,
  AppSettings settings = const AppSettings(),
  GameSounds Function()? soundsFactory,
  GameHaptics? haptics,
  PuzzleCatalogs catalogs = const PuzzleCatalogs(),
}) async {
  late JigsawGame game;
  await tester.runAsync(() async {
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          image: image,
          size: size,
          clock: clock,
          settings: settings,
          soundsFactory: soundsFactory,
          haptics: haptics,
          catalogs: catalogs,
        ),
      ),
    );
    game = currentGame(tester);
    await game.loaded;
  });
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return game;
}

/// Settles an overlay, menu, or dialog change with fixed pumps — the live
/// Flame game keeps requesting frames, so pumpAndSettle would never finish.
Future<void> pumpRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

/// Opens the game screen's Options (…) menu.
Future<void> openOptionsMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Options'));
  await pumpRoute(tester);
}

/// The menu's restart item, type-qualified: the confirm dialog's button
/// carries the same 'Start over' text, so plain find.text is ambiguous
/// while both are on screen.
final Finder startOverMenuItem = find.widgetWithText(
  MenuItemButton,
  'Start over',
);

/// The restart dialog's confirm button (see [startOverMenuItem] for why
/// the finder is type-qualified).
final Finder startOverDialogButton = find.widgetWithText(
  FilledButton,
  'Start over',
);

/// Opens the Options menu and taps "Start over", leaving the confirm
/// dialog up — the shared prefix of confirming AND declining a restart.
Future<void> openRestartDialog(WidgetTester tester) async {
  await openOptionsMenu(tester);
  await tester.tap(startOverMenuItem);
  await pumpRoute(tester);
}

/// Requests a restart through the Options menu and confirms the dialog.
/// Ends right after the confirm tap; callers drive the reload themselves.
Future<void> confirmRestartViaMenu(WidgetTester tester) async {
  await openRestartDialog(tester);
  await tester.tap(startOverDialogButton);
  await tester.pump();
}

/// Settles the last loose piece and waits for the board to report
/// completion — WITHOUT pumping past the card's reveal delay. Restart
/// tests use this directly: the pre-reveal window is the only time the
/// app bar is still usable.
Future<void> completeBoard(WidgetTester tester, JigsawGame game) async {
  game.world.children.whereType<PuzzlePiece>().single.settle();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(game.progress.isComplete, isTrue);
}

/// Completes a fixture with one loose piece, then shows the completion card.
Future<void> completePuzzle(WidgetTester tester, JigsawGame game) async {
  await completeBoard(tester, game);
  await tester.pump(GameScreen.completionRevealDelay);
  await tester.pump(CompletionCard.fadeDuration);
  // One more frame so the fade tween lands on exactly 1 and the card's
  // IgnorePointer releases before tests tap its buttons.
  await tester.pump();
}
