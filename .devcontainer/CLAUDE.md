# .devcontainer - how the security contract is enforced

Loaded automatically when working with files under `.devcontainer/`. Repo-wide context lives in the root `CLAUDE.md`.

Five files enforce the sandbox; a change to any of them is a change to its guarantees. The host-only list and guard (6) sit on top as an ergonomics layer, not a containment control.

## 1. `devcontainer.json`

- Grants `NET_ADMIN`/`NET_RAW` (to install the firewall), not `CAP_SYS_ADMIN` - so nothing inside can `mount`.
- Makes the rootfs `--read-only`, with a `noexec` `/tmp` tmpfs.
- Bind-mounts the project at its host path, then binds its `.git` back over itself **read-only**. This is the only thing stopping the agent writing the user's history. It applies to every process, whatever invoked it, and the guard's bypass does not affect it. Staging (`git add`, `stash`, `checkout -b`) fails too, by design; reads still work. `initializeCommand` pre-creates `.git` so a workspace with no repository does not end up with a root-owned one. Repos outside the workspace stay writable, and `verify.sh`'s scratch repo relies on that.
- Pins `"overrideCommand": false`. Otherwise the CLI starts the container with `--entrypoint /bin/sh` and the firewall is never installed. This line, the image `ENTRYPOINT`, and the Dockerfile's keep-alive `CMD` only work together: remove any one and enforcement quietly stops happening.
- Named volumes `claude-code-<kind>-${localEnv:SBX_SLUG}-${devcontainerId}` for bash history, Claude config, and npm cache. `${devcontainerId}` is the uniqueness key and must stay; without it, projects would share Claude credentials. The slug is only a readable label, and a launch without `SBX_SLUG` creates a stray `claude-code-<kind>--<id>` set.
- npm's cache at `/home/node/.npm` is a volume because on the read-only rootfs npm fails with `EROFS`. It cannot be a tmpfs because `npx` executes from the cache and tmpfs is `noexec`.
- `postStartCommand` (`sudo init-firewall.sh && verify.sh`, `waitFor`) is a redundant second install plus the full network-probing check. **It is not enforcement**: it doesn't run on `docker start` or restarts, and a failure there doesn't stop an already-running container.

## 2. `entrypoint.sh` - the enforcement point

Runs on every container start, as long as (1) keeps it attached. It installs the firewall, gates on `verify.sh --iptables-only`, writes `/tmp/.sandbox-firewall-installed`, then `exec "$@"`. On any failure it exits before the `exec`, so the container stops rather than running unprotected. The gate is offline on purpose: an Anthropic outage should show `NOT VERIFIED`, not stop the sandbox from starting. It runs as `node` and uses only the two existing NOPASSWD sudoers entries.

## 3. `allowed-domains.txt`

The entire egress policy, one hostname per line. To widen the sandbox, add a line here, not an iptables rule. A name that doesn't resolve aborts firewall setup.

## 4. `init-firewall.sh`

Saves Docker's `127.0.0.11` DNS NAT rules, sets all policies to DROP **before** flushing, restores the DNS rules, allows loopback and DNS, loads the whitelist into the `allowed-domains` ipset, then adds one ACCEPT for the ipset and a catch-all REJECT. Setting DROP before the flush means the chains are never empty and permissive at the same time. An `EXIT` trap (`seal`, gated on `FIREWALL_OK`) leaves any abort sealed: all policies DROP, loopback only. It uses `EXIT` rather than `ERR` because `ERR` is not inherited everywhere.

## 5. `verify.sh`

Checks the end state itself instead of trusting (4). Its checks are numbered 1-10 in its header: egress blocked, `git push` impossible with no credentials, Anthropic reachable, iptables in whitelist mode, entrypoint marker present, npm cache writable and exec-capable, volume names match this workspace, rootfs read-only, host-only guard working, `.git` read-only but readable.

`bad` = FAIL (exit 1, launch fails); `warn` = informational. Promoting a check to FAIL means any container that fails it can no longer start.

Before editing:

- **Reachability** is judged by curl's `%{time_connect}`, not exit code. TLS errors happen after connect, so going by exit code would score a reachable host as blocked.
- **iptables** needs root: the script re-execs the *installed* `/usr/local/bin/verify.sh --iptables-only` via sudo and reads back a `__VERIFY_COUNTS__`/`__VERIFY_FAILED__` trailer. Editing the working-tree copy leaves the installed one stale; a missing trailer FAILs.
- **Credentials** are detected by directory content, not an `id_*` glob, and are FAILs.
- **Volume names** (check 7) come from `/proc/self/mountinfo` (there is no Docker socket). They are compared against a slug re-derived from `SBX_WORKSPACE`, not against `SBX_SLUG`, which would only prove it equals itself. A non-empty id must follow the slug.
- **Entrypoint marker** is a configuration check, not an attestation. `/tmp` is recreated at every start, so the marker proves the entrypoint ran this start. The agent could forge it; that is accepted.
- **PID 1** is context only: after `exec`, PID 1 looks identical whether or not the entrypoint ran. It does tell which command is running: a `sleep` loop that also has `exec "$@"` is the CLI's shim, which means `overrideCommand` is back on. `PID1_KEEPALIVE` must match the Dockerfile `CMD`.
- **Host-only probes** run the guard in both directions and require it to fail closed on a missing list. `HOST_ONLY_SAMPLES` has one command per family (wrangler, git, `gh`); drop a sample only when you drop its family. `HOST_ONLY_ALLOWED` catches over-blocking. `git tag -l` is the key case there, because only `tag`'s mutating forms are declared.
- **Read-only `.git`** (check 10) probes `git rev-parse --absolute-git-dir` (worktrees and submodules point elsewhere). It resolves from the workspace with no fallback to cwd, creates a new file rather than `touch`ing an existing one, and checks that reads still work. No repository reports N/A, never a silent pass.
- **Writable mounts that tools execute from** need separate writability and exec probes. A `noexec` cache gets past `EROFS` but then fails with 126. The npm path comes from `npm config get cache`.

## 6. `host-only-commands.txt` + `host-only-guard.sh`

The list (`<ERE>  ::  <message>` per line) is the only place a command is declared host-only; the guard has no rules of its own. It runs as a `PreToolUse` hook on the Bash tool (wired in `/etc/claude-code/managed-settings.json`) and blocks with exit 2. `/etc/claude-code/CLAUDE.md` tells the agent to announce these commands instead of running them.

The guard makes nothing impossible. Every entry is enforced elsewhere, either by the firewall plus absent credentials (wrangler, `gh`, `git push`) or by the read-only `.git` mount (other git entries). Its job is to stop the agent reading `index.lock: Permission denied` as a broken repo. So `HOST_ONLY_GUARD_BYPASS=1` is harmless: it removes only the explanation. The guard also misses commands inside scripts, which the mount still catches. If you add an entry that nothing else enforces, say so in its comment, since the list's header promises every entry is enforced elsewhere.
