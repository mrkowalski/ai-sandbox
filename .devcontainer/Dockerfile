ARG UV_VERSION=0.9.0

# Named stage so the version can come from an ARG; COPY --from cannot expand one.
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM node:24-trixie-slim

ARG PYTHON_VERSION=3.13

RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  wget \
  curl \
  ca-certificates \
  && update-ca-certificates && apt-get clean && rm -rf /var/lib/apt/lists/*

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

ARG USERNAME=node

# Persist bash history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory \
  && echo "$SNIPPET" >> /home/$USERNAME/.bashrc \
  && chown $USERNAME:$USERNAME /home/$USERNAME/.bashrc

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# /workspace gets overriden by the devcontainer. ~/.npm is a volume mount point;
# pre-created so the first mount inherits node's ownership.
RUN mkdir -p /workspace /home/node/.npm && \
  chown -R node:node /workspace /home/node/.npm

WORKDIR /workspace

USER node

# Install global packages. Bundle scripts (/usr/local/share/sbx/bin) come first
# on PATH so a bundle wrapper wins over the binary it wraps.
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=/usr/local/share/sbx/bin:$PATH:/usr/local/share/npm-global/bin

ENV EDITOR=vim
ENV VISUAL=vim

# OpenSpec telemetry
ENV OPENSPEC_TELEMETRY=0

RUN npm install -g @fission-ai/openspec@latest

COPY init-firewall.sh /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/
COPY verify.sh /usr/local/bin/
COPY host-only-check /usr/local/bin/
COPY host-only-commands.txt /usr/local/etc/

# The agent-neutral sandbox policy, on the read-only rootfs and outside the
# workspace. Each agent bundle points its agent at it (or copies it where the
# agent looks), so no project can switch it off.
COPY sandbox-policy.md /etc/sbx/sandbox-policy.md
USER root

# uv and a uv-managed Python, baked into the read-only rootfs. Interpreter
# downloads come from GitHub, which the firewall blocks, so runtime downloads
# are switched off (ENV below): a missing version then fails with a plain
# "no interpreter" error instead of a network timeout. The cache is a volume
# (devcontainer.json); the directory is pre-created so the first mount
# inherits node's ownership. UV_LINK_MODE=copy because a project .venv sits on
# the workspace bind mount, a different filesystem from the cache, where
# hardlinking fails with a warning on every install.
COPY --from=uv /uv /uvx /usr/local/bin/
ENV UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python \
    UV_PYTHON_BIN_DIR=/usr/local/bin
RUN UV_CACHE_DIR=/root/.cache/uv-build uv python install "$PYTHON_VERSION" && \
    ln -sf "$(uv python find "$PYTHON_VERSION")" /usr/local/bin/python3 && \
    ln -sf python3 /usr/local/bin/python && \
    rm -rf /root/.cache/uv-build && \
    chmod -R a+rX /usr/local/share/uv && \
    mkdir -p /home/node/.cache/uv && \
    chown -R node:node /home/node/.cache
ENV UV_PYTHON_DOWNLOADS=never \
    UV_PYTHON_PREFERENCE=only-managed \
    UV_CACHE_DIR=/home/node/.cache/uv \
    UV_LINK_MODE=copy

# Login shells reset PATH in /etc/profile, so the ENV PATH above is restated.
#
# /usr/local/etc/sbx is an empty mount point: the image carries no whitelist.
# The launcher binds the host-resolved policy (allowed-domains.txt,
# firewall.conf) over it read-only; a launch without that bind aborts firewall
# installation on the unreadable whitelist, and the container stops.
RUN echo 'export PATH="/usr/local/share/sbx/bin:$PATH:/usr/local/share/npm-global/bin"' \
      > /etc/profile.d/npm-global-path.sh && \
    chmod 0644 /etc/profile.d/npm-global-path.sh && \
    chmod 0644 /usr/local/etc/host-only-commands.txt && \
    chmod 0644 /etc/sbx/sandbox-policy.md && \
    mkdir -p /usr/local/etc/sbx && \
    chmod +x /usr/local/bin/host-only-check && \
    chmod +x /usr/local/bin/init-firewall.sh && \
    chmod +x /usr/local/bin/entrypoint.sh && \
    chmod +x /usr/local/bin/verify.sh && \
    echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
    echo "node ALL=(root) NOPASSWD: /usr/local/bin/verify.sh" > /etc/sudoers.d/verify && \
    chmod 0440 /etc/sudoers.d/node-firewall && \
    chmod 0440 /etc/sudoers.d/verify

# Interactive shells (`sbx bash`) load each installed bundle's shell.sh.
# Appended after Debian's non-interactive early return, so `sbx <cmd>` and ACP
# never see these; bundle wrappers in bin/ are what applies there.
RUN printf '%s\n' \
      '' \
      '# sbx tool bundles' \
      'if [ -r /usr/local/share/sbx/tools.list ]; then' \
      '  while IFS= read -r _sbx_tool; do' \
      '    if [ -r "/usr/local/share/sbx/tools/$_sbx_tool/shell.sh" ]; then' \
      '      . "/usr/local/share/sbx/tools/$_sbx_tool/shell.sh"' \
      '    fi' \
      '  done < /usr/local/share/sbx/tools.list' \
      '  unset _sbx_tool' \
      'fi' >> /etc/bash.bashrc

# Tool bundles (tools/<name>/), selected by the launcher through TOOLS. The
# base command snapshot is taken before TOOLS is in scope, so every layer above
# it is shared by every tool combination. See install-tools.sh for what a
# bundle may install and what fails the build.
COPY install-tools.sh /usr/local/share/sbx/install-tools.sh
RUN bash /usr/local/share/sbx/install-tools.sh snapshot
ARG TOOLS=
COPY tools/ /usr/local/share/sbx/tools/
USER node
RUN bash /usr/local/share/sbx/install-tools.sh user $TOOLS
USER root
RUN bash /usr/local/share/sbx/install-tools.sh root $TOOLS

# The enforcement point. An image ENTRYPOINT runs on every container start -
# `docker start` and a post-reboot restart included - which is what postStartCommand
# cannot do, since iptables state does not survive a stop/start. It installs the
# firewall, verifies the ruleset offline, and only then execs the container command;
# a failure never reaches the exec, so the container stops instead of running open.
# Exec form on purpose: no shell in between to mangle the composed arguments.
# It needs no sudoers entry of its own - it reuses the two granted just above.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# The keep-alive the entrypoint execs, and the other half of devcontainer.json's
# "overrideCommand": false. With the override off the CLI supplies no command,
# so "$@" falls through to the image CMD - and the base image's is `node`, a
# REPL that exits immediately without a TTY and stops the container. This has to
# exist for the container to stay up at all.
#
# The `sleep 1 &` + `wait` idiom is the point of the loop, not decoration. PID 1
# ignores signals it has no handler for, so a plain `sleep infinity` would sit
# out `docker stop`'s SIGTERM and be SIGKILLed ten seconds later on every stop.
# `wait` is interruptible, so the trap runs immediately and the container exits
# 0. This is the same shape as the devcontainer CLI's own shim, minus its
# `exec "$@"` - which is what lets verify.sh tell the two apart.
CMD ["/bin/sh", "-c", "echo 'sandbox keep-alive (image CMD)'; trap 'exit 0' TERM INT; while sleep 1 & wait $!; do :; done"]

USER node
