# Tasks

Nothing under `.devcontainer/`, and no `docker`/`devcontainer` command, can be tested inside the sandbox. Every "Verify" step marked (host) is for the user to run on the host.

## 1. Launch-path spike

- [ ] 1.1 (host) Confirm what `devcontainer up --config .devcontainer/devcontainer.json --override-config <file>` does. Check whether `devcontainerId` stays the same as a plain `--config` launch, and whether the override replaces or merges with the base config. To verify, run the same `docker volume ls` before and after with an override that only adds a label, and record the result in design.md. If the id changes, switch design.md and 4.1 to the fallback (generated file as `--config`), and add the one-time volume migration note to the README.

## 2. Base image and tool fragments

- [ ] 2.1 Make `sandbox-policy.md` agent-neutral. Bake it to `/etc/sbx/sandbox-policy.md` in the base. Remove the Claude Code/ACP installs, the `managed-settings.json` copy, `CLAUDE_CODE_VERSION`, and the `allowed-domains.txt` copy from the base Dockerfile. Add an empty `/usr/local/etc/sbx` mount point, `ARG TOOLS=`, `COPY tools/`, the per-tool install loop, and `tools.list`. Verify (host): `docker build --build-arg TOOLS=` succeeds, `tools.list` is empty, and no `allowed-domains.txt` exists in the image.
- [ ] 2.2 Add `tools/claude/` (`install.sh`, `install-root.sh` for `/etc/claude-code/` with `permissions.defaultMode = "bypassPermissions"` plus the guard hook, `tool.conf`, `allowed-domains.txt` with the Anthropic, statsig, and sentry hosts). Verify (host): in a `claude`-enabled project, `sbx claude` starts with permissions bypassed and no flag, and with no confirmation dialog (add `skipDangerousModePermissionPrompt` if one appears). `/etc/claude-code/CLAUDE.md` matches the policy.
- [ ] 2.3 Add `tools/opencode/` (`npm i -g opencode-ai`, `/etc/sbx/opencode.json` with `instructions`, `OPENCODE_CONFIG`, state volumes, domains). Confirm which domains opencode needs to start with an Anthropic provider and record them in its `allowed-domains.txt`. Verify (host): with `tools = claude opencode`, `sbx opencode` starts and answers a prompt, and its session shows the sandbox policy loaded.
- [ ] 2.4 Update `.devcontainer/CLAUDE.md`: the base-vs-config rule and table, tool fragments, where the policy lives, and the `/usr/local/etc/sbx` mount. Verify that it names every enforcement file this change touched.

## 3. Firewall policy from the mount

- [ ] 3.1 `init-firewall.sh`: switch the default whitelist path to `/usr/local/etc/sbx/allowed-domains.txt`. Read `HOST_NETWORK` from `/usr/local/etc/sbx/firewall.conf` with `grep` (never `source`; a missing or invalid value means `0`). Add the host /24 rules only for `1`, and update the header. Verify (host): without the mount, the container stops and `docker logs` names the unreadable whitelist. With `host-network` unset, `curl` to a server on the Docker gateway is rejected; with `host-network = on`, it succeeds.

## 4. Config and launcher

