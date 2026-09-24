# Vendored: xscreensaver `hacks/glx/glsl/`

Reference copy of the Shadertoy-API GLSL sources from
**xscreensaver 6.16**, so this repo has no dependency on a checkout at
`/home/kjlape/dev/xscreensaver/xscreensaver-6.16` (or on downloading the
upstream tarball).

- **Provenance:** `hacks/glx/glsl/` from the xscreensaver 6.16 release
  tarball (`https://www.jwz.org/xscreensaver/`).
- **Contents:** 38 `.glsl` files / 32 distinct programs + upstream `README`
  (rendered by upstream via `../xshadertoy.c`).
- **Each file keeps its original header**, which carries the author,
  shadertoy URL, and license. Do not strip those headers when porting.
- These are **porting sources only** — nothing under `vendor/` is built,
  shipped, or enabled by the plugin. Ported/baked copies live in `shaders/`.

## License matrix (verified from file headers, 2026)

See `docs/roadmap.md` Phase 1 for the full per-program table. Summary:

| Status | Files |
|---|---|
| CC0 (otaviogood) | `alienbeacon`, `elementalring`, `fluxcore`, `gimbalharmonics`, `protophore`, `skyline` |
| CC0 (mrange, some mixed embedded credits) | `batteredplanet`, `goldenapollian`, `stardome`, `logarithmiccircles`, `neontriangulator`, `truchetzoom`, `trainmandala`, `stripeytorus`, `selfreflect` |
| CC0 (mrange), multi-pass | `neongravity-0`/`-1` |
| MIT, relicensed by author for xscreensaver (Matt Vianueva) | `bestill0-0`…`bestill5-0`, `darktransit`, `downfall`, `noxfire`, `rigrekt`, `trizm`, `universeball` |
| MIT (other authors) | `hexplasma` (Nemerix), `polarnight` (supervitas), `prococean` (afl_ext), `starnest` (Kali) |
| ⚠️ No license statement in file — verify before porting/shipping | `bubblecolors`, `driftclouds` |
| ⚠️ xscreensaver in-house (GPL) — verify before porting/shipping | `amigajuggler` |
| ⚠️ Derivative of CC BY 3.0 original — attribution obligation | `synthwavecity` |

The ⚠️ rows are kept here for reference but are **do-not-ship** until
their licensing is resolved (tracked in `docs/roadmap.md`).

## Updating

Re-vendor by copying over this directory from a newer xscreensaver tree
and re-running the header/license check documented in
`docs/roadmap.md`:

```bash
cp -r <xscreensaver-tree>/hacks/glx/glsl/* vendor/xscreensaver/hacks/glx/glsl/
```
