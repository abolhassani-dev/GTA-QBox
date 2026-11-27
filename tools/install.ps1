<#
    Mars Community 2 - one-click installer (Windows, PowerShell 5.1+)

    What it does:
      1. Downloads QBox, ox and the other base resources into server-data\resources
      2. Patches qbx_core so VMP players without a Rockstar license can join
      3. Creates the MariaDB database + user and imports all SQL
      4. Writes server-data\secrets.cfg (database password, etc.)

    Run it with tools\install.bat (double-click). Safe to run again: it
    re-downloads the resources and skips what already exists in the database.

    -Offline : skip step 1 and use the resources that are already in
               server-data\resources (for a folder copied from another PC).
               Run it with tools\install-offline.bat.
#>
param([switch]$Offline)

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
    # ox_lib is pinned: 3.41+ needs the new 'require' resource that VMP does not ship
    @{ group='[ox]'; name='ox_lib';        repo='overextended/ox_lib';        kind='release'; version='v3.40.3' }
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
    @{ group='[qbx]'; name='qbx_drugs';          repo='Qbox-project/qbx_drugs';          kind='source';  ref='main' }
    @{ group='[qbx]'; name='qbx_medical';        repo='Qbox-project/qbx_medical';        kind='source';  ref='main' }
    @{ group='[qbx]'; name='qbx_prison';         repo='Qbox-project/qbx_prison';         kind='source';  ref='main' }
    @{ group='[qbx]'; name='qbx_vehiclekeys';    repo='Qbox-project/qbx_vehiclekeys';    kind='source';  ref='main' }
    @{ group='[qbx]'; name='qbx_vehicleshop';    repo='Qbox-project/qbx_vehicleshop';    kind='source';  ref='main' }
    @{ group='[qbx]'; name='qbx_cityhall';       repo='Qbox-project/qbx_cityhall';       kind='source';  ref='main' }
    @{ group='[qbx]'; name='qbx_radialmenu';     repo='Qbox-project/qbx_radialmenu';     kind='source';  ref='main' }
    @{ group='[qbx]'; name='qbx_scoreboard';     repo='Qbox-project/qbx_scoreboard';     kind='source';  ref='main' }
    @{ group='[qbx]'; name='qbx_seatbelt';       repo='Qbox-project/qbx_seatbelt';       kind='source';  ref='main' }
    @{ group='[qbx]'; name='qbx_idcard';         repo='Qbox-project/qbx_idcard';         kind='source';  ref='main' }
    @{ group='[qbx]'; name='qbx_carwash';        repo='Qbox-project/qbx_carwash';        kind='source';  ref='main' }
    @{ group='[qbx]'; name='qbx_properties';     repo='Qbox-project/qbx_properties';     kind='source';  ref='main' }
    # JOBS
    @{ group='[qbx-jobs]'; name='qbx_policejob';    repo='Qbox-project/qbx_policejob';    kind='source'; ref='main' }
    @{ group='[qbx-jobs]'; name='qbx_ambulancejob'; repo='Qbox-project/qbx_ambulancejob'; kind='source'; ref='main' }
    @{ group='[qbx-jobs]'; name='qbx_mechanicjob';  repo='Qbox-project/qbx_mechanicjob';  kind='source'; ref='main' }
    @{ group='[qbx-jobs]'; name='qbx_taxijob';      repo='Qbox-project/qbx_taxijob';      kind='source'; ref='main' }
    @{ group='[qbx-jobs]'; name='qbx_towjob';       repo='Qbox-project/qbx_towjob';       kind='source'; ref='main' }
    @{ group='[qbx-jobs]'; name='qbx_garbagejob';   repo='Qbox-project/qbx_garbagejob';   kind='source'; ref='main' }
    @{ group='[qbx-jobs]'; name='qbx_busjob';       repo='Qbox-project/qbx_busjob';       kind='source'; ref='main' }
    @{ group='[qbx-jobs]'; name='qbx_truckerjob';   repo='Qbox-project/qbx_truckerjob';   kind='source'; ref='main' }
    @{ group='[qbx-jobs]'; name='qbx_newsjob';      repo='Qbox-project/qbx_newsjob';      kind='source'; ref='main' }
    @{ group='[qbx-jobs]'; name='qbx_recyclejob';   repo='Qbox-project/qbx_recyclejob';   kind='source'; ref='main' }
    # CRIME
    @{ group='[qbx-crime]'; name='qbx_bankrobbery';  repo='Qbox-project/qbx_bankrobbery';  kind='source'; ref='main' }
    @{ group='[qbx-crime]'; name='qbx_jewelery';     repo='Qbox-project/qbx_jewelery';     kind='source'; ref='main' }
    @{ group='[qbx-crime]'; name='qbx_houserobbery'; repo='Qbox-project/qbx_houserobbery'; kind='source'; ref='main' }
    @{ group='[qbx-crime]'; name='qbx_scrapyard';    repo='Qbox-project/qbx_scrapyard';    kind='source'; ref='main' }
    @{ group='[qbx-crime]'; name='qbx_streetraces';  repo='Qbox-project/qbx_streetraces';  kind='source'; ref='main' }
    # PHONE (npwd)
    @{ group='[phone]'; name='npwd';          repo='project-error/npwd';          kind='release'; version='3.14.3' }
    @{ group='[phone]'; name='qbx_npwd';      repo='Qbox-project/qbx_npwd';       kind='source';  ref='main' }
    @{ group='[phone]'; name='npwd_qbx_mail'; repo='Qbox-project/npwd_qbx_mail'; kind='release'; version='latest' }
    @{ group='[phone]'; name='screencapture'; repo='itschip/screencapture';       kind='release'; version='latest' }
    # STANDALONE
    @{ group='[standalone]'; name='bob74_ipl';           repo='Bob74/bob74_ipl';                      kind='source';  ref='master' }
    @{ group='[standalone]'; name='illenium-appearance'; repo='iLLeniumStudios/illenium-appearance';   kind='release'; version='latest' }
    @{ group='[standalone]'; name='Renewed-Banking';     repo='Renewed-Scripts/Renewed-Banking';      kind='release'; version='latest' }
    @{ group='[standalone]'; name='Renewed-Weathersync'; repo='Renewed-Scripts/Renewed-Weathersync';  kind='release'; version='latest' }
    @{ group='[standalone]'; name='loadscreen';          repo='D4isDAVID/loadscreen';                 kind='release'; version='latest' }
    @{ group='[standalone]'; name='scully_emotemenu';    repo='Scullyy/scully_emotemenu';             kind='source';  ref='main' }
    @{ group='[standalone]'; name='vehiclehandler';      repo='QuantumMalice/vehiclehandler';         kind='release'; version='latest' }
    @{ group='[standalone]'; name='MugShotBase64';       repo='BaziForYou/MugShotBase64';             kind='source';  ref='main' }
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

