# Spec Delta

## MODIFIED Requirements

### Requirement: The declaration applies to every project mounted in the sandbox

The list and the session instructions SHALL take effect in every sandbox session, for every installed coding agent, regardless of which host project is mounted as the workspace. They SHALL NOT require any per-project configuration. The enforcement hook SHALL take effect in every Claude Code session. Agents without an equivalent pre-execution hook get the list and instructions only. That is acceptable because every entry is also enforced by the firewall, absent credentials, or the read-only `.git` mount.

The configuration that activates enforcement and the instructions SHALL live outside the mounted workspace, so that content in the mounted project cannot disable it.

#### Scenario: An arbitrary host project is mounted

- **WHEN** a sandbox session is started against a project that has no knowledge of this sandbox
- **THEN** the list, the enforcement, and the session instructions are all in effect

#### Scenario: Workspace content attempts to disable enforcement

- **WHEN** the mounted project contains configuration that would turn the enforcement off
- **THEN** enforcement remains in effect

#### Scenario: Agent without a hook mechanism

- **WHEN** an `opencode` session runs `git commit`
- **THEN** no guard message is shown, the commit still fails on the read-only `.git` mount, and the session instructions already told the agent to hand the command to the user
