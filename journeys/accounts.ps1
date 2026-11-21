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
Push-Location "$env:GITHUB_WORKSPACE\app"
$shotDir = Join-Path $env:GITHUB_WORKSPACE 'verification'
New-Item -ItemType Directory -Force -Path $shotDir | Out-Null
$shot = Join-Path $shotDir 'dashboard.png'
$testScript = Join-Path $env:RUNNER_TEMP 'run-dashboard-test.ps1'
@'
flutter pub get
flutter test -d windows integration_test/native_journey_test.dart `
  --dart-define=PHASE=setup `
  --dart-define=API_URL=http://127.0.0.1:8170 `
  "--dart-define=EVIDENCE_DIR=$evidence"
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
