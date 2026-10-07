param([int]$EverySec = 1, [int]$KeepDays = 14, [switch]$ReportOnly, [switch]$Library)
if (-not $Library) { $ErrorActionPreference = 'Stop' }
$bbState = Join-Path $env:ProgramData 'SkYn3tLab'; $bbDir = Join-Path $bbState 'telemetry'
if (-not (Test-Path $bbDir)) { New-Item -ItemType Directory -Path $bbDir -Force | Out-Null }
trap { try { Add-Content (Join-Path $bbDir 'blackbox-errors.log') ("{0:yyyy-MM-dd HH:mm:ss} $_  at: $($_.ScriptStackTrace -replace "`r?`n", ' <- ')" -f (Get-Date)) } catch { }; break }
$bbCols = 'cpuTemp', 'cpuLoad', 'cpuMHz', 'cpuW', 'coresW', 'gpuTemp', 'gpuHot', 'gpuMemTemp', 'gpuLoad', 'gpuMHz', 'gpuMemMHz', 'gpuMv', 'gpuW', 'gpuFanPct', 'gpuFanRpm', 'vramGB', 'memUsedGB', 'driveTemp'
$bbHeader = 'time,' + ($bbCols -join ',') + ',foreground'

function Write-Through([string]$path, [string]$line) {
  $fs = New-Object IO.FileStream $path, ([IO.FileMode]::Append), ([IO.FileAccess]::Write), ([IO.FileShare]::ReadWrite), 4096, ([IO.FileOptions]::WriteThrough)
  try { $b = [Text.Encoding]::UTF8.GetBytes($line + "`r`n"); $fs.Write($b, 0, $b.Length); $fs.Flush($true) } finally { $fs.Close() }
}

function Write-CrashReport {
  $ev = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41 } -MaxEvents 1 -ErrorAction SilentlyContinue
  if (-not $ev) { return }
  $mark = Join-Path $bbDir 'last-crash-reported.txt'
  $done = if (Test-Path $mark) { [datetime](Get-Content $mark -First 1) } else { [datetime]::MinValue }
  if ($ev.TimeCreated -le $done.AddSeconds(1)) { return }
  $x = [xml]$ev.ToXml(); $bug = ($x.Event.EventData.Data | Where-Object { $_.Name -eq 'BugcheckCode' }).'#text'
  $back = $ev.TimeCreated
  $lines = @(Get-ChildItem $bbDir -Filter 'telemetry-*.csv' | Sort-Object Name | Where-Object { $_.LastWriteTime -ge $back.AddDays(-2) } | ForEach-Object { Get-Content $_.FullName } |
      Where-Object { $_ -match '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d,' -and $_.Substring(0, 19) -lt $back.ToString('yyyy-MM-dd HH:mm:ss') })
  $tail = @($lines | Select-Object -Last ([int](180 / $EverySec)))
  $r = New-Object Collections.ArrayList
  [void]$r.Add("Unclean shutdown: Windows came back at $($back.ToString('yyyy-MM-dd HH:mm:ss')) after stopping without a clean shutdown.")
  [void]$r.Add("Bugcheck code: $bug  (0 = no blue screen: a hard freeze, a reset or a loss of power; anything else is a blue-screen code)")
  $dump = Get-ChildItem C:\Windows\Minidump -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $back.AddMinutes(-30) } | Select-Object -First 1
  [void]$r.Add("Minidump: $(if ($dump) { $dump.FullName } else { 'none written' })")
  if ($tail) {
    $last = $tail[-1].Substring(0, 19)
    [void]$r.Add("Last reading: $last, $([int]($back - [datetime]$last).TotalSeconds) s before Windows came back (that gap is the restart).")
    [void]$r.Add(''); [void]$r.Add("The last $($tail.Count) readings before it went down:"); [void]$r.Add($bbHeader); $tail | ForEach-Object { [void]$r.Add($_) }
  } else {
    [void]$r.Add('Last reading: none. The black box was not running before this shutdown, so there are no readings for it.')
  }
  [void]$r.Add(''); [void]$r.Add('Settings changed before it (om3n-command-changes.log, newest last):')
  $j = Join-Path $bbState 'om3n-command-changes.log'
  if (Test-Path $j) { Get-Content $j | Where-Object { $_.Length -ge 19 -and $_.Substring(0, 19) -lt $back.ToString('yyyy-MM-dd HH:mm:ss') } | Select-Object -Last 20 | ForEach-Object { [void]$r.Add("  $_") } } else { [void]$r.Add('  (no settings journal yet)') }
  [void]$r.Add(''); [void]$r.Add('Sign-in list (what is re-applied at every sign-in):')
  $s = Join-Path $env:ProgramData 'SkYn3tLab\om3n-command-startup.txt'
  if (Test-Path $s) { Get-Content $s | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' } | ForEach-Object { [void]$r.Add("  om3n-command $_") } }
  [void]$r.Add(''); [void]$r.Add('Hardware-error records (WHEA) in the hour before:')
  $w = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $back.AddHours(-1); EndTime = $back.AddMinutes(5) } -ErrorAction SilentlyContinue)
  if ($w) { $w | Group-Object Id | ForEach-Object { [void]$r.Add("  id $($_.Name): $($_.Count)  (17 = corrected PCI Express error, routine on this PC; 18/19 = processor)") } } else { [void]$r.Add('  none') }
  $out = Join-Path $bbDir ('crash-{0:yyyyMMdd-HHmmss}.txt' -f $back)
  Set-Content $out $r; Set-Content $mark $back.ToString('o')
  "crash report written: $out"
}

