# Defects

Numbered, self-contained bug reports for agents working in this repo.

| ID | Title | Status |
|----|-------|--------|
| [0001](0001-gosimagepool-d1-brk-trap.md) | SIGTRAP in `GOSImagePool::~GOSImagePool` (D1 emits `brk #1`) | Fixed — virtual dtor; rebuild verified |
| [0002](0002-hidpi-mouse-normalized-by-drawable.md) | Mouse broken on Retina (normalized by drawable pixels) | Fixed — use window points; rebuild verified |
| [0003](0003-no-cursor-no-mouse-input.md) | No cursor / no mouse input (`drawMouse=0` + OS cursor hidden) | Fixed pending playtest — intro movie `mouseOn`, edge latches, `timeGetTime` saturation froze mission movie; smoke 0016 `EndMovieMode` → `drawMouse=1` |
| [0004](0004-ui-layout-breaks-at-nonclassic-resolution.md) | UI layout breaks at non-classic resolutions (e.g. 2560x1664) | Fixed pending playtest — stopgap: classic mode list + prefs snap + formula centering + table-driven `swapResolutions`; smoke 0019 |
| [0005](0005-in-game-ui-does-not-scale-at-higher-resolutions.md) | In-game UI stays fixed-pixel (tiny) at higher resolutions | Open — needs virtual design-space + uniform UI scale (deferred proper fix of 0004) |

Naming: `NNNN-short-slug.md`. When fixing, update the status line in both the
defect file and this index.
