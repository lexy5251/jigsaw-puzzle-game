import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jigsaw_puzzle/app_settings.dart';
import 'package:jigsaw_puzzle/completion_card.dart';
import 'package:jigsaw_puzzle/game_screen.dart';
import 'package:jigsaw_puzzle/game_sounds.dart';
import 'package:jigsaw_puzzle/jigsaw_game.dart';
import 'package:jigsaw_puzzle/puzzle_catalog.dart';
import 'package:jigsaw_puzzle/puzzle_completion.dart';
import 'package:jigsaw_puzzle/puzzle_piece.dart';
import 'package:jigsaw_puzzle/puzzle_save.dart';
import 'package:jigsaw_puzzle/puzzle_select_screen.dart';
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

// The channel-backed mock uses the plugin's prefixed storage keys.
final singlePieceProgressKey =
    'flutter.${puzzleSaveKey(imageId: singlePieceImage.id, columns: singlePieceSize.columns, rows: singlePieceSize.rows)}';
final singlePieceCompletionKey =
    'flutter.${puzzleCompletionKey(imageId: singlePieceImage.id, columns: singlePieceSize.columns, rows: singlePieceSize.rows)}';

/// Width of assets/images/test_photo.jpg. Injected saves must stamp it as
/// [PuzzleSaveState.boardWidth] or the game discards them as written against
/// a different image resolution.
const testPhotoWidth = 1600;

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
}) => PuzzleSaveState(
  trayPieceIndexes: [for (var i = placed; i < pieceCount; i++) i],
  lockedPieceIndexes: [for (var i = 0; i < placed; i++) i],
  loosePiecePositions: const {},
  startedDay: startedDay,
  boardWidth: boardWidth,
);

/// Every piece still in the tray — the standard "just started, resumable"
/// fixture. Stamp [boardWidth] with [testPhotoWidth] when the game itself
/// must accept the save (the scale guard discards other widths).
PuzzleSaveState fullTraySave(
  int pieceCount, {
  String? startedDay,
  int? boardWidth,
}) => partiallyPlacedSave(
  pieceCount,
  placed: 0,
  startedDay: startedDay,
  boardWidth: boardWidth,
);

/// A completion record finished [count] times, newest on [day].
CompletionRecord completionOn(DateTime day, {int count = 1}) =>
    CompletionRecord(count: count, lastCompletedAt: day);

/// Extracts the game currently hosted by the screen, including after restart.
JigsawGame currentGame(WidgetTester tester) => tester
    .widget<GameWidget<JigsawGame>>(find.byType(GameWidget<JigsawGame>))
    .game!;

/// The category page's photo card for one catalog image — the same semantics
/// identifier the Maestro flows tap.
Finder catalogPuzzleCard(String id) =>
    find.bySemanticsIdentifier('catalog-puzzle-$id');

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

/// Captures [boundaryKey]'s RepaintBoundary at the shared preview pixel
/// ratio and writes the PNG to [path]. Both preview harnesses go through
/// here so the owner's renders always use the same scale.
Future<void> capturePreviewPng(GlobalKey boundaryKey, String path) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final shot = await boundary.toImage(pixelRatio: 3);
  try {
    await writePreviewPng(shot, path);
  } finally {
    shot.dispose();
  }
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

/// Pumps the selection screen under the app's real theme with a fixed clock.
Future<void> pumpSelectScreen(
  WidgetTester tester, {
  required DateTime Function() clock,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: studioTheme(),
      home: PuzzleSelectScreen(clock: clock),
    ),
  );
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
  List<PuzzleImage> catalog = puzzleCatalog,
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
          catalog: catalog,
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
