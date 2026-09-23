# Design

## Context

See proposal.md — Why. Three constraints shape the approach:

1. `devcontainer.json` has no variable that yields a slugified path. `${localWorkspaceFolder}` contains `/`, which is illegal in a volume name, and `${localWorkspaceFolderBasename}` gives only the leaf. The slug therefore has to be computed by the host shell and passed in as `${localEnv:SBX_SLUG}` — which makes it only as reliable as the launcher, and the CLI substitutes an empty string for an unset `${localEnv:...}` rather than refusing.
2. `devcontainer up` has no `--image-name` (only `devcontainer build` does), so the image tag has to be applied after the container exists.
3. The launch wrappers are not all in one place: `sbx-up`/`sbx-claude`/`sbx-resume` are shell functions the README tells the user to paste into `.bashrc`, while `sbx-acp.sh` is a script in this repo that runs its own `devcontainer up`. Both create containers, so both need the slug.

Two facts were measured inside a running sandbox rather than assumed: `/proc/self/mountinfo` exposes each named volume's host path including the volume name (`/data/docker/volumes/claude-code-config-<name>/_data`), and the proposed pipeline turns `/home/marcin/tools/sandbox` into `home-marcin-tools-sandbox`.

## Goals / Non-Goals

**Goals:**

- A project's volumes and image are identifiable from the host by the folder they belong to.
- Per-project isolation does not depend on the launcher getting the slug right.
- One definition of the slug on the host, shared by every wrapper that launches a container.
- The naming is checked at start, not documented and hoped for — matching how the repo treats every other guarantee.

**Non-Goals:**

- Migrating existing volumes. New names mean new empty volumes; that is accepted.
- Renaming the container itself. A fixed `--name` would make `docker ps` readable too, but a container left behind by a crashed run then blocks the next `up` with a name conflict. The image tag delivers the legibility without that failure mode.
- Suppressing the CLI's own `vsc-*` image name. It stays; `sbx-<slug>` is an additional tag on the same image ID, which costs no disk.

## Decisions

### `${devcontainerId}` stays; the slug is a readable prefix

Volume names are `claude-code-<kind>-<slug>-<devcontainerId>`.

An earlier revision of this design dropped `${devcontainerId}` and named the volumes by the slug alone. Host measurement on 2026-09-23 (task 6.4) ended that: a `devcontainer up` from a shell without `SBX_SLUG` resolved the mounts to `claude-code-config-`, `claude-code-npm-`, and `claude-code-bashhistory-`, and the launch completed with `{"outcome":"success"}` rather than being refused. Every project launched that way would have shared one Claude Code config volume — one set of credentials and one session history for all of them.

Two things were wrong with relying on the check alone. The uniqueness key became a host-exported shell variable, which a bare `devcontainer up`, an editor integration, or a future wrapper can omit; and the only thing standing behind it was a `postStartCommand` that, measured, did not stop the launch. Retaining the CLI-computed key removes the dependency altogether: the slug is a label, and a missing or wrong label now costs legibility rather than isolation.

The slug leads and the hash trails so that `docker volume ls` sorts a project's three volumes together and `grep <slug>` finds them. An unset slug yields `claude-code-config--<id>`, whose doubled dash is itself a readable symptom.

### Verification recomputes the slug rather than trusting a passed-in value

`devcontainer.json` passes `"SBX_WORKSPACE": "${localWorkspaceFolder}"` through `containerEnv`, and `verify.sh` derives the expected slug from that and checks it against the volume names it reads out of `/proc/self/mountinfo`: each name must begin `claude-code-<kind>-<expected-slug>-` and have a non-empty remainder, which is the id the CLI supplied.

Passing `SBX_SLUG` itself into the container would be simpler but checks nothing: it would confirm the slug equals itself. `${localWorkspaceFolder}` is computed by the devcontainer CLI and cannot be forgotten by a wrapper, so recomputing from it turns the check into a real comparison between what the host named the volumes and what this workspace says they should be called. The cost is that the derivation exists twice — once in `sbx-env.sh`, once in `verify.sh` — and the two must agree. That is the check working as intended: drift surfaces as a loud failure at the next start, which is the repo's stated preference over degrading quietly.

