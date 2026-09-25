# Defect 0002: Mouse input broken on Retina (normalized by drawable pixels)

- **Status:** Fixed — normalize by `Environment.screenWidth/Height` (window points); rebuild verified. Playtest still showed no cursor — see Defect [0003](0003-no-cursor-no-mouse-input.md)
- **Severity:** High (cannot select units or click the command bar — no mission control)
- **Platform:** macOS arm64 with HiDPI/Retina (`SDL_WINDOW_ALLOW_HIGHDPI`), native `alariq/mc2` build
- **First seen:** `run-native-macos.sh` → campaign mission starts; clicks do not hit mech/command UI
- **Crash signal:** none (silent input failure)

## Symptom

Campaign loads and mission runs (audio, GUI, `setOnGUI` / objective init prints), but the player
cannot take control of mechs:

- Clicks land in the wrong place (effectively only the top-left region of the window is addressable)
- Bottom command bar / force-group icons unreachable
- World click-select and order issuing fail or hit the wrong target

## Root cause

`gos_GetMouseInfo` normalized SDL mouse coordinates by **drawable** size (backing pixels) while
the rest of the game uses **window points**:

| Value | Source | Units |
|-------|--------|-------|
| `event->motion.x` / `mi->x_` | SDL mouse events | window points |
| `Environment.screenWidth` | `SDL_GetWindowSize` | window points |
| `Environment.drawableWidth` | `SDL_GL_GetDrawableSize` | backing pixels (2× on Retina) |
| `viewMulX` / `viewAddX` | `gos_GetViewport` → `width_` (= `screenWidth`) | window points |

```cpp
// Bug: normalizing points by pixels
const float w = (float)Environment.drawableWidth;   // 2× on Retina
*pXPosition = mi->x_ / w;   // only reaches ~0.5 at right edge
```

On a 2× display, `mouseXPosition` only spans ~`[0, 0.5]`, so
`getMouseX() = mouseXPosition * viewMulX` only covers the top-left quarter of the screen.
All hit-testing (`MissionInterfaceManager`, `ControlGui`, `UserInput` click/drag) inherits this.

Secondary: `setMousePos` converts screen → normalized `0..1` via `/viewMulX`, but
`gos_SetMousePosition` passed that value straight to `SDL_WarpMouseInWindow` (which wants
window points), so scripted/tutorial cursor warps snapped near the origin.

## Fix

`GameOS/gameos/gameos_input.cpp`:

1. `gos_GetMouseInfo` — normalize and clamp deltas with `Environment.screenWidth/Height`.
2. `gos_SetMousePosition` — scale normalized `0..1` by `screenWidth/Height` before
   `SDL_WarpMouseInWindow`.

## Verification

- Full rebuild: `./build-native-macos.sh` → binary `build/native/mc2-build/mc2`
- `native/macos.patch` regenerated; reverse-apply check OK
- **Playtest required:** in-mission, confirm cursor tracks the OS pointer, left-click selects
  a mech, right-click (AOE profile) issues a move, and the bottom command bar is clickable

## Related

- Defect [0001](0001-gosimagepool-d1-brk-trap.md) — earlier mission-load SIGTRAP (fixed)
- `SDL_WINDOW_ALLOW_HIGHDPI` set in `GameOS/gameos/gos_render.cpp` window creation
