#!/bin/bash
#
# install.sh (opencode) - opencode, into the npm prefix. Runs as node at
# image build.

set -euo pipefail

npm install -g opencode-ai@latest
