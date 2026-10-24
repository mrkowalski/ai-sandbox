#!/bin/bash
#
# install-root.sh (claude) - Claude Code's managed policy, on the read-only
# rootfs and outside the workspace, so the guard hook, bypass mode and the
# sandbox policy apply to whichever project is mounted and cannot be switched
# off from inside it. Runs as root at image build, from the bundle directory.

set -euo pipefail

install -d -m 0755 /etc/claude-code
install -m 0644 managed-settings.json /etc/claude-code/managed-settings.json
install -m 0755 host-only-guard.sh /etc/claude-code/host-only-guard.sh
install -m 0644 /etc/sbx/sandbox-policy.md /etc/claude-code/CLAUDE.md
