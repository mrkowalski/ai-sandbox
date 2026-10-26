# Spec Delta

## Purpose

Lets the sandbox host many tools, such as coding agents, without installing all of them everywhere. Each tool comes as one bundle carrying everything it needs, each project's image contains only the tools that project enables, every agent can be driven over ACP, and every tool runs under the same tool-neutral enforcement.

## ADDED Requirements

### Requirement: Enforcement is tool-neutral

The firewall, read-only rootfs, read-only `.git` and `.sbx`, entrypoint gate, and verification suite SHALL be part of a base that every image shares. No tool bundle SHALL be able to remove or weaken them.

#### Scenario: An image with no Claude Code

- **WHEN** a project enables only `opencode`
- **THEN** the container installs the firewall at start, mounts `.git` read-only, and verification prints `VERIFIED` exactly as it does for a Claude Code image

### Requirement: Tools are self-contained bundles

Each tool SHALL be defined by one bundle directory, enabled as a unit when a config lists the tool. The bundle declares its install step, baked config files and hooks, its own scripts and interactive shell aliases, binaries, required hostnames and IPv4 ranges, persistent state directories, other writable directories, and reachability probe. It SHALL NOT declare a start command. Adding a tool SHALL NOT require editing the base or any other tool.

#### Scenario: Adding a new tool

- **WHEN** a maintainer adds a directory for a new tool and a project enables it
- **THEN** that project's next launch builds an image containing it, with no edits to the base Dockerfile, the firewall, or other tools

#### Scenario: A tool that needs writable directories

- **WHEN** a bundle declares directories outside the workspace as persistent state or as scratch space
- **THEN** the tool can write there, and the rest of the rootfs, including that tool's binaries and baked settings, stays read-only

#### Scenario: A bundle brings its own hook

- **WHEN** a project enables `opencode`
- **THEN** opencode's baked config and guard plugin are in effect with no project file, and disabling `opencode` removes them with it

### Requirement: Bundles require only hosts every configuration needs

A bundle's required hosts and reachability probe SHALL name only endpoints the tool needs under every configuration. A host the user chooses, such as an agent's model provider, SHALL NOT be a bundle host; the project config adds it with `allow`.

#### Scenario: Agent with a user-chosen model provider

- **WHEN** a project enables only `opencode`
- **THEN** no model provider's API is reachable until the project allows one, and verification does not require one to be reachable

### Requirement: Bundles can ship scripts

A bundle SHALL be able to ship executable scripts that are on `PATH` ahead of the tools' own binaries whenever the bundle is enabled, both for `sbx <cmd>` and for ACP commands. A script MAY have the same name as one of the bundle's own binaries and wrap it, which is how a bundle adds default arguments to its binary. A bundle SHALL also be able to ship aliases and functions that interactive shells load.

#### Scenario: Helper script

- **WHEN** an enabled bundle ships a script `foo`
- **THEN** `sbx foo` runs it inside the sandbox, and a process inside the container cannot modify it

#### Scenario: Wrapper adds default flags

- **WHEN** an enabled bundle ships a script with the same name as its binary that runs the binary with an extra flag
- **THEN** `sbx <binary>` runs the wrapper, and the binary runs with the flag added

#### Scenario: Interactive alias

- **WHEN** an enabled bundle ships a shell alias
- **THEN** the alias is defined in `sbx bash`, and is absent from the container when the tool is disabled

### Requirement: Bundle scripts do not collide

A bundle script SHALL NOT shadow a base command, and two enabled bundles SHALL NOT ship scripts with the same name. Either one SHALL fail the image build.

#### Scenario: Script shadows a base command

- **WHEN** a bundle ships a script named `git`, or two enabled bundles ship scripts with the same name
- **THEN** the image build fails and names the script and the bundles

### Requirement: Bundles come only from this repo

A project config SHALL select bundles from this repo and SHALL NOT supply one, so that no file from a mounted or cloned project is built into the image.

#### Scenario: A project ships its own bundle

- **WHEN** a project contains `.sbx/tools/<name>/` and enables `<name>`, for which this repo has no bundle
- **THEN** nothing from that directory is built into the image, and the launch aborts as an unknown tool

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

A tool bundle SHALL be able to install, from outside the workspace, the settings that make the plain binary behave correctly in the sandbox, so that running a tool needs no sandbox-specific arguments.

#### Scenario: Claude without flags

- **WHEN** the user runs `sbx claude` in a project that enables `claude`
- **THEN** Claude Code starts with permission prompts bypassed, as `claude --dangerously-skip-permissions` does today, and shows no bypass-mode confirmation, whether through baked settings or a bundle wrapper

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

### Requirement: Every coding agent is reachable over ACP

Every coding-agent bundle SHALL declare the command that serves the agent over the Agent Client Protocol on stdio, and that command SHALL be installed with the agent. ACP SHALL NOT be a separate opt-in: enabling an agent enables its ACP server. A bundle that declares itself an agent without an ACP command SHALL be rejected when the config is resolved.

#### Scenario: Any enabled agent from an IDE

- **WHEN** a project enables `claude opencode`
- **THEN** an editor can start either agent as an ACP server inside the project's sandbox

#### Scenario: Agent bundle without ACP

- **WHEN** a bundle declares itself an agent and declares no ACP command
- **THEN** the launch aborts and names that bundle's `tool.conf`

### Requirement: Every coding agent receives the sandbox policy

Each coding-agent tool SHALL be configured, from a location outside the workspace, to load the sandbox policy text: the host-only commands and the intermediate-scripts guidance.

#### Scenario: Non-Claude agent reaches a host-only step

- **WHEN** an `opencode` session needs to commit its work
- **THEN** the session has the policy text in context that tells it to hand the command to the user instead of running it

### Requirement: Verification follows the installed tools

Verification SHALL derive the tools it checks from the image itself. For each installed tool it SHALL assert that its declared binaries, and an agent's ACP command, are on `PATH`, that its state volumes are mounted under the expected names, that its declared scratch directories are writable, that its scripts are on `PATH` and read-only, and that its declared endpoint is reachable.

#### Scenario: Tool endpoint unreachable

- **WHEN** an enabled tool's declared endpoint cannot be reached after start
- **THEN** post-start verification reports that tool's endpoint as a failure and prints `NOT VERIFIED`, and the container keeps running (the start-time gate stays offline)

#### Scenario: Volumes of a disabled tool

- **WHEN** a project has disabled a tool it used before
- **THEN** verification does not expect that tool's volumes, and does not fail because they are absent
