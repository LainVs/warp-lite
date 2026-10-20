#Requires -Version 5.1
<#
.SYNOPSIS
    warp-lite one-click installer for Windows 10/11.

.DESCRIPTION
    Downloads usque + mihomo, registers a free Cloudflare WARP account,
    writes a local HTTP/SOCKS proxy front-end, adds autostart and starts it.

.PARAMETER Prefix
    Install directory. Default: %LOCALAPPDATA%\warp-lite

.PARAMETER Port
    Local HTTP/SOCKS mixed proxy port. Default: 17894

.PARAMETER SocksPort
    Internal SOCKS5 port used by usque. Default: 17896

.PARAMETER CtrlPort
    mihomo external controller port (localhost only). Default: 17895

.PARAMETER Lan
    Listen on all interfaces (for phone/tablet sharing).

.PARAMETER Mirror
    GitHub download mirror prefix, e.g. https://ghproxy.net/

.PARAMETER NoAutostart
    Do not create the startup entry.
#>
[CmdletBinding()]
param(
    [string]$Prefix = (Join-Path $env:LOCALAPPDATA 'warp-lite'),
    [int]$Port = 17894,
    [int]$SocksPort = 17896,
    [int]$CtrlPort = 17895,
    [string]$Username = 'warp',
    [string]$Password = '',
    [switch]$Lan,
    [switch]$NoAutostart,
    [string]$Mirror = '',
    [string]$UsquePath = '',
    [string]$MihomoPath = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

function Say([string]$m, [string]$c = 'Cyan') { Write-Host "[*] $m" -ForegroundColor $c }
function Ok([string]$m) { Write-Host "[+] $m" -ForegroundColor Green }
function Warn([string]$m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function Fail([string]$m) { Write-Host "[x] $m" -ForegroundColor Red; exit 1 }

# ------------------------------------------------------------------ validate
foreach ($pair in @(@('Port', $Port), @('SocksPort', $SocksPort), @('CtrlPort', $CtrlPort))) {
    $v = [int]$pair[1]
    if ($v -lt 1 -or $v -gt 65535) { Fail "$($pair[0]) must be 1-65535" }
}
if (($Port -eq $SocksPort) -or ($Port -eq $CtrlPort) -or ($SocksPort -eq $CtrlPort)) {
    Fail 'Port / SocksPort / CtrlPort must be different.'
}

if ([string]::IsNullOrWhiteSpace($Password)) {
    $chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    $Password = -join (1..18 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}
$secret = -join (1..24 | ForEach-Object { 'abcdefghijklmnopqrstuvwxyz0123456789'[(Get-Random -Maximum 36)] })

$Prefix = [IO.Path]::GetFullPath($Prefix)
$binDir = Join-Path $Prefix 'bin'
$usqueDir = Join-Path $Prefix 'usque'
$logDir = Join-Path $Prefix 'logs'
foreach ($d in @($Prefix, $binDir, $usqueDir, $logDir)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

Say "Install directory: $Prefix"

# ------------------------------------------------------------------ download
function Download-File([string]$url, [string]$out) {
    $urls = @()
    if ($Mirror) { $urls += ($Mirror.TrimEnd('/') + '/' + $url) }
    $urls += $url
    foreach ($u in $urls) {
        try {
            Write-Host "    GET $u" -ForegroundColor DarkGray
            Invoke-WebRequest -Uri $u -OutFile $out -UseBasicParsing -TimeoutSec 300
            return $true
        } catch {
            Write-Host "    failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }
    return $false
}

function Get-GitHubAssetUrl([string]$repo, [string]$pattern) {
    try {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" `
            -UseBasicParsing -TimeoutSec 60 -Headers @{ 'User-Agent' = 'warp-lite-installer' }
        $asset = $rel.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
        if ($asset) { return $asset.browser_download_url }
    } catch { }
    return $null
}

function Extract-Exe([string]$zip, [string]$name, [string]$dest) {
    $tmp = Join-Path $env:TEMP ('warp-lite-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $exe = Get-ChildItem -Path $tmp -Recurse -File -Filter $name | Select-Object -First 1
    if (-not $exe) { Fail "$name not found inside $zip" }
    Copy-Item $exe.FullName $dest -Force
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# usque
$usqueExe = Join-Path $binDir 'usque.exe'
if ($UsquePath) {
    Copy-Item $UsquePath $usqueExe -Force
    Ok 'usque.exe copied from local path'
} elseif (Test-Path $usqueExe) {
    Ok 'usque.exe already present'
} else {
    Say 'Downloading usque...'
    $zip = Join-Path $env:TEMP 'warp-lite-usque.zip'
    $url = Get-GitHubAssetUrl 'Dinboy1123/usque' 'windows_amd64\.zip'
    if (-not $url) { $url = 'https://github.com/Diniboy1123/usque/releases/download/v4.2.1/usque_4.2.1_windows_amd64.zip' }
    if (-not (Download-File $url $zip)) { Fail 'Failed to download usque. Use -UsquePath or -Mirror.' }
    Extract-Exe $zip 'usque.exe' $usqueExe
    Ok 'usque.exe installed'
}

# mihomo
$mihomoExe = Join-Path $binDir 'mihomo.exe'
if ($MihomoPath) {
    Copy-Item $MihomoPath $mihomoExe -Force
    Ok 'mihomo.exe copied from local path'
} elseif (Test-Path $mihomoExe) {
    Ok 'mihomo.exe already present'
} else {
    Say 'Downloading mihomo...'
    $zip = Join-Path $env:TEMP 'warp-lite-mihomo.zip'
    $url = Get-GitHubAssetUrl 'MetaCubeX/mihomo' '^mihomo-windows-amd64-v[\d.]+\.zip$'
    if (-not $url) { $url = 'https://github.com/MetaCubeX/mihomo/releases/download/v1.19.32/mihomo-windows-amd64-v1.19.32.zip' }
    if (-not (Download-File $url $zip)) { Fail 'Failed to download mihomo. Use -MihomoPath or -Mirror.' }
    Extract-Exe $zip 'mihomo.exe' $mihomoExe
    Ok 'mihomo.exe installed'
}

# ------------------------------------------------------------------ register
$usqueConfig = Join-Path $usqueDir 'config.json'
if (-not (Test-Path $usqueConfig)) {
    Say 'Registering a free Cloudflare WARP account...'
    $registerLog = Join-Path $logDir 'register.log'
    Push-Location $usqueDir
    try {
        & $usqueExe register -a -n warp-lite *> $registerLog
        $code = $LASTEXITCODE
    } catch {
        $code = 1
        $_ | Out-String | Add-Content -Path $registerLog
    }
    Pop-Location
    if ($code -ne 0 -or -not (Test-Path $usqueConfig)) {
        Get-Content $registerLog -ErrorAction SilentlyContinue | Select-Object -Last 20 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkYellow }
        Fail 'WARP registration failed. Check network, or rerun with a working proxy.'
    }
    Ok 'WARP account registered'
} else {
    Ok 'Existing WARP account found, reusing'
}

# ------------------------------------------------------------------ config
$allowLan = if ($Lan) { 'true' } else { 'false' }
$warpYaml = @"
mixed-port: $Port
external-controller: 127.0.0.1:$CtrlPort
secret: "$secret"
allow-lan: $allowLan
bind-address: "*"
authentication:
  - "${Username}:${Password}"
mode: rule
log-level: info
ipv6: false
profile:
  store-selected: true
dns:
  enable: true
  ipv6: false
  enhanced-mode: normal
  use-system-hosts: true
  nameserver:
    - https://1.1.1.1/dns-query
  direct-nameserver:
    - 223.5.5.5
    - 119.29.29.29
proxies:
  - name: WARP
    type: socks5
    server: 127.0.0.1
    port: $SocksPort
    udp: true
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - WARP
      - DIRECT
rules:
  - MATCH,PROXY
"@
Set-Content -Path (Join-Path $Prefix 'warp.yaml') -Value $warpYaml -Encoding UTF8

$config = [ordered]@{
    version    = 1
    prefix     = $Prefix
    port       = $Port
    socksPort  = $SocksPort
    ctrlPort   = $CtrlPort
    secret     = $secret
    username   = $Username
    password   = $Password
    lan        = [bool]$Lan
}
$config | ConvertTo-Json | Set-Content -Path (Join-Path $Prefix 'config.json') -Encoding UTF8

# copy runtime scripts
foreach ($name in @('warpctl.ps1', 'watchdog.ps1')) {
    $src = Join-Path $PSScriptRoot ('src\' + $name)
    if (Test-Path $src) { Copy-Item $src (Join-Path $Prefix $name) -Force }
}
if (-not (Test-Path (Join-Path $Prefix 'warpctl.ps1'))) {
    Warn 'warpctl.ps1 not found in src\, runtime control will be limited.'
}

# launchers
$vbs = @"
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$Prefix\warpctl.ps1"" start", 0, False
"@
Set-Content -Path (Join-Path $Prefix 'start-warp.vbs') -Value $vbs -Encoding ASCII

$vbsWatch = @"
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$Prefix\watchdog.ps1""", 0, False
"@
Set-Content -Path (Join-Path $Prefix 'watchdog.vbs') -Value $vbsWatch -Encoding ASCII

$bat = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0warpctl.ps1`" %*`r`n"
Set-Content -Path (Join-Path $Prefix 'warpctl.bat') -Value $bat -Encoding ASCII
$batStop = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0warpctl.ps1`" stop`r`npause`r`n"
Set-Content -Path (Join-Path $Prefix 'stop-warp.bat') -Value $batStop -Encoding ASCII
$batRestart = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0warpctl.ps1`" restart`r`npause`r`n"
Set-Content -Path (Join-Path $Prefix 'restart-warp.bat') -Value $batRestart -Encoding ASCII

# autostart
if (-not $NoAutostart) {
    $startup = [Environment]::GetFolderPath('Startup')
    if ($startup) {
        Copy-Item (Join-Path $Prefix 'watchdog.vbs') (Join-Path $startup 'warp-lite-watchdog.vbs') -Force
        Ok 'Autostart entry installed'
    }
}

# start
if (Test-Path (Join-Path $Prefix 'warpctl.ps1')) {
    Say 'Starting services...'
    & (Join-Path $Prefix 'warpctl.ps1') start
} else {
    Warn 'Skip auto-start: warpctl.ps1 missing.'
}

Write-Host ''
Ok 'warp-lite installed.'
Write-Host "    Proxy : http://127.0.0.1:$Port  (HTTP / SOCKS5)"
Write-Host "    User  : $Username"
Write-Host "    Pass  : $Password"
Write-Host "    Dir   : $Prefix"
Write-Host ''
Write-Host "    Status: $Prefix\warpctl.bat status"
Write-Host "    Test  : $Prefix\warpctl.bat test"
Write-Host ''
