#Requires -Version 5.1
<#
    warp-lite control script.
    Usage: warpctl.ps1 [status|start|stop|restart|test|ensure|lan|creds]
#>
param(
    [Parameter(Position = 0)]
    [string]$Command = 'status',
    [Parameter(Position = 1)]
    [string]$Value = ''
)

$ErrorActionPreference = 'SilentlyContinue'
$Prefix = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfgPath = Join-Path $Prefix 'config.json'
if (-not (Test-Path $cfgPath)) {
    Write-Host 'config.json not found. Run install.ps1 first.' -ForegroundColor Red
    exit 1
}
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json

$usqueExe = Join-Path $Prefix 'bin\usque.exe'
$mihomoExe = Join-Path $Prefix 'bin\mihomo.exe'
$warpYaml = Join-Path $Prefix 'warp.yaml'
$usqueDir = Join-Path $Prefix 'usque'
$logDir = Join-Path $Prefix 'logs'
$failFile = Join-Path $logDir 'usque_fail.txt'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function PortOpen([int]$port) {
    $c = New-Object Net.Sockets.TcpClient
    try {
        $iar = $c.BeginConnect('127.0.0.1', $port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(600)) { return $false }
        $c.EndConnect($iar)
        return $true
    } catch { return $false } finally { $c.Close() }
}

function Start-Usque {
    if (PortOpen $cfg.socksPort) { return }
    Start-Process -FilePath $usqueExe `
        -ArgumentList @('socks', '-b', '127.0.0.1', '-p', "$($cfg.socksPort)", '-m', '1280', '-k', '25s', '--always-reconnect') `
        -WorkingDirectory $usqueDir -WindowStyle Hidden
    Start-Sleep -Seconds 2
}

function Start-Mihomo {
    if (PortOpen $cfg.port) { return }
    Start-Process -FilePath $mihomoExe -ArgumentList @('-d', $Prefix, '-f', $warpYaml) -WindowStyle Hidden
    Start-Sleep -Seconds 2
}

function Stop-Usque {
    Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq 'usque.exe' -and $_.CommandLine -and $_.CommandLine.Contains("-p $($cfg.socksPort)")
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
}

function Stop-Mihomo {
    Get-CimInstance Win32_Process | Where-Object {
        $_.Name -eq 'mihomo.exe' -and $_.CommandLine -and $_.CommandLine.Contains($Prefix)
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
}

function Start-Watchdog {
    $exists = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -match 'powershell' -and $_.CommandLine -and $_.CommandLine.Contains('watchdog.ps1') -and $_.CommandLine.Contains($Prefix)
    }
    if (-not $exists) {
        Start-Process -FilePath 'wscript.exe' -ArgumentList @((Join-Path $Prefix 'watchdog.vbs')) -WindowStyle Hidden
    }
}

function Stop-Watchdog {
    Get-CimInstance Win32_Process | Where-Object {
        $_.Name -match 'powershell' -and $_.CommandLine -and $_.CommandLine.Contains('watchdog.ps1') -and $_.CommandLine.Contains($Prefix)
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
}

function Get-Delay {
    try {
        $u = [uri]::EscapeDataString('http://cp.cloudflare.com/generate_204')
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$($cfg.ctrlPort)/proxies/WARP/delay?url=$u&timeout=5000" `
            -Headers @{ Authorization = "Bearer $($cfg.secret)" } -TimeoutSec 10
        return [int]$r.delay
    } catch { return 0 }
}

function Show-Status {
    $m = PortOpen $cfg.port
    $s = PortOpen $cfg.socksPort
    $d = if ($m) { Get-Delay } else { 0 }
    Write-Host ''
    Write-Host '  warp-lite status' -ForegroundColor Cyan
    Write-Host '  ------------------------------------------'
    Write-Host ("  front-end : 127.0.0.1:{0}  {1}" -f $cfg.port, $(if ($m) { 'UP' } else { 'DOWN' })) -ForegroundColor $(if ($m) { 'Green' } else { 'Red' })
    Write-Host ("  usque     : 127.0.0.1:{0}  {1}" -f $cfg.socksPort, $(if ($s) { 'UP' } else { 'DOWN' })) -ForegroundColor $(if ($s) { 'Green' } else { 'Red' })
    Write-Host ("  health    : {0}" -f $(if ($d -gt 0) { "$d ms" } else { 'FAILED' })) -ForegroundColor $(if ($d -gt 0) { 'Green' } else { 'Red' })
    Write-Host ("  proxy     : http://127.0.0.1:{0}" -f $cfg.port)
    Write-Host ("  username  : {0}" -f $cfg.username)
    Write-Host ("  password  : {0}" -f $cfg.password)
    if ($cfg.lan) {
        $ip = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1).IPv4Address.IPAddress
        Write-Host ("  LAN       : {0}:{1}" -f $ip, $cfg.port)
    }
    Write-Host ''
}