# Folder names like [ox] contain square brackets, which PowerShell cmdlets treat
# as wildcards. These helpers use .NET directly so brackets are taken literally.
function Remove-Dir($p)  { if ([IO.Directory]::Exists($p)) { [IO.Directory]::Delete($p, $true) } }
function Ensure-Dir($p)  { [void][IO.Directory]::CreateDirectory($p) }
$Utf8NoBom = New-Object Text.UTF8Encoding($false)

function Install-Resource($r) {
    $groupDir = Join-Path $Res $r.group
    $dest     = Join-Path $groupDir $r.name
    $zip      = Join-Path $Tmp ($r.name + '.zip')
    $unz      = Join-Path $Tmp ($r.name + '-unzipped')
    Ensure-Dir $groupDir
    Remove-Dir $unz

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

    Remove-Dir $dest
    [IO.Directory]::Move($manifest.Directory.FullName, $dest)
}

# ---------------------------------------------------------------------------
$failed = @()
if ($Offline) {
    Say 'Step 1/4 - OFFLINE mode: using the resources already in server-data\resources'
    foreach ($r in $Resources) {
        if (-not [IO.Directory]::Exists((Join-Path (Join-Path $Res $r.group) $r.name))) { $failed += $r.name }
    }
    if ($failed.Count -gt 0) { Write-Host ("   missing: " + ($failed -join ', ')) -ForegroundColor Red }
    else { Write-Host '   all resources found.' -ForegroundColor Green }
} else {
Say 'Step 1/4 - downloading resources (this takes a few minutes)'
# cfx default resources (mapmanager, spawnmanager, ...)
$zip = Join-Path $Tmp 'cfx.zip'; $unz = Join-Path $Tmp 'cfx-unzipped'
Ensure-Dir $Res
Remove-Dir $unz
Write-Host "   - cfx-server-data"
Get-Zip "https://github.com/citizenfx/cfx-server-data/archive/refs/heads/master.zip" $zip
Expand-Archive -Path $zip -DestinationPath $unz -Force
$cfxDest = Join-Path $Res '[cfx-default]'
Remove-Dir $cfxDest
[IO.Directory]::Move((Join-Path (Get-ChildItem -LiteralPath $unz | Select-Object -First 1).FullName 'resources'), $cfxDest)
# The classic chat resource is kept: the VMP client has no built-in system chat

foreach ($r in $Resources) {
    try { Install-Resource $r; Start-Sleep -Milliseconds 500 }
    catch { $failed += $r.name; Write-Host "   !! $($r.name) FAILED: $($_.Exception.Message)" -ForegroundColor Red }
}
}

