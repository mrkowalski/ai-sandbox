#!/bin/bash
#
# host-only-guard.sh - Claude Code adapter over the base host-only-check matcher.
#
# Guarantees:
#   - a Bash tool call whose command host-only-check declares host-only never
#     executes; the agent gets host-only-check's explanation instead;
#   - a payload that cannot be parsed is refused rather than allowed, unless
#     the raw payload carries the bypass token;
#   - every other call passes through untouched and silently.
#
# The list and the matching live in /usr/local/bin/host-only-check, shared with
# every other agent's adapter. This file only unwraps Claude Code's payload.
# Like the matcher, it is ergonomics, not containment.
#
# Invocation: registered as a PreToolUse hook for the Bash tool in
# /etc/claude-code/managed-settings.json. Claude Code writes the tool-input
# JSON to stdin. Exit 0 allows the call; exit 2 blocks it and feeds stderr back
# to the model. Exit 2 rather than a JSON permissionDecision because it is the
# least version-dependent blocking contract and does not go through the
# permission system, which bypass mode switches off.
#
# Also runnable standalone, which is how verify.sh probes it:
#   echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | host-only-guard.sh

set -euo pipefail
export LC_ALL=C

CHECK=/usr/local/bin/host-only-check
BYPASS_VAR="HOST_ONLY_GUARD_BYPASS"

PAYLOAD="$(cat)"

# Nothing to inspect: allow. An empty payload is not a policy failure.
[ -n "${PAYLOAD//[[:space:]]/}" ] || exit 0

TOOL=""
COMMAND=""
# Two separate extractions rather than one @tsv: @tsv escapes newlines, which
# would hide the structure of a multi-line command (heredocs above all) from
# the matcher.
if TOOL="$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // ""' 2>/dev/null)"; then
  COMMAND="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
else
  # Failing open would silently disable the policy, so refuse - but keep the
  # escape hatch alive by looking for the bypass token in the raw text,
  # otherwise a payload-format change would brick the session.
  if printf '%s' "$PAYLOAD" | grep -q "$BYPASS_VAR="; then
    printf 'host-only-guard: payload unparseable; %s found, allowing.\n' "$BYPASS_VAR" >&2
    exit 0
  fi
  printf 'host-only-guard: could not parse the hook payload, so the host-only\n' >&2
  printf 'policy cannot be applied. Refusing the command rather than ignoring\n' >&2
  printf 'the policy. Prefix the command with %s=1 to run it anyway,\n' "$BYPASS_VAR" >&2
  printf 'and report this - the guard needs updating on the host.\n' >&2
  exit 2
fi

[ "$TOOL" = "Bash" ] || exit 0
[ -n "${COMMAND//[[:space:]]/}" ] || exit 0

# Anything other than a clean 0 blocks: a matcher that cannot run must not
# degrade into "nothing is host-only".
rc=0
"$CHECK" "$COMMAND" || rc=$?
[ "$rc" -eq 0 ] || exit 2
exit 0
