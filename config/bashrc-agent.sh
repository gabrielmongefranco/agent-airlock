# This file is part of Agent Airlock™
# config/bashrc-agent.sh
# Author(s): Gabriel Mongefranco
# Created: 2026-09-23
# Last Modified: 2026-09-26
# Summary: Shell defaults sourced by every interactive shell inside the agent
#          box: tool paths, Debian command-name aliases, and the local LLM
#          endpoint variables that MCP servers and shell tools read.
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

### Tool Paths ###
case ":${PATH}:" in
    *":${HOME}/.local/bin:"*) ;;
    *) PATH="${HOME}/.local/bin:${HOME}/.npm-global/bin:${PATH}" ;;
esac
export PATH

### Debian Command Names ###
# Debian installs the fd binary as fdfind to avoid a name clash.
command -v fdfind >/dev/null 2>&1 && alias fd='fdfind'

### Local LLM Endpoints ###
# The inference server runs on the host. host.containers.internal is the
# host as seen from inside the container. OPENAI_BASE_URL is deliberately not
# set here, because the Codex CLI would follow it and stop reaching OpenAI.
export LOCAL_LLM_BASE_URL="${LOCAL_LLM_BASE_URL:-http://host.containers.internal:8080/v1}"
export OLLAMA_HOST="${OLLAMA_HOST:-http://host.containers.internal:11434}"
