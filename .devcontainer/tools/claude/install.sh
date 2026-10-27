#!/bin/bash
#
# install.sh (claude) - Claude Code and its ACP server, into the npm prefix.
# Runs as node at image build.
#
# claude-code's bin/claude.exe is a placeholder stub; its postinstall
# (install.cjs) links the platform's native binary, already installed as an
# optional dependency, over it. Newer npm gates install scripts behind
# allowScripts, and install.cjs exits 0 leaving the stub when the native
# package is missing. So the postinstall is run here explicitly, and the build
# fails unless `claude --version` reports the installed package version.

set -euo pipefail

npm install -g --ignore-scripts @anthropic-ai/claude-code@latest

pkg="$(npm root -g)/@anthropic-ai/claude-code"
(cd "$pkg" && node ./install.cjs)

want="$(node -p "require('$pkg/package.json').version")"
got="$("$pkg/bin/claude.exe" --version 2>&1)" || got="exit $?: $got"
if [ "$got" != "$want (Claude Code)" ]; then
  printf 'install.sh (claude): bin/claude.exe is not the native %s binary: %s\n' "$want" "$got" >&2
  exit 1
fi

npm install -g @agentclientprotocol/claude-agent-acp@latest
