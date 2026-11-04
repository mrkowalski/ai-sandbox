# Tasks

## 1. Confirm the mechanism (host)

- [ ] 1.1 On the host, with the container still running after `sbx claude` exits, delete a scratch folder and record whether `.git` comes back, who owns it (`stat -c %U`), and when. Repeat after `docker stop sbx-<slug>`. Verify: the folder stays deleted once the container is stopped. If it does not, stop and revisit design.md.

## 2. Never create the workspace

- [ ] 2.1 `bin/sbx`: before resolving config, fail with `sbx: the current folder no longer exists: <path>` if `pwd -P` fails or `$PWD` is not a directory. Verify: in a shell, `cd` into a temp dir, `rmdir` it from another shell, run `sbx bash`. It exits non-zero and the dir is not recreated.
- [ ] 2.2 `devcontainer.json` `initializeCommand`: replace `mkdir -p` with a `mkdir` of `.git` only, guarded on it not already existing, so a missing workspace fails. Update `.devcontainer/CLAUDE.md` section 1 to match. Verify: `sbx --up` in a non-repo folder still leaves a user-owned `.git`, and `verify.sh` reports check 10 as N/A.

## 3. Stop when idle

- [ ] 3.1 `bin/sbx`: take a shared `flock` on `$STATE/session.lock` (fd 9) before `devcontainer up` and hold it for the session. Replace the final `exec` with a run of `devcontainer exec ... 9>&-` that saves its status, trapping INT/TERM/HUP with `:`. Verify: `sbx bash -c 'exit 7'` exits 7, and `sbx sh -c 'echo hi'` prints only `hi` on stdout.
- [ ] 3.2 `bin/sbx`: on the way out, also for `--up` with no command, release the shared lock, then try `flock -xn`. If it succeeds, `docker stop "$NAME" >&2`. A failed stop prints a warning on stderr and keeps the command's status. Add `flock` to the host requirement check. Verify on the host:
  - one session exits → `docker ps` no longer lists `sbx-<slug>`;
  - two terminals, one exits → the other keeps working;
  - closing the terminal window of the last session → the container stops;
  - `sbx-acp.sh claude` ended by the editor → the container stops and `/tmp/sbx-acp.log` shows the stop.
- [ ] 3.3 Race check on the host: start `sbx bash` in a second terminal while the first is stopping. Verify: the second session gets a started container and `verify.sh` passes in it.
- [ ] 3.4 Update the `bin/sbx` header guarantees, README (lifecycle: the container stops when the last session exits; launches after idle restart it; manual `docker stop`/`rm` for containers whose folder is already gone), `.devcontainer/CLAUDE.md` section 8, and `host-checklist.txt` (the stop checks from 3.2). Verify: no doc still says the container keeps running after `sbx` exits (`grep -n -i "stays up\|keeps running"`).
- [ ] 3.5 Amend `openspec/changes/add-configurable-agents/specs/sandbox-launcher/spec.md` line 26 ("and the container stays up") to "and the container stays up while another session uses it". Its `--up` requirement must also no longer imply the container is left running. Verify: `openspec validate add-configurable-agents` and `openspec validate stop-container-when-idle` pass.

## 4. Integration (host)

- [ ] 4.1 End to end on Docker Desktop: run `sbx claude` in a scratch folder, exit, delete the folder. Verify: it does not come back, including after `wsl --shutdown` and a Docker Desktop restart.

## Workflow follow-up

- Archive after `add-configurable-agents` is archived, so `sandbox-launcher` exists in `openspec/specs/` beside the new `container-lifecycle`.
