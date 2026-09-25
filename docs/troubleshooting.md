# Troubleshooting

Field notes from debugging the plugin, in rough order of how symptoms
present. Start here when "all evidence says it should be fine."

## Symptom: `IPC call failed` / `Target not found`

```
$ omarchy-overlay-screensaver status
omarchy-overlay-screensaver: IPC call failed — is the plugin enabled in shell.json?
$ omarchy-shell overlayscreensaver status
Target not found.
```

`Target not found` means the plugin's `IpcHandler` never registered —
i.e. **Service.qml failed to load**. The CLI's hint ("is the plugin enabled?")
is misleading: `omarchy plugin list` reporting `enabled` only reflects
*config state*, not whether the QML component actually compiled. A plugin
can be enabled in `shell.json`, present on disk, and completely dead.

Confirm by asking the shell for its registered IPC targets and checking the
log for load failures (see next section). A working third-party service
plugin (e.g. `kjlape.remote-lock`, `target: "remotelock"`) is a good control
experiment: if `omarchy-shell remotelock status` works, plugin loading in
general is fine and the problem is in *this* plugin's QML.

## Where the shell's logs actually are

The shell does **not** run as `omarchy-shell.service` (that unit doesn't
exist on Omarchy 4). It is spawned by `omarchy-launch-shell` inside the
uwsm compositor unit, so plugin errors land in:

```bash
journalctl --user -u "wayland-wm@hyprland.desktop.service" --since "-2 hours" \
  | grep -i "overlay\|plugin load failed"
```

Finding the process tells you the unit if in doubt:
`ps -eo pid,unit,cmd | grep quickshell`. Its stdout/stderr go to a socket,
not a plain file, so `/proc/<pid>/fd/2` is a dead end — use journald.

Plugin load failures look like:

```
WARN qml: service plugin load failed for kjlape.overlay-screensaver:
  file:///.../Service.qml:38:3: Cannot override FINAL property
```

## Gotcha: QML FINAL properties

`Item` (and most Quickshell types) declare `visible`, `anchors`, etc. as
**final** properties. Re-declaring one on the root object — e.g. our
original `property bool visible: false` as the overlay's state flag —
fails the *entire component* with `Cannot override FINAL property`. There
is no partial load: no `Component.onCompleted`, no `IpcHandler`, nothing.

State flags must not shadow built-in property names. That's why the
overlay's visibility flag is `overlayVisible`, and any new state property
should be similarly prefixed/renamed. A quick smoke test:

```bash
qml - <<'EOF'   # or a scratch file; errors print, silence = fine
import QtQuick
Item { property bool visible: false }   // -> Cannot override FINAL property
EOF
```

