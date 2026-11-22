# ==============================================================================
# Automated Plex Media Server Configuration Script (Windows 11)
#
# What this script does:
#   1. Starts Plex Media Server if it is not already running
#   2. Reads your local Plex auth token from Windows Registry (never printed!)
#   3. Creates (or appends folders to) the Movies, TV Shows, and Home Movies
#      libraries pointing at G:\Media\library\... (never touching F:\Private)
#   4. Enables hardware transcoding (NVENC / RTX 4080), HDR tone mapping,
#      automatic partial library scans, and LAN + Tailscale local bandwidth rules
# ==============================================================================

param(
    [string]$MediaRoot = "G:\Media",
    [string]$PlexUrl   = "http://127.0.0.1:32400",
    [string]$LanSubnets = "10.0.0.0/24,100.64.0.0/10"
)

$ErrorActionPreference = "Stop"

# 1. Ensure Plex Media Server is running
Write-Host "=== 1. Checking Plex Media Server ===" -ForegroundColor Cyan
$plexExe = "C:\Program Files\Plex\Plex Media Server\Plex Media Server.exe"
$plexProc = Get-Process -Name "Plex Media Server" -ErrorAction SilentlyContinue
if (-not $plexProc) {
    if (-not (Test-Path $plexExe)) {
        throw "Plex Media Server not found at '$plexExe'. Please install Plex first."
    }
    Write-Host "  Starting Plex Media Server..." -ForegroundColor Yellow
    Start-Process -FilePath $plexExe
}

$ready = $false
for ($i = 0; $i -lt 20; $i++) {
    try {
        $null = Invoke-WebRequest -Uri "$PlexUrl/identity" -UseBasicParsing -TimeoutSec 3
        $ready = $true
        break
    } catch {
        Start-Sleep -Seconds 1
    }
}
if (-not $ready) {
    throw "Plex Media Server did not respond at $PlexUrl within 20 seconds."
}
Write-Host "  Plex Media Server is running at $PlexUrl" -ForegroundColor Green

# 2. Read local Plex token from Registry (kept private — never echoed)
Write-Host "`n=== 2. Authenticating with Local Plex Server ===" -ForegroundColor Cyan
$regPath = "HKCU:\Software\Plex, Inc.\Plex Media Server"
$token = (Get-ItemProperty -Path $regPath -Name "PlexOnlineToken" -ErrorAction SilentlyContinue).PlexOnlineToken
if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Host "  Plex is not signed in / claimed yet." -ForegroundColor Yellow
    Write-Host "  1. Open $PlexUrl/web in your browser and sign in to your Plex account." -ForegroundColor White
    Write-Host "  2. Once signed in, re-run this script!" -ForegroundColor White
    exit 1
}
$headers = @{ "X-Plex-Token" = $token }
Write-Host "  Found local Plex token (kept hidden)." -ForegroundColor Green

# Ensure target library folders exist
$desiredLibraries = @(
    @{
        Title    = "Movies"
        Type     = "movie"
        Agent    = "tv.plex.agents.movie"
        Scanner  = "Plex Movie"
        Location = "$MediaRoot\library\movies"
    },
    @{
        Title    = "TV Shows"
        Type     = "show"
        Agent    = "tv.plex.agents.series"
        Scanner  = "Plex TV Series"
        Location = "$MediaRoot\library\tv"
    },
    @{
        Title    = "Home Movies"
        Type     = "movie"
        Agent    = "com.plexapp.agents.none"
        Scanner  = "Plex Video Files Scanner"
        Location = "$MediaRoot\library\home-movies"
    }
)

foreach ($lib in $desiredLibraries) {
    if (-not (Test-Path $lib.Location)) {
        New-Item -ItemType Directory -Path $lib.Location -Force | Out-Null
    }
}

# 3. Create or update Plex libraries
Write-Host "`n=== 3. Configuring Plex Libraries ===" -ForegroundColor Cyan
[xml]$sectionsXml = (Invoke-WebRequest -Uri "$PlexUrl/library/sections" -Headers $headers -UseBasicParsing).Content
$existingSections = @()
if ($sectionsXml.MediaContainer.Directory) {
    $existingSections = @($sectionsXml.MediaContainer.Directory)
}

