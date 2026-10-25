# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Personal Arch Linux environment management repo. Contains:
- **`bootstrap/arch/`** — System provisioning scripts (run once on a new machine)
- **`dotfiles/`** — Application configs managed as symlinks or copies
- **`scripts/`** — Shared shell utilities sourced by all bootstrap scripts
- **`services/`** — Docker Compose stack for self-hosted services

## Secrets and Encryption

Several files are encrypted with `git-crypt`:
- `dotfiles/ssh/config`
- `services/apps/auth-thu/auth-thu.json`
- `services/apps/sing-box/secrets/**` (subscription URL, clash API secret, inbound credentials)
- `services/secret-vars.env`

To unlock: join the tailnet, fetch the key from the self-hosted Bitwarden vault, then run `git-crypt unlock git-crypt.key`.

```bash
# Fetch git-crypt key from the self-hosted vaultwarden (tailnet only: https://hub.angora-wall.ts.net/vault)
bash scripts/sync_gitcrypt.sh
git-crypt unlock git-crypt.key
```

## Shared Script Utilities (`scripts/`)

All bootstrap scripts source these at the top:

```bash
. ${SCRIPTS_DIR}/color.sh   # color constants
. ${SCRIPTS_DIR}/log.sh     # info/warn/error/ok helpers
. ${SCRIPTS_DIR}/func.sh    # copy, link, backup functions
```

Key functions in `func.sh`:
- `copy src dst` — Copies a file, auto-backs-up existing destination, skips if identical
- `link src dst` — Creates a symlink, auto-backs-up if destination exists
- `backup file` — Renames file with a timestamp suffix
- Prefix `USE_SUDO=1` before any of the above to run with `sudo`

## Bootstrap Workflow (new machine)

Run scripts in this order (each is idempotent-friendly):

```bash
# 1. As root (after base Arch install, with network)
bash bootstrap/arch/bootstrap.sh

# 2. As user (sets up packages, docker, pacman config)
bash bootstrap/arch/setup.sh

# 3. As user (enables SSH agent, sound, SDDM)
bash bootstrap/arch/user_service.sh

# 4. Optional: NVIDIA GPU setup
bash bootstrap/arch/nvidia_setup.sh
```

Config files installed by bootstrap scripts come from `bootstrap/arch/etc/` and are either copied (system files that can't be symlinks, e.g. `/etc/systemd/`) or linked (e.g. `/etc/docker/daemon.json`).

## Dotfiles

Dotfiles in `dotfiles/` are not installed by any top-level script — they are linked manually using the `link` function from `scripts/func.sh`. The directory mirrors the target paths:

| Source | Target |
|--------|--------|
| `dotfiles/niri/config.kdl` | `~/.config/niri/config.kdl` |
| `dotfiles/hypr/hyprland.conf` | `~/.config/hypr/hyprland.conf` |
| `dotfiles/waybar/` | `~/.config/waybar/` |
| `dotfiles/dms/settings.json` | `~/.config/DankMaterialShell/settings.json` |
| `dotfiles/dms/plugins/AIAssistant/` | `~/.config/DankMaterialShell/plugins/AIAssistant/` |
| `dotfiles/local/bin/screenshot` | `~/.local/bin/screenshot` |

The `screenshot` script uses `grim` + `slurp` for capture, then `satty` for annotation, and `wl-copy` for clipboard.

## Services (Docker Compose)

All services are in `services/`. Run from that directory:

```bash
cd services

# Start all services
docker compose up -d

# Start a specific service
docker compose up -d caddy

# Rebuild after Dockerfile changes
docker compose build caddy && docker compose up -d caddy

# View logs
docker compose logs -f auth-thu
```

Services: `auth-thu` (Tsinghua network auth), `sing-box` (proxy), `corplink` (Feilian corp VPN, socks on 127.0.0.1:1088), `caddy` (reverse proxy), `qbittorrent`, `jellyfin`, `vaultwarden`, `gitea`.

### sing-box

Official image `ghcr.io/sagernet/sing-box:v1.14.4`. Config is generated, never hand-edited:

```bash
cd services/apps/sing-box
./update.sh [--fetch]      # regenerate all configs (--fetch pulls SUB_URL into secrets/subscription.b64 first),
                           # then apply.sh if gateway.json changed. Run manually; there is no timer.
python3 -m generator --target gateway   # generate only; writes out/, runs sing-box check
./apply.sh --detach        # switch out/gateway.json -> live/ via systemd; self-checks, auto-rolls back to live/good/
```

- Claude Code on the pi goes through `127.0.0.1:7890` — **never restart sing-box any other way than `apply.sh`**, and never run `docker compose up --force-recreate sing-box` without `--no-deps` (it would recreate auth-thu, whose deauth step logs the pi off the campus network).
- Inbounds: `local-in` 127.0.0.1:7890 (no auth), `ssh-forward-in` 127.0.0.1:9870 (no auth, public internet only — `RemoteForward 9870 127.0.0.1:9870` in `dotfiles/ssh/config`, servers use `http://127.0.0.1:9870`).
- `out/public/` (client-macos/client-linux/mobile.json) is served tailnet-only by `tailscale serve` at `https://hub.angora-wall.ts.net/sing-box/` — generating is publishing. Clients pull with `scripts/sync_sing_box.sh`.
- The pi is `hub` in the tailnet (100.66.22.71); `tailnet-gateway-in` on 100.66.22.71:7890 lets other tailnet devices reach the corp network.
- `out/` and `live/` are gitignored (they contain node passwords). `live/apply.log` has the switch history.
- When bumping the image, change both `compose.yml` and `IMAGE` in `generator/main.py`.

The `DISK_ROOT` env var controls where persistent data is stored (defaults to `~/disk`).

## DMS / AIAssistant Plugin

The `dotfiles/dms/plugins/AIAssistant/` directory is a QML/JavaScript plugin for DankMaterialShell. It has its own `CLAUDE.md` with detailed architecture, testing instructions, and provider-specific guidance. Read that file when working on the plugin.

```bash
# Reload after plugin changes
dms restart

# Debug mode
QS_FORCE_STDERR_LOGGING=1 DMS_LOG_LEVEL=debug dms run
```
