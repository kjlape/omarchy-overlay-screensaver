# Design: idle takeover with hard-close of the stock screensaver

> Refinement of Design 1 in [screensaver-toggle-integration.md](screensaver-toggle-integration.md)
> ("idle takeover"), with one deliberate deviation: **the stock
> `org.omarchy.screensaver` windows are killed at takeover, not left open
> behind the overlay.** Not implemented.

## Why the deviation is mandatory, not a preference

The parent doc's Design 1 kept the stock windows open to preserve
`omarchy.idle`'s lock bookkeeping (window count > 0 → lock timer stays
armed). Two facts — both verified in the installed sources — break that
premise for this plugin:

1. **Our overlay steals keyboard focus.** `Service.qml` maps the overlay
   with `WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive` (line
   ~286, needed so Escape reaches us and not the game underneath). A
   layer-shell surface with an exclusive keyboard grab takes the keyboard
   seat; the ttfx terminal behind it loses focus.
2. **The stock wrapper self-destructs on focus loss.**
   `/usr/share/omarchy/bin/omarchy-screensaver` runs a 1-second input loop
   whose exit condition is `read -n1 -t 1 || ! screensaver_in_focus` — the
   moment the screensaver window is not the focused window, the wrapper
   runs `exit_screensaver` (kills ttfx, restores the cursor) and exits.
   Within ~1s of our overlay mapping, ttfx is dead *no matter what we do*.

Consequence: in the parent design, the windows do **not** stay open. Their
`closewindow` events fire ~1s after takeover →
`handleScreensaverWindowClosed` → count hits 0 →
`cancelIdleCycle("screensaver-dismissed")` → **the pending lock is silently
canceled** and `omarchy-system-wake` runs. So the parent design's step 2
("their open windows keep the lock armed") is unachievable while our overlay
holds the keyboard; the lock bookkeeping is lost either way. Given that,
killing the stock windows *immediately and deterministically* is strictly
better than letting them die from an accident of focus timing: same lock
outcome (cycle canceled), but no half-dead wrapper, no 1s window where an
unfocused ttfx renders behind the overlay, and no dependence on
`screensaver_in_focus`'s `hyprctl activewindow` racing our layer grab.

The price is that **the lock must be re-owned by the plugin** (the built-in
lock timer is canceled with the cycle). That is the core of this design and
is handled below without forking the idle service and without reading
config behind the shell's back.

Separately, the user-motivating bug — stock screensaver windows going
fullscreen breaking fullscreen games — is addressed head-on in the
"Fullscreen-game safety" section: the damage is done by a stock window rule
at map time and cannot be prevented by fast killing; it is repaired with a
restore pass instead.

## Verified mechanics this design rides on

All from `/usr/share/omarchy/` (Omarchy 4.0.4-1), cross-checked against
`shell/plugins/services/idle/Service.qml`:

- `omarchy.idle` reacts to Hyprland socket2 `openwindow`/`closewindow`
  events for class `org.omarchy.screensaver` and *only* to those. Killing
  the windows produces the exact same "screensaver dismissed" signal the
  user produces by touching a key — the documented, first-party
  cancellation path (`handleScreensaverWindowClosed` →
  `cancelIdleCycle("screensaver-dismissed")`).
- On that cancellation the idle service itself runs
  `omarchy-system-wake`. **Wake is free** in this design — brightness and
  keyboard restoration happen at takeover, not at dismissal. (Harmless:
  the overlay is showing, and `omarchy-system-wake` never kills the
  screensaver or touches windows.)
- `omarchy-system-lock`'s teardown is
  `pkill -x ttfx; timeout 1s pidwait -x ttfx; pkill -f
  '[o]rg.omarchy.screensaver'` — killing by name/class is Omarchy's own
  cleanup idiom, reused verbatim. Note the ordering: kill ttfx first, wait,
  then kill the wrapper — killing the wrapper first would skip its SIGTERM
  trap (which restores `cursor:invisible`).
