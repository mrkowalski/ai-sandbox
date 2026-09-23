# Claude Code headless sandbox

## What is it?

It is a sandbox Docker dev container that restricts Claude Code's access to the current folder and applies firewall whitelisting.

It is loosely based on https://github.com/anthropics/claude-code/tree/main/.devcontainer

It is a headless sandbox; it contains no human-facing features. It restricts what Claude Code can do and makes cost the only risk of the `--dangerously-skip-permissions` flag.

### Crucially, it:

- cannot modify the project's git repository: `.git` is bind-mounted read-only. `git push` is impossible too: there is no SSH key, no credential helper, and no egress
- mounts the container fs as readonly except for volumes and tmps
- disables outbound network traffic for everything except for entries in `.devcontainer/allowed-domains.txt`

## Running

### Install devcontainers

```bash
npm install -g @devcontainers/cli
```

### Clone the repo into a homedir folder (tools)

```bash
git clone https://github.com/mrkowalski/sandbox ~/tools/sandbox
```

### Put into your `.bashrc`:

```bash
# ~/.bashrc
SBX=~/tools/sandbox/.devcontainer/devcontainer.json
source ~/tools/sandbox/sbx-env.sh   # defines sbx_slug / sbx_tag_image

sbx-up() {
    SBX_SLUG=$(sbx_slug) || return 1
    export SBX_SLUG
    devcontainer up --workspace-folder "$PWD" --config "$SBX" --remove-existing-container || return 1
    sbx_tag_image
}
sbx-claude(){ devcontainer exec --workspace-folder "$PWD" --config "$SBX" claude --dangerously-skip-permissions; }
sbx-resume(){ devcontainer exec --workspace-folder "$PWD" --config "$SBX" claude --dangerously-skip-permissions --resume; }
```

### ACP

`sbx-acp.sh` exposes the sandboxed Claude Code as an ACP agent server.

Unlike `sbx-up`, the script does not pass `--remove-existing-container`: doing so would kill a live ACP container every time a second editor session opened. A container created before the volume naming last changed is therefore reused as it stands, old volume names and all - and nothing announces it, because `verify.sh` is the thing that would and nothing runs it at start. The symptom is a Claude Code that has forgotten its credentials. Recreate the container once, from the project folder:

```bash
sbx-up   # or, without the .bashrc functions:
docker rm -f "$(docker ps -aq --filter label=devcontainer.local_folder=$PWD)"
```

## The firewall

The firewall is installed by the image entrypoint. If the firewall cannot be installed - most often a hostname in `allowed-domains.txt` that will not resolve - the container stops, and `docker logs` says why. If you need a shell inside an image whose container will not start, bypass the entrypoint from the host:

```bash
docker run --rm -it --entrypoint /bin/bash <image>   # no firewall installed
```

## Commands that must run outside the sandbox

Some commands cannot work in the sandbox: they authenticate against, or act on, an account whose credentials live on the host, or over an API the firewall does not allow. `npx wrangler login` is the example. Credentials do not propagate into the sandbox.

`.devcontainer/host-only-commands.txt` is the list of those commands. When Claude Code hits one it says so and hands the exact command to run in a terminal, instead of trying to run it. If it tries anyway, a guard blocks the command before it executes and gives it the same message.

To add one, add a line to that file and rebuild:

```
<pattern>  ::  <what the user should be told>
```

`<pattern>` is a POSIX ERE matched against the start of each command in the line the agent submitted, after `npx`-style runners are stripped - so a pattern reading `wrangler ... deploy` also catches `cd app && npx wrangler deploy`. The file's header documents the format and the normalization in full.

If a pattern turns out to be too broad, you do not need a rebuild to get past it - prefix the command with the bypass, which applies to that one invocation:

```bash
HOST_ONLY_GUARD_BYPASS=1 npx wrangler deploy
```

## Maintenance

### Container volumes

Each project gets three named volumes - bash history, Claude Code config, and an npm cache - named after the workspace path it was launched from, followed by the dev container id. Launching in `/home/marcin/tools/sandbox` produces:

```
claude-code-bashhistory-home-marcin-tools-sandbox-<devcontainerId>
claude-code-config-home-marcin-tools-sandbox-<devcontainerId>
claude-code-npm-home-marcin-tools-sandbox-<devcontainerId>
```

The slug is the absolute path with the leading `/` stripped, lowercased, and every character outside `[a-z0-9_.-]` replaced by `-`; `sbx_slug` in `sbx-env.sh` is the one definition of it. It leads the name so a project's volumes sort together; the `${devcontainerId}` hash trails it and is what actually keeps two projects apart, whichever launcher was used. The image is tagged from the slug alone, as `sbx-<slug>`, so one project's image and volumes filter together.

The npm cache volume is what makes `npm install` and `npx` work against the read-only rootfs, and npm never prunes it. To reclaim the space, either run `npm cache clean --force` inside the container, or remove the volume from the host:

```bash
docker volume ls | grep home-marcin-tools-sandbox   # one project's volumes
docker volume ls | grep claude-code-npm             # every project's npm caches
docker volume rm <volume-name>                      # container must be stopped
docker images   | grep '^sbx-'                      # the matching image tags
```

Removing a project's `claude-code-config-*` volume discards its Claude Code credentials and session history, so `sbx-resume` starts from nothing there; the other two cost only a re-download and a lost shell history.

### OpenSpec maintenance

Run `openspec update` after bumping the npm package, it regenerates `.claude/skills` and prunes anything deselected, so public tree doesn't accumulate stale command files.
