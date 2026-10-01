<!--
This file is part of Agent Airlock™
docs/implementation-plan.md
Author(s): Gabriel Mongefranco
Created: 2026-09-23
Last Modified: 2026-10-01
Summary: Phased plan for bringing up the airlock on Fedora first, then
         Windows through WSL2, then macOS, with a verification checklist per
         phase and the decisions still open.
Notes: See README file for documentation and full license information.

Copyright © 2026 Gabriel Mongefranco

Licensed under the GNU Free Documentation License v1.3 or later.
See <https://www.gnu.org/licenses/fdl-1.3.html>. See README for full license information.

-->

# Agent Airlock™

## Implementation Plan

[← Back to README](../README.md)

This plan takes the launcher and image from untested files to a daily-use setup, one phase at a time. Each phase ends with a checklist you run by hand before starting the next. The files were written and linted but never run against a real podman, so Phase 1 is where the first real evidence appears. Linux comes first, Windows second, and macOS last.


### Overview

Phases 1 to 4 give you the full setup on Fedora and prove the three workflows that matter. Phase 5 adds Windows, Phase 6 the Mac, and Phase 7 turns the folder into a repository.

Files in this folder:

| File | Purpose |
|---|---|
| `airlock` | Launcher: install, build, up, down, shell, vscode (with the code and open shorthands), attach, login, update, snapshot, status, doctor, reset, uninstall. |
| `Containerfile` | Debian image with the toolchains, Playwright, the agent CLIs, and optional VS Code. |
| `entrypoint.sh` | Creates the runtime directory Wayland clients need, then idles. |
| `config/claude-settings.json` | Default Claude Code settings inside the airlock (nested sandbox with its filesystem layer off, all of `~/git` as the workspace, excluded commands, domain allowlist). |
| `config/claude-airlock-rules.md` | Instructions Claude Code loads in every session inside the airlock: the workspace, servers and ports, `sudo`, and local models. |
| `config/codex-config.toml` | Default Codex settings inside the airlock (no inner sandbox, because it cannot start in the container; Playwright MCP). |
| `config/bashrc-agent.sh` | Shell defaults inside the airlock. |
| `config/env.example` | Optional API keys and endpoint overrides for the launcher. |
| `config/vscode-host-settings.jsonc` | Settings to merge into the host VS Code for the attach fallback. |
| `config/vscode-container-settings.jsonc` | Default user settings for the VS Code inside the airlock (Workspace Trust off). |

The launcher records whether a container was started with `--gui` as a container label, so `airlock code` can refuse to run against a container that has no display.


### Phase 1: Fedora, first start

#### Steps
1. Clone the repository somewhere stable, for example `~/git/agent-airlock`, and run `bash ./airlock install --gui` in it. Install offers to add podman if it is missing, links `airlock` into `~/.local/bin`, runs the doctor host check, and builds the image. Expect a long first build: apt packages, Playwright's Chromium, VS Code, the Codex npm package, and the Claude Code installer.
2. Run `airlock up --gui`. On Fedora it offers the one-time SELinux relabel of `~/git`. Accept it.
3. Run `airlock shell` and check the basics: `whoami` (agent), `id -u` (1000), `ls ~/git`, `touch ~/git/airlock-test && ls -l ~/git/airlock-test` (owned by you on the host), then remove the file.

#### Checklist
- `podman ps` shows `airlock` running.
- Inside the airlock, `ls /home` shows only `agent`, and `ls /run/host` fails.
- Inside the airlock, `curl http://host.containers.internal:8080/v1/models` lists the llama-swap models and `curl http://host.containers.internal:11434/v1/models` answers.
- Inside the airlock, `node --version`, `python3 --version`, `go version`, `lua5.4 -v`, `gh --version`, `claude --version`, `codex --version`, and `npx playwright --version` all print.
- On the host, `~/git` files still open normally in Dolphin and in the host git.

#### Verification notes
Two things in this phase were not verified in advance and may need a fix on first contact. The Debian package names in the Containerfile (`gh`, `golang-go`, `lua5.4`, `pipx`, `fd-find`) are believed correct for Debian 13; a missing package fails the build with its name, so correct and rebuild. Playwright's `--with-deps` must recognize Debian 13; if it refuses, pin `DEBIAN_RELEASE=bookworm` as a build argument.


### Phase 2: editor inside the container, logins, MCP

#### Steps
1. Run `airlock code ~/git/<repo>`. A VS Code window opens from inside the container.
2. Install the Claude Code and Codex extensions in that window. They land in the airlock's own VS Code.
3. Run `airlock login claude` and `airlock login codex` from a host terminal. Open each printed URL in the host browser.
4. Run `airlock login gh` with a fine-grained token limited to the repositories the agents work on. Keep your own `gh` login on the host untouched.
5. Register the Playwright MCP server with Claude Code inside the airlock: `claude mcp add --scope user playwright -- npx -y @playwright/mcp@latest`. Codex already has it from `config/codex-config.toml`.

