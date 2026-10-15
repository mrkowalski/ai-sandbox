# Design

## Context

The rootfs is read-only and `$HOME` is not writable, except for the named volumes. `/tmp` is `noexec`. Egress is an ipset of A records resolved once at firewall install. The base image (`node:24-trixie-slim`) has no Python. The npm cache (`npm-cache` spec) is the pattern to copy.

## Goals / Non-Goals

**Non-Goals:** `uv tool install` and `pip install --user` (both write to read-only `$HOME`; `uvx` covers the same need from the cache). Private indexes. Blocking `node` for scripts: the policy guides the agent and nothing enforces it.

## Decisions

**uv binary.** `COPY --from=ghcr.io/astral-sh/uv:<pinned> /uv /uvx /usr/local/bin/`, pinned to a version like the rest of the build. The alternative, the curl installer, is harder to pin and runs a remote script. This is a build-time pull on the host, outside the sandbox firewall.

**Interpreter.** Run `uv python install <pinned 3.x> --default` at build, with `UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python` and `UV_PYTHON_BIN_DIR=/usr/local/bin`. That puts `python`/`python3` on `PATH` on the read-only rootfs. Runtime env: `UV_PYTHON_DOWNLOADS=never` and `UV_PYTHON_PREFERENCE=only-managed`. The interpreter would come from GitHub, which stays blocked, so a runtime download could only fail with a confusing network error. With `never`, uv says plainly that it has no matching interpreter. Debian `python3` was the alternative, but it ties the version to the base image.

**Cache.** Set `UV_CACHE_DIR=/home/node/.cache/uv` on a new volume, `claude-code-uv-${localEnv:SBX_SLUG}-${devcontainerId}`. Pre-create the directory in the Dockerfile, owned by `node`, so the first mount inherits that ownership. A tmpfs won't work: uv runs binaries from script environments in the cache, and `/tmp` is `noexec`. Set `UV_LINK_MODE=copy`. A project `.venv` sits on the workspace bind mount, a different filesystem from the cache, so hardlinks fail and uv falls back with a warning the agent would otherwise misread.

**Egress.** Add `pypi.org` (simple index) and `files.pythonhosted.org` (wheels and sdists) to `allowed-domains.txt` under a new `## Python` heading. Nothing else is needed for `uv run` with inline deps.

**Policy text.** The only managed memory file is `/etc/claude-code/CLAUDE.md` (from `sandbox-policy.md`). Add a short `## Intermediate scripts` section and make its H1 general enough to cover both topics. A second file would never be loaded.

**Verification.** Split check 6 into a helper, `check_cache_dir <dir> <label>`, run for npm and for uv (`uv cache dir`). Add four entries in total: a check that runs `uv run --offline` on a stdlib one-liner, a read-only check on the interpreter dir, and an optional reachability probe for `pypi.org` next to the npm one. Check 7 gets a fourth volume. `github.com` is added as a must-be-blocked probe next to `example.com`.

## Risks / Trade-offs

- [Fastly rotates IPs for `files.pythonhosted.org` behind the once-resolved ipset] → intermittent download failures in long-lived containers. Run `sudo init-firewall.sh` to re-resolve. `registry.npmjs.org` already behaves this way.
- [`upload.pypi.org` can share Fastly IPs with `pypi.org`, so IP-based allowlisting may let it through] → an upload needs a PyPI token, and the sandbox has none. That is the same posture as `npm publish`. Accepted. Record it in the whitelist comment.
- [PyPI is a new exfiltration and supply-chain surface] → this is inherent to the request. The cost and data boundary in the root `CLAUDE.md` stays the same: the agent could already reach npm.
- [Image grows by about 100 MB] → accepted.

## Migration Plan

Rebuild the image and recreate the container with `sbx-up`, which passes `--remove-existing-container`. The new volume only appears on a recreated container. An old container fails check 7, which is intended.
