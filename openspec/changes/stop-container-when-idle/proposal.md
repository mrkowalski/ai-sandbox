# Proposal

## Why

The project's container keeps running after `sbx` exits. On Docker Desktop it holds the project folder's bind mounts, including the read-only `.git` bind. So a folder deleted on the host comes back containing only `.git`. The sandbox, not the user, should make sure that once no `sbx` session is using a folder, nothing keeps that folder pinned or recreates it.

## What Changes

- `sbx` stops the project's container when its last session exits, including sessions started with `sbx-acp.sh`. The next launch starts the container again, and the entrypoint reinstalls the firewall as it does on every start.
- `sbx` no longer `exec`s the command. It waits for the command, then stops the container if no other session is using it. It still exits with the command's status and prints nothing to stdout.
- `sbx --up` with no command stops the container again after it comes up and verifies, unless a session is using it.
- Neither `sbx` nor `initializeCommand` creates the project folder any more. A launch from a folder that no longer exists fails.

## Capabilities

### New Capabilities
- `container-lifecycle`: when the project's container runs and when it stops, and the guarantee that the sandbox never creates or pins a project folder no session is using.

### Modified Capabilities
None in `openspec/specs/`. The `sandbox-launcher` spec in the unarchived `add-configurable-agents` change has a scenario saying "the container stays up" after a failed command. That scenario is edited in place (see tasks).

## Impact

`bin/sbx`, `.devcontainer/devcontainer.json` (`initializeCommand`), `.devcontainer/CLAUDE.md` section 1 and 8, README, `host-checklist.txt`. Every launch after an idle period pays the full start cost again: firewall install and `verify.sh`. Nothing changes inside the container, so there is no new `verify.sh` assertion. This is a host-side lifecycle change, and `verify.sh` cannot observe it from inside.
