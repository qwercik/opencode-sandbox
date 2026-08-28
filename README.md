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
5. **Network isolation** — creates a dedicated bridge network with iptables rules that
   block all inbound/outbound traffic to private subnets and inter-container
   communication. The container runs with `--cap-drop=ALL` and `--security-opt=no-new-privileges`.
6. **host.docker.internal** — the container can reach the host via this hostname.
7. **`.env.agent`** — if a `.env.agent` file exists in the project directory, its
   variables are loaded into the container (only safe names are accepted).
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
| `opencode-sandbox` | Normal run |
| `opencode-sandbox --update` | Pulls the latest image from GitHub Container Registry |
| `opencode-sandbox --cleanup` | Prunes orphaned sandbox networks |
| `opencode-sandbox --version` | Shows the script version and opencode version in the image |
| `opencode-sandbox mcp add ...` | All arguments are passed into the container |

## Versioning

The script has a version (`VERSION` at the top of the file). `--version` shows
both the script version and the opencode version in the image. Every 24h the script
checks GitHub releases for opencode and the script's own URL — if a newer version of the script or opencode is available,
it displays a notification and update instructions.

## Clipboard

For security reasons the container does not have access to the host X11,
so `xclip` / copying text from inside the container does not work.

Recommended solution: disable mouse capture in the TUI configuration.
Add to `~/.config/opencode-sandbox/tui.json`:

```json
{
  "mouse": false
}
```

This way the terminal does not intercept mouse events and you can normally
select and copy text via the terminal (Ctrl+Shift+C).

## Environment variables

| Variable | Description |
|----------|-------------|
| `SANDBOX_ALLOW_HOST_PORTS` | Comma-separated list of host ports accessible from the container (e.g. `3000,8080`). Opens inbound firewall rules on the sandbox bridge. |

## Security

Sandbox mounts **only the current directory** (`$PWD`) into the container as
`/project/<directory-name>`. The container runs with `--cap-drop=ALL` and
`--security-opt=no-new-privileges`, so even though opencode has high privileges
inside, there is no way to break out.

The container has no access to any host directory — including `/etc`, `/home`,
`/tmp`, etc. The only exceptions are the explicitly mounted config volumes
(`~/.config/opencode-sandbox`, `~/.local/share/opencode-sandbox/`).

Network access is restricted via a dedicated bridge network with iptables rules
that block:
- All traffic to/from private subnets (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
- All inter-container communication
- All inbound traffic from the bridge

The container can reach the host via `host.docker.internal` and access the
internet (for API calls), but cannot reach other machines on the local network.