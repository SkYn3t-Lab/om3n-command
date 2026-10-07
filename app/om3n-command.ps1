param(
  [Parameter(Position = 0)][ValidateSet('status', 'sensors', 'fan', 'profile', 'selftest', 'gpu', 'cpu', 'light', 'lights', 'memory', 'display', 'startup', 'log', 'state', 'app')][string]$Command = 'status',
  [Parameter(Position = 1)][string]$Mode = '',
  [Parameter(Position = 2)][ValidateRange(-1, 255)][int]$Red = -1,
  [Parameter(Position = 3)][ValidateRange(-1, 255)][int]$Green = -1,
  [Parameter(Position = 4)][ValidateRange(-1, 255)][int]$Blue = -1,
  [switch]$Simulate, [switch]$PretendCrash, [switch]$Once, [int]$Seconds = 60, [int]$Interval = 5, [switch]$Background, [string]$ResetReports = '',
  [int]$QuietBelow = 50, [int]$TurboAbove = 75, [int]$Hysteresis = 5, [int]$DownAfter = 60,
  [uint32]$ControlId = 0, [string]$Value = '', [string[]]$FanCurve = @(),
  [ValidateSet('static', 'off', 'breathing', 'cycle', 'blinking', 'wave', 'spiral', 'vitals', 'audio')][string]$Effect = 'static',
  [ValidateSet('custom', 'galaxy', 'volcano', 'jungle', 'ocean', 'unicorn', 'arcane', 'valorant', 'omen', 'hyperx')][string]$Theme = 'custom',
  [ValidateSet('slow', 'medium', 'fast')][string]$Speed = 'medium',
  [ValidateSet(0, 1)][int]$Direction = 0,
  [string]$Setting = '', [switch]$Reset,
  [ValidateSet('', 'antilag', 'boost', 'sharpen', 'chill', 'framecap', 'rsr', 'afmf', 'led')][string]$Feature = '', [ValidateSet(-1, 0, 1)][int]$Enable = -1,
  [int]$Display = -1, [string]$Set = '',
  [ValidateSet(0, 25, 50, 75, 100)][int]$Brightness = 100,
  [string]$Colors = '', [ValidateSet('wake', 'sleep')][string]$State = 'wake', [ValidateSet('level', 'bass', 'treble')][string]$Band = 'level',
  [ValidateSet('cpuload', 'gpuload', 'cputemp', 'gputemp')][string]$Source = 'cputemp', [ValidateSet(1, 2)][int]$Preset = 1
)
$ErrorActionPreference = 'Stop'
$modeByte = @{ quiet = 0x10; normal = 0x20; turbo = 0x30 }
$stateDir = Join-Path $env:ProgramData 'SkYn3tLab'
function Write-Journal([string]$text) {
  try {
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir | Out-Null }
    $fs = New-Object IO.FileStream (Join-Path $stateDir 'om3n-command-changes.log'), ([IO.FileMode]::Append), ([IO.FileAccess]::Write), ([IO.FileShare]::ReadWrite), 4096, ([IO.FileOptions]::WriteThrough)
    try { $b = [Text.Encoding]::UTF8.GetBytes(('{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $PID, $text) + "`r`n"); $fs.Write($b, 0, $b.Length); $fs.Flush($true) } finally { $fs.Close() }
  } catch { }
}
$stateFile = Join-Path $stateDir 'om3n-command-fanmode.txt'

function Get-CpuTemp {
  $s = (Get-Counter '\Thermal Zone Information(*)\Temperature').CounterSamples
  $cpu = $s | Where-Object { $_.InstanceName -match 'hptz' } | Select-Object -First 1
  if (-not $cpu) { throw 'thermal zone hptz not found' }
  [int]($cpu.CookedValue - 273)
}
function Get-LastMode { if (Test-Path $stateFile) { (Get-Content $stateFile -TotalCount 1).Trim() } else { 'unknown' } }
function Invoke-Bios([uint32]$command, [uint32]$type, [byte[]]$data) {
  $inst = Get-CimInstance -Namespace root\wmi -ClassName hpqBIntM
  $in = New-CimInstance -Namespace root\wmi -ClassName hpqBDataIn -ClientOnly -Property @{
    Sign = [byte[]](0x53, 0x45, 0x43, 0x55); Command = $command; CommandType = $type; Size = [uint32]4; hpqBData = $data
  }
  (Invoke-CimMethod -InputObject $inst -MethodName hpqBIOSInt4 -Arguments @{ InData = $in }).OutData.rwReturnCode
}
function Set-FanMode([string]$m) {
  $rc = Invoke-Bios 0x20008 0x1A ([byte[]](0xFF, $modeByte[$m], 0, 0))
  if ($rc -ne 0) { throw "the BIOS returned code $rc for fan mode $m" }
  if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir | Out-Null }
  Set-Content -Path $stateFile -Value $m
}
$autoFile = Join-Path $stateDir 'om3n-command-auto.pid'
$autoLog = Join-Path $stateDir 'om3n-command-auto.log'
function Get-AutoProcess {
  if (-not (Test-Path $autoFile)) { return }
  $id = [int](Get-Content $autoFile -TotalCount 1)
  Get-CimInstance Win32_Process -Filter "ProcessId=$id" | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -match 'om3n-command\.ps1"? profile' }
}
function Stop-Auto {
  $p = Get-AutoProcess
  if ($p) { Stop-Process -Id $p.ProcessId -Force }
  Remove-Item $autoFile -ErrorAction SilentlyContinue
  [bool]$p
}
function Select-Mode([int]$t, [string]$current) {
  switch ($current) {
    'turbo'  { if ($t -ge ($TurboAbove - $Hysteresis)) { 'turbo' } elseif ($t -lt ($QuietBelow - $Hysteresis)) { 'quiet' } else { 'normal' } }
    'normal' { if ($t -ge $TurboAbove) { 'turbo' } elseif ($t -lt ($QuietBelow - $Hysteresis)) { 'quiet' } else { 'normal' } }
    'quiet'  { if ($t -ge $TurboAbove) { 'turbo' } elseif ($t -ge $QuietBelow) { 'normal' } else { 'quiet' } }
    default  { if ($t -ge $TurboAbove) { 'turbo' } elseif ($t -lt $QuietBelow) { 'quiet' } else { 'normal' } }
  }
}
function Test-SelectMode {
  $m = 'quiet'; $seen = @()
  foreach ($t in (40..80) + (79..40)) { $n = Select-Mode $t $m; if ($n -ne $m) { $seen += "$t`:$n"; $m = $n } }
  $want = "$QuietBelow`:normal $TurboAbove`:turbo $($TurboAbove - $Hysteresis - 1)`:normal $($QuietBelow - $Hysteresis - 1)`:quiet"
  if (($seen -join ' ') -ne $want) { throw "mode selection is wrong: got '$($seen -join ' ')', expected '$want'" }
  "selftest ok: $want"
}

