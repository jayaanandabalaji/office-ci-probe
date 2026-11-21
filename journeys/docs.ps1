$ErrorActionPreference = 'Stop'
$svc = Get-Service | Where-Object Name -like 'postgresql-x64-*' | Select-Object -First 1
Set-Service $svc.Name -StartupType Manual
Start-Service $svc.Name
$bin = $env:PGBIN
if (-not $bin) { $v = $svc.Name -replace 'postgresql-x64-', ''; $bin = "C:\Program Files\PostgreSQL\$v\bin" }
$env:PGPASSWORD = 'root'
& "$bin\createdb.exe" -h 127.0.0.1 -U postgres office_docs_ci 2>$null
Push-Location "$env:GITHUB_WORKSPACE\server"
npm ci
npm run build
$env:DATABASE_URL = 'postgresql://postgres:root@127.0.0.1:5432/office_docs_ci'
$env:HTTP_PORT = '8090'
$env:PUBLIC_URL = 'http://127.0.0.1:8090'
$env:DATA_DIR = Join-Path $env:RUNNER_TEMP 'docs-data'
$env:CORS_ORIGINS = '*'
Remove-Item Env:\NODE_ENV -ErrorAction SilentlyContinue
Remove-Item Env:\ACCOUNTS_ISSUER -ErrorAction SilentlyContinue
Start-Process node -ArgumentList 'dist/index.js' -WorkingDirectory (Get-Location) -WindowStyle Hidden -PassThru | Out-Null
$ok = $false
for ($i = 0; $i -lt 60; $i++) {
  try { if ((Invoke-WebRequest 'http://127.0.0.1:8090/api/health' -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200) { $ok = $true; break } } catch {}
  Start-Sleep -Seconds 2
}
if (-not $ok) { throw 'backend did not become healthy' }
Pop-Location
$body = @{email = 'admin@balaji.com'; password = 'OfficeDocs#2026'; displayName = 'Admin'} | ConvertTo-Json
try { Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:8090/api/setup' -ContentType 'application/json' -Body $body | Out-Null } catch {}
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
