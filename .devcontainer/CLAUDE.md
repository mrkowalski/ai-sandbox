# .devcontainer - how the security contract is enforced

Loaded automatically when working with files under `.devcontainer/`. Repo-wide context lives in the root `CLAUDE.md`.

## Base vs config: one rule

If a part only restricts the sandbox, or is harmless on its own, it is baked into the base image and cannot be configured. If it widens what the sandbox can reach, it is config (`sbx-defaults.conf` plus a project's `.sbx/config`, resolved on the host by `sbx-env.sh`).

| Part | Where | Why |
|---|---|---|
| Default-deny firewall, entrypoint gate, seal, `verify.sh` | base | restricts |
| Read-only rootfs, `noexec` `/tmp`, read-only `.git` and `.sbx` binds | base | restricts |
| No credentials, host-only list and shared matcher, sandbox policy text | base | restricts |
| `NET_ADMIN`/`NET_RAW`, the two sudoers entries | base | needed to install the firewall; node cannot use them beyond the two scripts, which only read read-only policy |
| git, gh, node/npm, uv/python, jq, openspec | base | harmless without egress or credentials |
| npm, uv, and bash-history volumes | base | per project, no new reach |
| Egress hostnames and public IPv4 ranges | config `allow`/`deny` | every entry is an exfiltration path |
| Tools (bundles) | config `tools` | reach comes through their hosts and stored credentials |
| Docker-host /24 | config `host-network`, default off | reaches services on the host |
| Extra host folders | config `mount`, read-only default | exposes host data |

Do not add a config key for a restriction, and do not bake a reach-widening part into the base.

The enforcement files below are listed with what each guarantees; a change to any of them is a change to the sandbox's guarantees. The host-only list, matcher, and adapters (6) sit on top as an ergonomics layer, not a containment control.

## 1. `devcontainer.json` and the generated config

- Grants `NET_ADMIN`/`NET_RAW` (to install the firewall), not `CAP_SYS_ADMIN` - so nothing inside can `mount`.
- Makes the rootfs `--read-only`, with a `noexec` `/tmp` tmpfs.
- Bind-mounts the project at its host path, then binds its `.git` back over itself **read-only**. This is the only thing stopping the agent writing the user's history. It applies to every process, whatever invoked it, and the guard's bypass does not affect it. Staging (`git add`, `stash`, `checkout -b`) fails too, by design; reads still work. `initializeCommand` pre-creates `.git` so a workspace with no repository does not end up with a root-owned one. Repos outside the workspace stay writable, and `verify.sh`'s scratch repo relies on that.
- Pins `"overrideCommand": false`. Otherwise the CLI starts the container with `--entrypoint /bin/sh` and the firewall is never installed. This line, the image `ENTRYPOINT`, and the Dockerfile's keep-alive `CMD` only work together: remove any one and enforcement quietly stops happening.
- Base named volumes `sbx-<kind>-${localEnv:SBX_SLUG}-${devcontainerId}` for bash history, npm cache, and uv cache. `${devcontainerId}` is the uniqueness key and must stay; without it, projects would share tool credentials. The slug is only a readable label, and a launch without `SBX_SLUG` creates a stray `sbx-<kind>--<id>` set.
- npm's cache at `/home/node/.npm` is a volume because on the read-only rootfs npm fails with `EROFS`. It cannot be a tmpfs because `npx` executes from the cache and tmpfs is `noexec`.
- uv's cache at `/home/node/.cache/uv` is a volume for the same two reasons: `uv run` and `uvx` build environments in it and exec from them. Interpreters are baked into `/usr/local/share/uv/python` (read-only) and `UV_PYTHON_DOWNLOADS=never`, since their download host, GitHub, is blocked.
- `postStartCommand` (`sudo init-firewall.sh && verify.sh`, `waitFor`) is a redundant second install plus the full network-probing check. **It is not enforcement**: it doesn't run on `docker start` or restarts, and a failure there doesn't stop an already-running container.
- The static file is not launched as-is. `bin/sbx` writes `~/.local/state/sbx/<slug>/devcontainer.json`: `build` replaced by `image: sbx-img:<hash>`, plus `--name=sbx-<slug>`, the `sbx.config` label, tool volumes `sbx-<tool>-<kind>-<slug>-<id>`, tool tmpfs (`noexec,nosuid`), tool env, the read-only policy bind at `/usr/local/etc/sbx`, a read-only bind of `<workspace>/.sbx` when it exists, and the `mount` entries. A bare `devcontainer up` on the static file gets no policy mount and stops at start (3).

## 2. `entrypoint.sh` - the enforcement point

Runs on every container start, as long as (1) keeps it attached. It installs the firewall, gates on `verify.sh --iptables-only`, writes `/tmp/.sandbox-firewall-installed`, then `exec "$@"`. On any failure it exits before the `exec`, so the container stops rather than running unprotected. The gate is offline on purpose: a provider outage should show `NOT VERIFIED`, not stop the sandbox from starting. It runs as `node` and uses only the two existing NOPASSWD sudoers entries.

## 3. The policy mount: `/usr/local/etc/sbx`

The image ships this directory empty and carries no whitelist. `bin/sbx` resolves the policy on the host and binds `~/.local/state/sbx/<slug>/policy/` over it read-only: `allowed-domains.txt` (the effective whitelist, one hostname, IPv4 address, or CIDR range per line) and `firewall.conf` (`HOST_NETWORK=0|1`). The source is outside the workspace and not writable from inside, so nothing in the container can widen its own policy. Without the mount the whitelist is unreadable and (4) aborts sealed. To widen egress, edit the config, never an iptables rule.

## 4. `init-firewall.sh`

Saves Docker's `127.0.0.11` DNS NAT rules, sets all policies to DROP **before** flushing, restores the DNS rules, allows loopback and DNS, loads the whitelist into the `allowed-domains` ipset (hostnames resolved with `dig`; IPv4 addresses and ranges added as given), accepts the Docker host's /24 only when `firewall.conf` has `HOST_NETWORK=1`, then adds one ACCEPT for the ipset and a catch-all REJECT. `firewall.conf` is read with `grep`, never sourced. Setting DROP before the flush means the chains are never empty and permissive at the same time. An `EXIT` trap (`seal`, gated on `FIREWALL_OK`) leaves any abort sealed: all policies DROP, loopback only. It uses `EXIT` rather than `ERR` because `ERR` is not inherited everywhere. Paths are fixed because `sudo` resets the environment; sudoers stays unchanged.

## 5. `verify.sh`

Checks the end state itself instead of trusting (4). Its expectations come from the image (`/usr/local/share/sbx/tools.list`, each bundle's `tool.conf`) and the policy mount, never from a list of its own. Its checks are numbered 1-14 in its header: egress blocked on a non-whitelisted probe host (including github.com unless allowed), `git push` impossible with no credentials, each tool's `probe` reachable, iptables in whitelist mode with the host /24 matching `HOST_NETWORK`, entrypoint marker present, npm and uv caches writable and exec-capable, volume names match this workspace, rootfs read-only, host-only matcher and adapters working, `.git` read-only but readable, `uv run` works offline, tool binaries and bundle scripts on `PATH` from read-only dirs, tool tmpfs writable and noexec, `.sbx` and the policy mount read-only.

`bad` = FAIL (exit 1, launch fails); `warn` = informational. Promoting a check to FAIL means any container that fails it can no longer start.

Before editing:

- **Reachability** is judged by curl's `%{time_connect}`, not exit code. TLS errors happen after connect, so going by exit code would score a reachable host as blocked.
- **Blocked-egress probes** (check 1) skip candidates in the whitelist or whose address a whitelisted name or range covers (the ipset holds addresses, so a shared CDN address counts). No remaining candidate is a FAIL.
- **iptables** needs root: the script re-execs the *installed* `/usr/local/bin/verify.sh --iptables-only` via sudo and reads back a `__VERIFY_COUNTS__`/`__VERIFY_FAILED__` trailer. Editing the working-tree copy leaves the installed one stale; a missing trailer FAILs.
- **Credentials** are detected by directory content, not an `id_*` glob, and are FAILs.
- **Volume names** (check 7) come from `/proc/self/mountinfo` (there is no Docker socket). They are compared against a slug re-derived from `SBX_WORKSPACE`, not against `SBX_SLUG`, which would only prove it equals itself. A non-empty id must follow the slug. The expected set is the base volumes plus the installed tools' `volume` entries, so a disabled tool's volumes are not expected.
- **Entrypoint marker** is a configuration check, not an attestation. `/tmp` is recreated at every start, so the marker proves the entrypoint ran this start. The agent could forge it; that is accepted.
- **PID 1** is context only: after `exec`, PID 1 looks identical whether or not the entrypoint ran. It does tell which command is running: a `sleep` loop that also has `exec "$@"` is the CLI's shim, which means `overrideCommand` is back on. `PID1_KEEPALIVE` must match the Dockerfile `CMD`.
- **Host-only probes** run the matcher in both directions and require it to fail closed on a missing list. `HOST_ONLY_SAMPLES` has one command per family (wrangler, git, `gh`); drop a sample only when you drop its family. `HOST_ONLY_ALLOWED` catches over-blocking. `git tag -l` is the key case there, because only `tag`'s mutating forms are declared. Adapter checks run only for installed agents this script knows (claude, opencode).
- **Read-only `.git`** (check 10) probes `git rev-parse --absolute-git-dir` (worktrees and submodules point elsewhere). It resolves from the workspace with no fallback to cwd, creates a new file rather than `touch`ing an existing one, and checks that reads still work. No repository reports N/A, never a silent pass.
- **Writable mounts that tools execute from** need separate writability and exec probes. A `noexec` cache gets past `EROFS` but then fails with 126. The npm path comes from `npm config get cache`, the uv path from `uv cache dir`; both go through `check_cache_dir`. A tool directory it executes from must be a `volume`, not a `tmpfs`; check 13 requires tmpfs to be noexec.
- **The container name** is a host-side label, not a capability; there is no Docker socket inside, so it has no assertion here.

## 6. Host-only list, shared matcher, adapters

- `host-only-commands.txt` (`<ERE>  ::  <message>` per line) is the only place a command is declared host-only.
- `host-only-check` (base, `/usr/local/bin`) is the only matcher: a command string in, exit 2 with the policy message on a match (or on a missing or malformed list), 0 otherwise. It has no rules of its own.
- Adapters only unwrap their agent's payload and call it: `tools/claude/host-only-guard.sh` (a `PreToolUse` hook wired in `/etc/claude-code/managed-settings.json`) and `tools/opencode/host-only-guard.js` (a `tool.execute.before` plugin in `/etc/sbx/opencode/plugin/`). Both refuse when the matcher cannot run. Agents without a pre-execution hook get the policy text only.
- `sandbox-policy.md` is agent-neutral, baked at `/etc/sbx/sandbox-policy.md`. Each agent bundle points its agent at it (Claude Code: copied to `/etc/claude-code/CLAUDE.md`; opencode: `instructions` in its baked `opencode.json`).

The guard makes nothing impossible. Every entry is enforced elsewhere, either by the firewall plus absent credentials (wrangler, `gh`, `git push`) or by the read-only `.git` mount (other git entries). Its job is to stop the agent reading `index.lock: Permission denied` as a broken repo. So `HOST_ONLY_GUARD_BYPASS=1` is harmless: it removes only the explanation. The guard also misses commands inside scripts, which the mount still catches. If you add an entry that nothing else enforces, say so in its comment, since the list's header promises every entry is enforced elsewhere.

## 7. Tool bundles: `tools/<name>/` and `install-tools.sh`

A bundle is everything one tool needs, enabled as a unit by config `tools`. Bundles live only in this repo; a project selects them and cannot ship its own. The image is built with `--build-arg TOOLS="<names>"`; `install-tools.sh` installs only those, writes `/usr/local/share/sbx/tools.list`, and removes the other bundle directories.

Files: `tool.conf` (required), `install.sh` (runs as node; writes only the npm prefix or `/usr/local/share/sbx/<name>`), optional `install-root.sh` (runs as root; baked settings, hooks, plugins under `/etc/<tool>` or `/etc/sbx/<name>/`, and system packages it needs - opencode installs `ripgrep` because it would otherwise fetch it from github.com), optional `bin/` (scripts copied to `/usr/local/share/sbx/bin/`, first on `PATH`), optional `shell.sh` (interactive shells only, sourced from `/etc/bash.bashrc`), and `allowed-domains.txt`.

What a bundle may grant is exactly its `tool.conf` keys, each validated on the host by `sbx-env.sh`: `type = agent | tool`, `bin`, `acp` (agents must declare it; first word must be a `bin`), `volume = <kind>:/home/node/<path>`, `tmpfs = /home/node/<path>`, `env = KEY=VALUE` (not `PATH`, `SBX_*`, `LD_*`, no `$`), `probe = https://...`, plus the hostnames and public IPv4 ranges in `allowed-domains.txt` (same validation as config `allow`). Install scripts only write the image; everything they write lands on the read-only rootfs. A bundle may not:

- remove or weaken any base restriction (there is no key for it);
- ship a `bin/` script that shadows a base command (anything on the base `PATH`, snapshotted before any bundle installs) or another selected bundle's script or binary - the build fails naming the script; a wrapper with the same name as the bundle's *own* `bin` entry is the allowed way to add default flags;
- declare a start command.

## 8. The host launcher: `bin/sbx`, `sbx-env.sh`, `sbx-acp.sh`

Not enforcement inside the container, but the gate in front of it: it decides what policy, tools, and mounts a container gets. Config files and `tool.conf` are parsed as data (`read`, never `source`/`eval`); any unknown key or invalid value aborts naming file and line. `mount` paths are resolved with `realpath`, may not be `/`, a container system path (`/usr`, `/etc`, `/home/node`, ...) or an ancestor of one, an ancestor of the workspace, or inside its `.git`/`.sbx`; `:rw` may not touch this repo or `~/.local/state/sbx` (or an ancestor or descendant of either). A new or changed `.sbx/config` needs interactive approval (`~/.local/state/sbx/<slug>/approved` holds its sha256); without a terminal on stdin and stderr it refuses. The container is recreated when its `sbx.config` label (hash of the generated config, policy files, and image id) differs.
