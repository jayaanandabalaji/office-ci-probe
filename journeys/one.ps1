$ErrorActionPreference = 'Stop'
$svc = Get-Service | Where-Object Name -like 'postgresql-x64-*' | Select-Object -First 1
Set-Service $svc.Name -StartupType Manual
Start-Service $svc.Name
$bin = $env:PGBIN
if (-not $bin) { $v = $svc.Name -replace 'postgresql-x64-', ''; $bin = "C:\Program Files\PostgreSQL\$v\bin" }
$env:PGPASSWORD = 'root'
& "$bin\createdb.exe" -h 127.0.0.1 -U postgres office_one_test 2>$null
Push-Location "$env:GITHUB_WORKSPACE\server"
npm ci
$env:PORT = '8160'
$env:PUBLIC_URL = 'http://127.0.0.1:8160'
$env:ALLOW_GUEST = 'true'
$env:APP_STATUS_CHECKS = 'false'
$env:NODE_ENV = 'development'
$env:DATABASE_URL = 'postgresql://postgres:root@127.0.0.1:5432/office_one_test'
Pop-Location
Push-Location "$env:GITHUB_WORKSPACE\app"
$shotDir = Join-Path $env:GITHUB_WORKSPACE 'verification'
New-Item -ItemType Directory -Force -Path $shotDir | Out-Null
$shot = Join-Path $shotDir 'dashboard.png'
$testScript = Join-Path $env:RUNNER_TEMP 'run-dashboard-test.ps1'
@'
flutter test -d windows integration_test/windows_dashboard_test.dart `
--dart-define=JOURNEY_SERVER_URL=http://127.0.0.1:18290 `
--dart-define=JOURNEY_ADMIN_EMAIL=admin@journey.test `
--dart-define=JOURNEY_ADMIN_PASSWORD=JourneyPass123 `
--dart-define=JOURNEY_ADMIN_NAME='Ada Admin'
'@ | Set-Content -Path $testScript -Encoding utf8
$outLog = Join-Path $env:RUNNER_TEMP 'dashboard-test.out.log'
$errLog = Join-Path $env:RUNNER_TEMP 'dashboard-test.err.log'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$test = Start-Process pwsh -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File', $testScript -PassThru -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog
$frame = 0
$deadline = (Get-Date).AddMinutes(20)
while (-not $test.HasExited -and (Get-Date) -lt $deadline) {
  try {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $m = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($m)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
    $m.Save((Join-Path $shotDir ('frame-{0:d3}.png' -f $frame)), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $m.Dispose()
    $frame++
  } catch {}
  Start-Sleep -Seconds 3
}
$test.WaitForExit()
Write-Host '--- dashboard test output ---'
if (Test-Path $outLog) { Get-Content $outLog | Write-Host }
if (Test-Path $errLog) { Get-Content $errLog | Write-Host }
$best = $null
$bestColors = 0
Get-ChildItem -Path $shotDir -Filter 'frame-*.png' -ErrorAction SilentlyContinue | ForEach-Object {
  $bmp = [System.Drawing.Bitmap]::FromFile($_.FullName)
  $colors = @{}
  for ($y = 0; $y -lt $bmp.Height; $y += 16) { for ($x = 0; $x -lt $bmp.Width; $x += 16) { $colors[$bmp.GetPixel($x, $y).ToArgb()] = 1 } }
  $bmp.Dispose()
  if ($colors.Count -gt $bestColors) { $bestColors = $colors.Count; $best = $_.FullName }
}
if ($best) { Copy-Item $best $shot -Force; Write-Host "dashboard screenshot: $shot (colors=$bestColors)" }
Get-ChildItem -Path $shotDir -Filter 'frame-*.png' -ErrorAction SilentlyContinue | Remove-Item -Force
if ($test.ExitCode -ne 0) { throw "dashboard journey failed with exit code $($test.ExitCode)" }
if (-not (Test-Path $shot)) { throw 'no dashboard screenshot was captured' }
Pop-Location
