# Moonshot: autonomous idle mode — a screensaver that knows nothing about Omarchy

> Goal, as asked for: an integration that **does not touch the stock
> screensaver machinery at all**. It has its own toggle, its own idle clock, and
> its own config. The user turns Omarchy's built-in screensaver off (the stock
> toggle, one command, config not code), turns this on, and the overlay then
> runs until dismissed. It does not *suppress* suspend, hibernate, lid sleep,
> monitor off, or the auto-lock — those keep operating exactly as the system
> configures them, with the overlay sitting there, indifferent.
>
> **Short answer to "does zero integration simplify it?" — enormously.** Every
> component of [screensaver-takeover-close.md](screensaver-takeover-close.md)
> (victim registry, hard-close sequence, `idle status` parsing, re-owned lock
> countdown, fullscreen restore pass) exists *only* to undo damage caused by
> letting the stock screensaver start. Remove the collision and the design
> collapses to one `IdleMonitor`, one flag file, and one guard. The costs are
> not technical, they're UX-political: two clocks, two toggles, and no
> inherited courtesy behaviour (menu button, branding preview) — *except*
> stay-awake awareness and pointer hiding, which turned out cheap enough to be
> **requirements** (§2b, §4b), not losses.
>
> Not implemented. Researched 2026-09-25 against this machine (Omarchy 4.0.4,
> Hyprland 0.56.2, Quickshell 0.3.1). Empirical results are marked **[verified]**.

## Verified mechanics this design rides on

