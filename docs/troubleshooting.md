<!--
This file is part of Agent Airlock™
docs/troubleshooting.md
Author(s): Gabriel Mongefranco
Created: 2026-09-26
Last Modified: 2026-10-01
Summary: Known failure modes seen in real use, each with its symptom, cause,
         and fix. Covers setup, the doctor check, building, logins, opening
         the editor, and the agents' own sandboxes.
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


### Empty hidden files such as `.bashrc` or `.mcp.json` appear in a repository

**Symptom:** `git status` or the Source Control view lists untracked files you did not create, such as `.bash_profile`, `.bashrc`, `.gitconfig`, `.gitmodules`, `.idea`, `.mcp.json`, `.profile`, `.ripgreprc`, `.vscode`, `.zprofile`, and `.zshrc`, plus empty files under `.claude/`. They come and go while an agent works, or stay for days.

**Cause:** older airlock settings left the filesystem layer of Claude Code's Bash sandbox on. On Linux, that layer protects these paths while a command runs by creating an empty, read-only file at each one that does not exist yet. It removes the files when the command ends. A command that keeps running, such as a test server started in the background, keeps the files in place, and a session that is killed leaves them behind.

**Fix:** update the airlock, which turns the filesystem layer off. A new home volume gets the setting from the image. For an existing volume, merge the setting into the live file from a host terminal. This keeps your other choices, such as the model and theme:

```bash
podman exec airlock bash -lc 'cd ~/.claude && jq ".sandbox.filesystem.disabled = true | .permissions.additionalDirectories = (((.permissions.additionalDirectories // []) + [\"/home/agent/git\"]) | unique) | .sandbox.excludedCommands -= [\"sudo apt-get *\", \"sudo apt *\"]" settings.json > settings.json.new && mv settings.json.new settings.json'
```

Then reload each editor window (Command Palette, then "Developer: Reload Window"). The reload also stops any background command that still holds the files. If some files remain, list them, check the list, and delete them. Never commit them.

```bash
find ~/git -maxdepth 4 -type f -size 0 -perm 444 \( -name '.*' -o -path '*/.claude/*' -o -name config.lock \)
```


### "git push -u" or a new branch fails with "could not lock config file .git/config: File exists"

**Symptom:** `git push -u`, `git checkout -b <branch> origin/main`, or the editor's Source Control fails with `error: could not lock config file .git/config: File exists`. The push itself goes through, but git does not record the upstream branch, so a later plain `git push` says the branch has no upstream. The error can appear inside the airlock and in git on the host.