**Confirmed on the host (2026-09-23, task 6.3).** The two derivations were exercised against a path neither was developed on, and on the case-folding branch specifically: `sbx_slug` turned `/home/marcin/projects/LibreChat` into `home-marcin-projects-librechat` on the host, and `verify.sh`, recomputing from `SBX_WORKSPACE` inside the container, printed the same and passed all three mounts. The duplication is real but the copies agree where it matters.

### The check fails rather than warns

With `${devcontainerId}` retained, a bad slug pools nothing, so a warning would be defensible. It is a FAIL anyway, for the reason the repo states as a convention. A container whose volumes do not carry its own workspace's name was launched by something that does not know the naming rule — a stale `.bashrc` block, an editor integration that bypasses `sbx-acp.sh`, or a drift between `sbx_slug()` and verify.sh's copy of the derivation — and each is worth a stopped launch and a fixed launcher rather than a line of yellow text nobody reads. The empty-slug case gets its own message, because its cause is specific and its fix is one line in the launcher.

The honest limit is under Risks: measured on 2026-09-23, a FAIL does not stop a launch, because `postStartCommand` — the only thing that would run `verify.sh` at start — does not appear to run at all. The FAIL is therefore a report to whoever runs `verify.sh`, not a gate, until that is fixed repo-wide.

### Reading volume names from `/proc/self/mountinfo`

The container has no Docker socket, so the mount table is the only way it can learn what it is mounted from. The field is the volume driver's host path, which contains the volume name. This was confirmed in a live container; it is not guaranteed across every storage driver, so an undetermined mount source is treated as a FAIL rather than a pass — consistent with `verify.sh` already failing on an undetectable host IP rather than assuming the best.

### The image is tagged after `up`, by container label

After `devcontainer up` returns, the wrapper finds the container by the label the CLI stamps on it (`devcontainer.local_folder=$PWD`), reads its image ID, and `docker tag`s it `sbx-<slug>:latest`. Re-tagging on each launch moves the tag rather than adding one, so a project keeps exactly one tag.

Alternatives: parsing the `containerId` from the JSON result line `devcontainer up` prints on stdout works but requires capturing stdout, which would swallow the live build log the wrapper currently streams. Pre-building with `devcontainer build --image-name` names the image properly but does not stop `up` from resolving its own `vsc-*` tag for a Dockerfile-based config, so it changes the build flow for no guaranteed gain.

**Confirmed on the host (2026-09-23, task 4.1):** `devcontainer.local_folder` is present and holds the workspace path (`/home/marcin/projects/LibreChat` on the container inspected), alongside `devcontainer.config_file` and `devcontainer.metadata`. The label lookup stands; the `containerId` fallback is not needed.

The filter must match on the label's *value* (`label=devcontainer.local_folder=$PWD`), not merely its presence — several sandbox containers run at once, one per project, and a presence-only filter returns all of them.

## Risks / Trade-offs

