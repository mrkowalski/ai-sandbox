#!/bin/bash
#
# verify.sh (opencode) - bundle check run by the base verify.sh (check 15), as
# node, in a child process. Asserts that opencode reads the baked config dir,
# that its config loads the sandbox policy, and that the v1 guard plugin is
# installed and calls the shared matcher.
#
# No `set -e`: every check runs and reports, whatever an earlier one found.

set -uo pipefail
. /usr/local/lib/sbx/verify-lib.sh

OC_DIR=/etc/sbx/opencode

if [ "${OPENCODE_CONFIG_DIR:-}" = "$OC_DIR" ]; then
  ok "opencode: OPENCODE_CONFIG_DIR is $OC_DIR"
else
  bad "opencode: OPENCODE_CONFIG_DIR is '${OPENCODE_CONFIG_DIR:-unset}', expected $OC_DIR - its policy and guard are not loaded"
fi

if jq -e --arg p "$HOST_ONLY_POLICY" '.instructions | index($p)' "$OC_DIR/opencode.json" >/dev/null 2>&1; then
  ok "opencode: opencode.json loads the sandbox policy"
else
  bad "opencode: $OC_DIR/opencode.json does not list $HOST_ONLY_POLICY in instructions"
fi

if grep -qF "$HOST_ONLY_CHECK" "$OC_DIR/plugin/host-only-guard.js" 2>/dev/null; then
  ok "opencode: guard plugin is installed and calls $HOST_ONLY_CHECK"
else
  bad "opencode: $OC_DIR/plugin/host-only-guard.js is missing or does not call $HOST_ONLY_CHECK"
fi

verify_finish
