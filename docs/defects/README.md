# Defects

Numbered, self-contained bug reports for agents working in this repo.

| ID | Title | Status |
|----|-------|--------|
| [0001](0001-gosimagepool-d1-brk-trap.md) | SIGTRAP in `GOSImagePool::~GOSImagePool` (D1 emits `brk #1`) | Fixed — virtual dtor; rebuild verified |
| [0002](0002-hidpi-mouse-normalized-by-drawable.md) | Mouse broken on Retina (normalized by drawable pixels) | Fixed — use window points; rebuild verified |
| [0003](0003-no-cursor-no-mouse-input.md) | No cursor / no mouse input (`drawMouse=0` + OS cursor hidden) | Fixed pending playtest — intro movie `mouseOn`, edge latches, `timeGetTime` saturation froze mission movie; smoke 0016 `EndMovieMode` → `drawMouse=1` |

Naming: `NNNN-short-slug.md`. When fixing, update the status line in both the
defect file and this index.
