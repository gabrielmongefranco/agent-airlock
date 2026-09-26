<!--
This file is part of Agent Airlock™
docs/troubleshooting.md
Author(s): Gabriel Mongefranco
Created: 2026-09-26
Last Modified: 2026-09-26
Summary: Known failure modes seen in real use, each with its symptom, cause,
         and fix. Covers setup, the doctor check, building, logins, and
         opening the editor.
Notes: See README file for documentation and full license information.

Copyright © 2026 Gabriel Mongefranco

Licensed under the GNU Free Documentation License v1.3 or later.
See <https://www.gnu.org/licenses/fdl-1.3.html>. See README for full license information.

-->

# Agent Airlock™

## Troubleshooting

[← Back to README](../README.md)

This page lists problems people have actually hit, with the cause and the fix. Each section starts with the message or behavior you see. If your problem is not here, run the failing command again and keep its full output; that output is what a fix needs.


### Reading the doctor output

`airlock doctor` labels every line:

| Label | Meaning |
|---|---|
| `fail` | Must be fixed. Doctor exits with an error while any of these remain. |
| `warn` | The airlock runs, but something will misbehave until this is fixed. |
| `info` | Context only. No action needed. |

The local LLM port lines are `info` because the airlock works without a local model server; only local-model features wait on it. The Wayland line is `info` because a missing display only removes the `code` command, and `open` still works.


### "Containerfile not found next to this script"

**Symptom:** `airlock build` stops with this error, usually when `airlock` is run through a symlink such as `~/.local/bin/airlock`.

**Cause:** older copies of the launcher looked for the Containerfile next to the symlink instead of next to the real script.

**Fix:** update to the current launcher, which resolves the symlink first, and create the link with `bash ./airlock install` rather than by hand.


### Playwright warns about a missing project during the build

**Symptom:** the image build prints a Playwright warning about running without a project dependency, as if it were installing into a project.

**Cause:** the build used to call Playwright through `npx` in a bare directory, which Playwright treats as a project install.

**Fix:** rebuild with the current Containerfile, which installs Playwright as a global npm package before fetching its Chromium browser.


### "airlock is not running; run: airlock up"

**Symptom:** `login`, `shell`, or an editor command stops with this message.

**Cause:** older copies of the launcher required a manual `airlock up` before any command that uses the container.

**Fix:** update the launcher. Commands that need the container now start it themselves, with `--gui` when the image was built with it. On an older copy, run `airlock up --gui` (or `airlock up` on macOS) first. `airlock status` shows whether the container is running.


### Claude Code cannot open a browser during login

**Symptom:** `airlock login claude` prints a URL instead of opening the browser, and asks you to paste a code back.

**Cause:** this is expected. The container has no browser, so the login is a copy-and-paste round trip through the host browser.

**Fix:** open the URL on the host, sign in, copy the code, and paste it back in the terminal. When the login finishes, type `/exit` to leave Claude Code and return to the host shell.


### The Claude Code trust prompt names `/home/agent`

**Symptom:** during `airlock login claude`, Claude Code asks whether you trust the workspace `/home/agent`.

**Cause:** Claude Code treats its working directory as the workspace, and older launchers started it in the container home.

**Fix:** update the launcher. Logins now start in `~/git`, the shared projects directory, so the prompt names that folder instead. Trusting `~/git` covers the tree where all projects live; it does not tie you to a single repository.


### VS Code never appears, or the desktop reports a fatal error in `/usr/share/code/code`

**Symptom:** `airlock vscode` (or the `code` shorthand) reports a launch, but no window opens. On KDE, a notification may say `/usr/share/code/code has encountered a fatal error`.

**Cause:** VS Code is an Electron application, and Electron embeds Chromium as its user interface engine, so Chromium's flags and sandbox rules apply to the editor. Two causes have been seen. Chromium's setuid sandbox cannot start inside a rootless container, so the launcher passes `--no-sandbox`, because the container itself is the isolation boundary. And when the editor cannot reach the Wayland socket, it falls back to X11, which does not exist in the container, and exits; a foreground run then prints `Missing X server or $DISPLAY` and `The platform failed to initialize`. A dead socket usually means the compositor restarted (logout or reboot) after the container started. The `Failed to connect to the bus ... system_bus_socket` line in the same output is harmless, because the container has no system D-Bus.

**Fix:** update the launcher. It now pins the editor to Wayland with `--ozone-platform=wayland` and refuses to launch when the socket inside the container is not alive, naming this restart as the fix:

```bash
airlock down && airlock up --gui
```

If it still fails, run the editor in the foreground so the real error is visible:

```bash
podman exec -it airlock code --ozone-platform=wayland --disable-gpu --no-sandbox --verbose ~/git
```

Type the flags exactly; a misspelled flag such as `--nosand-box` is passed through to Chromium and silently ignored. Keep the output; it names the actual failure. If you override `AIRLOCK_CODE_ARGS`, your override replaces all three default flags, so include them.


### "sysctl: permission denied" and "invoke-rc.d: policy-rc.d denied execution" during the build

