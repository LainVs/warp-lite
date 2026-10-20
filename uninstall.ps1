#Requires -Version 5.1
<#
    warp-lite uninstaller.
    Usage: powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 [-Prefix <dir>] [-KeepConfig]
#>
[CmdletBinding()]
param(
    [string]$Prefix = (Join-Path $env:LOCALAPPDATA 'warp-lite'),
    [switch]$KeepConfig
)

$ErrorActionPreference = 'SilentlyContinue'
function Say([string]$m) { Write-Host "[*] $m" -ForegroundColor Cyan }
function Ok([string]$m) { Write-Host "[+] $m" -ForegroundColor Green }

$Prefix = [IO.Path]::GetFullPath($Prefix)
if (-not (Test-Path $Prefix)) { Ok "Nothing to remove: $Prefix"; exit 0 }

$cfg = $null
$cfgPath = Join-Path $Prefix 'config.json'
if (Test-Path $cfgPath) { $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json }

Say 'Stopping processes...'
Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -and $_.CommandLine.Contains($Prefix)
} | ForEach-Object {
    if ($_.Name -match 'mihomo|usque|powershell|wscript') {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

# fall back to port-based cleanup
if ($cfg) {
    Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq 'usque.exe' -and $_.CommandLine -and $_.CommandLine.Contains("-p $($cfg.socksPort)")
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

Say 'Removing autostart entry...'
$startup = [Environment]::GetFolderPath('Startup')
if ($startup) {
    Remove-Item (Join-Path $startup 'warp-lite-watchdog.vbs') -Force -ErrorAction SilentlyContinue
}

if ($cfg) {
    Say 'Removing firewall rule...'
    Remove-NetFirewallRule -DisplayName ("warp-lite {0}" -f $cfg.port) -ErrorAction SilentlyContinue
}

if ($KeepConfig) {
    Ok "Processes stopped. Config kept at $Prefix"
    exit 0
}

Say 'Removing files...'
Remove-Item $Prefix -Recurse -Force -ErrorAction SilentlyContinue
Ok 'warp-lite removed.'
