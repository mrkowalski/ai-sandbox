# Tasks

## 1. Bundle and base image

- [x] 1.1 Add `.devcontainer/tools/openspec/tool.conf` (`type = tool`, `bin = openspec`, `env = OPENSPEC_TELEMETRY=0`; no `allowed-domains.txt`, volume, or probe) and `install.sh` (header block, `set -euo pipefail`, `npm install -g @fission-ai/openspec@latest`). Verify `sbx-env.sh` accepts the bundle: `sbx --up` with `tools = claude openspec` gets past config resolution.
- [x] 1.2 Remove `ENV OPENSPEC_TELEMETRY=0` and the `npm install -g @fission-ai/openspec@latest` line (with its comment) from `.devcontainer/Dockerfile`. Verify `grep -rni openspec .devcontainer/Dockerfile` is empty.
- [x] 1.3 Add `openspec` to this repo's `.sbx/config` (`tools = claude openspec`) so planning keeps working here.
- [x] 1.4 Docs: drop openspec from the base list in `README.md` (Base vs config) and the base row in `.devcontainer/CLAUDE.md`; mention the `openspec` bundle where README lists tools, and rewrite "OpenSpec maintenance" (skills now live globally on the host, not in `.claude/skills`). Verify `grep -rn -i openspec README.md .devcontainer/CLAUDE.md` shows only the bundle and maintenance mentions.

## 2. Host verification (user)

- [x] 2.1 (host) `sbx --rebuild --up` with `tools = claude`: postStart prints `VERIFIED` and `sbx sh -c 'command -v openspec'` exits non-zero.
- [x] 2.2 (host) With `tools = claude openspec`: `VERIFIED`, `sbx openspec --version` works, `sbx printenv OPENSPEC_TELEMETRY` prints `0`, and the effective `allowed-domains.txt` under `~/.local/state/sbx/<slug>/policy/` matches the `tools = claude` one.

## Workflow follow-up

- Archive after `add-configurable-agents`, which introduces the `sandbox-tools` capability this delta adds to.