**Symptom:** the image build prints lines such as `sysctl: permission denied on key "kernel.core_pattern"` or `invoke-rc.d: policy-rc.d denied execution of start`, usually while apt sets up systemd or procps.

**Cause:** Debian packages try to apply kernel settings and start services when they install. A rootless container build is not allowed to change the host kernel or run services, so those steps are denied. Nothing in the image needs them.

**Fix:** none needed. The build continues and the lines are harmless. A real build failure stops the build and names a package or command.


### "airlock down" hangs for ten seconds and warns about SIGKILL

**Symptom:** `airlock down` waits about ten seconds and prints `StopSignal SIGTERM failed to stop container ... resorting to SIGKILL`.

**Cause:** the container idles on a `sleep` command as process 1, and process 1 does not receive default signal handling, so the stop signal was ignored until podman forced the kill.

**Fix:** the launcher now starts the container with `--init`, which runs a small init as process 1 and forwards the stop signal. An existing container keeps its old settings, so remove and recreate it once: `airlock reset`, then `airlock up --gui`. Nothing is lost; the home volume survives.


### The host VS Code asks to create a `.devcontainer` instead of attaching

**Symptom:** `airlock vscode --host` (or the `open` shorthand) opens the host VS Code, but instead of attaching to the running container it offers to set up a `.devcontainer`.

**Cause:** the Dev Containers extension talks to Docker unless the host settings point it at podman. When it cannot find the container, it falls back to offering a new dev container configuration. No `.devcontainer` folder is needed or wanted; the attach works without one by design.

**Fix:** merge `config/vscode-host-settings.jsonc` into your host VS Code user settings, which sets `dev.containers.dockerPath` to `podman`, and install the Dev Containers extension on the host. `airlock attach` prints the manual steps. The launcher now warns when the settings are missing.


### VS Code shows a "Restricted Mode" banner and Source Control does not work

**Symptom:** the editor inside the container opens with a banner reading "Restricted Mode is intended for safe code browsing", and the Source Control view says no provider works in restricted mode.

**Cause:** VS Code's Workspace Trust treats a folder it has not seen before as untrusted and disables features, including git integration, until you trust it. Inside the airlock this guard adds little, because everything under `~/git` is your own work and the container is the isolation boundary.

**Fix:** rebuild the image and recreate the container, and the airlock's VS Code starts with Workspace Trust disabled (`config/vscode-container-settings.jsonc`). On an existing container, either click "Manage" in the banner and trust the parent folder `/home/agent/git` once, or copy the setting in by hand:

```bash
podman exec airlock mkdir -p /home/agent/.config/Code/User
podman cp config/vscode-container-settings.jsonc airlock:/home/agent/.config/Code/User/settings.json
```

The image copies this file only when the home volume is first created, so an existing volume keeps whatever settings it already has.


### GitHub sign-in from the editor inside the container never finishes

**Symptom:** clicking "Sign in with GitHub" in the VS Code that runs inside the container shows a progress bar that never completes.

**Cause:** that sign-in needs a browser round trip that ends in a `vscode://` link handled by the same machine. Without a browser in the container, the reply never arrives.

**Fix:** the sign-in must finish in a browser inside the container. Images built with `--gui` include Firefox for exactly this, so rebuild (`airlock build --gui`) and recreate the container, or install it into the running container without a rebuild:

```bash
airlock shell
sudo apt-get update && sudo apt-get install -y firefox-esr
```

Then retry the sign-in; it opens Firefox on your desktop, and the redirect back to the editor stays inside the container. Two fallbacks also work: open the project through the host window (`airlock vscode --host`), where the round trip completes on the host, or skip editor sign-in entirely when you only need the agents, because Claude Code, Codex, and git read the `airlock login` credentials. Installing extensions from the marketplace needs no sign-in; only account-bound extensions such as Copilot do.


### "git push" asks for a username and password, then rejects them

**Symptom:** `git push` opens prompts for a username and a password, and then fails saying password authentication is not supported.

**Cause:** GitHub turned off password authentication for git over HTTPS in 2021. The prompts mean git has no credential helper configured, on the host or in the container; a password typed there can never work.

**Fix:** log in with the GitHub CLI and let it act as git's credential helper. On the host: install it (`sudo dnf install gh` on Fedora, `sudo apt-get install gh` on Debian and Ubuntu), then run `gh auth login` (choose GitHub.com, HTTPS, and the web-browser flow) followed by `gh auth setup-git`. Inside the container: run `airlock login gh`, which runs the same login and registers the helper for you. The two logins are separate on purpose; the container keeps its own token in the home volume, inside the boundary, and never sees the host's.


### Conclusion

You can now match the failures seen so far to their fixes, and you know to keep the full command output when something new breaks. The [implementation plan](implementation-plan.md) carries the per-phase checklists that catch most of these earlier.


### Additional resources

* [Architecture](architecture.md)
* [Implementation plan](implementation-plan.md)
* [Pending decisions](pending-decisions.md)



[← Back to README](../README.md)

----

Copyright © 2026 Gabriel Mongefranco
