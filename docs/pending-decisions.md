<!--
This file is part of Agent Airlock™
docs/pending-decisions.md
Author(s): Gabriel Mongefranco
Created: 2026-09-26
Last Modified: 2026-09-26
Summary: Lists design decisions that are still open, with the options for
         each. Covers how the image installs Claude Code and how every other
         downloaded package is pinned and verified.
Notes: See README file for documentation and full license information.

Copyright © 2026 Gabriel Mongefranco

Licensed under the GNU Free Documentation License v1.3 or later.
See <https://www.gnu.org/licenses/fdl-1.3.html>. See README for full license information.

-->

# Agent Airlock™

## Pending Decisions

[← Back to README](../README.md)

This page lists decisions that are still open, so they are not lost. Each one describes what the code does today, the options, and their trade-offs. Nothing here has been chosen yet. It is written for the maintainer who picks these up later.


### Overview

The image downloads software from the internet while it builds. Two questions apply to every download:

- **Pinning:** does the build ask for one exact version, or whatever is newest?
- **Verification:** does the build check that the file is the one the publisher released, before it runs?

A few terms used below:

- A **checksum** (SHA-256 here) is a fingerprint of one exact file. If the file changes, the checksum changes.
- A **signature** is made with the publisher's private key. Anyone with the matching public key can check it. A signature can cover new releases, so it works with "always newest". A checksum cannot.
- A **lockfile** records the exact version and checksum of every package, so later installs get the same files.

A checksum only proves something when it comes from a different place than the file. If the same server hands out both, whoever controls the server controls both.


### Decision 1: how the image installs Claude Code

#### Current state

The `Containerfile` runs `curl -fsSL https://claude.ai/install.sh | bash` as the `agent` user. The shell runs the script as it downloads. The build does not check the script or the binary it installs.

The installer puts Claude Code in the home volume, and it updates itself from there:

- Native installs update in the background by default.
- `airlock update` runs `claude update`.

So a check at build time only covers the first install. Later versions replace it without passing through the build.

A bad download would affect the image, and everything the agents can reach from it, such as `~/git` and their logins. It runs as an unprivileged user during the build, so it does not reach the host system directly.

#### Options

Anthropic's setup documentation describes all of the install methods below. It also states that Linux binaries are not individually code-signed. Instead, each release publishes a `manifest.json` with SHA-256 checksums, signed with the Claude Code release key.

| Option | How it works | Gets the newest version | How it is verified | Cost |
|---|---|---|---|---|
| A. Signed apt repository | Add Anthropic's apt repository and key, then `apt-get install claude-code`. | Yes, by channel: `stable` (about a week behind) or `latest`. | apt checks every package against the release signing key. The build checks the key's fingerprint first. | Installs into the image, not the home volume. It does not update itself; updates come from a rebuild or `sudo apt upgrade claude-code`. `airlock update` would need to change. |
| B. Native binary with the signed manifest | Download `manifest.json` and `manifest.json.sig` for a release, check the signature with `gpg`, then check the binary's SHA-256 against the manifest. | Yes. Trust rests on the key, so the build can look up the newest release. | GPG signature plus checksum. | More shell code in the `Containerfile`. Signatures exist from release 2.1.89 onward. |
| C. Pinned version and checksum | Store the version and its SHA-256 in the `Containerfile`. A bot opens a pull request when a new release ships. | After you merge each bump. | The checksum is checked at pin time and on every build. | Needs Renovate or a scheduled workflow. |
| D. npm with a lockfile | List `@anthropic-ai/claude-code` in a `package.json` and `package-lock.json`, and install with `npm ci`. | After you merge each bump. | npm checks the sha512 integrity hash in the lockfile. | Trust rests on the npm registry. The package pulls the same native binary through a per-platform optional dependency. Whether it publishes provenance attestations is not checked. |
| E. Keep the install script | No change. | Yes. | TLS only. | Does not meet the pinning rule in section 7 of `AGENTS.md`. |

The key fingerprint published in Anthropic's setup documentation is `31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE`. Check it against that page again before relying on it.

#### Updates inside the container

Every option above has to decide whether Claude Code may update itself in the home volume. Anthropic documents two settings:

- `DISABLE_AUTOUPDATER=1` stops the background check. `claude update` still works.
- `DISABLE_UPDATES` blocks every update path, including `claude update`.