- The wrapper *re-launches* ttfx in a loop if ttfx dies alone
  (`while true; do ttfx … done`). Killing `ttfx` without killing the
  wrapper just restarts the effect. The wrapper (`pkill -f
  org.omarchy.screensaver`, which matches the terminal's `--class` argv)
  must be killed too. `omarchy-system-lock`'s sequence does this correctly.
- `omarchy-launch-screensaver` spawns terminals **per monitor in a loop**,
  focusing each monitor first (`hypr_focus_monitor`) and waiting for each
  window. Killing the first ttfx does not stop the loop: monitors 2..n
  still spawn fullscreen windows, each one demoting a fullscreen game on
  its monitor. The takeover must therefore keep killing every
  `org.omarchy.screensaver` `openwindow` for a suppression window (~5s), or
  kill the launcher script itself.
- The launcher also fights over monitor focus: it focuses every monitor in
  turn, then tries to restore the original. Whatever we do must restore
  focus ourselves (see the restore pass).
- The fullscreen state of the stock windows comes from a **stock Hyprland
  window rule applied at map time** — `default/hypr/apps/system.lua:35`
  (`o.window("org.omarchy.screensaver", { fullscreen = true })`, plus
  `float`). No reaction speed prevents it; the demotion of the game's
  fullscreen happens the instant the ttfx window maps, before any event we
  can observe.
- `omarchy-shell idle status` (IPC target `idle`, function `statusJson()`)
  exposes, live: `inIdleCycle`, `screensaverStarted`, `screensaver`,
  `lock`, `screensaverDelay`, **`lockDelay`**, `screensaverWindows`, and
  `timers.lock` (whether the lock timer is running). This is the clean
  source for both "is this an idle launch or a manual `force` launch?" and
  "how many seconds remain to lock" — **no shell.json reading, no config
  divergence**, the values come from the running service itself. (Remember
  the AGENTS.md rule: `omarchy-shell` IPC can exit 0 on failure — parse the
  result string, never trust the exit code.)

## The design

### Component 1 — victim registry (the game-safety core)

Goal: know, at takeover, exactly which windows were fullscreen (and which
held keyboard focus) *before* the ttfx windows mapped, so we can put them
back afterwards. Pure event tracking on the `Connections { target:
Hyprland; function onRawEvent }` we add for the takeover trigger — no
polling:

- `activewindowv2>>ADDR` (fires on every focus change): record
  `lastFocusedAddr`.
- `fullscreen>>1` (fires when *any* window enters fullscreen; payload is
  the state only, **no address**): correlate with `lastFocusedAddr` — a
  window entering fullscreen is virtually always the focused window — and
  set `victim[addr] = true`.
- `fullscreen>>0`: clear the flag for `lastFocusedAddr`.
- `closewindow>>ADDR`: delete from `victim` and `lastFocusedAddr` if
  matching.

State is process-local only (dies with the plugin, recomputed from events —
consistent with the recovery guarantee: nothing persisted). On a shell
restart mid-session the registry starts empty; the worst case is a missed
restore for games that entered fullscreen before the plugin (re)started,
which is the same as today's behavior without the plugin. Optionally
seeded at startup with one `hyprctl clients -j` snapshot (address,
monitor, `fullscreen` flag) to cover the pre-plugin fullscreen case.

### Component 2 — takeover trigger (openwindow watcher, then hard close)

On the **first** `openwindow>>ADDR,WS,org.omarchy.screensaver,…`:

1. **Show the overlay** (`overlayVisible = true`, source
   `"idle-takeover"`). Immediately — this bounds the flash frame. The
   overlay's keyboard grab also lands here, which is what will soon kill
   ttfx anyway; doing it deliberately is the point.
2. **Query the idle service**: spawn a `Process` running
   `omarchy-shell idle status`, capture stdout. This must complete
   *before* the kill (below) — killing flips `inIdleCycle` to false, and
   we need the pre-kill values. Expect ~10–50ms.
3. **Hard-close the stock screensaver**, Omarchy's own sequence, plus the
   launcher and cursor repair:
   ```
   pkill -f 'omarchy-launch-screensaver'          # stop the per-monitor spawn loop
   pkill -x ttfx; sleep 0.3; pkill -x ttfx        # ttfx first (wrapper would respawn it)
   pkill -f '[o]rg.omarchy.screensaver'           # then the wrapper/terminals (TERM → trap → cursor restore)
   hyprctl keyword cursor:invisible false         # belt-and-braces if the trap lost the race
   ```
   Run via one `Process`. Every *subsequent* `org.omarchy.screensaver`
   `openwindow` within ~5s of the first triggers the kill sequence again
   (idempotent `pkill`s) — this sweeps up monitor 2..n windows that were
   already mid-spawn when we killed the launcher. After the suppression
   window, ignore the class until the next takeover.
4. **Parse the captured status** and decide the mode:
   - `timers.lock == true` (idle launch, lock armed): start our lock
     countdown (Component 3) for `lockDelay` seconds.
   - otherwise (manual menu launch, `omarchy branding screensaver …`):
     no countdown — pure manual overlay show, exactly like IPC `show`.
   - status unparseable / IPC failed: fall back to defaults
     (`lockDelay = lock − screensaver`, 300 − 150 = 150s) and log. The
     fallback constant matches `Service.qml`'s own defaults.

### Component 3 — the lock, re-owned (without owning the clock)

The built-in lock timer is dead the moment we kill the windows (the cycle
canceled). We re-arm a lock of our own whose *duration and trigger* come
from the running idle service, not from our config:

- `Timer` with `interval = lockDelay * 1000` from Component 2. This is
  deliberately **not** an `IdleMonitor` and not a second idle clock: the
  screensaver *trigger* remains 100% Omarchy's (`omarchy.idle` launched
  the thing we took over), the *duration* is read live from the service
  that computed it, and the countdown starts at the same moment the
  built-in one was running. The only divergence left is that upstream
  won't restart our timer if the user changes `idle.lock` mid-cycle — an
  edge case the built-in doesn't handle either.
