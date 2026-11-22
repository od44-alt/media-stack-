# ==============================================================================
# Windows 11 Pro Media Server Setup Script
# Run in an elevated PowerShell (Run as Administrator)
#
# What this script does:
#   1. Creates the TRaSH-compliant Media directory tree (hardlink-ready)
#   2. Creates the personal Home Movies editing & ingest folders
#   3. Creates a physically separate Private Stash tree (never touched by Plex)
#   4. Configures Windows 11 power settings so the server never sleeps
#   5. Prints optional SMB share commands for connecting your Mac over LAN
# ==============================================================================

param(
    [string]$ConfigDrive = "C:\MediaStack\config",
    [string]$MediaRoot   = "D:\Media",
    [string]$StashRoot   = "D:\Private\stash"
)

$ErrorActionPreference = "Stop"

Write-Host "=== 1. Creating Folder Structure ===" -ForegroundColor Cyan

$directories = @(
    # Docker container configs (SSD)
    "$ConfigDrive\gluetun",
    "$ConfigDrive\qbittorrent",
    "$ConfigDrive\prowlarr",
    "$ConfigDrive\sonarr",
    "$ConfigDrive\radarr",
    "$ConfigDrive\overseerr",
    "$ConfigDrive\stash\config",
    "$ConfigDrive\stash\metadata",
    "$ConfigDrive\stash\cache",
    "$ConfigDrive\metube",

    # Unified *arr + Plex media root (same drive for atomic moves & hardlinks)
    "$MediaRoot\torrents\movies",
    "$MediaRoot\torrents\tv",
    "$MediaRoot\library\movies",
    "$MediaRoot\library\tv",
    "$MediaRoot\library\home-movies",

    # Personal Movie Editing workflow (mounted via SMB on Mac)
    "$MediaRoot\editing\01_raw_imports",
    "$MediaRoot\editing\02_working_projects",
    "$MediaRoot\editing\03_ingest_ready",
    "$MediaRoot\editing\04_archived_originals",

    # Strictly isolated Private Stash library
    "$StashRoot\inbox",
    "$StashRoot\library",
    "$StashRoot\generated"
)

foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "  Created: $dir" -ForegroundColor Green
    } else {
        Write-Host "  Exists:  $dir" -ForegroundColor DarkGray
    }
}

Write-Host "`n=== 2. Hardening Windows 11 Always-On Power Settings ===" -ForegroundColor Cyan
# Disable sleep, hibernate, and hard disk spin-down timeouts on AC power
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
powercfg /change disk-timeout-ac 0
powercfg /change monitor-timeout-ac 10
Write-Host "  Sleep & hibernate disabled on AC power (monitor still sleeps after 10 min)." -ForegroundColor Green

Write-Host "`n=== 3. Optional: Enable Hyper-V for Home Assistant OS ===" -ForegroundColor Cyan
$hyperv = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
if ($hyperv.State -ne "Enabled") {
    Write-Host "  Hyper-V is NOT enabled yet. To enable it (requires reboot), run:" -ForegroundColor Yellow
    Write-Host "    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All" -ForegroundColor White
} else {
    Write-Host "  Hyper-V is already enabled!" -ForegroundColor Green
}

Write-Host "`n=== 4. Next Step: Create SMB Shares for Your Mac ===" -ForegroundColor Cyan
Write-Host "Replace YOUR_WIN_USER with your Windows account name and run:" -ForegroundColor Yellow
Write-Host @"
  # Share for Mac editing (DaVinci Resolve / LosslessCut / ingest script) + Home Movies
  New-SmbShare -Name "MediaEditing" -Path "$MediaRoot\editing" -FullAccess "YOUR_WIN_USER"
  New-SmbShare -Name "HomeMovies"   -Path "$MediaRoot\library\home-movies" -FullAccess "YOUR_WIN_USER"

  # OPTIONAL: Hidden SMB share (trailing `$ hides it from network browsing) for private Infuse PIN-locked access
  New-SmbShare -Name "StashPrivate`$" -Path "$StashRoot\library" -FullAccess "YOUR_WIN_USER"
"@ -ForegroundColor White

Write-Host "`nDone! Remember to also configure BIOS 'Restore on AC Power Loss = Power On' and set a static LAN IP / DHCP reservation for this PC." -ForegroundColor Green
