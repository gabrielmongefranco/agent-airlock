#!/usr/bin/env bash
# This file is part of Agent Airlock™
# entrypoint.sh
# Author(s): Gabriel Mongefranco
# Created: 2026-09-23
# Last Modified: 2026-09-26
# Summary: Container entrypoint. Creates the per-session runtime directory
#          that Wayland clients and Chromium expect, then runs the container
#          command (by default an idle sleep that keeps the box up).
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

set -euo pipefail

### Prepare Runtime Directory ###
# XDG_RUNTIME_DIR is set in the image. It must exist, be owned by the agent
# user, and be private, or Wayland clients refuse to start.
runtime_dir="${XDG_RUNTIME_DIR:-/tmp/agent-runtime}"
mkdir -p "${runtime_dir}"
chmod 0700 "${runtime_dir}"

### Run Container Command ###
exec "$@"