#### Checklist
- The window renders under Plasma with working clipboard and correct scaling. If scaling is wrong, set `AIRLOCK_CODE_ARGS="--disable-gpu --force-device-scale-factor=2"` (or your factor).
- If VS Code reports a Chromium sandbox error, add `--no-sandbox` to `AIRLOCK_CODE_ARGS`. That flag concerns Chromium's renderer sandbox, not the container.
- Both extensions show as signed in without a second login, because they read the CLI credential stores. The Codex extension's login callback, if it asks, arrives on port 1455.
- In Claude Code, `/sandbox` shows the sandbox enabled and no Dependencies tab. Ask it to run `curl -sS -m 10 https://example.com`; the sandbox refuses the host or asks you first. Ask it to run `ls -la` in a repository; no empty dotfiles such as `.bashrc` appear.
- Ask Claude Code to run `ls /home/<your host user>`; it fails, because that directory does not exist in the airlock.
- `codex` starts and reports `danger-full-access` as its sandbox mode. Codex's own sandbox cannot start in a rootless container, because bubblewrap may not mount a fresh `/proc` there, so the container is Codex's boundary.
- Signing in to GitHub from the editor (for Copilot) opens the in-container Firefox and the redirect returns to the editor.
- Closing and reopening the window keeps the logins.


### Phase 3: workflow verification

#### Field Station AI
1. Open the Field Station repo.
2. From the editor terminal, run `zippyserve` (build it inside the airlock first with `go install` or `go build`) on a port in the published range 4000 to 4010, in the repo directory. Open it in the host browser. WebGPU inference runs in the host browser as before.
3. Ask Claude Code to start zippyserve itself. It should run without a sandbox prompt because the command is in `excludedCommands` and allowed in `permissions.allow`.
4. Ask Claude Code to take a screenshot of the page with Playwright and read it back. For headed mode, `headless: false` with the Chromium argument `--ozone-platform=wayland` puts the browser on your desktop.

#### PeerFoil
1. Run a PeerFoil session where Claude Code calls Codex through the Codex MCP server.
2. Point PeerFoil's local-model tool at `LOCAL_LLM_BASE_URL` and confirm a local review round completes.

#### Extractium
1. Inside the airlock, install the Rust toolchain with rustup as the agent user. It lands in the home volume.
2. Build a Linux release and run it from `/home/agent/tmp`, outside the git tree, which matches the manual test habit without touching the host.
3. Try a cross-compile target the project uses (mingw-w64 via `sudo apt install mingw-w64`, or cargo-xwin). Windows binaries are tested on the Windows machine.
4. Have the agent open a branch and a pull request with the airlock's `gh` login. Merge on the host, as before.

#### Checklist
- Both server paths (terminal and agent) reach the host browser on `localhost`.
- The agent's Playwright screenshot shows the served page.
- A PeerFoil round with Codex and a local model completes without any host-side tool.
- Extractium builds and runs inside the airlock, and nothing new appeared on the host outside `~/git`.


### Phase 4: attach fallback on Fedora

#### Steps
1. Merge `config/vscode-host-settings.jsonc` into the host VS Code user settings and install the Dev Containers extension on the host.
2. Run `airlock open ~/git/<repo>`. The host VS Code opens a window attached to the running container.
3. If the URI form is rejected, use `airlock attach` for the manual steps and record the working URI form in the launcher.

#### Checklist
- The attached window shows the extensions under the container, not under Local, and the same logins work.
- A dev server started in the attached window appears in the Ports panel and opens in the host browser.
- The same container serves both transports; switching between `airlock code` and `airlock open` needs no restart.


### Phase 5: Windows through WSL2

#### Steps
1. In a WSL2 distro (Ubuntu or Fedora), enable systemd in `/etc/wsl.conf`, install `podman`, and keep `~/git` inside the distro's filesystem, never under `/mnt/c`.
2. Copy the folder into the distro and run `airlock doctor`. It prints the WSL gateway address and the two variables to set if the LLM server runs on Windows under NAT networking. Under mirrored networking (`networkingMode=mirrored` in `.wslconfig`) the defaults already reach the Windows loopback.
3. Run `airlock build --gui` and `airlock up --gui`. The launcher resolves WSLg's Wayland socket symlink before mounting it.
4. Run `airlock code ~/git/<repo>`. The window appears on the Windows desktop through WSLg.
5. For the attach fallback, open a Remote-WSL window in the Windows VS Code, set `dev.containers.executeInWSL` to `true` and `dev.containers.executeInWSLDistro` to the distro name, then use `airlock open` from a distro terminal or attach by hand.

#### Checklist
- The container inside the distro passes the Phase 1 checklist unchanged.
- A dev server on a published port opens in a Windows browser at `localhost`.
- The Codex login callback on port 1455 reaches the airlock from a Windows browser.
- With the hardened `wsl.conf` from the earlier exploration (`automount` and `interop` off), WSLg still provides the Wayland socket and `airlock code` still opens a window. If it does not, record which setting breaks it.
- Windows-side LLM endpoints are reachable at the address `airlock doctor` printed.


