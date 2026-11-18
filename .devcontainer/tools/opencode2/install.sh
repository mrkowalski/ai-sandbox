#!/bin/bash
#
# install.sh (opencode2) - opencode v2 (@opencode/cli), into the npm prefix.
# Runs as node at image build.
#
# The package declares two bins, `opencode` and `opencode2`. Only `opencode2`
# is kept: `opencode` is the v1 bundle's name, and an undeclared binary on PATH
# would run v2 under it.
#
# The postinstall picks a platform binary and keeps the first one whose
# `--version` exits 0, with that check's output discarded, so a failure is
# reported only as "Failed to install OpenCode". So the postinstall is run
# here, and on failure each installed binary is re-run with its output shown.

set -euo pipefail

npm install -g --ignore-scripts @opencode/cli@latest

prefix="$(npm prefix -g)"
pkg="$(npm root -g)/@opencode/cli"
if ! (cd "$pkg" && node ./postinstall.mjs); then
  for bin in "$(npm root -g)"/@opencode/cli-*/bin/opencode; do
    [ -e "$bin" ] || continue
    printf 'install.sh (opencode2): %s --version:\n' "$bin" >&2
    "$bin" --version || printf 'install.sh (opencode2): exit %s\n' "$?" >&2
  done
  exit 1
fi

link="$prefix/bin/opencode"
case "$(readlink -f "$link" 2>/dev/null)" in
  "$pkg"/*) rm -f "$link" ;;
  *) printf 'install.sh (opencode2): %s is not @opencode/cli'"'"'s link; refusing to remove it\n' "$link" >&2; exit 1 ;;
esac
"$prefix/bin/opencode2" --version
