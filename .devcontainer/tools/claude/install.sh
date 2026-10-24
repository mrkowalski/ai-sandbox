#!/bin/bash
#
# install.sh (claude) - Claude Code and its ACP server, into the npm prefix.
# Runs as node at image build.

set -euo pipefail

npm install -g @anthropic-ai/claude-code@latest
npm install -g @agentclientprotocol/claude-agent-acp@latest
