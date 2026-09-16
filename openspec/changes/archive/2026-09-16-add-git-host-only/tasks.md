## 1. The boundary: read-only `.git`

- [x] 1.1 Add the read-only bind mount of the workspace `.git` to `.devcontainer/devcontainer.json` (`source=${localWorkspaceFolder}/.git,target=${localWorkspaceFolder}/.git,type=bind,readonly`). Verify the file is valid JSON and that the existing `workspaceMount`, `runArgs`, and volume mounts are unchanged.
- [x] 1.2 Add `"initializeCommand"` creating the mount source on the host so a non-repo workspace gets a user-owned `.git` rather than a root-owned one. Verify it is a no-op on a directory that already has `.git`.
- [x] 1.3 Record in `devcontainer.json` (comment or adjacent docs) that this mount is part of the security contract, alongside `--read-only` and the capability list. Verify `.devcontainer/CLAUDE.md` and the file agree on what it guarantees.

## 2. The explanation: host-only entries

- [x] 2.1 Declare `git push`, the history-writing subcommands, the mutating `git tag` forms, and the account-touching `gh` subcommands in `.devcontainer/host-only-commands.txt`. Verify each pattern parses with `host-only-guard.sh --check-list`.
- [x] 2.2 Verify the publish entry matches `git push`, `git push -u origin HEAD`, and `git -C sub push` by feeding each to the guard as a synthetic payload (exit 2 means blocked).
- [x] 2.3 Verify the history entry matches `git commit`, `git commit -m x`, `git -c user.email=a@b commit -m x`, `git --no-pager commit`, `git merge foo`, `git rebase -i main`, `git cherry-pick abc`, `git revert abc`, `git am < p.patch`, and `cd x && git commit -m y`.
- [x] 2.4 Verify the mutating `git tag` forms are blocked (`git tag v1.0`, `git tag -a v1 -m x`, `git tag -d v1`) and the listing forms are not (`git tag`, `git tag -l 'v*'`, `git tag --list`, `git tag -n`, `git tag --contains HEAD`).
- [x] 2.5 Verify the `gh` entry blocks `gh pr create`, `gh auth login`, `gh repo clone x`, `gh api /user`, and passes `gh --version`.
- [x] 2.6 Add a staging entry covering `git add`, `git stash`, `git rm`, and `git mv`, which the read-only mount now makes fail with an unexplained `Permission denied`. Verify each is blocked and that `git status`, `git diff`, `git log`, `git show HEAD`, `git branch`, and `git tag` still pass with exit 0 and no output.
- [x] 2.7 Rewrite the git entries' remedy text: the mount is what refuses these, so the reason given must be the read-only `.git`, not policy or missing credentials. Verify no remedy claims a credential or endpoint is the cause where it is not.
- [x] 2.8 Note in the entries' comments that `HOST_ONLY_GUARD_BYPASS=1` gets a command past the filter and into the same `Permission denied`, and that `git checkout`/`branch`/`reset`/`restore` are deliberately unlisted because their read and write forms cannot be told apart by pattern. Verify the claim by bypassing the guard on `git add` in the rebuilt container (task 6.3).

## 3. Correct the premise in the places that state it

- [x] 3.1 Revise the header of `.devcontainer/host-only-commands.txt`: it currently frames the git entries as policy-only with the guard as the sole barrier, which the mount makes false. State which mechanism enforces each group — firewall, read-only mount, or the filter alone. Verify no sentence is false of any entry.
- [x] 3.2 Note in the same header that the guard sees Bash-tool calls only, so a command run from inside a script is not intercepted — including `verify.sh`'s own scratch-repo `git commit`.
- [x] 3.3 Correct the check-8 preamble comment in `.devcontainer/verify.sh` to match 3.1. Verify the comment matches what the list now declares.
- [x] 3.4 Rewrite item 6 of `.devcontainer/CLAUDE.md` and add the mount to the chain the document describes: the guard is ergonomics, the mount is the guarantee. Verify the document still reads as one coherent chain and that `devcontainer.json`'s entry mentions the new mount.

## 4. Session instructions

- [x] 4.1 Rewrite `.devcontainer/sandbox-policy.md`'s rationale: git commands are refused because the mounted repository is read-only, not because the user declined them. Verify the reason given is true of `git commit` and of `git add`.
- [x] 4.2 Instruct the agent that where it would ordinarily propose a declared command, it recommends the operation and states plainly that it is not possible inside the sandbox — it does not offer to run it and does not ask to be allowed to, and being asked does not reinstate it.
- [x] 4.3 State that the working tree is writable but the repository is not, so the agent edits files and shows work with `git diff` rather than staging it. Verify this is consistent with the entries declared in group 2.
- [x] 4.4 State that the bypass is the user's, and that using it on a git command reaches the read-only mount anyway. Verify it does not contradict the guard's own block message.

## 5. Start-time verification

- [x] 5.1 Replace `HOST_ONLY_SAMPLE` with `HOST_ONLY_SAMPLES` carrying one command per declared family, and `HOST_ONLY_ALLOWED` for the over-blocking side. Verify by running the probes with the git entries removed from a copy of the list: it must FAIL.
- [x] 5.2 Verify the over-blocking side FAILs against a deliberately over-broad `tag` pattern.
- [x] 5.3 Add a staging sample (`git add .`) to `HOST_ONLY_SAMPLES` once 2.6 lands. Verify it is blocked and the allowed set still passes.
- [x] 5.4 Add a new check asserting the write protection: a write to the workspace's resolved git directory must fail, and reading the repository (`git status`, `git log`) must succeed. Verify it FAILs when pointed at a writable repository.
- [x] 5.5 Make that check report *not applicable* — not a pass, not a FAIL — when the mounted workspace contains no git repository. Verify against a directory that is not a repo.
- [x] 5.6 Assert the absence of SSH private keys, `SSH_AUTH_SOCK`, and a git credential helper. Verify it reports when a key is planted in a scratch `HOME`.
- [x] 5.8 Consolidate the credential assertions into check 2, which already owned them, instead of duplicating them in check 9; promote them from `warn` to `bad` and replace the `id_*` glob with content-based detection. Verify a key named `deploy_key` is caught (the old glob missed it) and that `known_hosts`, `config`, and `*.pub` are not treated as key material.
- [x] 5.7 Update the `verify.sh` header comment block, which lists the checks the script performs, and the matching bullets in `.devcontainer/CLAUDE.md`. Verify the list of checks matches what the script now does.

## 6. Docs and host-side verification

- [x] 6.1 Update `README.md`: the sandbox cannot modify the project's git repository at all, reads still work, and staging and committing happen on the host. Verify the claim matches the mount and the list exactly, naming no command the list does not declare.
- [x] 6.2 Rebuild and launch on the host: `devcontainer up --workspace-folder "$PWD" --config ~/tools/sandbox/.devcontainer/devcontainer.json --remove-existing-container`. Verify the container starts and the postStart `verify.sh` prints VERIFIED.
- [x] 6.3 In a session inside the rebuilt container, confirm `git commit` and `git add` are blocked with the list's explanation; that `HOST_ONLY_GUARD_BYPASS=1 git add .` gets past the filter and still fails on the read-only mount; and that `git status`, `git diff`, and `git log` all work.
- [x] 6.4 Confirm on the host that the repository is untouched after the session — `git status` on the host shows the agent's file edits as unstaged, with no new commits, refs, or stash entries.
