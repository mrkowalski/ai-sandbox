# Spec Delta

## Purpose

Makes Python, run through `uv run`, the language the agent defaults to for throwaway scripts it writes for its own use, whatever project is mounted.

## ADDED Requirements

### Requirement: Managed policy sets Python via uv as the default for intermediate scripts

The managed `/etc/claude-code/CLAUDE.md` SHALL tell the agent to write intermediate scripts in Python and run them with `uv run`, declaring third-party dependencies inline (PEP 723) instead of installing them into an environment. Intermediate scripts are ones written to do the agent's own work, such as data munging, probes, or one-off transforms. The policy SHALL NOT apply to a project's own code, and SHALL NOT override a language the user asks for.

#### Scenario: Agent writes a helper script in a Node project

- **WHEN** the agent needs a one-off script to process data while working in a project whose code is JavaScript
- **THEN** it writes the script in Python and runs it with `uv run`, not `node`

#### Scenario: User names a language

- **WHEN** the user asks for the script in a specific language
- **THEN** the agent uses that language

#### Scenario: Project code is unaffected

- **WHEN** the agent adds or edits code that belongs to the project
- **THEN** it uses the project's own language and tooling


#### Scenario: Script in /tmp

- **WHEN** the agent saves an intermediate script under the `noexec` `/tmp`, such as the session scratchpad
- **THEN** it invokes the script as `uv run <path>`, which works, not as `./<path>`, which exits 126