**Cause:** the same sandbox layer described in [Empty hidden files](#empty-hidden-files-such-as-bashrc-or-mcpjson-appear-in-a-repository) puts an empty, read-only `.git/config.lock` in the repository while an agent's command runs. Git uses that file name as its lock, so every git process treats the config as locked: the agents, the editor, and git on the host.

**Fix:** apply the settings update from [Empty hidden files](#empty-hidden-files-such-as-bashrc-or-mcpjson-appear-in-a-repository) and reload the editor windows. For a branch that was pushed while the lock was in place, record the upstream once:

```bash
git branch --set-upstream-to=origin/<branch>
```


### An agent reports "Read-only file system" for another repository under `~/git`

**Symptom:** an agent can change files in the repository its session started in, but gets `Read-only file system` anywhere else under `~/git`. For example, it cannot clone a repository into `~/git` or change a sibling repository.

**Cause:** with the filesystem layer on, Claude Code's sandbox let commands write only to the session's working folder, which is the folder the editor window has open. `airlock vscode` asks for `~/git`, but VS Code reopens the windows you had last, so most sessions start in a single repository.

**Fix:** apply the settings update from [Empty hidden files](#empty-hidden-files-such-as-bashrc-or-mcpjson-appear-in-a-repository). It also lists `/home/agent/git` under `permissions.additionalDirectories`, so Claude Code's file tools treat all of `~/git` as the workspace from any window.


### A folder disappears in the file manager and comes back after you go up a level

**Symptom:** while an agent works, Dolphin or another file manager shows a folder inside a repository as gone. After you go up to a parent folder and back, the folder is there again.

**Cause:** git removes a folder when it switches to a commit that does not have it, and creates the folder again when it switches back. Agents often check out an outdated local `main` and then pull, so folders that the newer commits add disappear and return within seconds. The new folder has the same name but is a different folder on disk, so a file manager that was showing the old one loses track of it. This is ordinary git behavior and happens outside the airlock too.

**Fix:** go up a level and back to reload the folder. The airlock's rules file for Claude Code (`config/claude-airlock-rules.md`) asks agents to start new branches from `origin/<default-branch>` without checking out the outdated local branch first, which avoids most of these switches. [A server started by one command cannot be reached from the next](#a-server-started-by-one-command-cannot-be-reached-from-the-next) shows how to add the rules file to an existing home volume.


### A server started by one command cannot be reached from the next

**Symptom:** an agent starts a database or web server in one command and tests it in another, and the test fails with `Connection refused`, curl exit code 7, or `ERROR 2002 (HY000): Can't connect to server on '127.0.0.1'`. A server you start in the editor terminal is also out of reach for the agent's commands, even though the editor and the host browser can reach it.

**Cause:** Claude Code's sandbox runs each Bash command in its own network namespace, with its own loopback interface. A server listens only inside the namespace of the command that started it. The sandbox's domain allowlist works through the same isolation, so the airlock keeps it on.

**Fix:** to test servers, ask the agent to start them, run the checks, and stop them in one command. To open a server in the host browser, start it in the editor terminal, or with one of the commands listed under `excludedCommands` in `config/claude-settings.json`, on a port from 4000 to 4010.

The airlock's rules file tells Claude Code about this limit in every session. A new home volume gets it from the image. For an existing volume, add it from a host terminal in the repository folder:

```bash
podman exec airlock mkdir -p /home/agent/.claude/rules
podman cp config/claude-airlock-rules.md airlock:/home/agent/.claude/rules/airlock.md
```

For a project that needs long-running servers shared between commands, turn the inner sandbox off for that project only. Create `.claude/settings.local.json` in the project with the content below, check that the repository's `.gitignore` covers `.claude/`, and start a new Claude session there. In that project, Bash commands then run at container level with no domain allowlist and no API key hiding, and each one goes through the normal permission flow: a prompt in Manual mode, or the classifier in auto mode.

```json
{
  "sandbox": {
    "enabled": false
  }
}
```


### "Can't start server : UNIX Socket : Operation not permitted"

**Symptom:** MariaDB, or another server that listens on a socket file, fails to start inside an agent's command with this error. A client that connects through a socket file fails in the same way.

**Cause:** the sandbox's seccomp filter blocks Unix-domain sockets in Bash commands.

**Fix:** use TCP on `127.0.0.1`, inside one command as described in [A server started by one command cannot be reached from the next](#a-server-started-by-one-command-cannot-be-reached-from-the-next). Start MariaDB with `--socket= --bind-address=127.0.0.1 --port=<port>`, and connect with `mariadb -h 127.0.0.1 -P <port> --protocol=tcp`. In PHP, set the database host to `127.0.0.1:<port>`, not `localhost`, because MySQL and MariaDB clients treat `localhost` as a request for the socket file. The per-project switch in the same entry also lifts this limit.


### `sudo` fails with a "no new privileges" error

**Symptom:** an agent's `sudo apt-get install` fails with `sudo: The "no new privileges" flag is set, which prevents sudo from running as root.`

**Cause:** Claude Code keeps every command that starts with `sudo` inside its sandbox, even when `excludedCommands` lists it, and `sudo` cannot run there. Older airlock settings listed `sudo apt-get *` and `sudo apt *` as excluded, which had no effect.

**Fix:** when the agent asks to run the install outside the sandbox, approve it, or run the install yourself in the editor terminal or in `airlock shell`. The settings update in [Empty hidden files](#empty-hidden-files-such-as-bashrc-or-mcpjson-appear-in-a-repository) removes the two unused entries.


### The Codex panel shows no sign-in screen

**Symptom:** the Codex extension's panel stays empty or shows an error instead of a sign-in screen. The Codex output log (Output panel, then "Codex") shows `failed to initialize sqlite state runtime under /home/agent/.codex` and `Codex app-server process exited unexpectedly`.

**Cause:** each editor window starts its own Codex backend. Right after the extension is installed, every open window starts one at the same moment on a new `~/.codex` folder, and only the first can set up its state database. The others exit.

**Fix:** reload each affected window, one at a time (Command Palette, then "Developer: Reload Window"). Then sign in from the panel, which opens Firefox inside the container, or run `airlock login codex` from a host terminal. A `401 Unauthorized` line in the log before you sign in is expected.


### Codex commands fail with "bwrap: Can't mount proc on /proc: Operation not permitted"

**Symptom:** shell commands that Codex runs under its own sandbox fail with this message.

**Cause:** Codex's `workspace-write` sandbox runs commands under bubblewrap with a fresh `/proc`, which a rootless container does not allow. Its legacy Landlock mode also requires bubblewrap, so Codex's sandbox cannot start in the airlock.

**Fix:** update the airlock. Its Codex settings (`config/codex-config.toml`) now use `sandbox_mode = "danger-full-access"`, so the container is Codex's boundary. For an existing home volume, copy the file in from a host terminal in the repository folder, then reload the editor windows. The copy replaces `~/.codex/config.toml` in the container, so carry over any changes you made there first.

```bash
podman cp config/codex-config.toml airlock:/home/agent/.codex/config.toml
```


### Conclusion

You can now match the failures seen so far to their fixes, and you know to keep the full command output when something new breaks. The [implementation plan](implementation-plan.md) carries the per-phase checklists that catch most of these earlier.


### Additional resources

* [Architecture](architecture.md)
* [Implementation plan](implementation-plan.md)
* [Pending decisions](pending-decisions.md)
* [Claude Code sandboxing documentation](https://code.claude.com/docs/en/sandboxing)



[← Back to README](../README.md)

----

Copyright © 2026 Gabriel Mongefranco
