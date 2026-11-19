# Tasks

## 1. Image and mounts

- [x] 1.1 In `.devcontainer/Dockerfile`, replace the "Persist bash history" block (`/commandhistory` creation and the `HISTFILE`/`PROMPT_COMMAND` snippet) with one that appends `unset HISTFILE` to `/home/node/.bashrc`, so interactive shells don't try to write history to the read-only rootfs. Verify `grep -n commandhistory .devcontainer/Dockerfile` returns nothing.
- [x] 1.2 Remove the `sbx-bashhistory-...` mount from `.devcontainer/devcontainer.json`. Verify `grep -rn bashhistory .devcontainer/` matches only the docs fixed in 2.2.

## 2. Verification, launcher, docs

- [x] 2.1 Drop `"|bashhistory|/commandhistory"` from `VOLUME_SPECS` in `.devcontainer/verify.sh`, and `/commandhistory` from `_SBX_SYSTEM_PATHS` in `sbx-env.sh`. Verify with `bash -n` on both files.
- [x] 2.2 Remove bash history mentions from `README.md` (Names listing), `CLAUDE.md` (writable paths), and `.devcontainer/CLAUDE.md` (base volumes table and list). Verify `grep -rn -i "commandhistory\|bashhistory\|bash.history" --exclude-dir=.git --exclude-dir=openspec .` returns nothing.

## 3. Host check (user, outside the sandbox)

- [x] 3.1 Run `sbx --rebuild`, then `sbx bash`. Verify that `verify.sh` prints `VERIFIED`, that `docker volume ls | grep bashhistory` lists only volumes from before the change, and that exiting an interactive shell prints no history error.
- [x] 3.2 Remove the orphaned volumes once the container is stopped: `docker volume rm $(docker volume ls -q | grep '^sbx-bashhistory-')`.

## Workflow follow-up

- Archive the change after the host check passes.