- On expiry:
  1. Guard: `omarchy-shell lock isLocked` → if already true (user locked
     manually mid-idle, hyprlock already up), just hide the overlay and
     skip. Never double-lock.
  2. Hide the overlay first — this fixes H1/H2 from
     [idle-integration.md](idle-integration.md) **by construction**: the
     overlay is never up when hyprlock maps, and can't swallow the lock
     screen's keystrokes.
  3. Run `omarchy-system-lock` (its ttfx/pgrep teardown is a no-op —
     everything is already dead — and it runs the real lock).

### Component 4 — dismissal (all existing paths, plus two gratis)

Every existing dismissal (Escape, click, mouse-move via the `cursorpos`
poller, IPC `hide`) additionally:

- Stop our lock timer (it must never fire after the user came back —
  mirror of the built-in "screensaver dismissed cancels the lock").
- No teardown needed — the stock windows died at takeover. The wake is
  also already handled: the idle service ran `omarchy-system-wake` when
  the `closewindow` events canceled the cycle at takeover. So dismissal
  is just "stop timer, hide".
- User activity *without* an explicit dismissal (e.g. the user mashes a
  key that the overlay ignores): our mouse-move poller covers pointer
  activity; any keystroke reaches the overlay's key catcher (keyboard is
  exclusive) and dismisses. There is no path where the user is back and
  the overlay/timer doesn't know — an improvement on the stock
  arrangement, where dismissal depends on ttfx's focus trap noticing.

### Component 5 — the restore pass (fixing the games)

Demotion is unavoidable (window rule at map time); recovery is not. After
the stock windows are gone (overlay still up, covering everything, so the
user sees none of it):

1. For each `victim` address still alive: read its monitor from a
   `hyprctl clients -j` snapshot (their `fullscreen` field is now false,
   but `monitor` and `workspace` are intact; skip clients that closed).
2. Re-apply fullscreen and hand focus back:
   ```
   hyprctl dispatch focuswindow address:0xADDR
   hyprctl dispatch fullscreen 1        # mode 1 = real fullscreen (verify mode number at implementation)
   ```
   Re-issuing fullscreen is exactly what makes the affected games recover
   (the user's current manual hacks — workspace switching etc. — work
   because they force the window back through a fullscreen state
   transition).
3. Restore focus to the pre-takeaway focused window (`lastFocusedAddr`
   at takeover, saved before our overlay grabbed the seat).
4. Clear the victim registry.

**Ordering risk (verify empirically):** step 2–3 hand keyboard focus to a
game window *while the overlay holds an exclusive grab*. Two possible
outcomes — decide by test:

- The layer grab survives (layer surfaces keep the seat despite toplevel
  focus changes): restore immediately after teardown, dismissals keep
  working, done.