function Write-ResetReport {
  param([switch]$Again, [string]$Reports = (Join-Path $env:SystemRoot 'LiveKernelReports\WATCHDOG'))
  $d = Get-ChildItem (Join-Path $Reports '*.dmp') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
  if (-not $d) { return }
  $mark = Join-Path $bbDir 'last-reset-reported.txt'; $at = $d.LastWriteTime; $stamp = $at.ToString('yyyy-MM-dd HH:mm:ss')
  $done = if (Test-Path $mark) { "$(Get-Content $mark -First 1)".Trim() } else { $null }
  if (-not $Again) { if ($null -eq $done) { Set-Content $mark $stamp; return }; if ($stamp -le $done) { return } }
  $r = New-Object Collections.ArrayList
  [void]$r.Add("Graphics driver reset: Windows reported it at $stamp (the card stopped answering and its driver was restarted).")
  [void]$r.Add("Reports: $((Get-ChildItem (Split-Path $Reports) -Recurse -File -ErrorAction SilentlyContinue | Where-Object { [Math]::Abs(($_.LastWriteTime - $at).TotalSeconds) -le 120 } | ForEach-Object { $_.Name }) -join ', ')")
  [void]$r.Add("Resets on record: $(@(Get-ChildItem (Join-Path $Reports '*.dmp')).Count) reports in that folder. Open the newest with gpu-reset-dumps.ps1.")
  $lines = @(Get-ChildItem $bbDir -Filter 'telemetry-*.csv' | Sort-Object Name | Where-Object { $_.LastWriteTime -ge $at.AddDays(-1) } | ForEach-Object { Get-Content $_.FullName } |
      Where-Object { $_ -match '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d,' -and $_.Substring(0, 19) -le $at.AddSeconds(30).ToString('yyyy-MM-dd HH:mm:ss') })
  $tail = @($lines | Select-Object -Last ([int](210 / $EverySec)))
  [void]$r.Add(''); [void]$r.Add("The $($tail.Count) readings up to 30 s after it:"); [void]$r.Add($bbHeader); $tail | ForEach-Object { [void]$r.Add($_) }
  [void]$r.Add(''); [void]$r.Add('Readings held in memory (oldest first, one a second, ending now; a blank means the card gave none):')
  foreach ($k in 'gpuW', 'gpuMv', 'gpuMHz', 'gpuLoad', 'gpuHot', 'cpuW', 'cpuTemp') { try { [void]$r.Add(('  {0,-8} {1}' -f $k, ((@([Dash]::History($k)) | Select-Object -Last 80 | ForEach-Object { [int]$_ }) -join ' '))) } catch { } }
  [void]$r.Add(''); [void]$r.Add('Settings changed before it (om3n-command-changes.log, newest last):')
  $j = Join-Path $bbState 'om3n-command-changes.log'
  if (Test-Path $j) { Get-Content $j | Where-Object { $_.Length -ge 19 -and $_.Substring(0, 19) -le $stamp } | Select-Object -Last 12 | ForEach-Object { [void]$r.Add("  $_") } }
  [void]$r.Add(''); [void]$r.Add('Sign-in list (what is re-applied at every sign-in):')
  $s = Join-Path $env:ProgramData 'SkYn3tLab\om3n-command-startup.txt'
  if (Test-Path $s) { Get-Content $s | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' } | ForEach-Object { [void]$r.Add("  om3n-command $_") } }
  [void]$r.Add(''); [void]$r.Add("Programs with a window when this was written ($(Get-Date -Format 'HH:mm:ss')): $((Get-Process | Where-Object { $_.MainWindowTitle } | ForEach-Object { $_.Name } | Sort-Object -Unique) -join ', ')")
  [void]$r.Add("Uptime: $([int]((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalMinutes) min since Windows started.")
  [void]$r.Add(''); [void]$r.Add('Hardware-error records (WHEA) in the hour before:')
  $w = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $at.AddHours(-1); EndTime = $at.AddMinutes(2) } -ErrorAction SilentlyContinue)
  if ($w) { $w | Group-Object Id | ForEach-Object { [void]$r.Add("  id $($_.Name): $($_.Count)  (17 = corrected PCI Express error, routine on this PC)") } } else { [void]$r.Add('  none') }
  $out = Join-Path $bbDir ('reset-{0:yyyyMMdd-HHmmss}.txt' -f $at)
  Set-Content $out $r; Set-Content $mark $stamp
  "RESET: the graphics driver was reset at $stamp; report written: $out"
}

