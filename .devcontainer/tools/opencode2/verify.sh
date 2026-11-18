#!/bin/bash
#
# verify.sh (opencode2) - bundle check run by the base verify.sh (check 15),
# as node, in a child process. Asserts that opencode v2 reads the baked config
# dir, that its config loads the sandbox policy, that the guard is a v2 plugin
# calling the shared matcher, that the background server can start on the
# read-only config dir, and that v2 is not on PATH under v1's name.
#
# v2 skips a v1-shaped plugin (no default `{ id, setup }` export) with only a
# log warning, so the guard's shape is checked, not just its presence.
#
# No `set -e`: every check runs and reports, whatever an earlier one found.

set -uo pipefail
. /usr/local/lib/sbx/verify-lib.sh

OC_DIR=/etc/sbx/opencode2
OC_GUARD="$OC_DIR/plugin/host-only-guard.js"

if [ "${OPENCODE_CONFIG_DIR:-}" = "$OC_DIR" ]; then
  ok "opencode2: OPENCODE_CONFIG_DIR is $OC_DIR"
else
  bad "opencode2: OPENCODE_CONFIG_DIR is '${OPENCODE_CONFIG_DIR:-unset}', expected $OC_DIR - its policy and guard are not loaded"
fi

if jq -e --arg p "$HOST_ONLY_POLICY" '.instructions | index($p)' "$OC_DIR/opencode.json" >/dev/null 2>&1; then
  ok "opencode2: opencode.json loads the sandbox policy"
else
  bad "opencode2: $OC_DIR/opencode.json does not list $HOST_ONLY_POLICY in instructions"
fi

if grep -qF "$HOST_ONLY_CHECK" "$OC_GUARD" 2>/dev/null &&
   grep -q '^export default' "$OC_GUARD" &&
   grep -qF '"create.before"' "$OC_GUARD"; then
  ok "opencode2: v2 guard plugin is installed and calls $HOST_ONLY_CHECK"
else
  bad "opencode2: $OC_GUARD is missing, not a v2 plugin, or does not call $HOST_ONLY_CHECK"
fi

# Without a password here the server generates one and writes it back, which
# fails with EROFS and stops the TUI.
if jq -e '.password | type == "string" and length > 0' "$OC_DIR/service.json" >/dev/null 2>&1; then
  ok "opencode2: service.json holds the background server's password"
else
  bad "opencode2: $OC_DIR/service.json has no password - the TUI's server would fail with EROFS"
fi

if p=$(type -P opencode); then
  bad "opencode2: 'opencode' is on PATH ($p) - v2 would run under v1's name"
else
  ok "opencode2: no 'opencode' binary on PATH; v2 runs only as opencode2"
fi

verify_finish