foreach ($lib in $desiredLibraries) {
    $normTarget = $lib.Location.TrimEnd('\').ToLowerInvariant()

    # Check if any existing library already includes this exact path
    $alreadyHasPath = $existingSections | Where-Object {
        @($_.Location) | Where-Object { $_.path -and $_.path.TrimEnd('\').ToLowerInvariant() -eq $normTarget }
    } | Select-Object -First 1

    if ($alreadyHasPath) {
        Write-Host "  Exists:  '$($alreadyHasPath.title)' already includes $($lib.Location)" -ForegroundColor DarkGray
        continue
    }

    # Check if a library with the same title already exists (preserve its current folders and append ours)
    $sameTitle = $existingSections | Where-Object { $_.title -ieq $lib.Title } | Select-Object -First 1
    if ($sameTitle) {
        try {
            $existingPaths = @($sameTitle.Location | ForEach-Object { $_.path } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $allPaths = $existingPaths + $lib.Location
            $putParts = @("agent=" + [Uri]::EscapeDataString($sameTitle.agent)) + ($allPaths | ForEach-Object { "location=" + [Uri]::EscapeDataString($_) })
            $putUrl = "$PlexUrl/library/sections/$($sameTitle.key)?" + ($putParts -join "&")
            Invoke-WebRequest -Uri $putUrl -Method Put -Headers $headers -UseBasicParsing | Out-Null
            Write-Host "  Updated: Added $($lib.Location) to existing '$($sameTitle.title)' library" -ForegroundColor Green
        } catch {
            Write-Host "  Warning: Could not update existing '$($sameTitle.title)' library: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        continue
    }

    # Create new library
    try {
        $queryParts = @(
            "name="     + [Uri]::EscapeDataString($lib.Title),
            "type="     + [Uri]::EscapeDataString($lib.Type),
            "agent="    + [Uri]::EscapeDataString($lib.Agent),
            "scanner="  + [Uri]::EscapeDataString($lib.Scanner),
            "language=en-US",
            "location=" + [Uri]::EscapeDataString($lib.Location)
        )
        $postUrl = "$PlexUrl/library/sections?" + ($queryParts -join "&")
        Invoke-WebRequest -Uri $postUrl -Method Post -Headers $headers -UseBasicParsing | Out-Null
        Write-Host "  Created: '$($lib.Title)' -> $($lib.Location)" -ForegroundColor Green
    } catch {
        if ($lib.Agent -eq "com.plexapp.agents.none") {
            # Fallback for newer PMS builds that use tv.plex.agents.none / Plex Video Files
            try {
                $fallbackParts = @(
                    "name="     + [Uri]::EscapeDataString($lib.Title),
                    "type="     + [Uri]::EscapeDataString($lib.Type),
                    "agent="    + [Uri]::EscapeDataString("tv.plex.agents.none"),
                    "scanner="  + [Uri]::EscapeDataString("Plex Video Files"),
                    "language=en-US",
                    "location=" + [Uri]::EscapeDataString($lib.Location)
                )
                $fallbackUrl = "$PlexUrl/library/sections?" + ($fallbackParts -join "&")
                Invoke-WebRequest -Uri $fallbackUrl -Method Post -Headers $headers -UseBasicParsing | Out-Null
                Write-Host "  Created: '$($lib.Title)' -> $($lib.Location)" -ForegroundColor Green
                continue
            } catch {
                Write-Host "  Warning: Could not create '$($lib.Title)' library: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  Warning: Could not create '$($lib.Title)' library: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# Print final library summary & verify isolation
[xml]$finalSectionsXml = (Invoke-WebRequest -Uri "$PlexUrl/library/sections" -Headers $headers -UseBasicParsing).Content
Write-Host "`n  Active Plex Libraries:" -ForegroundColor White
foreach ($sec in @($finalSectionsXml.MediaContainer.Directory)) {
    $paths = (@($sec.Location) | ForEach-Object { $_.path }) -join ", "
    Write-Host "    - $($sec.title) ($($sec.type)): $paths" -ForegroundColor Gray
    if ($paths -match "(?i)stash|\\Private") {
        Write-Host "      WARNING: Private/Stash path detected in Plex! Remove it immediately." -ForegroundColor Red
    }
}

# 4. Configure Transcoder (RTX 4080 NVENC), Auto-Scan, and Local Subnets
Write-Host "`n=== 4. Configuring Hardware Transcoding & Server Preferences ===" -ForegroundColor Cyan
[xml]$prefsXml = (Invoke-WebRequest -Uri "$PlexUrl/:/prefs" -Headers $headers -UseBasicParsing).Content
$availableSettings = @{}
foreach ($s in @($prefsXml.MediaContainer.Setting)) {
    if ($s.id) {
        $availableSettings[$s.id.ToLowerInvariant()] = $s
    }
}

$desiredPrefs = [ordered]@{
    "HardwareAcceleratedCodecs"        = "1"
    "HardwareAcceleratedEncoders"      = "1"
    "TranscoderToneMapping"            = "1"
    "FSEventLibraryUpdatesEnabled"     = "1"
    "FSEventLibraryPartialScanEnabled" = "1"
    "LanNetworks"                      = $LanSubnets
}

# Auto-select NVIDIA / RTX GPU if HardwareDevicePath exposes it in enumValues
if ($availableSettings.ContainsKey("hardwaredevicepath")) {
    $hwSetting = $availableSettings["hardwaredevicepath"]
    if ($hwSetting.enumValues) {
        $nvidiaOpt = ($hwSetting.enumValues -split '\|') | Where-Object { $_ -match "(?i)NVIDIA|RTX|GeForce" } | Select-Object -First 1
        if ($nvidiaOpt) {
            $gpuKey = ($nvidiaOpt -split ':(?=[^:]*$)')[0]
            $desiredPrefs["HardwareDevicePath"] = $gpuKey
            Write-Host "  Detected GPU option: $nvidiaOpt" -ForegroundColor Green
        }
    }
}

$prefQueryParts = @()
foreach ($k in $desiredPrefs.Keys) {
    $lk = $k.ToLowerInvariant()
    if ($availableSettings.ContainsKey($lk)) {
        $exactId = $availableSettings[$lk].id
        $val = $desiredPrefs[$k]
        $prefQueryParts += "$exactId=" + [Uri]::EscapeDataString($val)
        Write-Host "  Set $exactId = $val" -ForegroundColor Green
    } else {
        Write-Host "  Skipped (not present on this PMS version): $k" -ForegroundColor DarkGray
    }
}

if ($prefQueryParts.Count -gt 0) {
    $prefsPutUrl = "$PlexUrl/:/prefs?" + ($prefQueryParts -join "&")
    Invoke-WebRequest -Uri $prefsPutUrl -Method Put -Headers $headers -UseBasicParsing | Out-Null
}

Write-Host "`nPlex configuration complete! (Note: Hardware transcoding requires an active Plex Pass.)" -ForegroundColor Green