- The grab is lost (Escape stops dismissing): move the restore pass to
  just **before** the overlay hides (`Timer` ~150ms ahead of hide +
  `Process` after unmap for the final focus set), so the seat handoff
  happens with the overlay gone. Slightly racy (hyprctl dispatch after
  unmap) but testable; the mouse-move/click dismissals work either way.

Note the restore also fixes **focus-pause**: most games pause on keyboard
focus loss, which is part of "don't recover without hacks". Handing focus
back while the overlay still covers the screen means the game is running
and fullscreened before the user ever sees the desktop again.

## What `omarchy toggle screensaver` still does, for free

Unchanged from the parent doc — the takeover triggers on the stock
*launch*, so the flag-file guard keeps gating everything:

| Toggle state | Launcher at idle | Our behavior |
|---|---|---|
| Enabled (no flag) | spawns stock windows | takeover → overlay; stock killed; lock at `idle.lock` (our timer) |
| Disabled (flag file) | exits 1 at its own guard | no window, no event → nothing; lock still fires at `idle.lock` (built-in) |

Menu "Screensaver" (`force`) and `omarchy branding screensaver …` still
show the overlay instead of ttfx (Component 2's mode discrimination keeps
them from arming a spurious lock).

## Known limitations & accepted trade-offs

- **Shell restart mid-cycle loses the lock for this cycle.** If
  `omarchy-shell` restarts (or the plugin crashes) while our countdown is
  armed: overlay starts hidden (recovery guarantee, untouched), but the
  countdown dies and the built-in cycle was already canceled at takeover —
  so nothing locks until the user's next activity→idle transition re-arms
  a cycle. The parent design kept the built-in lock alive through a
  restart only by keeping ttfx alive, which (per the focus-trap facts
  above) it never actually did. This is the one real regression vs. the
  parent design *on paper*. Mitigation option (phase 3, optional):
  at countdown start, spawn a transient systemd user unit —
  `systemd-run --user --on-active=<lockDelay>s --unit=overlay-screensaver-lock omarchy-system-lock`
  — stopped via `systemctl --user stop overlay-screensaver-lock.timer` on
  dismissal; the unit checks `omarchy-shell lock isLocked` before
  locking, and a dismiss-marker state file prevents a lock firing after
  the user came back to a dead plugin. Adds moving parts; do it only if
  the "away → no lock" window matters in practice.
- **Flash frame is larger than in the parent design.** Overlay map +
  status IPC + kill ≈ 50–150ms of a fullscreen ttfx visible on each
  monitor. Same mitigation as parent (accept it); the restore pass means
  the games don't care.
- **Branding preview wart** (inherited): `omarchy branding screensaver …`
  shows our shader, not the branding preview.
- **Wasted GPU eliminated** (a parent-design wart that this variant
  accidentally fixes): ttfx never survives takeover, so no 120fps render
  behind the overlay, and the `-STOP` freeze idea (rejected in the parent
  doc as fragile) is unnecessary.
- **One second-idle-cycle oddity:** after takeover, `omarchy.idle` sees
  the cycle as canceled and `idleMonitor.isIdle` still true; it won't
  start a new cycle until real user activity resets it. While the overlay
  is up there is no input (by definition), so nothing spurious happens.
  Verified consequence: `omarchy-shell idle status` shows
  `inIdleCycle: false` while our overlay is up — expected, do not treat
  as a bug when diagnosing.

## Invariants (from AGENTS.md — all preserved)

