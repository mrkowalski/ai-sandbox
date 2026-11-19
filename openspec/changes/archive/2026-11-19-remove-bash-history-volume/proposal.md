# Proposal

## Why

The sandbox keeps interactive bash history on a per-project `/commandhistory` volume. Nothing depends on it, and agents get nothing from it because their shells are non-interactive. It is also a writable location that persists across restarts, so an agent can plant a command there that the user later re-runs with up-arrow.

## What Changes

- Remove the `sbx-bashhistory-*` volume, the `/commandhistory` directory, and the `HISTFILE`/`PROMPT_COMMAND` snippet. Interactive shells keep history in memory for the session only.
- Drop the volume from verification and from the launcher's protected-path list.

## Capabilities

### New Capabilities

### Modified Capabilities
- `docker-resource-naming`: the base volumes are npm cache and uv cache only.

## Impact

`.devcontainer/Dockerfile`, `.devcontainer/devcontainer.json`, `.devcontainer/verify.sh`, `sbx-env.sh`, `README.md`, `CLAUDE.md`, `.devcontainer/CLAUDE.md`. Existing `sbx-bashhistory-*` volumes on the host are left orphaned until the user removes them.
