# Tasks

Nothing under `.devcontainer/`, and no `docker`/`devcontainer` command, can be tested inside the sandbox. Every "Verify" step marked (host) is for the user to run on the host.

## 1. Launch-path spike

- [ ] 1.1 (host) Confirm what `devcontainer up --config .devcontainer/devcontainer.json --override-config <file>` does. Check whether `devcontainerId` stays the same as a plain `--config` launch, and whether the override replaces or merges with the base config. To verify, run the same `docker volume ls` before and after with an override that only adds a label, and record the result in design.md. If the id changes, switch design.md and 4.1 to the fallback (generated file as `--config`), and add the one-time volume migration note to the README.

## 2. Base image and tool bundles

- [ ] 2.1 Make `sandbox-policy.md` agent-neutral. Bake it to `/etc/sbx/sandbox-policy.md` in the base. Remove the Claude Code/ACP installs, the `managed-settings.json` copy, `CLAUDE_CODE_VERSION`, and the `allowed-domains.txt` copy from the base Dockerfile. Add an empty `/usr/local/etc/sbx` mount point, `ARG TOOLS=`, `COPY tools/`, the per-tool install loop, and `tools.list`. Split `host-only-guard.sh`: the list matching moves to a base `/usr/local/bin/host-only-check` (command string in, exit 2 with the policy message on a match, 0 otherwise), and the Claude hook becomes an adapter that calls it. Verify (host): `docker build --build-arg TOOLS=` succeeds, `tools.list` is empty, no `allowed-domains.txt` exists in the image, and `host-only-check 'git commit -m x'` exits 2 with the message while `host-only-check 'git status'` exits 0.
- [ ] 2.2 Add `tools/claude/` (`install.sh` for Claude Code and `claude-agent-acp`, `install-root.sh` for `/etc/claude-code/` with `permissions.defaultMode = "bypassPermissions"` plus the guard hook adapter, `tool.conf` with `type = agent` and `acp = claude-agent-acp`, `allowed-domains.txt` with the Anthropic, statsig, and sentry hosts). Verify (host): in a `claude`-enabled project, `sbx claude` starts with permissions bypassed and no flag, and with no confirmation dialog (add `skipDangerousModePermissionPrompt` if one appears). `/etc/claude-code/CLAUDE.md` matches the policy. Asking Claude to run `git commit` shows the guard message.
- [ ] 2.3 Add `tools/opencode/`: `npm i -g opencode-ai`; `/etc/sbx/opencode/` with `opencode.json` (`instructions`) and `plugin/host-only-guard.js` (a `tool.execute.before` adapter over `host-only-check`); `env = OPENCODE_CONFIG_DIR=/etc/sbx/opencode`; `type = agent`, `acp = opencode acp`; state volumes; a `volume` or `tmpfs` for each further directory it writes; domains. Find the directories by running it on the read-only rootfs and recording each EROFS; persistent caches get a `volume`, the rest `tmpfs`. Confirm which domains opencode needs to start with an Anthropic provider and record them in its `allowed-domains.txt`. Confirm the plugin loads from `OPENCODE_CONFIG_DIR`; if it cannot be loaded from outside the workspace, drop it and record that in design.md. Verify (host): with `tools = claude opencode`, `sbx opencode` starts and answers a prompt with no EROFS, its session shows the sandbox policy loaded, and asking it to run `git commit` shows the guard message.
- [ ] 2.4 Update `.devcontainer/CLAUDE.md`: the base-vs-config rule and table, tool bundles (what a bundle may and may not grant), the shared guard matcher and its adapters, where the policy lives, and the `/usr/local/etc/sbx` mount. Verify that it names every enforcement file this change touched.

## 3. Firewall policy from the mount

- [ ] 3.1 `init-firewall.sh`: switch the default whitelist path to `/usr/local/etc/sbx/allowed-domains.txt`. Read `HOST_NETWORK` from `/usr/local/etc/sbx/firewall.conf` with `grep` (never `source`; a missing or invalid value means `0`). Add the host /24 rules only for `1`. Add whitelist entries that are IPv4 addresses or CIDR ranges to the ipset as given, without `dig`. Update the header. Verify (host): without the mount, the container stops and `docker logs` names the unreadable whitelist. With `host-network` unset, `curl` to a server on the Docker gateway is rejected; with `host-network = on`, it succeeds. A project with `allow = <public IPv4 address>` reaches that address.

## 4. Config and launcher

