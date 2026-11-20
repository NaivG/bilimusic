# TESSERA.md

This file provides guidance to Tessera when working with code in this repository.

## Repo shape

Five parallel clients live in this repo. They share the Bilibili API protocol, but **not** code and **not** package management:

| Client | Entry | Toolchain |
| --- | --- | --- |
| Flutter app (Windows / Linux / Android stable; macOS / iOS experimental) | `lib/main.dart` | `flutter` / `dart` |
| Terminal client (TUI) | `bin/bilimusic_tui.dart` | `dart` (pure Dart) |
| Xiaomi Vela watch app | `vela/src/app.ux` | `npm` (independent project — never run `flutter pub` in `vela/`) |
| Chrome extension (MV3) | `extension/manifest.json` | zero-build, plain JS |
| OpenHarmony host | `ohos/entry/.../EntryAbility.ets` | shares `lib/`, built via `tool/ohos_build.ps1` |

`packages/` holds path dependencies (not published to pub.dev): `audio_service_ohos`, `share_plus_ohos`, `mpv_audio_kit_ohos` (OHOS platform impls), `audio_session` and `file_picker` (whole-package vendored — the latter two also need matching `dependency_overrides` in `pubspec.yaml`).

## Commands

The CI-equivalent checks, in the order CI runs them:

```bash
dart format .                        # MUST run before committing (see below)
dart analyze --no-fatal-warnings     # CI uses this exact command
flutter test                         # full suite
flutter build windows                # build the platform you touched
```

- **Use `dart analyze --no-fatal-warnings`, not `flutter analyze`.** The repo carries a standing baseline of ~36 `info`-level lints (`prefer_final_fields`, `prefer_initializing_formals`, `deprecated_member_use`, `sized_box_for_whitespace`). `flutter analyze` exits 1 on those; `dart analyze --no-fatal-warnings` exits 0. Do not "fix" the unrelated baseline lints, but do not add new ones either.
- **`dart format .` is not optional.** CI runs it and the bot auto-commits any diff back onto your branch as `Format code for <sha>` — unformatted code produces a stray bot commit on your PR.
- **Run only the affected test directory** by default (`flutter test test/settings/`); a single file is `flutter test test/settings/title_meta_filter_test.dart`. Run the full `flutter test` before opening a PR.

Per-client verification (mandatory when you touch that client):

```bash
cd vela && npm run verify          # Vela watch app offline self-check
node extension/scripts/verify.mjs   # Chrome extension offline self-check
```

The Chrome extension also needs its assets generated before it will load in the browser: `node extension/scripts/gen_daisyui_subset.mjs` and `node extension/scripts/gen_fontawesome_subset.mjs`.

Other one-off tools:

```bash
dart run bin/bilimusic_tui.dart --probe    # network/decode self-check
dart run tool/network_smoke.dart           # device bootstrap + WBI self-check (touches no login state)
dart run tool/db_schema_check.dart [--downgrade]
```

## Environment

- Flutter **3.47.5** (CI pins it exactly), Dart SDK `^3.13.0`.
- Local verification target is the **Windows desktop** build: `flutter run -d windows`. Windows needs the Visual Studio Desktop C++ workload.
- `flutter pub get` can fail with a gitcode Git LFS `Authorization error` on first run. Retry with smudge skipped — PowerShell: `$env:GIT_LFS_SKIP_SMUDGE='1'; flutter pub get` (bash: `GIT_LFS_SKIP_SMUDGE=1 flutter pub get`).
- Linux build deps: `sudo apt install libgtk-3-dev libx11-dev libxi-dev`. Do **not** preinstall libmpv — `mpv_audio_kit` downloads it at build time.
- **OHOS builds go through `.\tool\ohos_build.ps1`, never a bare `flutter build`.** Its pub cache must sit on the same drive as the project (hvigor requires a relative `srcPath`).
- No credentials are needed to build. Never commit cookies, `SESSDATA`, `refresh_token`, device fingerprints, `build/`, or editor-private files.

## Architecture rules (review blockers)

1. **`lib/core/` must stay pure Dart** — no Flutter imports, because the TUI host reuses it without a Flutter engine. Platform capabilities are injected by the host (`NetworkConfig.cookieLoader` / `cookieSaver`).
2. **The composition root is `lib/app/app_providers.dart`.** Long-lived services are created and disposed *only* there: dependencies via `ref.watch`, resources via `ref.onDispose`. UI consumes providers and must never instantiate a Manager/Service directly. Tests swap dependencies with `ProviderContainer(overrides: [...])`.
3. **UI state providers live in `lib/features/<feature>/*_providers.dart`** and use Riverpod 3.x `Notifier` / `NotifierProvider`. See `features/playlist/playlist_providers.dart` for the fixed pattern for bridging server-side `ChangeNotifier` / `ValueNotifier`.
4. **`AnimatedSwitcher.transitionBuilder` must be `switcherFadeTransition`** from `lib/shared/utils/animations.dart`. The default builder attaches `ValueKey(child.key)`, which trips a `Duplicate keys found` assertion when the subtree key is fixed or null.
5. **Outbound request headers have exactly one assembly point: `NetworkConfig.headersFor(uri)`.** Never hand-write a `Cookie` header and never add a path that bypasses it.
6. **Do not "simplify" the database placement/migration code** in `lib/core/storage/`. Two invariants must hold: `AppDatabase.database` is single-flight (`playlistService.initialize()` and `migrateFromPrefsOnce()` race), and a failed relocation must never return a location with no database. Update the `test/storage/` regression tests when you touch this code.
7. **A version bump is a three-place edit**: `pubspec.yaml` (`version: x.y.z+build`), `assets/version.json` (`version` field plus a new `changelog` entry), and `lib/shared/utils/app_version.dart` (the display / boot-version constant). Changing only one breaks in-app update detection or the onboarding upgrade check.
8. **Never disable lint rules project-wide.** `analysis_options.yaml` keeps `flutter_lints`; use line-level `// ignore:` for the rare exception.

