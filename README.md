# sbx - headless coding-agent sandbox

## What is it?

A Docker dev container that restricts a coding agent (Claude Code, opencode, ...) to the current folder and a whitelist of hosts. It is headless; it contains no human-facing features. It makes cost the only risk of running an agent with permission prompts off.

### Whatever runs inside it:

- cannot modify the project's git repository: `.git` is bind-mounted read-only. `git push` is impossible too: no SSH key, no credential helper, no egress
- has a read-only filesystem except for the project, volumes, and tmpfs
- has no outbound network access except to the hosts and IPv4 ranges in its resolved config
- cannot change the config that governs it: `.sbx/` and the firewall policy are mounted read-only

### Base vs config

Anything that only restricts the sandbox, or is harmless on its own, is baked into the base image and cannot be configured: the firewall, the read-only rootfs and `.git`, the host-only guard, git, gh, node/npm, uv/python, openspec. Anything that widens what the sandbox can reach is config: which tools are installed, which hosts it can reach, whether it can reach the Docker host, and which extra host folders it sees.

## Setup

```bash
npm install -g @devcontainers/cli                               # host requirements: docker, devcontainer, jq
git clone https://github.com/mrkowalski/sandbox ~/tools/sandbox
echo 'export PATH="$HOME/tools/sandbox/bin:$PATH"' >> ~/.bashrc
```

## Usage

```
sbx [--rebuild] [--up] [--] <cmd> [args...]
sbx [--rebuild] --up
```

`sbx` brings up the sandbox for the current folder if needed and runs `<cmd>` in it exactly as given. There is no default command, and its exit status is the command's. Everything `sbx` prints itself goes to stderr.

```bash
sbx claude              # Claude Code, permission prompts bypassed by its baked settings
sbx claude --resume
sbx opencode
sbx bash                # a shell; a second sbx in another terminal joins the same container
sbx --up                # bring the container up (and approve a new config) without running anything
sbx --rebuild claude    # rebuild the image without cache (refreshes tools pinned to latest), then run
sbx -- --weird-name     # `--` ends sbx's options
```

The container is reused as long as the resolved config and image are unchanged; otherwise `sbx` recreates it. A command that is not installed fails with the shell's command-not-found status: the shipped defaults enable no tools, so a project needs `tools = claude` (or the defaults file edited) before `sbx claude` works.

## Config

Two files, both `key = value` with `#` comments. They are parsed, never sourced: an unknown key or invalid value aborts the launch naming the file and line.

- `.devcontainer/sbx-defaults.conf` - the defaults for every project (no tools; npm, PyPI, and Cloudflare docs hosts). Edit it to widen every project at once.
- `<project>/.sbx/config` - optional, applied on top.

| Key | Meaning |
|---|---|
| `tools = <name> ...` | tool bundles to install; the project value replaces the default |
| `allow = <entry>` | add a hostname, or a public IPv4 address or CIDR range no wider than /16 (repeatable) |
| `deny = <entry>` | remove an entry from the whitelist (repeatable); denying a host an enabled tool requires is an error |
| `host-network = on \| off` | accept the Docker host's /24, e.g. for a local model server (default off) |
| `mount = <abs path>[:rw]` | bind a host folder at the same path, read-only unless `:rw` (repeatable) |

The effective whitelist is the defaults' `allow` entries, plus the hosts of every enabled tool, plus the project's `allow` entries, minus `deny`. Private, loopback, link-local, CGNAT, and multicast ranges are rejected; the Docker host is reached through `host-network` only. `mount` refuses `/`, container system paths, an ancestor of the project, and the project's `.git`/`.sbx`; `:rw` is refused for this repo, `~/.local/state/sbx`, and their ancestors.

Example `.sbx/config`:

```
tools = claude opencode
allow = example.com
allow = 203.0.113.0/24       # a provider reached by address range
deny = developers.cloudflare.com
host-network = on            # opencode talks to a model server on the host
mount = /home/me/docs        # read-only reference folder
```

### Approval

The first time `sbx` sees a project's `.sbx/config`, and whenever its content changes, it prints what the config changes relative to the defaults (tools, added and removed hosts and ranges, host-network, mounts) and asks `Apply this config? [y/N]`. Without a terminal it refuses, so run `sbx --up` once interactively before an editor launches the project over ACP. The approved hash is kept in `~/.local/state/sbx/<slug>/approved`.

## Tool bundles

Each tool is one directory under `.devcontainer/tools/<name>/`, enabled as a unit by `tools`. A project's image contains only the tools its config enables; images are tagged `sbx-img:<content hash>` and shared by projects with the same tools. Bundles come only from this repo.

