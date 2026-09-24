# Moonshots

Half-baked-but-promising extension ideas for the overlay-screensaver plugin.
Nothing here is implemented or committed to; each doc is a design sketch with
enough research to know whether the idea is viable.

| Doc | Idea | Status |
|---|---|---|
| [xscreensaver-hacks.md](xscreensaver-hacks.md) | Run the full xscreensaver hack collection (all ~250 of them) inside the overlay via an offscreen X stage + frame capture | Design sketch |
| [matrix-hacks.md](matrix-hacks.md) | Feasibility of the two Matrix-themed hacks (`xmatrix`, `glmatrix`) — comparison, porting paths (GLSL reimplementation vs. running the packaged binaries), licensing | Feasibility report; A1 (`xmatrix` as a shader) shipped as [`shaders/xmatrix.frag`](../shaders/xmatrix.frag) |
| [idle-integration.md](idle-integration.md) | Trigger the overlay on idle so it *is* Omarchy's screensaver — how `omarchy.idle` really works on Omarchy 4, the PATH-shadow recipe, why the lock needs a plugin-side hook | Design sketch (researched, not implemented) |