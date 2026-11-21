$ErrorActionPreference = 'Stop'

# Office Mail: start local Postgres + backend, then run the integration test
# that walks first-run setup, signs in, and reaches Inbox (the dashboard).
Set-Service -Name postgresql-x64-17 -StartupType Manual
Start-Service -Name postgresql-x64-17
$env:PGPASSWORD = 'root'
& "$env:PGBIN\createdb.exe" -h 127.0.0.1 -U postgres -p 5432 office_mail_desktop 2>$null

Push-Location "$env:GITHUB_WORKSPACE\server"
npm ci
npm run build
$env:DATABASE_URL = 'postgresql://postgres:root@127.0.0.1:5432/office_mail_desktop'
$env:MAIL_HOSTNAME = 'mx.journey.test'
$env:HTTP_PORT = '18290'
$env:SMTP_PORT = '0'
$env:SUBMISSION_PORT = '0'
$env:SMTPS_PORT = '0'
$env:IMAP_PORT = '0'
$env:IMAPS_PORT = '0'
$env:POP3_PORT = '0'
$env:POP3S_PORT = '0'
$env:SIEVE_PORT = '0'
$env:DATA_DIR = Join-Path $env:RUNNER_TEMP 'mail-data'
$env:ALLOW_INSECURE_AUTH = 'true'
$env:NODE_ENV = 'development'
Remove-Item Env:\ACCOUNTS_ISSUER -ErrorAction SilentlyContinue
Start-Process node -ArgumentList 'dist/index.js' -WorkingDirectory (Get-Location) `
  -RedirectStandardOutput (Join-Path $env:RUNNER_TEMP 'mail-server.out.log') `
  -RedirectStandardError (Join-Path $env:RUNNER_TEMP 'mail-server.err.log') `
  -WindowStyle Hidden -PassThru | Out-Null
$ok = $false
for ($i = 0; $i -lt 60; $i++) {
  try { if ((Invoke-WebRequest 'http://127.0.0.1:18290/api/setup' -UseBasicParsing).StatusCode -eq 200) { $ok = $true; break } } catch {}
  Start-Sleep -Seconds 2
}
if (-not $ok) { Get-Content (Join-Path $env:RUNNER_TEMP 'mail-server.err.log') -Tail 30; throw 'Mail backend did not become ready' }
Pop-Location

Push-Location "$env:GITHUB_WORKSPACE\app"
flutter test integration_test/journey_test.dart -d windows `
  --dart-define=OFFICE_ANALYTICS_APP_KEY=test `
  --dart-define=OFFICE_APP_VERSION=1.0.0
Pop-Location
