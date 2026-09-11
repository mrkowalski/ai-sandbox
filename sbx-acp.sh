#!/bin/bash

SBX=~/tools/sandbox/.devcontainer/devcontainer.json
exec 2>>/tmp/sbx-acp.log
devcontainer up --workspace-folder "$PWD" --config "$SBX" >>/tmp/sbx-acp.log
exec devcontainer exec --workspace-folder "$PWD" --config "$SBX" claude-agent-acp
