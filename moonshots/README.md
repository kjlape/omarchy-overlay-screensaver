# Moonshots

Half-baked-but-promising extension ideas for the overlay-screensaver plugin.
Nothing here is implemented or committed to; each doc is a design sketch with
enough research to know whether the idea is viable.

| Doc | Idea | Status |
|---|---|---|
| [xscreensaver-hacks.md](xscreensaver-hacks.md) | Run the full xscreensaver hack collection (all ~250 of them) inside the overlay via an offscreen X stage + frame capture | Design sketch |
| [matrix-hacks.md](matrix-hacks.md) | Feasibility of the two Matrix-themed hacks (`xmatrix`, `glmatrix`) — comparison, porting paths (GLSL reimplementation vs. running the packaged binaries), licensing | Feasibility report; A1 (`xmatrix` as a shader) shipped as [`shaders/xmatrix.frag`](../shaders/xmatrix.frag) |
| [screensaver-toggle-integration.md](screensaver-toggle-integration.md) | Make `omarchy toggle screensaver` / the idle screensaver launch control the overlay instead of ttfx — toggle chain research, four designs, upstream PR options | Design sketch (researched, not implemented) |
| [screensaver-takeover-close.md](screensaver-takeover-close.md) | Refined Design 1: hard-close the stock screensaver windows at takeover (they can't survive our keyboard grab anyway) and re-own the lock; includes the fullscreen-game victim/restore mechanism | Design sketch (researched, not implemented) |
| [standalone-idle-mode.md](standalone-idle-mode.md) | The opposite pole: **zero** integration — own `ext-idle-notify` clock, own toggle, own config; runs until dismissed and lets suspend/monitor-off/auto-lock operate normally (lock-detection is provably unnecessary). Two requirements folded in because they proved cheap: Omarchy Stay Awake awareness (read-only, one state file) and `Qt.BlankCursor` pointer hiding. Includes the P-vs-standalone-daemon axis and the full cost/benefit vs the takeover designs | Design sketch (researched, not implemented) |