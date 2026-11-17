## ADDED Requirements

### Requirement: OpenSpec is an optional tool

The base image SHALL NOT contain OpenSpec. It SHALL be available only as the `openspec` tool bundle, which a config enables through `tools`. The bundle SHALL add no reachable host, and OpenSpec telemetry SHALL be off wherever the bundle is installed.

#### Scenario: Not enabled

- **WHEN** a project's resolved `tools` does not list `openspec`
- **THEN** `openspec` is not on `PATH` in its container

#### Scenario: Enabled

- **WHEN** a project sets `tools = claude openspec`
- **THEN** `openspec` runs from a read-only directory with `OPENSPEC_TELEMETRY=0`, and the effective whitelist is the same as with `tools = claude`
