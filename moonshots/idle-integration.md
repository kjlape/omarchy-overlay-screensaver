# Moonshot: trigger the overlay on idle (become Omarchy's screensaver)

> Goal: make the overlay the thing that happens when this machine goes idle —
> at `idle.screensaver` seconds, ahead of the lock — while keeping every core
> guarantee intact: starts hidden, no persisted visibility, `kill` always
> recovers the screen.

**Not implemented.** Researched 2026-09-24 against this machine (Omarchy 4,
Hyprland, shell `omarchy-shell`) and `/usr/share/omarchy` source. The plugin
today is manual-only: the only timers in `Service.qml` are the 16 ms shader
clock and the 300 ms `hyprctl cursorpos` poll, and every show path enters
through `IpcHandler`.

## TL;DR

- Idle is owned by the first-party **`omarchy.idle` shell service**, *not*
  hypridle. (`~/.config/hypr/hypridle.conf` is dead config here — nothing runs
  hypridle. Don't edit it, don't add listeners there.)
- The `screensaver-off` toggle is implemented **entirely inside**
  `/usr/share/omarchy/bin/omarchy-launch-screensaver`. Nothing upstream
  consults it. So any approach that doesn't route through that script must
  re-implement the guard or it silently breaks `omarchy toggle screensaver`.
- Cheapest viable path (zero plugin code): **PATH-shadow that script**. Works,
  inherits the whole idle→lock→wake cycle and the `force` launch entry point.
- Two hazards the shadow **cannot** fix, because they need in-process
  knowledge: the overlay survives the lock, and it can't see keystrokes
  once hyprlock holds the keyboard. Both are fixed plugin-side by watching
  `omarchy.lock`'s `locked` property (already prescribed in
  [../docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) "How to extend").
- Recommended: shadow + hide-on-lock patch (≈10 lines), *or* go all the way to
  the in-process design below. Don't ship the shadow alone.

## What actually drives idle here (verified)

`/usr/share/omarchy/shell/plugins/services/idle/Service.qml` (361 lines,
`manifest.json` id `omarchy.idle`, `keepLoaded: true`):

| Mechanism | Detail |
|---|---|
| Idle source | `IdleMonitor { timeout: firstIdleTimeoutSeconds; respectInhibitors: true }` where `firstIdleTimeoutSeconds = min(screensaver, lock)` |
| Config | `shell.json` → `"idle": { "screensaver": 150, "lock": 300 }`; defaults 150/300 in the file |
| On idle | `startIdleCycle()` → screensaver fires at the first timeout, `lockTimer` covers the remainder |
| Screensaver cmd | line 69: `[[ $(omarchy-shell lock isLocked) == "true" ]] \|\| omarchy-launch-screensaver` via `bash -lc` |
| Lock cmd | `omarchy-system-lock` |
| Wake | `cancelIdleCycle()` runs `omarchy-system-wake` **only if a cycle was in flight** |
| Kill switch | `idleEnabled: stayAwakeStateLoaded && !stayAwake`, where stay-awake = presence of `~/.local/state/omarchy/indicators/stay-awake` |
| Screensaver tracking | watches Hyprland `openwindow`/`closewindow` for class `org.omarchy.screensaver` (line 27) to count live screensaver windows; 3 s `screensaverLaunchGraceTimer` |
| IPC | `omarchy-shell idle <status\|debug\|enable\|disable\|toggle>` — `status` is a rich JSON diagnostic (timers, window count, `lastEvent`) |
| UI | bar indicator `plugins/bar/indicators/StayAwake.qml`; menu `omarchy-menu.jsonc:85` `trigger.toggle.idle-lock`, `:88` `trigger.toggle.screensaver` |

Cycle logic that matters for us (`handleActiveSignal`, ~line 158): once the
idle service has started a cycle, resuming activity normally cancels it — *but*
it deliberately keeps the lock timer armed while a screensaver window exists or
during the 3 s launch grace. Two consequences for a surface it can't count:

- A layer-shell surface emits no `openwindow`, so `screensaverWindowCount`
  stays 0. The grace timer's cancel branch requires `!idleMonitor.isIdle`, and
  our overlay generates no input, so it doesn't fire → **the lock still happens
  on schedule.** Good.
- Dismissal-by-input still cancels the pending lock (count 0 + grace expired →
  falls through to `cancelIdleCycle("activity")`). Good. What we lose is the
  `handleScreensaverWindowClosed` fast path ("screensaver dismissed → cancel
  pending lock"), which can only trigger on a window we never create.

`omarchy-system-lock` teardown, for contrast — this is the gap:

```bash
pkill -x ttfx 2>/dev/null || true                      # the screensaver renderer
pkill -f '[o]rg.omarchy.screensaver' 2>/dev/null || true   # its terminal
```

Neither pattern can match our overlay: it is not a process and not a window. It
lives in the shell process on `WlrLayer.Top`. **Nothing outside the plugin can
tear it down** except our own IPC/`kill`, our Escape/click/key handlers, or the
cursor-move poll.

## Option A — PATH-shadow `omarchy-launch-screensaver` (no plugin code)

Viability checks, both run on this machine:

- `bash -lc 'command -v omarchy-launch-screensaver'` → upstream is at
  `/bin` + `/usr/bin` (same file as `/usr/share/omarchy/bin/…`).
- A login shell's `PATH` (what `runProcess` uses) puts `~/.local/bin` at
  position 5, `/usr/bin` far below → **a file in `~/.local/bin` wins.**
- `~/.config/omarchy/hooks/` is a red herring: the only hook upstream fires is
  `post-boot` (`default/hypr/autostart.lua:13`). **There is no lock/unlock
  hook**, so the hooks directory cannot close the teardown gap.

`~/.local/bin/omarchy-launch-screensaver` — guards copied so the toggle keeps
working:

```bash
#!/bin/bash
# PATH-shadow of /usr/share/omarchy/bin/omarchy-launch-screensaver: the idle
# screensaver becomes the overlay plugin. Guards mirror upstream so that
# `omarchy toggle screensaver` and `omarchy-launch-screensaver force` behave.

# Already running? (upstream: pgrep -f '[o]rg.omarchy.screensaver')
[[ $(omarchy-overlay-screensaver status 2>/dev/null | jq -r .visible) == true ]] && exit 0

# screensaver-off toggle, with force bypass (upstream:13)
if omarchy-toggle-enabled screensaver-off && [[ $1 != "force" ]]; then
  exit 1
fi

exec omarchy-overlay-screensaver shader   # or: shader <name>, or randomize from `shaders`
```

What this inherits for free: the `isLocked` guard, the 150/300 timing, stay-awake
respect, `omarchy-system-wake` on resume, and — because the guard is `force`-aware
— the omarchy menu entry `system.screensaver` (`omarchy-menu.jsonc:31`, action
`omarchy-launch-screensaver force`) turns into "show the overlay now".

What it costs:

1. `omarchy toggle screensaver` still works **only because we copied the
   guard**; the notification text ("Screensaver enabled/disabled") now refers to
   the overlay.
2. `omarchy branding screensaver image|text|reset` each end with
   `omarchy-launch-screensaver force` → flashes a GLSL hack instead of
   redrawing ASCII branding. Harmless, wrong.
3. It is a fork of a system script: if upstream's launcher grows logic, re-copy.
4. Hazards H1/H2 below remain.

## Residual hazards (need plugin code)

**H1 — the overlay survives the lock.** At 300 s hyprlock engages with the
overlay up. Whether it visually covers the password prompt depends on how
Hyprland stacks its lockscreen surface vs `WlrLayer.Top` — **untested**. Either
way it's wrong state: on unlock, `omarchy-system-lock`'s teardown doesn't touch
us and the cursor baseline is stale.

**H2 — keystrokes can be invisible to us.** ttfx's wrapper
(`/usr/share/omarchy/bin/omarchy-screensaver`) traps input and exits on *any*
keyboard/mouse event. Our overlay hides on a key only while it holds
`WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive`, and the lock grabs
the keyboard away. So: unlock by typing the password, never touch the mouse,
and the shader is still covering the desktop while you type. The cursor poll is
the only recovery. Same class of hole any time focus is stolen from us.

Both are the same fix, and it's the fix `docs/ARCHITECTURE.md` already names.

## Recommended implementation (for when we do this)

Resolve the lock service. `shell.firstPartyServiceFor(id)` is the right call
for a *first-party* id — it is literally `serviceFor(pluginRegistry
.resolveEnabledId(id))` (`shell.qml:890`), so it handles cloned plugins without
copying remote-lock's manual dance (`~/.config/omarchy/plugins/kjlape.remote-lock/Service.qml:29`,
which needs the dance only because its target id is third-party `kjlape.lock`).
Target: `omarchy.lock` (`/usr/share/omarchy/shell/plugins/lock/Service.qml`),
which exposes `readonly property bool locked: lockRequested || sessionLock.locked ||
sessionLock.secure` (line 37) and is `keepLoaded: true`.