### Gotchas that will bite you

- **Startup order is a contract.** In `lib/main.dart`, do not `await` opening or migrating the database before `runApp` — that delays the window behind disk I/O. `playlistService.initialize()` and `migrateFromPrefsOnce()` are deliberately `unawaited`. The full order is documented in `ARCHITECTURE.md`.
- **Quit has one entry point: `AppLifecycleManager.quit()`** — tray → audio + media session → dispose the provider container → release the close-intercept → close the window. Container disposal already fires every `ref.onDispose`, so do not add per-service exit callbacks.
- **The desktop database must not follow `Directory.current`.** `sqflite_common_ffi` defaults to a cwd-relative `.dart_tool/sqflite_common_ffi/databases`, which silently reads a different (empty) database depending on how the app was launched. Use the injected `AppDatabase.directoryResolver`.
- **Branch on OHOS with `Platform.operatingSystem == 'ohos'`** in Dart code that compiles everywhere. Never import an OHOS-only symbol into shared code.
- **Do not re-enable Swift Package Manager.** `pubspec.yaml` pins `flutter.config.enable-swift-package-manager: false` because `flutter_app_update`'s iOS layout breaks Xcode's SPM resolver; iOS goes through CocoaPods.

## Conventions

- **Write comments, commit messages, and docs in Chinese** — the entire repo does. English-only prose is out of place.
- **Shared UI primitives use the `Bm` prefix** (`BmDialog`, `BmMenuRow`, `BmPressable`, `BmSheet`, `BmField`, `BmTokens`, `BmMotion`, …) and live in `lib/shared/ui/`, `lib/shared/widgets/`, `lib/shared/motion/`. New shared components follow the same naming and file convention (`bm_*.dart`).
- **Use the design tokens** (`BmTokens` spacing / radius / sizing, `BmMotion` durations) rather than hardcoded numbers for shared surfaces.
- **Themes are registered in `lib/shared/theme/theme_registry.dart`** — add or change a theme there, not in a feature.
- **Place new code by layer**: shared data models → `lib/domain/`; testable logic → a pure Dart class under `logic/` / `core/` / `vela/src/common/`, never bound to a widget; UI → `features/<feature>/ui/` or `lib/shared/`. Pure shared models must not depend on any other layer.

## Testing

- `test/` mirrors the concerns: `network/`, `storage/`, `player/`, `offline/`, `sync/`, `settings/`, `lyrics/`, `shell/`, plus per-feature directories.
- **Network tests are pure Dart** — inject a fixed clock and in-memory loader/saver, never hit the real network.
- **New pure logic needs a unit test**: parsing, sorting, encoding/decoding, state merging, settings serialization.
- Widget tests override dependencies with `ProviderContainer(overrides: [...])`.
- Vela assertions go into `vela/scripts/verify.mjs`; extension assertions into `extension/scripts/verify.mjs`.

## Git and PR etiquette

- **`dev` is the development trunk. Every PR targets `dev`.** `main` only carries releases — never push changes to `main` directly.
- Branch naming: `<type>/<short-description>` — `feat/`, `fix/`, `refactor/`, `docs/`, `chore/`.
- Commits: Conventional Commits with a Chinese description — `<type>(<scope>): <中文描述>`. The scope is the module or directory (`player`, `network`, `settings`, `update`, `vela`…). Explain *why* in the body, not the subject.
- Merge into `dev` with a merge commit. **Do not force-push after a review has started** — it invalidates the reviewer's context.
- Keep changes focused: no drive-by refactors, no whole-file reformatting, no unrelated baseline-lint cleanup.
- UI changes should be checked in landscape, portrait, and square layouts, and PRs with UI changes should attach before/after screenshots(compare them).

## Read before you change things

- `ARCHITECTURE.md` — layering, the playback request path, startup/exit order, network and storage model, platform differences, architecture constraints.
- `CONTRIBUTING.md` — environment setup, branch model, commit conventions, the full hard-rules list, testing requirements.
- `SECURITY.md` — what counts as a vulnerability, and the contributor's security floor.
- `vela/README.md`, `extension/README.md`, `ohos/README.md` — the per-client docs.
