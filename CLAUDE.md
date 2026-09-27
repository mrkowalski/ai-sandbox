# CLAUDE.md

## Repo

- Definition of a headless Docker dev container that sandboxes Claude Code. Not an application: no source tree, no package manifest.
- Deliverable: `.devcontainer/`. README and `openspec/` describe or plan it.
- Goal: `claude --dangerously-skip-permissions` is safe. Agent sees only the bind-mounted project, reaches only whitelisted hosts, cannot `git push` or write `.git`. Cost is the only remaining risk.
- Test suite: `verify.sh`.
- Enforcement files and their rationale: `.devcontainer/CLAUDE.md` (auto-loaded under that dir). Read before editing anything there; every change there changes the sandbox's guarantees.

## Inside the sandbox (`$DEVCONTAINER=true`)

- No `docker`, `podman`, or `devcontainer` CLI: cannot build, run, or rebuild the container.
- Rootfs read-only. Writable: project folder (at its host path), `/tmp`, `/commandhistory`, `/home/node/.claude`, `/home/node/.npm`.
- Project `.git` is mounted read-only: commit, stage, stash, etc. fail by design.
- `/tmp` is `noexec` tmpfs: anything executed from there exits 126.
- `/usr/local/bin/*` are the image's baked copies. Editing `.devcontainer/*.sh` has no effect until a host-side rebuild.
- Egress default-deny: a failed fetch is usually the firewall working.
- Host-only commands (`/usr/local/etc/host-only-commands.txt`): follow `/etc/claude-code/CLAUDE.md`.
- You cannot verify changes to `.devcontainer/`. State explicitly what was not tested; the user tests on the host.

## Host-side (user only)

- Launch: `sbx-up`, then `sbx-claude` (README shell functions). Plain `devcontainer up` without `SBX_SLUG` creates stray volumes.
- `verify.sh` runs twice per start:
  - entrypoint: `--iptables-only`, start-time gate
  - `postStartCommand`: full run
- Manual re-run inside a container:

  ```bash
  verify.sh                        # full; VERIFIED / NOT VERIFIED, exit 1 on any FAIL
  sudo verify.sh --iptables-only   # ruleset checks only
  ```

## Fail-closed

- Failed firewall install: entrypoint exits before `exec`, container stops, nothing to `devcontainer exec` into. Reason in `docker logs <container>`.
- Aborted `init-firewall.sh` (initial or `sudo` re-run, e.g. unresolvable whitelist entry): container sealed, all policies DROP, loopback only.
- Shell in an image that will not start (host operator only):

  ```bash
  docker run --rm -it --entrypoint /bin/bash <image>   # no firewall installed
  ```

- No in-image bypass (no `SANDBOX_SKIP_FIREWALL=1`), deliberately.
- Container won't start = mechanism working. Diagnose the whitelist or ruleset; never look for a way to start it anyway.

## OpenSpec

- `openspec` CLI, `openspec-*` skills, `/opsx:*` commands.
- Active: `openspec/changes/<name>/` (`proposal.md`, `design.md`, `specs/<capability>/spec.md`, `tasks.md`). Archived: `openspec/changes/archive/`.
- Archive holds implemented and abandoned changes; the proposal header marks abandoned ones.
  - Abandoned, 0 tasks done: `add-podman-support` (sandbox is Docker-only), `add-sbx-launcher` (launcher is still the README shell functions).
- Source of truth for implemented behaviour: `openspec/specs/`. Absent from there = not built.
- Planning skills never edit `.devcontainer/`. Implement only on explicit follow-up request.

## Conventions

- Shell scripts: header comment block (guarantees, invocation); `set -euo pipefail`.
- Other comments only for non-obvious invariants, ordering, workarounds, external constraints. Never restate the code.
- Fail loudly: missing config or discrepancy = clear error + exit.
- Every new container capability gets a `verify.sh` assertion.
- No emdash; use hyphens.