- **`SBX_SLUG` unset — a bare `devcontainer up` outside the wrappers — yields `claude-code-config--<devcontainerId>`** → Isolation is unaffected: the id still keys the volume to this workspace alone. The cost is a *second* set of volumes for the same project. A launch without the slug does not share Claude Code config or npm cache with `sbx-up`'s launch of the same folder, so the agent re-authenticates and the cache is cold, and the stray volumes accumulate until someone removes them. `verify.sh` fails and names the empty component, which is how the operator finds out.
- **A verify FAIL does not stop the launch** → Settled on the host, 2026-09-23 (task 6.7). `verify.sh` run by hand in the unscoped container reports 44/0/3 and `NOT VERIFIED` and exits non-zero, while the `devcontainer up` that created that same container had reported `{"outcome":"success"}` and left it running. The check fires; nothing acts on it. `docker logs` shows only the entrypoint's output, as it must — `postStartCommand` runs through `docker exec` and never reaches PID 1's stream — but `postStartCommand` opens with `init-firewall.sh`, whose output appeared exactly once per launch and is accounted for by the entrypoint. No second firewall run appeared anywhere, so `postStartCommand` most likely did not run at all; a run whose failure went unpropagated is the less likely alternative and is not fully excluded.

  The consequence is repo-wide, not local to this check: at container start only the entrypoint's six `--iptables-only` checks execute. Blocked egress, git push, the read-only rootfs, the host-only guard, the `.git` bind and the npm cache are not exercised automatically, so `verify.sh` is in practice a manual tool despite `waitFor: postStartCommand`. Fixing that belongs in the entrypoint, alongside the firewall's own enforcement, and is a separate change — this one only found it. Note the further limit any such fix must face: `postStartCommand` would not run on `docker start` or after a host reboot either, so a restarted container is not re-checked. For this change specifically the stakes stay low, since `${devcontainerId}` keeps the volumes isolated whatever the name says: what goes unchecked here is a label. `waitFor: postStartCommand` is supposed to make a failing `verify.sh` fail the launch, and it is worth establishing whether it does, because *every* check in `verify.sh` rests on that assumption — not just this one. Task 6.7 diagnoses it. Note the further limit: `postStartCommand` does not run on `docker start` or after a host reboot, so a restarted container is not re-checked — the same gap the firewall has, and the reason the firewall's real enforcement lives in the entrypoint. This check stays out of the entrypoint regardless: with the id retained, what it protects is a label.

  **It has since cost something real (2026-09-23, task 6.5).** The first ACP launch after the rename reused a container created before it, so the session came up on the superseded volumes. Nothing said so: no `verify.sh` runs at start, and the symptom the operator actually got was a Claude Code config that had forgotten who they were. The container had to be removed by hand before a re-launch produced the new names. The stakes stayed low, as argued above, because what was wrong was a label and a cold cache rather than an isolation boundary. But it is worth recording that the first thing this gap cost was not hypothetical, and that the operator found out by inference rather than from the check that exists precisely to tell them.
- **Two different paths can slug to the same name** → Now a labelling collision only. `${devcontainerId}` differs, so the two projects still get different volumes; they merely share a prefix in `docker volume ls`. Three ways it happens: illegal characters collapsing (`/a/b-c` and `/a-b/c` both give `a-b-c`), case folding (`/home/Marcin/Tools` and `/home/marcin/tools` are different directories on Linux but one slug — measured during task 1.2), and non-ASCII characters mapping to one `-` per UTF-8 byte. The image *tag* is the one place the collision still bites, since it carries no id suffix: two such projects fight over `sbx-<slug>:latest` and the last launch wins. Accepted; it takes adversarial folder naming to hit, and lowercasing is not negotiable because Docker image repository names must be lowercase.
- **The image tag points at an image the next rebuild orphans** → Same behaviour the CLI's own `vsc-*` tags already have; dangling images are reclaimed with `docker image prune` as before.
- **Nothing in this change can be tested in the sandbox** → Every task that touches launch behaviour is verified by the user on the host, and tasks.md marks which ones those are rather than implying they were checked.

## Migration Plan

None. The names gain a slug prefix, so the first `sbx-up` per project creates the new volumes empty and Claude Code re-authenticates there; the old `claude-code-*-<devcontainerId>` volumes are left in place for the user to remove or ignore.

Two practical notes from carrying it out on 2026-09-23.

The new names take effect when a container is *created*, not when it starts. `sbx-up` passes `--remove-existing-container`, so it migrates a project on its next launch. `sbx-acp.sh` does not, and should not: forcing recreation there would kill a live ACP container whenever a second editor session opened. The consequence is that a project whose container predates this change keeps that container, and its first ACP launch silently lands on the pre-change volumes. One `sbx-up`, or one `docker rm -f` on the container, is the whole migration; task 5.4 puts that in the README.

This host carries two stale generations per project rather than the one an outside user would, because the superseded id-less revision of this design ran here before being reverted. So `docker volume ls` shows, for a project launched throughout, a hash-only set (pre-change), an id-less slugged set (superseded), and the current slug-plus-id set, plus whatever an unscoped test launch left behind. Only the last is live. That is an artefact of developing the change, not something the change does to a user, and it is why the run-3 listing has six volumes per project where the plan predicted three. It happens once — because the id is retained, a later launch that forgets the slug lands on its own volumes rather than on another project's.

Rollback is reverting the three files and rebuilding: the `${devcontainerId}` component is unchanged by this design, so dropping the prefix restores exactly the previous names — including the original Claude Code config volume — and picks them up as they were.
