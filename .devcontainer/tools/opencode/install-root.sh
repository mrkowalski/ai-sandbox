#!/bin/bash
#
# install-root.sh (opencode) - opencode's baked config dir and ripgrep. Runs as
# root at image build, from the bundle directory.
#
# ripgrep: opencode downloads rg from github.com unless one is on PATH, and
# github.com is not whitelisted.

set -euo pipefail

apt-get update
apt-get install -y --no-install-recommends ripgrep
apt-get clean
rm -rf /var/lib/apt/lists/*

install -d -m 0755 /etc/sbx/opencode /etc/sbx/opencode/plugin
install -m 0644 opencode.json /etc/sbx/opencode/opencode.json
install -m 0644 host-only-guard.js /etc/sbx/opencode/plugin/host-only-guard.js

# opencode writes a .gitignore into each config dir when it is missing and
# tolerates EACCES but not EROFS, so on the read-only rootfs it must already
# exist or the server fails to start. Only its existence is checked.
printf '%s\n' node_modules package.json package-lock.json bun.lock .gitignore \
  > /etc/sbx/opencode/.gitignore
chmod 0644 /etc/sbx/opencode/.gitignore
