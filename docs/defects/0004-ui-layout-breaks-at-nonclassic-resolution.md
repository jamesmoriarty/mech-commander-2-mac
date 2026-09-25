# Defect 0004: UI layout breaks when graphics resolution is set above classic widths

- **Status:** Fixed pending playtest (stopgap — clamp to classic resolution set; proper UI-scaling fix deferred to [0005](0005-in-game-ui-does-not-scale-at-higher-resolutions.md))
- **Severity:** Medium (menus/HUD misaligned; game remains playable but ratios are wrong)
- **Platform:** macOS arm64, native `alariq/mc2` SDL/OpenGL build (HiDPI / `FULLSCREEN_DESKTOP`)
- **First seen:** Options → Graphics → Resolution = **2560x1664x32** (max display mode), then back to mission
- **Screenshots:**
  - [`docs/screenshots/mech-lab.png`](../screenshots/mech-lab.png) — after fix: Mech Lab at 1920x1200 renders correctly framed across the full framebuffer
  - `/Users/jamesmoriarty/Desktop/Screenshot 2026-09-25 at 3.53.48 PM.png` — in mission: bottom command bar occupies only the left ~55% of the screen; pause menu (top-right) cramped; world/UI ratios look wrong
  - `/Users/jamesmoriarty/Desktop/Screenshot 2026-09-25 at 3.53.57 PM.png` — Graphics tab showing resolution `2560X1664X32`, video card `APPLE M4`; dialog framed as if still on a classic layout
- **Crash signal:** none (visual/layout only)

## Symptom

Setting the graphics resolution to the maximum advertised mode (here `2560x1664x32`) produces incorrect UI ratios:

- Mission HUD (command bar, unit portraits, minimap) does not span/fill the screen — elements sized/offset for an older layout leave large empty margins
- Options dialog art and buttons are mis-framed relative to the new framebuffer
- Subsequent screens (load screen, mission GUI) may use mismatched art/layout files

Default path (never touch Options → Resolution) still looks correct — see Defect [0003](0003-no-cursor-no-mouse-input.md) verification.

## Root causes (stacked)

The port enumerates **real display modes** via `gos_GetDisplayModeByIndex` (includes non-classic sizes like 2560x1664), but UI layout code and art only support the classic set **{640x480, 800x600, 1024x768, 1280x1024, 1600x1200, 1920x1200}**.

| # | Bug | Effect |
|---|-----|--------|
| 1 | `OptionsXScreen` art centering (`code/optionsarea.cpp`) `switch (Environment.screenWidth)` had cases for 640/1024/1280/1600 only — **no default, no 1920/2560** (and `case 1024` was `x = 13`, a typo vs its own comment `113`) | At 2560, `xOffset/yOffset` stayed 0 → dialog art placed for the 800-class canvas on a larger framebuffer (screenshot 2) |
| 2 | `ControlGui::swapResolutions` (`code/controlgui.cpp`) picked `buttonlayout*.fit` by **exact** width with `else → buttonlayout1920.fit`, and `y_correction` per-width if/else chains | Unknown width took the 1920 layout on a 2560 screen → X layout left-weighted (screenshot 1) |
| 3 | Resolution dropdown offered **every SDL display mode** (`gos_GetNumDisplayModes`) — non-classic widths selectable with no layout support | User could pick 2560x1664 at all — the repro |
| 4 | `LoadScreenWrapper::changeRes` (`code/loadscreen.cpp`) appendix table `{640,1024,1280,1600,1920}` **omits 800**; `KeyboardRef::init` (`code/keyboardref.cpp`) same table, also omits 800 (`mcui_keyref_800.fit` exists but was never used) | At the default 800x600 both fall through to the `_1024` art — latent wrong-art bug even before any resolution change |
| 5 | Saved `options.cfg` could carry `ResolutionX=2560, ResolutionY=1664` | Every later boot started from a non-classic resolution |

Corrected findings from the original investigation (both turned out to be dead code, so they were **not** fixed and are not causes):

- `prefs.resolution` enum mapping in `optionsarea.cpp`/`missiongui.cpp:3087`/`loadscreen.cpp:95` is inside `/* */` comments, and `prefs.resolution` itself is commented out in `prefs.h` — the "stale enum" theory was moot.
- `logmain.cpp`'s `switch (resolutionX)` (default → 640x480) is **not in the CMake sources** — dead file.
- `Environment.screenWidth/Height` do update on mode change (`gameos_graphics.cpp` `handleEvents` → `resize_window`), so the mismatch was purely layout assets/logic, never a stale Environment. Logical resolution is decoupled from the physical drawable; any logical size runs, layout code is what breaks.

