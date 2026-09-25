# Defect 0003: No cursor and no usable mouse input in-game (drawMouse=0 + OS cursor hidden)

- **Status:** Fixed (pending playtest) — intro movie held `mouseOff`; edge-latch keys; **mission movie never ended** because `timeGetTime()` saturated to `0xFFFFFFFF` after ~49.7 days uptime; all three fixed; smoke 0016: `EndMovieMode` → `movie in=0` → `drawMouse=1`
- **Severity:** High (player cannot see a cursor or interact with the UI)
- **Platform:** macOS arm64, native `alariq/mc2` SDL/OpenGL build (often with HiDPI / `FULLSCREEN_DESKTOP`)
- **First seen:** `run-native-macos.sh` → campaign starts; log `/tmp/mc2-input-diag.log`
- **Crash signal:** none (silent input failure)

## Symptom

Campaign/mission runs (audio, GUI init), keyboard events arrive (e.g. Space), but:

- **No visible cursor** (neither game-drawn nor OS pointer)
- **Mouse clicks / movement do not drive the UI** (command bar, selection, menus)

Diagnostic sample (every ~120 frames):

```
[IN] drawMouse=0 mouseState=43 screen=800x600 drawable=1920x1200
[UI] update mx=0.899 my=1.020 dx=0 dy=0 buttons=0x0 drawMouse=0 state=43
[IN] polled=0 focus_lost=0 mouse=(719,612) buttons=0x0 win_flags=0x3727
```

- `drawMouse=0` for the whole session → `UserInput::render()` never draws the software cursor
- On focus gain, `set_mouse_capture(true)` called `SDL_ShowCursor(SDL_DISABLE)` unconditionally → **OS cursor also hidden**
- `Environment.screenWidth/Height` (800×600) disagreed with `drawableWidth/Height` (1920×1200) and live window size
- `viewMulX/Y` started at 0 until a camera/mission viewport was set → `getMouseX()` collapsed to 0

## Root causes (stacked)

| # | Bug | Effect |
|---|-----|--------|
| 1 | Init called `userInput->mouseOff()`; logistics `start()` had `mouseOn()` commented out | Software cursor never enabled on boot / logistics entry |
| 2 | `set_mouse_capture` hid the OS cursor whenever the window had focus, independent of `drawMouse` | No fallback pointer while game cursor is off |
| 3 | Mouse position only updated from `SDL_MOUSEMOTION`; no per-frame absolute poll | Stale `mi->x_/y_` if motion events were missed |
| 4 | `gos_GetMouseInfo` / `gos_SetMousePosition` used `Environment.screenWidth/Height` only | Wrong scale when env size ≠ live `SDL_GetWindowSize` after fullscreen/HiDPI |
| 5 | `UserInput::viewMulX/Y` remained 0 until `setViewport` | `getMouseX()`/`getMouseY()` = 0 → hit-tests and cursor draw at origin |
| 6 | `MainMenu` intro movie called `mouseOff()` every frame and never `mouseOn()` when it ended (unlike `Logistics::bMovie`) | `drawMouse` stuck 0 on boot/main menu |
| 7 | Keyboard/mouse edges were **poll-only** (`SDL_GetKeyboardState` / `SDL_GetMouseState` at end of frame). Same-frame KEYDOWN+KEYUP or click down+up never exposed `KEY_PRESSED` | SPACE/ESC skip and short clicks missed by `getKeyDown` / `isLeftClick` |
| 8 | `timeGetTime()` did `DWORD ms = tv_sec * 1e+3` — on ARM64, out-of-range double→uint32 **saturates to `0xFFFFFFFF`** once `tv_sec*1000 > 4.29e9` (~49.7 days uptime). ABL `GetLogisticsTime` then always returned the same value | Mission script stage machine stuck forever in the first `GetLogisticsTime - startTime > 6000` wait (`mcprint` frozen at stage 4); `SetMovieMode` with no `EndMovieMode`; `inMovieMode=1` → `mouseOff` every frame |

Related earlier fix: Defect [0002](0002-hidpi-mouse-normalized-by-drawable.md) (normalize by window points, not drawable pixels) — necessary but not sufficient; player still reported no cursor/input.

## Fix

**Cursor visibility**

