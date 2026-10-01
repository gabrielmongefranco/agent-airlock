<!--
This file is part of Agent Airlock™
Copyright © 2026 Gabriel Mongefranco
Licensed under the GNU Free Documentation License v1.3 or later.
See <https://www.gnu.org/licenses/fdl-1.3.html>. See README for full license information.
-->

# Agent Airlock™

You are running inside Agent Airlock, a rootless podman container. The container is the security boundary between you and the rest of the user's computer. It shares one host folder, the user's `~/git`, which is `/home/agent/git` here. When the user gives a host path such as `/home/<name>/git/<repo>`, use `/home/agent/git/<repo>`.

## Files and git

- Every folder under `/home/agent/git` is part of your workspace, whichever folder this session started in. Change other repositories only when the task needs it.
- The user browses these folders on the host while you work. To start a branch, run `git fetch`, then `git switch --no-track -c <new-branch> origin/<default-branch>`. Checking out an outdated local default branch and then pulling deletes folders and creates them again, and the host file manager loses track of them.
- Do not edit Claude Code's settings files to get around the limits below. Tell the user what you need instead.

## Servers and network

- Each Bash command runs in its own network namespace with its own loopback. A server started in one command can't be reached from later commands, the editor, or the host browser. Servers the user starts in the editor terminal can't be reached from your commands either. Start a server, run its checks, and stop it in the same command.
- Bash commands can't use Unix-domain sockets. Run servers on TCP at `127.0.0.1`, and connect to `127.0.0.1` rather than `localhost`, which MySQL and MariaDB clients treat as a request for the socket. Start MariaDB with `--socket=` and `--bind-address=127.0.0.1`.
- The commands listed under `sandbox.excludedCommands` in `~/.claude/settings.json` run outside these limits. Ports 4000 to 4010 are published to the host's `localhost` by default, so a server started that way on one of them can be opened in the host browser.
- `sudo` fails inside the sandbox. Installing a package with `sudo apt-get` needs a command run outside the sandbox, which the user approves.
- The host's local model server is at `$LOCAL_LLM_BASE_URL` (OpenAI-style API) and `$OLLAMA_HOST` (Ollama API).
