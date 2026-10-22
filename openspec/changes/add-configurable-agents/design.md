# Design

## Context

Today `.devcontainer/Dockerfile` bakes Claude Code, `claude-agent-acp` and OpenSpec. `devcontainer.json` is static: four volumes, a `build` section, and `postStartCommand`. `init-firewall.sh` reads `/usr/local/etc/allowed-domains.txt` under `sudo`, which resets the environment, so paths are effectively fixed. It also always ACCEPTs the Docker host's /24. Launching goes through README shell functions plus `sbx-acp.sh`. The rest of the context is in proposal.md.

## Goals / Non-Goals

**Non-Goals:**
- A user-level config layer (`~/.config/sbx`); edit the repo defaults instead.
- Docker Compose.
- A host-only guard for opencode (see Risks).
- Making restrictions or base tooling (uv, npm cache) switchable.
- A fully offline project: an empty effective whitelist still aborts firewall setup, as it does today.

## Decisions

**Base vs config: one rule.** If a part only restricts the sandbox, or is harmless on its own, it is baked into the base image and cannot be configured. If it widens what the sandbox can reach, it is config.

| Part | Where | Why |
|---|---|---|
| Default-deny firewall, entrypoint gate, seal, `verify.sh` | base | restricts |
| Read-only rootfs, `noexec` `/tmp`, read-only `.git` and `.sbx` binds | base | restricts |
| No credentials, host-only list and guard, sandbox policy text | base | restricts |
| `NET_ADMIN`/`NET_RAW`, the two sudoers entries | base | needed to install the firewall; node cannot use them beyond the two scripts, which only read read-only policy |
| git, gh, node/npm, uv/python, jq, openspec | base | harmless without egress or credentials |
| npm, uv, and bash-history volumes | base | per project, no new reach |
| Egress domains, including npm, PyPI, and Anthropic | config `allow`/`deny` | every domain is an exfiltration path |
| Tools (binary + domains + credential volumes) | config `tools` | reach comes through their domains and stored credentials |
| Docker-host /24 | config `host-network`, default off | reaches services on the host |
| Extra host folders | config `mount`, read-only default | exposes host data |

The shipped `.devcontainer/sbx-defaults.conf` contains `tools =` (none) and `allow` lines for the npm registry, PyPI, and the Cloudflare docs, which are today's base list minus Claude's hosts. The user widens the defaults by editing that file.

**Image: one Dockerfile, `TOOLS` build arg.** The base stages stay as they are, minus the Claude-specific lines and minus the `allowed-domains.txt` copy. Then `COPY tools/ /usr/local/share/sbx/tools/`, `RUN` each selected `tools/<name>/install.sh`, and write `/usr/local/share/sbx/tools.list`. The launcher builds with `docker build --build-arg TOOLS="claude opencode"` and tags `sbx-img:<hash>`. The hash covers `.devcontainer/` (excluding `CLAUDE.md`, `sbx-defaults.conf`) and the sorted tool list. Domains are not in the hash, because they never enter the image. Docker's layer cache shares the base across every combination.
*Alternative:* one image per tool `FROM sbx-base`. This needs N images for N tools and cannot run two agents in one container, which the user does today (`sbx-claude` and `sbx-opencode` against the same project).

**Tool fragment.** `.devcontainer/tools/<name>/` holds:
- `install.sh`: runs as `node` at build and writes only to the npm prefix or `/usr/local/share/sbx/<name>`. An optional `install-root.sh` handles baked settings under `/etc`.
- `allowed-domains.txt`: the hosts the tool requires.
- `tool.conf`: the same parser as the config. Keys: `bin` (repeatable, checked on `PATH`), `volume = <kind>:<path>` (repeatable), `env = KEY=VALUE` (repeatable), `probe = <url>`. There is no start command.

`claude`:
- Installs Claude Code and `claude-agent-acp`.
- Writes `managed-settings.json` to `/etc/claude-code/`, now with `permissions.defaultMode = "bypassPermissions"` alongside the guard hook.
- Copies the policy to `/etc/claude-code/CLAUDE.md`.
- Declares `volume = config:/home/node/.claude` and `env = CLAUDE_CONFIG_DIR=/home/node/.claude`.
- Owns the Anthropic, statsig, and sentry hosts.

`opencode`:
- Installs `npm i -g opencode-ai`.
- Bakes `/etc/sbx/opencode.json` with `instructions: ["/etc/sbx/sandbox-policy.md"]`, and sets `env = OPENCODE_CONFIG=/etc/sbx/opencode.json`.
- Declares volumes for `~/.config/opencode` and `~/.local/share/opencode`.
- Its domains are confirmed in task 2.3.

`sandbox-policy.md` becomes agent-neutral, at `/etc/sbx/sandbox-policy.md` in the base.

**Config format.** `key = value`, `#` comments, whitespace-trimmed, parsed in bash with `read` and never `source`d. Sourcing a cloned repo's file would run its code on the host.
- `tools`: space-separated; the project value replaces the default.
- `allow`, `deny`: repeatable, one hostname each, validated against `^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$`.
- `host-network`: `on` or `off`.
- `mount`: repeatable, `<abs path>[:rw]`. The path is resolved with `realpath`, and ancestry is checked on resolved paths so a symlink cannot sneak past the protected-path rule. Protected from `:rw`: this repo and `~/.local/state/sbx`, and every ancestor of either.

*Alternatives:* YAML/TOML would need `yq` or Python on the host. JSON/`jq` is unfriendly to hand-edit and has no comments.

