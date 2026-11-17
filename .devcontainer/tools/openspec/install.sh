#!/bin/bash
#
# install.sh (openspec) - OpenSpec, into the npm prefix. Runs as node at image
# build.

set -euo pipefail

npm install -g @fission-ai/openspec@latest
