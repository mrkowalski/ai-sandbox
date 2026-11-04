# Spec Delta

## Purpose

Defines when a project's sandbox container runs and when it stops. Once no `sbx` session is using a project folder, the sandbox holds no mount on that folder and never recreates it.

## ADDED Requirements

### Requirement: The container stops when its last session exits

The project's container SHALL be stopped, not removed, when the last `sbx` session for that folder exits, whatever the command's exit status or how the session ended. This covers sessions started through `sbx-acp.sh`. While at least one session is running, the container SHALL stay up.

#### Scenario: Two sessions, one exits

- **WHEN** two `sbx` sessions run in the same folder and one of them exits
- **THEN** the other keeps running in the same container, and the container stays up

#### Scenario: Last session exits

- **WHEN** the only `sbx` session for a folder exits, normally, with a non-zero status, or because its terminal was closed
- **THEN** the container is stopped
- **AND** the folder can then be deleted on the host and stays deleted

#### Scenario: Launch races the stop

- **WHEN** a new `sbx` session starts in a folder while the previous last session is stopping the container
- **THEN** the new session runs in a started container with the firewall installed. It never finds the container stopped mid-command, and it never runs a command without the firewall.

### Requirement: Stopping does not change what the command sees

Stopping the container on exit SHALL NOT change `sbx`'s exit status, which SHALL remain the command's own. It SHALL NOT write anything to stdout. A failure to stop SHALL be reported on stderr and SHALL NOT replace the command's status.

#### Scenario: ACP session ends

- **WHEN** an editor ends an `sbx-acp.sh` session that was the folder's only one
- **THEN** the agent's stdout carried only the agent's output, and the container is stopped

### Requirement: Bringing the container up without a command leaves it stopped when idle

`sbx --up` with no command SHALL bring the container up and pass start-time verification, then stop it again unless a session is using it. It SHALL exit 0 only if bring-up and verification succeeded.

#### Scenario: Approving a config ahead of ACP use

- **WHEN** the user runs `sbx --up` in a folder with no running session
- **THEN** the config is approved, the container comes up and verifies, and it is stopped before `sbx` exits

### Requirement: The sandbox never creates the project folder

Neither `sbx` nor any step it runs SHALL create the project folder. A launch from a folder that no longer exists SHALL fail with a clear message and create nothing on the host.

#### Scenario: Launch from a deleted folder

- **WHEN** `sbx` is run from a shell whose working directory has been deleted
- **THEN** it exits non-zero naming the missing folder, and the folder is not recreated
