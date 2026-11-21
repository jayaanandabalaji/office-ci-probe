$ErrorActionPreference = 'Stop'

# Office Accounts: local backend, then first-run setup journey ending at the signed-in home.
$svc = Get-Service | Where-Object Name -like 'postgresql-x64-*' | Select-Object -First 1
Set-Service $svc.Name -StartupType Manual
Start-Service $svc.Name
$bin = $env:PGBIN
if (-not $bin) { $v = $svc.Name -replace 'postgresql-x64-', ''; $bin = "C:\Program Files\PostgreSQL\$v\bin" }
$env:PGPASSWORD = 'root'
& "$bin\createdb.exe" -h 127.0.0.1 -U postgres office_accounts_ci 2>$null

Push-Location "$env:GITHUB_WORKSPACE\server"
npm ci
npm run build
@"
DATABASE_URL=postgresql://postgres:root@127.0.0.1:5432/office_accounts_ci
HTTP_PORT=8170
PUBLIC_URL=http://127.0.0.1:8170
MAIL_FROM=Office Accounts <no-reply@native.test>
CORS_ORIGINS=*
"@ | Set-Content .env -Encoding utf8
Start-Process node -ArgumentList '--env-file=.env','dist/index.js' -WorkingDirectory (Get-Location) `
  -RedirectStandardError (Join-Path $env:RUNNER_TEMP 'accounts-server.err.log') -WindowStyle Hidden -PassThru | Out-Null
$ok = $false
for ($i = 0; $i -lt 60; $i++) {
  try {
    $h = Invoke-RestMethod 'http://127.0.0.1:8170/api/setup' -TimeoutSec 3
    if ($h.initialized -eq $false) { $ok = $true; break }
  } catch {}
  Start-Sleep -Seconds 2
}
if (-not $ok) { Get-Content (Join-Path $env:RUNNER_TEMP 'accounts-server.err.log') -Tail 30; throw 'Accounts backend did not become ready' }
Pop-Location

$evidence = ($env:GITHUB_WORKSPACE -replace '\\', '/') + '/evidence'
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
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
