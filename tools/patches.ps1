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

# 2. qbx_core: we have no phone (npwd) or housing tables yet -> stop the startup warnings
Edit-File (Join-Path $Res '[qbx]\qbx_core\config\server.lua') {
    param($t)
    $lines = $t -split "`r?`n"
    $kept = $lines | Where-Object { $_ -notmatch "^\s*\{\s*'(npwd_[a-z_]+|properties)'\s*," }
    return ($kept -join "`r`n")
}

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
