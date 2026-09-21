#!/bin/bash
#
# sbx-acp.sh - expose the sandboxed Claude Code as an ACP agent server.

set -uo pipefail

SBX=~/tools/sandbox/.devcontainer/devcontainer.json
LOG=${SBX_ACP_LOG:-/tmp/sbx-acp.log}

# stderr is not part of the ACP stream, so it is the one place a diagnostic can
# go.
exec 2>>"$LOG"
echo "=== sbx-acp $(date -Is) pwd=$PWD ===" >&2

if ! devcontainer up --workspace-folder "$PWD" --config "$SBX" >>"$LOG" </dev/null; then
    echo "sbx-acp: 'devcontainer up' failed - see $LOG" >&2
    exit 1
fi

exec devcontainer exec --workspace-folder "$PWD" --config "$SBX" claude-agent-acp
