# MechCommander 2 on Apple Silicon

The ZIP contains the original 32-bit Windows game (`Mc2Rel.exe`) and its
runtime data. It is not a macOS application and cannot be made runnable by
renaming the EXE or placing it in an `.app` bundle.

## Free option: WineHQ build

This workspace now includes `build-macos.sh`, based on the same pattern as the
GeneralsX macOS scripts: keep the game runtime in a directory, keep the
compatibility libraries separate, set the working directory explicitly, and
launch through a wrapper. It downloads the free Gcenx WineHQ macOS build and
uses Apple's free Rosetta 2 translation for Wine's x86_64 host binaries.

Run setup and launch:

```sh
chmod +x ./build-macos.sh
./build-macos.sh
```

The first run downloads about 200 MB of Wine runtime files into `build/tools`,
downloads Winetricks and the DirectPlay redistributable, extracts the game into
`build/Mech Commander 2 RIP`, and creates its Wine prefix in `build/wine-prefix`.
The DirectPlay step fixes the game's `Cannot CreateNetLib` /
`NLERR_CANTGETCAPS` startup error. `cabextract` is installed with Homebrew if
it is missing. To set up without launching:

```sh
./build-macos.sh --setup
```

The setup also enables Wine's macOS event-tap cursor capture and DirectInput
mouse warping. macOS may require permission for this. Open **System Settings ->
Privacy & Security -> Accessibility** and enable both the terminal application
that runs this script and this bundled app:

```text
build/tools/Wine Staging.app
```

If macOS still denies input, use the Accessibility list's **+** button to add
this separate Wine helper as well:

```text
build/tools/Wine Staging.app/Contents/Resources/wine/bin/wineserver
```

Because this launcher executes Wine directly rather than through Finder, also
add this executable to both **Accessibility** and **Input Monitoring** if the
game window does not accept keyboard or mouse input:

```text
build/tools/Wine Staging.app/Contents/Resources/wine/bin/wine
```

Add the terminal application to **Input Monitoring** as well. Quit any existing
Wine processes, then restart the launcher after granting permission.

If Rosetta is not installed, install Apple's translation component once:

```sh
softwareupdate --install-rosetta --agree-to-license
```

To force windowed mode:

```sh
./run-macos.sh --windowed
```

After setup, launch the game directly with:

```sh
./run-macos.sh
```

If the old black window is still visible, close it and run:

```sh
./run-macos.sh --windowed
```

Wine's virtual-desktop mode is not supported by this setup: Wine 11.17 fails
Direct3D initialization on the Apple M4 in that mode. Use the normal windowed
launch above.

The DirectInput trace confirms that mouse clicks reach the game. If the game
still exits or stops responding after displaying, bypass Wine's failing
DirectDraw framebuffer path with the original BLADE software renderer:

```sh
./run-macos.sh --windowed --software
```

To disable MechCommander's hardware/asynchronous cursor update:

```sh
./run-macos.sh --windowed --software --no-hardware-mouse
```

Windowed launches also patch the game's detected hardware profile files, which
otherwise reset `FullScreen = TRUE` during startup, and pass the legacy
`-window /gosnojoystick` switch. Hardware launches additionally use
`/gosnoblade /gosusehw`; software launches omit both so the game's BLADE
software rasterizer remains enabled.

## Compare Engines And Settings

The optional matrix runner creates copy-on-write prefixes and records startup
failures without changing the main prefix:

```sh
TIME_LIMIT=25 ./test-matrix.sh
```

Run one case at a time for manual input testing:

```sh
./test-matrix.sh --case wine11-software-default
./test-matrix.sh --case wine11-software-force
./test-matrix.sh --case wine11-hardware-default
```

With Sikarugir available, the case names are
`sikarugir-software-default` and `sikarugir-hardware-default`.

To stage Porting Kit's installed Sikarugir engine and run its cases:

```sh
./setup-sikarugir.sh
SIKARUGIR_WINE_BIN="$PWD/build/tools/sikarugir/wswine.bundle/bin/wine64" \
  ./test-matrix.sh --case sikarugir-software-default
```

Results are written to `build/matrix/summary.tsv`. The matrix identifies
renderer and display-mode failures; input still requires a manual interaction
test.

The launcher now installs DirectPlay automatically. Do not use the old Wine
prefix from before this fix unless it has been recreated or the DirectPlay
step has completed successfully.

