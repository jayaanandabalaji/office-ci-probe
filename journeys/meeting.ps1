$ErrorActionPreference = 'Stop'

# Office Meeting: local backend, then native journey that creates the workspace and lands on the dashboard.
$svc = Get-Service | Where-Object Name -like 'postgresql-x64-*' | Select-Object -First 1
Set-Service $svc.Name -StartupType Manual
Start-Service $svc.Name
$bin = $env:PGBIN
if (-not $bin) { $v = $svc.Name -replace 'postgresql-x64-', ''; $bin = "C:\Program Files\PostgreSQL\$v\bin" }
$env:PGPASSWORD = 'root'
& "$bin\createdb.exe" -h 127.0.0.1 -U postgres office_meeting_ci 2>$null

Push-Location "$env:GITHUB_WORKSPACE\server"
npm ci
$env:PORT = '8160'
$env:DATABASE_URL = 'postgresql://postgres:root@127.0.0.1:5432/office_meeting_ci'
$env:PUBLIC_URL = 'http://127.0.0.1:8160'
$env:COOKIE_SECURE = 'false'
$env:ANNOUNCED_IP = '127.0.0.1'
$env:H323_ENABLED = 'false'
$env:LOGIN_ACCOUNT_MAX_ATTEMPTS = '500'
$env:LOGIN_IP_MAX_ATTEMPTS = '500'
Remove-Item Env:\NODE_ENV -ErrorAction SilentlyContinue
Start-Process node -ArgumentList 'src/index.js' -WorkingDirectory (Get-Location) `
  -RedirectStandardError (Join-Path $env:RUNNER_TEMP 'meeting-server.err.log') -WindowStyle Hidden -PassThru | Out-Null
$ok = $false
for ($i = 0; $i -lt 60; $i++) {
  try { if ((Invoke-WebRequest 'http://127.0.0.1:8160/api/ready' -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200) { $ok = $true; break } } catch {}
  Start-Sleep -Seconds 2
}
if (-not $ok) { Get-Content (Join-Path $env:RUNNER_TEMP 'meeting-server.err.log') -Tail 30; throw 'Meeting backend did not become ready' }
Pop-Location

Push-Location "$env:GITHUB_WORKSPACE\server"
npm ci
$env:DATABASE_URL = 'postgresql://postgres:root@127.0.0.1:5432/office_drive'
$env:PORT = '8106'
$env:PUBLIC_URL = 'http://127.0.0.1:8106'
$env:ALLOW_REGISTRATION = 'true'
$env:STORAGE_QUOTA_BYTES = '10737418240'
$env:DATA_DIR = Join-Path $env:RUNNER_TEMP 'drive-data'
Remove-Item Env:\NODE_ENV -ErrorAction SilentlyContinue
Remove-Item Env:\ACCOUNTS_ISSUER -ErrorAction SilentlyContinue
Start-Process node -ArgumentList 'src/index.js' -WorkingDirectory (Get-Location) -WindowStyle Hidden -PassThru | Out-Null
$ok = $false
for ($i = 0; $i -lt 60; $i++) {
  try { if ((Invoke-WebRequest 'http://127.0.0.1:8106/api/health' -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200) { $ok = $true; break } } catch {}
  Start-Sleep -Seconds 2
}
if (-not $ok) { throw 'backend did not become healthy' }
Pop-Location
