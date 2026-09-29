# overlay-screensaver: shader modes draw nothing on zion

Investigated 2026-09-28. Plugin: `kjlape.overlay-screensaver` at commit `2e3da3f`,
installed at `~/.config/omarchy/plugins/kjlape.overlay-screensaver`.

## Symptom

- `omarchy-overlay-screensaver shader <name>` puts the overlay up, and `status`
  reports `"mode":"shader"`, but the shader never appears.
- Image mode works fine.

## Root cause

On zion (NVIDIA RTX 3070, driver 610.57.04, Wayland), Qt gets an **OpenGL ES
3.2** context, not desktop OpenGL:

```
qt.rhi.general: OpenGL VENDOR: NVIDIA Corporation RENDERER: NVIDIA GeForce RTX 3070/PCIe/SSE2 VERSION: OpenGL ES 3.2 NVIDIA 610.57.04
```

The committed `.qsb` files were baked with `--glsl "100,120,150,330,440"`, which
is desktop GLSL only (plus SPIR-V). Qt looks for GLSL ES variants
(`320, 310, 300, 100` es), finds none, and can't build the pipeline. The
journal (`wayland-wm@hyprland.desktop.service`) fills with about 90 of these
per second while a shader is up:

```
WARN: No GLSL shader code found (versions tried:  QList(320, 310, 300, 100) ) in baked shader QShader(stage=4 shaders=QList(ShaderKey(0 Version(100 QFlags()) 0), ShaderKey(1 Version(100 QFlags()) 0), ShaderKey(1 Version(120 QFlags()) 0), ShaderKey(1 Version(150 QFlags()) 0), ShaderKey(1 Version(330 QFlags()) 0), ShaderKey(1 Version(440 QFlags()) 0)) desc.isValid=true)
WARN: Failed to build graphics pipeline state
```

Image mode is unaffected because it uses only built-in Qt Quick shaders, which
ship with ES variants.

## Why it only showed up now

This is not a regression on zion. It is the first time the shaders have run
on this machine:

- The plugin was cloned onto zion on 2026-09-28 at 19:29 (`git reflog`:
  `clone: from github.com:kjlape/omarchy-overlay-screensaver.git`). The
  previous boot has no plugin log lines at all.
- No package, driver, or env/config changes on zion since 2026-09-16.
- A brand-new scratch Quickshell process also gets ES 3.2, so this isn't
  stale state in the running shell.
- The shaders were developed and tested on a machine where Qt gets desktop
  GL, so the missing ES variants never mattered there.
- `tools/shadercheck.qml` runs with `QT_QUICK_BACKEND=opengl
  QT_QPA_PLATFORM=offscreen`, which gets desktop GL, so the offline checker
  can't catch this either.

## Verified fix

Re-bake with GLSL ES targets added:

```bash
/usr/lib/qt6/bin/qsb --glsl "300es,310es,320es,100,120,150,330,440" shaders/<name>.frag -o shaders/<name>.frag.qsb
/usr/lib/qt6/bin/qsb --glsl "300es,310es,320es,100,120,150,330,440" shaders/<name>.vert -o shaders/<name>.vert.qsb
```

- **Tested:** starnest re-baked this way, loaded in a scratch Quickshell
  window on zion. No warnings, and it renders correctly (screenshot checked).
- **Leave out `100es`.** It fails to bake for `xmatrix` and `xmatrixcrt`
  (`Tried to convert uint literal into int, but this made the literal
  negative`), because GLSL ES 1.0 has no unsigned ints and those shaders
  use `uint`/`uvec2` hashes and glyph tables. `300es`, `310es` and `320es`
  all bake fine for every shader.

Re-bake all shaders in one go:

```bash
cd ~/.config/omarchy/plugins/kjlape.overlay-screensaver
for f in shaders/*.frag shaders/*.vert; do
  /usr/lib/qt6/bin/qsb --glsl "300es,310es,320es,100,120,150,330,440" "$f" -o "$f.qsb"
done
omarchy restart shell
```

## Follow-ups in the repo

1. Commit the re-baked `.qsb` files.
2. Update the documented bake command so future ports don't bring the bug back:
   - `AGENTS.md` (porting loop, step 4)
   - `README.md:210`
   - `.agents/skills/port-shader/SKILL.md:65-66`
   - `docs/roadmap.md:39-40, 139-140, 431, 531-532`
3. Add a troubleshooting entry: "shader overlay is blank + `No GLSL shader
   code found` in the journal = missing ES bake". Include the note that
   `tools/shadercheck.qml` uses desktop GL and can't catch this.
4. Optional: after baking, check each `.qsb` with `qsb -d` and fail if the
   GLSL ES variants are missing, as a pre-commit guard.

## Diagnostic commands used

```bash
# Journal while a shader is shown
journalctl --user -u "wayland-wm@hyprland.desktop.service" --since "-1 min" | grep -E 'No GLSL|pipeline'

# Which GL context a fresh Qt/Quickshell process gets (from ssh: borrow the session env)
eval "export $(tr '\0' '\n' < /proc/$(pgrep -f 'quickshell -n' | head -1)/environ | grep -E '^(WAYLAND_DISPLAY|XDG_RUNTIME_DIR)=' | tr '\n' ' ')"
QT_QPA_PLATFORM=wayland QSG_INFO=1 timeout 4 quickshell -n -p <scratch-dir> 2>&1 | grep 'OpenGL VENDOR'

# What a .qsb actually contains
/usr/lib/qt6/bin/qsb -d shaders/starnest.frag.qsb | grep 'Shader [0-9]'
```
