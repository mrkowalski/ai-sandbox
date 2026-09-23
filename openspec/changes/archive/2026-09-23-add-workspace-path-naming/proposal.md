# Proposal

## Why

Every Docker resource the sandbox creates is named after `${devcontainerId}` — an opaque hash like `claude-code-npm-1c6jf25oqln0n9kejjqkb0o9m5ommccp1pg2o5nntmemaq4asm8o`. The volumes are already correctly isolated per project (that hash is derived from the workspace folder), so this is a legibility problem, not an isolation one: `docker volume ls` cannot tell the operator which project a volume belongs to, so reclaiming disk means guessing or deleting everything. Prefixing the names with the workspace path fixes that without giving up the key that keeps projects apart.

## What Changes

- Add `sbx-env.sh` at the repo root defining `sbx_slug()`: the absolute workspace path, leading `/` stripped, lowercased, every character outside `[a-z0-9_.-]` replaced with `-`, under `LC_ALL=C`. `/home/marcin/tools/sandbox` becomes `home-marcin-tools-sandbox`.
- Volume sources in `devcontainer.json` become `claude-code-{bashhistory,config,npm}-${localEnv:SBX_SLUG}-${devcontainerId}`. The slug leads, so a project's three volumes sort and filter together; `${devcontainerId}` stays as the suffix and remains the thing that guarantees two workspaces never share a volume, whatever the launcher does.
- `sbx-up` and `sbx-acp.sh` export `SBX_SLUG` before `devcontainer up`, and afterwards tag the resulting image `sbx-<slug>:latest` — `devcontainer up` has no `--image-name`, so the tag has to be applied after the fact.
- `verify.sh` gains a check that the three mounted volumes carry the slug for this workspace, reading the volume names out of `/proc/self/mountinfo` and comparing against a slug recomputed from `${localWorkspaceFolder}` (passed in as `SBX_WORKSPACE` via `containerEnv`). A missing or mismatched slug fails verification. With `${devcontainerId}` retained the consequence of a bad name is a mislabelled volume rather than a shared one, but a launcher that cannot name its own volumes does not know the naming rule, and this repo's convention is to fail loudly rather than degrade quietly.
- **BREAKING**: the new names designate new, empty volumes. The first `sbx-up` per project after this change starts with a fresh `/home/node/.claude` — Claude Code re-authenticates and `sbx-resume` has no history for that project. It happens once: because the id suffix is retained, a later launch that forgets the slug lands on its own volumes rather than on another project's.

## Capabilities

### New Capabilities
- `docker-resource-naming`: the sandbox's volumes and image are named after the workspace path they belong to, over a uniqueness key the launcher cannot omit, and verification reports whether the name is this workspace's.

### Modified Capabilities

None. `npm-cache` requires the cache be "scoped to a single dev container instance" so that "two dev containers do not share cache state"; `${devcontainerId}` is retained, so that partition is untouched and only the readable prefix is new.

## Impact

- `.devcontainer/devcontainer.json` (mounts, containerEnv), `.devcontainer/verify.sh` (one new section), `sbx-acp.sh`, `README.md` (the `.bashrc` block, the volume-maintenance section, and a new section documenting `sbx-acp.sh` — added because the migration caveat had nowhere else to live, the script being undocumented until now), plus the new `sbx-env.sh`.
- Nothing in the security contract moves: no mount is added or removed, no capability granted, no egress rule touched. The `.git` read-only bind and the workspace bind are untouched.
- Unverifiable from inside the container: the image-tagging step needs `docker` and the devcontainer CLI, neither of which exists in the sandbox. It has to be exercised on the host.
