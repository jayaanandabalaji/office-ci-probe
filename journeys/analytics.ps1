$ErrorActionPreference = 'Stop'
$svc = Get-Service | Where-Object Name -like 'postgresql-x64-*' | Select-Object -First 1
Set-Service $svc.Name -StartupType Manual
Start-Service $svc.Name
$bin = $env:PGBIN
if (-not $bin) { $v = $svc.Name -replace 'postgresql-x64-', ''; $bin = "C:\Program Files\PostgreSQL\$v\bin" }
$env:PGPASSWORD = 'root'
& "$bin\createdb.exe" -h 127.0.0.1 -U postgres office_analytics_ci 2>$null
Push-Location "$env:GITHUB_WORKSPACE\server"
npm ci
$env:DATABASE_URL = 'postgresql://postgres:root@127.0.0.1:5432/office_analytics_ci'
$env:PORT = '8150'
$env:PUBLIC_URL = 'http://127.0.0.1:8150'
$env:OFFICE_ONE_URL = 'http://127.0.0.1:8160'
Remove-Item Env:\NODE_ENV -ErrorAction SilentlyContinue
Remove-Item Env:\ACCOUNTS_ISSUER -ErrorAction SilentlyContinue
Start-Process node -ArgumentList 'src/index.js' -WorkingDirectory (Get-Location) -WindowStyle Hidden -PassThru | Out-Null
$ok = $false
for ($i = 0; $i -lt 60; $i++) {
  try { if ((Invoke-WebRequest 'http://127.0.0.1:8150/api/health' -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200) { $ok = $true; break } } catch {}
  Start-Sleep -Seconds 2
}
if (-not $ok) { throw 'backend did not become healthy' }
Pop-Location
$token = 'ci-dashboard-token'
$hash = ([BitConverter]::ToString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($token)))).Replace('-','').ToLower()
$sql = @"
INSERT INTO members(id,name,email,role_id,status)
 SELECT '11111111-1111-1111-1111-111111111111','CI Admin','ci-admin@acme.test',id,'Active'
 FROM roles WHERE name='Administrator' ON CONFLICT (email) DO NOTHING;
INSERT INTO sessions(token_hash,member_id)
 VALUES ('$hash','11111111-1111-1111-1111-111111111111') ON CONFLICT DO NOTHING;
INSERT INTO projects(id,name) VALUES ('22222222-2222-2222-2222-222222222222','CI Project') ON CONFLICT (id) DO NOTHING;
"@
& "$bin\psql.exe" -h 127.0.0.1 -U postgres -d office_analytics_ci -c $sql
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
