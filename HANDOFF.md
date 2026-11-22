# Antigravity Session Handoff — Windows 11 Media Stack

> **For the Antigravity agent on the Windows 11 PC:**
> Read this file and `BLUEPRINT.md` first. Everything below summarizes the completed `/grill-me` scoping interview from the user's Mac so you can pick up immediately without re-asking settled questions.

## Locked-In Architecture & Decisions

1. **Always-On Server Host**: **Windows 11 Pro PC** (decent GPU / Intel CPU)
   - **Native Windows**: Plex Media Server (for native Intel QSV / NVENC hardware transcoding), Tailscale (private remote mesh, no port forwarding), SMB shares (`MediaEditing`, `HomeMovies`, optional hidden `StashPrivate$`).
   - **Docker Desktop (WSL2)**: `docker/docker-compose.yml` running:
     - **Gluetun** configured for **ExpressVPN via OpenVPN** (`VPN_SERVICE_PROVIDER=expressvpn`, `VPN_TYPE=openvpn` — requires the user's dedicated *Manual Configuration* OpenVPN username/password from the ExpressVPN web dashboard, NOT their regular email/password).
     - **`*arr` stack**: qBittorrent (routed through Gluetun), Prowlarr, Sonarr, Radarr, Overseerr — using TRaSH Guides unified `/data` mount for atomic moves/hardlinks.
     - **Isolated Private Adult Library**: **Stash** (password-protected, strictly separate `STASH_ROOT` drive/folder never mounted into Plex or `*arr`) + **MeTube** (`yt-dlp` web UI + REST API dropping straight into Stash's `inbox`, routed through Gluetun).
   - **Hyper-V VM (Bridged External Virtual Switch)**: **Home Assistant OS (HAOS)** — bridged LAN IP so mDNS, HomeKit Bridge, Apple TV (`pyatv`), Hue/smart lights, and AVR/TV discovery work natively without WSL2 NAT issues.

2. **Apple TV 4K & Hands-Free Voice Control**:
   - **Player**: **Infuse** (synced to Plex for Dolby Vision/HDR/codec playback & clean UI) + Plex app + Tailscale tvOS.
   - **Hardware to integrate**: Apple TV 4K, HomePod(s), smart lights/plugs (Hue/HomeKit/Matter), AVR/soundbar/smart TV.
   - **Voice Control**:
     - Curated HomeKit Bridge scripts (`home-assistant/homekit_bridge_config.yaml` + `automations_and_scripts.yaml`) exposing *Movie Night*, *Intermission*, *Living Room TV Off* to HomePod/iPhone Siri, plus auto-dim/brighten cinema lighting after sunset.
     - Dynamic Plex title playback via iOS/HomePod Siri Shortcut -> HA webhook (`/api/webhook/play_plex_title`).

3. **Private Adult Library Access & Downloads**:
   - Never mixed into Plex.
   - 1-tap iPhone/Mac Share Sheet Shortcut + browser bookmarklet posting to MeTube (`http://<WIN11_TAILSCALE_IP>:8081/add`) -> downloads straight into Stash's `inbox`.
   - Watched via Stash PWA on iPhone/iPad/Mac (over Tailscale when away), and privately on Apple TV via **AirPlay** from iPhone/iPad OR a **PIN-locked hidden SMB share (`StashPrivate$`)** in Infuse excluded from library indexing.

4. **Personal Movie Editing Pipeline (macOS -> Windows 11)**:
   - User edits on their **Mac** over LAN/SMB using **LosslessCut** (quick lossless cuts/merges), **DaVinci Resolve Free** (full creative editing), and `editing/ingest_home_movie.sh` (FFmpeg batch optimizer for Apple Silicon HEVC + `-16 LUFS` loudness normalization + `+faststart` + auto-filing into `HomeMovies/YYYY/YYYY-MM-DD - Title.mp4`, or `--lossless` remux mode).

## Files Included in This Workspace

- `BLUEPRINT.md` — Full architecture diagram and 5-phase setup roadmap.
- `windows/setup-folders.ps1` — Creates folder structure, disables sleep/hibernate, checks Hyper-V, prints SMB share commands.
- `docker/docker-compose.yml` & `docker/.env.example` — Complete ExpressVPN/Gluetun + `*arr` + Stash + MeTube stack.
- `home-assistant/automations_and_scripts.yaml` & `home-assistant/homekit_bridge_config.yaml` — Ready-to-customize HA configs.
- `shortcuts/README-shortcuts-and-bookmarklet.md` — Exact recipes for the iPhone/Mac Share Sheet Shortcut, bookmarklet, and Siri Plex Shortcut.
- `editing/ingest_home_movie.sh` — macOS FFmpeg ingest script.

## Immediate Next Steps on This Windows 11 PC

1. Inspect the Windows 11 PC's available drives, free space, GPU/CPU, Hyper-V status, and LAN subnet so we can customize `windows/setup-folders.ps1` and create `docker/.env`.
2. Execute **Phase 1** (folders, power settings, SMB shares, Tailscale, native Plex Media Server).
3. Execute **Phase 2** (Docker Desktop + `docker compose up -d` with ExpressVPN OpenVPN credentials + Stash security setup).
4. Execute **Phase 3** (Hyper-V External Virtual Switch + Home Assistant OS VM + Apple TV & HomeKit Bridge).
