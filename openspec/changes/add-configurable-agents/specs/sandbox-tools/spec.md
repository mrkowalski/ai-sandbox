# Spec Delta

## Purpose

Lets the sandbox host many tools, such as coding agents, without installing all of them everywhere. Each project's image contains only the tools that project enables, and every tool runs under the same tool-neutral enforcement.

## ADDED Requirements

### Requirement: Enforcement is tool-neutral

The firewall, read-only rootfs, read-only `.git` and `.sbx`, entrypoint gate, and verification suite SHALL be part of a base that every image shares. No tool fragment SHALL be able to remove or weaken them.

#### Scenario: An image with no Claude Code

- **WHEN** a project enables only `opencode`
- **THEN** the container installs the firewall at start, mounts `.git` read-only, and verification prints `VERIFIED` exactly as it does for a Claude Code image

### Requirement: Tools are self-contained fragments

Each tool SHALL be defined by one directory in this repo. That directory declares the tool's install step, the binaries it provides, the egress domains it requires, its state directories, and its reachability probe. A fragment SHALL NOT declare a start command. Adding a tool SHALL NOT require editing the base or any other tool.

#### Scenario: Adding a new tool

- **WHEN** a maintainer adds a directory for a new tool and a project enables it
- **THEN** that project's next launch builds an image containing it, with no edits to the base Dockerfile, the firewall, or other tools

### Requirement: An image contains only the enabled tools

The image a project runs SHALL contain the binaries of the tools its resolved config enables and no others. Images SHALL be identified by their content, so that projects enabling the same tools on the same sandbox revision share one image.

#### Scenario: Tool not enabled

- **WHEN** a project enables only `claude`
- **THEN** the `opencode` binary is not present in its container

#### Scenario: No tools enabled

- **WHEN** neither the defaults nor the project config enable any tool
- **THEN** the container runs with the base tooling only (shell, git, node/npm, uv/python)

#### Scenario: Two projects, same tools

- **WHEN** two projects enable the same tools and the sandbox files have not changed
- **THEN** the second launch reuses the first one's image without building

### Requirement: Tools bake in their sandbox defaults

A tool fragment SHALL be able to install, from outside the workspace, the settings that make the plain binary behave correctly in the sandbox, so that running a tool needs no sandbox-specific arguments.

#### Scenario: Claude without flags

- **WHEN** the user runs `sbx claude` in a project that enables `claude`
- **THEN** Claude Code starts with permission prompts bypassed, as `claude --dangerously-skip-permissions` does today

### Requirement: Tool binaries are not writable from inside

Tool binaries and their baked settings SHALL be installed into the image's read-only rootfs, not into a volume or the workspace.

#### Scenario: Agent tampers with a tool

- **WHEN** a process inside the container tries to modify any installed tool's binary, package directory, or baked settings
- **THEN** the write fails with a read-only filesystem error

### Requirement: Tool state is per project and per tool

Each enabled tool's declared state directories SHALL be backed by named volumes scoped to the project, so that credentials and sessions persist across container recreation and are shared with no other project.

#### Scenario: Recreating the container keeps the login

- **WHEN** the container is recreated because the project config changed
- **THEN** every enabled tool still has its credentials and session history

#### Scenario: Disabling and re-enabling a tool

- **WHEN** a tool is removed from a project's config and later added back
- **THEN** its earlier state volume is mounted again rather than a fresh one

### Requirement: Every coding agent receives the sandbox policy

Each coding-agent tool SHALL be configured, from a location outside the workspace, to load the sandbox policy text: the host-only commands and the intermediate-scripts guidance.

#### Scenario: Non-Claude agent reaches a host-only step

- **WHEN** an `opencode` session needs to commit its work
- **THEN** the session has the policy text in context that tells it to hand the command to the user instead of running it

### Requirement: Verification follows the installed tools

Verification SHALL derive the tools it checks from the image itself. For each installed tool it SHALL assert that its declared binaries are on `PATH`, that its state volumes are mounted under the expected names, and that its declared endpoint is reachable.

#### Scenario: Tool endpoint unreachable

- **WHEN** an enabled tool's declared endpoint cannot be reached after start
- **THEN** post-start verification reports that tool's endpoint as a failure and prints `NOT VERIFIED`, and the container keeps running (the start-time gate stays offline)

#### Scenario: Volumes of a disabled tool

- **WHEN** a project has disabled a tool it used before
- **THEN** verification does not expect that tool's volumes, and does not fail because they are absent
