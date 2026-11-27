<#
    Mars Community 2 - update WITHOUT restarting the server.
    1. downloads the developer's changes (git pull)
    2. applies patches
    3. restarts only the scripts that changed, live, through the remote console
    Some changes (items list, core scripts, server.cfg) still need a full restart;
    the script says so.
    Run with hot-update.bat while the server is running.
#>
$ErrorActionPreference = 'Continue'
$Root    = Split-Path -Parent $PSScriptRoot
$Data    = Join-Path $Root 'server-data'
$Res     = Join-Path $Data 'resources'
$Secrets = Join-Path $Data 'secrets.cfg'
Set-Location $Root

# scripts that cannot be restarted live (everything depends on them)
$CoreOnly = @('mars_identity', 'oxmysql', 'ox_lib', 'qbx_core', 'ox_inventory', 'ox_target', 'pma-voice', 'npwd')

# ---------- git ----------
$git = 'git'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    foreach ($d in 'D', 'E', 'F', 'C') {
        foreach ($p in "${d}:\Git\cmd\git.exe", "${d}:\PortableGit\cmd\git.exe") { if (Test-Path $p) { $git = $p } }
    }
}
$before = (& $git rev-parse HEAD).Trim()
Write-Host 'Downloading the latest changes from the developer...' -ForegroundColor Cyan
& $git pull
if ($LASTEXITCODE -ne 0) { Write-Host "`nUPDATE FAILED - send a screenshot to the developer." -ForegroundColor Red; exit 1 }
$after = (& $git rev-parse HEAD).Trim()
$changed = @()
if ($before -ne $after) { $changed = @(& $git diff --name-only $before $after) }

# ---------- what changed ----------
$restart = New-Object System.Collections.Generic.List[string]
$full    = New-Object System.Collections.Generic.List[string]
foreach ($f in $changed) {
    $f = $f -replace '/', '\'
    if ($f -like 'server-data\resources\*') {
        $parts = @($f.Substring('server-data\resources\'.Length).Split('\') | Where-Object { $_ -notmatch '^\[.*\]$' })
        if ($parts.Count -gt 1 -and -not $restart.Contains($parts[0])) { $restart.Add($parts[0]) }
    } elseif ($f -like 'server-data\*.cfg') {
        $full.Add("settings file $([IO.Path]::GetFileName($f))")
    } elseif ($f -like 'tools\ox_items.lua') {
        $full.Add('item list (new or changed items)')
    }
}

# patches (may touch downloaded scripts)
$global:MarsPatchedResources = @()
. (Join-Path $PSScriptRoot 'patches.ps1')
foreach ($r in $global:MarsPatchedResources) { if (-not $restart.Contains($r)) { $restart.Add($r) } }

# item list: copy now, it is used at the next full restart
$itemsSrc = Join-Path $PSScriptRoot 'ox_items.lua'
$itemsDst = Join-Path $Res '[ox]\ox_inventory\data\items.lua'
if ([IO.File]::Exists($itemsSrc) -and [IO.File]::Exists($itemsDst)) {
    if ([IO.File]::ReadAllText($itemsSrc) -ne [IO.File]::ReadAllText($itemsDst)) {
        [IO.File]::Copy($itemsSrc, $itemsDst, $true)
        if (-not ($full -contains 'item list (new or changed items)')) { $full.Add('item list (new or changed items)') }
    }
}

foreach ($r in @($restart)) {
    if ($CoreOnly -contains $r) { [void]$restart.Remove($r); $full.Add("core script $r") }
}

if ($restart.Count -eq 0 -and $full.Count -eq 0) {
    Write-Host "`nNothing new - the server is already up to date." -ForegroundColor Green
    exit 0
}

# ---------- remote console ----------
$pw = $null
if (Test-Path $Secrets) {
    $m = Select-String -Path $Secrets -Pattern 'rcon_password\s+"([^"]+)"' | Select-Object -First 1
    if ($m) { $pw = $m.Matches[0].Groups[1].Value }
}

function Send-Rcon([string]$cmd) {
    $udp = New-Object Net.Sockets.UdpClient
    $udp.Client.ReceiveTimeout = 4000
    try {
        $udp.Connect('127.0.0.1', 30120)
        $bytes = [byte[]](@(255, 255, 255, 255) + [Text.Encoding]::UTF8.GetBytes("rcon $pw $cmd"))
        [void]$udp.Send($bytes, $bytes.Length)
        $ep = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
        $reply = $udp.Receive([ref]$ep)
        return ([Text.Encoding]::UTF8.GetString($reply, 4, $reply.Length - 4) -replace '^print ', '').Trim()
    } catch { return $null } finally { $udp.Close() }
}

if ($restart.Count -gt 0) {
    Write-Host "`nScripts to restart live: $($restart -join ', ')" -ForegroundColor Cyan
    $ok = $false
    if ($pw) {
        $reply = Send-Rcon 'refresh'
        $ok = $null -ne $reply -and $reply -notmatch 'Invalid password'
    }
    if (-not $ok) {
        Write-Host '   Could not reach the running server.' -ForegroundColor Yellow
        Write-Host '   (Is the server running? The first time, the server must be restarted once with start.bat'
        Write-Host '    so the remote console turns on. After that, hot-update.bat works without restarts.)'
    } else {
        foreach ($r in $restart) {
            $out = Send-Rcon "ensure $r"
            Write-Host "   restarted $r" -ForegroundColor Green
            if ($out) { Write-Host "      $out" }
        }
        Write-Host "`nDone - players stay connected. If something looks strange in game, reconnect to the server." -ForegroundColor Green
    }
}

if ($full.Count -gt 0) {
    Write-Host "`nThese changes need a FULL restart (close the server window, run start.bat):" -ForegroundColor Yellow
    foreach ($x in $full) { Write-Host "   - $x" }
}