The script uses Wine's built-in Direct3D translation first; it does not require
CrossOver, DXVK, Vulkan, or a Windows VM. This is the free path to test first.
The supplied RIP archive is not a full installer, so the script intentionally
does not run `Setup.exe` or install the bundled Windows DLLs globally.

The WineHQ macOS package is an x86_64 host build, so Rosetta 2 is expected.
The first launch may take a while while Wine initializes the prefix. The game
was observed reaching MoltenVK/Apple M4 graphics initialization during testing;
the terminal launch was stopped after 20 seconds rather than left running.

## CrossOver fallback

CrossOver is the practical route for this archive on an M4 Mac. It translates
the Windows API and DirectX calls instead of requiring a Windows virtual
machine. CodeWeavers has a MechCommander 2 compatibility entry, although its
last public test is old and reports limited functionality, so use the trial
before purchasing.

1. Download and install CrossOver 26 or newer from
   <https://www.codeweavers.com/crossover/download-now>.
2. Extract `MechCommander-2_Win_EN_RIP-Version.zip` with Archive Utility.
3. Rename the extracted folder to `MechCommander2` and move it somewhere
   permanent, such as `~/Games/MechCommander2`.
4. In CrossOver, create a new **Windows 10 64-bit** bottle. Use a 64-bit
   bottle; the 32-bit Windows game can run inside it, while current/future
   CrossOver releases are removing standalone 32-bit bottle support.
5. Choose **Install an unlisted application**, select `Mc2Rel.exe` from the
   extracted folder, and complete the bottle setup. If the installer is not
   offered, open **Run Command** for the bottle and select `Mc2Rel.exe`.
6. Launch `Mc2Rel.exe` from CrossOver, not by double-clicking the Windows EXE
   in Finder. Keep the extracted game folder intact because the EXE uses
   relative paths to `data/`, `assets/`, and the `.fst` files.
7. On the first launch, open the game options. Prefer windowed mode and
   disable **Hardware Mouse** if the cursor flickers or disappears.

The archive is a RIP rather than a full installer. It includes the game
executable and data but does not include the original DirectX installer. Do
not install the bundled legacy DLLs over macOS; they are Windows DLLs intended
for the bottle.

## If CrossOver cannot start it

Try these in order:

1. Use a fresh Windows 7 64-bit bottle instead of the Windows 10 template.
2. Launch `Mc2Rel.exe` using CrossOver's **Run Command** so the working
   directory is the game folder.
3. Edit `options.cfg` and change the fullscreen setting to false before
   launching. The file is in the extracted game folder.
4. Use CrossOver's compatibility settings for the bottle, then retry. Do not
   add random system DLL downloads; they commonly make old games less stable.

## Native Apple Silicon port

There is an open-source 64-bit engine port at
<https://github.com/alariq/mc2> with separate runtime-data tooling at
<https://github.com/alariq/mc2srcdata>. It is potentially better than Wine
because it uses SDL/OpenGL and runs as an ARM64 program, but it is a source
port, not a converter for this ZIP. The data build expects additional generated
archives and assets, and the current source requires Apple-Silicon portability
fixes before it builds cleanly with the current Xcode toolchain.

## Apple Game Porting Toolkit

Apple's Game Porting Toolkit is primarily a developer evaluation/porting tool,
not a packaged game launcher. It can evaluate unmodified Windows executables
on Apple Silicon, but setting it up for this 2001 DirectX 8 title is more work
than CrossOver and does not remove the old game's compatibility issues:
<https://developer.apple.com/games/game-porting-toolkit/>.

## Legal note

Use game files you are entitled to use. Keep the original game data local;
the open-source engine does not grant redistribution rights to Microsoft's
game assets.

## Sources checked

- CrossOver system requirements and download: <https://www.codeweavers.com/crossover>
- CrossOver MechCommander 2 compatibility entry: <https://www.codeweavers.com/compatibility/crossover/mechcommander-2>
- Apple Game Porting Toolkit: <https://developer.apple.com/games/game-porting-toolkit/>
- Native engine build notes: <https://github.com/kevinctracy/mc2/blob/master/BUILD-MAC.md>
- Free WineHQ macOS builds: <https://github.com/Gcenx/macOS_Wine_builds>