function ConvertFrom-CpuLines([string[]]$lines) {
  $o = [ordered]@{}
  foreach ($l in $lines) {
    if ($l -notmatch '^(0x[0-9A-F]{8}) ') { continue }
    $w = @($l -split '\s+' | Where-Object { $_ })
    $k = [Math]::Max([Array]::LastIndexOf($w, 'rw'), [Array]::LastIndexOf($w, 'ro')); if ($k -lt 5) { continue }
    $o[$w[0]] = [ordered]@{ name = $(if ($k -gt 5) { $w[1..($k - 5)] -join ' ' } else { '' }); default = [double]$w[$k - 4]; active = [double]$w[$k - 3]; boot = [double]$w[$k - 2]; proposed = [double]$w[$k - 1]
      writable = ($w[$k] -eq 'rw'); range = $(if ($k + 1 -lt $w.Count) { $w[$k + 1] } else { '' }) }
  }
  $o
}
function ConvertFrom-GpuLines([string[]]$lines) {
  $g = [ordered]@{ sensors = [ordered]@{}; settings = [ordered]@{}; features = [ordered]@{} }
  foreach ($l in $lines) {
    if ($l -match '^\s*sensor\s+\d+\s+(\S+)\s+=\s+(-?\d+)') { $g.sensors[$Matches[1]] = [int]$Matches[2] }
    elseif ($l -match '^\s*setting\s+(\d+)\s+(\S+)\s+min=(-?\d+)\s+max=(-?\d+)\s+default=(-?\d+)\s+current=(-?\d+)') {
      $g.settings[$Matches[2]] = [ordered]@{ id = [int]$Matches[1]; min = [int]$Matches[3]; max = [int]$Matches[4]; default = [int]$Matches[5]; current = [int]$Matches[6] }
    }
    elseif ($l -match '^\s*(Anti-Lag|Radeon Boost|Image Sharpening|Radeon Chill|Frame rate target)\s+(.*)$') {
      $f = [ordered]@{}; foreach ($m in [regex]::Matches($Matches[2], '(\w[\w ]*?)=(-?\d+)')) { $f[$m.Groups[1].Value.Trim()] = [int]$m.Groups[2].Value }
      $g.features[$Matches[1]] = $f
    }
  }
  $g
}
function Test-Parsers {
  $c = ConvertFrom-CpuLines @(
    '0x00000030 TurboPackageTdpExtended                          125.000   170.000       125   170.000  rw 1.000..4095.875',
    '0x0000002F                                                  250.000       250       250       250  rw 1.000..4095.875',
    '0x00000022 CpuVoltageOffset                                       0       -90         0       -90  rw -1000..4294967295',
    '0x0000001D Max Turbo for 1 Cores                                 51        47        51        47  rw 8..120',
    '0x00000050                                                        1         1         1         1  ro 0..1',
    '0xD0000002                                                 5100.000  5100.000  5100.000  5100.000  ro ',
    'controls=64')
  $g = ConvertFrom-GpuLines @(
    '    sensor  27 TEMPERATURE_HOTSPOT          = 66',
    '    setting 37 OD_VOLTAGE                                   min=700     max=1150    default=1150    current=1100  (featureID 0x20000)',
    '    setting  9 POWER_PERCENTAGE                             min=-10     max=15      default=0       current=-5  (featureID 0x8)',
    '      Image Sharpening   rc=0  on=0  sharpness=80 % (range 10..100 step 10)',
    '      Radeon Chill       rc=0  supported=1  on=0  fps min=75 max=140 (range 30..300 step 1)  (get rc=0)')
  $got = "$($c.Count) $($c['0x00000030'].active) $($c['0x0000002F'].name -eq '') $($c['0x00000022'].active) $($c['0x0000001D'].name)|$($c['0x0000001D'].active) $($c['0x00000050'].writable) $($c['0xD0000002'].active)" +
    " / $($g.sensors.TEMPERATURE_HOTSPOT) $($g.settings.OD_VOLTAGE.current) $($g.settings.POWER_PERCENTAGE.current) $($g.settings.POWER_PERCENTAGE.min) $($g.features['Image Sharpening'].sharpness) $($g.features['Radeon Chill'].on) $($g.features['Radeon Chill'].'fps min')"
  $want = '6 170 True -90 Max Turbo for 1 Cores|47 False 5100 / 66 1100 -5 -10 80 0 75'
  if ($got -ne $want) { throw "the state parsers are wrong: got '$got', expected '$want'" }
  "selftest ok: parsers ($want)"
}

