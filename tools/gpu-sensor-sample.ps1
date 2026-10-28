param([int]$Seconds = 30, [int]$EveryMs = 1500)
$ErrorActionPreference = 'Stop'
. (Join-Path (Join-Path (Split-Path $PSScriptRoot) 'app') 'om3n-command-lib.ps1')
Import-Dash
[Dash]::Start($EveryMs)
Start-Sleep -Milliseconds ($EveryMs * 2)
$keys = 'gpuLoad', 'gpuMHz', 'gpuMv', 'gpuTemp', 'gpuHot', 'gpuMemTemp', 'gpuW', 'gpuFanRpm'
$rows = @()
$end = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $end) {
  $d = [Dash]::Snapshot()
  $rows += , ($keys | ForEach-Object { if ($d.ContainsKey($_)) { $d[$_] } else { [double]::NaN } })
  '{0:HH:mm:ss}  ' -f (Get-Date) + (($keys | ForEach-Object -Begin { $i = 0 } -Process { '{0}={1:N0}' -f $_, $rows[-1][$i]; $i++ }) -join '  ')
  Start-Sleep -Milliseconds $EveryMs
}
'--- summary over {0} samples (min / avg / max)' -f $rows.Count
for ($i = 0; $i -lt $keys.Count; $i++) {
  $v = $rows | ForEach-Object { $_[$i] } | Where-Object { -not [double]::IsNaN($_) } | Measure-Object -Minimum -Average -Maximum
  '  {0,-10} {1,7:N0} {2,7:N0} {3,7:N0}' -f $keys[$i], $v.Minimum, $v.Average, $v.Maximum
}
if ([Dash]::Problems) { 'sampler problems: ' + ([Dash]::Problems -replace "`n", ' | ') }
