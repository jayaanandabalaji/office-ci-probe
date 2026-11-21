$ErrorActionPreference = 'Stop'
$svc = Get-Service | Where-Object Name -like 'postgresql-x64-*' | Select-Object -First 1
Set-Service $svc.Name -StartupType Manual
Start-Service $svc.Name
$bin = $env:PGBIN
if (-not $bin) { $v = $svc.Name -replace 'postgresql-x64-', ''; $bin = "C:\Program Files\PostgreSQL\$v\bin" }
$env:PGPASSWORD = 'root'
& "$bin\createdb.exe" -h 127.0.0.1 -U postgres office_people 2>$null
Push-Location "$env:GITHUB_WORKSPACE\server"
npm ci
Copy-Item .env.example .env -Force
(Get-Content .env) -replace '^DATABASE_URL=.*', 'DATABASE_URL=postgresql://postgres:root@127.0.0.1:5432/office_people' | Set-Content .env
$env:DATABASE_URL = 'postgresql://postgres:root@127.0.0.1:5432/office_people'
$env:PORT = '8120'
$env:PUBLIC_URL = 'http://127.0.0.1:8120'
Remove-Item Env:\NODE_ENV -ErrorAction SilentlyContinue
Remove-Item Env:\ACCOUNTS_ISSUER -ErrorAction SilentlyContinue
Start-Process node -ArgumentList '--env-file-if-exists=.env','src/index.js' -WorkingDirectory (Get-Location) -WindowStyle Hidden -PassThru | Out-Null
$ok = $false
for ($i = 0; $i -lt 60; $i++) {
  try { if ((Invoke-WebRequest 'http://127.0.0.1:8120/api/health' -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200) { $ok = $true; break } } catch {}
  Start-Sleep -Seconds 2
}
if (-not $ok) { throw 'backend did not become healthy' }
Pop-Location
Push-Location "$env:GITHUB_WORKSPACE\app"
flutter test -d windows integration_test/dashboard_smoke_test.dart `
--no-pub --timeout=600s --reporter=expanded `
--dart-define=API_URL=http://127.0.0.1:8120
Pop-Location
