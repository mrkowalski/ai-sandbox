## Context

See proposal.md — Why. Four facts about the existing sandbox shape the approach:

- `devcontainer.json` uses `"workspaceMount": "source=${localWorkspaceFolder},target=${localWorkspaceFolder}"`, so the project sits at the same absolute path inside and outside. A nested mount under it is expressible in the same file.
- The container holds `NET_ADMIN` and `NET_RAW` only. It has no `CAP_SYS_ADMIN`, so nothing inside it can call `mount`.
- The guard (`host-only-guard.sh`) is a `PreToolUse` hook on the **Bash tool**. It matches a POSIX ERE, anchored at the start of each normalized segment, after heredoc bodies are dropped, the command is split on `; && || | ( )`, runner words and `VAR=value` are stripped, and the command is reduced to its basename. It never sees a command a *script* runs.
- Every entry shipped so far is a command the firewall independently blocks, and the list, `verify.sh`'s check-8 preamble, and `.devcontainer/CLAUDE.md` item 6 all say so.

Measured, not assumed — with `.git` made unwritable, `git status`, `git diff`, `git log`, `git show`, `git branch`, and `git tag -l` all exit 0 with no warning, while `git add`, `git commit`, `git stash`, and `git checkout -b` fail at the first lock they try to take (`index.lock`, `refs/heads/x.lock`).

## Goals / Non-Goals

**Goals:**

- Make writing the mounted repository impossible, by a control the agent cannot reach, rather than by instruction.
- Keep reads completely intact, so the agent can still show the user exactly what it changed.
- Keep the clear handoff: an unexplained `Permission denied` is a worse outcome than a blocked command that says what to run on the host.
- Leave the sandbox's own tooling — `verify.sh`'s scratch repo — working.

**Non-Goals:**

- Blocking commits in *any* repository. A throwaway repo the agent creates under `/tmp` stays fully usable; that is deliberate, and `verify.sh` depends on it.
- Preventing an agent that is determined to evade the command filter from *trying*. The filter is ergonomics; the mount is the boundary, and it does not care whether the filter was bypassed.

## Decisions

### The boundary is a read-only bind mount of `.git`, declared in `devcontainer.json`

```
source=${localWorkspaceFolder}/.git,target=${localWorkspaceFolder}/.git,type=bind,readonly
```

Docker applies the nested mount over the workspace bind, so the repository directory is read-only while the working tree stays writable. This is the same kind of control as `--read-only` on the rootfs: enforced by the kernel, outside the agent's reach, in force before any process in the container starts.

*Alternatives considered:*

- **Remount read-only from `entrypoint.sh`.** Needs `CAP_SYS_ADMIN`, which the container deliberately does not have. Granting it to gain this would trade a large class of container escapes for a git guarantee — a clear net loss.
- **A `git` wrapper earlier on `PATH`.** Bypassable with `/usr/bin/git`, and invisible to anything that calls git by absolute path. Convention wearing a boundary's clothes.
- **Removing the `git` binary.** Takes the reads away too, which is most of git's value in here.
- **Partial read-only mounts** (`objects` and `index` writable, `refs`/`HEAD`/`logs`/`packed-refs` read-only) to preserve `git add`. Rejected as fragile: `packed-refs` frequently does not exist, and Docker creates a *directory* at a missing bind source, which would put a directory where git expects a file and break the repository. A failed commit would also leave dangling objects behind.

### Losing `git add`, `git stash`, and `git checkout -b` is accepted

They write `.git`, so a read-only `.git` takes them. This reverses an earlier decision to keep staging, and it is the right way round: staging *is* modifying the repository, and the sandbox's contract is now that it does not. The agent prepares changes in the working tree and shows them with `git diff`, which needs no write. The user stages and commits on the host, where they were going to do it anyway.

### The command filter stays, and grows the staging commands