**Launcher = `bin/sbx` driving the devcontainer CLI.** Grammar: `sbx [--rebuild] [--up] [--] <cmd> [args...]`. Option parsing stops at the first non-option or `--`. No command without `--up` prints usage and exits 2. Steps:
1. Resolve and validate the config.
2. Run the approval gate.
3. Compute the image hash and build if the tag is missing; `--rebuild` passes `--no-cache` and always builds.
4. Write `~/.local/state/sbx/<slug>/policy/` (`allowed-domains.txt`, `firewall.conf` with `HOST_NETWORK=0|1`) and a generated `devcontainer.json`.
5. `devcontainer up --config .devcontainer/devcontainer.json --override-config <generated>`, adding `--remove-existing-container` only when the running container's `sbx.config` label differs from the hash of the resolved config plus the image.
6. `sbx_tag_image`.
7. `devcontainer exec ... "$@"`, propagating its exit status.

The generated config is the static one with:
- `build` replaced by `"image": "sbx-img:<hash>"`
- `--label=sbx.config=<hash>` added to `runArgs`
- the tool volumes and env
- a read-only bind of the policy dir at `/usr/local/etc/sbx`
- a read-only bind of `<workspace>/.sbx` when it exists
- the `mount` entries

Keeping `--config` constant is meant to keep `devcontainerId`, and with it the existing Claude volumes, stable. Task 1.1 checks this.
*Alternatives:* Compose, or plain `docker run`. Either one would re-specify the entrypoint and `overrideCommand` pinning, `postStartCommand` verification, and `devcontainerId` naming that `firewall-enforcement` and `docker-resource-naming` already rest on.

**Firewall reads `/usr/local/etc/sbx/`.** `init-firewall.sh` changes its default path to `/usr/local/etc/sbx/allowed-domains.txt` and reads `HOST_NETWORK` from `/usr/local/etc/sbx/firewall.conf`. It parses `firewall.conf` with `grep`, not `source`, for the same data-not-code reason. It adds the host /24 INPUT and OUTPUT ACCEPTs only when the flag is `1`. Fixed paths keep `sudo` and sudoers unchanged. The image ships an empty mount point, so a launch without the mount aborts on the unreadable whitelist. That path is already sealed and fatal under `firewall-enforcement`. A missing source dir on `docker start` makes Docker refuse to start the container, which also fails closed.

**Approval gate.** `~/.local/state/sbx/<slug>/approved` stores the sha256 of `.sbx/config`. On a mismatch, `sbx` prints the delta against the defaults (tools, domains, host-network, mounts) and prompts, defaulting to No. Without a TTY it refuses. The read-only `.sbx` mount stops edits made from inside a running container. The gate catches files written before that, by a cloned repo, or through a writable `mount`.

**verify.sh.**
- Check 1 picks its must-be-blocked probe hosts from a candidate list (`example.com`, `github.com`, `example.org`, ...), skipping any host in the mounted whitelist.
- Check 3 probes each installed tool's `probe`.
- Check 4 also asserts that the host /24 ACCEPT rule is present exactly when `HOST_NETWORK=1`.
- Check 7 builds its expected kinds from `tools.list` plus each `tool.conf` `volume`.
- A new check asserts each tool's `bin` is on `PATH` with a read-only package dir.
- Another new check asserts that `.sbx` is read-only when it exists.
- Another new check asserts that `/usr/local/etc/sbx` is read-only and not inside the workspace.

## Risks / Trade-offs

- [`--override-config` might change `devcontainerId` or not merge as assumed] → task 1.1 spikes this first, on the host. Fallback: pass the generated file as `--config`. That changes the id once, so a one-time Claude re-login and cold caches. Document the cleanup of the old volumes.
- [Claude may still show its one-time bypass-mode confirmation, or ignore `defaultMode` from managed settings] → task 2.2 checks both. Fallback: add `skipDangerousModePermissionPrompt` to the baked settings. If neither works, a host alias that adds the flag.
- [`host-network` defaulting to off removes access that exists today, such as opencode talking to a model server on the host] → set `host-network = on` in that project's config. Nothing in the sandbox's own launch path needs it, because `devcontainer exec` goes through the Docker socket on the host.
- [opencode has no `PreToolUse`-style hook wired up] → the guard is ergonomics, not containment (`.devcontainer/CLAUDE.md` section 6). opencode gets the policy text. A plugin-based guard is a follow-up.
- [The approval gate is trust-on-first-use, so a user who confirms without reading widens the sandbox] → the prompt lists every added host and mount explicitly, and defaults to No.
- [Shipped defaults with no tools make the first `sbx claude` in a new project fail with command-not-found] → this is intended. The README shows the one-line `.sbx/config` and the option to add `claude` to the defaults file.
- [Image count grows with distinct tool combinations] → base layers are shared. Prune old images with `docker images sbx-img`, which the README covers.
- [The volume prefix stays `claude-code-` for non-Claude tools] → this is accepted to keep existing volume names, and with them existing Claude credentials. Renaming the prefix can be its own change.

## Migration Plan

1. After implementation, add `tools = claude` (plus `opencode` where used) to the defaults file or to each project's `.sbx/config`. Projects that relied on reaching the Docker host also need `host-network = on`.
2. Run `sbx --up` once per project. It recreates the container from the new image, and if task 1.1 holds, keeps the existing volumes.
3. Replace `sbx-up`, `sbx-claude`, `sbx-resume`, and `sbx-opencode` in `.bashrc` with `~/tools/sandbox/bin` on `PATH`.
4. Rollback: check out the previous commit and use the old `.bashrc` functions. The new image cannot be started without `sbx`.
