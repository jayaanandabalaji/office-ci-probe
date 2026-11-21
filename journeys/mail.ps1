$ErrorActionPreference = 'Stop'
$svc = Get-Service | Where-Object Name -like 'postgresql-x64-*' | Select-Object -First 1
Set-Service $svc.Name -StartupType Manual
Start-Service $svc.Name
$bin = $env:PGBIN
if (-not $bin) { $v = $svc.Name -replace 'postgresql-x64-', ''; $bin = "C:\Program Files\PostgreSQL\$v\bin" }
$env:PGPASSWORD = 'root'
& "$bin\createdb.exe" -h 127.0.0.1 -U postgres office_mail_desktop 2>$null
Push-Location "$env:GITHUB_WORKSPACE\server"
npm ci
npm run build
$env:DATABASE_URL = 'postgresql://postgres:root@127.0.0.1:5432/office_mail_desktop'
$env:MAIL_HOSTNAME = 'mx.journey.test'
$env:HTTP_PORT = '18290'
$env:SMTP_PORT = '0'; $env:SUBMISSION_PORT = '0'; $env:SMTPS_PORT = '0'
$env:IMAP_PORT = '0'; $env:IMAPS_PORT = '0'; $env:POP3_PORT = '0'; $env:POP3S_PORT = '0'; $env:SIEVE_PORT = '0'
$env:DATA_DIR = Join-Path $env:RUNNER_TEMP 'mail-data'
$env:ALLOW_INSECURE_AUTH = 'true'
Remove-Item Env:\NODE_ENV -ErrorAction SilentlyContinue
$env:NODE_ENV = 'development'
Remove-Item Env:\ACCOUNTS_ISSUER -ErrorAction SilentlyContinue
Start-Process node -ArgumentList 'dist/index.js' -WorkingDirectory (Get-Location) -WindowStyle Hidden -PassThru | Out-Null
$ok = $false
for ($i = 0; $i -lt 60; $i++) {
  try { if ((Invoke-WebRequest 'http://127.0.0.1:18290/api/setup' -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200) { $ok = $true; break } } catch {}
  Start-Sleep -Seconds 2
}
if (-not $ok) { throw 'backend did not become healthy' }
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
