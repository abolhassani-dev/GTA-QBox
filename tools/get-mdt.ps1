<#
    Mars Community 2 - downloads the police MDT (ps-mdt) and its dependencies
    from their official GitHub releases into server-data\resources\[police],
    then runs the offline installer (patches + database tables).
    Run with tools\get-mdt.bat
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

$Root   = Split-Path -Parent $PSScriptRoot
$Police = Join-Path $Root 'server-data\resources\[police]'
$Tmp    = Join-Path $Root 'tmp-mdt'
[void][IO.Directory]::CreateDirectory($Police)
[void][IO.Directory]::CreateDirectory($Tmp)

function Remove-Dir($p) { if ([IO.Directory]::Exists($p)) { [IO.Directory]::Delete($p, $true) } }

# name = folder name the server expects; check = file that proves the UI is pre-built
$Packages = @(
    @{ name = 'PolyZone';    repo = 'mkafrin/PolyZone';         check = 'client.lua' }
    @{ name = 'ps_lib';      repo = 'Project-Sloth/ps_lib';     check = 'fxmanifest.lua' }
    @{ name = 'ps-dispatch'; repo = 'Project-Sloth/ps-dispatch'; check = 'html\index.html' }
    @{ name = 'ps-mdt';      repo = 'Project-Sloth/ps-mdt';     check = 'web\dist\index.html' }
)

$failed = @()
foreach ($p in $Packages) {
    Write-Host "`n>>> $($p.name)" -ForegroundColor Cyan
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$($p.repo)/releases/latest" -Headers @{ 'User-Agent' = 'mars-installer' }
        Write-Host "   latest release: $($release.tag_name)"

        # pick the zip asset: prefer one named after the resource, never examples
        $zips = @($release.assets | Where-Object { $_.name -like '*.zip' -and $_.name -notmatch 'example' })
        $asset = $zips | Where-Object { $_.name -ieq "$($p.name).zip" } | Select-Object -First 1
        if (-not $asset) { $asset = $zips | Where-Object { $_.name -match [regex]::Escape($p.name) } | Select-Object -First 1 }
        if (-not $asset) { $asset = $zips | Select-Object -First 1 }

        $zip = Join-Path $Tmp "$($p.name).zip"
        if ($asset) {
            Write-Host "   downloading $($asset.name)"
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
        } else {
            Write-Host '   no packaged zip in this release - using the source code archive' -ForegroundColor Yellow
            Invoke-WebRequest -Uri $release.zipball_url -OutFile $zip -UseBasicParsing -Headers @{ 'User-Agent' = 'mars-installer' }
        }

        $unz = Join-Path $Tmp "$($p.name)-unz"
        Remove-Dir $unz
        Expand-Archive -Path $zip -DestinationPath $unz -Force

        $manifest = Get-ChildItem -Path $unz -Recurse -Include 'fxmanifest.lua' |
                    Sort-Object { $_.FullName.Length } | Select-Object -First 1
        if (-not $manifest) { throw 'no fxmanifest.lua in the download' }

        $dest = Join-Path $Police $p.name
        Remove-Dir $dest
        [IO.Directory]::Move($manifest.Directory.FullName, $dest)

        if ([IO.File]::Exists((Join-Path $dest $p.check))) {
            Write-Host "   installed to [police]\$($p.name)" -ForegroundColor Green
        } else {
            Write-Host "   installed, but $($p.check) is missing - this release may not include the built screen" -ForegroundColor Yellow
            $failed += "$($p.name) (no $($p.check))"
        }
    } catch {
        Write-Host "   FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $failed += $p.name
    }
}

Remove-Dir $Tmp

if ($failed.Count -gt 0) {
    Write-Host "`nProblems: $($failed -join ', ')" -ForegroundColor Red
    Write-Host 'Send a screenshot of this window to the developer.'
} else {
    Write-Host "`nAll MDT packages downloaded." -ForegroundColor Green
}

Write-Host "`n>>> Now setting up the database tables (offline installer)..." -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'install.ps1') -Offline
