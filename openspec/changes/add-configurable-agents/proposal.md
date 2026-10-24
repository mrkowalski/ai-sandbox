# Proposal

## Why

Every coding agent is baked into the single sandbox image, and starting one needs its own hand-written shell function (`sbx-claude`, `sbx-opencode`). Everything that widens the sandbox (egress, host-network access) is hard-coded for all projects, so one project's need opens it for every project. A tool that needs more than a binary - writable directories, baked config, its own hook mechanism, its own hosts - has nowhere to declare it, and only Claude Code can be driven from an IDE over ACP.

## What Changes

- Draw one line through the sandbox. Anything that only restricts or is harmless on its own stays baked into the base image. Anything that widens reach becomes config: tools, egress hosts and IPv4 ranges, host-network access, and extra host folders. Config is the editable repo defaults file plus an optional per-project `.sbx/config`.
- Add tool bundles under `.devcontainer/tools/<name>/`. A bundle is everything a tool needs to work in the sandbox, enabled as one unit when a config lists the tool: the install step, any baked config files and hooks, its own scripts on `PATH` (helpers, or wrappers that add default flags to its binary) and interactive shell aliases, the hostnames and public IPv4 ranges it requires, its state volumes, and the directories it must be able to write. Claude runs in bypass-permissions mode without a flag; opencode brings its own writable directories and a host-only guard plugin. Bundles live only in this repo: a project selects them and cannot ship its own. A project's image contains only the tools its config enables. It is tagged by content hash and shared across projects. The shipped defaults enable no tools.
- ACP is standard. Every coding-agent bundle must declare its ACP server command (`claude-agent-acp`, `opencode acp`), so any enabled agent can be driven from an IDE with no further opt-in. **BREAKING**: `sbx-acp.sh <tool>` takes the agent name and runs that bundle's ACP command through `sbx`.
- Config keys: `tools`, `allow`/`deny` (hostnames or public IPv4 addresses and ranges), `host-network`, `mount`. The file is parsed, never sourced, and is mounted read-only inside the container. The launcher asks for approval the first time it sees a project config and whenever it changes.
- Add one host launcher, `bin/sbx [--rebuild] [--up] [--] <cmd> [args...]`. It runs any command exactly as typed inside the project's sandbox; there is no default command. A command that is not installed simply fails. The container is reused unless the resolved config changed. **BREAKING**: `sbx-up`/`sbx-claude`/`sbx-resume` leave the README.
- The image carries no whitelist. The host resolves the firewall policy (hosts and IPv4 ranges plus the host-network flag) and mounts it read-only. **BREAKING**: a bare `devcontainer up` no longer starts, and the Docker-host /24 is blocked unless the config sets `host-network = on`. `verify.sh` derives its expectations from the installed tools and the resolved config.

## Capabilities

### New Capabilities
- `sandbox-tools`: tool bundles (install, baked files and hooks, writable directories, hosts and IPv4 ranges, state volumes), the ACP entry every agent declares, images that contain only enabled tools, and policy delivery.
- `sandbox-config`: default and per-project config, which settings it may carry, the format, validation, approval, read-only exposure, whitelist composition, and extra mounts.
- `sandbox-launcher`: the `sbx` command, which covers running commands, container reuse and recreation, rebuilds, failure behavior, and launching an enabled agent as an ACP server.

### Modified Capabilities
- `firewall-enforcement`: the policy comes only from the host-resolved read-only mount, IPv4 entries are allowed as given, host-network access is opt-in, and blocked-host probes never use an allowed host.
- `docker-resource-naming`: the volume set depends on the enabled tools, and volumes take the `sbx-` prefix instead of `claude-code-`. Images get a shared content tag alongside the per-project tag.
- `host-only-commands`: the guard applies to every agent that offers a pre-execution hook (Claude Code's hook, opencode's plugin), all matching one shared list. Agents without such a hook receive the policy text only.

## Impact

`.devcontainer/` (Dockerfile split, `tools/`, `devcontainer.json`, `init-firewall.sh`, `host-only-guard.sh` split into a shared matcher plus the Claude adapter, `verify.sh`, `CLAUDE.md`), new `bin/sbx` and `.devcontainer/sbx-defaults.conf`, `sbx-env.sh`, `sbx-acp.sh`, README. Host state lives under `~/.local/state/sbx/<slug>/`. Greenfield: no migration and no backwards compatibility. Existing sandbox volumes and images are removed by hand, and each agent logs in again once.
