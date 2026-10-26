# Design

## Context

Today `.devcontainer/Dockerfile` bakes Claude Code, `claude-agent-acp` and OpenSpec. `devcontainer.json` is static: four volumes, a `build` section, and `postStartCommand`. `init-firewall.sh` reads `/usr/local/etc/allowed-domains.txt` under `sudo`, which resets the environment, so paths are effectively fixed. It also always ACCEPTs the Docker host's /24. Launching goes through README shell functions plus `sbx-acp.sh`. The rest of the context is in proposal.md.

Greenfield: no migration and no backwards compatibility. Existing sandbox volumes and images are removed by hand, and each agent logs in again once.

## Goals / Non-Goals

**Non-Goals:**
- A user-level config layer (`~/.config/sbx`); edit the repo defaults instead.
- Docker Compose.
- Project-supplied tool bundles. Bundles live in `.devcontainer/tools/` only, so a cloned project's install scripts never reach the image.
- Making restrictions or base tooling (uv, npm cache) switchable.
- A fully offline project: an empty effective whitelist still aborts firewall setup, as it does today.
- Private IPv4 ranges in a whitelist. The Docker host is reached through `host-network` only; other LAN access stays out of scope.

## Decisions

**Base vs config: one rule.** If a part only restricts the sandbox, or is harmless on its own, it is baked into the base image and cannot be configured. If it widens what the sandbox can reach, it is config.

| Part | Where | Why |
|---|---|---|
| Default-deny firewall, entrypoint gate, seal, `verify.sh` | base | restricts |
| Read-only rootfs, `noexec` `/tmp`, read-only `.git` and `.sbx` binds | base | restricts |
| No credentials, host-only list and shared guard matcher, sandbox policy text | base | restricts |
| `NET_ADMIN`/`NET_RAW`, the two sudoers entries | base | needed to install the firewall; node cannot use them beyond the two scripts, which only read read-only policy |
| git, gh, node/npm, uv/python, jq, openspec | base | harmless without egress or credentials |
| npm, uv, and bash-history volumes | base | per project, no new reach |
| Egress hostnames and public IPv4 ranges, including npm, PyPI, and a model provider for an agent that lets the user choose one | config `allow`/`deny` | every entry is an exfiltration path |
| Tools (bundle: binary, baked files and hooks, scripts and aliases, ACP entry, hosts and IPv4 ranges, state volumes, writable directories) | config `tools` | reach comes through their hosts and stored credentials |
| Docker-host /24 | config `host-network`, default off | reaches services on the host |
| Extra host folders | config `mount`, read-only default | exposes host data |

The shipped `.devcontainer/sbx-defaults.conf` contains `tools =` (none) and `allow` lines for the npm registry, PyPI, and the Cloudflare docs, which are today's base list minus Claude's hosts. The user widens the defaults by editing that file.

**Image: one Dockerfile, `TOOLS` build arg.** The base stages stay as they are, minus the Claude-specific lines and minus the `allowed-domains.txt` copy. Then `COPY tools/ /usr/local/share/sbx/tools/`, `RUN` each selected `tools/<name>/install.sh`, and write `/usr/local/share/sbx/tools.list`. The launcher builds with `docker build --build-arg TOOLS="claude opencode"` and tags `sbx-img:<hash>`. The hash covers `.devcontainer/` (excluding `CLAUDE.md`, `sbx-defaults.conf`) and the sorted tool list. Domains are not in the hash, because they never enter the image. Docker's layer cache shares the base across every combination.
*Alternative:* one image per tool `FROM sbx-base`. This needs N images for N tools and cannot run two agents in one container, which the user does today (`sbx-claude` and `sbx-opencode` against the same project).

