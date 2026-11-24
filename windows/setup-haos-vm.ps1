# ==============================================================================
# Automated Home Assistant OS (Hyper-V Bridged VM) Setup Script — Windows 11 Pro
# Run in an elevated PowerShell (Run as Administrator)
#
# What this script does:
#   1. Creates (or reuses) a Bridged External Hyper-V Virtual Switch on your LAN
#      adapter so mDNS, Apple TV (pyatv), HomeKit Bridge, and smart lights work
#   2. Downloads & extracts the latest stable HAOS Hyper-V VHDX to E:\MediaStack\haos
#   3. Creates a Gen 2 VM (4 GB RAM, 2 vCPUs, Secure Boot OFF, auto-start ON)
#   4. Boots Home Assistant OS and prints its LAN URL (http://<HA_IP>:8123)
# ==============================================================================

param(
    [string]$VmName         = "HomeAssistant",
    [string]$VmDir          = "E:\MediaStack\haos",
    [string]$SwitchName     = "MediaStack-Bridged",
    [string]$NetAdapterName = "LadyJustice",
    [int]$MemoryGB          = 2,
    [int]$CpuCount          = 2
)

$ErrorActionPreference = "Stop"

# Verify Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "Please run this script in PowerShell as Administrator."
}

# 1. Ensure Bridged External Virtual Switch exists
Write-Host "=== 1. Configuring Bridged Hyper-V Virtual Switch ===" -ForegroundColor Cyan
$existingExt = Get-VMSwitch | Where-Object { $_.SwitchType -eq "External" } | Select-Object -First 1
if ($existingExt) {
    $useSwitch = $existingExt.Name
    Write-Host "  Reusing existing External switch: '$useSwitch'" -ForegroundColor Green
} else {
    $adapter = Get-NetAdapter -Name $NetAdapterName -ErrorAction SilentlyContinue
    if (-not $adapter) {
        $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -notmatch "Hyper-V|Tailscale|Virtual|Loopback|WSL" } | Select-Object -First 1
    }
    if (-not $adapter) {
        throw "Could not find an active physical LAN adapter. Pass -NetAdapterName '<AdapterName>'."
    }
    Write-Host "  Creating External switch '$SwitchName' on adapter '$($adapter.Name)' (brief 2-3s network blip is normal)..." -ForegroundColor Yellow
    New-VMSwitch -Name $SwitchName -NetAdapterName $adapter.Name -AllowManagementOS $true | Out-Null
    $useSwitch = $SwitchName
    Write-Host "  Created External switch: '$useSwitch'" -ForegroundColor Green
}

# 2. Download & extract latest stable HAOS VHDX
Write-Host "`n=== 2. Preparing Home Assistant OS VHDX ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Path $VmDir -Force | Out-Null
$vhdxPath = Join-Path $VmDir "haos.vhdx"

if (Test-Path $vhdxPath) {
    Write-Host "  Exists:  $vhdxPath" -ForegroundColor DarkGray
} else {
    $fallbackUrl = "https://github.com/home-assistant/operating-system/releases/download/18.4/haos_ova-18.4.vhdx.zip"
    $downloadUrl = $fallbackUrl
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/home-assistant/operating-system/releases?per_page=15" -Headers @{ "User-Agent" = "media-stack-setup" } -TimeoutSec 15
        foreach ($rel in $releases) {
            if ($rel.prerelease) { continue }
            $asset = $rel.assets | Where-Object { $_.name -match '^haos_ova-.*\.vhdx\.zip$' } | Select-Object -First 1
            if ($asset) {
                $downloadUrl = $asset.browser_download_url
                Write-Host "  Found latest stable HAOS release: $($rel.tag_name) ($($asset.name))" -ForegroundColor Green
                break
            }
        }
    } catch {
        Write-Host "  Using fallback HAOS URL (GitHub API lookup skipped: $($_.Exception.Message))" -ForegroundColor Yellow
    }

    $zipPath = Join-Path $VmDir "haos.vhdx.zip"
    Write-Host "  Downloading $downloadUrl ..." -ForegroundColor Yellow
    & curl.exe -fL --progress-bar -o $zipPath $downloadUrl
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to download HAOS image from $downloadUrl"
    }

    Write-Host "  Extracting VHDX (takes ~15-30 seconds)..." -ForegroundColor Yellow
    $extractDir = Join-Path $VmDir "extract_tmp"
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
    $extractedVhdx = Get-ChildItem -Path $extractDir -Filter "*.vhdx" -Recurse | Select-Object -First 1
    if (-not $extractedVhdx) {
        throw "No .vhdx file found inside $zipPath"
    }
    Move-Item -Path $extractedVhdx.FullName -Destination $vhdxPath -Force
    Remove-Item $extractDir -Recurse -Force
    Remove-Item $zipPath -Force
    Write-Host "  Extracted: $vhdxPath" -ForegroundColor Green
}

# 3. Create & configure Hyper-V VM
Write-Host "`n=== 3. Creating & Starting Hyper-V VM '$VmName' ===" -ForegroundColor Cyan
$vm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
if (-not $vm) {
    $memBytes = [int64]$MemoryGB * 1GB
    New-VM -Name $VmName -MemoryStartupBytes $memBytes -Generation 2 -VHDPath $vhdxPath -SwitchName $useSwitch | Out-Null
    Set-VMProcessor -VMName $VmName -Count $CpuCount
    Set-VMMemory -VMName $VmName -DynamicMemoryEnabled $false
    Set-VMFirmware -VMName $VmName -EnableSecureBoot Off
    Set-VM -VMName $VmName -AutomaticStartAction Start -AutomaticStartDelay 15 -AutomaticStopAction ShutDown -CheckpointType Disabled
    Write-Host "  Created VM '$VmName' (Gen 2, ${MemoryGB}GB RAM, ${CpuCount} vCPUs, Secure Boot OFF, Switch='$useSwitch')" -ForegroundColor Green
    $vm = Get-VM -Name $VmName
} else {
    Write-Host "  VM '$VmName' already exists (State: $($vm.State))" -ForegroundColor DarkGray
}

if ($vm.State -ne "Running") {
    Start-VM -Name $VmName
    Write-Host "  Started VM '$VmName'." -ForegroundColor Green
}

# 4. Wait for HAOS to acquire a LAN IP
Write-Host "`n=== 4. Waiting for Home Assistant OS LAN IP (first boot takes ~1-2 min) ===" -ForegroundColor Cyan
$haIp = $null
for ($i = 0; $i -lt 45; $i++) {
    $ips = (Get-VMNetworkAdapter -VMName $VmName).IPAddresses
    $haIp = $ips | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^169\.254\.' } | Select-Object -First 1
    if ($haIp) { break }
    Start-Sleep -Seconds 2
}

if ($haIp) {
    Write-Host "  Home Assistant OS LAN IP: $haIp" -ForegroundColor Green
    Write-Host "  Open in your browser: http://${haIp}:8123  (or http://homeassistant.local:8123)" -ForegroundColor Cyan
} else {
    Write-Host "  VM is still booting (normal on first start). Try http://homeassistant.local:8123 in ~1 minute," -ForegroundColor Yellow
    Write-Host "  or check its IP with: (Get-VMNetworkAdapter -VMName HomeAssistant).IPAddresses" -ForegroundColor White
}
