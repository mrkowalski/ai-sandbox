## Why

OpenSpec is baked into every image (`Dockerfile`: `npm install -g @fission-ai/openspec@latest`, `OPENSPEC_TELEMETRY=0`), although only projects that plan with it use it. It is a workflow tool, not part of the sandbox's contract, so it should be selected per project like any other tool.

## What Changes

- New `openspec` tool bundle (`type = tool`): installs the npm package and sets `OPENSPEC_TELEMETRY=0`. No hosts, volumes, or probe.
- Remove the OpenSpec install and env from the base `Dockerfile`.
- **BREAKING**: a project that runs `openspec` inside the sandbox must add it to `tools` (e.g. `tools = claude openspec`). The shipped defaults stay `tools =`.
- Drop openspec from the base lists in `README.md` and `.devcontainer/CLAUDE.md`.

## Capabilities

### New Capabilities

### Modified Capabilities
- `sandbox-tools`: OpenSpec moves from the base image to an optional bundle. The capability is introduced by the in-progress `add-configurable-agents` change, so this change archives after it.

## Impact

`.devcontainer/Dockerfile`, new `.devcontainer/tools/openspec/`, `README.md`, `.devcontainer/CLAUDE.md`. `verify.sh` needs no edit: its bundle checks (binaries on `PATH` from read-only dirs) are driven by `tools.list` and `tool.conf`. Images without the bundle get a new content hash and rebuild once.
