param([string]$Arms = '0,-100,0', [int]$Threads = 4, [int]$LoadSec = 75, [int]$SkipSec = 15, [int]$MaxTemp = 85, [int]$StartBelow = 60, [int]$EndOffset = -100)
$ErrorActionPreference = 'Stop'
$ctl = Join-Path (Join-Path (Split-Path $PSScriptRoot) 'app') 'om3n-command.ps1'
function Get-CpuTemp {
  $s = (Get-Counter '\Thermal Zone Information(*)\Temperature').CounterSamples | Where-Object { $_.InstanceName -match 'hptz' } | Select-Object -First 1
  [int]($s.CookedValue - 273)
}
function Get-Active([string]$id) {
  $line = & $ctl cpu | Where-Object { $_ -match "^$id " } | Select-Object -First 1
  $w = @("$line" -split '\s+' | Where-Object { $_ }); if ($w.Count -ge 7) { $w[-5] } else { '?' }
}
$burn = {
  param($sec)
  (Get-Process -Id $PID).PriorityClass = 'BelowNormal'
  $end = (Get-Date).AddSeconds($sec)
  while ((Get-Date) -lt $end) { $x = 1.0; for ($i = 0; $i -lt 300000; $i++) { $x = $x * 1.0000001 } }
}
$meters = (Get-Counter -ListSet 'Energy Meter').PathsWithInstances | Where-Object { $_ -match '\\Power$' -and $_ -match 'pkg|pp0' }
"energy meters: $($meters -join ', ')"
$tdp0 = Get-Active '0x00000030'
"start: offset 0x22 = $(Get-Active '0x00000022'), package power limit 0x30 = $tdp0"
$results = @()
try {
  foreach ($arm in ($Arms -split ',' | ForEach-Object { [int]$_.Trim() })) {
    $set = & $ctl cpu -ControlId 0x22 -Value $arm | Where-Object { $_ -match 'ApplyChanges|FAILED|ABORT' } | Select-Object -First 1
    $waited = 0
    while ((Get-CpuTemp) -ge $StartBelow -and $waited -lt 120) { Start-Sleep -Seconds 5; $waited += 5 }
    '{0:HH:mm:ss} arm {1} mV: {2} | start {3} C after {4} s' -f (Get-Date), $arm, "$set".Trim(), (Get-CpuTemp), $waited
    $jobs = 1..$Threads | ForEach-Object { Start-Job -ScriptBlock $burn -ArgumentList $LoadSec }
    Start-Sleep -Seconds $SkipSec
    $pkg = @(); $pp0 = @(); $tmp = @(); $perf = @(); $t = $SkipSec; $note = ''
    while ($t -lt $LoadSec - 5) {
      $c = (Get-Counter ($meters + '\Processor Information(_Total)\% Processor Performance') -SampleInterval 5 -MaxSamples 1).CounterSamples
      $t += 5
      $pkg += [Math]::Round((($c | Where-Object { $_.Path -match 'pkg' }).CookedValue | Measure-Object -Sum).Sum / 1000, 1)
      $pp0 += [Math]::Round((($c | Where-Object { $_.Path -match 'pp0' }).CookedValue | Measure-Object -Sum).Sum / 1000, 1)
      $perf += [int](($c | Where-Object { $_.Path -match 'Processor Performance' }).CookedValue)
      $now = Get-CpuTemp; $tmp += $now
      if ($now -ge $MaxTemp) { $note = " STOPPED EARLY at $now C"; break }
    }
    $jobs | Stop-Job; $jobs | Remove-Job -Force
    $avg = { param($a) [Math]::Round(($a | Measure-Object -Average).Average, 1) }
    '         package W {0}   cores W {1}   temp C {2}   clock % {3}{4}' -f ($pkg -join ' '), ($pp0 -join ' '), ($tmp -join ' '), ($perf -join ' '), $note
    $results += [pscustomobject]@{ Arm = $arm; Pkg = (& $avg $pkg); Pp0 = (& $avg $pp0); Temp = (& $avg $tmp); Perf = (& $avg $perf) }
  }
} finally {
  Get-Job | Remove-Job -Force
  & $ctl cpu -ControlId 0x22 -Value $EndOffset | Where-Object { $_ -match 'ApplyChanges|FAILED|ABORT' } | Select-Object -First 1
  if ($tdp0 -ne '?' -and (Get-Active '0x00000030') -ne $tdp0) {
    & $ctl cpu -ControlId 0x30 -Value ([int][double]$tdp0) | Where-Object { $_ -match 'ApplyChanges|FAILED|ABORT' } | Select-Object -First 1
  }
  "end: offset 0x22 = $(Get-Active '0x00000022'), package power limit 0x30 = $(Get-Active '0x00000030')"
}
'RESULT (averages under load):'
$results | ForEach-Object { '  offset {0,5} mV   package {1,6} W   cores {2,6} W   temp {3,5} C   clock {4,4} %' -f $_.Arm, $_.Pkg, $_.Pp0, $_.Temp, $_.Perf }