## Repro (before fix)

1. `./run-native-macos.sh` → skip intro → campaign mission (or any mission).
2. Options → Graphics → set **Resolution** to the largest mode (e.g. `2560x1664x32`), apply.
3. Return to the mission / open pause menu.
4. Observe: command bar and HUD not aligned to screen edges; options dialog re-open looks mis-framed.

## Fix applied (stopgap — "Option A": clamp to the classic set)

Chosen over the proper fix (virtual design-space + uniform UI scaling, now [0005](0005-in-game-ui-does-not-scale-at-higher-resolutions.md)) to restore correct layout with minimal blast radius.

1. **Classic mode list instead of SDL modes** — `OptionsGraphics::init` now synthesizes the original table: `{640x480, 800x600, 1024x768, 1280x1024, 1600x1200, 1920x1200}` × `{16,32}` bpp (mirrors the commented original `resModes[10]`, plus 1920). `gos_GetNumDisplayModes`/`gos_GetDisplayModeByIndex` no longer used by the game. `OptionsGraphics::reset()` got a second-pass match on xRes/yRes ignoring `bitDepth`.
2. **Snap on load** — `CPrefs::load` (`code/prefs.cpp`) runs `snapToClassicResolution()` after reading `ResolutionX/Y`: nearest classic width, canonical height pair (`{640,800,1024,1280,1600,1920}` → `{480,600,768,1024,1200,1200}`). Self-heals a bad `options.cfg` (2560x1664 → 1920x1200) on next boot; the value is re-written on next save.
3. **Options centering by formula** — `OptionsXScreen::init`: `if (screenWidth != 800) { xOffset = (W-800)/2; yOffset = (H-660)/2; }` — reproduces every original case exactly (640 → -80,-90; 1024 → 112,54; 1280 → 240,182; 1600 → 400,270) and covers 1920 (560,270) and anything else; 800x600 stays (0,0). Fixes the 1024 typo.
4. **`swapResolutions` table-driven** — nearest-classic-width selection over `{640,800,1024,1280,1600,1920}` with design bases `{480,600,768,768,768,768}`; `y_correction = resolutionY - (base + hiResOffsetY)` unchanged in semantics (bottom-anchors content), no more per-width if/else chains.
5. **Art appendix tables gain 800** — `loadscreen.cpp` → `800 → ""` (base `mcl_loadingscreen.fit`); `keyboardref.cpp` → `800 → "_800"`.

## Verification

- [x] Rebuild clean; `native/macos.patch` regenerated, `git apply --reverse --check` → `REVERSE_OK` (1890 lines)
- [x] Boot with `options.cfg` = `2560x1664` → log shows `screen=1920x1200 drawable=1920x1200 win=1920x1200` (snap applied) — smoke 0017/0019
- [x] Mission loads, intro movie plays and ends naturally, `drawMouse=1` after movie (0003 path unaffected)
- [x] Options screen (from pause menu) renders **centered** at 1920x1200; Graphics tab shows `1920X1200X32` (synthesized entry selected by `reset()`)
- [x] Mouse/UI hit-tests match: game logs `mouse=(1843,209)` for the pointer at the pause-menu OPTIONS button; hover help-text and button activation track the visuals exactly
- [x] Options screen closes and returns to the mission (ACCEPT/CANCEL)
- [ ] User playtest: cycle 800 → 1920 → 800 in Options from the **main menu** (resolution dropdown is intentionally locked in-mission: "RESOLUTION CANNOT BE CHANGED DURING A MISSION")
- [ ] Load screen art not stretched/clipped after a resolution change
- [ ] Default path (never touch resolution) unchanged — re-run 0003 checklist

## Related

- Defect [0005](0005-in-game-ui-does-not-scale-at-higher-resolutions.md) — HUD/UI stays fixed-pixel at high resolutions (the deferred proper fix)
- Defect [0003](0003-no-cursor-no-mouse-input.md) — cursor/input; establishes `Environment.screenWidth` (800) vs window (1920x1200) split and `viewMul`
- Defect [0002](0002-hidpi-mouse-normalized-by-drawable.md) — HiDPI normalize by window points (coordinate spaces)
