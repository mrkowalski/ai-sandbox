# Spec Delta

## MODIFIED Requirements

### Requirement: Named volumes carry the workspace path

The sandbox's per-project named volumes SHALL carry a component derived from the absolute host path of the workspace folder the container was launched for. The same workspace path SHALL always produce the same component, and two different workspace paths SHALL produce different components.

The derivation SHALL be: take the absolute workspace path, strip the leading `/`, lowercase it, and replace every character outside `[a-z0-9_.-]` with `-`, evaluated bytewise so that a non-ASCII path yields a stable name rather than a locale-dependent one.

That component SHALL lead the name, ahead of any uniqueness key, so that one project's volumes sort together in a listing.

#### Scenario: A volume is attributable to its project

- **WHEN** an operator lists Docker volumes on the host after launching the sandbox in `/home/<user>/tools/sandbox` with `tools = claude opencode`
- **THEN** the base volumes begin `claude-code-bashhistory-home-<user>-tools-sandbox`, `claude-code-npm-home-<user>-tools-sandbox`, and `claude-code-uv-home-<user>-tools-sandbox`
- **AND** the tool volumes begin `claude-code-config-home-<user>-tools-sandbox` for Claude Code and `claude-code-opencode-<state>-home-<user>-tools-sandbox` for each state directory opencode declares
- **AND** filtering the listing on `home-<user>-tools-sandbox` returns that project's volumes and no others

#### Scenario: A path that is not a legal volume name

- **WHEN** the workspace path contains characters Docker does not accept in a volume name - a space, a `+`, an uppercase letter, or a non-ASCII character
- **THEN** the derived name still consists only of characters Docker accepts, and the launch succeeds rather than failing on an invalid volume name

### Requirement: Isolation does not depend on the launcher

Volume names SHALL also contain a uniqueness key supplied by the dev container tooling rather than by the invoking shell, so that two different workspace folders never share a volume even when the workspace-path component is absent or wrong.

#### Scenario: Two projects do not share volumes

- **WHEN** the sandbox is launched in two different workspace folders
- **THEN** each launch mounts its own base and tool volumes, and neither project's tool credentials, session history, bash history, npm cache, or uv cache are visible to the other

#### Scenario: A launcher that does not supply the workspace name

- **WHEN** the sandbox is launched by something that does not supply the workspace-path component - a bare dev container launch outside `sbx` - so the volumes are named with an empty path component
- **THEN** the volumes it mounts are still scoped to that one workspace and are shared with no other project
- **AND** they are a different set from the ones `sbx` mounts for the same workspace, so that launch starts with no tool credentials and cold npm and uv caches

### Requirement: The image carries the same name

The image the sandbox runs SHALL be reachable on the host under a tag derived from the same workspace path as the volumes, so that images and volumes for one project sort and filter together. The same image SHALL also carry a content tag shared by every project that enables the same tools on the same sandbox revision.

#### Scenario: The image is identifiable after launch

- **WHEN** a sandbox launch completes for workspace `/home/<user>/tools/sandbox`
- **THEN** `docker images` lists that container's image under the tag `sbx-home-<user>-tools-sandbox`, and under a content tag in the `sbx-img` repository

#### Scenario: Relaunching does not accumulate tags

- **WHEN** the same workspace is launched again after the image is rebuilt
- **THEN** the per-project tag names the new image, and the project has exactly one such tag rather than one per launch

### Requirement: A volume name that is not this workspace's fails verification

Verification SHALL assert, whenever the verification suite runs, that each mounted base and tool volume carries the workspace-path component derived from this container's own workspace folder, ahead of a non-empty uniqueness key. The expected set SHALL be the base volumes plus the state volumes declared by the tools installed in the image. A name whose component is absent, does not match, or cannot be determined SHALL fail verification rather than warn: the volumes stay isolated either way, but a launcher that cannot name them does not know the naming rule, and this project fails loudly rather than degrading quietly.

#### Scenario: The naming is checked by the verification suite

- **WHEN** the verification suite runs
- **THEN** it reports a passing check that the bash history, npm cache, and uv cache mounts, and every installed tool's state mounts, are backed by volumes carrying the name derived from this container's workspace path

#### Scenario: A missing workspace name fails verification

- **WHEN** the container is started without the workspace-path component being supplied, so the volumes are named with an empty path component
- **THEN** verification reports a failure that names the empty component and identifies the launcher as its cause, prints `NOT VERIFIED`, and exits non-zero

#### Scenario: A stale or mismatched name fails verification

- **WHEN** the mounted volumes' names do not carry the component derived from this container's workspace path - because the derivation on the host and the one used to check it have drifted apart, or the container was started against another workspace's volumes
- **THEN** verification reports a failure naming both the expected and the mounted volume
- **AND** verification fails rather than passing silently when the mounted volume names cannot be determined at all

#### Scenario: An installed tool's state is not on a volume

- **WHEN** a tool installed in the image has a declared state directory that is not backed by a named volume
- **THEN** verification reports a failure naming the tool and the directory
