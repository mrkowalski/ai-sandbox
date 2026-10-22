# Spec Delta

## ADDED Requirements

### Requirement: The firewall policy comes only from the host-resolved mount

The firewall SHALL read its whitelist and host-network flag from a fixed path that the launcher mounts read-only from host state outside the workspace. The image SHALL carry no whitelist of its own, so a container started without that mount SHALL stop at start rather than run with a guessed policy.

#### Scenario: Policy provenance

- **WHEN** the container is running
- **THEN** the policy the firewall loaded is not writable from inside the container and does not live in the workspace

#### Scenario: Launched without the launcher

- **WHEN** the container is started by a bare `devcontainer up` that supplies no policy mount
- **THEN** firewall installation aborts on the unreadable whitelist, the container stops, and the log names the missing policy

### Requirement: Docker-host network access is opt-in

The firewall SHALL NOT accept traffic to or from the Docker host's network unless the resolved config sets `host-network = on`. Loopback and DNS SHALL stay allowed either way.

#### Scenario: Default

- **WHEN** a project's config does not set `host-network`
- **THEN** a connection from inside the container to a service listening on the Docker host's gateway address is rejected

#### Scenario: Local model server

- **WHEN** a project sets `host-network = on`
- **THEN** a connection to a service on the Docker host's network succeeds, and every other non-whitelisted host stays blocked

### Requirement: Blocked-host probes never use an allowed host

Verification's must-be-blocked probes SHALL skip any host present in the effective whitelist and use another known non-whitelisted host instead. It SHALL fail if no candidate remains.

#### Scenario: Project allows a default probe host

- **WHEN** a project's config has `allow = example.com`
- **THEN** verification does not report example.com as an egress leak, and still proves egress is blocked using a host that is not allowed
