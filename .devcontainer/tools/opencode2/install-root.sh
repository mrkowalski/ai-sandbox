#!/bin/bash
#
# install-root.sh (opencode2) - opencode v2's baked config dir and ripgrep.
# Runs as root at image build, from the bundle directory.
#
# ripgrep: opencode downloads rg from github.com unless one is on PATH, and
# github.com is not whitelisted.
#
# service.json: the TUI talks to a background server (`opencode2 serve
# --service`, 127.0.0.1 inside the container). Without a password in
# <config dir>/service.json it generates one and writes it there, which fails
# with EROFS on the read-only config dir and stops the TUI. So the password is
# baked. It is not a secret: every process that could reach that port runs as
# node in this container, and could read a generated one just as well.

set -euo pipefail

apt-get update
apt-get install -y --no-install-recommends ripgrep
apt-get clean
rm -rf /var/lib/apt/lists/*

install -d -m 0755 /etc/sbx/opencode2 /etc/sbx/opencode2/plugin
install -m 0644 opencode.json /etc/sbx/opencode2/opencode.json
install -m 0644 service.json /etc/sbx/opencode2/service.json
install -m 0644 host-only-guard.js /etc/sbx/opencode2/plugin/host-only-guard.js
