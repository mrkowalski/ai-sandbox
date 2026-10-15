# Proposal

## Why

The agent writes throwaway scripts in Node because Node is the only interpreter in the image. Python is the better fit for that work, and uv runs it, with PEP 723 inline dependencies, from one command.

## What Changes

- Bake a pinned `uv` and a uv-managed Python into the image. Disable interpreter downloads at runtime.
- Add a per-container `uv` cache volume (writable and exec-capable, like npm's) and whitelist `pypi.org` and `files.pythonhosted.org`. This widens egress.
- Tell the agent, through the managed `/etc/claude-code/CLAUDE.md`, to write intermediate scripts in Python and run them with `uv run`. Node stays available.
- Add `verify.sh` assertions for all of the above.

## Capabilities

### New Capabilities
- `python-runtime`: uv and Python are present, `uv run` works with inline deps from PyPI, the uv cache is writable and exec-capable and persists, and nothing beyond PyPI is reachable.
- `agent-script-language`: the managed policy makes Python via `uv run` the agent's default for intermediate scripts.

### Modified Capabilities
- `docker-resource-naming`: three per-project volumes become four (adds `claude-code-uv-<slug>-<id>`). Verification checks all four.

## Impact

`.devcontainer/` `Dockerfile`, `devcontainer.json`, `allowed-domains.txt`, `sandbox-policy.md`, `verify.sh`, `CLAUDE.md`; README volume section. Image size grows by about 100 MB.
