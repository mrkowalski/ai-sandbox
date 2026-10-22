# Proposal

## Why

Every coding agent is baked into the single sandbox image, and starting one needs its own hand-written shell function (`sbx-claude`, `sbx-opencode`). Everything that widens the sandbox (egress, host-network access) is hard-coded for all projects, so one project's need opens it for every project.

## What Changes

- Draw one line through the sandbox. Anything that only restricts or is harmless on its own stays baked into the base image. Anything that widens reach becomes config: tools, egress domains, host-network access, and extra host folders. Config is the editable repo defaults file plus an optional per-project `.sbx/config`.
- Add tool fragments under `.devcontainer/tools/<name>/`. Each holds the install step, the domains it needs, its state volumes, and the defaults it bakes in (Claude runs in bypass-permissions mode without a flag). A project's image contains only the tools its config enables. It is tagged by content hash and shared across projects. The shipped defaults enable no tools.
- Config keys: `tools`, `allow`/`deny`, `host-network`, `mount`. The file is parsed, never sourced, and is mounted read-only inside the container. The launcher asks for approval the first time it sees a project config and whenever it changes.
- Add one host launcher, `bin/sbx [--rebuild] [--up] [--] <cmd> [args...]`. It runs any command exactly as typed inside the project's sandbox; there is no default command. A command that is not installed simply fails. The container is reused unless the resolved config changed. **BREAKING**: `sbx-up`/`sbx-claude`/`sbx-resume` leave the README, and `sbx-acp.sh` calls `sbx claude-agent-acp`.
- The image carries no whitelist. The host resolves the firewall policy (domains plus the host-network flag) and mounts it read-only. **BREAKING**: a bare `devcontainer up` no longer starts, and the Docker-host /24 is blocked unless the config sets `host-network = on`. `verify.sh` derives its expectations from the installed tools and the resolved config.

## Capabilities

### New Capabilities
- `sandbox-tools`: tool fragments, images that contain only enabled tools, per-tool state volumes, domains, baked defaults, and policy delivery.
- `sandbox-config`: default and per-project config, which settings it may carry, the format, validation, approval, read-only exposure, whitelist composition, and extra mounts.
- `sandbox-launcher`: the `sbx` command, which covers running commands, container reuse and recreation, rebuilds, and failure behavior.

### Modified Capabilities
- `firewall-enforcement`: the policy comes only from the host-resolved read-only mount, host-network access is opt-in, and blocked-host probes never use an allowed host.
- `docker-resource-naming`: the volume set depends on the enabled tools. Images get a shared content tag alongside the per-project tag.
- `host-only-commands`: the guard hook applies to Claude Code sessions. Other agents receive the policy text, but not the hook.

## Impact

`.devcontainer/` (Dockerfile split, `tools/`, `devcontainer.json`, `init-firewall.sh`, `verify.sh`, `CLAUDE.md`), new `bin/sbx` and `.devcontainer/sbx-defaults.conf`, `sbx-env.sh`, `sbx-acp.sh`, README. Host state lives under `~/.local/state/sbx/<slug>/`. Existing Claude volumes are kept if the devcontainer id stays stable (see design).
