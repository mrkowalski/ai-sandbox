## Why

`git push` already fails in the sandbox — there are no SSH keys, no credential helper, and the forge is not on the egress whitelist — but it fails opaquely, so the agent discovers the wall instead of being told about it. `git commit` and the other history-writing commands are worse: they *succeed*, so the agent can write into the user's real repository from a container that exists precisely so it cannot act outside the workspace. Git history in the mounted project must be the host operator's alone, and that has to be enforced, not merely asked for.

## What Changes

- **Containment**: the mounted project's `.git` is bind-mounted read-only, so every git write against the workspace fails regardless of the command filter, the permission mode, or whether the write came from a script. Reads are untouched — `status`, `diff`, `log`, `show`, `branch`, `tag -l` all work with no warning.
- **Explanation**: `host-only-commands.txt` declares `git push`, `git commit`, `merge`, `rebase`, `cherry-pick`, `revert`, `am`, the mutating `git tag` forms, and the staging commands `add`, `stash`, `rm`, `mv`, so the agent gets a handoff instead of an unexplained `Permission denied`. `gh`'s account-touching subcommands are declared for the same reason.
- **Instruction**: the agent is told not to *propose* these commands or ask to be allowed to run them — it recommends the git operation and states plainly that it is not possible in here.
- **BREAKING for the agent's workflow**: `git add`, `git stash`, and `git checkout -b` stop working in the mounted project. The agent prepares changes in the working tree and shows them with `git diff`; staging and committing happen on the host.
- Start-time verification asserts the new guarantee in both directions — a write to the workspace `.git` must fail, a read must succeed — plus the absence of SSH keys, a forwarded agent, and a credential helper.
- An `initializeCommand` pre-creates the mount source on the host, so launching on a folder that is not a repository leaves a user-owned empty `.git` rather than a root-owned one needing `sudo` to remove.

## Capabilities

### New Capabilities

- `git-write-protection`: the mounted project's repository cannot be modified from inside the sandbox, reads stay fully available, scratch repositories outside the workspace still work, and no git credentials are present.

### Modified Capabilities

- `host-only-commands`: the requirement fixing the list's contents to wrangler alone is replaced — it also declares the git and `gh` commands above. A new requirement holds each entry to stating accurately *why* its command is refused and which mechanism enforces it, since the list now mixes commands stopped by the firewall, by the read-only mount, and by the filter alone.

## Impact

- `.devcontainer/devcontainer.json` — a read-only bind mount of the workspace `.git`, plus `initializeCommand`. This file is part of the security contract; changing it changes the sandbox's guarantees.
- `.devcontainer/verify.sh` — a new check for the write protection and for absent credentials; git and `gh` samples added to the host-only guard probes.
- `.devcontainer/host-only-commands.txt` — new entries and a revised header.
- `.devcontainer/sandbox-policy.md` (installed as `/etc/claude-code/CLAUDE.md`) — rationale widened beyond "credentials live on the host".
- `.devcontainer/CLAUDE.md`, `README.md` — the architecture notes and the "does not allow `git push`" claim.
- No change to `host-only-guard.sh`: its matching, normalization, and bypass carry the new entries unchanged.
- Requires a host-side rebuild; none of it can be exercised from inside the sandbox.
