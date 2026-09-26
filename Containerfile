# This file is part of Agent Airlock™
# Containerfile
# Author(s): Gabriel Mongefranco
# Created: 2026-09-23
# Last Modified: 2026-09-26
# Summary: Builds the Agent Airlock image: a Debian container that holds the
#          coding agents, their toolchains, Playwright, and optionally VS Code,
#          so that nothing an agent installs or runs touches the host system.
# Notes: See README file for documentation and full license information.
#
# Copyright © 2026 Gabriel Mongefranco
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program. If not, see <https://www.gnu.org/licenses/>.

### Base Image ###
# Debian is used instead of the host distribution because Playwright's
# dependency installer only understands apt-based systems.
ARG DEBIAN_RELEASE=trixie
FROM docker.io/library/debian:${DEBIAN_RELEASE}-slim

# WITH_GUI=1 adds a full VS Code install so the editor itself can run inside
# the container over the host's Wayland socket (Linux hosts only).
ARG WITH_GUI=0
# The in-container user id. The launcher maps the host user onto it with
# --userns=keep-id so files written under ~/git keep the host user's ownership.
ARG AGENT_UID=1000
ARG AGENT_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

### Base Toolchain ###
# Language-agnostic tools plus the interpreters used across the projects this
# box serves: Node, Python, Go, and Lua. Rust is deliberately absent; it is
# large and only some projects need it, so agents install it per box.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg \
        git gh openssh-client \
        sudo locales tzdata \
        build-essential pkg-config make cmake \
        python3 python3-pip python3-venv pipx \
        nodejs npm \
        golang-go \
        lua5.4 liblua5.4-dev luarocks \
        jq ripgrep fd-find tree htop less procps file unzip zip xz-utils \
        nano shellcheck sqlite3 \
        bubblewrap socat \
        fonts-dejavu-core fonts-liberation \
    && rm -rf /var/lib/apt/lists/*

### Optional Desktop VS Code ###
# Installed from Microsoft's apt repository only when WITH_GUI=1. The package
# pulls in its own GTK and audio dependencies.
RUN if [ "${WITH_GUI}" = "1" ]; then \
        curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
            | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg \
        && echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
            > /etc/apt/sources.list.d/vscode.list \
        && apt-get update && apt-get install -y --no-install-recommends code \
        && rm -rf /var/lib/apt/lists/* ; \
    fi

### Agent User ###
# Passwordless sudo is safe here because root inside the container is still
# the unprivileged host user outside of it, and apt changes stay in the image.
RUN groupadd -g "${AGENT_GID}" agent \
    && useradd -m -u "${AGENT_UID}" -g "${AGENT_GID}" -s /bin/bash agent \
    && echo 'agent ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/agent \
    && chmod 0440 /etc/sudoers.d/agent

### Playwright Browsers ###
# Installed at build time into a shared path owned by the agent user, so a
# project's own Playwright version can add browsers without leaving the
# workspace-write sandboxes the agents run under.
RUN mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}" \
    && npx -y playwright install --with-deps chromium \
    && chown -R agent:agent "${PLAYWRIGHT_BROWSERS_PATH}" \
    && rm -rf /root/.npm /var/lib/apt/lists/*

### Entrypoint ###
COPY --chmod=0755 entrypoint.sh /usr/local/bin/airlock-entrypoint

### Agent-Level Tools ###
# Everything below lives in /home/agent, which the launcher mounts as a named
# volume. The first start copies this image content into the volume; after
# that the tools update themselves inside the volume.
USER agent
WORKDIR /home/agent
ENV PATH=/home/agent/.local/bin:/home/agent/.npm-global/bin:${PATH} \
    NPM_CONFIG_PREFIX=/home/agent/.npm-global \
    XDG_RUNTIME_DIR=/tmp/agent-runtime

RUN mkdir -p "${HOME}/.npm-global" "${HOME}/.local/bin" "${HOME}/git" \
        "${HOME}/.claude" "${HOME}/.codex" \
    && npm install -g @openai/codex @anthropic-ai/sandbox-runtime @playwright/mcp \
    && curl -fsSL https://claude.ai/install.sh | bash \
    && pipx install uv \
    && rm -rf "${HOME}/.npm/_cacache"

# Default agent configuration. These land in the home volume on first start
# and are never overwritten by later image builds.
COPY --chown=agent:agent config/claude-settings.json /home/agent/.claude/settings.json
COPY --chown=agent:agent config/codex-config.toml /home/agent/.codex/config.toml
COPY --chown=agent:agent config/bashrc-agent.sh /home/agent/.bashrc.d/airlock.sh
RUN printf '\n# Airlock shell defaults\nfor f in ~/.bashrc.d/*.sh; do [ -r "$f" ] && . "$f"; done\n' >> "${HOME}/.bashrc"

ENTRYPOINT ["/usr/local/bin/airlock-entrypoint"]
CMD ["sleep", "infinity"]
