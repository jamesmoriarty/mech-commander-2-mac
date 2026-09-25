# Defect 0005: In-game UI does not scale at higher resolutions

- **Status:** Open
- **Severity:** Low/Medium (cosmetic/usability — everything is centered and hit-tests correctly, but HUD/menus stay small on large screens)
- **Platform:** macOS arm64, native `alariq/mc2` SDL/OpenGL build
- **First seen:** Playtest at 1920x1200 (post-[0004](0004-ui-layout-breaks-at-nonclassic-resolution.md) stopgap)
- **Screenshots** (from smoke 0019, 1920x1200 fullscreen):
  - `/tmp/mc2-esc-0019.png` — pause menu is a small panel in the top-right corner; bottom command bar art is fixed-pixel and floats with large margins
  - `/tmp/mc2-options-open.png` — options dialog correctly centered but occupies well under half the screen
  - `/tmp/mc2-now.png` — in mission: objectives text, portraits, minimap all same pixel size as at 800x600
- **Crash signal:** none (visual only)

## Symptom

At any resolution above the classic 800x600 baseline the UI keeps its original **pixel** size:

- Pause menu, options dialog, command bar, unit portraits, minimap and fonts are all the same size they were at 800x600, so they look tiny and leave large empty margins at 1024+ (worst at 1920x1200)
- Hit-testing matches the visuals (verified — see 0004), so this is purely a sizing/scale issue, not a layout-correctness one

## Root cause

Layout is authored per width in `buttonlayout<width>.fit` files: `ControlGui::swapResolutions` applies `hiResOffsetX/Y` **translations** (from each file's `HiresOffsets` block plus a `y_correction` that bottom-anchors content) but never a **scale**. Art assets and font metrics are fixed-pixel. A few scattered sites do scale ad hoc (`infowindow.cpp` `SCROLLAMOUNT *= screenWidth/640`, `mechicon.cpp` `HEALTH_BARLENGTH *= screenWidth/600`, `controlgui.cpp` mission-results/objective scroll `* screenWidth/640`), but panels, buttons and fonts don't.

The original game shipped art sets per width (`_640/_800/_1024/_1280/_1600/_1920` variants) so each classic mode had correctly proportioned art; the in-between sizing still comes from translation-only offsets.

## Why this exists alongside 0004

Defect 0004 offered two strategies:

1. **Clamp to the classic set** (stopgap, implemented) — layout is *correct* at classic widths, just small at the large ones.
2. **Virtual design space + uniform UI scale** — proper fix, deferred → this defect.

## Fix direction

Pick a design space (800x600 or 1024x768) and apply a uniform UI scale factor derived from `Environment.screenWidth/Height` to:

- panel/dialog placement (replaces the per-width `xOffset/yOffset` formulas from 0004)
- `buttonlayout*.fit` consumption in `swapResolutions` (scale rects/positions, not just translate)
- fonts and text regions (`gos_TextSet*`, font init sizes)
- hit-testing must use the same scale so mouse targets stay aligned (coordinate pipeline: `userInput` `viewMul/viewAdd` from 0002/0003)

Alternatively/additionally: ship scaled art variants and select by nearest width (extends the existing `_NNNN` appendix pattern used by `loadscreen.cpp` / `keyboardref.cpp`).

## Repro

1. `./run-native-macos.sh` → mission.
2. Set resolution to 1920x1200 (or boot with `ResolutionX=1920` in `options.cfg`).
3. ESC → pause menu: small panel top-right; observe margins around HUD/dialogs.

## Verification (when fixed)

- [ ] HUD/panel proportions at 1920x1200 match their look at 800x600 (same fraction of screen)
- [ ] All click targets still land on their visuals (compare against smoke 0019 method: log `mouse=` vs button rects)
- [ ] 800x600 unchanged (scale factor 1.0)
- [ ] No double-scaling in the sites that already scale ad hoc (`infowindow`, `mechicon`, mission-results scroll)

## Related

- Defect [0004](0004-ui-layout-breaks-at-nonclassic-resolution.md) — stopgap that clamped resolutions; source of the formula-based centering this defect would replace
- Defect [0003](0003-no-cursor-no-mouse-input.md) — `viewMul`/cursor coordinate pipeline
- Defect [0002](0002-hidpi-mouse-normalized-by-drawable.md) — drawable-vs-window coordinate spaces (scaling must not reintroduce this)
