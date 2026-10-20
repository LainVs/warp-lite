#Requires -Version 5.1
# warp-lite watchdog: checks every 60 seconds and restarts dead services.
$ErrorActionPreference = 'SilentlyContinue'
$Prefix = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $Prefix 'logs\watchdog.log'
New-Item -ItemType Directory -Force -Path (Join-Path $Prefix 'logs') | Out-Null

Add-Content -Path $log -Value ("{0} watchdog started" -f (Get-Date -Format 's'))
while ($true) {
    try {
        & (Join-Path $Prefix 'warpctl.ps1') ensure
    } catch {
        Add-Content -Path $log -Value ("{0} ensure error: {1}" -f (Get-Date -Format 's'), $_.Exception.Message)
    }
    Start-Sleep -Seconds 60
}
