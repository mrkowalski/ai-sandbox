## ADDED Requirements

### Requirement: Git and GitHub account operations are declared host-only

The list SHALL declare host-only every command that writes the mounted repository — recording a commit, rewriting history, publishing it, or staging toward it — and every `gh` subcommand that authenticates against or acts on a GitHub account.

At minimum this SHALL cover `git push`, `git commit`, `git merge`, `git rebase`, `git cherry-pick`, `git revert`, `git am`, the mutating forms of `git tag`, and the staging commands `git add`, `git stash`, `git rm`, and `git mv`, including their invocations that carry global options such as `-C <dir>`.

Git commands that only read the repository — reporting status, showing differences, reading the log, showing a commit, listing branches, listing tags — SHALL NOT be declared host-only, so the agent can still show the user exactly what it changed.

These declarations SHALL be understood as the sandbox explaining a refusal, not as the mechanism producing it: the mounted repository's write protection is specified in `git-write-protection` and holds independently of this list.

#### Scenario: The agent tries to commit its work

- **WHEN** the agent attempts `git commit` in the mounted workspace
- **THEN** no commit is created
- **AND** the agent is told the step must be run in a terminal outside the sandbox, and what to run there

#### Scenario: A history-writing command other than commit

- **WHEN** the agent attempts a command that would create a commit without invoking `git commit` — a merge, rebase, cherry-pick, revert, or `git am`
- **THEN** it is blocked in the same way, so the declaration cannot be stepped around by choosing a different command

#### Scenario: Git with a global option before the subcommand

- **WHEN** the agent invokes a declared git subcommand with global options in front of it, such as `git -C some/dir commit`
- **THEN** it is still recognised and blocked

#### Scenario: A staging command that would otherwise fail obscurely

- **WHEN** the agent attempts `git add` or `git stash` in the mounted workspace
- **THEN** it receives the list's explanation rather than an unexplained permission error from the filesystem

#### Scenario: Showing the user what changed

- **WHEN** the agent diffs the working tree and reads the log to summarise its work
- **THEN** both run normally

### Requirement: Each entry states accurately why its command is refused

An entry's explanation SHALL give the actual reason the command is refused. Where a command is refused for more than one reason — because it cannot work here *and* because the sandbox declines it — the explanation SHALL be true of every command the entry matches.

An entry SHALL NOT attribute a refusal to missing credentials or a blocked endpoint when that is not what prevents the command, and SHALL NOT describe a refused command as broken or as having failed.

The list SHALL record, for each group of entries, which mechanism actually enforces it, so that a later reader can tell an entry backed by containment from one the command filter alone would refuse.

#### Scenario: A command that would otherwise succeed

- **WHEN** the agent is stopped attempting a command that no credential or network restriction would have prevented
- **THEN** the explanation it relays gives the real reason
- **AND** does not claim the command failed or that a credential was missing

#### Scenario: A reader auditing the list

- **WHEN** a reader consults the list to determine what actually stops a declared command
- **THEN** each group of entries names the mechanism that enforces it

## MODIFIED Requirements

### Requirement: Host-only commands are declared in one editable list

The sandbox SHALL keep a single list of the commands that cannot work inside it, installed into the container image alongside the egress whitelist. That list SHALL be the only place a command is declared host-only; no other file SHALL carry its own copy of the rules.

Each entry SHALL carry both a pattern that identifies the command and human-readable text stating why the command cannot work in the sandbox and what the user should run on the host instead. The file SHALL support comments and blank lines so entries can be annotated in place.

Extending the sandbox's knowledge of a host-only command SHALL require only adding a line to this list and rebuilding the container.

The list SHALL declare the `wrangler` subcommands that authenticate against, or act on, a Cloudflare account; the git commands that write or publish history; and the `gh` subcommands that authenticate against, or act on, a GitHub account. Subcommands of a listed tool that only read local state SHALL NOT be declared host-only.

#### Scenario: Adding a new host-only command

