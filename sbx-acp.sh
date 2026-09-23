#!/bin/bash
#
# sbx-acp.sh - expose the sandboxed Claude Code as an ACP agent server.

set -uo pipefail

SBX=~/tools/sandbox/.devcontainer/devcontainer.json
SBX_ENV=~/tools/sandbox/sbx-env.sh
LOG=${SBX_ACP_LOG:-/tmp/sbx-acp.log}

# stderr is not part of the ACP stream, so it is the one place a diagnostic can
# go.
exec 2>>"$LOG"
echo "=== sbx-acp $(date -Is) pwd=$PWD ===" >&2

# devcontainer.json names this project's volumes
# `claude-code-<kind>-${localEnv:SBX_SLUG}-${devcontainerId}`. The id is what
# keeps them isolated, and the CLI derives it from the workspace folder, so
# launching without the slug exported is untidy rather than dangerous: the
# volumes are named `claude-code-config--<id>`, are still this project's alone,
# and are a second, stray set - no Claude Code credentials, a cold npm cache,
# and nothing that mounts them again. verify.sh reports that shape by name, but
# only for whoever runs verify.sh; nothing runs it at container start. Refusing
# here is the earlier, clearer stop.
# shellcheck source=sbx-env.sh
if ! . "$SBX_ENV"; then
    echo "sbx-acp: cannot source $SBX_ENV - refusing to launch unscoped" >&2
    exit 1
fi

if ! SBX_SLUG=$(sbx_slug); then
    echo "sbx-acp: no workspace slug for $PWD - refusing to launch unscoped" >&2
    exit 1
fi
export SBX_SLUG
echo "sbx-acp: workspace slug $SBX_SLUG" >&2

if ! devcontainer up --workspace-folder "$PWD" --config "$SBX" >>"$LOG" </dev/null; then
    echo "sbx-acp: 'devcontainer up' failed - see $LOG" >&2
    exit 1
fi

# Cosmetic, and deliberately not allowed to fail the launch: the container is
# already up and the ACP stream is what the caller is waiting for.
sbx_tag_image

exec devcontainer exec --workspace-folder "$PWD" --config "$SBX" claude-agent-acp
