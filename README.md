# Jigsaw Puzzle Game

A Flutter and Flame jigsaw puzzle prototype for Android, iOS, and web.

## Project layout

`jigsaw-puzzle-game/` is both the Flutter project root and the intended Git
repository root. Run Flutter and Git commands from this folder.

```text
jigsaw-puzzle-game/
├── .gitignore          # All repository ignore rules
├── pubspec.yaml        # Flutter dependencies and assets
├── pubspec.lock        # Locked dependency versions
├── lib/                # Dart application code
├── assets/             # Puzzle images
├── test/               # Test scaffolding
├── android/            # Android project
├── ios/                # iOS project
└── web/                # Web project
```

The Dart package name in `pubspec.yaml` is `jigsaw_puzzle`. This identifier is
separate from the folder name and is used for Dart package imports.

## Run

With the Flutter SDK installed, run these commands from the project root:

```sh
flutter pub get
flutter run -d chrome
```

For an attached phone or simulator, select a device with `flutter run`.

## Checks and builds

```sh
flutter analyze
flutter build web
flutter build apk --release
```

Tests live in `test/`: game-logic unit tests plus widget tests for snapping
and the select-screen flow. Run them with `flutter test`.

Planning notes in `docs/` are local files and are excluded from Git.
