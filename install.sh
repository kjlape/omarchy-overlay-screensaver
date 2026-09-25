#!/usr/bin/env bash

# Install the overlay-screensaver CLI. The plugin itself is installed by the
# Omarchy CLI -- `omarchy plugin add <this-repo> --enable` -- which clones the
# repo into ~/.config/omarchy/plugins/kjlape.overlay-screensaver, validates
# the manifest, and enables the service. All this script adds is the
# `omarchy-overlay-screensaver` command on PATH.

set -euo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

Installs the omarchy-overlay-screensaver CLI to ~/.local/bin.

Options:
  --system     Also install the CLI to /usr/local/bin (needs sudo) so that
               `ssh box omarchy-overlay-screensaver ...` resolves without a
               full path.
  -h, --help   Show this help.

The plugin is installed separately with the Omarchy CLI:

  omarchy plugin add https://github.com/kjlape/omarchy-overlay-screensaver.git --enable
USAGE
}

while (( $# )); do
  case $1 in
    --system) SYSTEM=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install: unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

fail() { echo "install: $1" >&2; exit 1; }

(( EUID != 0 )) || fail "run this as your desktop user, not root"

mkdir -p "$HOME/.local/bin" "$HOME/.local/share/overlay-screensaver"
install -m 755 "$REPO_DIR/bin/omarchy-overlay-screensaver" "$HOME/.local/bin/omarchy-overlay-screensaver"
install -m 644 "$REPO_DIR/config/overlay-screensaver.example.json" \
  "$HOME/.local/share/overlay-screensaver/config.example.json"
echo "installed $HOME/.local/bin/omarchy-overlay-screensaver"
echo "installed $HOME/.local/share/overlay-screensaver/config.example.json"

if (( ${SYSTEM:-0} )); then
  sudo install -m 755 "$REPO_DIR/bin/omarchy-overlay-screensaver" /usr/local/bin/omarchy-overlay-screensaver
  echo "installed /usr/local/bin/omarchy-overlay-screensaver"
fi

cat <<'DONE'

Done. If you have not added the plugin yet:

  omarchy plugin add https://github.com/kjlape/omarchy-overlay-screensaver.git --enable

Then check it with:

  omarchy-overlay-screensaver status

DONE