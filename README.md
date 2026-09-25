# MechCommander 2 for macOS (Apple Silicon)

![Mech Lab at 1920x1200](docs/screenshots/mech-lab.png)

A native arm64 port of MechCommander 2: the open-source
[alariq/mc2](https://github.com/alariq/mc2) SDL/OpenGL engine built and run
on macOS, with this machine's changes carried as
[`native/macos.patch`](native/macos.patch). The port uses SDL2/OpenGL input
and rendering, bypassing the original DirectDraw/Win32 input path entirely.

## Quick start

```sh
git submodule update --init
./build-native-macos.sh
./run-native-macos.sh
```

Requires CMake, git, and make (plus Homebrew `sdl2-compat`, `sdl2_mixer`,
and `glew`). The build script clones
[mc2srcdata](https://github.com/alariq/mc2srcdata), applies
`native/macos.patch`, builds the engine and data tools, and processes the
runtime data locally — it does not replace or redistribute Microsoft's game
assets.

Known defects and their fixes are tracked in
[docs/defects](docs/defects/README.md).

## Repository layout

- `native/mc2` — upstream engine submodule; macOS changes live in the patch,
  not in the submodule (pinned to the commit the patch applies to)
- `native/macos.patch` — input, cursor, HiDPI, movie, and resolution fixes
- `build-native-macos.sh` / `run-native-macos.sh` — build and launch
- `docs/defects/` — tracked bugs and their fixes
  ([index](docs/defects/README.md))

Earlier Wine/CrossOver experiments for this workspace (including the
launcher, test matrix, and their instructions) were removed and remain
recoverable from git history.

## Legal

Use game files you are entitled to use. Keep the original game data local;
the open-source engine does not grant redistribution rights to Microsoft's
game assets.

## Sources

- Native engine build notes:
  <https://github.com/kevinctracy/mc2/blob/master/BUILD-MAC.md>
