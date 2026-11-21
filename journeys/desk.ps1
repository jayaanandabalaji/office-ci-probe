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

Push-Location "$env:GITHUB_WORKSPACE\app"
$shotDir = Join-Path $env:GITHUB_WORKSPACE 'verification'
New-Item -ItemType Directory -Force -Path $shotDir | Out-Null
$shot = Join-Path $shotDir 'dashboard.png'
$testScript = Join-Path $env:RUNNER_TEMP 'run-dashboard-test.ps1'
@'
flutter test -d windows integration_test/windows_dashboard_test.dart `
  --dart-define=API_URL=http://127.0.0.1:8150 `
  "--dart-define=DESK_BOOT_TOKEN=$token" `
  --dart-define=ADMIN_EMAIL=admin@native.test `
  --dart-define=ADMIN_PASSWORD=correct-horse-1
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
