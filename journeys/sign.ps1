$ErrorActionPreference = 'Stop'

# Office Sign: local backend, register the first admin, then drive the Windows
# app to its dashboard with the session token injected into secure storage.
$svc = Get-Service | Where-Object Name -like 'postgresql-x64-*' | Select-Object -First 1
Set-Service $svc.Name -StartupType Manual
Start-Service $svc.Name
$bin = $env:PGBIN
if (-not $bin) { $v = $svc.Name -replace 'postgresql-x64-', ''; $bin = "C:\Program Files\PostgreSQL\$v\bin" }
$env:PGPASSWORD = 'root'
& "$bin\createdb.exe" -h 127.0.0.1 -U postgres office_sign_desktop 2>$null

Push-Location "$env:GITHUB_WORKSPACE\server"
npm ci
$env:DATABASE_URL = 'postgresql://postgres:root@127.0.0.1:5432/office_sign_desktop'
$env:PORT = '8120'
$env:PUBLIC_URL = 'http://127.0.0.1:8120'
$env:CORS_ORIGINS = 'http://127.0.0.1:8120'
$env:ALLOW_REGISTRATION = 'true'
$env:DATA_DIR = Join-Path $env:RUNNER_TEMP 'sign-data'
Remove-Item Env:\NODE_ENV -ErrorAction SilentlyContinue
Remove-Item Env:\ACCOUNTS_ISSUER -ErrorAction SilentlyContinue
Start-Process node -ArgumentList 'src/index.js' -WorkingDirectory (Get-Location) -WindowStyle Hidden -PassThru | Out-Null
$ok = $false
for ($i = 0; $i -lt 60; $i++) {
  try { if ((Invoke-WebRequest 'http://127.0.0.1:8120/api/health' -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200) { $ok = $true; break } } catch {}
  Start-Sleep -Seconds 2
}
if (-not $ok) { throw 'Sign backend did not become healthy' }
Pop-Location

Push-Location "$env:GITHUB_WORKSPACE\app"
$shotDir = Join-Path $env:GITHUB_WORKSPACE 'verification'
New-Item -ItemType Directory -Force -Path $shotDir | Out-Null
$shot = Join-Path $shotDir 'dashboard.png'
$testScript = Join-Path $env:RUNNER_TEMP 'run-dashboard-test.ps1'
@'
flutter test -d windows integration_test/windows_dashboard_test.dart `
  --dart-define=API_URL=http://127.0.0.1:8120 `
  --dart-define=TEST_ADMIN_EMAIL=admin@journey.test `
  --dart-define=TEST_ADMIN_PASSWORD=JourneyPass123
'@ | Set-Content -Path $testScript -Encoding utf8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$test = Start-Process pwsh -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File', $testScript -PassThru -WindowStyle Hidden
$deadline = (Get-Date).AddMinutes(20)
while (-not $test.HasExited -and (Get-Date) -lt $deadline) {
  try {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $m = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($m)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
    $m.Save($shot, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $m.Dispose()
  } catch {}
  Start-Sleep -Seconds 4
}
$test.WaitForExit()
if ($test.ExitCode -ne 0) { throw "dashboard journey failed with exit code $($test.ExitCode)" }
if (-not (Test-Path $shot)) { throw 'no dashboard screenshot was captured' }
Write-Host "dashboard screenshot: $shot"
Pop-Location