```qml
// Service.qml — hides the overlay when the session locks (fixes H1 + H2)
readonly property var lockSvc: shell && typeof shell.firstPartyServiceFor === "function"
  ? shell.firstPartyServiceFor("omarchy.lock") : null

Connections {
  target: root.lockSvc
  enabled: root.lockSvc !== null
  function onLockedChanged() {
    if (root.lockSvc.locked && root.overlayVisible) {
      console.log("overlay-screensaver: hidden source=session-lock")
      root.overlayVisible = false
    }
  }
}
```

**Unknown to verify at implementation time:** whether a *third-party* service is
allowed to resolve first-party services at all — the shell has capability
gating (`isAuthenticationService`, `__hostCapabilities`, `pluginCloneMaySummon`),
and `firstPartyServiceFor` may be intended for the bar's own use. If
`lockSvc` comes back null, two fallbacks, in order of preference:

1. Poll `omarchy-shell lock isLocked` from a `Process` while the overlay is
   shown (we already poll `hyprctl cursorpos` the same way — reuse that shape),
   or subscribe to lock state over our own IPC verb from the caller.
2. Shadow `omarchy-system-lock` on PATH too (`omarchy-overlay-screensaver hide`
   then `exec` the real script). Ugly, and it doubles the fork surface — only
   take this if 1 is unacceptable.

Then pick the trigger. Two variants:

- **A+** — keep the shadow script for the trigger, add the lock hook above.
  Minimum code, keeps one idle clock, `stay-awake` + lock timings respected for
  free. Cost: the fork-maintenance and branding warts in Option A's list, and we
  still lie to the idle service's window bookkeeping.
- **B** — in-process trigger, no shadow at all. Either
  `IdleMonitor { timeout: cfg("idleSeconds", 0) }` with its own clock (simple,
  but competes with `omarchy.idle` and double-counts idle), or — better —
  subscribe to the idle service the same way
  (`shell.firstPartyServiceFor("omarchy.idle")`, watch `idledThisCycle` /
  `screensaverStartedThisCycle`, reuse `screensaverTimeoutSeconds`) so we *are*
  the screensaver with one clock. Then `omarchy toggle screensaver` needs an
  equivalent: read the `screensaver-off` flag (or better, adopt
  `omarchy-toggle-enabled` semantics in the plugin) so the existing UX keeps
  meaning something.

Ship whichever trigger with the lock hook; **the lock hook is the part that
makes idle-triggering safe.**

### Invariants any implementation must keep