Either one goes in the `env` key of `config/claude-settings.json`. If updates stay on, the build-time check only covers the first install.

#### Recommendation

Option A looks like the best fit. The image is already Debian, apt does the checking, and the `stable` or `latest` channel keeps it current without a manual bump. Option B is the fallback if Claude Code must stay in the home volume. Both would be paired with `DISABLE_AUTOUPDATER` so that updates go through the checked path.


### Decision 2: pinning the other packages

#### Current state

| Package | Where | What happens today | Pinning options |
|---|---|---|---|
| Debian base image `debian:trixie-slim` | `Containerfile` | Pulled by tag. The tag moves when Debian publishes updates. | Pin by digest (`debian:trixie-slim@sha256:...`) and let a bot update the digest. |
| Debian packages (base toolchain) | `Containerfile` | Newest in Debian 13 at build time. apt checks them against the Debian archive keys already in the image. | Usually left as is. `snapshot.debian.org` can reproduce an exact package set if that is ever needed. |
| Microsoft apt signing key | `Containerfile` (`--gui` only) | Downloaded with `curl` and trusted over TLS alone. | Check the key's fingerprint against Microsoft's published value before using it. |
| VS Code (`code`) | `Containerfile` (`--gui` only) | Newest from Microsoft's repository. apt checks it against the key above. | Pin with `code=<version>` if exact builds are wanted. |
| Playwright and its Chromium | `Containerfile` | `npx -y playwright install` fetches the newest Playwright at build time. | Pin the Playwright version, in a lockfile or as `playwright@<version>`. |
| `@openai/codex`, `@anthropic-ai/sandbox-runtime`, `@playwright/mcp` | `Containerfile` | `npm install -g` installs the newest versions. There is no lockfile. | A `package.json` and `package-lock.json` installed with `npm ci`, with bot bumps. |
| `uv` | `Containerfile` | `pipx install uv` installs the newest version from PyPI. | Pin `uv==<version>`, or install from a hash-checked requirements file. |
| `@playwright/mcp@latest` | `config/codex-config.toml` | Codex starts it with `npx -y`, so it downloads the newest version when it runs, not at build time. | Pin a version, or point Codex at the copy installed in the image. |
| `@playwright/mcp@latest` | Phase 2 of the [implementation plan](implementation-plan.md) | The `claude mcp add` command has the same behavior for Claude Code. | Same as the row above. |
| `airlock update` | `airlock` | Runs `claude update` and then `npm update -g`. | Anthropic's documentation warns that `npm update -g` keeps to the version range of the first install and may not reach the newest release. Decide whether `airlock update` should rebuild the image instead. |

#### Keeping pins current

Pins go stale unless something updates them. Two common tools can open a pull request for each new release:

- **Renovate** handles `Containerfile` image digests, npm lockfiles, and, with a custom regex rule, version and checksum pairs written anywhere in a file.
- **Dependabot** handles npm and container images, and is built into GitHub.

Either way, you review and merge each bump, and CI builds the image before it lands.


### Questions to answer

1. Which Claude Code install option (A to E) should the image use?
2. Should Claude Code update itself inside the home volume, or only through a rebuild?
3. Which of the other packages need exact pins, and which are fine at "newest, verified"?
4. Renovate, Dependabot, or neither?
5. Should `airlock update` keep updating in place, or rebuild the image?


### Conclusion

You now have the open decisions on installing and pinning the image's software, with the options for each. When one is decided, change the code, move the decision into the [architecture page](architecture.md), and remove it from this page.


### Additional resources

* [Architecture](architecture.md)
* [Implementation plan](implementation-plan.md)
* [Project instructions, section 7 on security](../AGENTS.md)
* [Claude Code advanced setup: Linux package managers, version pinning, and binary integrity](https://code.claude.com/docs/en/setup)
* [npm ci command reference](https://docs.npmjs.com/cli/commands/npm-ci)
* [Renovate documentation](https://docs.renovatebot.com/)
* [Dependabot documentation](https://docs.github.com/en/code-security/dependabot)
* [Debian snapshot archive](https://snapshot.debian.org/)



[← Back to README](../README.md)

----

Copyright © 2026 Gabriel Mongefranco