- **WHEN** the user adds an entry for a command to the list and rebuilds the container
- **THEN** that command is treated as host-only in every subsequent session
- **AND** no other file needed editing for it to take effect

#### Scenario: The list cannot be read

- **WHEN** the list is missing, unreadable, or malformed at the time a command is checked
- **THEN** the sandbox reports the problem loudly rather than silently treating every command as permitted

#### Scenario: A local-only subcommand of a listed tool

- **WHEN** the agent runs a subcommand of a listed tool that neither authenticates, nor contacts a remote endpoint, nor writes the repository — such as `wrangler dev`, `git diff`, or `git log`
- **THEN** the command runs normally and is not treated as host-only

### Requirement: Start-time verification asserts the guard is installed and working

The sandbox's start-time verification SHALL assert that this capability is actually in place, not merely intended, and SHALL fail the launch when it is not. The assertions SHALL cover the list being present and parseable, the enforcement mechanism being installed and activated by configuration outside the mounted workspace, and the session instructions being installed.

Verification SHALL additionally exercise the enforcement rather than only inspecting its configuration: it SHALL confirm that a command known to be on the list is blocked and that an ordinary command is not.

The commands it exercises SHALL include at least one from each family the list is relied upon to declare, so that dropping a whole family from the list fails the launch instead of passing unnoticed.

#### Scenario: Enforcement is not installed

- **WHEN** the enforcement mechanism, the list, or the session instructions are missing at container start
- **THEN** verification reports the failure and the launch fails

#### Scenario: Enforcement is installed but ineffective

- **WHEN** the enforcement mechanism is present but does not block a command known to be on the list
- **THEN** verification reports the failure and the launch fails

#### Scenario: A declared family is dropped from the list

- **WHEN** the entries covering git history commands are removed from the list
- **THEN** verification reports the failure and the launch fails

#### Scenario: Enforcement over-blocks

- **WHEN** the enforcement mechanism blocks an ordinary command that is not on the list
- **THEN** verification reports the failure and the launch fails

#### Scenario: Everything is in place

- **WHEN** the list, the enforcement, and the session instructions are all installed and behave correctly
- **THEN** verification passes this section and the launch proceeds

### Requirement: The agent tells the user what to run outside the sandbox

The instructions in effect for every session SHALL direct the agent to consult the list before proposing or running shell work, to never attempt a declared host-only command, and instead to state to the user that the command must be run in a terminal outside the sandbox.

That statement SHALL name the sandbox restriction as the reason, and SHALL quote the exact command the user needs to run on the host. The agent SHALL NOT present the situation as a failure, a bug, or something to retry, and SHALL NOT substitute a workaround that attempts the same effect by other means without saying it is doing so.

The instructions SHALL further direct the agent not to offer to run a declared command, nor to ask the user for permission to run one. Where the agent would ordinarily propose such a step, it SHALL instead describe the operation it recommends and state that it cannot be performed inside the sandbox.

When the agent nevertheless attempts a listed command and is stopped, it SHALL relay the returned explanation and host-side remedy to the user rather than retrying, rewording, or working around the command.

#### Scenario: Host-only step reached during a task

- **WHEN** completing the user's task requires a declared host-only command
- **THEN** the agent states that this step must be run outside the sandbox, quotes the command verbatim, and gives the sandbox restriction as the reason
- **AND** the agent does not attempt the command

#### Scenario: The agent would otherwise propose the command

- **WHEN** the agent finishes work that would ordinarily end in a declared command, such as a commit
- **THEN** it recommends the operation and states plainly that it is not possible inside the sandbox
- **AND** it does not offer to run it or ask to be allowed to

#### Scenario: The agent is stopped mid-attempt

- **WHEN** the agent attempts a declared host-only command and enforcement stops it
- **THEN** the agent reports to the user what must be run on the host and why
- **AND** does not retry the command, reword it to evade the match, or silently substitute an alternative

#### Scenario: Remaining work continues

- **WHEN** a task contains both host-only steps and steps the sandbox can perform
- **THEN** the agent completes the steps it can and states plainly which steps were left for the user to run on the host
