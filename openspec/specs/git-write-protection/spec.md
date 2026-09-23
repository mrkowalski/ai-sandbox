## Purpose

Guarantees that the git repository of the project mounted into the sandbox cannot be modified from inside it, so that the history of the user's real repository is written only on the host, while the agent keeps full read access to it.

## Requirements

### Requirement: The mounted project's git repository is not writable from inside the sandbox

The sandbox SHALL make the git directory of the mounted workspace unwritable to the agent by a containment control enforced outside the agent's reach, not by instruction or by a command filter alone.

Every git operation that records, rewrites, or stages repository state - including committing, merging, rebasing, cherry-picking, reverting, tagging, staging, stashing, moving refs, and editing repository configuration - SHALL fail when attempted against the mounted workspace, whether invoked by the agent directly, through a package runner, or from inside a script the agent runs.

This protection SHALL NOT depend on the session's permission mode, on any command list, or on any instruction the agent is given, and SHALL remain in force if all three are absent or bypassed.

#### Scenario: The agent commits inside a script

- **WHEN** the agent runs a script that invokes `git commit` in the mounted workspace, so that no command filter inspects it
- **THEN** the commit fails and the repository's history is unchanged

#### Scenario: The command filter is bypassed

- **WHEN** the agent uses the documented single-invocation bypass to run a declared git command against the mounted workspace
- **THEN** the command still fails, because the bypass applies to the filter and not to this protection

#### Scenario: Staging is refused

- **WHEN** the agent attempts to stage, stash, or otherwise write to the repository without creating a commit
- **THEN** the attempt fails

### Requirement: Reading the mounted repository remains fully available

The protection SHALL be confined to writes. Inspecting the repository SHALL continue to work without error, warning, or degradation, so the agent can understand the project's history and show the user exactly what it changed.

At minimum, reporting status, showing differences against the index or a commit, reading the log, showing a commit, listing branches, and listing tags SHALL all succeed.

#### Scenario: Ordinary inspection during a task

- **WHEN** the agent reports status, diffs the working tree, reads the log, or lists branches and tags in the mounted workspace
- **THEN** each command succeeds and produces its normal output

#### Scenario: Handing work back

- **WHEN** the agent has finished changes the user will commit on the host
- **THEN** it can still show the complete diff of those changes from inside the sandbox

### Requirement: Repositories outside the mounted workspace are unaffected

The protection SHALL apply to the mounted workspace's repository. A repository the sandbox creates in its own writable scratch space SHALL remain fully usable, so that tooling which builds a throwaway repository - including the sandbox's own start-time verification - continues to work.

#### Scenario: Start-time verification's scratch repository

- **WHEN** verification creates a temporary repository outside the workspace and commits to it
- **THEN** that commit succeeds

### Requirement: No git credentials or SSH keys are present in the sandbox

The sandbox SHALL contain no SSH private keys, no forwarded SSH agent, and no configured git credential helper, so that publishing history has no credential to use even before the network is considered.

#### Scenario: Looking for a key to push with

- **WHEN** a push is attempted from inside the sandbox
- **THEN** no key, agent socket, or stored credential is available to authenticate it

### Requirement: Mounting a workspace that is not a git repository leaves nothing behind that the user cannot remove

Where the protection requires a path to exist in the mounted project, the sandbox SHALL ensure that any such path it causes to be created in a project that is not a git repository is owned by the user, so it can be removed without elevated privileges.

#### Scenario: Sandbox launched on a folder with no repository

- **WHEN** the sandbox is started against a project directory that contains no git repository
- **THEN** the session starts normally
- **AND** anything created in the project directory to support this protection is removable by the user without `sudo`

### Requirement: Start-time verification asserts the protection in both directions

The sandbox's start-time verification SHALL assert that the protection is actually in force, and SHALL fail the launch when it is not.

It SHALL confirm that a write to the mounted repository is refused, and - because over-blocking is as much a failure as under-blocking - that reading the repository still succeeds. It SHALL also assert the absence of SSH private keys, a forwarded SSH agent, and a git credential helper.

When the mounted workspace contains no git repository, verification SHALL report that the write assertion did not apply rather than passing it silently or failing the launch.

#### Scenario: The protection is missing

- **WHEN** the workspace's git directory is writable at container start
- **THEN** verification reports the failure and the launch fails

#### Scenario: The protection is too broad

- **WHEN** the workspace's git directory cannot be read
- **THEN** verification reports the failure and the launch fails

#### Scenario: A credential appears in the sandbox

- **WHEN** an SSH private key, a forwarded agent socket, or a git credential helper is present at container start
- **THEN** verification reports it

#### Scenario: Workspace is not a repository

- **WHEN** the mounted workspace contains no git repository
- **THEN** verification reports the write assertion as not applicable and the launch proceeds
