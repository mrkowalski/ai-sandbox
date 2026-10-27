#!/bin/bash
#
# install.sh (opencode) - opencode, into the npm prefix. Runs as node at
# image build.
#
# opencode-ai's postinstall picks a platform binary and keeps the first one
# whose `--version` exits 0, with that check's output discarded. When every
# glibc binary fails it falls through to the musl ones, and npm reports only
# their EBADPLATFORM, which hides the real cause. So the postinstall is run
# here, and on failure each installed binary is re-run with its output shown.

set -euo pipefail

npm install -g --ignore-scripts opencode-ai@latest

pkg="$(npm root -g)/opencode-ai"
if ! (cd "$pkg" && node ./postinstall.mjs); then
  for bin in "$pkg"/node_modules/opencode-*/bin/opencode; do
    [ -e "$bin" ] || continue
    printf 'install.sh (opencode): %s --version:\n' "$bin" >&2
    "$bin" --version || printf 'install.sh (opencode): exit %s\n' "$?" >&2
  done
  exit 1
fi