- [ ] 4.1 Add `.devcontainer/sbx-defaults.conf` (`tools =`, plus `allow` lines for the npm registry, PyPI, and the Cloudflare docs). In `sbx-env.sh`, add the `key = value` parser and resolver (no `source`, no `eval`) for config and `tool.conf`. It produces the tools, the effective whitelist, `host-network`, the mounts, and the volumes/tmpfs/env/ACP command per tool. It rejects unknown keys, bad hostnames, IPv4 entries that are private or wider than /16, unknown tools, `deny` of a tool-required entry, an `agent` bundle without `acp`, an `acp` whose first word is not a `bin`, and invalid or protected mounts (checked on `realpath`), each error naming the file and line. Verify: a `uv run` test script in the scratchpad feeds valid and invalid configs (including `allow = $(touch /tmp/pwned)`, `git-readonly = off`, `mount = $HOME:rw`, a symlink to the sandbox repo with `:rw`, `allow = 10.0.0.0/8`, `allow = 8.0.0.0/8`, `allow = 203.0.113.0/24`, and test bundles with `type = agent` and no `acp`) and checks the outputs, the exit codes, and that nothing was executed.
- [ ] 4.2 Implement the approval gate: a sha256 stored in `~/.local/state/sbx/<slug>/approved`, a printed delta (tools, hosts and IPv4 ranges, host-network, mounts), a prompt defaulting to No, and a refusal without a TTY. Verify with the same test script, driving it with `</dev/null` and with piped `y`.
- [ ] 4.3 Add `bin/sbx` (header block, `set -euo pipefail`) with `sbx [--rebuild] [--up] [--] <cmd> [args...]`. It shows usage and exits 2 when there is no command and no `--up`. It computes the image hash and builds, writes the policy dir and generated config, recreates the container only on an `sbx.config` label mismatch, tags the image, runs `devcontainer exec` with the command, and propagates its exit status. Everything it prints itself goes to stderr. It fails loudly on a missing docker/devcontainer, a failed build, or a container that does not start (pointing at `docker logs`). Verify (host):
  - `sbx` prints usage and creates no container.
  - `sbx claude --resume` resumes.
  - A second `sbx bash` attaches without killing the first.
  - `sbx opencode` in a claude-only project exits 127.
  - `sbx -- --rebuild` runs `--rebuild` as a command.
  - Editing `.sbx/config` prompts and recreates.
  - `sbx echo hi 2>/dev/null` prints only `hi`.
- [ ] 4.4 Rewrite `sbx-acp.sh` as `sbx-acp.sh <tool>`: parse that bundle's `acp`, refuse a missing name, an unknown or non-agent tool, or one the resolved config does not enable (listing the enabled agents), then exec `sbx -- <acp command>`. Verify (host): `sbx-acp.sh claude` and `sbx-acp.sh opencode` each serve an editor ACP session in an approved project that enables both; an unapproved project fails with the "run `sbx --up` once" message; `sbx-acp.sh opencode` in a claude-only project fails naming `claude`.
- [ ] 4.5 README: replace the `.bashrc` functions with `PATH` + `sbx` usage. Document the base-vs-config rule, the `.sbx/config` keys with an example (including an IPv4 range), the bundle layout and `tool.conf` keys, the `sbx-acp.sh <tool>` editor config, the approval prompt, `--rebuild`/`--up`, `sbx-img` image pruning, and the migration (tools in config, `host-network = on` where needed, editor ACP configs naming the agent). Update the volume section for tool volumes. Verify that every command shown in the README matches `bin/sbx`'s usage text.
- [ ] 4.6 Update the root `CLAUDE.md` "Host-side" section (`sbx` replaces `sbx-up`/`sbx-claude`) and verify that no remaining reference to the removed functions survives (`grep -rn 'sbx-up\|sbx-claude' --exclude-dir=archive`).

## 5. Verification suite

- [ ] 5.1 verify.sh:
  - Check 1 picks blocked-probe hosts that are not in the mounted whitelist and not covered by an allowed range, and FAILs if none remain.
  - Check 3 probes come from each tool's `probe`.
  - Check 4 asserts the host /24 rule matches `HOST_NETWORK`.
  - Check 7 volumes come from `tools.list` + `tool.conf`.

  Update the header list. Verify (host): `VERIFIED` with `tools =`, `tools = claude`, and `tools = claude opencode`. A project with `allow = example.com` still verifies. A project that disables opencode after using it still verifies.
- [ ] 5.2 Add the checks: each tool's `bin` is on `PATH` with a read-only package dir, each agent's `acp` command resolves on `PATH`, each tool's `tmpfs` paths are writable and `noexec`, `.sbx` is read-only when present, and `/usr/local/etc/sbx` is read-only and outside the workspace. Verify (host): each check PASSes, and `touch .sbx/x` inside the container fails. A temporary override that drops the `.sbx` read-only bind makes verify FAIL.
- [ ] 5.3 (host) A project whose `.sbx/config` has `allow = example.com` can reach example.com. Removing that line and rerunning `sbx --up` blocks it again. `deny = developers.cloudflare.com` blocks that host. `mount = <dir>` is readable and not writable, and `mount = <dir>:rw` is writable. Verify each by running `sbx curl ...` and `sbx touch ...`.

## 6. Integration

- [ ] 6.1 (host) In a project without `.sbx/` and with the shipped defaults, `sbx --up` prints `VERIFIED` in postStart. In a project with an existing claude volume set (from before this change) and `tools = claude`, `sbx claude` is still logged in (per 1.1). Then run `openspec validate add-configurable-agents --strict` and confirm it passes.

## Workflow follow-up

- Archive the change after host-side verification (`/opsx:archive`).