(Caveat: the standalone `qml`/`qmllint` tools are unreliable for this —
`qmllint` was silent on the offending file. The authoritative check is the
shell's own log line above.)

## Gotcha: the installed copy is not always your dev tree

The dev loop assumes a **symlink** install
(`ln -sfn "$PWD" ~/.config/omarchy/plugins/kjlape.overlay-screensaver`).
If the plugin was installed via a git clone instead, the installed
directory is a separate working tree and edits to `~/dev/...` are **not**
hot-reloaded — the shell watches the installed path only. Check which you
have:

```bash
ls -la ~/.config/omarchy/plugins/kjlape.overlay-screensaver
# symlink -> dev tree: edits hot-reload
# real dir with .git    -> clone: sync with cp or git pull from origin
```

## Gotcha: hot-reload can serve a stale (broken) compile

After fixing a broken Service.qml in the installed location, the shell
logs `Local plugin changed, reloading: kjlape.overlay-screensaver` but can
still fail with the *old* error, at the *old* line, even though the file on
disk is verified fixed (check with `sed -n '38p' <file>` against the line
in the error). The engine holds a cached compiled component and the
incremental reload path doesn't always invalidate it.

Disambiguate stale cache from real error by loading the file in a scratch
Quickshell instance (never load the real installed config twice — it would
double panels):

```bash
mkdir -p /tmp/qstest
cat > /tmp/qstest/shell.qml <<'EOF'
import QtQuick
import Quickshell
ShellRoot {
  Loader { source: "/home/kjlape/.config/omarchy/plugins/kjlape.overlay-screensaver/Service.qml" }
}
EOF
timeout 8 quickshell -n -p /tmp/qstest 2>&1 | head
```

If the scratch instance loads clean, the file is fine and the running
shell is stale → do a full restart, which is always safe for this plugin:

```bash
omarchy restart shell
```

The overlay starts hidden with no persisted state, so a shell restart can
never leave the screen covered.

## Gotcha: IdleMonitor `isIdle` dies after a `timeout` change (Quickshell 0.3.1)

Symptom: `IdleMonitor` exists, `enabled` is true, the C++ side even logs
`IdleNotification ... has been marked idle` / `resumed` in the journal — but
the QML `isIdle` property never changes and `onIsIdleChanged` never fires.
Status reads `idle:false` forever.

Cause: the monitor is created with the default timeout (or an earlier one)
and the `timeout` binding then changes; quickshell destroys and recreates the
underlying `ext-idle-notify` object, and after that recreation the QML-side
property silently stops following the C++ impl. Protocol events still arrive
(see `journalctl`/`quickshell log -r "*.debug=true"` → `has been marked
idle/resumed`), so nothing looks wrong.

Fix (what Service.qml does): **declare the monitor statically and toggle it
via `enabled` only.** A monitor instantiated mid-session (Loader `active`
flip) has a dead `isIdle` even when it exists and is enabled — verified in
the live shell by adding a statically-created monitor next to the Loader one:
the static one fired, the Loader one never did. Enable/disable flips are safe
(they replay current idle state, which the `seenActiveEdge` arming guard
absorbs) — but the `timeout` binding may only change while the monitor is
disabled; config edits go through a disable → reload → re-arm dance
(`rearmIdleMonitor`) so the impl is reborn with the correct timeout.
Never arm before the config's `idleSeconds` is actually parsed: gate on the
FileView `loaded` SIGNAL — the `loaded` PROPERTY is `isLoadedOrAsync` and is
already true during the async load, which would re-introduce a
born-on-default-then-flip race.

## Gotcha: FileView on an absent file never notices it appear

Symptom: a `FileView` whose `path` points at a file that did not exist when
the shell started (e.g. the user's config file, created afterwards) never
loads it — `watchChanges: true` does not help, and editor saves that replace
the file (`sed -i`, most editors) silently break the per-file watch too.

Fix (what Service.qml does): watch the parent **directory** with a second
`FileView`, probe for existence on every dir event (`[[ -f ]]` bash probe,
upstream's own pattern), point the real `FileView` at the file only once it
exists, and on every dir event `reload()` it and give it ~150 ms before
dependent consumers rebuild. In Service.qml that reload also feeds
`recreateIdleMonitor()` so an `idleSeconds` edit rebuilds the IdleMonitor
instead of triggering the timeout-recreation bug above.

## Tripping hazards inherited from the shell

- `omarchy-shell` IPC can exit 0 on failure — parse the result string
  (`"Target not found."`), not the exit code.
- `omarchy-shell shell rescanPlugins` may return before the reload
  finishes; give it a few seconds before re-testing.
- `omarchy plugin validate .` only checks the manifest, not QML validity —
  a green validate proves nothing about whether Service.qml compiles.

## Quick diagnostic ladder

1. `omarchy-shell overlayscreensaver status` → `Target not found` ⇒ plugin
   not loaded (skip to 3). JSON ⇒ loaded; the bug is in your logic.
2. `omarchy plugin list | grep overlay` — `enabled` is necessary but tells
   you nothing about load state.
3. `journalctl --user -u "wayland-wm@hyprland.desktop.service" | grep
   "plugin load failed"` — the actual compiler error, with file:line:col.
4. Verify the file at that line matches the error (stale-compile check,
   scratch quickshell above); restart the shell if it doesn't.
5. Still failing after a clean restart ⇒ real QML error; fix, sync the
   installed copy, restart again.
