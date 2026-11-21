$ErrorActionPreference = 'Stop'

# Office Desk: local backend, seed admin, log in for a token, then drive the
# Windows app to the dashboard with that token injected at compile time.
$svc = Get-Service | Where-Object Name -like 'postgresql-x64-*' | Select-Object -First 1
Set-Service $svc.Name -StartupType Manual
Start-Service $svc.Name
$bin = $env:PGBIN
if (-not $bin) { $v = $svc.Name -replace 'postgresql-x64-', ''; $bin = "C:\Program Files\PostgreSQL\$v\bin" }
$env:PGPASSWORD = 'root'
& "$bin\createdb.exe" -h 127.0.0.1 -U postgres office_desk_native 2>$null

Push-Location "$env:GITHUB_WORKSPACE\server"
npm ci --no-audit --no-fund
$env:DATABASE_URL = 'postgresql://postgres:root@127.0.0.1:5432/office_desk_native'
$env:PORT = '8150'
$env:PUBLIC_URL = 'http://127.0.0.1:8150'
Remove-Item Env:\NODE_ENV -ErrorAction SilentlyContinue
Remove-Item Env:\ACCOUNTS_ISSUER -ErrorAction SilentlyContinue
Start-Process node -ArgumentList 'src/index.js' -WorkingDirectory (Get-Location) -WindowStyle Hidden -PassThru | Out-Null
$ok = $false
for ($i = 0; $i -lt 60; $i++) {
  try { if ((Invoke-WebRequest 'http://127.0.0.1:8150/api/health' -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200) { $ok = $true; break } } catch {}
  Start-Sleep -Seconds 2
}
if (-not $ok) { throw 'Desk backend did not become healthy' }
Pop-Location

$setup = @{ company = 'Native Desk'; name = 'Ada Admin'; email = 'admin@native.test'; password = 'correct-horse-1'; timezone = 'UTC' } | ConvertTo-Json
try { Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:8150/api/setup' -ContentType 'application/json' -Body $setup | Out-Null } catch {}
$login = @{ email = 'admin@native.test'; password = 'correct-horse-1' } | ConvertTo-Json
$token = (Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:8150/api/auth/login' -ContentType 'application/json' -Body $login).token
if (-not $token) { throw 'Could not obtain a Desk session token' }

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