| # | Fact | Evidence |
|---|---|---|
| 1 | Idle notification is a **standard Wayland protocol**, available to any client: `ext-idle-notify-v1`, wrapped by Quickshell as `IdleMonitor { enabled, timeout, respectInhibitors, readonly isIdle; onIsIdleChanged }`. No `idled` signal — state is the `isIdle` property, same as `omarchy.idle` uses (`/usr/share/omarchy/shell/plugins/services/idle/Service.qml:251`). | `/usr/lib/qt6/qml/Quickshell/Wayland/_IdleNotify/quickshell-wayland-idle-notify.qmltypes`; `/usr/share/wayland-protocols/staging/ext-idle-notify/ext-idle-notify-v1.xml` (`idled`/`resumed` events, seat-scoped, "a zero timeout is valid") |
| 2 | **A second, non-Omarchy Quickshell instance gets its own working idle clock in this live session** — separate process, separate `IdleMonitor`, real `isIdle` transitions. Two independent clocks coexist. | **[verified]** `/tmp/qsidle/shell.qml` under `qs -p`, log: `IDLE-CHANGED isIdle=true` then `false` |
| 3 | **A session lock beats our overlay and is not disturbed by it.** `ext-session-lock-v1` is explicit: on `locked` the compositor "must stop rendering and providing input to normal clients", must blank outputs opaquely, and only lock surfaces (plus compositor-privileged shell UI) may be rendered. Our layer surface is a *normal client* surface: invisible and inert while locked, back when unlocked. Confirmed by hand: overlay shown manually, session locked from ssh, lock screen came up normally. | **[verified]** user test + `/usr/share/wayland-protocols/staging/ext-session-lock/ext-session-lock-v1.xml` |
| 4 | Therefore **lock detection is unnecessary** and is deliberately *not* part of this design. The H1/H2 hazards in [idle-integration.md](idle-integration.md) (overlay over the password prompt / swallowing the lock's keystrokes) are protocol-impossible: we can neither be seen nor heard while locked. Everything else in that file still stands — it was written before fact 3 was checked. | this doc, fact 3 |
| 5 | Not inhibiting anything is a *choice we can guarantee by omission*: idle inhibition is a separate opt-in object (`zwp_idle_inhibitor_v1`, Quickshell `Wayland._IdleInhibitor/IdleInhibitor`), and DPMS/suspend/lock are driven by the compositor and logind, not by us. This plugin never creates an inhibitor and never touches `systemd-inhibit`, so monitor-off, suspend, hibernate and the auto-lock all keep their own schedules. | `/usr/lib/qt6/qml/Quickshell/Wayland/_IdleInhibitor/…qmltypes` |
| 6 | Quickshell's own `WlSessionLock { locked, secure, unlock(), surface }` is the *locker* API (Omarchy's lock screen is drawn by the shell through it — `plugins/lock/Service.qml:230,264`), **not** a lock observer. A second instance cannot read the first one's lock state; a second `get_lock` just gets `finished` ("…or the compositor has decided to deny the request…"). Another reason to skip lock awareness entirely. | `…/Wayland/quickshell-wayland.qmltypes`; `/usr/share/omarchy/shell/plugins/lock/Service.qml` |
| 7 | If lock state is ever genuinely needed, it is reachable **without Omarchy IPC**: `hyprctl -j monitors` reports `solitaryBlockedBy` containing `"LOCK"` while a session lock is held — that is precisely how upstream detects it in `omarchy-hyprland-session-locked` (exit 0/1/2). Hyprland also advertises `hyprland_lock_notifier_v1` (≥0.52.1; this is 0.56.2) but **Quickshell 0.3.1 does not bind it**. Logind's `LockedHint` is not maintained by Hyprland (no `sd_session_set_*` in the binary) — don't bother. | **[verified]** `hyprctl monitors -j` → `solitaryBlockedBy: ["WINDOWED","CANDIDATE"]`; `strings /usr/bin/Hyprland` → `hyprland_lock_notifier_v1`, `ext_session_lock_*` |
| 8 | A standalone instance is controllable over **plain Quickshell IPC**, no Omarchy in the loop: `qs ipc -p <path> call <target> <fn> [args…]`. From an ssh/TTY environment with no `WAYLAND_DISPLAY`, instance selection needs `--any-display` (without it: `No running instances … Dead instances`). | **[verified]** `env -u WAYLAND_DISPLAY … qs ipc --any-display -p /tmp/qsidle/shell.qml call idletest ping` → `{"idle":false,…,"screens":1}` |
| 9 | Independence does **not** remove the collision risk if the user forgets to disable the built-in. The stock wrapper's input loop exits on `! screensaver_in_focus` (`hyprctl activewindow -j` must report class `org.omarchy.screensaver`), which our mapping surface breaks within ~1 s; its `closewindow` events then make `omarchy.idle` cancel the pending lock and run `omarchy-system-wake`. Two independent screensavers on one machine = **the auto-lock silently dies**, and the stock windows still get their `fullscreen` window rule (the game-demotion bug). See [screensaver-takeover-close.md](screensaver-takeover-close.md) "Why the deviation is mandatory". | `/usr/share/omarchy/bin/omarchy-screensaver`; `shell/plugins/services/idle/Service.qml:130` |
| 10 | What the stock toggle does *not* cover: `omarchy-launch-screensaver force` (menu entry `system.screensaver`, `omarchy branding screensaver …`) bypasses `screensaver-off`. With the built-in "disabled" the menu Screensaver button still launches ttfx — i.e. still collides (fact 9). | `/usr/share/omarchy/bin/omarchy-launch-screensaver:13`, `default/omarchy/omarchy-menu.jsonc:31` |
| 11 | The cursor is drawn by Hyprland above every layer, and the stock screensaver hides it with a **leaky, compositor-specific** keyword (`hyprctl keyword cursor:invisible true`, restored in its exit trap) — global state that would strand an invisible pointer if *we* died while it was set, so it is disqualified here. The generic replacement (`Qt.BlankCursor` → null cursor in Qt Wayland, fact 14) is a one-property requirement (§4b). | `/usr/share/omarchy/bin/omarchy-screensaver` |
| 12 | Nothing on this machine actually does monitor-off at idle: `hypridle` is not running, `~/.config/hypr/hypridle.conf` is dead config, and the only `dpms` references in `/usr/share/omarchy` are Hyprland's `misc:key_press_enables_dpms` / `mouse_move_enables_dpms` *wake* options (`default/hypr/input.lua:72`). So "don't suppress monitor off" is satisfied trivially — we don't inhibit; if the user later wires DPMS (or `hl.dpms`), nothing about the overlay blocks it. | **[verified]** `pgrep -a hypridle` empty; `grep -rln dpms /usr/share/omarchy/` |
| 13 | **Omarchy's Stay Awake is nothing but one state file**: every entry point — the bar indicator, `omarchy toggle idle [stay-awake\|allow-idle]`, `omarchy-shell idle enable/disable/toggle` — funnels into `applyStayAwake()`, which touches/removes `~/.local/state/omarchy/indicators/stay-awake`. Upstream consumes it with a one-shot `[[ -f ]]` probe (`stayAwakeStateProbe`) plus a `FileView` on the *directory* with `watchChanges: true` for live updates. Any third-party consumer can copy that pattern verbatim; ~10 lines, no IPC, no injected API. | `shell/plugins/services/idle/Service.qml` (`persistStayAwake`, `stayAwakeStateProbe`, `stayAwakeStateDirWatcher`); `/usr/share/omarchy/bin/omarchy-toggle-idle` (`STATE_FILE="$STATE_DIR/stay-awake"`) |
| 14 | **`Qt::BlankCursor` hides the pointer on Wayland, generically**: Qt's Wayland platform plugin handles it explicitly by setting a null cursor — `if (newShape == Qt::BlankCursor) { mDisplay->setCursor(NULL, NULL); }` in `qwaylandcursor.cpp`. Via QML: `MouseArea { cursorShape: Qt.BlankCursor }`. Per-client, per-surface, and leak-proof by construction — the moment our surface unmaps, the pointer returns; no cleanup path can be skipped. | **[verified in Qt source]** `qtwayland/src/client/qwaylandcursor.cpp` (`cursorImage()`); effect on *this* stack **[verify — checklist 4]** |

## The design

Four self-contained pieces. None of them names an Omarchy path, binary, IPC
target, window class, or injected shell property.

### 1. The clock — `IdleMonitor`, edge-triggered, armed on first activity

