# Defect 0001: SIGTRAP in `GOSImagePool::~GOSImagePool` (D1 emits `brk #1`)

- **Status:** Fixed — `virtual ~GOSImagePool()`; rebuild verified (full mission-load playtest still recommended)
- **Severity:** High (hard crash during mission load)
- **Platform:** macOS arm64 (Apple clang 21), native `alariq/mc2` build
- **First seen:** `run-native-macos.sh` → `Logistics::beginMission` → `mission->destroy()`
- **Crash signal:** `EXC_BREAKPOINT` / `SIGTRAP` (process exit 133)

## Symptom

Game runs ~3 minutes with audio, reaches logistics/mission transition, then traps:

```
stop reason = EXC_BREAKPOINT (code=1, subcode=0x100289480)
frame #0: 0x0000000100289480 mc2`MidLevelRenderer::GOSImagePool::~GOSImagePool(this=...) at gosimagepool.cpp:23:1
->  0x100289480 <+0>: brk    #0x1
```

Call chain (lldb `/tmp/mc2-lldb3.log`):

```
GOSImagePool::~GOSImagePool          ← traps here (D1)
MLRTexturePool::~MLRTexturePool      ← `delete imagePool`
MC_TextureManager::flush
Mission / Logistics teardown
Logistics::beginMission
```

## Root cause

`GOSImagePool` is an **abstract class with a non-virtual destructor**.

```cpp
// native/mc2/mclib/mlr/gosimagepool.hpp
class GOSImagePool {
public:
    GOSImagePool();
    ~GOSImagePool();                          // NOT virtual
    virtual bool LoadImage(GOSImage*, int=0) = 0;  // abstract
    // ...
};
```

`delete imagePool` in `MLRTexturePool::~MLRTexturePool` (`mlrtexturepool.cpp:158`)
deletes a `GOSImagePool*` that actually points at a `TGAFilePool`.

In the Itanium C++ ABI:

- **D1** = complete-object destructor (`~T()` as a complete object)
- **D2** = base-object destructor (destroying only the base subobject)
- **D0** = deleting destructor (D1 + `operator delete`) — only exists if dtor is virtual

Because `GOSImagePool` is abstract, a complete object of type `GOSImagePool` can
never exist. Apple clang therefore decides D1 is unreachable/invalid for this class
and emits a trap instead of a body:

```llvm
; LLVM IR (-O2)
define noundef ptr @_ZN16MidLevelRenderer12GOSImagePoolD1Ev(...) {
  tail call void @llvm.trap()
  unreachable
}
```

```asm
; Assembly
__ZN16MidLevelRenderer12GOSImagePoolD1Ev:
    brk    #0x1          ; 0xd4200020 — intentional trap
```

Meanwhile **D2 has the real destructor body** (hash iteration, `DeletePlugs`, etc.)
and lives at a different address (`0x100243b58` vs D1's `0x100289480`).

Because the destructor is non-virtual, `delete imagePool` emits a **direct call to D1**
(not a virtual dispatch through D0), so execution hits the trap.

The compiler also warns at the call site (suppressed/ignored in the current build flags):

```
mlrtexturepool.cpp:158: warning: delete called on 'MidLevelRenderer::GOSImagePool'
that is abstract but has non-virtual destructor [-Wdelete-abstract-non-virtual-dtor]
```

### Minimal reproduction

```cpp
struct A {
    A();
    ~A();                 // non-virtual
    virtual bool f() = 0; // abstract
    int* p;
};
A::A() : p(new int) {}
A::~A() { delete p; }

void destroy(A* a) { delete a; }  // compiles; D1 → brk #1
```

Observed with Apple clang 21.0.0, `-O0` through `-O3`, with and without
`-fpermissive`, with and without a `delete` in the same TU. Independent of
optimization level: **D1 is always `brk #1` for abstract + non-virtual dtor.**

Making the destructor `virtual` moves `delete` onto D0/vtable dispatch and
avoids the direct D1 call (D0/D2 carry the real body).

## Evidence (commands)

```bash
# 1. D1 is a trap in the object file
otool -tv build/native/mc2-build/out/mclib/mlr/CMakeFiles/mlr.dir/gosimagepool.cpp.o \
  | awk '/GOSImagePoolD1Ev:/{getline;print}'
# → 00000000000001cc  brk  #0x1

# 2. nm marks D1 as [cold func]
nm -m .../gosimagepool.cpp.o | grep GOSImagePoolD1
# → 00000000000001cc (__TEXT,__text) external [cold func] ...GOSImagePoolD1Ev

# 3. Final binary: D1=brk, D2=real
nm -n build/native/mc2-build/mc2 | grep GOSImagePoolD
# → 0000000100289480 T ...GOSImagePoolD1Ev   (brk #1 cluster)
# → 0000000100243b58 T ...GOSImagePoolD2Ev   (real body)

# 4. Call site references D1
nm .../mlrtexturepool.cpp.o | grep GOSImagePoolD1
# → U ...GOSImagePoolD1Ev

# 5. Rebuild warning
# mlrtexturepool.cpp:158: warning: ... abstract but has non-virtual destructor
```