- `code/mechcmd2.cpp` — after `initMouseCursors` / `setMouseCursor(mState_NORMAL)`, call `mouseOn()` instead of `mouseOff()`.
- `code/logistics.cpp` — restore `userInput->mouseOn()` in `Logistics::start`.
- `code/mainmenu.cpp` — `mouseOn()` when intro movie ends (and in `skipIntro()`); same pattern as `Logistics::bMovie`.
- `GameOS/gameos/gameosmain.cpp` — `set_mouse_capture` only hides the OS cursor when `UserInput_drawMouse_diag` is set; every frame while focused, sync `SDL_ShowCursor` to `drawMouse` (disable only if game is drawing its own cursor).

**Mouse coordinates**

- `GameOS/gameos/gos_input.cpp` — `updateMouseState()` polls `SDL_GetMouseState(&x,&y)` every frame and writes `mi->x_/y_` (absolute position), not only motion events.
- `GameOS/gameos/gameos_input.cpp` — `gos_GetMouseInfo` / `gos_SetMousePosition` normalize/warp using live `SDL_GetWindowSize` (fallback `Environment.screenWidth/Height` if window null).

**Viewport fallback**

- `mclib/userinput.cpp` — in `UserInput::update()`, if `viewMulX/Y` is ~0, set from `Environment.screenWidth/Height`.
- `mclib/userinput.h` — `getMouseX`/`getMouseY`/`realMouseX`/`realMouseY` use `Environment.screenWidth/Height` when `viewMul` is ~0 (belt and suspenders).

**Input edge latching (Defect 0003 #6/#7)**

- `GameOS/gameos/gos_input.{h,cpp}` — per-frame `*_down_event_` / `*_up_event_` / `*_pending_release_` for keyboard scancodes and mouse buttons. Events latch `KEY_PRESSED` so same-frame down+up is visible to `getKeyDown`/`isLeftClick` this frame; release is deferred one frame.
- `GameOS/gameos/gameosmain.cpp` — re-enable `handleMouseButton` for edge latches; call `beginUpdateKeyboardState()` before polling events.

**Mission movie stuck (Defect 0003 #8)**

- `GameOS/src/platform_mmsystem.cpp` — `timeGetTime()` computes ms in `uint64_t` then truncates to `DWORD` (Win32 wrap). Do **not** assign `tv_sec * 1e+3` to `DWORD` on arm64.
- `mclib/camera.cpp` — if `startEnding && inMovieMode && letterBoxPos==0`, clear `inMovieMode` immediately (letterbox never opened → `updateLetterboxAndFade` could never end the movie).

**Diagnostics (kept for playtest)**

- Frame samples include `drawMouse`, `viewMul`, live `win=` size, `screen`/`drawable`.
- Button-state transitions log `[UI] buttons … getXY=…`.
- `mouseOn`/`mouseOff` log every *transition* with RA; intro movie / logistics movie / mission movie / load screen log periodic probes.

## Verification

- Full rebuild: `./build-native-macos.sh` → `build/native/mc2-build/mc2` (ready marker).
- `native/macos.patch` regenerated; `git -C native/mc2 apply --reverse --check` OK.
- Smoke (`/tmp/mc2-smoke-0009.log`): intro movie `mouseOff` → SPACE → `[INTRO] skip key space=1` → `mouseOn` → `[UI] render drawMouse=1` held across frames.
- Smoke (`/tmp/mc2-smoke-0016.log`, `./mc2 -mission mc2_01`): stage machine advanced (`mcprint` 0→4→7→11→12) → `[ABL] EndMovieMode` → `[CAM] movie in=0` → `[MIGUI] mouseOn path movie=0` → `drawMouse=1`; ESC path also verified (`[MIGUI] ESC -> forceMovieToEnd`, `forceEnd=1`).
- **Playtest required:**
  1. Cursor visible immediately (OS or game-drawn).
  2. Skip intro with Space/ESC/LMB; cursor stays on in main menu.
  3. Pointer tracks the OS mouse.
  4. Menus / command bar clickable.
  5. In mission: intro camera movie ends on its own (~10s) or ESC; cursor appears; left-click selects, right-click orders.
  6. Confirm no double cursor (OS + software both visible).

## Related

- Defect [0001](0001-gosimagepool-d1-brk-trap.md) — mission-load SIGTRAP (fixed)
- Defect [0002](0002-hidpi-mouse-normalized-by-drawable.md) — HiDPI normalize by drawable (fixed; precursor to this)
