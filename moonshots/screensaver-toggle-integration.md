# Research: make `omarchy toggle screensaver` control *this* overlay

> Goal: when the user flips the system screensaver setting (`omarchy toggle
> screensaver`, the menu's Toggle → Screensaver entry, or any other surface),
> it should enable/disable the overlay plugin instead of the built-in
> ttfx/terminal screensaver — refined, and without changes to Omarchy's
> packages or plugins.

Researched 2026-10-26 against this machine (Omarchy 4.0.4-1, Hyprland,
`omarchy-shell` from `/usr/share/omarchy/shell` — upstream repo layout:
`github.com/omacom/omarchy`, top-level `shell/`, `bin/`, `manual/`). Companion
to [idle-integration.md](idle-integration.md), which researched idle
*triggering* generally; this file narrows to the toggle question and adds the
new facts found since (the plugin **clone** system and the marketplace's
approved screensaver-takeover precedent). Not implemented.

## TL;DR

- **The toggle is just a flag file, and the flag has exactly one consumer:**
  `omarchy toggle screensaver` → `omarchy-toggle-screensaver` →
  `omarchy-toggle screensaver-off` → touches/removes
  `~/.local/state/omarchy/toggles/screensaver-off`. Nothing in the shell
  reads it. The only reader is the guard at
  `/usr/share/omarchy/bin/omarchy-launch-screensaver:13`, which every
  screensaver launch (idle cycle, menu "Screensaver" button via `force`,
  `omarchy branding screensaver …`) goes through.
- **Therefore the integration point is the launch, not the toggle.** Make the
  overlay the thing that happens when the stock screensaver *launches*, and
  the toggle — along with stay-awake, idle timings, lock orchestration, the
  menu button, and wake — controls the overlay for free, with zero flag-reading
  code and zero changes to Omarchy.
- **Recommended: the "idle takeover" trigger** (Design 1 below). Our plugin
  watches Hyprland for the stock screensaver's `openwindow` events (class
  `org.omarchy.screensaver`, the exact signal `omarchy.idle` itself watches),
  covers the windows with the overlay, and tears the stock screensaver down
  with Omarchy's own cleanup commands when the overlay hides. This is not a
  novel hack: it is the *same technique used by an approved-and-listed
  marketplace plugin* (see precedent below), which the community has already
  reviewed and blessed.
- If Omarchy-side changes were ever desired instead, the three PRs to plan
  are in the last section — but none are required for the recommended design.

## What the toggle actually is (verified chain)

```
omarchy toggle screensaver
└─ omarchy-toggle-screensaver            (/usr/share/omarchy/bin/)
   ├─ omarchy-toggle screensaver-off      → touch/rm ~/.local/state/omarchy/toggles/screensaver-off
   └─ omarchy-notification-send "Screensaver disabled/enabled"
```

- `omarchy-toggle` is a pure flag-file mutator — no IPC, no shell involvement.
- `grep -Rn "screensaver-off" /usr/share/omarchy/` (follow symlinks!) finds
  exactly three hits: the toggle wrapper, the notification branch, and the
  launcher guard. **The shell's idle service never consults the toggle**;
  `omarchy.idle` always calls `omarchy-launch-screensaver` at the configured
  `idle.screensaver` seconds, and the launcher itself decides to no-op when
  the flag exists (unless called with `force`).
- Consequence 1: a plugin can't "ask" the shell whether the screensaver is
  enabled — it must read the flag file (trivial, `FileView`, same pattern the
  idle service uses for stay-awake) or, better, never need to (Design 1).
- Consequence 2: suppressing the stock screensaver *without* touching
  Omarchy means either intercepting the launcher (PATH shadow), winning its
  `pgrep -f '[o]rg.omarchy.screensaver'` already-running guard, or letting it
  launch and covering/tearing it down. These are the design axes below.

Related verified facts that constrain any design:

- `omarchy-system-wake` does **not** kill the screensaver — it only restores
  brightness/keyboards and handles clamshell. The stock screensaver's own
  wrapper (`/usr/share/omarchy/bin/omarchy-screensaver`) exits on input via
  its own trap. Anything that hides the stock windows without feeding them
  input must clean them up itself.