$changes = switch ($Command) {
  'fan' { $Mode -ne '' -and -not $Background }
  'cpu' { [bool]$ControlId }
  'gpu' { ($Setting -and ($Value -ne '' -or $Reset)) -or ($Feature -and $Enable -ge 0) -or [bool]$FanCurve }
  'light' { $true }
  'lights' { $Mode -ne '' }
  'memory' { $Mode -ne '' }
  'display' { $Set -ne '' }
  'startup' { $Mode -in 'on', 'off', 'restore', 'drop' }
  'log' { $Mode -in 'on', 'off' }
  'app' { $Mode -in 'on', 'off', 'restart' }
  default { $false }
}
if ($Simulate) { $changes = $false }
$what = (@($Command) + @($PSBoundParameters.GetEnumerator() | Where-Object { $_.Key -ne 'Command' } | ForEach-Object { if ($_.Key -eq 'Mode') { "$($_.Value)" } else { "-$($_.Key) $($_.Value -join ',')" } })) -join ' '
if ($changes) { Write-Journal "START om3n-command $what" }
$finished = $false; $soft = $false
try {
& {
switch ($Command) {
  'log' {
    $tdir = Join-Path $stateDir 'telemetry'; $flag = Join-Path $tdir 'recording-off.txt'
    $today = Join-Path $tdir ('telemetry-{0:yyyy-MM-dd}.csv' -f (Get-Date))
    switch ($Mode) {
      '' {
        "black box: $(if (Test-Path $flag) { 'off (switched off with "log off")' } else { 'on' })"
        $age = if (Test-Path $today) { [int]((Get-Date) - (Get-Item $today).LastWriteTime).TotalSeconds } else { -1 }
        "  recording: $(if ($age -ge 0 -and $age -le 20) { "yes, the latest reading is $age s old" } else { 'NO reading in the last 20 s (the app records while it runs: see "om3n-command.ps1 app")' })"
        if (Test-Path $today) { $n = @(Get-Content $today).Count - 1; "  today: $n readings in $today"; "  latest: $(Get-Content $today -Tail 1)" } else { "  today: no readings yet ($today)" }
        $c = @(Get-ChildItem $tdir -Filter 'crash-*.txt' -ErrorAction SilentlyContinue | Sort-Object Name)
        "  crash reports: $($c.Count)$(if ($c) { ', newest ' + $c[-1].FullName })"
        "  settings journal: $(Join-Path $stateDir 'om3n-command-changes.log')"
        $e = Join-Path $tdir 'blackbox-errors.log'; if (Test-Path $e) { "  recorder's last error: $(Get-Content $e -Tail 1)" }
      }
      'on' { Remove-Item $flag -ErrorAction SilentlyContinue; 'black box: on. The app records while it runs.' }
      'off' { if (-not (Test-Path $tdir)) { New-Item -ItemType Directory -Path $tdir -Force | Out-Null }; Set-Content $flag ('switched off {0:yyyy-MM-dd HH:mm:ss}' -f (Get-Date)); 'black box: off. The app stops recording within a few seconds.' }
      'show' { if (Test-Path $today) { Get-Content $today -First 1; Get-Content $today -Tail 12 } else { "no readings today ($today)" } }
      'crash' { $c = @(Get-ChildItem $tdir -Filter 'crash-*.txt' -ErrorAction SilentlyContinue | Sort-Object Name); if ($c) { $c[-1].FullName; Get-Content $c[-1].FullName } else { 'no crash report has been written' } }
      'changes' { $j = Join-Path $stateDir 'om3n-command-changes.log'; if (Test-Path $j) { Get-Content $j -Tail 30 } else { 'no setting has been changed since the journal began' } }
      default { throw 'log takes: nothing (state), on, off, show, crash, or changes' }
    }
  }
  'app' {
    $ui = Join-Path $PSScriptRoot 'om3n-command-ui.ps1'; $tApp = 'SkYn3tLab-om3n-command-app'; $tOpen = 'SkYn3tLab-om3n-command-open'
    switch ($Mode) {
      '' {
        foreach ($t in $tApp, $tOpen) { $x = Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue; "app: task $t $(if ($x) { "present ($($x.State))" } else { 'absent' })" }
        $p = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'om3n-command-ui\.ps1' })
        "app: $(if ($p) { "running (process $($p.ProcessId -join ', '))" } else { 'not running' })"
      }
      'on' {
        if (-not (Test-Path $ui)) { throw "om3n-command-ui.ps1 must sit beside om3n-command.ps1 ($ui not found)" }
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Highest
        $run = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ui`""
        $atSignIn = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -Priority 4
        $onDemand = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances Parallel -Priority 4
        Register-ScheduledTask -TaskName $tApp -Action (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "$run -Tray") -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $me) -Principal $principal -Settings $atSignIn -Force | Out-Null
        Register-ScheduledTask -TaskName $tOpen -Action (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $run) -Principal $principal -Settings $onDemand -Force | Out-Null
        $old = 'SkYn3tLab-om3n-command-blackbox'
        if (Get-ScheduledTask -TaskName $old -ErrorAction SilentlyContinue) { Stop-ScheduledTask -TaskName $old -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName $old -Confirm:$false; "app: the separate recorder task $old is removed (the app records)" }
        "app: on. It starts in the notification area at every sign-in of $me, and the desktop shortcut opens it with no administrator prompt."
      }
      'off' {
        foreach ($t in $tApp, $tOpen) { Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue }
        "app: off (tasks present = $([bool](Get-ScheduledTask -TaskName $tApp -ErrorAction SilentlyContinue)), $([bool](Get-ScheduledTask -TaskName $tOpen -ErrorAction SilentlyContinue))). Om3n Command.cmd still starts it, with the administrator prompt."
      }
      'restart' {
        $p = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'om3n-command-ui\.ps1' -and $_.CommandLine -notmatch 'SelfTest|OffScreen' })
        $p | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
        Start-Sleep -Seconds 1; Start-ScheduledTask -TaskName $tApp
        "app: restarted in the notification area ($($p.Count) running app ended)"
      }
      default { throw 'app takes: nothing (state), on, off, or restart' }
    }
  }
  'selftest' {
    Test-SelectMode; Test-Parsers
    . (Join-Path $PSScriptRoot 'om3n-command-lib.ps1'); . (Join-Path $PSScriptRoot 'om3n-command-hold.ps1')
    Test-HoldPlan | Select-Object -Last 1
    & (Join-Path $PSScriptRoot 'om3n-command-history.ps1') -HistoryTest alerts | Select-Object -Last 1
  }
  'state' {
    if ($Mode -notin '', 'cpu', 'gpu') { throw 'state takes: nothing (everything), cpu, or gpu' }
    $o = [ordered]@{ time = (Get-Date).ToString('s'); errors = @() }
    if ($Mode -in '', 'cpu') {
      try { $o.cpu = ConvertFrom-CpuLines @(& (Join-Path $PSScriptRoot 'cpu-tune.ps1')); if (-not $o.cpu.Count) { throw 'no control came back' } }
      catch { $o.errors += "cpu: $($_.Exception.Message)" }
    }
    if ($Mode -in '', 'gpu') {
      try {
        $o.gpu = ConvertFrom-GpuLines (@(& (Join-Path $PSScriptRoot 'radeon-read.ps1')) + @(& (Join-Path $PSScriptRoot 'radeon-features.ps1')))
        if (-not $o.gpu.settings.Count) { throw 'no setting came back' }
      } catch { $o.errors += "gpu: $($_.Exception.Message)" }
    }
    if ($Mode -eq '') {
      $auto = Get-AutoProcess
      $o.fan = if ($auto) { 'auto' } else { Get-LastMode }
      $sf = Join-Path $env:ProgramData 'SkYn3tLab\om3n-command-startup.txt'
      $o.startup = [ordered]@{ on = [bool](Get-ScheduledTask -TaskName 'SkYn3tLab-om3n-command-startup' -ErrorAction SilentlyContinue)
        lines = @(if (Test-Path $sf) { Get-Content $sf | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' } | ForEach-Object { "$_" } }) }
      $hf = Join-Path $stateDir 'om3n-command-held.txt'
      $rf = Join-Path $stateDir 'om3n-command-lastreset.txt'
      $wd = Get-ChildItem (Join-Path $(if ($ResetReports) { $ResetReports } else { Join-Path $env:SystemRoot 'LiveKernelReports\WATCHDOG' }) '*.dmp') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
      if ($wd) {
        $reset = $wd.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'); $o.reset = $reset
        $seen = if (Test-Path $rf) { "$(Get-Content $rf -TotalCount 1)".Trim() } else { $null }
        if ($null -eq $seen -or $reset -gt $seen) {
          $gv = @($o.startup.lines | Where-Object { $_ -match '^\s*gpu\b.*-Setting\s+OD_VOLTAGE\b' })
          if ($Simulate) { $o.resetWould = [ordered]@{ reset = $reset; seen = $seen; hold = @(if ($null -ne $seen) { $gv }) } }
          else {
            if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir | Out-Null }
            Set-Content $rf $reset
            if ($null -ne $seen -and $gv) {
              $old = @(if (Test-Path $hf) { Get-Content $hf | ForEach-Object { "$_" } })
              Set-Content $hf (@($(if ($old) { $old[0] } else { "graphics driver reset $reset" })) + @($old | Select-Object -Skip 1) + @($gv | Where-Object { $_ -notin $old }))
            }
          }
        }
      }
      $o.held = if (Test-Path $hf) { $h = @(Get-Content $hf | ForEach-Object { "$_" }); [ordered]@{ crash = $h[0]; lines = @($h | Select-Object -Skip 1) } } else { $null }
    }
    $o | ConvertTo-Json -Depth 6 -Compress
  }
  'gpu' {
    $reader = Join-Path $PSScriptRoot 'radeon-read.ps1'
    if (-not (Test-Path $reader)) { throw "radeon-read.ps1 must sit beside om3n-command.ps1 ($reader not found)" }
    $features = Join-Path $PSScriptRoot 'radeon-features.ps1'
    $adlx = Join-Path $PSScriptRoot 'radeon-adlx.ps1'
    if ($Setting -in 'enhancedsync', 'vsync', 'aamode', 'aalevel', 'aamethod', 'maa', 'af', 'aflevel', 'tessmode', 'tesslevel') {
      if (-not (Test-Path $adlx)) { throw "radeon-adlx.ps1 must sit beside om3n-command.ps1 ($adlx not found)" }
      if ($Value -eq '') { & $adlx -Setting $Setting } else { & $adlx -Setting $Setting -Value ([int]$Value) -Simulate:$Simulate }
      break
    }
    if ($Setting -eq 'shadercache') {
      if (-not (Test-Path $adlx)) { throw "radeon-adlx.ps1 must sit beside om3n-command.ps1 ($adlx not found)" }
      if (-not $Reset -and -not $Simulate) { throw 'the shader cache can only be reset: add -Reset (or -Simulate to check that it is supported)' }
      & $adlx -ResetShaderCache -Simulate:$Simulate
      break
    }
    if ($Feature -in 'rsr', 'afmf') {
      if (-not (Test-Path $adlx)) { throw "radeon-adlx.ps1 must sit beside om3n-command.ps1 ($adlx not found)" }
      & $adlx -Feature $Feature -Enable $Enable -Simulate:$Simulate
      break
    }
    if ($Feature) {
      if (-not (Test-Path $features)) { throw "radeon-features.ps1 must sit beside om3n-command.ps1 ($features not found)" }
      if ($Enable -lt 0) { & $features -Feature $Feature }
      elseif ($Value -ne '') { & $features -Feature $Feature -Enable $Enable -Value ([int]$Value) -Simulate:$Simulate }
      else { & $features -Feature $Feature -Enable $Enable -Simulate:$Simulate }
      break
    }
    if ($FanCurve) {
      $setter = Join-Path $PSScriptRoot 'radeon-set.ps1'
      if (-not (Test-Path $setter)) { throw "radeon-set.ps1 must sit beside om3n-command.ps1 ($setter not found)" }
      & $setter -FanCurve ($FanCurve -join ',') -Simulate:$Simulate; break
    }
    if (-not $Setting) { & $reader; if (Test-Path $features) { '  graphics features:'; & $features | ForEach-Object { "    $_" } }; break }
    $setter = Join-Path $PSScriptRoot 'radeon-set.ps1'
    if (-not (Test-Path $setter)) { throw "radeon-set.ps1 must sit beside om3n-command.ps1 ($setter not found)" }
    if ($Reset) { & $setter -Setting $Setting -Reset -Simulate:$Simulate }
    elseif ($Value -eq '') { throw 'give -Value <number> or -Reset with -Setting' }
    else { & $setter -Setting $Setting -Value ([int]$Value) -Simulate:$Simulate }
  }
  'cpu' {
    if ([bool]$ControlId -ne [bool]$Value) { throw 'to set a control give both -ControlId and -Value; give neither to read' }
    $tool = Join-Path $PSScriptRoot 'cpu-tune.ps1'
    if (-not (Test-Path $tool)) { throw "$tool must sit beside om3n-command.ps1" }
    if (-not $ControlId) { & $tool; break }
    $out = & $tool -ControlId $ControlId -Value $Value
    $out
    if ($ControlId -ne 0x11B -and ($out -match 'CHANGED 0x0000011B active 0->1')) {
      '--- restoring Vmax Stress (0x11B) to 0, which the service changed on its own'
      & $tool -ControlId 0x11B -Value 0 | Where-Object { $_ -match 'ApplyChanges|CHANGED|controls changed|FAILED|ABORT' }
    }
  }
  'status' {
    $c = (Get-Counter '\Thermal Zone Information(*)\Temperature', '\Processor Information(_Total)\% Processor Utility', '\Processor Information(_Total)\% Processor Performance', '\GPU Engine(*engtype_3D)\Utilization Percentage').CounterSamples
    foreach ($z in ($c | Where-Object { $_.Path -like '*thermal zone*' })) { '{0,-22} {1} C' -f $z.InstanceName, [int]($z.CookedValue - 273) }
    Get-PhysicalDisk | ForEach-Object { $r = $_ | Get-StorageReliabilityCounter; if ($r.Temperature) { '{0,-22} {1} C' -f $_.FriendlyName, $r.Temperature } }
    'cpu load               {0:N0} %   performance {1:N0} %' -f ($c | Where-Object { $_.Path -like '*processor utility' }).CookedValue, ($c | Where-Object { $_.Path -like '*processor performance' }).CookedValue
    'gpu 3D load            {0:N0} %' -f (($c | Where-Object { $_.Path -like '*gpu engine*' }) | Measure-Object CookedValue -Sum).Sum
    $auto = Get-AutoProcess
    "fan mode (last set here) $(Get-LastMode)"
    "fan selection          $(if ($auto) { "automatic by CPU temperature (process $($auto.ProcessId))" } else { "$(Get-LastMode) (fixed)" })"
  }
  'light' {
    $zones = @{ Logo = 0; InternalBar = 1; FrontFan = 2; CpuFan = 3 }
    if ($Mode -ne 'Ram' -and -not $zones.ContainsKey($Mode)) { throw 'say which zone: Logo, InternalBar, FrontFan, CpuFan or Ram' }
    $themeColours = @{ unicorn = '236,110,173;207,78,214;111,72,170'; arcane = '15,211,250;191,15,250'; valorant = '36,189,255;255,255,255'
      omen = '11,1,255;11,242,252;243,10,213;158,3,255'; hyperx = '199,0,0;255,0,0;153,0,0;214,0,0' }
    if ($themeColours.ContainsKey($Theme)) {
      if ($Mode -eq 'Ram' -or $Effect -in 'static', 'off', 'vitals', 'audio') { throw "theme $Theme is a colour list for an animated effect on a case zone" }
      $Colors = $themeColours[$Theme]; $Theme = 'custom'
    }
    $list = @()
    if ($Colors) {
      if ($Mode -eq 'Ram' -or $Effect -in 'static', 'off', 'vitals', 'audio') { throw '-Colors is for an animated effect on a case zone' }
      foreach ($t in ($Colors -split ';')) {
        $p = @($t -split ',' | ForEach-Object { [int]$_.Trim() })
        if ($p.Count -ne 3 -or ($p | Where-Object { $_ -lt 0 -or $_ -gt 255 })) { throw "-Colors: '$t' is not red,green,blue with each 0-255" }
        $list += , $p
      }
    }
    $needColour = $Effect -notin 'off', 'vitals' -and $Theme -eq 'custom' -and -not ($Mode -eq 'Ram' -and $Effect -eq 'cycle') -and -not $Colors
    if ($needColour -and ($Red -lt 0 -or $Green -lt 0 -or $Blue -lt 0)) { throw 'give the colour as three numbers 0-255: red green blue (or -Colors, -Theme galaxy|volcano|jungle|ocean, or -Effect off)' }
    if ($needColour) { $list = @(, @($Red, $Green, $Blue)) }
    if ($Effect -in 'vitals', 'audio' -and $Mode -eq 'Ram') { throw 'vitals and audio are case-zone effects' }
    if ($Effect -eq 'static' -and $Theme -ne 'custom') { throw 'a static colour has no theme; give red green blue' }
    if ($Mode -eq 'Ram') {
      if ($Effect -eq 'spiral') { throw 'the RAM has no spiral effect: static, off, breathing, cycle, blinking or wave' }
      if ($Theme -ne 'custom' -and $Effect -ne 'wave') { throw 'on the RAM a theme only exists for wave (any theme name gives the rainbow wave); give red green blue' }
      $b = $Brightness; $k = @{ slow = 0; medium = 1; fast = 2 }[$Speed]
      function Split16([int]$v) { ($v -shr 8), ($v -band 0xFF) }
      $colour = @(0xEC, $Red), @(0xED, $Green), @(0xEE, $Blue)
      $body = @(switch ($Effect) {
        'static' { @(0xE4, 9), @(0xDD, 100), @(0xDD, $b); $colour }
        'off' { , @(0xE2, 1) }
        'cycle' { $h, $l = Split16 (1312, 857, 437)[$k]; @(0xE3, 4), @(0xD3, $h), @(0xD4, $l), @(0xD5, $h), @(0xD6, $l), @(0xDD, $b) }
        'breathing' { $h, $l = Split16 (6516, 4344, 2172)[$k]; $h2, $l2 = Split16 (450, 300, 150)[$k]
          @(0xE4, 3), @(0xD7, $h), @(0xD8, $l), @(0xD9, $h), @(0xDA, $l), @(0xDB, $h2), @(0xDC, $l2), @(0xDE, $b), @(0xDF, 0); $colour }
        'blinking' { $h, $l = Split16 (750, 500, 250)[$k]; @(0xE4, 6), @(0xDB, $h), @(0xDC, $l), @(0xD3, $h), @(0xD4, $l), @(0xDD, $b); $colour }
        'wave' {
          if ($Theme -ne 'custom') { $h, $l = Split16 (76, 51, 25)[$k]; @(0xE3, 5), @(0xD1, $h), @(0xD2, $l), @(0xDD, $b) }   # rainbow wave
          else {
            $h, $l = Split16 (315, 212, 107)[$k]
            if ($Direction -eq 0) { @(0xE4, 2), @(0xD1, $h), @(0xD2, $l), @(0xDD, $b) } else { @(0xE4, 8), @(0xD1, $h), @(0xD2, $l), @(0xDD, $b), @(0xDE, $b), @(0xDF, $b) }
            $colour
          }
        }
      })
      $seq = @(, @(0xE1, 1)) + @($body) + @(, @(0xE1, 2)) + @(, @(0xE1, 3))
      $what = if ($Effect -eq 'off') { 'off' } elseif ($Effect -eq 'cycle' -or ($Effect -eq 'wave' -and $Theme -ne 'custom')) { "$Effect (built-in colours), speed $Speed" } elseif ($Effect -eq 'static') { "static colour $Red, $Green, $Blue" } else { "$Effect, colour $Red, $Green, $Blue, speed $Speed" }
      "light: RAM, $what, brightness $b$(if ($Simulate) { ' -- SIMULATE, nothing is sent' })"
      foreach ($s in $seq) {
        if ($Simulate) { '  would write register {0:X2} = {1}' -f $s[0], $s[1]; continue }
        Start-Sleep -Milliseconds 50
        $rc = Invoke-Bios 0x20009 0x0A ([byte[]]($s[0], $s[1], 0, 0))
        if ($rc -ne 0) { throw ('the BIOS returned code {0} for RAM lighting register {1:X2}; stopped there' -f $rc, $s[0]) }
      }
      if (-not $Simulate) { "light: RAM, $($seq.Count) register writes accepted (BIOS return code 0 each)" }
      break
    }
    $zi = $zones[$Mode] + 1
    $what = switch ($Effect) {
      'off' { 'off' }
      'vitals' { "system vitals from $Source, gradient $Preset, for $Seconds s" }
      'audio' { "audio pulse ($Band), colour $Red, $Green, $Blue, for $Seconds s" }
      default { if ($Theme -ne 'custom') { "$Effect, theme $Theme" } elseif ($list.Count -gt 1) { "$Effect, $($list.Count) colours" } else { "$Effect, colour $($list[0] -join ', ')" } }
    }
    "light: zone $Mode (command zone $zi), $what$(if ($Effect -in 'breathing', 'cycle', 'blinking', 'wave', 'spiral') { ", speed $Speed" })$(if ($Effect -in 'wave', 'spiral') { ", direction $Direction" }), brightness $Brightness, state $State$(if ($Simulate) { ' -- SIMULATE, nothing is sent' })"
    if ($Simulate) { break }
    $sender = Join-Path $PSScriptRoot 'om3n-command-hid.ps1'
    if (-not (Test-Path $sender)) { throw "om3n-command-hid.ps1 must sit beside om3n-command.ps1 ($sender not found)" }
    . $sender
    $common = @{ Zone = $Mode; Brightness = $Brightness; State = $State }
    if ($Effect -in 'vitals', 'audio') {
      $live = Join-Path $PSScriptRoot 'om3n-command-live.ps1'
      if (-not (Test-Path $live)) { throw "om3n-command-live.ps1 must sit beside om3n-command.ps1 ($live not found)" }
      . $live
      $h = Open-LightController
      try {
        $end = (Get-Date).AddSeconds($Seconds); $n = 0; $last = -1
        while ((Get-Date) -lt $end) {
          if ($Effect -eq 'vitals') {
            $v = [Math]::Max(0, [Math]::Min(100, (Get-LiveValue $Source)))
            $null = Send-LightPackets $h (Get-LightPackets @common -Effect vitals -Value $v -Preset $Preset)
            Start-Sleep -Milliseconds 1000
          } else {
            $v = [Math]::Max(0, [Math]::Min(100, (Get-LiveValue $(if ($Band -eq 'level') { 'audio' } else { $Band }))))
            $null = Send-LightPackets $h (Get-LightPackets @common -Effect audio -Value $v -Colors $list)
            Start-Sleep -Milliseconds 100
          }
          $n++
          if ($v -ne $last -and ($n -le 3 -or $n % 10 -eq 0)) { "  frame $n value $v" }; $last = $v
        }
        "light: $n frames written to the controller"
      } finally { Close-LightController $h }
    }
    else { Send-LightZone @common -Effect $Effect -Colors $list -Theme $Theme -Speed $Speed -Direction $Direction }
  }
  'sensors' {
    $c = (Get-Counter @('\Thermal Zone Information(*)\Temperature', '\Processor Information(*)\% Processor Utility', '\Processor Information(*)\Actual Frequency',
        '\Energy Meter(*)\Power', '\Memory\Available Bytes', '\Memory\Committed Bytes', '\GPU Engine(*engtype_3D)\Utilization Percentage',
        '\GPU Adapter Memory(*)\Dedicated Usage', '\Network Interface(*)\Bytes Received/sec', '\Network Interface(*)\Bytes Sent/sec',
        '\PhysicalDisk(*)\Disk Read Bytes/sec', '\PhysicalDisk(*)\Disk Write Bytes/sec') -ErrorAction SilentlyContinue).CounterSamples
    function Pick([string]$like) { $c | Where-Object { $_.Path -like $like } }
    'CPU'
    foreach ($z in (Pick '*thermal zone information*')) { '  {0,-26} {1} C' -f $(if ($z.InstanceName -match 'hptz') { 'temperature (CPU zone)' } else { 'temperature (board zone)' }), [int]($z.CookedValue - 273) }
    foreach ($e in (Pick '*energy meter*' | Where-Object { $_.InstanceName -ne '_total' })) {
      $name = @{ rapl_package0_pkg = 'power, whole package'; rapl_package0_pp0 = 'power, cores'; rapl_package0_pp1 = 'power, integrated graphics'; rapl_package0_dram = 'power, memory' }[$e.InstanceName]
      '  {0,-26} {1:N1} W' -f $(if ($name) { $name } else { $e.InstanceName }), ($e.CookedValue / 1000)
    }
    $util = Pick '*% processor utility'; $freq = Pick '*actual frequency'
    '  {0,-26} {1:N0} %' -f 'load, all cores', ($util | Where-Object { $_.InstanceName -eq '_total' }).CookedValue
    foreach ($u in ($util | Where-Object { $_.InstanceName -match '^\d+,\d+$' } | Sort-Object { [int]($_.InstanceName -split ',')[1] })) {
      $f = ($freq | Where-Object { $_.InstanceName -eq $u.InstanceName }).CookedValue
      '  thread {0,-19} {1,3:N0} %  {2,5:N0} MHz' -f ($u.InstanceName -split ',')[1], $u.CookedValue, $f
    }
    'MEMORY'
    $total = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory; $avail = (Pick '*available bytes').CookedValue
    '  {0,-26} {1:N1} of {2:N1} GB' -f 'in use', (($total - $avail) / 1GB), ($total / 1GB)
    '  {0,-26} {1:N1} GB' -f 'committed', ((Pick '*committed bytes').CookedValue / 1GB)
    'GPU'
    '  {0,-26} {1:N0} %' -f '3D load', ((Pick '*gpu engine*') | Measure-Object CookedValue -Sum).Sum
    '  {0,-26} {1:N1} GB' -f 'video memory in use', (((Pick '*gpu adapter memory*') | Measure-Object CookedValue -Maximum).Maximum / 1GB)
    $reader = Join-Path $PSScriptRoot 'radeon-read.ps1'
    $gs = if (Test-Path $reader) { try { & $reader 2>$null | Where-Object { $_ -match '^\s+sensor' } } catch { } }
    if ($gs) { $gs | ForEach-Object { if ($_ -match 'sensor\s+\d+\s+(\S+)\s+=\s+(-?\d+)') { '  {0,-26} {1}' -f $Matches[1].ToLower(), $Matches[2] } } }
    else { '  (the Radeon''s own sensors need the desktop session)' }
    'DRIVES'
    foreach ($d in Get-PhysicalDisk) {
      $r = $d | Get-StorageReliabilityCounter
      '  {0,-26} {1}  hottest {2}  power-on hours {3}  wear {4} %' -f $d.FriendlyName, $(if ($r.Temperature) { "$($r.Temperature) C" } else { 'no temperature' }), $(if ($r.TemperatureMax) { "$($r.TemperatureMax) C" } else { '-' }), $(if ($r.PowerOnHours) { $r.PowerOnHours } else { '-' }), $r.Wear
    }
    foreach ($d in (Pick '*disk read bytes*' | Where-Object { $_.InstanceName -ne '_total' })) {
      $w = (Pick '*disk write bytes*' | Where-Object { $_.InstanceName -eq $d.InstanceName }).CookedValue
      '  disk {0,-21} read {1:N1} MB/s  write {2:N1} MB/s' -f $d.InstanceName, ($d.CookedValue / 1MB), ($w / 1MB)
    }
    'NETWORK'
    foreach ($n in (Pick '*bytes received/sec')) {
      $s = (Pick '*bytes sent/sec' | Where-Object { $_.InstanceName -eq $n.InstanceName }).CookedValue
      '  {0,-40} down {1:N2} Mbit/s  up {2:N2} Mbit/s' -f $n.InstanceName, ($n.CookedValue * 8 / 1e6), ($s * 8 / 1e6)
    }
    "FAN MODE (last set here)     $(Get-LastMode)"
  }
  'display' {
    $tool = Join-Path $PSScriptRoot 'radeon-display.ps1'
    if (-not (Test-Path $tool)) { throw "radeon-display.ps1 must sit beside om3n-command.ps1 ($tool not found)" }
    $adlx = Join-Path $PSScriptRoot 'radeon-adlx.ps1'
    if (-not $Set) { & $tool; if (Test-Path $adlx) { '  through the newer interface:'; & $adlx | ForEach-Object { "  $_" } } }
    elseif ($Value -eq '') { throw 'give -Value with -Set' }
    elseif ($Set -in 'freesync', 'vsr', 'integerscaling') {
      if (-not (Test-Path $adlx)) { throw "radeon-adlx.ps1 must sit beside om3n-command.ps1 ($adlx not found)" }
      & $adlx -Feature $Set -Display $Display -Enable ([int]$Value) -Simulate:$Simulate
    }
    else { & $tool -Display $Display -Set $Set -Value ([int]$Value) -Simulate:$Simulate }
  }
  'memory' {
    $inst = Get-CimInstance -Namespace root\wmi -ClassName hpqBIntM
    $in = New-CimInstance -Namespace root\wmi -ClassName hpqBDataIn -ClientOnly -Property @{ Sign = [byte[]](0x53, 0x45, 0x43, 0x55); Command = [uint32]0x20008; CommandType = [uint32]0x18; Size = [uint32]4; hpqBData = [byte[]](0, 0, 0, 0) }
    $o = (Invoke-CimMethod -InputObject $inst -MethodName hpqBIOSInt128 -Arguments @{ InData = $in }).OutData
    if ($o.rwReturnCode -ne 0) { throw "the BIOS returned code $($o.rwReturnCode) for the memory status" }
    $d = $o.Data; $base = $d[3] * 256 + $d[4]; $fast = $d[5] * 256 + $d[6]
    "memory: in use $(if ($d[0]) { $fast } else { $base }) MHz; profiles on offer $base and $fast MHz; switching supported = $([bool]$d[1]); modules HP-certified = $([bool]$d[2])"
    if (-not $Mode) { break }
    if ($Mode -notin "$base", "$fast") { throw "say which profile for the next boot: $base or $fast" }
    if (-not $d[1]) { throw 'the BIOS reports that switching the memory profile is not supported' }
    $pick = [byte][int]($Mode -eq "$fast")
    "memory: profile for the NEXT boot = $Mode MHz (BIOS command 0x20008 / 0x19, input $pick)$(if ($Simulate) { ' -- SIMULATE, nothing is sent' })"
    if ($Simulate) { break }
    $rc = Invoke-Bios 0x20008 0x19 ([byte[]]($pick, 0, 0, 0))
    if ($rc -ne 0) { throw "the BIOS returned code $rc" }
    'memory: accepted (BIOS return code 0). It takes effect after a restart; the BIOS retrains the memory then.'
  }
  'fan' {
    if ($Mode -notin 'quiet', 'normal', 'turbo', 'auto') { throw 'say which: quiet, normal, turbo or auto' }
    if ($TurboAbove - $Hysteresis -le $QuietBelow) { throw '-TurboAbove minus -Hysteresis must be above -QuietBelow' }
    if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir | Out-Null }
    $was = Stop-Auto
    $sf = Join-Path $env:ProgramData 'SkYn3tLab\om3n-command-startup.txt'
    $keep = @(if (Test-Path $sf) { Get-Content $sf | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*fan\s' } })
    $autoLine = @(if ($Mode -eq 'auto') { "fan auto -QuietBelow $QuietBelow -TurboAbove $TurboAbove -Hysteresis $Hysteresis" })
    if ($autoLine -or (Test-Path $sf)) { Set-Content $sf (@('# om3n-command commands to run at every sign-in, one per line (see "om3n-command.ps1 startup"). Written by the app.') + $keep + $autoLine) }
    if ($Mode -ne 'auto') {
      Set-FanMode $Mode
      "fan selection: $Mode (BIOS return code 0)$(if ($was) { '; the automatic selection was stopped' })"
      break
    }
    $a = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" profile -Seconds 0 -Background -QuietBelow $QuietBelow -TurboAbove $TurboAbove -Hysteresis $Hysteresis -Interval $Interval -DownAfter $DownAfter"
    $p = Start-Process powershell.exe -ArgumentList $a -WindowStyle Hidden -PassThru
    Set-Content -Path $autoFile -Value $p.Id
    Start-Sleep -Seconds 2
    if (-not (Get-AutoProcess)) { Remove-Item $autoFile -ErrorAction SilentlyContinue; throw "the automatic selection did not stay running; see $autoLog" }
    "fan selection: automatic (quiet below $QuietBelow C, turbo from $TurboAbove C, back down $Hysteresis C below each, after $DownAfter s there; process $($p.Id))"
    'It runs until you choose quiet, normal or turbo, and is started again at every sign-in. Its mode changes are logged to ' + $autoLog
  }
  'lights' {
    $file = Join-Path $env:ProgramData 'SkYn3tLab\om3n-command-lights.json'
    if (-not (Test-Path $file)) { throw "the saved looks are missing ($file not found): repair.ps1 puts the default look back" }
    $profiles = Get-Content $file -Raw | ConvertFrom-Json
    $names = @($profiles.PSObject.Properties.Name)
    if (-not $Mode) { foreach ($n in $names) { "$n"; $profiles.$n | ForEach-Object { "    light $_" } }; break }
    $name = $names | Where-Object { $_ -eq $Mode } | Select-Object -First 1
    if (-not $name) { throw "no lighting profile named '$Mode'; there is: $($names -join ', ')" }
    "lights: profile $name$(if ($Simulate) { ' -- SIMULATE, nothing is sent' })"
    foreach ($line in $profiles.$name) {
      $words = @($line -split ' ' | Where-Object { $_ }); if ($Simulate) { $words += '-Simulate' }
      $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath light @words 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^light:' }
      $out | ForEach-Object { "  $_" }
      if (-not $Simulate -and $LASTEXITCODE -ne 0) { throw "the profile stopped at '$line': the zone was not accepted" }
    }
  }
  'startup' {
    $file = Join-Path $env:ProgramData 'SkYn3tLab\om3n-command-startup.txt'; $task = 'SkYn3tLab-om3n-command-startup'
    $log = Join-Path $stateDir 'om3n-command-startup.log'
    $marker = Join-Path $stateDir 'om3n-command-lastcrash.txt'; $heldFile = Join-Path $stateDir 'om3n-command-held.txt'
    function Get-LastCrash {
      $ev = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41 } -MaxEvents 1 -ErrorAction SilentlyContinue
      if ($ev) { $ev.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
    }
    function Test-Undervolt([string]$line) { $line -match '^\s*cpu\b.*-ControlId\s+(0x22|34|0x4F|79)\b.*-Value\s+-\d' -or $line -match '^\s*gpu\b.*-Setting\s+OD_VOLTAGE\b' }
    function Invoke-StartupLine([string]$line) {
      $words = @($line -split ' ' | Where-Object { $_ })
      foreach ($try in 1..3) {
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @words 2>&1 | ForEach-Object { "$_" }
        $own = @(foreach ($l in $out) { if ($l -match '^--- lines the service logged') { break }; $l })
        $bad = $own | Where-Object { $_ -match 'FAILED|ABORT|REFUSED|Exception|must sit beside' } | Select-Object -First 1
        if (-not $bad) { break }
        Add-Content $log ('{0:HH:mm:ss} try {1} of "{2}" failed: {3}' -f (Get-Date), $try, $line, "$bad".Trim()); Start-Sleep -Seconds 20
      }
      $keep = $out | Where-Object { $_ -match 'ApplyChanges|CHANGED|controls changed|fan selection|written to the controller|accepted|rc=' } | Select-Object -First 6
      Add-Content $log ('{0:HH:mm:ss} om3n-command {1}  ->  {2}' -f (Get-Date), $line, $(if ($bad) { "FAILED: $("$bad".Trim())" } else { ($keep -join ' | ') }))
      $bad
    }
    $lines = @(if (Test-Path $file) { Get-Content $file | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' } })
    switch ($Mode) {
      '' {
        $t = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
        "startup: $(if ($t) { "on (task $task, $($t.State))" } else { 'off' })"
        if ($lines) { $lines | ForEach-Object { "    om3n-command $_" } } else { "    (nothing listed in $file)" }
        if (Test-Path $log) { '  last run:'; Get-Content $log -Tail 6 | ForEach-Object { "    $_" } }
      }
      'on' {
        if (-not $lines) { throw "there is nothing to run: put om3n-command commands, one per line, in $file" }
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" startup run"
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $me; $trigger.Delay = 'PT1M'
        $principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
        "startup: on. At every sign-in of $me, one minute in, this runs:"; $lines | ForEach-Object { "    om3n-command $_" }
      }
      'off' {
        Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
        "startup: off (task present = $([bool](Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue)))"
      }
      'run' {
        if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir | Out-Null }
        $crash = Get-LastCrash
        $known = if (Test-Path $marker) { "$(Get-Content $marker -TotalCount 1)".Trim() } else { $null }
        $isNew = if ($Simulate -and $PretendCrash) { $true } else { $null -ne $known -and $crash -and $crash -gt $known }
        $hold = @(if ($isNew) { $lines | Where-Object { Test-Undervolt $_ } })
        if ($Simulate) {
          'startup run, SIMULATE (nothing is sent, no file is written)'
          "  newest unclean shutdown in the Windows log: $(if ($crash) { $crash } else { 'none' })$(if ($PretendCrash) { '   (pretending it is new)' })"
          "  the one already dealt with: $(if ($null -eq $known) { 'no record yet; a real run would only record the newest one and hold nothing' } else { $known })"
          foreach ($line in $lines) { "  $(if ($line -in $hold) { 'HOLD' } else { 'RUN ' })  om3n-command $line$(if ($line -in $hold) { '   (an undervolt, and the PC went down uncleanly since the last sign-in)' })" }
        }
        else {
          if ($null -eq $known -or $isNew) { Set-Content $marker $crash }
          if ($hold) { Set-Content $heldFile (@($crash) + $hold) } elseif (Test-Path $heldFile) { Remove-Item $heldFile }
          Set-Content $log ('{0:yyyy-MM-dd HH:mm:ss} startup run, {1} command(s)' -f (Get-Date), ($lines.Count - $hold.Count))
          if ($hold) { Add-Content $log ('{0:HH:mm:ss} the PC stopped without a clean shutdown at {1}: {2} undervolt line(s) held back this time: {3}' -f (Get-Date), $crash, $hold.Count, ($hold -join ' | ')) }
          foreach ($line in $lines) { if ($line -notin $hold) { [void](Invoke-StartupLine $line) } }
          Get-Content $log
        }
      }
      'restore' {
        if (-not (Test-Path $heldFile)) { 'startup: nothing is being held back' }
        else {
          $h = @(Get-Content $heldFile | Select-Object -Skip 1 | Where-Object { $_.Trim() })
          $failed = @(foreach ($line in $h) { $bad = Invoke-StartupLine $line; if ($bad) { "FAILED  om3n-command ${line}: $("$bad".Trim())" } })
          if ($failed) { $failed } else { Remove-Item $heldFile; "startup: put back now: $($h -join ' | ')" }
        }
      }
      'drop' {
        if (-not (Test-Path $heldFile)) { 'startup: nothing is being held back' }
        else {
          $h = @(Get-Content $heldFile | Select-Object -Skip 1 | Where-Object { $_.Trim() })
          Set-Content $file @(Get-Content $file | Where-Object { $_ -notin $h })
          Remove-Item $heldFile
          "startup: taken off the sign-in list: $($h -join ' | ')"
        }
      }
      default { throw 'startup takes: nothing (show), on, off, run, restore or drop' }
    }
  }
  'profile' {
    $current = Get-LastMode
    $end = (Get-Date).AddSeconds($Seconds)
    $start = "profile: quiet below $QuietBelow C, turbo from $TurboAbove C, hysteresis $Hysteresis C, down after $DownAfter s, start mode '$current'$(if ($Simulate) { ', SIMULATE (nothing is sent)' })"
    if ($Background) { Set-Content -Path $autoLog -Value ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $start) } else { $start }
    $rank = @{ quiet = 0; normal = 1; turbo = 2 }; $lowSince = $null
    do {
      $t = Get-CpuTemp
      $want = Select-Mode $t $current
      if (-not $Once -and $want -ne $current -and $rank[$want] -lt $rank[$current]) {
        if (-not $lowSince) { $lowSince = Get-Date }
        if (((Get-Date) - $lowSince).TotalSeconds -lt $DownAfter) { $want = $current }
      } else { $lowSince = $null }
      $line = $null
      if ($want -ne $current) {
        if ($Simulate) { $line = '{0:HH:mm:ss} cpu {1} C: would change {2} -> {3}' -f (Get-Date), $t, $current, $want }
        else { Set-FanMode $want; $line = '{0:HH:mm:ss} cpu {1} C: changed {2} -> {3}' -f (Get-Date), $t, $current, $want }
        $current = $want
      } elseif (-not $Background) { $line = '{0:HH:mm:ss} cpu {1} C: stay {2}' -f (Get-Date), $t, $current }
      if ($line) { if ($Background) { Add-Content -Path $autoLog -Value $line } else { $line } }
      if ($Once) { break }
      Start-Sleep -Seconds $Interval
    } while ($Seconds -eq 0 -or (Get-Date) -lt $end)
  }
}
} | ForEach-Object { if ("$_" -cmatch '^\s*(ABORT|FAILED)\b|\(REFUSED\)|^ApplyChanges -> general=(?!Success)') { $soft = $true }; $_ }
$finished = $true
} finally { if ($changes) { Write-Journal "$(if (-not $finished) { 'ERROR' } elseif ($soft) { 'FAIL ' } else { 'END  ' }) om3n-command $what" } }
if ($soft) { exit 2 }
