# MechCommander 2 for macOS (Apple Silicon)

A native arm64 port of MechCommander 2: the open-source
[alariq/mc2](https://github.com/alariq/mc2) SDL/OpenGL engine, built and run
on macOS. macOS fixes are carried as [`native/macos.patch`](native/macos.patch)
rather than committed into the engine submodule. The port renders through
SDL2/OpenGL, bypassing the original DirectDraw/Win32 path entirely.

## Download & play

Grab the signed, notarized build from the
[latest release](https://github.com/jamesmoriarty/mech-commander-2-mac/releases/latest):

1. Download and unzip `MechCommander2-mac.zip`.
2. Double-click `MechCommander2.app`. On first run it downloads the game
   data (~630 MB) from the
   [alariq/mc2 release](https://github.com/alariq/mc2/releases) into
   `~/Library/Application Support/MechCommander2/`.

The app bundles every required library (no Homebrew needed) and is signed
with a Developer ID + notarized by Apple, so Gatekeeper opens it without
warnings. The game data is Microsoft's, not redistributed here — see
[Legal](#legal).

## Screenshots

![Gameplay at 800x600](docs/screenshots/gameplay.png)

![Mech Lab at 1920x1200](docs/screenshots/mech-lab.png)

Gameplay video: [docs/screenshots/gameplay.mp4](docs/screenshots/gameplay.mp4)

## Building from source

```sh
git submodule update --init
make deps      # install Homebrew build dependencies
make native    # build the engine + process game data
make run       # launch
```

Requirements: CMake, git, make, and ffmpeg, plus the Homebrew formulas
`sdl2-compat`, `sdl2_mixer`, `sdl2_ttf`, and `glew`. `make deps` installs
them, and the build script checks and names anything missing (ffmpeg converts
the intro movie videos). The build clones
[mc2srcdata](https://github.com/alariq/mc2srcdata), applies
`native/macos.patch`, builds the engine and data tools, and processes the
runtime data locally — it does not replace or redistribute Microsoft's game
assets.

Known defects and their fixes are tracked in
[docs/defects](docs/defects/README.md).

## Packaging a release

```sh
make dist            # → dist/MechCommander2.app, .zip, and mc2-data.tar.gz
make dist-no-data    # same, but skip the game-data archive
```

The app bundles all Homebrew libraries — including the SDL3 library that
Homebrew's SDL2-compat shim loads at runtime — so it runs on Apple Silicon
Macs without a developer environment. Game data is fetched on first launch
from the URL in `Contents/Resources/data-url.txt` (override with
`MC2_DATA_URL`, or point it at your own `mc2-data.tar.gz`).

Pushing a `v*` tag runs the same package build on GitHub Actions and uploads
`MechCommander2-mac.zip` to a GitHub release:

```sh
git tag -a v0.1.2-mac -m "..." && git push origin v0.1.2-mac
```

The CI job never builds or uploads `mc2-data.tar.gz` (Microsoft assets stay
out of releases).

### Signing & notarization

When a `Developer ID Application` certificate is present — in the local
keychain, or imported on CI from the `MC2_SIGN_P12_BASE64` /
`MC2_SIGN_P12_PASSWORD` secrets — the build signs the whole bundle (hardened
runtime + secure timestamp); otherwise it falls back to ad-hoc signing. To
also notarize (removing all Gatekeeper prompts), provide Apple notarytool
credentials: `MC2_NOTARY_API_KEY_B64`, `MC2_NOTARY_KEY_ID`, and
`MC2_NOTARY_ISSUER_ID` on CI, or `MC2_NOTARY_PROFILE=<name>` locally.
Notarized builds are stapled and re-zipped automatically.

## Repository layout

- `native/mc2` — upstream engine submodule (pinned to the commit the patch
  applies to; macOS changes live in the patch, not the submodule)
- `native/macos.patch` — input, cursor, HiDPI, movie, and resolution fixes
- `native/icon/` — app icon sources (`AppIcon.iconset`)
- `native/launcher/` — the Swift bundle launcher + download progress UI
- `Makefile` — convenience targets (`make help`) delegating to `scripts/`
- `scripts/build-native-macos.sh` / `scripts/run-native-macos.sh` — build and
  launch
- `scripts/build-dist-macos.sh` — build the relocatable `.app` + archives
- `docs/defects/` — tracked bugs and their fixes
  ([index](docs/defects/README.md))

## Legal

The engine and `native/macos.patch` are GPL-3.0 (see
[LICENSE](LICENSE)). MechCommander 2 game data is Microsoft's — use files you
are entitled to; this project neither bundles nor redistributes it.

## Sources

- Upstream engine: <https://github.com/alariq/mc2>
- Game data source: <https://github.com/alariq/mc2srcdata>
- Native engine build notes:
  <https://github.com/kevinctracy/mc2/blob/master/BUILD-MAC.md>
