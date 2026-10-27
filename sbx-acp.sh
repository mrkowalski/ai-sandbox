#!/bin/bash
#
# sbx-acp.sh - serve an enabled coding agent over ACP from inside the current
# folder's sandbox.
#
# Guarantees:
#   - a missing tool name, a tool with no bundle, a bundle that is not an
#     agent, and an agent the resolved config does not enable are refused
#     before anything runs, naming the enabled agents;
#   - stdin and stdout belong to the agent: every diagnostic goes to stderr,
#     which is appended to $SBX_ACP_LOG (default /tmp/sbx-acp.log);
#   - the launch goes through `sbx`, so config validation, the approval gate,
#     and container reuse are the same as for any other command. An unapproved
#     project config is refused, since there is no terminal to approve it on.
#
# Usage (as an editor's agent command, from the project folder):
#   sbx-acp.sh <tool>        e.g. sbx-acp.sh claude, sbx-acp.sh opencode

set -euo pipefail

SELF=$(readlink -f "${BASH_SOURCE[0]}")
ROOT=$(dirname "$SELF")
LOG=${SBX_ACP_LOG:-/tmp/sbx-acp.log}

exec 2>>"$LOG"
echo "=== sbx-acp $(date -Is) pwd=$PWD args=$* ===" >&2

# shellcheck source=sbx-env.sh
. "$ROOT/sbx-env.sh"

die() { printf 'sbx-acp: %s\n' "$*" >&2; exit 1; }

TOOL="${1:-}"
[ "$#" -eq 1 ] && [ -n "$TOOL" ] || die "usage: sbx-acp.sh <tool>"

sbx_resolve "$PWD" || die "invalid config for $PWD; nothing was started"

enabled_agents() {
    local t out=""
    for t in "${SBX_TOOLS[@]}"; do
        [ "${SBX_TOOL_TYPE[$t]:-}" = agent ] && out+="$t "
    done
    printf '%s' "${out% }"
}

mapfile -t AVAILABLE < <(sbx_available_tools)
if ! sbx_in "$TOOL" "${AVAILABLE[@]}"; then
    die "unknown tool '$TOOL' (enabled agents: $(enabled_agents | sed 's/^$/none/'))"
fi
if ! sbx_in "$TOOL" "${SBX_TOOLS[@]}"; then
    die "'$TOOL' is not enabled for $PWD (enabled agents: $(enabled_agents | sed 's/^$/none/'))"
fi
if [ "${SBX_TOOL_TYPE[$TOOL]}" != agent ]; then
    die "'$TOOL' is not an agent (enabled agents: $(enabled_agents | sed 's/^$/none/'))"
fi

read -r -a ACP <<<"${SBX_TOOL_ACP[$TOOL]}"
echo "sbx-acp: $TOOL -> ${ACP[*]}" >&2
exec "$ROOT/bin/sbx" -- "${ACP[@]}"
