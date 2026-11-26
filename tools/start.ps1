# Mars Community 2 - starts the VMP server and saves the console output to logs\
$Root  = Split-Path -Parent $PSScriptRoot
$Data  = Join-Path $Root 'server-data'
$Arts  = Join-Path $Root 'artifacts'
$Logs  = Join-Path $Root 'logs'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null

$exe = Get-ChildItem -Path $Arts -Recurse -Include 'FXServer.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $exe) {
    $exe = Get-ChildItem -Path $Arts -Recurse -Filter '*.exe' -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -match 'server' } | Select-Object -First 1
}
if (-not $exe) {
    Write-Host "Server program not found in $Arts" -ForegroundColor Red
    Write-Host "Put the VMP server files in that folder (see docs\02-nasb-payeh.md)."
    exit 1
}
if (-not (Test-Path (Join-Path $Data 'secrets.cfg'))) {
    Write-Host "server-data\secrets.cfg is missing - run tools\install.bat first." -ForegroundColor Red
    exit 1
}

$log = Join-Path $Logs ('server-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
Write-Host "Starting $($exe.FullName)"
Write-Host "Console is also saved to: $log`n" -ForegroundColor Cyan
Set-Location $Data
& $exe.FullName +set onesync on +exec server.cfg 2>&1 | Tee-Object -FilePath $log