| File | Purpose |
|---|---|
| `tool.conf` | declarations (below) |
| `install.sh` | runs as `node` at build; installs into the npm prefix |
| `install-root.sh` | optional; runs as root at build; baked settings, hooks, plugins under `/etc` |
| `bin/` | optional scripts, first on `PATH`: helpers, or a wrapper with the same name as the tool's binary that `exec`s it with extra arguments. Wrappers are how a bundle aliases a command, since `sbx <cmd>` and ACP run no interactive shell. A script may not shadow a base command or another bundle's script; the build fails |
| `shell.sh` | optional aliases and functions for interactive shells (`sbx bash`) only |
| `allowed-domains.txt` | hostnames and public IPv4 ranges the tool requires |

`tool.conf` keys:

| Key | Meaning |
|---|---|
| `type = agent \| tool` | required; an agent must declare `acp` and load the sandbox policy |
| `bin = <name>` | a binary the tool provides (repeatable, checked on `PATH` by `verify.sh`) |
| `acp = <command> [args...]` | the ACP server on stdio; the first word must be a `bin` |
| `volume = <kind>:<path>` | persistent state, volume `sbx-<tool>-<kind>-<slug>-<id>` (repeatable) |
| `tmpfs = <path>` | writable scratch, `noexec`, discarded on recreation (repeatable) |
| `env = KEY=VALUE` | container environment (repeatable) |
| `probe = <url>` | endpoint `verify.sh` requires to be reachable |

## ACP

Every agent bundle declares its ACP server, so any enabled agent can be driven from an editor. Configure the editor's agent command as, run from the project folder:

```bash
~/tools/sandbox/sbx-acp.sh claude      # or: sbx-acp.sh opencode
```

It refuses a tool that is not an enabled agent (naming the enabled ones), then runs the agent's `acp` command through `sbx`. Diagnostics go to `$SBX_ACP_LOG` (default `/tmp/sbx-acp.log`).

## Firewall

The firewall is installed by the image entrypoint, from the policy `sbx` resolves on the host and mounts read-only at `/usr/local/etc/sbx`. The image carries no whitelist, so a bare `devcontainer up` stops at start. If the firewall script fails, the container stops; see `docker logs sbx-<slug>`. If you need a shell inside an image whose container will not start, bypass the entrypoint from the host:

```bash
docker run --rm -it --entrypoint /bin/bash <image>   # no firewall installed
```

## Commands that must run outside the sandbox

Some commands cannot work in the sandbox due to credentials, APIs, etc. `.devcontainer/host-only-commands.txt` is the list of those commands. One matcher, `host-only-check`, applies it for every agent that has a pre-execution hook: Claude Code's `PreToolUse` hook and opencode's guard plugin.

To add one, add a line to `.devcontainer/host-only-commands.txt` and rebuild:

```
<pattern>  ::  <what the user should be told>
```

`<pattern>` is a POSIX ERE matched against the start of each command in the line the agent submitted, after `npx`-style runners are stripped - so a pattern reading `wrangler ... deploy` also catches `cd app && npx wrangler deploy`. The file's header documents the format and the normalization in full.

If a pattern turns out to be too broad, you do not need a rebuild to get past it - prefix the command with the bypass, which applies to that one invocation:

```bash
HOST_ONLY_GUARD_BYPASS=1 npx wrangler deploy
```

## Maintenance

### Names

Everything for one project carries a slug of its path: the absolute path with the leading `/` stripped, lowercased, and every character outside `[a-z0-9_.-]` replaced by `-`. Launching in `/home/marcin/tools/sandbox` with `tools = claude` produces:

```
sbx-home-marcin-tools-sandbox                                   # container
sbx-bashhistory-home-marcin-tools-sandbox-<devcontainerId>      # base volumes
sbx-npm-home-marcin-tools-sandbox-<devcontainerId>
sbx-uv-home-marcin-tools-sandbox-<devcontainerId>
sbx-claude-config-home-marcin-tools-sandbox-<devcontainerId>    # one per tool volume
sbx-home-marcin-tools-sandbox:latest                            # image tag, next to sbx-img:<hash>
```

A tool's volumes survive disabling it and are mounted again when it is re-enabled. Host state lives in `~/.local/state/sbx/<slug>/`.

#### Cleanup

```bash
docker volume ls | grep home-marcin-tools-sandbox   # one project's volumes
docker volume ls | grep sbx-npm-                     # every project's npm caches
docker volume rm <volume-name>                      # container must be stopped
docker images sbx-img                               # content-tagged images, one per tool combination
docker image rm sbx-img:<hash>                      # prune an old one
docker images | grep '^sbx-'                        # per-project tags
```

### OpenSpec maintenance

Run `openspec update` after bumping the npm package. It regenerates `.claude/skills`.
