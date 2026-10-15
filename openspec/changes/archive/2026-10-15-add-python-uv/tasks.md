# Tasks

Verification of `.devcontainer/` changes happens on the host, after `sbx-up` rebuilds the image. Nothing here can be tested inside the sandbox.

## 1. uv and interpreter in the image

- [x] 1.1 Dockerfile: `COPY --from=ghcr.io/astral-sh/uv:<pinned>` for `uv`/`uvx` into `/usr/local/bin`. `uv python install <pinned> --default` with `UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python` and `UV_PYTHON_BIN_DIR=/usr/local/bin`. `ENV UV_PYTHON_DOWNLOADS=never UV_PYTHON_PREFERENCE=only-managed UV_LINK_MODE=copy UV_CACHE_DIR=/home/node/.cache/uv`. Pre-create `/home/node/.cache/uv` owned by `node`. Verify: `uv --version`, `python3 --version`, and `uv run --python 3.99 python -c 1` fails fast with "No interpreter found for Python 3.99 in virtual environments or managed installations".
- [x] 1.2 verify.sh: add a check that `uv run --offline` on a stdlib script prints the expected output (`bad` on failure). Add `check_ro_dir /usr/local/share/uv/python`. Update the header list. Verify: the full `verify.sh` run shows both PASS.

## 2. uv cache volume

- [x] 2.1 devcontainer.json: add the `claude-code-uv-${localEnv:SBX_SLUG}-${devcontainerId}` volume at `/home/node/.cache/uv`. Verify: `docker volume ls | grep claude-code-uv` on the host after `sbx-up`.
- [x] 2.2 verify.sh: factor check 6 into `check_cache_dir <dir> <label>` and call it for npm (`npm config get cache`) and uv (`uv cache dir`). Add `uv:/home/node/.cache/uv` to check 7's volume list. Verify: PASS for both caches and all four volumes. A container created before this change fails check 7.
- [x] 2.3 Update `.devcontainer/CLAUDE.md` (section 1 volumes and cache rationale, section 5 check list) and the README "Container volumes" section to four volumes, and verify that both list `claude-code-uv-*`.

## 3. PyPI egress

- [x] 3.1 allowed-domains.txt: add `pypi.org` and `files.pythonhosted.org` under a `## Python` heading. In the comment, note the `upload.pypi.org` shared-IP caveat. Verify: the firewall installs and the container starts.
- [x] 3.2 verify.sh: add `check_reachable https://pypi.org/simple/ ... optional` in check 3, and a `github.com` must-be-blocked probe in check 1. Verify: a host-side run of a PEP 723 script with `dependencies = ["requests"]` through `uv run` succeeds twice, and the second run doesn't download (this also covers the restart scenario if a container restart happens between the runs).

## 4. Default scripting language

- [x] 4.1 sandbox-policy.md: broaden the H1. Add a terse `## Intermediate scripts` section: write them in Python, run with `uv run <path>` (never `./<path>`, since `/tmp` is noexec), declare deps via PEP 723, leave the project's own code and any language the user names alone, and use `uvx` rather than `uv tool install`. Verify: inside a rebuilt container, `/etc/claude-code/CLAUDE.md` contains the section, and a fresh session asked for a throwaway data transform writes a `.py` and runs it with `uv run`.

## 5. Integration

- [x] 5.1 Host-side: `sbx-up` from scratch, then the full `verify.sh` prints `VERIFIED`. `openspec validate add-python-uv --strict` passes.

## Workflow follow-up

- Archive the change after host-side verification (`/opsx:archive`).
