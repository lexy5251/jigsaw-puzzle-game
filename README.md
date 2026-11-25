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

## Adding a new puzzle image

Before a new image goes into the catalog, run the image QA check on it:

```sh
export OPENAI_API_KEY=sk-...   # once per terminal, or put it in ~/.zshrc
python3 tool/image_qa/check_image.py assets/images/<category>/<new-image>.webp
```

It verifies the image works as puzzle pieces (no unreadable patches, no
AI-generation artifacts) and prints PASS or CHECK. On CHECK, read the report
in `tool/image_qa/out/<image>/` and decide: keep or regenerate. Details and
options (e.g. the cheaper `--flags-only` mode) in `tool/image_qa/README.md`.

The full pipeline for a new image: keep the source PNG in
`originals/regen-square/<category>/` (not in Git), convert with
`cwebp -q 85 <source>.png -o assets/images/<category>/<name>.webp`,
run the QA check, then add the entry to the catalog in `lib/`.

Planning notes in `docs/` are local files and are excluded from Git.