function Test-Proxy {
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) {
        Write-Host 'curl.exe not found; use a browser with the proxy settings instead.' -ForegroundColor Yellow
        return
    }
    $proxy = "http://127.0.0.1:$($cfg.port)"
    $out = & curl.exe -sS -m 25 -x $proxy --proxy-user "$($cfg.username):$($cfg.password)" https://www.cloudflare.com/cdn-cgi/trace 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Test FAILED:' -ForegroundColor Red
        Write-Host ($out | Out-String)
        return
    }
    $ip = ($out | Where-Object { $_ -match '^ip=' })
    $warp = ($out | Where-Object { $_ -match '^warp=' })
    $colo = ($out | Where-Object { $_ -match '^colo=' })
    Write-Host 'Test OK' -ForegroundColor Green
    Write-Host ("  {0}  {1}  {2}" -f $ip, $colo, $warp)
}

function Set-Lan([bool]$on) {
    $text = Get-Content $warpYaml -Raw
    $text = [regex]::Replace($text, '(?m)^allow-lan:\s*(true|false)\s*$', ('allow-lan: ' + $(if ($on) { 'true' } else { 'false' })))
    Set-Content -Path $warpYaml -Value $text -Encoding UTF8
    $cfg.lan = $on
    $cfg | ConvertTo-Json | Set-Content -Path $cfgPath -Encoding UTF8

    Stop-Mihomo
    Start-Sleep -Milliseconds 600
    Start-Mihomo

    $ruleName = "warp-lite $($cfg.port)"
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($on) {
        if ($admin) {
            Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
            New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $cfg.port -Profile Any | Out-Null
            Write-Host 'Firewall rule added.' -ForegroundColor Green
        } else {
            Write-Host 'Run this in an elevated PowerShell to allow the port:' -ForegroundColor Yellow
            Write-Host ("  New-NetFirewallRule -DisplayName '{0}' -Direction Inbound -Action Allow -Protocol TCP -LocalPort {1} -Profile Any" -f $ruleName, $cfg.port)
        }
        $ip = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1).IPv4Address.IPAddress
        Write-Host ("LAN proxy: {0}:{1}  user={2}  pass={3}" -f $ip, $cfg.port, $cfg.username, $cfg.password) -ForegroundColor Cyan
    } else {
        if ($admin) { Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue }
        Write-Host 'LAN sharing disabled.' -ForegroundColor Green
    }
}

function Ensure {
    Start-Usque
    Start-Mihomo
    $d = Get-Delay
    $fails = 0
    if (Test-Path $failFile) { $fails = [int](Get-Content $failFile -Raw) }
    if ($d -gt 0) {
        if ($fails -ne 0) { Set-Content -Path $failFile -Value '0' -Encoding ASCII }
        return
    }
    $fails++
    Set-Content -Path $failFile -Value "$fails" -Encoding ASCII
    if ($fails -ge 2) {
        Add-Content -Path (Join-Path $logDir 'watchdog.log') -Value ("{0} restart usque (health failed)" -f (Get-Date -Format 's'))
        Stop-Usque
        Start-Sleep -Seconds 1
        Start-Usque
        Set-Content -Path $failFile -Value '0' -Encoding ASCII
    }
}

switch ($Command.ToLower()) {
    'start' {
        Start-Usque
        Start-Mihomo
        Start-Watchdog
        Start-Sleep -Seconds 2
        Show-Status
    }
    'stop' {
        Stop-Watchdog
        Stop-Mihomo
        Stop-Usque
        Write-Host 'warp-lite stopped.' -ForegroundColor Green
    }
    'restart' {
        Stop-Watchdog
        Stop-Mihomo
        Stop-Usque
        Start-Sleep -Seconds 1
        Start-Usque
        Start-Mihomo
        Start-Watchdog
        Start-Sleep -Seconds 2
        Show-Status
    }
    'status' { Show-Status }
    'test' { Test-Proxy }
    'ensure' { Ensure }
    'creds' {
        Write-Host ("http://127.0.0.1:{0}" -f $cfg.port)
        Write-Host ("user: {0}" -f $cfg.username)
        Write-Host ("pass: {0}" -f $cfg.password)
    }
    'lan' {
        if ($Value -eq 'on') { Set-Lan $true }
        elseif ($Value -eq 'off') { Set-Lan $false }
        else { Write-Host 'Usage: warpctl.ps1 lan on|off' -ForegroundColor Yellow }
    }
    default {
        Write-Host 'Usage: warpctl.ps1 [status|start|stop|restart|test|ensure|lan on|lan off|creds]' -ForegroundColor Yellow
    }
}
