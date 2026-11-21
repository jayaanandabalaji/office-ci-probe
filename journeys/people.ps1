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
for ($i = 0; $i -lt 60; $i++) {{
  try {{ if ((Invoke-WebRequest 'http://127.0.0.1:8120/api/health' -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200) {{ $ok = $true; break }} }} catch {{}}
  Start-Sleep -Seconds 2
}}
if (-not $ok) {{ throw 'backend did not become healthy' }}
Pop-Location
Push-Location "$env:GITHUB_WORKSPACE\app"
$shotDir = Join-Path $env:GITHUB_WORKSPACE 'verification'
New-Item -ItemType Directory -Force -Path $shotDir | Out-Null
$shot = Join-Path $shotDir 'dashboard.png'
$testScript = Join-Path $env:RUNNER_TEMP 'run-dashboard-test.ps1'
@'
flutter test -d windows integration_test/dashboard_smoke_test.dart `
--no-pub --timeout=600s --reporter=expanded `
--dart-define=API_URL=http://127.0.0.1:8120
'@ | Set-Content -Path $testScript -Encoding utf8
$outLog = Join-Path $env:RUNNER_TEMP 'dashboard-test.out.log'
$errLog = Join-Path $env:RUNNER_TEMP 'dashboard-test.err.log'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
if (-not ('WinCap' -as [type])) {
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class WinCap {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static IntPtr FindAppWindow() {
    IntPtr best = IntPtr.Zero; long bestArea = 0;
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      if (!IsWindowVisible(h)) return true;
      var sb = new StringBuilder(256); GetClassName(h, sb, 256);
      var cn = sb.ToString();
      if (cn.IndexOf("FLUTTER", StringComparison.OrdinalIgnoreCase) >= 0) {
        RECT r; GetWindowRect(h, out r);
        long area = (long)(r.Right - r.Left) * (r.Bottom - r.Top);
        if (area > bestArea) { bestArea = area; best = h; }
      }
      return true;
    }, IntPtr.Zero);
    return best;
  }
}
'@
}
$test = Start-Process pwsh -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File', $testScript -PassThru -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog
$frame = 0
$deadline = (Get-Date).AddMinutes(20)
while (-not $test.HasExited -and (Get-Date) -lt $deadline) {
  try {
    $h = [WinCap]::FindAppWindow()
    if ($h -ne [IntPtr]::Zero) {
      [void][WinCap]::ShowWindow($h, 9)
      [void][WinCap]::SetForegroundWindow($h)
      Start-Sleep -Milliseconds 500
      $r = New-Object WinCap+RECT
      [void][WinCap]::GetWindowRect($h, [ref]$r)
      $w = $r.Right - $r.Left
      $ht = $r.Bottom - $r.Top
      if ($w -gt 0 -and $ht -gt 0) {
        $m = New-Object System.Drawing.Bitmap $w, $ht
        $g = [System.Drawing.Graphics]::FromImage($m)
        $g.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size($w, $ht)))
        $m.Save((Join-Path $shotDir ('frame-{0:d3}.png' -f $frame)), [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $m.Dispose()
        $frame++
      }
    }
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
  for ($y = 0; $y -lt $bmp.Height; $y += 8) { for ($x = 0; $x -lt $bmp.Width; $x += 8) { $colors[$bmp.GetPixel($x, $y).ToArgb()] = 1 } }
  $bmp.Dispose()
  if ($colors.Count -gt $bestColors) { $bestColors = $colors.Count; $best = $_.FullName }
}
if ($best) { Copy-Item $best $shot -Force; Write-Host "dashboard screenshot: $shot (colors=$bestColors)" }
Get-ChildItem -Path $shotDir -Filter 'frame-*.png' -ErrorAction SilentlyContinue | Remove-Item -Force
if ($test.ExitCode -ne 0) { throw "dashboard journey failed with exit code $($test.ExitCode)" }
if (-not (Test-Path $shot)) { throw 'no dashboard screenshot was captured' }
Pop-Location