**Tool bundle.** `.devcontainer/tools/<name>/` is the whole unit a config enables with `tools`; nothing outside it is tool-specific. Nothing in it can weaken the base: install scripts only write the image, and every runtime grant is a `tool.conf` key the launcher validates. It holds:
- `install.sh`: runs as `node` at build and writes only to the npm prefix or `/usr/local/share/sbx/<name>`. An optional `install-root.sh` places baked settings, hook scripts, and plugins under `/etc/<tool>` or `/etc/sbx/<name>/`.
- Any further files the install scripts copy (config templates, hook scripts, plugins). They end up in the read-only rootfs, never in a volume or the workspace.
- `bin/` (optional): executable scripts. The build copies every selected bundle's `bin/*` into `/usr/local/share/sbx/bin/`, which the base puts first on `PATH`, ahead of the npm prefix. Two bundles shipping the same name fail the build, and so does a name that shadows a base command (anything on the base image's `PATH`, such as `git` or `verify.sh`) other than one of the bundle's own `bin` entries. A script is either a helper command or a wrapper with the same name as the tool's binary that `exec`s the real binary by absolute path with extra arguments. Wrappers are how a bundle aliases a command: `sbx <cmd>` and ACP run no interactive shell, so bash aliases never apply there.
- `shell.sh` (optional): aliases and functions for interactive shells only (`sbx bash`). The base `/etc/bash.bashrc` sources `/usr/local/share/sbx/tools/<name>/shell.sh` for each entry in `tools.list`.
- `allowed-domains.txt`: the hostnames, and public IPv4 addresses or CIDR ranges, the tool requires under every configuration. Same validation as config `allow`. A bundle host cannot be denied, so a host the user chooses, such as a model provider, is not a bundle host; the project adds it with `allow`.
- `tool.conf`: the same parser as the config. Keys:
  - `type = agent | tool` (required). An `agent` must also declare `acp` and must load the sandbox policy.
  - `bin` (repeatable, checked on `PATH`).
  - `acp = <command> [args...]`: the ACP server on stdio. Its first word must be one of the `bin` entries.
  - `volume = <kind>:<path>` (repeatable): persistent writable state, a named per-project volume `sbx-<name>-<kind>-<slug>-<devcontainerId>`. Base volumes are `sbx-<kind>-<slug>-<devcontainerId>` (`bashhistory`, `npm`, `uv`).
  - `tmpfs = <path>` (repeatable): writable scratch, `noexec,nosuid`, discarded on recreation.
  - `env = KEY=VALUE` (repeatable).
  - `probe = <url>`.

There is no start command. The rootfs stays read-only, so a tool's write outside the workspace, its `volume`s, and its `tmpfs`es fails, and that is how a missing declaration shows up.

`claude`:
- `type = agent`, `acp = claude-agent-acp`.
- Installs Claude Code and `claude-agent-acp`.
- Writes `managed-settings.json` to `/etc/claude-code/`, now with `permissions.defaultMode = "bypassPermissions"` and `skipDangerousModePermissionPrompt = true` alongside the guard hook, which calls the base matcher. Settings, not a wrapper, because `claude-agent-acp` reads them too.
- Copies the policy to `/etc/claude-code/CLAUDE.md`.
- Declares `volume = config:/home/node/.claude` and `env = CLAUDE_CONFIG_DIR=/home/node/.claude`.
- Owns the Anthropic, statsig, and sentry hosts.

`opencode`:
- `type = agent`, `acp = opencode acp`.
- Installs `npm i -g opencode-ai`.
- Bakes `/etc/sbx/opencode/` and sets `env = OPENCODE_CONFIG_DIR=/etc/sbx/opencode`. It holds `opencode.json` with `instructions: ["/etc/sbx/sandbox-policy.md"]`, and `plugin/host-only-guard.js`, a `tool.execute.before` plugin that hands each bash command to the base matcher and throws its message on a match.
- Declares volumes for `~/.config/opencode`, `~/.local/share/opencode`, `~/.local/state/opencode`, and `~/.cache/opencode`: the four directories it wrote on the read-only rootfs in task 1.3 (opencode 1.19.4). The cache holds binaries it downloads and executes, so it is a volume, not a noexec tmpfs.
- Domains (task 1.3): `models.opencode.ai` (model catalogue) only, and `probe = https://models.opencode.ai/`. opencode works with any model provider, so the bundle names none: the project adds its provider with `allow` (`api.anthropic.com`, `api.openai.com`, ...) or reaches a model server on the host with `host-network = on`. A bundle-owned provider could not be denied and would open Anthropic to every opencode project. With no provider allowed, opencode starts and its requests to the model fail. `registry.npmjs.org`, which it uses for a background install of `@opencode-ai/plugin` into `~/.config/opencode`, is a warning only and stays in the defaults rather than the bundle. It downloads ripgrep from `github.com` unless `rg` is on `PATH`, so `install-root.sh` installs Debian's `ripgrep`; this is the one bundle that adds a system package.
- Task 1.3 confirmed the plugin loads from a read-only `OPENCODE_CONFIG_DIR` and blocks `git commit` with the `host-only-check` message, and that the policy reaches the system prompt through `instructions`. The plugin imports nothing from `@opencode-ai/plugin`, since that package is installed in the background and may be absent.

