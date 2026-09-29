#!/usr/bin/env bash
# Bake .qsb files for all (or one named) shader stage sources in shaders/.
#
# The GLSL version list is defined HERE, in one place. Do not inline it in
# docs or your shell history — always call this script. See
# bugs/overlay-screensaver-shaders-gles.md for why the ES targets are
# mandatory: some machines (e.g. zion) get OpenGL ES contexts from Qt, and
# shaders baked without ES variants fail to build pipelines there, drawing
# nothing.
#
# Usage:
#   tools/bake-shaders.sh            # re-bake every .frag/.vert in shaders/
#   tools/bake-shaders.sh starnest   # re-bake starnest.frag/.vert only
#
# After baking, each .qsb is verified with `qsb -d` to fail hard if any
# expected variant (including the GLSL ES ones) is missing.
set -euo pipefail
cd "$(dirname "$0")/.."

QSB=/usr/lib/qt6/bin/qsb
# Desktop GLSL + GLSL ES variants. 100es is deliberately NOT included: it
# fails for xmatrix/xmatrixcrt (GLSL ES 1.0 has no unsigned ints).
VERSIONS="300es,310es,320es,100,120,150,330,440"
# Versions qsb -d must report present: 100es→100 (es flag), etc.
EXPECT_ES="300 310 320"
EXPECT_DESKTOP="100 120 150 330 440"

if [ $# -gt 0 ]; then
    SOURCES=""
    for name in "$@"; do
        for stage in frag vert; do
            [ -f "shaders/${name}.${stage}" ] && SOURCES+=" shaders/${name}.${stage}"
        done
    done
    [ -n "$SOURCES" ] || { echo "no sources found for: $*" >&2; exit 1; }
else
    SOURCES=$(ls shaders/*.frag shaders/*.vert)
fi

for src in $SOURCES; do
    out="${src}.qsb"
    echo "baking $src -> $out"
    "$QSB" --glsl "$VERSIONS" "$src" -o "$out"

    # Verify: dump the baked shader and check each expected variant exists.
    dump=$("$QSB" -d "$out")
    missing=""
    for v in $EXPECT_ES; do
        [[ "$dump" == *"GLSL ${v} es"* ]] || missing="$missing ${v}es"
    done
    for v in $EXPECT_DESKTOP; do
        [[ "$dump" == *"GLSL ${v} ["* ]] || missing="$missing ${v}"
    done
    if [ -n "$missing" ]; then
        echo "ERROR: $out is missing variants:$missing" >&2
        exit 1
    fi
done
echo "OK: all baked .qsb files contain the GLSL ES and desktop variants."