The mount produces `fatal: Unable to create '.../index.lock': Permission denied`. That is exactly the opaque failure the host-only list exists to eliminate — the agent would be left guessing whether the repo is broken. So the list keeps its git entries and adds `add`, `stash`, `rm`, and `mv`.

The two layers do different jobs and the file comments say so: **the mount is what stops the command; the list is what explains it.** This also settles what the bypass means — `HOST_ONLY_GUARD_BYPASS=1` gets a command past the filter and straight into the same `Permission denied`, which is the correct outcome and worth stating.

Commands whose read/write split is ambiguous (`git checkout`, `git branch`, `git reset`, `git restore`) are deliberately *not* listed: a pattern precise enough to catch only their writing forms would be guesswork, and their read forms matter. They fail with the OS error, and `sandbox-policy.md` carries the general rule that explains it.

### `git tag` is still declared only in its mutating forms

Bare `git tag`, `-l`, `--list`, `-n`, `--contains` all read, and the mount permits them. The guard has no negative matching, so the block pattern discriminates on the first argument:

```
... tag[[:space:]]+(-[adfsmu]|--(annotate|sign|delete|force|message|local-user)|[^-[:space:]])
```

### Global options are absorbed with the wrangler idiom

`git`'s global options sit between the binary and the subcommand exactly as `wrangler`'s do, and the file already has a tested shape for that: `([[:space:]]+--?[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*`. It takes `-C <dir>`, `-c user.email=...`, `--no-pager`, `--git-dir=...`. Because the group only matches tokens starting with `-`, the subcommand alternation is reachable only when every preceding token was a flag — which is what keeps `git checkout commit` and `git log --grep merge` out.

### `initializeCommand` pre-creates the mount source

Docker creates a missing bind source as a root-owned directory. On a project that is not a repository that would leave a root-owned `.git` in the user's folder, removable only with `sudo`. `"initializeCommand": "mkdir -p '${localWorkspaceFolder}/.git'"` runs on the host as the user first, so the stray directory is theirs. It is a no-op for real repositories.

### Verification asserts both directions, and reports N/A rather than passing

The repo's rule is that a granted capability comes with an assertion. The new check writes to the workspace `.git` and requires failure, then reads the repository and requires success — over-blocking is as much a failure as under-blocking. Credentials are asserted too, but in check 2 where the `git push` probes already live rather than duplicated here. That existing assertion is strengthened rather than added: it was a `warn` that globbed `id_*`, so a `deploy_key` or a `.pem` slipped past it and a key that did match only produced a warning. It is now a `bad` that treats every non-`.pub`, non-`known_hosts`, non-`config` file in `~/.ssh` as key material, and checks the agent socket independently instead of in an `elif`.

A workspace with no repository reports *not applicable* rather than a silent pass: a silent pass is indistinguishable from a protection that quietly stopped working.

## Risks / Trade-offs

- **A worktree or submodule keeps a writable gitdir.** There `.git` is a *file* pointing elsewhere, and only that file is mounted read-only; the real directory is outside the mount and stays writable. → Accepted and documented. The common case is a plain clone. `verify.sh`'s probe writes to the resolved git directory, so it reports the gap rather than hiding it.
- **Repos outside the workspace remain writable.** `/tmp` is writable, so the agent could `git init` and commit there. → Deliberate: `verify.sh`'s own scratch repo needs it, and a throwaway repo is not the user's history.
- **A non-repo workspace still gets an empty `.git`.** → Reduced, not eliminated: it is user-owned and removable with `rmdir`.
- **Cannot be tested from inside the sandbox.** Mounts, images, and `/usr/local/bin` copies are all host-side. The behavioural findings above were obtained with a permissions proxy on a scratch repo, which is evidence for how git reacts, not proof that the mount is configured correctly. → The tasks end with a host-side rebuild and a `verify.sh` run.

## Migration Plan

Additive. Rollback is removing the mount and the list entries, then rebuilding. It takes effect only on the next `devcontainer up --remove-existing-container`, and existing containers keep the old behaviour until then.