## Impact / blast radius

The same `brk #1` pattern appears for **D1/D0 of 23 classes** clustered at the
end of `__text` (`0x100289454`–`0x1002894a8`), including at least:

| Class | Abstract? | Non-virtual dtor? | Notes |
|-------|-----------|-------------------|-------|
| `GOSImagePool` | yes | yes | **live crash** — `delete imagePool` |
| `MLREffect` | yes | yes | latent |
| `MLRLight` | yes | yes | latent |
| `MLRIndexedPrimitiveBase` | yes | yes | latent |
| `Stuff::Iterator` | yes | no (virtual `~Iterator`) | check D1 usage |
| `AppearanceType` | yes | yes | latent |
| `PilotListItem` | yes | yes | latent |
| `C*ObjectiveCondition` (several) | yes | inherits virtual dtor | latent |
| `MLRSorter` / `MLRPrimitiveBase` / iterators | mixed | mixed | verify each |

Only GOSImagePool is currently proven to have a **direct `delete` through the
abstract base** that reaches the trap D1. Others are landmines: any `delete` of
their D1 will trap the same way.

Related dead-code artifacts in the same `.o`: template `HashIteratorOf` /
`HashOf` D1 symbols are emitted as `b <self>` (infinite loop) — same
"unreachable complete-object dtor" class of emission.

## Recommended fix (applied)

Preferred (correct C++): make the destructor virtual so `delete` uses D0/vtable:

```cpp
// gosimagepool.hpp
virtual ~GOSImagePool();
```

Consequences:
- Enables D0 (deleting destructor) so `~TGAFilePool` + `operator delete` run correctly.
- `delete imagePool` becomes virtual dispatch instead of a direct D1 call.
- Must rebuild; D1 may still be a trap for abstract classes (harmless if unused).

**Applied in:** `native/mc2/mclib/mlr/gosimagepool.hpp` (submodule working tree → `native/macos.patch`).

Post-fix verification (Release binary):

- `-Wdelete-abstract-non-virtual-dtor` warning for `mlrtexturepool.cpp:158` is gone.
- `mlrtexturepool.cpp.o` no longer has `U ...GOSImagePoolD1Ev`.
- `delete imagePool` site is now vtable dispatch:
  `ldr x8,[x0]; ldr x8,[x8,#0x8]; blr x8`
- `TGAFilePoolD0` (`0x10024420c`) calls `GOSImagePoolD2` then `__ZdlPv` — real path.
- `TGAFilePoolD1` (`0x100244208`) is `b GOSImagePoolD2` — real path.
- `GOSImagePoolD2` (`0x100243b60`) has the full hash-cleanup body.
- `GOSImagePoolD1`/`D0` remain `brk #1` in the cold cluster — never reached for `TGAFilePool` dynamic type (all production pools are `new TGAFilePool(...)` in `txmmgr.cpp` / `mechcmd2.cpp`).

Alternative (narrower): change ownership so `MLRTexturePool` stores/deletes a
concrete `TGAFilePool*`, or add an explicit virtual `Destroy()` API on
`GOSImagePool` and call that instead of `delete`.

Also enable `-Wdelete-abstract-non-virtual-dtor` (or `-Weverything` in CI) so
remaining landmines surface at compile time.

## Verification plan

1. ~~Apply fix (`virtual ~GOSImagePool()`).~~ **done**
2. ~~Rebuild: `rm -f build/native/.ready && ./build-native-macos.sh`~~ **done**
3. ~~Confirm warning gone.~~ **done** — no `delete-abstract` in build log.
4. ~~Confirm call site is vtable dispatch / `TGAFilePoolD0`.~~ **done**
5. **Recommended:** run through mission load; expect no `EXC_BREAKPOINT` at old `GOSImagePoolD1` address.
6. Optionally audit the other 22 classes with `brk` D1/D0.

## Environment notes

- Build flags (from `flags.make`): `-std=c++0x -O3 -DNDEBUG -arch arm64 -fpermissive`
  — no `-fno-exceptions`, no LTO, no `-dead_strip`.
- `ENTER_DEBUGGER`/`_ARMOR` are unrelated; Release build active (`NDEBUG`).
- This is **not** the earlier Wine-input problem; it is a native codegen/ABI defect.

## Related files

| Path | Role |
|------|------|
| `native/mc2/mclib/mlr/gosimagepool.hpp` | class decl (non-virtual dtor, pure virtual) |
| `native/mc2/mclib/mlr/gosimagepool.cpp:22-26` | D2 body; D1 is separate trap |
| `native/mc2/mclib/mlr/mlrtexturepool.cpp:158` | `delete imagePool` call site |
| `native/mc2/mclib/mlr/mlrtexturepool.hpp` | `GOSImagePool *imagePool` member |
| `build/native/mc2-build/.../gosimagepool.cpp.o` | D1 = `brk #1` at `0x1cc` |
| `/tmp/mc2-lldb3.log` | full backtrace |
