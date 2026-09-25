# MechCommander 2 on Apple Silicon

## Native Apple Silicon port

The workspace includes the source port as a Git submodule:
<https://github.com/alariq/mc2>. Its generated runtime data comes from
<https://github.com/alariq/mc2srcdata>. Build and run the native ARM64 engine:

```sh
git submodule update --init
./build-native-macos.sh
./run-native-macos.sh
```

The native path uses SDL2/OpenGL input and rendering, so it bypasses the
original DirectDraw/Win32 input path entirely. It builds the source data
locally and does not replace or redistribute Microsoft's game assets.

Requires CMake, git, and make (plus Homebrew `sdl2-compat`, `sdl2_mixer`,
and `glew`). The build script clones `mc2srcdata`, applies
`native/macos.patch`, builds the engine and data tools, and processes the
runtime data.

Known defects and their fixes are tracked in
[docs/defects](docs/defects/README.md).

Earlier Wine/CrossOver experiments for this workspace (including the
launcher, test matrix, and their instructions) were removed and remain
recoverable from git history.

## Legal note

Use game files you are entitled to use. Keep the original game data local;
the open-source engine does not grant redistribution rights to Microsoft's
game assets.

## Sources checked

- Native engine build notes: <https://github.com/kevinctracy/mc2/blob/master/BUILD-MAC.md>