```qml
// Service.qml  (see §2/§2b for what gates auto-show)
readonly property bool autoShow: cfg("autoShow", false)          // opt-in
readonly property int  idleSeconds: Math.max(0, Number(cfg("idleSeconds", 300)))
property bool  stayAwake: false           // Omarchy Stay Awake awareness (§2b)
property bool  stayAwakeLoaded: false
property bool  seenActiveEdge: false      // arming guard, see below
property bool  holdOff: false             // our own temporary stay-awake (§2)
property bool  autoEnabled: autoShow && idleSeconds > 0 && !holdOff && !(stayAwakeLoaded && stayAwake)

IdleMonitor {
  id: screensaverIdle
  enabled: root.autoEnabled
  timeout: root.idleSeconds
  respectInhibitors: true                 // standard seat idle-inhibition
  onIsIdleChanged: {
    if (!screensaverIdle.isIdle) { root.seenActiveEdge = true; return }
    if (!root.seenActiveEdge) return      // started while already idle → ignore
    if (!root.overlayVisible) root.showShader(root.configuredShader, "idle")
  }
}
```

`isIdle` (not a `dismissed`-style bookkeeping flag) is the whole state machine:
one object, one seat, `enabled` binding, and a re-arm for free — after any
dismissal the user is by definition active, so the next `idled` is a fresh
timeout. No cycle timers, no grace timers, no window counting.

**The arming guard is load-bearing and is what keeps the recovery guarantee
true.** An overlay that can appear at load time is an overlay that can cover a
screen you are not looking at (shell/daemon restart over ssh while the machine
sits idle). `seenActiveEdge` requires one observed activity→idle *transition*
per process lifetime before it will ever auto-show, so a restart while unattended
is always a no-op — same fail-safe spirit as `visible: false` at start. Whether
`ext-idle-notify` even *can* report `idled` immediately on bind is unknown
(the protocol has no initial hint event, only `idled`/`resumed`); the guard makes
the question moot instead of assuming an answer. **[verify anyway — checklist 1]**

`respectInhibitors: true` buys the honest, portable version of "don't screensave
while something is happening": any app that creates a `zwp_idle_inhibitor_v1`
(video players, presenters, `wl-inhibit`) suppresses us. Apps are only half of
the story, though — Omarchy's Stay Awake indicator is *not* an inhibitor (fact
13), which is why §2b makes consuming its state file a requirement.

### 2. The toggle — our own flag file, opt-in, gating auto-show only

- State: `$XDG_STATE_HOME/overlay-screensaver/off` (default `~/.local/state/…`),
  created/removed by `overlay-screensaver disable` / `enable`. Read with
  `FileView` (hot-reload on change, no polling, no Omarchy code path). (Verb
  names below are written in the portable form this design implies —
  `overlay-screensaver …`; today's CLI is
  `bin/omarchy-overlay-screensaver`, which would stay as a shim.)
- `overlay-screensaver hold` / `unhold` → `$XDG_STATE_HOME/overlay-screensaver/hold`
  is the *temporary* stay-awake equivalent. Two files because they mean different
  things to a human: "never again" vs "not while I'm presenting".
- **`autoShow` defaults to false.** Installing or enabling this must never change
  when the screen gets covered. The user opts in once (`overlay-screensaver
  enable`) after turning the stock one off, and that ordering is the README's
  first paragraph — because fact 9 says the wrong order breaks auto-lock.
- The toggle gates *auto-activation only*. Manual `show`/`shader` over IPC keeps
  working with the toggle off — that's how you test, and how the ssh-triggered
  "cover this display now" use case stays alive.

### 2b. Stay-awake awareness — a requirement, not a shim

Deciding factor (fact 13): Omarchy's Stay Awake — the bar indicator, the menu's
idle toggle, and `omarchy-shell idle enable/disable` — all funnel into one state
file, `~/.local/state/omarchy/indicators/stay-awake`, whose presence means "the
user asked for no idle behaviour". Respecting it costs exactly the pattern
upstream already runs against itself: a one-shot existence probe plus a
`FileView` on the *parent directory* with `watchChanges: true` (a FileView on
the file itself would error while absent, which is why upstream watches the
directory):

```qml
// §2b requirement: copy omarchy.idle's own consumption pattern, read-only
readonly property string stayAwakeDir: home + "/.local/state/omarchy/indicators"
readonly property string stayAwakePath: stayAwakeDir + "/stay-awake"
property bool stayAwake: false
property bool stayAwakeLoaded: false

Process {   // one-shot, at load and after any dir event
  id: stayAwakeProbe
  command: ["bash", "-c",
    "[[ -f \"$1/stay-awake\" ]] && echo yes || echo no", "--", root.stayAwakeDir]
  stdout: SplitParser {
    onRead: function (line) {
      root.stayAwake = String(line).trim() === "yes"
      root.stayAwakeLoaded = true
    }
  }
}
FileView { path: root.stayAwakeDir; watchChanges: true; printErrors: false
  onFileChanged: if (!stayAwakeProbe.running) stayAwakeProbe.running = true }
```

Complexity assessment: **~10 lines, zero new processes beyond the probe
upstream itself runs, zero IPC.** That is well under the "unreasonably complex"
bar, so it is a requirement:

- When `stay-awake` exists, `autoEnabled` is false (§1's binding already
  includes it) and — critically — the *entire idle path* goes quiet, exactly
  mirroring upstream's `idleEnabled: stayAwakeStateLoaded && !stayAwake`.
  This is **awareness, not inhibition**: we merely don't fire; we still create
  no `zwp_idle_inhibitor_v1`, so DPMS/suspend/lock schedules are untouched even
  while Stay Awake is on. The user's "allow them to operate as normal"
  requirement is preserved — staying awake is the user's choice, expressed in
  the place Omarchy already puts it.
- All three UI surfaces work for free because they all write that one file
  (bar indicator → shell IPC → `persistStayAwake`; `omarchy toggle idle`;
  `omarchy-shell idle enable|disable|toggle`). We are a **read-only consumer**:
  never create, delete, or "helpfully" clean up that file — Omarchy owns its
  lifecycle and co-owning it invites drift (two writers, one file).
- Our own `hold` verb (§2) stays: it is the ssh/portable equivalent that works
  on non-Omarchy hosts. Two mechanisms with clearly distinct ownership:
  *their* file gates us when it exists; *our* file gates us when it exists.
- Escape hatch kept but demoted: `cfg("respectOmarchyStayAwake", true)` exists
  so a future non-Omarchy host can turn the dependency off entirely — it is
  the one hardcoded Omarchy path in the QML, and it must be documented as such
  (the doc's "zero integration" claim is henceforth "zero Omarchy *APIs*, one
  documented, read-only state file").
- Do not extend this to other Omarchy state (idle timings, lock config, the
  `screensaver-off` toggle): those are *policy*, not awareness, and consuming
  them is exactly the coupling this design declines. The line is drawn at the
  file that expresses the user's "don't idle right now" intent, which is also
  the only one whose absence makes our behaviour *wrong* rather than merely
  unfused.

### 3. The config — our own file, so the QML has one less host assumption

Today `cfg()` reads `shell.shellConfig.plugins[]` — Omarchy's shell object. Add a
second source with lower precedence:

- `$XDG_CONFIG_HOME/overlay-screensaver/config.json` (`idleSeconds`, `autoShow`,
  `shader`, `image`, `fps`), parsed with `FileView` + `JsonAdapter` (both exist
  in `Quickshell.Io` **[verified: exports list]**).
- Precedence: injected `plugins[]` entry > our own file > built-in defaults. The
  QML stays byte-identical between Variant P and Variant S (§5); nothing in it
  requires `shell !== null`.

### 4. Dismissal — pointer events, not `hyprctl`

Replace the 300 ms `hyprctl cursorpos` poll (`Service.qml:cursorTimer/cursorProc`)
with Qt-level input on the surface that already covers the screen:

```qml
MouseArea {
  anchors.fill: parent
  hoverEnabled: true
  acceptedButtons: Qt.AllButtons
  onClicked: root.hide("click")
  onPositionChanged: function (e) {
    // ignore the synthetic motion/enter that a fresh map delivers under a
    // stationary cursor; require a real delta after a short grace
    if (root.overlayVisible && e.buttons === Qt.NoButton) root.hide("motion")
  }
}
```

This is the last compositor-specific call in the plugin, and it is what makes the
claim "runs until dismissed regardless of what else is going on" actually
testable: dismissal no longer needs a binary on PATH, an instance signature, or a
focused window. It also covers the one gap fact 3 opens — after an
unlock, our keyboard grab may or may not be re-granted by the compositor, so the
**pointer must be a complete dismissal path on its own**. Keystroke dismissal
stays (Escape and any key, via the existing exclusive grab) as an optimisation,
not a guarantee.

Unavoidable detail: the map-time synthetic motion. Guard it with a "first motion
must differ from the position seen at map/enter by ≥1 px, ≥250 ms after show"
rule. **[verify — checklist 2; if it turns out untrustworthy, keep the cursorpos
poll behind `cfg("motionSource", "hyprctl")` as the fallback rather than losing
motion-dismissal.]**

### 4b. The pointer — hide it with `Qt.BlankCursor` (requirement)

A screensaver with a visible arrow parked on it is broken; the stock one hides
the cursor. But its mechanism is disqualified for us: `hyprctl keyword
cursor:invisible true` is (a) compositor-specific, and (b) **leaky global
state** — Hyprland holds that keyword until something writes it back, and a
process that dies while it is set (shell crash, `kill -9`, oom) leaves a
machine with no visible pointer. Upstream survives that risk because its
wrapper traps every signal; we live inside a process that can die arbitrarily.

The generic alternative is real (fact 14): Qt's Wayland plugin maps
`Qt::BlankCursor` to a null cursor, and QML exposes it directly:

```qml
MouseArea {
  anchors.fill: parent
  hoverEnabled: true
  cursorShape: root.overlayVisible ? Qt.BlankCursor : Qt.ArrowCursor
  …
}
```

Complexity assessment: **one property binding.** Well under the bar, so it is
a requirement:

- Blank while shown, restored automatically on unmap — the guarantee can't be
  skipped by any hide path, including a crashed process, because it lives in
  the surface itself, not in compositor state.
- Never reach for `cursor:invisible`. It belongs in the same prohibition
  family as `dpms` and inhibitors (see Invariants): global, leak-on-death,
  compositor-specific.
- **[verify — checklist 4]** that the blank shape actually lands on this
  stack (Quickshell 0.3.1 / Hyprland 0.56.2: Qt sends a null cursor image on
  the pointer surface while hovering our MouseArea). Known cosmetic gap even
  if it works: between surface map and the first pointer enter, the compositor
  still draws the last cursor image it had — a sub-second arrow blip at
  show time. Accept it; the only fix is the forbidden keyword.
- If it *doesn't* work (e.g. a Qt/Hyprland cursor-shape-protocol quirk), the
  accepted fallback is a visible arrow over the shader, not the keyword —
  document it and move on. Cursor hiding is polish; leak-proofness is the
  requirement.

### 5. Where it runs — Variant P (hosted by the shell) vs Variant S (its own process)

Both variants share §1–§4 verbatim.

**P — same plugin, same process as `omarchy-shell` (recommended first).**
Zero new moving parts; the failsafe stays exactly as documented in
[../AGENTS.md](../AGENTS.md): the overlay is in the shell process, starts hidden,
and `kill` / `omarchy restart shell` always recovers. `manifest.json`,
`omarchy plugin add/enable`, hot reload, and the marketplace story all keep
working. "Zero integration" here means *zero Omarchy APIs in the logic* —
still hosted by Omarchy's shell.

**S — its own Quickshell instance under a systemd user unit.** Truly
independent: own process, own IPC (`qs ipc --any-display -p … call`, fact 8),
own config, and it runs unchanged on any compositor that provides
`wlr-layer-shell` + `ext-idle-notify` (Hyprland, Sway, river, labwc, niri,
KWin). New files:

- `daemon/shell.qml` — a `ShellRoot` that imports the unchanged `Service.qml`
  with no injected properties;
- `daemon/overlay-screensaver.service` — `ExecStart=qs -p %h/.local/share/overlay-screensaver`,
  `WantedBy=graphical-session.target`, `Restart=on-failure`;
- `bin/overlay-screensaver` — talks to the instance by config path instead of
  through `omarchy-shell`, so its `kill` verb becomes
  `systemctl --user stop overlay-screensaver.service`.

|  | P | S |
|---|---|---|
| Omarchy coupling left | hosting + manifest + injected `shell` (optional per §3) | none |
| Break-glass recovery | `omarchy restart shell` (drags the bar/lock/whole shell with it) | `systemctl --user stop overlay-screensaver.service` from any TTY — independent of shell health |
| AGENTS.md "no daemon can wedge the overlay" | intact | **deliberately violated**; softened by (a) surfaces die with the process, so a dead daemon = clear screen, and (b) a stoppable unit — but a live-but-stuck renderer *can* hold the screen until you kill it |
| Failsafe *quality* | depends on the shell's IPC or `omarchy` CLI | depends only on systemd/killing a pid |
| Second GPU context / Qt renderer | no | yes |
| Portable off Omarchy | no | yes |
| Managed by `omarchy plugin`, marketplace, hot reload | yes | no |
| Idle-while-unlocked by a shell restart | overlay dies (screen recovers) | overlay survives the shell restart — *and* survives `omarchy plugin remove`, which is how you get a screensaver nobody can uninstall by accident |

Ship P. Land S only if the "usable without Omarchy" story matters, and land it as
an *alternative install mode* with P's `Service.qml` untouched — with the
AGENTS.md recovery paragraph rewritten in the same commit, not after.

## Does zero integration simplify it? Yes — here is the arithmetic

| [screensaver-takeover-close.md](screensaver-takeover-close.md) (max integration) | This doc (zero integration) |
|---|---|
| 5 new components: victim registry, `openwindow` watcher + suppression window, `idle status` IPC parse, self-owned lock countdown, fullscreen restore pass | 1 component: `IdleMonitor` + two flag files |
| ~7 spawned processes (`pkill` ×3, `idle status`, `isLocked`, `omarchy-system-lock`, `clients -j`) | **+1 short-lived probe** (stay-awake state check — the same one-shot `[[ -f ]]` upstream runs on itself); everything else is a Wayland event or a `FileView` |
| Depends on: `org.omarchy.screensaver` class, `omarchy-launch-screensaver` spawn loop, ttfx's focus trap, `omarchy.idle`'s window counting + grace timer, `idle.lock` semantics, `omarchy-shell` IPC, shell.json `plugins[]` | Depends on: `ext-idle-notify-v1`, `wlr-layer-shell`, Qt input events, XDG paths |
| One *ordering* unknown that can break Escape (layer grab vs `focuswindow` dispatch), plus a restore-before-hide contingency | No ordering unknowns; one motion-guard unknown |
| Fixes the game-demotion bug with a repair pass (re-fullscreen every victim, hand focus back) | The bug **cannot occur**: with the stock toggle off, no `org.omarchy.screensaver` window ever maps, so the `fullscreen` window rule never fires (`default/hypr/apps/system.lua:35`) |
| Must re-own the lock, because killing the stock windows cancels `omarchy.idle`'s cycle (and needs an `isLocked` guard against double-locking) | Nothing to re-own: `omarchy.idle` keeps its own clock and locks on its own schedule; we are invisible to it (a layer surface emits no `openwindow`) and it is invisible to us |
| Lock timing must be read live from `omarchy-shell idle status` to avoid config divergence | Own `idleSeconds`; divergence is accepted, documented, and priced below |
| Accepted warts: 50–150 ms ttfx flash frame, branding-preview hijack, "no lock this cycle after a shell restart" | Accepted warts: two toggles to understand; stay-awake is consumed but nothing dims; cursor-hiding via BlankCursor has a sub-second arrow blip at show |

The whole takeover design is a *repair* strategy for a collision we choose not to
have. Declining the collision deletes the design. That is the real answer to the
question, and it is why this doc is a page and a half where the takeover doc is
four hundred lines.

## What you lose (and what you'd have to rebuild)

Ranked by how much it will actually annoy you.

1. ~~Stay-awake~~ — **handled, as a requirement (§2b)**. This used to be the
   top item in this list until fact 13 was checked: Stay Awake is one state
   file with three writers, and consuming it is upstream's own ~10-line
   pattern. What remains honest here is the *cost*: it is the single hardcoded
   Omarchy path in the QML (`cfg("respectOmarchyStayAwake", true)` exists to
   switch the dependency off on other hosts), and our `hold` verb remains the
   portable parallel mechanism (ssh/non-Omarchy), because the Omarchy
   indicator does not exist there. Do **not** merge the two — different owners,
   different lifecycles.
2. **Two clocks, and ours can be scheduled after the lock.** `idle.lock` (300 s
   default) locks the session; if `idleSeconds` > that, the lock happens first
   and we are never seen (fact 3: locked = we're not rendered). The recommended
   relationship (`idleSeconds` < `idle.lock`) is a README line, not enforced —
   enforcing it means reading the shell's config or IPCing for it, which is the
   coupling this doc exists to avoid. Zero-integration's price here is "the
   correct settings are a comment in your config file".
3. **The stock screensaver must actually be off, and `omarchy toggle screensaver`
   does not cover everything** (facts 9, 10): the menu's Screensaver button and
   `omarchy branding screensaver …` use `force` and will still spawn ttfx —
   which then steals-focus-kills itself against our grab *and* demotes
   fullscreen games. Two options, both user-config, no code: drop/rebind that
   menu entry in `~/.config/omarchy/omarchy-menu.jsonc`, or accept that pressing
   it collides. Our `enable` verb should print a warning if
   `omarchy-toggle-enabled screensaver-off` is false — a read-only, human-facing
   hint in the CLI, which is a different category of coupling from QML logic.
4. **No diagnostics through the shell's own lens**: `omarchy-shell idle status`
   never mentions us (it can't), and `omarchy-shell overlayscreensaver …` stops
   being the only way in once Variant S exists. Replace with our own
   `overlay-screensaver status` (already exists) extended with
   `{autoShow, idleSeconds, idle: isIdle, held: bool, enabled: bool, next: …}`.
5. **Branding has no meaning for us** — `~/.config/omarchy/branding/screensaver.txt`
   is ttfx's input. Our analogue is `shader`/`image` in our own config. Fine; just
   don't promise `omarchy branding screensaver image` does anything.
6. **Most of the *visual* idle experience still doesn't carry over**: cursor
   hiding **is handled** (requirement, §4b — `Qt.BlankCursor`, generic and
   leak-proof), but there is no `omarchy-brightness-display` dimming and no
   black-terminal-frame before the effect. Dimming is the tempting one: it
   would need `omarchy-brightness-display` (Omarchy binary) or `brightnessctl`/
   DDC (generic but a new dependency, plus state to restore on every hide path
   — the same leak-on-death argument that killed `cursor:invisible`, but with
   hardware consequences). Deliberately out of scope: if dimming is wanted,
   it should be its own moonshot with its own restore guarantees.
7. **We are not a "provider".** Nothing registers us as *the* system screensaver:
   other plugins, the marketplace, the bar, and any future Omarchy UI keep their
   own opinion. The alternative (becoming the lock screen itself via
   `WlSessionLock`) is a bigger, different moonshot: it is the only design that
   gives one seamless locked→unlocked visual, and it is *incompatible with the
   requirement* "let auto-lock operate as normal", because you'd be replacing the
   locker. Recorded here so nobody re-derives it by accident.

All of [../AGENTS.md](../AGENTS.md) survives, plus new prohibitions and two
new requirements:

- Overlay starts `visible: false`, no persisted *visibility*. §1's `seenActiveEdge`
  is process-local and intentionally resets every restart, which strengthens this.
- `WlrKeyboardFocus.Exclusive` only on the visible surface — unchanged.
- **Never create an `IdleInhibitor`, never take a systemd inhibitor lock, never
  write `cursor:invisible`, never dispatch `dpms`.** The "does not suppress
  suspend/hibernate/monitor-off/auto-lock" promise is a promise about what we
  *don't* do; a future contributor adding one of those breaks it silently.
  Note this still holds with Stay Awake awareness in place: reading the
  indicator file makes us *idle-aware*, not *idle-inhibiting* — the schedules
  of DPMS/suspend/lock are untouched whether or not Stay Awake is on.
- **Never write the stay-awake indicator file** (§2b). We consume it; Omarchy
  owns it. Creating or deleting `~/.local/state/omarchy/indicators/stay-awake`
  from our code would make two components fight over one file. Our own
  `hold` file under `$XDG_STATE_HOME/overlay-screensaver/` is the only state
  we may create for this purpose.
- **Never add lock detection.** Fact 3: the protocol already guarantees the lock
  wins. If a future bug report suggests we interfere with hyprlock/shell-lock,
  re-test fact 3 on that compositor before writing code — and if the fix ever
  needs it, fact 7's `solitaryBlockedBy` probe is the least-coupled form.
- New (requirement): the auto-show path must be *dead at load* (§1 guard) and
  *opt-in at install* (§2 default), so this feature can never cover a screen
  the user isn't watching.
- New (requirement): the pointer is blank while the overlay is shown and
  restored by unmapping alone (§4b) — if `Qt.BlankCursor` ever fails on a
  future stack, the accepted state is a visible arrow, never the keyword.

## Implementation sketch

1. `Service.qml`: add the two `FileView`s (off/hold), the stay-awake probe +
   dir-watcher (§2b, upstream's own pattern), the `IdleMonitor` block,
   `seenActiveEdge`, and the own-config `FileView`+`JsonAdapter`; replace
   `cursorTimer`/`cursorProc` with `MouseArea` hover/motion (keep the poll behind
   `motionSource` if checklist 2 fails); add `cursorShape: Qt.BlankCursor` to the
   overlay's `MouseArea` (§4b). ~80 lines net, ~30 removed.
2. `bin/omarchy-overlay-screensaver`: add `enable|disable|hold|unhold|state`,
   print the built-in-toggle warning in `enable`, keep everything else. If Variant
   S ships, the portable verb name becomes `bin/overlay-screensaver` and the
   `omarchy-`-prefixed script stays as a shim that execs it (the
   `WlrLayershell.namespace` stays exactly as-is — AGENTS.md uniqueness rule).
3. `config/overlay-screensaver.example.json` (+ `docs/` note on precedence, §3).
4. Docs: README gets an "Autonomous idle mode" section whose first line is
   `omarchy toggle screensaver` and whose second is "do not press the menu's
   Screensaver button"; roadmap.md gets a Phase row (`standalone idle mode`,
   difficulty: trivial mechanically, annoying empirically);
   `moonshots/idle-integration.md` gets a header pointer here — its H1/H2 hazard
   analysis is superseded by fact 3.
5. Variant S, only if wanted: `daemon/shell.qml`, the unit file, a
   `--any-display`-based CLI mode, and the AGENTS.md recovery-paragraph rewrite.

## Verification checklist

Empirical items first; the rest is the existing ladder re-run with the overlay on
a timer.

1. **Idle at load.** `enable`, set `idleSeconds: 5`, get the seat genuinely idle
   (no touch), then `omarchy restart shell` (Variant P) / `systemctl restart`
   (S). Expect: *no* overlay. Confirm the guard works and the next real
   activity→idle edge does show it. Also tells you whether Hyprland emits `idled`
   immediately for a freshly created notification (§1).
2. **Self-dismissal.** Show via idle, do not touch the mouse, watch for 2 s:
   must stay up (map-time motion guard works). Then move 1 px: must hide, and
   `status` must report `visible:false` with `source=motion`.
3. **Lock over the overlay** (already hand-verified — re-verify as an assertion,
   not a hope): overlay up → `loginctl lock-session` (or `omarchy-shell lock lock`)
   from ssh → lock prompt is fully visible and *takes keystrokes* (type the
   password blind if needed) → unlock → the overlay is back → one mouse move
   clears it. Then note explicitly whether Escape also clears it post-unlock
   (§4's keyboard caveat) and, if it doesn't, whether re-asserting the grab
   (flip `keyboardFocus` None→Exclusive on pointer re-entry) fixes it cheaply.
4. **Cursor** (§4b requirement): `Qt.BlankCursor` over the surface — pointer
   invisible while shown, back immediately after `hide`/crash/`kill`. Record the
   show-time arrow blip if present. If the blank shape does not land, confirm
   the accepted fallback (visible arrow, never `cursor:invisible`).
5. **Suspend/hibernate with the overlay up**: `systemctl suspend`, wait, resume →
   overlay still there, input still dismisses, no GL corruption, and the shader
   clock resyncs (it will jump — `time` is accumulated in `onTriggered`, so
   a long suspend only skips frames; confirm no NaN/uniform blow-up).
6. **Monitor off (synthesised)**: `hyprctl dispatch dpms off` / `on` with the
   overlay up — display must sleep and wake with us still covering, and
   `misc:mouse_move_enables_dpms` must still wake it on motion (motion arriving
   at our surface *is* seat input, so it should).
7. **Inhibitors**: run a video player / `wayland idle-inhibit` holder, shorten
   `idleSeconds` to 10, confirm we don't fire; then kill it and confirm we do.
7b. **Stay Awake, all three writers** (§2b): `omarchy-shell idle disable` →
    no overlay at the idle deadline (and the *whole* idle path quiet, like
    upstream); `omarchy toggle idle` → same; the bar's StayAwake indicator →
    same, live within a second of the file appearing (dir-watch catches it
    without a restart). Then each reverse direction: overlay fires again.
    Confirm `omarchy-shell idle status` still reports our independence honestly
    (we never wrote the file — `ls` before/after must be identical).
8. **Collision regression**: `disable` our hold, leave the *stock* screensaver
   enabled (no `screensaver-off` flag), idle past both timeouts, and confirm the
   documented failure (ttfx spawns, self-exits, `omarchy-shell idle status`
   reports `inIdleCycle:false`, auto-lock never fires). Document it in the
   README as *why* the ordering matters.
9. **Multi-monitor**: `Variants` gives every screen a surface; the new monitor
   plugged in *while shown* is immediately covered — acceptable? (Today: yes.
   Re-check.)
10. **Recovery ladder** unchanged: `hide`, Escape, click, motion, `kill`,
    `omarchy restart shell`; plus for S: `systemctl --user stop
    overlay-screensaver.service` and `pkill -f 'qs -p .*overlay-screensaver'`.
11. **Journal**: `journalctl --user -u "wayland-wm@hyprland.desktop.service"` for
    the show edges (`shown source=idle`) and GL errors; for Variant S, the unit's
    own log instead (`journalctl --user -u overlay-screensaver`).

## Open questions

- §1's initial-`idled` behaviour (checklist 1) — the guard makes it safe either
  way, but the answer decides whether `enabled: false → true` transitions (e.g.
  `unhold`) can *themselves* trigger an immediate show. They shouldn't: the
  notification object is recreated, and if Hyprland replays idle state, an
  `unhold` on an idle seat would cover the screen. If so, the arming guard must
  also be re-armed on `enabled` toggles — which is what `seenActiveEdge` already
  does if we clear it whenever `autoEnabled` goes false.
- Does a `WlrLayer.Top` surface with `keyboardFocus: Exclusive` ever *win* against
  a compositor's notion of the lock? Fact 3 says no on Hyprland; it is a per-
  compositor question only if Variant S ships to others. Nested Hyprland
  (`Hyprland` inside this session, own `HYPRLAND_INSTANCE_SIGNATURE`) is the cheap
  sandbox for that class of test — worth standing up before claiming portability.
- `fps`-capping the shader while the overlay is up: 60 fps animation for hours on
  battery is the honest cost of "runs until dismissed". A `cfg("fps", 30)` cap
  (just the `shaderTimer` interval) is a two-line mitigation; a *pause when the
  output is DPMS-off* would need `hyprctl monitors -j` (compositor-specific) and
  is not worth the dependency.
- Is `hold` better implemented as our own `zwp_idle_inhibitor_v1`? No — an
  inhibitor suppresses *other* clients' idle timers (including the built-in
  lock), which is precisely the "don't suppress anything" violation. Flag file
  only, for ourselves.

## Sources / evidence

- Protocol: `/usr/share/wayland-protocols/staging/ext-idle-notify/ext-idle-notify-v1.xml`,
  `…/staging/ext-session-lock/ext-session-lock-v1.xml`,
  [hyprland-lock-notify-v1](https://wayland.app/protocols/hyprland-lock-notify-v1)
- Quickshell types: `/usr/lib/qt6/qml/Quickshell/Wayland/_IdleNotify/quickshell-wayland-idle-notify.qmltypes`,
  `…/Wayland/_IdleInhibitor/…`, `…/Wayland/quickshell-wayland.qmltypes`
  (`WlSessionLock`), `…/Io/quickshell-io.qmltypes` (`FileViewAdapter`,
  `JsonAdapter`, `IpcHandler`)
- Upstream scripts: `omarchy-launch-screensaver`, `omarchy-screensaver`,
  `omarchy-system-lock`, `omarchy-system-wake`, `omarchy-hyprland-session-locked`,
  `omarchy-toggle-idle` (all `/usr/share/omarchy/bin/`),
  `shell/plugins/services/idle/Service.qml` (incl. the stay-awake probe/dir-watch
  pattern and `applyStayAwake`), `shell/plugins/lock/Service.qml`
- Qt: `qtwayland/src/client/qwaylandcursor.cpp` (`Qt::BlankCursor` → null
  cursor), [qwaylandcursor.cpp on GitHub](https://github.com/GarageGames/Qt/blob/master/qt-5/qtwayland/src/client/qwaylandcursor.cpp)
- Live probes on this machine: standalone `qs -p /tmp/qsidle/shell.qml`
  (idle transitions + `qs ipc --any-display` from an environment with no
  `WAYLAND_DISPLAY`), `hyprctl monitors -j` (`dpmsStatus`,
  `solitaryBlockedBy`), `hyprctl layers` (namespace `omarchy-overlay-screensaver`
  on layer `top`, same pid as bar/background), manual
  overlay-up-then-lock-session test
- Sibling docs: [screensaver-toggle-integration.md](screensaver-toggle-integration.md)
  (the integration ladder this doc declines),
  [screensaver-takeover-close.md](screensaver-takeover-close.md) (the repair
  machinery this doc makes unnecessary; still the authority if you *want* the
  takeover), [idle-integration.md](idle-integration.md) (H1/H2 superseded by
  fact 3; its inventory of the idle service still useful)