`sandbox-policy.md` becomes agent-neutral, at `/etc/sbx/sandbox-policy.md` in the base.

**Host-only guard: one matcher, per-agent adapters.** The list matching in `host-only-guard.sh` moves to a base `/usr/local/bin/host-only-check`: a command string in, exit 2 with the policy message on a match, 0 otherwise. The Claude hook becomes an adapter that unwraps the hook JSON and calls it; the opencode plugin is the second adapter. The list and the matching stay in one place, so agents cannot drift apart. The guard stays ergonomics, not containment (`.devcontainer/CLAUDE.md` section 6).

**ACP: a bundle contract, one entry point.** `sbx-acp.sh <tool>` parses that bundle's `tool.conf` on the host. It refuses a missing name, a tool that is not an `agent`, or one the resolved config does not enable, listing the enabled agents. It then execs `sbx -- <acp command>`, with stdin and stdout passed through and diagnostics on stderr and the log. The base image needs nothing ACP-specific beyond the contract; an `agent` bundle without `acp` is rejected when the config is resolved, so enabling an agent always enables its ACP server.
*Alternative:* bake `claude-agent-acp` into the base. That only serves Claude, and with no Anthropic hosts it reaches nothing.

**Config format.** `key = value`, `#` comments, whitespace-trimmed, parsed in bash with `read` and never `source`d. Sourcing a cloned repo's file would run its code on the host.
- `tools`: space-separated; the project value replaces the default.
- `allow`, `deny`: repeatable, one entry each. An entry is a hostname, validated against `^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$`, or an IPv4 address or CIDR range with a prefix of /16 or longer. Private, loopback, link-local, CGNAT, and multicast ranges are rejected: the Docker host is reached through `host-network` only. Bundle `allowed-domains.txt` entries get the same validation.
- `host-network`: `on` or `off`.
- `mount`: repeatable, `<abs path>[:rw]`. The path is resolved with `realpath`, and ancestry is checked on resolved paths so a symlink cannot sneak past the protected-path rule; the resolved path is the bind source and target. Protected from `:rw`: this repo and `~/.local/state/sbx`, every ancestor of either, and everything inside them. Refused in any mode, because the bind lands at the same path inside the container: a container system path (`/usr`, `/etc`, `/home/node`, `/tmp`, ...), any ancestor of one, an ancestor of the workspace (it would cover the read-only `.git` and `.sbx` binds), and a path containing `,`, `$`, quotes, `\`, or `=` (they break or are interpolated in the devcontainer mount string).

*Alternatives:* YAML/TOML would need `yq` or Python on the host. JSON/`jq` is unfriendly to hand-edit and has no comments.

**Launcher = `bin/sbx` driving the devcontainer CLI.** Grammar: `sbx [--rebuild] [--up] [--] <cmd> [args...]`. Option parsing stops at the first non-option or `--`. No command without `--up` prints usage and exits 2. Steps:
1. Resolve and validate the config.
2. Run the approval gate.
3. Compute the image hash and build if the tag is missing; `--rebuild` passes `--no-cache` and always builds.
4. Write `~/.local/state/sbx/<slug>/policy/` (`allowed-domains.txt`, `firewall.conf` with `HOST_NETWORK=0|1`) and `~/.local/state/sbx/<slug>/devcontainer.json`, a complete config.
5. `devcontainer up --config <generated>`, adding `--remove-existing-container` only when the running container's `sbx.config` label differs from the hash of the resolved config plus the image.
6. `sbx_tag_image`.
7. `devcontainer exec ... "$@"`, propagating its exit status.

Everything `sbx` prints itself goes to stderr, so stdout carries only the command's output. ACP depends on this.

The generated config is the static `.devcontainer/devcontainer.json` merged with `jq`, so `jq` is a host requirement checked like docker and the devcontainer CLI. It is the static one with:
- `build` replaced by `"image": "sbx-img:<hash>"`
- `--label=sbx.config=<hash>` added to `runArgs`
- `--name=sbx-<slug>` added to `runArgs`. The name has no `devcontainerId`, so it stays readable. A slug collision makes Docker refuse the name, and `sbx` reports this rather than removing the other container.
- the base volumes under the `sbx-` prefix, and the tool volumes, tmpfs mounts, and env
- a read-only bind of the policy dir at `/usr/local/etc/sbx`
- a read-only bind of `<workspace>/.sbx` when it exists
- the `mount` entries

`devcontainerId` stays stable per project because the generated path is fixed per slug. `--override-config` is not used: it replaces the base config rather than merging, so a complete file is needed either way.
*Alternatives:* Compose, or plain `docker run`. Either one would re-specify the entrypoint and `overrideCommand` pinning, `postStartCommand` verification, and `devcontainerId` naming that `firewall-enforcement` and `docker-resource-naming` already rest on.

**Firewall reads `/usr/local/etc/sbx/`.** `init-firewall.sh` changes its default path to `/usr/local/etc/sbx/allowed-domains.txt` and reads `HOST_NETWORK` from `/usr/local/etc/sbx/firewall.conf`. It parses `firewall.conf` with `grep`, not `source`, for the same data-not-code reason. Whitelist entries that are IPv4 addresses or ranges go into the `allowed-domains` ipset (already `hash:net`) as given, with no DNS lookup. It adds the host /24 INPUT and OUTPUT ACCEPTs only when the flag is `1`. Fixed paths keep `sudo` and sudoers unchanged. The image ships an empty mount point, so a launch without the mount aborts on the unreadable whitelist. That path is already sealed and fatal under `firewall-enforcement`. A missing source dir on `docker start` makes Docker refuse to start the container, which also fails closed.

**Approval gate.** `~/.local/state/sbx/<slug>/approved` stores the sha256 of `.sbx/config`. On a mismatch, `sbx` prints the delta against the defaults (tools, hosts and IPv4 ranges, host-network, mounts) and prompts, defaulting to No. Without a TTY it refuses. The read-only `.sbx` mount stops edits made from inside a running container. The gate catches files written before that, by a cloned repo, or through a writable `mount`.

**verify.sh.**
- Check 1 picks its must-be-blocked probe hosts from a candidate list (`example.com`, `github.com`, `example.org`, ...), skipping any host in the mounted whitelist or whose address falls in an allowed range.
- Check 3 probes each installed tool's `probe`.
- Check 4 also asserts that the host /24 ACCEPT rule is present exactly when `HOST_NETWORK=1`.
- Check 7 builds its expected kinds from `tools.list` plus each `tool.conf` `volume`.
- A new check asserts each tool's `bin` is on `PATH` with a read-only package dir, and each agent's `acp` command resolves on `PATH`.
- A new check asserts each tool's `tmpfs` paths are writable and `noexec`.
- Another new check asserts that `.sbx` is read-only when it exists.
- Another new check asserts that `/usr/local/etc/sbx` is read-only and not inside the workspace.
- Another new check asserts that each installed bundle's `bin/` scripts resolve on `PATH` to `/usr/local/share/sbx/bin/`, and that this directory is read-only.

## Risks / Trade-offs

- [Claude may still show its one-time bypass-mode confirmation, or ignore `defaultMode` or `skipDangerousModePermissionPrompt` from managed settings] → task 1.2 checks both. Fallback: a `bin/claude` wrapper in the bundle that adds `--dangerously-skip-permissions`. That covers the CLI only; ACP still depends on the settings.
- [`host-network` defaulting to off removes access that exists today, such as opencode talking to a model server on the host] → set `host-network = on` in that project's config. Nothing in the sandbox's own launch path needs it, because `devcontainer exec` goes through the Docker socket on the host.
- [opencode's plugin API or `OPENCODE_CONFIG_DIR` loading may not work as assumed, or may change upstream] → task 1.3 checks that the baked plugin blocks `git commit` with the policy message. If it cannot be loaded from outside the workspace, opencode ships without the guard: the guard is ergonomics, not containment (`.devcontainer/CLAUDE.md` section 6), the policy text still applies, and the read-only mount still enforces.
- [An IPv4 range opens every address in it with one approval] → the /16 floor, the private-range ban, and the approval delta listing each range.
- [The approval gate is trust-on-first-use, so a user who confirms without reading widens the sandbox] → the prompt lists every added host, range, and mount explicitly, and defaults to No.
- [Shipped defaults with no tools make the first `sbx claude` in a new project fail with command-not-found] → this is intended. The README shows the one-line `.sbx/config` and the option to add `claude` to the defaults file.
- [Image count grows with distinct tool combinations] → base layers are shared. Prune old images with `docker images sbx-img`, which the README covers.
- [`verify.sh` cannot check the container name, because there is no Docker socket inside] → it is a host-side label, not a capability, so it gets no `verify.sh` assertion. Task 5.1 checks it on the host.