$bbInv = [Globalization.CultureInfo]::InvariantCulture
function Write-Reading {
  $now = Get-Date; $file = Join-Path $bbDir ('telemetry-{0:yyyy-MM-dd}.csv' -f $now)
  if ((Test-Path $file) -and (Get-Content $file -First 1) -ne $bbHeader) { Move-Item $file ($file -replace '\.csv$', ('-until-{0:HHmmss}.csv' -f $now)) }
  if (-not (Test-Path $file)) { Write-Through $file $bbHeader }
  $d = [Dash]::Snapshot()
  $vals = foreach ($c in $bbCols) { if ($d.ContainsKey($c)) { [Math]::Round($d[$c], 1).ToString($bbInv) } else { '' } }
  Write-Through $file (($now.ToString('yyyy-MM-dd HH:mm:ss')) + ',' + ($vals -join ',') + ',' + [Dash]::Foreground())
}
function Remove-OldReadings { Get-ChildItem $bbDir -Include 'telemetry-*.csv', 'crash-*.txt' -Recurse | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$KeepDays) } | Remove-Item -ErrorAction SilentlyContinue }
if ($Library) { return }

Write-CrashReport
if ($ReportOnly) { return }

$mutex = New-Object Threading.Mutex $false, 'Global\SkYn3tLab-om3n-command-blackbox'
if (-not $mutex.WaitOne(0)) { 'the black box is already running (the app records while it runs)'; return }

. (Join-Path $PSScriptRoot 'om3n-command-lib.ps1')
Import-Dash
[Dash]::Start([Math]::Max(1000, $EverySec * 500))
Start-Sleep -Seconds 4
Remove-OldReadings
try { while ($true) { Write-Reading; Start-Sleep -Seconds $EverySec } } finally { $mutex.ReleaseMutex() }
