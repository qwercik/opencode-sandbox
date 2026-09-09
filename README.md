# opencode-sandbox

## Installation

```bash
curl -sS https://raw.githubusercontent.com/qwercik/opencode-sandbox/master/opencode-sandbox \
  -o ~/.local/bin/opencode-sandbox
chmod +x ~/.local/bin/opencode-sandbox
```

If `~/.local/bin` is not in `$PATH`, add to `~/.bashrc`:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Usage

```bash
cd ~/projects/my-project
opencode-sandbox
```

## Bash aliases

For convenience you can add to `~/.bashrc`:

```
alias opencode-host='TERM=linux command opencode'
alias opencode='TERM=linux opencode-sandbox'
```

This way:
- `opencode` in the terminal runs the sandboxed version
- `opencode-host` runs the native version installed on the host

## How it works

The script pulls a pre-built lightweight Docker image from `ghcr.io/qwercik/opencode-sandbox`
(no Node.js on the host, nothing to install besides Docker). On startup:

1. **Config** — uses an isolated `~/.config/opencode-sandbox/`
   (created automatically). No need to worry about sandbox permissions
   leaking into native opencode.
2. **API key** — if you place `auth.json` in `~/.local/share/opencode-sandbox/auth.json`,
   it will be shared across all projects. Otherwise,
   use `/connect` inside the sandbox — the key will be saved per-project.
3. **Per-project sessions** — each folder has its own `opencode.db` and snapshots
   in `~/.local/share/opencode-sandbox/data/<hash>/`. No sessions from other
   projects are visible.
4. **Updates** — every 24h it checks whether a newer version of opencode or the script
   is available and prompts `opencode-sandbox --update`.
5. **Security** — the container runs with `--cap-drop=ALL` and `--security-opt=no-new-privileges`.
6. **Agent router** — the container is started with `--label agent-router.enabled=true` and `--label agent-router.name=<project-folder>` so that agent-router (e.g. Traefik) can discover and route to it.
7. **Built-in server** — when run without arguments, the container starts the opencode TUI with its embedded HTTP server listening on `0.0.0.0:4096` inside the container. This allows agent-router (or any other service in the same Docker network) to reach the opencode API without exposing ports to the host.
8. **`.env.agent`** — if a `.env.agent` file exists in the project directory, its
   variables are loaded into the container (only safe names are accepted).
   Use `SANDBOX_NETWORK=<network-name>` in `.env.agent` to attach the container
   to a specific Docker network. Without it, the container uses Docker's default
   bridge.
8. **Home directory** — if run from `$HOME`, a dedicated chat workspace is created in
   `~/.local/share/opencode-sandbox/chats/` instead of mounting the home directory.
9. **Symlinks** — symlinks in the project directory pointing outside the workspace are
    resolved and their targets are mounted individually (system paths are skipped).
10. **Config integrity** — before launching the container, the script checks that
    `~/.config/opencode-sandbox/` (when it is a git repository) has no staged, unstaged
    or untracked changes. This prevents accidental loss of opencode configuration
    inside the sandbox.

## Commands

| Command | Effect |
|---------|--------|
| `opencode-sandbox` | Normal run — TUI with embedded server on `0.0.0.0:4096` inside the container |
| `opencode-sandbox --update` | Pulls the latest image from GitHub Container Registry |
| `opencode-sandbox --cleanup` | Prunes orphaned sandbox networks created by older versions |
| `opencode-sandbox --version` | Shows the script version |
| `opencode-sandbox mcp add ...` | All arguments are passed into the container |

## Versioning

The script has a version (`VERSION` at the top of the file). `--version` shows
the script version. Every 24h the script checks GitHub releases for opencode
and the script's own URL — if a newer version of the script or opencode is available,
it displays a notification and update instructions.

## Clipboard

A terminal emulator supporting **OSC 52** escape sequences is required (e.g.
[Alacritty](https://alacritty.org/), iTerm2, Windows Terminal). `gnome-terminal`
does not support it.

## Environment variables

| Variable | Description |
|----------|-------------|
| `SANDBOX_NETWORK` | Name of a Docker network to attach the container to (set in `.env.agent`). When empty, the container uses Docker's default bridge with no special isolation. |

## Security

Sandbox mounts **only the current directory** (`$PWD`) into the container as
`/project/<directory-name>`. The container runs with `--cap-drop=ALL` and
`--security-opt=no-new-privileges`, so even though opencode has high privileges
inside, there is no way to break out.

The container has no access to any host directory — including `/etc`, `/home`,
`/tmp`, etc. The only exceptions are the explicitly mounted config volumes
(`~/.config/opencode-sandbox`, `~/.local/share/opencode-sandbox/`).

For network isolation, set `SANDBOX_NETWORK=<network-name>` in `.env.agent`
to attach to a restricted Docker network of your choice.

The sandbox itself does not enforce network isolation. For a generic solution
that restricts container network access via iptables, see
[github.com/qwercik/docker-isolate](https://github.com/qwercik/docker-isolate).