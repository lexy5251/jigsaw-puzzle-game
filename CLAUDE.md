# CLAUDE.md

Flutter + Flame jigsaw puzzle for iOS, Android, web. Package name is
`jigsaw_puzzle` (differs from the folder name).

# Commands

- Install deps: `flutter pub get`
- Lint: `flutter analyze`
- All tests: `flutter test`
- One test file: `flutter test test/piece_shapes_test.dart`
- Run locally: `flutter run -d chrome` (quickest) or `flutter run` for a device
- E2E: Maestro flows in `.maestro/` — only before store submissions, not per change

Before finishing any code change: `flutter analyze` and `flutter test` must
both pass.

# Conventions

- Pure game logic (grid math, geometry, clamping) lives in Flame-free files
  like `puzzle_logic.dart` and `piece_shapes.dart`; Flame components call into
  it. New logic follows this split so it unit-tests directly.
- Platform plugins are never imported by gameplay code — wrap them in a small
  interface with a test fake (see `GameSounds`, `SaveStore`).
- New features ship with tests in the same change.
- Tests reach game-internal state via `@visibleForTesting` getters, not by
  making fields public.
- UI that e2e tests must find gets a constant tooltip or `Semantics` label.
- Comments explain *why*, not what. All code and comments in English.

# Gotchas

- Save/resume re-creates a puzzle from its key, so randomness must be seeded
  and stable across platforms and Dart versions. Use `_Xorshift32` and
  `shapeSeedForKey` — never `dart:math` `Random` or `String.hashCode` for
  anything persisted.
- Sound and haptics swallow their own errors (decoration must never crash
  gameplay). Keep that guarantee when touching them.
- To game logic a piece is its base-cell rectangle; only rendering uses the
  shaped image and its bleed margin. Don't mix the two sides.
- `docs/` (MVP plan, notes) is local-only and excluded from Git.

# Project decisions

- No AI features — owner's explicit decision; don't propose them.
- Ask before adding a dependency.
- Features come from `docs/puzzle-game-mvp-plan.md`; if something isn't in the
  plan, ask first. When a feature is finished, mark it in the plan:
  `✅ ... _(done YYYY-MM-DD: one-line summary)_`.
