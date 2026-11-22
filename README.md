# Personal Media Stack — Starter Bundle

An always-on **Windows 11 Pro** media server + **Apple TV 4K / HomePod** Siri-controlled living room + **macOS** personal movie editing pipeline + strictly isolated **Stash** private library.

## Architecture Overview

| Layer | Host | Components |
| :--- | :--- | :--- |
| **Core Media Server** | Windows 11 Pro (Native) | Plex Media Server (Intel QSV / NVENC transcoding), Tailscale, SMB Shares |
| **Automation & Private Library** | Windows 11 Pro (Docker Desktop / WSL2) | Gluetun (VPN kill-switch), qBittorrent, Prowlarr, Sonarr, Radarr, Overseerr, Stash, MeTube |
| **Smart Home & Siri Voice Bridge** | Windows 11 Pro (Hyper-V VM, Bridged LAN) | Home Assistant OS (Apple TV integration, HomeKit Bridge, Lights/AVR scenes, Plex voice webhook) |
| **Living Room Playback** | Apple TV 4K + HomePod | Infuse Pro (synced to Plex), Plex app, Apple Home / Siri Shortcuts, Tailscale tvOS |
| **Personal Movie Editing** | macOS (over LAN/SMB) | LosslessCut (instant lossless cuts), DaVinci Resolve Free (full NLE), `ingest_home_movie.sh` (FFmpeg batch optimizer) |

## What's in This Bundle

1. [`windows/setup-folders.ps1`](windows/setup-folders.ps1) — Creates the TRaSH-Guides-compliant directory tree (hardlink-ready for `*arr`), keeps `Private/stash` physically separate from Plex, configures Windows 11 always-on power settings, and prints SMB share setup commands.
2. [`docker/.env.example`](docker/.env.example) & [`docker/docker-compose.yml`](docker/docker-compose.yml) — Complete stack for VPN-isolated `*arr` automation plus isolated Stash + MeTube downloader.
3. [`home-assistant/automations_and_scripts.yaml`](home-assistant/automations_and_scripts.yaml) & [`home-assistant/homekit_bridge_config.yaml`](home-assistant/homekit_bridge_config.yaml) — Ready-to-use Home Assistant scenes, Siri-exposed scripts, cinema lighting automations, and dynamic Plex voice webhook.
4. [`shortcuts/README-shortcuts-and-bookmarklet.md`](shortcuts/README-shortcuts-and-bookmarklet.md) — Exact setup steps for the 1-tap iPhone/Mac **"Send to Stash"** Share Sheet Shortcut, browser bookmarklet, and hands-free **"Play on Plex"** Siri Shortcut.
5. [`editing/ingest_home_movie.sh`](editing/ingest_home_movie.sh) — macOS batch-processing script (`ffmpeg`) for normalizing audio, preserving dates, applying `+faststart` for Apple TV/Infuse, and auto-filing into `HomeMovies/YYYY/YYYY-MM-DD - Title.mp4`.

## Recommended Deployment Order

1. **Windows 11 Base**: Run `windows/setup-folders.ps1` (as Administrator), install **Tailscale**, **Plex Media Server** (native), and **Docker Desktop (WSL2)**.
2. **Docker Stack**: Copy `docker/.env.example` to `docker/.env`, fill in your drive paths and VPN credentials, and run `docker compose up -d`.
3. **Hyper-V Home Assistant OS**: Create the HAOS VM on a **Bridged External Virtual Switch** so mDNS/HomeKit/Apple TV discovery works natively, then add the Apple TV & HomeKit Bridge integrations.
4. **Apple TV & Infuse**: Install **Infuse** (connect to Plex) and **Tailscale** on Apple TV 4K; keep Stash completely excluded from Plex.
5. **Shortcuts & Editing**: Set up the iPhone/Mac Share Sheet Shortcut for MeTube -> Stash, mount the Windows SMB share on your Mac, and install LosslessCut + DaVinci Resolve + `ffmpeg` (`brew install ffmpeg`).