### Phase 6: macOS

#### Steps
1. `brew install podman && podman machine init --now`.
2. Run `airlock build` and `airlock up` (no `--gui`; macOS has no Wayland display). The launcher skips the pasta flags and the relabel on macOS.
3. Use `airlock open ~/git/<repo>` for the editor.

#### Checklist
- `host.containers.internal:8080` reaches a llama-server on the Mac. If it hangs, bind llama-server to `0.0.0.0` and let the macOS firewall block outside access, then record the result here.
- Files written under `~/git` from the airlock keep the Mac user's ownership through the virtiofs mount.
- The Codex login callback works through podman machine's port publishing.


### Phase 7: repository packaging

#### Steps
1. Initialize the repository from the personal repo template as `agent-airlock`, and copy these files in. The placeholders are already filled with the project name.
2. Add `docs/README.md` linking `architecture.md` and this plan, and a short root `README.md` quick start (`doctor`, `build --gui`, `up --gui`, `code`, `login`) with the slogan.
3. Link the repository from PeerFoil issue #4 as the recommended machine setup, and from the Windows exploration document as the container layer inside its Tier 2 distro.

#### Placement decision
This belongs in its own repository. PeerFoil states that it recommends and detects a sandbox but does not own machine setup, so it links here. The EFDC repository template can carry the Claude settings fragment for work repos, but the container image and launcher are personal-machine tooling and would bloat the template.


### Decision still open: shell script or a Go program

The launcher is a 470-line bash script wrapping about a dozen podman invocations. Whether it should become a Go program, with or without a window, does not need deciding before Phase 3, but the trade-offs are known now.

| Form | What it gives | What it costs |
|---|---|---|
| Bash script (current) | Nothing to build or release; runs unchanged on Linux, WSL2, and macOS; easy for a colleague to read and patch. | Terminal only. Error handling and configuration stay simple. macOS ships bash 3.2, so the script must keep avoiding bash 4 features. |
| Go command-line binary (no window) | One static binary per platform via GitHub releases; structured config; `go test` coverage of the podman argument assembly; a Windows `.exe` that drives `wsl.exe` would remove the "open a WSL terminal first" step for coworkers. | A build and release pipeline for a tool that mostly assembles argument lists. |
| Go terminal interface (Bubble Tea) | Menu-driven `airlock` with no platform dependencies beyond the binary: status, up, code, login as menu items. Good middle ground for colleagues who avoid flags. | Same pipeline cost; still a terminal. |
| Go desktop window or tray icon (Fyne, Wails, or a systray library) | A "Start airlock, open VS Code" tray icon on Windows and Linux. | GUI toolkits bring cgo, WebView2 or WebKitGTK, and Wayland versus X11 quirks. The heaviest option for the least added capability. |

Recommendation: keep bash through Phase 4 so the design is proven before anything is rebuilt. Revisit at Phase 5, because Windows coworkers are the audience that gains from a Go build, and the first Go form to consider is the Windows `.exe` that drives `wsl.exe`, with a tray icon only if colleagues ask for it. Go is already in the image and in your own projects, so the language choice carries no new cost.


### Open items

- `act` inside the airlock needs podman inside podman (`--device /dev/fuse` and SELinux labeling off). Decide after Phase 3 whether the Linux CI job reproduced by `cargo test` is enough.
- The KDE chat client (Alpaka) speaks the Ollama API; the 11434 gateway speaks the OpenAI API. Either extend the gateway with `/api/tags` and `/api/chat`, or run Ollama with its Vulkan backend after confirming it detects the RX 5500 XT.
- The Claude domain allowlist in `config/claude-settings.json` is a starting seed. Prune or extend it after a week of prompts.
- The attached-container URI that `airlock open` builds encodes `{"containerName":"/airlock"}` in hex. The Dev Containers extension has used that form; if a VS Code update changes it, Phase 4 records the new one.
- The image bakes the Claude Code installer and the Codex npm package into the home volume on first start. Later image rebuilds do not refresh the volume; `airlock update` does.
- On Windows, the Windows-side LLM server must accept connections from the WSL subnet under NAT networking, which usually means a Windows Firewall rule for the server binary.


### Conclusion
After Phase 3 the setup is complete for daily Fedora work. Phases 4 to 7 follow in the order most likely to be wanted: the attach fallback, Windows for coworkers, the Mac when it arrives, and the repository last.


### Additional resources
* [Architecture](architecture.md)
* [Claude Code sandboxing documentation](https://code.claude.com/docs/en/sandboxing)
* [Claude Code MCP documentation](https://code.claude.com/docs/en/mcp)
* [Podman 5.3 pasta networking changes](https://blog.podman.io/2024/10/podman-5-3-changes-for-improved-networking-experience-with-pasta/)
* [WSL networking modes](https://learn.microsoft.com/en-us/windows/wsl/networking)
* [PeerFoil sandbox preflight issue](https://github.com/gabrielmongefranco/peerfoil/issues/4)



[← Back to README](../README.md)

----

Copyright © 2026 Gabriel Mongefranco