# npwd uses the Qbox phone config shipped with qbx_npwd
$npwdCfg = Join-Path $Res '[phone]\qbx_npwd\config.json'
if ([IO.File]::Exists($npwdCfg) -and [IO.Directory]::Exists((Join-Path $Res '[phone]\npwd'))) {
    [IO.File]::Copy($npwdCfg, (Join-Path $Res '[phone]\npwd\config.json'), $true)
}

# ox_inventory item list from the Qbox recipe
$invData = Join-Path $Res '[ox]\ox_inventory\data'
if ([IO.Directory]::Exists($invData)) { [IO.File]::Copy((Join-Path $PSScriptRoot 'ox_items.lua'), (Join-Path $invData 'items.lua'), $true) }

# ---------------------------------------------------------------------------
Say 'Step 2/4 - applying Mars patches (VMP identity shim, warnings)'
& (Join-Path $PSScriptRoot 'patches.ps1')

# ---------------------------------------------------------------------------
Say 'Step 3/4 - database'
# newer MariaDB versions ship mariadb.exe; older ones mysql.exe
# MariaDB may be installed on any drive (e.g. D:\MariaDB 11.8 on a frozen-C: PC)
$mysqlCandidates = @()
foreach ($drv in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' })) {
    foreach ($dir in 'Program Files\MariaDB*\bin', 'MariaDB*\bin', 'Program Files (x86)\MariaDB*\bin') {
        foreach ($exe in 'mariadb.exe', 'mysql.exe') {
            $mysqlCandidates += @(Get-ChildItem -Path (Join-Path $drv.Root "$dir\$exe") -ErrorAction SilentlyContinue)
        }
    }
}
$mysql = $mysqlCandidates | Sort-Object @{ Expression = { $_.Name -eq 'mariadb.exe' }; Descending = $true }, FullName | Select-Object -First 1
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
            (Join-Path $Res '[qbx]\qbx_vehicles\vehicles.sql'),
            (Join-Path $Res '[qbx]\qbx_drugs\qbx_drugs.sql'),
            (Join-Path $Res '[qbx]\qbx_vehicleshop\vehshop.sql'),
            (Join-Path $Res '[qbx]\qbx_properties\property.sql'),
            (Join-Path $Res '[qbx]\qbx_properties\property_garages.sql'),
            (Join-Path $Res '[qbx]\qbx_properties\decorations.sql'),
            (Join-Path $Res '[phone]\npwd\import.sql')
        )
        foreach ($f in $sqlFiles) {
            if ([IO.File]::Exists($f)) {
                Write-Host "   importing $(Split-Path $f -Leaf)"
                [IO.File]::ReadAllText($f) | & $mysql.FullName -u root mars_community
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
