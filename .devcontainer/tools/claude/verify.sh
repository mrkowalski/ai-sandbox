#!/bin/bash
#
# verify.sh (claude) - bundle check run by the base verify.sh (check 15), as
# node, in a child process. Asserts that Claude Code's managed settings run
# the host-only guard hook, bypass permissions without a prompt, and that the
# sandbox policy is the managed CLAUDE.md; then drives the hook with a
# blocked and an allowed command.
#
# No `set -e`: every check runs and reports, whatever an earlier one found.

set -uo pipefail
. /usr/local/lib/sbx/verify-lib.sh

CC_SETTINGS=/etc/claude-code/managed-settings.json
CC_GUARD=/etc/claude-code/host-only-guard.sh

if [ -r "$CC_SETTINGS" ] && grep -qF "$CC_GUARD" "$CC_SETTINGS"; then
  ok "claude: managed settings register $CC_GUARD as a PreToolUse hook"
else
  bad "claude: $CC_SETTINGS does not reference $CC_GUARD - the guard would never run"
fi

if [ "$(jq -r '.permissions.defaultMode // ""' "$CC_SETTINGS" 2>/dev/null)" = bypassPermissions ] &&
   [ "$(jq -r '.skipDangerousModePermissionPrompt // false' "$CC_SETTINGS" 2>/dev/null)" = true ]; then
  ok "claude: managed settings bypass permissions with no confirmation prompt"
else
  bad "claude: managed settings do not set defaultMode bypassPermissions and skipDangerousModePermissionPrompt"
fi

if cmp -s /etc/claude-code/CLAUDE.md "$HOST_ONLY_POLICY"; then
  ok "claude: /etc/claude-code/CLAUDE.md is the sandbox policy"
else
  bad "claude: /etc/claude-code/CLAUDE.md is missing or differs from $HOST_ONLY_POLICY"
fi

for cmd in 'git commit -m x' 'git status'; do
  want=$([ "$cmd" = 'git status' ] && echo 0 || echo 2)
  out=$(jq -n --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}' | "$CC_GUARD" 2>&1)
  rc=$?
  if [ "$rc" -eq "$want" ]; then
    ok "claude: hook adapter exits $rc for '$cmd'"
  else
    bad "claude: hook adapter exited $rc for '$cmd', expected $want"
    [ -n "$out" ] && info "$(head -n 1 <<<"$out")"
  fi
done

verify_finish
