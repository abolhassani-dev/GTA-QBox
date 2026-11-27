<#
    Mars Community 2 - small, idempotent patches to downloaded resources.
    Run automatically by install.ps1 and start.ps1, so a fix pushed by the
    developer reaches the server with update.bat + start.bat only.
#>

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$Res  = Join-Path $Root 'server-data\resources'
$Utf8NoBom = New-Object Text.UTF8Encoding($false)

function Edit-File($path, [scriptblock]$transform) {
    if (-not [IO.File]::Exists($path)) { return }
    $before = [IO.File]::ReadAllText($path)
    $after = & $transform $before
    if ($after -ne $before) {
        [IO.File]::WriteAllText($path, $after, $Utf8NoBom)
        Write-Host "   patched $([IO.Path]::GetFileName([IO.Path]::GetDirectoryName($path)))\$([IO.Path]::GetFileName($path))"
    }
}

# 1. qbx_core: VMP identity shim must load first in qbx_core
Edit-File (Join-Path $Res '[qbx]\qbx_core\fxmanifest.lua') {
    param($t)
    if ($t -match '@mars_identity/shim.lua') { return $t }
    return ($t -replace "server_scripts\s*\{", "server_scripts {`r`n    '@mars_identity/shim.lua',")
}

# 2. (removed) phone/housing tables now exist: npwd and qbx_properties are installed

# 3. ox_lib: version is pinned on purpose (3.41+ needs a 'require' resource VMP lacks)
Edit-File (Join-Path $Res '[ox]\ox_lib\resource\version\server.lua') {
    param($t)
    return ($t -replace "(?m)^lib\.versionCheck\('overextended/ox_lib'\)", "-- lib.versionCheck('overextended/ox_lib') -- disabled by Mars: version pinned for VMP")
}

# 4. scully_emotemenu: its GitHub version check fails behind Iranian internet
Edit-File (Join-Path $Res '[standalone]\scully_emotemenu\fxmanifest.lua') {
    param($t)
    return ($t -replace "(?m)^\s*'server/version_check\.lua',\s*\r?\n", '')
}

# 5. death / respawn (Mars settings)
#    - keep the inventory when respawning at the hospital (Qbox default wipes it)
#    - shorter death and last-stand timers (Qbox default 300 s)
Edit-File (Join-Path $Res '[qbx-jobs]\qbx_ambulancejob\config\server.lua') {
    param($t)
    return ($t -replace 'wipeInvOnRespawn\s*=\s*true', 'wipeInvOnRespawn = false')
}
Edit-File (Join-Path $Res '[qbx-jobs]\qbx_ambulancejob\config\client.lua') {
    param($t)
    return ($t -replace 'laststandTimer\s*=\s*\d+', 'laststandTimer = 180')
}
Edit-File (Join-Path $Res '[qbx]\qbx_medical\config\client.lua') {
    param($t)
    return ($t -replace 'deathTime\s*=\s*\d+', 'deathTime = 180')
}

# 6. City Hall: offer the Mars work jobs (mars_jobs) in the employment menu
Edit-File (Join-Path $Res '[qbx]\qbx_cityhall\config\shared.lua') {
    param($t)
    if ($t -match "pizza\s*=") { return $t }
    $add = "bus = 'Bus Driver',`r`n            pizza = 'Pizza Delivery',`r`n            postal = 'GoPostal Courier',`r`n            electrician = 'Electrician',`r`n            vineyard = 'Vineyard Picker',`r`n            miner = 'Quarry Miner',`r`n            lumberjack = 'Lumberjack',"
    return ($t -replace "bus\s*=\s*'Bus Driver',", $add)
}

# 7. the default qbx_pawnshop is replaced by mars_pawnshop
$oldPawn = Join-Path $Res '[qbx-crime]\qbx_pawnshop'
if ([IO.Directory]::Exists($oldPawn)) {
    [IO.Directory]::Delete($oldPawn, $true)
    Write-Host '   removed qbx_pawnshop (replaced by mars_pawnshop)'
}

# 8. ps-mdt / ps_lib (downloaded by hand into resources\[police]) – adapt to Mars
Edit-File (Join-Path $Res '[police]\ps-mdt\config.lua') {
    param($t)
    $t = $t -replace "Resource\s*=\s*'lb-phone'", "Resource     = ''"
    $t = $t -replace "(?m)^(\s*)'lspd',", "`$1'police',"
    $t = $t -replace "(?m)^(\s*)'sahp'(,?)", "`$1'sasp'`$2"
    return $t
}
Edit-File (Join-Path $Res '[police]\ps_lib\Config.lua') {
    param($t)
    $t = $t -replace 'Config\.Banking\s*=\s*"qb"', 'Config.Banking = "Renewed"'
    $t = $t -replace 'Config\.EmoteMenu\s*=\s*"rpemotes"', 'Config.EmoteMenu = "scully"'
    return $t
}

# 9. ps_lib (release 1.0.0) qbx bridge: functions crash when the player is not
#    loaded yet (still connecting) -> return nil instead of erroring
Edit-File (Join-Path $Res '[police]\ps_lib\bridge\framework\qbx\server.lua') {
    param($t)
    if ($t -match 'mars: nil-safe') { return $t }
    $t = $t -replace "(?m)^([ \t]*)local player = ps\.getPlayer\(source\)[ \t]*\r?$", "`$1local player = ps.getPlayer(source)`r`n`$1if not player then return nil end"
    return "-- mars: nil-safe player lookups`r`n" + $t
}
