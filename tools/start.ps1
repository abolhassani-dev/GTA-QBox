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

# --- make sure MariaDB is running (it may live on D: without a Windows service) ---
function Test-Port($port) {
    try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', $port); $c.Close(); return $true } catch { return $false }
}
if (-not (Test-Port 3306)) {
    Write-Host 'MariaDB is not running - trying to start it...' -ForegroundColor Yellow
    $svc = Get-Service -Name 'MariaDB*','MySQL*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($svc) {
        try { Start-Service $svc.Name; Write-Host "   started service $($svc.Name)" } catch { Write-Host "   could not start service: $($_.Exception.Message)" }
    } else {
        $daemon = $null
        foreach ($drv in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' })) {
            foreach ($dir in 'MariaDB*\bin', 'Program Files\MariaDB*\bin') {
                foreach ($exe in 'mariadbd.exe', 'mysqld.exe') {
                    if (-not $daemon) { $daemon = Get-ChildItem -Path (Join-Path $drv.Root "$dir\$exe") -ErrorAction SilentlyContinue | Select-Object -First 1 }
                }
            }
        }
        if ($daemon) {
            $ini = Join-Path (Split-Path -Parent $daemon.Directory.FullName) 'data\my.ini'
            $args = @()
            if (Test-Path $ini) { $args += "--defaults-file=$ini" }
            Start-Process -FilePath $daemon.FullName -ArgumentList $args -WindowStyle Hidden
            Write-Host "   started $($daemon.FullName)"
        } else {
            Write-Host '   MariaDB not found on any drive!' -ForegroundColor Red
        }
    }
    for ($i = 0; $i -lt 20 -and -not (Test-Port 3306); $i++) { Start-Sleep -Seconds 1 }
    if (Test-Port 3306) { Write-Host '   MariaDB is up.' -ForegroundColor Green }
    else { Write-Host '   MariaDB did not start - the server will not be able to load characters.' -ForegroundColor Red }
}

$log = Join-Path $Logs ('server-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
Write-Host "Starting $($exe.FullName)"
Write-Host "Console is also saved to: $log`n" -ForegroundColor Cyan
Set-Location $Data
& $exe.FullName +set onesync on +exec server.cfg 2>&1 | Tee-Object -FilePath $log
