# python-runtime Specification

## Purpose

Lets the agent run Python scripts with `uv`, including scripts that declare their own PyPI dependencies, without weakening the sandbox's rootfs, egress, or git guarantees.

## Requirements

### Requirement: uv runs Python scripts with inline dependencies

The image SHALL provide `uv` and a Python interpreter on `PATH`. `uv run` SHALL run a script that declares PEP 723 inline dependencies, fetching them from PyPI.

#### Scenario: Script with an inline dependency

- **WHEN** the agent runs `uv run script.py`, where the script declares `dependencies = ["requests"]` in a PEP 723 block
- **THEN** uv resolves and installs `requests` from PyPI, and the script runs
- **AND** no `EROFS` or `read-only file system` error is emitted

#### Scenario: Stdlib script runs offline

- **WHEN** the agent runs `uv run --offline` on a script with no dependencies
- **THEN** it runs on the baked interpreter without any network access

### Requirement: The Python interpreter comes from the image

The interpreter SHALL be baked into the read-only rootfs at build time. uv SHALL NOT download an interpreter at runtime. A request for a version the image lacks SHALL fail with an error, not a network attempt.

#### Scenario: Unavailable Python version requested

- **WHEN** a script declares `requires-python` that the baked interpreter does not satisfy
- **THEN** `uv run` fails, reporting that no matching interpreter is found in managed installations
- **AND** no connection to an interpreter download host is attempted

#### Scenario: Interpreter is not writable

- **WHEN** a write is attempted to the baked interpreter's install directory
- **THEN** it fails with a read-only-filesystem error

### Requirement: The uv cache is writable, exec-capable, and per-container

uv's cache SHALL be on a named volume scoped to one dev container instance, mounted without `noexec`, and SHALL persist across restarts. uv runs script environments' binaries from the cache, so a `noexec` cache SHALL NOT satisfy this requirement.

#### Scenario: Cached environment survives a restart

- **WHEN** a script with inline dependencies runs, the container restarts, and the script runs again
- **THEN** the second run uses the cached packages and does not download them again

#### Scenario: Cache not on /tmp

- **WHEN** the mount table is inspected
- **THEN** the uv cache directory is not backed by the `noexec` `/tmp` tmpfs

### Requirement: Python egress is limited to PyPI

The whitelist SHALL gain exactly `pypi.org` and `files.pythonhosted.org`. No other host SHALL become reachable. In particular, the GitHub hosts that serve interpreter downloads SHALL stay blocked.

#### Scenario: Interpreter download host blocked

- **WHEN** verification probes `github.com`
- **THEN** no TCP connection is established

### Requirement: Python runtime guarantees are verified at start

The verification suite SHALL assert that the uv cache is writable and exec-capable and that `uv` and the baked interpreter are usable offline. Any of these failing SHALL fail verification. PyPI reachability SHALL be a warning, not a failure, so a PyPI outage does not stop the sandbox from starting.

#### Scenario: Broken uv cache blocks launch

- **WHEN** the uv cache directory is missing, not writable, or mounted `noexec`
- **THEN** verification reports a failure, prints `NOT VERIFIED`, and exits non-zero

#### Scenario: PyPI unreachable

- **WHEN** PyPI is unreachable at start
- **THEN** verification reports a warning and does not fail on that account
