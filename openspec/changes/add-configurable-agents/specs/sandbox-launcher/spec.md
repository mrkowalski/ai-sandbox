# Spec Delta

## Purpose

Defines the one host command that brings a project's sandbox up and runs any command in it. That command replaces the per-agent shell functions.

## ADDED Requirements

### Requirement: sbx runs the given command verbatim

`sbx [--rebuild] [--up] [--] <cmd> [args...]` SHALL bring the sandbox up for the current folder if needed. It SHALL then run `<cmd>` with exactly the given arguments inside it, attached to the terminal. Its exit status SHALL be the command's. Options are recognized only before the command or `--`. There SHALL be no default command.

#### Scenario: Agent with arguments

- **WHEN** the user runs `sbx claude --resume`
- **THEN** `claude --resume` runs inside the project's sandbox, with nothing added by the launcher

#### Scenario: No command

- **WHEN** the user runs `sbx` with no command
- **THEN** it prints usage, exits non-zero, and does not start or create a container

#### Scenario: Command not installed

- **WHEN** the user runs `sbx opencode` in a project whose config does not enable `opencode`
- **THEN** the command fails with the shell's command-not-found status, and the container stays up

#### Scenario: Command that looks like an option

- **WHEN** the user runs `sbx -- --rebuild`
- **THEN** `--rebuild` is run as the command, not interpreted by the launcher

### Requirement: The container can be brought up without running anything

`sbx --up` with no command SHALL resolve and approve the config and bring the container up, then exit 0 without running a command.

#### Scenario: Pre-approving for a non-interactive caller

- **WHEN** the user runs `sbx --up` in a project with a new `.sbx/config`
- **THEN** the approval prompt is shown, and once confirmed, later non-interactive launches of that project proceed

### Requirement: The container is reused unless its config changed

`sbx` SHALL reuse the project's running container when it was created from the same resolved config and image. Otherwise it SHALL recreate the container. A changed config SHALL never be silently ignored.

#### Scenario: Second terminal on the same project

- **WHEN** a command is already running in the project's container and the user runs another `sbx` command with no config change
- **THEN** it runs in the same container, and the first command keeps running

#### Scenario: Config changed

- **WHEN** the project config, the defaults, or any sandbox file baked into the image changed since the container was created
- **THEN** `sbx` rebuilds the image if needed and recreates the container before running the command

### Requirement: Rebuild on demand

`sbx --rebuild` SHALL rebuild the image without the build cache, then recreate the container, so that tools pinned to `latest` can be refreshed.

#### Scenario: Refreshing a tool

- **WHEN** the user runs `sbx --rebuild claude`
- **THEN** each enabled tool is reinstalled from its upstream, the container runs the new image, and `claude` starts in it

### Requirement: Launch failures are loud

`sbx` SHALL exit non-zero with a clear message, and run no command, when Docker or the devcontainer CLI is missing, the config is invalid or unapproved, the image fails to build, or the container fails to start.

#### Scenario: Firewall fails at start

- **WHEN** the container stops because firewall installation failed
- **THEN** `sbx` reports that the container did not start, points at `docker logs`, and does not attempt to run the command
