# ==============================================================================
# Home Assistant Entity Discovery Script (Read-Only, Token Kept Private)
#
# Queries your local Home Assistant OS (http://10.0.0.72:8123) and prints a
# clean list of your Apple TVs, Plex players, TVs/AVRs, and Lights so we can
# generate an exact multi-room Siri voice automation package with zero guesswork.
# ==============================================================================

param(
    [string]$HaUrl = "http://10.0.0.72:8123"
)

$ErrorActionPreference = "Stop"

$tokenFile = Join-Path $env:USERPROFILE ".media_stack_ha_token.dpapi"
$token = $null

if (Test-Path $tokenFile) {
    try {
        $sec = Get-Content $tokenFile -Raw | ConvertTo-SecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    } catch {
        $token = $null
    }
}

if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Host "Paste your Home Assistant Long-Lived Access Token (input is hidden, saved encrypted locally):" -ForegroundColor Cyan
    $sec = Read-Host "HA Token" -AsSecureString
    $sec | ConvertFrom-SecureString | Set-Content -Path $tokenFile -Force
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}

try {
    $states = Invoke-RestMethod -Uri "$HaUrl/api/states" -Headers $headers -TimeoutSec 15
} catch {
    # Clear saved token if unauthorized so next run re-prompts cleanly
    if ($_.Exception.Message -match "401") {
        Remove-Item $tokenFile -Force -ErrorAction SilentlyContinue
        throw "Home Assistant returned 401 Unauthorized. Saved token cleared — re-run and paste a valid Long-Lived Access Token."
    }
    throw
}

Write-Host "`n=== MEDIA PLAYERS (Apple TVs, Plex, TVs/AVRs, HomePods) ===" -ForegroundColor Cyan
$states | Where-Object { $_.entity_id -like "media_player.*" } |
    Select-Object entity_id, state, @{N='friendly_name';E={$_.attributes.friendly_name}} |
    Sort-Object entity_id | Format-Table -AutoSize

Write-Host "=== REMOTES (Apple TV Remotes) ===" -ForegroundColor Cyan
$states | Where-Object { $_.entity_id -like "remote.*" } |
    Select-Object entity_id, state, @{N='friendly_name';E={$_.attributes.friendly_name}} |
    Sort-Object entity_id | Format-Table -AutoSize

Write-Host "=== LIGHTS ===" -ForegroundColor Cyan
$states | Where-Object { $_.entity_id -like "light.*" } |
    Select-Object entity_id, state, @{N='friendly_name';E={$_.attributes.friendly_name}} |
    Sort-Object entity_id | Format-Table -AutoSize

Write-Host "Copy & paste the tables above back into chat (your token was NOT printed)." -ForegroundColor Green