From `AGENTS.md`: the overlay must always start `visible: false` with no
persisted state, and an idle trigger must not change that — a shell restart
during idle must come back un-overlaid (so: no "restore visibility from idle
state at load"; re-arm on the next idle edge instead). `WlrKeyboardFocus.Exclusive`
stays on the visible surface only. An idle-triggered show must remain
dismissable by all four existing paths plus `kill`.

### Verification checklist (the empirical unknowns)

1. `journalctl --user -u "wayland-wm@hyprland.desktop.service" | grep "omarchy idle"`
   through a full cycle — expect `idle-cycle-start → process-start screensaver →
   lock-system`, and **no** `idle-cycle-cancel: screensaver-not-running` (that
   would mean the grace timer cancelled our cycle; see
   [../docs/troubleshooting.md](../docs/troubleshooting.md) for why it's the
   journal and not `-u omarchy-shell`).
2. Watch `omarchy-shell idle status` during a cycle: `screensaverWindows` will
   read 0 with the overlay up. Expected, not a bug — but confirm the `lock`
   timer still fires.
3. Shorten for testing: `"idle": { "screensaver": 10, "lock": 40 }`.
4. Lock interplay, the actual question: let it reach the lock, then `grim` a
   capture before and after entering the password. Is the overlay drawn over
   hyprlock? Does the first mouse move dismiss it? Is any keystroke swallowed?
5. Confirm `WlrLayer.Top` vs hyprlock stacking explicitly (H1) rather than
   inferring from absence of complaints.
6. Re-test recovery ladder after the change: `hide`, Escape, click, mouse-move,
   `omarchy-overlay-screensaver kill`.
7. Multi-monitor: `status` reports `screens` (1 here). Upstream loops monitors
   spawning one terminal each; we get per-monitor `Variants` surfaces for free —
   verify with a second monitor attached.

## Enabling any of this on *this* machine

Both switches are currently off, so nothing happens on idle today:

```bash
omarchy-shell idle status | jq -c '{enabled,lastEvent}'
# → {"enabled":false,"lastEvent":"idle-cycle-cancel: stay-awake"}   (idle disabled)

omarchy-toggle-idle allow-idle   # remove ~/.local/state/omarchy/indicators/stay-awake
omarchy toggle screensaver       # ~/.local/state/omarchy/toggles/screensaver-off exists → suppresses the launcher
```

Also note the default hack resolves to **starnest** (`cfg("shader", "starnest")`
— the `plugins[]` entry has no `shader` key). `status` showing another name is
in-memory state from the last manual show, not config.

## Evidence index

| Fact | Where |
|---|---|
| Idle timers, cycle, lock, grace, stay-awake, IPC | `/usr/share/omarchy/shell/plugins/services/idle/Service.qml` (`:17-27` config/defaults, `:69` launch, `:130` dismissed-window cancel, `:158` activity handling) |
| `screensaver-off` has exactly one consumer | `grep -rn screensaver-off /usr/share/omarchy/` → `bin/omarchy-launch-screensaver:13` |
| Upstream already-running guard | `bin/omarchy-launch-screensaver:10` (`pgrep -f '[o]rg.omarchy.screensaver'`) |
| Lock teardown can't see us | `omarchy-system-lock` (`pkill -x ttfx`, `pkill -f '[o]rg.omarchy.screensaver'`) |
| `force` callers | `default/omarchy/omarchy-menu.jsonc:31`, `bin/omarchy-branding-screensaver:15,19,22` |
| hypridle not in use | `pgrep -a hypridle` empty; no user unit; `~/.config/hypr/hypridle.conf` unsourced |
| PATH shadowing works | `bash -lc 'echo $PATH'` → `~/.local/bin` before `/usr/bin` |
| No lock/unlock hook exists | only caller of `omarchy-hook` upstream is `default/hypr/autostart.lua:13` (`post-boot`) |
| Lock service watchable state | `plugins/lock/Service.qml:37` `locked`, manifest `omarchy.lock` `keepLoaded: true` |
| resolveEnabledId precedent + first-party accessor | `~/.config/omarchy/plugins/kjlape.remote-lock/Service.qml:29`; `shell.qml:886` `serviceFor`, `:890` `firstPartyServiceFor` |
| Cursor poll / dismissal | `Service.qml` `cursorTimer`/`cursorProc`/`Keys.onPressed`/`MouseArea` |