- `omarchy-system-lock` teardown is: `pkill -x ttfx`, `timeout 1s pidwait -x
  ttfx`, `pkill -f '[o]rg.omarchy.screensaver'` — i.e. killing by process
  name/class is Omarchy's *own documented cleanup mechanism*, fair game for
  a plugin to reuse verbatim.
- The idle service's lock timer is coupled to screensaver **window**
  bookkeeping: it counts `openwindow`/`closewindow` events for class
  `org.omarchy.screensaver`, and a "screensaver dismissed before the lock
  deadline" cancels the pending lock (`cancelIdleCycle("screensaver-dismissed")`).
  **If we close the stock windows while a cycle is armed, we cancel the
  lock.** Whatever we do to the stock windows must respect this.

## Precedent: the marketplace has already blessed a screensaver takeover

[omacom/omarchy-plugin-marketplace
#6150](https://github.com/omacom/omarchy-plugin-marketplace/issues/6150)
("[Plugin]: ANSI Screensaver", approved-and-verified, listed) is a screensaver
*replacement* plugin whose maintainer notes describe the technique:

> "the plugin's service watches Hyprland for that window and swaps in ours …
> Idle takeover leaves the stock idle service untouched: it launches its
> screensaver as usual, the plugin's service watches Hyprland for that window
> and swaps in ours (a fallback IdleMonitor covers a stock launcher that
> never ran)."

That plugin keeps the *same window class* (`org.omarchy.screensaver`) so
Omarchy's lock logic keeps working. Our overlay is a layer surface and can't
carry a window class — but it doesn't need to: it covers everything at
`WlrLayer.Top`, so the stock windows can simply *stay open behind it*,
keeping the idle service's bookkeeping (and therefore the lock) intact. The
takeover pattern is community-endorsed; only the swap mechanics differ.

## The design space

Four ways to own the screensaver slot without modifying Omarchy. Ordered by
recommendation.

### Design 1 (recommended): idle takeover — watch the stock launch, cover it

**Mechanism.** Add to `Service.qml`:

1. A Hyprland event watcher — the same `Connections { target: Hyprland;
   function onRawEvent(event) }` shape `omarchy.idle` uses — filtering
   `openwindow` events for `org.omarchy.screensaver`. On the first such
   window: show the overlay (`overlayVisible = true`, source
   `"idle-takeover"`). It already covers every monitor; the stock terminals
   spawn per-monitor behind it, invisible.
2. **Do not kill or close the stock windows while the cycle is armed.** Their
   open windows are what keep the idle service counting (window count > 0 →
   "cycle remains armed" → the lock timer survives). Closing them early
   triggers `screensaver-dismissed` and silently cancels the lock.
3. On every overlay dismissal path (key, click, mouse-move, IPC `hide`), run
   Omarchy's own teardown as a `Process`: `pkill -x ttfx; timeout 1s
   pidwait -x ttfx; pkill -f '[o]rg.omarchy.screensaver'`. The wrapper's
   SIGTERM trap also restores `cursor:invisible`. The resulting
   `closewindow` events tell the idle service the screensaver was dismissed,
   which cancels the pending lock and runs `omarchy-system-wake` — precisely
   the built-in semantics.
4. The hide-on-lock watcher from
   [idle-integration.md](idle-integration.md) (poll `omarchy-shell lock
   isLocked` while shown, or resolve `omarchy.lock` if permitted — see that
   doc's "Unknown to verify"): the overlay must not outlive the lock (H1) or
   swallow keystrokes hyprlock needs (H2).

**What `omarchy toggle screensaver` does under this design, for free:**

| Toggle state | Launcher behavior at idle | Our behavior |
|---|---|---|
| Enabled (no flag file) | spawns stock windows | `openwindow` fires → overlay covers them → lock at `idle.lock` as usual |
| Disabled (flag file) | exits 1 at its own guard | no window, no event → overlay never shows; lock still happens at `idle.lock` (identical to built-in disabled semantics) |

Zero flag-reading code, zero divergence risk from idle timings, stay-awake
respected (the stock service never fires), and **graceful degradation**: if
our plugin is disabled, uninstalled, or crashes, the machine silently falls
back to the stock screensaver — no idle behavior is lost. That property is
unique to this design.

**Bonus surfaces it fixes for free:** the menu's Screensaver entry
(`omarchy-launch-screensaver force`, bypasses the toggle) and
`omarchy branding screensaver …` both spawn stock windows → the takeover
trigger fires → the user sees the overlay, not ttfx. No PATH shadow needed
for any of them.

**Warts / open questions:**

- **One flash frame**: the stock terminal may be visible for the instant
  between its `openwindow` and our layer surface mapping (layer-shell maps
  are fast; likely a few ms). Verify with `grim` mid-launch; if objectionable,
  the ANSI plugin's "fallback IdleMonitor" trick can pre-arm us a beat
  earlier — but that reintroduces a second clock and timing divergence;
  prefer accepting the flash.
- **Wasted GPU**: the stock `ttfx` keeps rendering at 120 fps behind the
  overlay. Bounded, but real. The tempting `pkill -STOP -x ttfx` freeze is
  **not** recommended: a stopped process can't handle the SIGTERM that
  `omarchy-system-lock` sends (pending until SIGCONT), so the lock path's
  `pidwait` times out and a stopped ttfx leaks. If pursued, every hide/lock
  path must SIGCONT before killing — fragile; skip unless the cost matters.
- **Branding preview wart** (shared with every takeover design):
  `omarchy branding screensaver image|text|reset` force-launches to show the
  new branding — the user sees our shader instead of their branding preview.
- Invariants from [../AGENTS.md](../AGENTS.md) still hold: overlay starts
  hidden, no persisted visibility, `kill` recovers; the takeover adds no
  state that survives a restart (a shell restart during idle drops the
  overlay; the stock screensaver keeps running under it, and the next cycle
  re-covers).

### Design 2: PATH-shadow `omarchy-launch-screensaver`

The moonshot's Option A ([idle-integration.md](idle-integration.md)):
`~/.local/bin/omarchy-launch-screensaver` re-implements the launcher's guards
and `exec`s our CLI. It still works, but under the new facts it's the weakest
option:

- Forks a system script whose guards (pgrep pattern, toggle check, `force`
  semantics) must be re-copied on every upstream change — the exact
  "hacky suggestion" this research was asked to move past.
- The idle service's window bookkeeping goes blind (count 0 during a cycle),
  relying on subtle grace-timer reasoning to keep the lock armed.
- Needs the plugin-side lock watcher anyway (H1/H2), so it saves less code
  than it appears.
- Superior in exactly one respect vs Design 1: it *prevents* ttfx from ever
  spawning (no wasted GPU, no flash). If that matters, prefer Design 3.

### Design 3: clone `omarchy.idle` and own the clock

New fact since the idle moonshot: Omarchy has a **first-party plugin clone
system**, and it is the sanctioned "replace a built-in" mechanism:

- `omarchy plugin clone omarchy.idle` copies the entire idle service to
  `~/.config/omarchy/plugins/<user>.idle/`, sets `omarchy.clonedFrom:
  "omarchy.idle"` in the manifest, and **enabling a service-kind clone
  automatically adds `omarchy.idle` to `disabledPlugins[]`**
  (`PluginRegistry.qml:548`) — the built-in stops loading; only the clone
  runs. `omarchy plugin enable omarchy.idle` restores the stock service.
- The clone keeps `IpcHandler { target: "idle" }` working (clone tooling
  deliberately keeps built-in ids as stable IPC targets), the bar's
  StayAwake indicator keeps working (`firstPartyServiceFor("omarchy.idle")`
  routes to the clone via `resolveEnabledId`), and the clone is granted the
  real `idle` config block (`publicIdleConfigFor` is gated on exactly
  `clonedFrom == "omarchy.idle"` — the gate exists for this).

**Mechanism.** In the clone, edit ~3 spots: `launchScreensaver()` runs
`omarchy-overlay-screensaver shader` (or `show`) instead of the launcher —
after adding the two-line `screensaver-off` guard the launcher used to
provide; `lockSystem()` hides the overlay before `omarchy-system-lock` (fixes
H1 by construction); keep everything else byte-identical. Ship a
`tools/make-idle-clone.sh` in this repo that runs the clone then applies the
patch, so re-syncing after an `omarchy update` is one command.

**Pros:** one clock; owns lock orchestration; the toggle's meaning becomes
ours to interpret; ttfx never spawns; `omarchy-shell idle status/debug`
reflects our overlay.

**Cons — why it's the *deep* option, not the default:**

- We fork 361 lines of lock-orchestration QML. A bug there doesn't ruin a
  screensaver, it ruins *locking* — the highest-stakes component in the
  shell. The clone is a static copy: upstream fixes to idle logic (the
  stay-awake persistence dance, grace-timer reasoning) don't propagate until
  someone re-runs the script.
- The stock idle service is replaced, so there's no graceful fallback to the
  built-in if our plugin has issues — the whole idle subsystem rides on a
  third-party fork.
- `omarchy update` drift is silent: nothing warns that the clone is stale.

This is the right design only if we later want first-class integration
(indicator wiring, `idle status` reflecting the overlay) or if the
wasted-GPU cost of Design 1 proves unacceptable.

### Design 4: own IdleMonitor in our plugin (rejected)

The idle moonshot's Option B-lite: our own `IdleMonitor` with timeouts from
our `plugins[]` config. Rejected for the toggle question: `publicIdleConfigFor`
returns `{}` for anyone but an idle clone, so we cannot read the real
`idle.screensaver`/`idle.lock` values through the injected shell API — we'd
maintain *duplicate timeouts in our own plugin config*, and the user's
`screensaver`/`lock` settings would silently diverge (screen "locks" when
our overlay says so, or the real lock lands mid-overlay with different
timing). Re-implementing `FileView` watches on shell.json is possible but
just rebuilds the idle service badly. If we need our own clock, Design 3 is
the honest version.

### Comparison

| | D1 takeover | D2 PATH shadow | D3 idle clone | D4 own monitor |
|---|---|---|---|---|
| Changes to Omarchy | none | none (user PATH) | none (user clone, sanctioned) | none |
| `omarchy toggle screensaver` gates the overlay | yes, via launch | yes, via copied guard | yes, via in-clone guard | only if we read the flag |
| Menu "Screensaver" force shows overlay | yes | yes | no (still ttfx) | no |
| Idle timings always match shell.json | yes | yes | yes (owns them) | **no — divergence** |
| Lock timer stays correct | yes (window count intact) | grace-timer reasoning | yes (owns it) | re-derived |
| Stock ttfx spawns | yes (hidden) | no | no | yes, visible |
| Fallback if plugin disabled/crashes | stock screensaver | none (shadow still fires) | none until re-enabled | stock screensaver |
| Code we must maintain beyond this plugin | hide-on-lock watcher | launcher fork + lock watcher | 361-line idle fork | ~30-line idle reimplementation |
| H1/H2 (lock stacking/keystrokes) | needs lock watcher | needs lock watcher | fixed by construction | needs lock watcher |

## Recommended plan (when we implement)

Design 1, in three increments:

1. **Takeover trigger + teardown** (the core): Hyprland `openwindow` watcher
   → show; upstream's exact teardown `Process` on every hide path. Test the
   full idle→lock→wake cycle with `"idle": { "screensaver": 10, "lock": 40 }`
   per [../docs/troubleshooting.md](../docs/troubleshooting.md)'s journal
   ladder; confirm the lock still fires *with the overlay up* (the whole
   point of not closing the stock windows).
2. **Hide-on-lock** watcher (H1/H2) — required before shipping; the
   stacking of `WlrLayer.Top` vs hyprlock's lock surface is still an
   empirical unknown, verified only by `grim` at lock time.
3. Optional polish: `grim` the launch flash; decide whether the branding
   wart is worth documenting in the README's caveats.

Verification checklist: everything in idle-integration.md's checklist, plus
(1) toggle OFF end-to-end (no overlay, no ttfx, lock still fires), (2) toggle
ON end-to-end (overlay covers, stock windows alive behind, lock fires, wake
tears down cleanly — no orphan ttfx after dismissal: `pgrep -a ttfx` empty),
(3) `omarchy-shell idle status` shows `screensaverWindows > 0` during a cycle
(positive proof the bookkeeping we depend on is intact), (4) ssh `hide`
mid-cycle (teardown → cycle cancels → wake runs), (5) recovery ladder
(`hide`, Escape, click, mouse-move, `kill`, `omarchy restart shell` — starts
hidden) unchanged.

## If Omarchy changes were on the table (not required for Design 1)

For completeness: the minimal upstream changes that would make this (and
the already-listed ANSI screensaver plugin) first-class, in merge-likelihood
order. All target **`omacom/omarchy`** — `shell/plugins/services/idle/`
(the idle service), `bin/omarchy-launch-screensaver` (the launcher), and
`manual/` (docs); none target `omarchy-plugin-marketplace` (a listing repo,
not code).

### PR 1 (docs-only, easiest merge): document the takeover contract

`manual/`, "Shell plugins" / "Toggles, idle & screensaver" pages: document
that (a) `org.omarchy.screensaver` is the screensaver window class the idle
service's lock bookkeeping keys on, (b) `omarchy-launch-screensaver force`
is the manual entry point, and (c) a plugin may watch that window/class to
replace the visuals — the technique two shipped plugins already use
blind, against an undocumented internal.

- **Sell:** zero code, converts an accident into an interface; the
  marketplace already blessed a screensaver-replacement plugin, so the
  behavior exists in the wild either way — better to specify it than break
  it. Frame: "document what the idle service's window bookkeeping expects
  from a screensaver, so replacement plugins don't accidentally disable the
  lock."
- **Likely objections:** "documenting it makes us maintainers of it";
  preference that plugins use the clone system instead; risk it's read as
  endorsing process-killing as API. Mitigate by documenting the teardown
  commands as exactly what `omarchy-system-lock` already does.

### PR 2 (scripts): a user hook in the launcher

`bin/omarchy-launch-screensaver`: before spawning terminals, if
`~/.config/omarchy/hooks/screensaver` exists and is executable, `exec` it
with the same argument (`force` or empty). Precedent: `~/.config/omarchy/hooks/`
already exists and `omarchy-hook post-boot` is fired from autostart.

- **Sell:** official customization point for "run *my* screensaver,"
  eliminating every PATH-shadow fork (a pattern the current design actively
  incentivizes — users shadow a root-owned script with `~/.local/bin`, which
  upstream can't even see). Contract is crisp: the hook owns already-running
  detection, multi-monitor, and dismissal; the toggle guard and `force`
  semantics stay in the launcher. Frame as "give screensavers the same hook
  surface as boot, so users stop forking system scripts."
- **Likely objections:** hook sprawl ("why not the plugin system?");
  ambiguity over whether the hook must honor the
  `org.omarchy.screensaver` class convention for lock bookkeeping (a
  non-window hook breaks window counting — same tradeoffs as our Design 1);
  "ttfx screensaver is a feature, not a placeholder." Weakest technically
  of the three because it doesn't solve the window-bookkeeping mismatch —
  pair it with PR 3's framing if pushing.

### PR 3 (shell): idle provider awareness / observable idle state

`shell/shell.qml` + `shell/services/PluginFirstPartyServiceApi.qml`: extend
the `omarchy.idle` proxy for third-party *service* plugins (currently
proxies are granted only to bar-capable plugins, and expose only
`stayAwake`/`enabled` + setters) with observable state — `isIdle`,
`inIdleCycle`, `screensaverStarted` — and/or let the idle service accept a
registered screensaver provider (a service exposing e.g. `show`/`active`)
instead of exec'ing a terminal, falling back to stock.

- **Sell:** the sanctioned-plugin story. Today a screensaver plugin must
  either fork the idle service (clone), shadow a script, or sniff window
  events — three workarounds for "tell me when the screensaver should show /

  let me *be* the screensaver." One observable idle state lets plugins build
  idle-reactive things (dimmers, overlays, presence) without private
  IdleMonitor clocks that can drift from the real lock timing. A provider
  interface makes the marketplace's existing screensaver-replacement category
  first-class instead of an accident. Frame: "plugins already replace the
  screensaver; give them a way to do it without breaking lock bookkeeping."
- **Likely objections (the big one): security).** Idle state is a
  surveillance-adjacent side channel — knowing when the user is away — and
  the allow-list-plus-setters-only shape of `PluginFirstPartyServiceApi`
  ("intentionally has no generic property or method forwarding") is clearly
  deliberate. Objections will cite exactly that comment. Mitigation:
  expose only *screensaver-relevant* edges (`screensaverStarted`), not raw
  idle; possibly gate behind a new manifest capability so consent is
  explicit. Also expect scope-creep resistance (API commitments outlive
  features) and "the clone system already solves this" (it does — by
  forking; be ready with the no-fallback/stale-clone argument). This is the
  most useful and least likely to merge; propose it *after* PR 1 lands, so
  the discussion starts from a documented contract rather than a novel API.

### PR 0 (not a PR, but the right first move)

Open an issue on `omacom/omarchy` describing this plugin and asking which
integration surface upstream prefers *before* writing any of the above.
Omarchy is an opinionated, fast-moving project (2k open issues, 2.5k PRs at
time of writing); a 30-line "idle takeover" demo plus the marketplace
precedent is a better conversation opener than a speculative API patch.

## Evidence index

| Fact | Where |
|---|---|
| Toggle chain: CLI → wrapper → flag file, no shell involvement | `/usr/share/omarchy/bin/omarchy-toggle-screensaver`, `/usr/share/omarchy/bin/omarchy-toggle` |
| `screensaver-off` has exactly one guard consumer | `grep -Rn screensaver-off /usr/share/omarchy/` → `bin/omarchy-launch-screensaver:13` (+ toggle/notification wrappers) |
| Idle service: launch, window bookkeeping, dismissed→cancel-lock, grace, stay-awake | `/usr/share/omarchy/shell/plugins/services/idle/Service.qml` |
| Lock teardown = kill by name/class (reusable by plugins) | `/usr/share/omarchy/bin/omarchy-system-lock` |
| Wake does not kill the screensaver | `/usr/share/omarchy/bin/omarchy-system-wake` (brightness/keyboard/clamshell only) |
| Stock wrapper: input trap, cursor invisible, exits on SIGTERM | `/usr/share/omarchy/bin/omarchy-screensaver` |
| Clone system: replaces built-in, auto-disables source, stable IPC targets, grants idleConfig | `/usr/share/omarchy/bin/omarchy-plugin-clone`; `shell/services/PluginRegistry.qml:548`, `:178`; `shell/shell.qml:364` (`publicIdleConfigFor` clonedFrom gate), `:446-511` (proxy allow-list) |
| Third-party service plugins get scoped `shell` API; no idle observables for them | `shell/shell.qml:287` `PluginShellApi`, `services/PluginFirstPartyServiceApi.qml` ("intentionally no generic forwarding") |
| Menu/branding force callers | `default/omarchy/omarchy-menu.jsonc:31` (`system.screensaver`), `bin/omarchy-branding-screensaver` |
| Marketplace-approved screensaver takeover precedent | [omacom/omarchy-plugin-marketplace#6150](https://github.com/omacom/omarchy-plugin-marketplace/issues/6150) (ANSI Screensaver, listed + approved-and-verified) |
| Upstream repo & component layout | [github.com/omacom/omarchy](https://github.com/omacom/omarchy) — `shell/`, `bin/`, `manual/` (Omarchy 4.0.4-1 locally) |
| PATH-shadow analysis (Option A), H1/H2 hazards, lock-watcher recipe | [idle-integration.md](idle-integration.md) |
