#!/usr/bin/env bash

# Remove the overlay-screensaver CLI. The plugin itself is removed by the
# Omarchy CLI: `omarchy plugin remove kjlape.overlay-screensaver`, which
# disables it first.

set -euo pipefail

for bin in "$HOME/.local/bin/omarchy-overlay-screensaver" /usr/local/bin/omarchy-overlay-screensaver; do
  [[ -e $bin ]] || continue
  if [[ -w $(dirname "$bin") ]]; then rm -f "$bin"; else sudo rm -f "$bin"; fi
  echo "removed $bin"
done

cat <<'DONE'
Done. Remove the plugin itself with:

  omarchy plugin remove kjlape.overlay-screensaver

DONE