- Overlay starts with `visible: false`; the takeover adds no persisted
  state; `kill`/shell restart recovers (worst case per above: this
  cycle's auto-lock is skipped).
- `WlrKeyboardFocus.Exclusive` only on the visible overlay — unchanged;
  the takeover never maps an always-visible grabbing surface.
- Namespace, `cfg()` config access, IPC result-string checking —
  unchanged.

## Implementation sketch (`Service.qml`)

New pieces, roughly in dependency order:

1. `property var victims: ({})`, `property string lastFocusedAddr: ""`,
   `property bool takeoverSuppress: false` (flag name must not collide
   with any final QML property — same rule as `overlayVisible`).
2. Extend the existing Hyprland `Connections` (add one if absent):
   `openwindow` (takeover trigger + suppress-window re-kills),
   `closewindow` (registry GC), `fullscreen` + `activewindowv2`
   (registry maintenance).
3. `function takeover()` — show overlay, spawn the `idle status` Process,
   then (on exit) run the teardown Process, then start/`$lockDelay` the
   lock `Timer`.
4. `function restoreVictims()` — clients snapshot + dispatch loop.
5. Hook `hide(source)` (single existing function all dismissal paths go
   through): stop the lock timer before hiding.
6. Lock-timer `onTriggered`: isLocked guard → hide → `Process` running
   `omarchy-system-lock`.

All processes via the existing `Process`/`bash -lc` pattern; everything
idempotent (`pkill` no-ops when nothing matches).

## Verification checklist

Everything in the parent doc's checklist, adjusted for hard-close:

1. **Toggle OFF end-to-end**: idle past `screensaver` → no window, no
   takeover, built-in lock fires at `idle.lock` (stock behavior
   untouched).
2. **Toggle ON end-to-end**: idle → ttfx flashes ≤200ms → overlay;
   `omarchy-shell idle status` shows `inIdleCycle: false` +
   `screensaverWindows: 0` (cycle canceled — expected); overlay stays;
   at `lockDelay` expiry → overlay hides → hyprlock; wake already ran;
   after unlock, `pgrep -a ttfx` and `pgrep -f org.omarchy.screensaver`
   both empty, cursor visible.
3. **The game case (the reason this doc exists)**: leave a game
   fullscreen (test with any fullscreen app; real game if available) →
   idle → takeover → after takeover, `hyprctl clients -j` shows the game
   with `fullscreen: true` again and (post-verify ordering) keyboard
   focus; dismiss; game fullscreen and focused, no workspace tricks
   needed.
4. **Multi-monitor**: game fullscreen on monitor B, ttfx loop spawning
   per monitor → both monitors' stock windows dead, B's game restored.
5. **Manual launch** (`omarchy-launch-screensaver force`, menu button):
   overlay shows, **no** lock countdown armed (dismiss → nothing locks).
6. **Dismissal ladder**: Escape, click, mouse-move, ssh `hide` — all
   stop the countdown; then confirm no lock fires even after `lockDelay`
   elapses.
7. **Lock-race guard**: `omarchy-shell lock` manually mid-overlay →
   countdown expiry sees `isLocked == true` → hides only, no second
   hyprlock.
8. **Recovery ladder**: `kill` / `omarchy restart shell` mid-overlay →
   overlay gone, starts hidden; note the accepted no-lock-this-cycle
   behavior.
9. Journal check for the takeover window
   (`journalctl --user -u "wayland-wm@hyprland.desktop.service"`): GL
   errors (blank overlay) and our `console.log` takeover/teardown traces.

## Unknowns to verify at implementation time

- **Layer keyboard grab vs. toplevel focus dispatch** (Component 5
  ordering): does Escape still dismiss after `focuswindow` hands the seat
  to a game? Determines restore-immediately vs. restore-before-hide.
- Actual visible flash duration (overlay map + IPC + kill), measured with
  `grim` or a phone camera — decide whether to eat it or pre-arm.
- `hyprctl dispatch fullscreen` mode argument for a *client-request*
  fullscreen (1 vs 2) on this Hyprland version; also whether
  `focuswindow address:` + `fullscreen` needs the window to be on the
  focused workspace first (`movetoworkspacesilent` fallback).
- Whether `pkill -f 'omarchy-launch-screensaver'` can race the launcher's
  own `socat` event stream in a way that leaks a window past the 5s
  suppression window (unlikely; the re-kill-on-openwindow rule covers it).
- Quickshell `Hyprland.rawEvent` payload shapes for `fullscreen>>` and
  `activewindowv2>>` on the installed Quickshell (eventParts parsing, same
  as idle service's `IdleModel.eventParts`).

## Relationship to the parent doc

This doc supersedes Design 1's steps 1–3 in
[screensaver-toggle-integration.md](screensaver-toggle-integration.md) for
implementation purposes; the parent doc's research (toggle chain, clone
system, upstream PR menu, marketplace precedent) all still stands. If the
focus-trap finding above ever changes (upstream removes
`screensaver_in_focus`, or the overlay stops grabbing keyboard), re-evaluate
the parent design's keep-windows-open variant — until then, this is the
only variant of Design 1 whose behavior under the overlay's keyboard grab
is actually deterministic.