- [ ] 4.1 Add `.devcontainer/sbx-defaults.conf` (`tools =`, plus `allow` lines for the npm registry, PyPI, and the Cloudflare docs). In `sbx-env.sh`, add the `key = value` parser and resolver (no `source`, no `eval`) for config and `tool.conf`. It produces the tools, the effective domains, `host-network`, the mounts, and the volumes/env per tool. It rejects unknown keys, bad hostnames, unknown tools, `deny` of a tool-required domain, and invalid or protected mounts (checked on `realpath`), each error naming the file and line. Verify: a `uv run` test script in the scratchpad feeds valid and invalid configs (including `allow = $(touch /tmp/pwned)`, `git-readonly = off`, `mount = $HOME:rw`, and a symlink to the sandbox repo with `:rw`) and checks the outputs, the exit codes, and that nothing was executed.
- [ ] 4.2 Implement the approval gate: a sha256 stored in `~/.local/state/sbx/<slug>/approved`, a printed delta (tools, domains, host-network, mounts), a prompt defaulting to No, and a refusal without a TTY. Verify with the same test script, driving it with `</dev/null` and with piped `y`.
- [ ] 4.3 Add `bin/sbx` (header block, `set -euo pipefail`) with `sbx [--rebuild] [--up] [--] <cmd> [args...]`. It shows usage and exits 2 when there is no command and no `--up`. It computes the image hash and builds, writes the policy dir and generated config, recreates the container only on an `sbx.config` label mismatch, tags the image, runs `devcontainer exec` with the command, and propagates its exit status. It fails loudly on a missing docker/devcontainer, a failed build, or a container that does not start (pointing at `docker logs`). Verify (host):
  - `sbx` prints usage and creates no container.
  - `sbx claude --resume` resumes.
  - A second `sbx bash` attaches without killing the first.
  - `sbx opencode` in a claude-only project exits 127.
  - `sbx -- --rebuild` runs `--rebuild` as a command.
  - Editing `.sbx/config` prompts and recreates.
- [ ] 4.4 Switch `sbx-acp.sh` to `sbx claude-agent-acp`. Verify (host): an editor ACP session starts in an approved project and fails with the "run `sbx --up` once" message in an unapproved one.
- [ ] 4.5 README: replace the `.bashrc` functions with `PATH` + `sbx` usage. Document the base-vs-config rule, the `.sbx/config` keys with an example, the approval prompt, `--rebuild`/`--up`, `sbx-img` image pruning, and the migration (tools in config, `host-network = on` where needed). Update the volume section for tool volumes. Verify that every command shown in the README matches `bin/sbx`'s usage text.
- [ ] 4.6 Update the root `CLAUDE.md` "Host-side" section (`sbx` replaces `sbx-up`/`sbx-claude`) and verify that no remaining reference to the removed functions survives (`grep -rn 'sbx-up\|sbx-claude' --exclude-dir=archive`).

## 5. Verification suite

- [ ] 5.1 verify.sh:
  - Check 1 picks blocked-probe hosts that are not in the mounted whitelist, and FAILs if none remain.
  - Check 3 probes come from each tool's `probe`.
  - Check 4 asserts the host /24 rule matches `HOST_NETWORK`.
  - Check 7 volumes come from `tools.list` + `tool.conf`.

  Update the header list. Verify (host): `VERIFIED` with `tools =`, `tools = claude`, and `tools = claude opencode`. A project with `allow = example.com` still verifies. A project that disables opencode after using it still verifies.
- [ ] 5.2 Add the checks: each tool's `bin` is on `PATH` with a read-only package dir, `.sbx` is read-only when present, and `/usr/local/etc/sbx` is read-only and outside the workspace. Verify (host): each check PASSes, and `touch .sbx/x` inside the container fails. A temporary override that drops the `.sbx` read-only bind makes verify FAIL.
- [ ] 5.3 (host) A project whose `.sbx/config` has `allow = example.com` can reach example.com. Removing that line and rerunning `sbx --up` blocks it again. `deny = developers.cloudflare.com` blocks that host. `mount = <dir>` is readable and not writable, and `mount = <dir>:rw` is writable. Verify each by running `sbx curl ...` and `sbx touch ...`.

## 6. Integration

- [ ] 6.1 (host) In a project without `.sbx/` and with the shipped defaults, `sbx --up` prints `VERIFIED` in postStart. In a project with an existing claude volume set (from before this change) and `tools = claude`, `sbx claude` is still logged in (per 1.1). Then run `openspec validate add-configurable-agents --strict` and confirm it passes.

## Workflow follow-up

- Archive the change after host-side verification (`/opsx:archive`).
