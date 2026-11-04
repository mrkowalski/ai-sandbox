# Design

## Context

Today `bin/sbx` ends with `exec devcontainer exec ...`. Nothing runs after the command, and the container's keep-alive `CMD` keeps it up indefinitely. `initializeCommand` runs `mkdir -p '<ws>/.git'` on the host on every `devcontainer up`. The exact recreation path on Docker Desktop (WSL2) has not been confirmed. Candidates are the running container's binds and `mkdir -p` from a stale `$PWD`. This design removes both, so it does not depend on which one it is.

## Goals / Non-Goals

**Non-Goals:** removing the container or its volumes. Stopping is enough to release the binds. Removing would lose tool credentials and caches, and volume cleanup is already documented. Also out of scope: protecting a folder that is deleted while a session is still running in it.

## Decisions

**Session tracking with `flock` on a host lock file, not by counting processes.** Each `sbx` takes a shared lock on `~/.local/state/sbx/<slug>/session.lock` before `devcontainer up` and holds it until the command exits. On exit it drops the shared lock and tries a non-blocking exclusive lock. If it gets the lock, no other session is running, so it runs `docker stop <name>` while still holding it, then releases it. A new launch blocks on its shared lock until the stop finishes, then `devcontainer up` starts the container again. That gives the race scenario in the spec.
- Alternatives:
  - Count `docker exec` sessions (`ExecIDs` in inspect, or `ps` inside). Exec bookkeeping varies across engine versions, and an exec can be between start and attach.
  - Use a counter file. It leaks when `sbx` is SIGKILLed. A lock held by the kernel is released when the process dies.

**`sbx` stays the parent; no `exec`.** It runs `devcontainer exec ... 9>&-`, so the command never inherits the lock fd, saves the status, does the stop, and exits with that status. INT, TERM, and HUP are trapped with a handler (`:`), not ignored. An ignored disposition would be inherited by the child, and a handler is reset in it. So Ctrl-C still reaches the command, and `sbx` survives to clean up. `docker stop` output goes to stderr.

**Graceful `docker stop`.** This uses the default 10 s grace. The keep-alive already exits on TERM, so a stop takes about 1 s.

**No workspace creation.** `bin/sbx` checks the folder with `[ -d "$PWD" ]` (after `pwd -P` succeeds) before anything else. `initializeCommand` becomes `mkdir` without `-p`, guarded on the `.git` path not existing. That still pre-creates a user-owned `.git` for non-repo folders, as git-write-protection requires, but it can never create the workspace itself.

## Risks / Trade-offs

- [Each launch after idle pays for container start, firewall install, and full `verify.sh`, a few seconds] → Accepted for correctness. Several terminals in one folder still share one running container.
- [SIGKILL of the last `sbx` skips the stop] → The container stays up as it does today. The next session that exits normally stops it.
- [Docker Desktop recreates the folder through some path other than the two removed here] → Task 1 confirms the mechanism on the host before implementing. If the folder still comes back with the container stopped, revisit this design before going further.
- [Containers left running from before this change] → They stop the first time their folder's `sbx` exits. For a folder already deleted, `docker stop sbx-<slug>` / `docker rm` by hand (README note).
