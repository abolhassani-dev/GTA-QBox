<#
    Mars Community 2 - one-click installer (Windows, PowerShell 5.1+)

    What it does:
      1. Downloads QBox, ox and the other base resources into server-data\resources
      2. Patches qbx_core so VMP players without a Rockstar license can join
      3. Creates the MariaDB database + user and imports all SQL
      4. Writes server-data\secrets.cfg (database password, etc.)

    Run it with tools\install.bat (double-click). Safe to run again: it
    re-downloads the resources and skips what already exists in the database.
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'   # makes Invoke-WebRequest much faster

$Root      = Split-Path -Parent $PSScriptRoot
$Data      = Join-Path $Root 'server-data'
$Res       = Join-Path $Data 'resources'
$Tmp       = Join-Path $Root 'tmp-install'
$LogDir    = Join-Path $Root 'logs'
New-Item -ItemType Directory -Force -Path $Tmp, $LogDir | Out-Null
$LogFile   = Join-Path $LogDir ('install-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
Start-Transcript -Path $LogFile | Out-Null

function Say($msg, $color = 'Cyan') { Write-Host "`n>>> $msg" -ForegroundColor $color }

# ---------------------------------------------------------------------------
# Resource list. kind = 'release' -> GitHub release zip (already built)
#                kind = 'source'  -> GitHub source archive of branch 'ref'
# To pin an older version for an older VMP server, replace 'latest' with a tag.
# ---------------------------------------------------------------------------
$Resources = @(
    # OX
    @{ group='[ox]'; name='oxmysql';       repo='overextended/oxmysql';       kind='release'; version='latest' }
    @{ group='[ox]'; name='ox_lib';        repo='overextended/ox_lib';        kind='release'; version='latest' }
    @{ group='[ox]'; name='ox_target';     repo='overextended/ox_target';     kind='release'; version='latest' }
    @{ group='[ox]'; name='ox_inventory';  repo='overextended/ox_inventory';  kind='release'; version='latest' }
    @{ group='[ox]'; name='ox_doorlock';   repo='overextended/ox_doorlock';   kind='release'; version='latest' }
    @{ group='[ox]'; name='ox_fuel';       repo='overextended/ox_fuel';       kind='source';  ref='main' }
    # QBOX
    @{ group='[qbx]'; name='qbx_core';           repo='Qbox-project/qbx_core';           kind='release'; version='latest' }
    @{ group='[qbx]'; name='qbx_vehicles';       repo='Qbox-project/qbx_vehicles';       kind='release'; version='latest' }
    @{ group='[qbx]'; name='qbx_management';     repo='Qbox-project/qbx_management';     kind='release'; version='latest' }
    @{ group='[qbx]'; name='qbx_garages';        repo='Qbox-project/qbx_garages';        kind='release'; version='latest' }
    @{ group='[qbx]'; name='qbx_smallresources'; repo='Qbox-project/qbx_smallresources'; kind='release'; version='latest' }
    @{ group='[qbx]'; name='qbx_density';        repo='Qbox-project/qbx_density';        kind='release'; version='latest' }
    @{ group='[qbx]'; name='qbx_adminmenu';      repo='Qbox-project/qbx_adminmenu';      kind='release'; version='latest' }
    @{ group='[qbx]'; name='qbx_hud';            repo='Qbox-project/qbx_hud';            kind='release'; version='latest' }
    @{ group='[qbx]'; name='qbx_spawn';          repo='Qbox-project/qbx_spawn';          kind='release'; version='latest' }
    @{ group='[qbx]'; name='qbx_customs';        repo='Qbox-project/qbx_customs';        kind='release'; version='latest' }
    @{ group='[qbx]'; name='qbx_radio';          repo='Qbox-project/qbx_radio';          kind='release'; version='latest' }
    # STANDALONE
    @{ group='[standalone]'; name='bob74_ipl';           repo='Bob74/bob74_ipl';                      kind='source';  ref='master' }
    @{ group='[standalone]'; name='illenium-appearance'; repo='iLLeniumStudios/illenium-appearance';   kind='release'; version='latest' }
    @{ group='[standalone]'; name='Renewed-Banking';     repo='Renewed-Scripts/Renewed-Banking';      kind='release'; version='latest' }
    @{ group='[standalone]'; name='Renewed-Weathersync'; repo='Renewed-Scripts/Renewed-Weathersync';  kind='release'; version='latest' }
    @{ group='[standalone]'; name='loadscreen';          repo='D4isDAVID/loadscreen';                 kind='release'; version='latest' }
    @{ group='[standalone]'; name='scully_emotemenu';    repo='Scullyy/scully_emotemenu';             kind='source';  ref='main' }
    @{ group='[standalone]'; name='vehiclehandler';      repo='QuantumMalice/vehiclehandler';         kind='release'; version='latest' }
    @{ group='[standalone]'; name='mana_audio';          repo='Manason/mana_audio';                   kind='release'; version='latest' }
    # VOICE
    @{ group='[voice]'; name='pma-voice'; repo='AvarianKnight/pma-voice'; kind='source'; ref='main' }
)

function Get-Zip($url, $out) {
    for ($i = 1; $i -le 3; $i++) {
        try { Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing; return }
        catch { Write-Host "   download failed (try $i/3): $($_.Exception.Message)" -ForegroundColor Yellow; Start-Sleep -Seconds (5 * $i) }
    }
    throw "Could not download $url"
}

function Install-Resource($r) {
    $groupDir = Join-Path $Res $r.group
    $dest     = Join-Path $groupDir $r.name
    $zip      = Join-Path $Tmp ($r.name + '.zip')
    $unz      = Join-Path $Tmp ($r.name + '-unzipped')
    New-Item -ItemType Directory -Force -Path $groupDir | Out-Null
    if (Test-Path $unz) { Remove-Item $unz -Recurse -Force }

    if ($r.kind -eq 'release') {
        if ($r.version -eq 'latest') { $url = "https://github.com/$($r.repo)/releases/latest/download/$($r.name).zip" }
        else                        { $url = "https://github.com/$($r.repo)/releases/download/$($r.version)/$($r.name).zip" }
    } else {
        $url = "https://github.com/$($r.repo)/archive/refs/heads/$($r.ref).zip"
    }

    Write-Host "   - $($r.name)  <=  $url"
    Get-Zip $url $zip
    Expand-Archive -Path $zip -DestinationPath $unz -Force

    # The resource is the folder that contains fxmanifest.lua (or __resource.lua)
    $manifest = Get-ChildItem -Path $unz -Recurse -Include 'fxmanifest.lua','__resource.lua' |
                Sort-Object { $_.FullName.Length } | Select-Object -First 1
    if (-not $manifest) { throw "No fxmanifest.lua found in $($r.name)" }

    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Move-Item -Path $manifest.Directory.FullName -Destination $dest
}

# ---------------------------------------------------------------------------
Say 'Step 1/4 - downloading resources (this takes a few minutes)'
# cfx default resources (mapmanager, spawnmanager, ...)
$cfx = @{ group='[cfx-default]'; name='cfx-server-data'; repo='citizenfx/cfx-server-data'; kind='source'; ref='master' }
$zip = Join-Path $Tmp 'cfx.zip'; $unz = Join-Path $Tmp 'cfx-unzipped'
if (Test-Path $unz) { Remove-Item $unz -Recurse -Force }
Write-Host "   - cfx-server-data"
Get-Zip "https://github.com/citizenfx/cfx-server-data/archive/refs/heads/master.zip" $zip
Expand-Archive -Path $zip -DestinationPath $unz -Force
$cfxDest = Join-Path $Res '[cfx-default]'
if (Test-Path $cfxDest) { Remove-Item $cfxDest -Recurse -Force }
Move-Item -Path (Join-Path (Get-ChildItem $unz | Select-Object -First 1).FullName 'resources') -Destination $cfxDest
# Qbox uses the built-in system chat, so the old chat resource is removed
$oldChat = Join-Path $cfxDest '[gameplay]\chat'
if (Test-Path $oldChat) { Remove-Item $oldChat -Recurse -Force }

$failed = @()
foreach ($r in $Resources) {
    try { Install-Resource $r; Start-Sleep -Milliseconds 500 }
    catch { $failed += $r.name; Write-Host "   !! $($r.name) FAILED: $($_.Exception.Message)" -ForegroundColor Red }
}

# ox_inventory item list from the Qbox recipe
Copy-Item (Join-Path $PSScriptRoot 'ox_items.lua') (Join-Path $Res '[ox]\ox_inventory\data\items.lua') -Force

# ---------------------------------------------------------------------------
Say 'Step 2/4 - patching qbx_core for VMP (identity shim)'
$coreManifest = Join-Path $Res '[qbx]\qbx_core\fxmanifest.lua'
if (Test-Path $coreManifest) {
    $text = Get-Content $coreManifest -Raw
    if ($text -notmatch '@mars_identity/shim.lua') {
        $text = $text -replace "server_scripts\s*\{", "server_scripts {`r`n    '@mars_identity/shim.lua',"
        Set-Content -Path $coreManifest -Value $text -Encoding UTF8
        Write-Host '   qbx_core patched.'
    } else { Write-Host '   already patched.' }
} else { Write-Host '   qbx_core is missing - patch skipped!' -ForegroundColor Red }

# ---------------------------------------------------------------------------
Say 'Step 3/4 - database'
# newer MariaDB versions ship mariadb.exe; older ones mysql.exe
$mysql = Get-ChildItem 'C:\Program Files\MariaDB*\bin\mariadb.exe','C:\Program Files\MariaDB*\bin\mysql.exe' -ErrorAction SilentlyContinue |
         Sort-Object FullName -Descending | Select-Object -First 1
$secrets = Join-Path $Data 'secrets.cfg'

if (-not $mysql) {
    Write-Host '   MariaDB was not found in C:\Program Files. Install MariaDB first (see docs\02-nasb-payeh.md) and run this again.' -ForegroundColor Red
} else {
    Write-Host "   Found $($mysql.FullName)"
    $rootPwSecure = Read-Host '   Type the MariaDB ROOT password you chose during MariaDB setup' -AsSecureString
    $rootPw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($rootPwSecure))

    # keep an existing app password if secrets.cfg already has one
    $dbPw = $null
    if (Test-Path $secrets) {
        $m = Select-String -Path $secrets -Pattern 'mysql://marsuser:([^@]+)@' | Select-Object -First 1
        if ($m) { $dbPw = $m.Matches[0].Groups[1].Value }
    }
    if (-not $dbPw -or $dbPw -eq 'PUT_DB_PASSWORD_HERE') {
        $chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
        $dbPw = -join (1..24 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    }

    $env:MYSQL_PWD = $rootPw
    $setup = @"
CREATE DATABASE IF NOT EXISTS mars_community CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'marsuser'@'localhost' IDENTIFIED BY '$dbPw';
ALTER USER 'marsuser'@'localhost' IDENTIFIED BY '$dbPw';
GRANT ALL PRIVILEGES ON mars_community.* TO 'marsuser'@'localhost';
FLUSH PRIVILEGES;
"@
    $setup | & $mysql.FullName -u root
    if ($LASTEXITCODE -ne 0) { Write-Host '   Database setup failed - is the root password correct?' -ForegroundColor Red }
    else {
        $sqlFiles = @(
            (Join-Path $PSScriptRoot 'qbox.sql'),
            (Join-Path $Res '[qbx]\qbx_core\qbx_core.sql'),
            (Join-Path $Res '[qbx]\qbx_vehicles\vehicles.sql')
        )
        foreach ($f in $sqlFiles) {
            if (Test-Path $f) {
                Write-Host "   importing $(Split-Path $f -Leaf)"
                Get-Content $f -Raw | & $mysql.FullName -u root mars_community
                if ($LASTEXITCODE -ne 0) { Write-Host "   (errors above are OK if the tables already existed)" -ForegroundColor Yellow }
            } else { Write-Host "   missing SQL file: $f" -ForegroundColor Yellow }
        }
        Write-Host '   Database ready.' -ForegroundColor Green
    }
    Remove-Item Env:\MYSQL_PWD

    # ------------------------------------------------------------------
    Say 'Step 4/4 - writing server-data\secrets.cfg'
    $licenseKey = 'PUT_YOUR_VMP_LICENSE_KEY_HERE'
    $steamKey   = 'none'
    if (Test-Path $secrets) {
        $m = Select-String -Path $secrets -Pattern 'sv_licenseKey\s+"([^"]*)"' | Select-Object -First 1
        if ($m) { $licenseKey = $m.Matches[0].Groups[1].Value }
        $m = Select-String -Path $secrets -Pattern 'steam_webApiKey\s+"([^"]*)"' | Select-Object -First 1
        if ($m) { $steamKey = $m.Matches[0].Groups[1].Value }
    }
    @"
# Generated by tools\install.ps1 - this file is NOT uploaded to GitHub.
sv_licenseKey "$licenseKey"
set steam_webApiKey "$steamKey"
set mysql_connection_string "mysql://marsuser:$dbPw@127.0.0.1/mars_community?charset=utf8mb4"
"@ | Set-Content -Path $secrets -Encoding ASCII
    Write-Host "   written: $secrets" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
Say 'Extra - opening port 30120 in Windows Firewall'
try {
    foreach ($proto in 'TCP','UDP') {
        $ruleName = "Mars Community 2 ($proto 30120)"
        if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol $proto -LocalPort 30120 -Action Allow | Out-Null
        }
    }
    Write-Host '   port 30120 TCP/UDP is open.' -ForegroundColor Green
} catch { Write-Host "   could not open the port (run install.bat as Administrator): $($_.Exception.Message)" -ForegroundColor Yellow }

Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue

Say 'DONE' 'Green'
if ($failed.Count -gt 0) { Write-Host ("Failed downloads: " + ($failed -join ', ') + "  -> run install again, or send the log to the developer.") -ForegroundColor Red }
Write-Host "Log saved to: $LogFile"
Stop-Transcript | Out-Null
