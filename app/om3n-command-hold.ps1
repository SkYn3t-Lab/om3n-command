if (-not (Get-Command Get-FanSelection -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'om3n-command-lib.ps1') }

$script:holdFile = Join-Path $env:ProgramData 'SkYn3tLab\om3n-command-hold.json'
$script:holdHistory = @{}     # setting -> the times it was put back (the brake's memory; a restart of the app clears it)
$script:holdStopped = @{}     # setting -> the command that was given up on
$script:holdPending = ''      # an unlock or start that arrived while a command of the owner's was running
$script:holdHubTrack = @{}    # which of Gaming Hub's log files has been read, and how far
$script:holdOnUnlock = $null; $script:holdUnlockDue = $null

function Get-HoldSettings {
  $s = [pscustomobject]@{ on = $true; look = '' }
  try {
    if (Test-Path $script:holdFile) {
      $j = Get-Content $script:holdFile -Raw | ConvertFrom-Json
      if ($null -ne $j.on) { $s.on = [bool]$j.on }
      if ($j.look) { $s.look = "$($j.look)" }
    }
  } catch { }   # an unreadable file is the same as none: the defaults
  $s
}
function Set-HoldSettings {
  param([bool]$On, [string]$Look)
  $s = Get-HoldSettings
  if ($PSBoundParameters.ContainsKey('On')) { $s.on = $On }
  if ($PSBoundParameters.ContainsKey('Look')) { $s.look = $Look }
  $dir = Split-Path $script:holdFile
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  $s | ConvertTo-Json | Set-Content $script:holdFile -Encoding UTF8
  $s
}

function Get-HoldWanted([string]$Folder = (Join-Path $env:ProgramData 'SkYn3tLab')) {
  $lines = @(); $look = ''
  try { $f = Join-Path $Folder 'om3n-command-startup.txt'; if (Test-Path $f) { $lines = @(Get-Content $f | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' } | ForEach-Object { "$_".Trim() }) } } catch { }
  try {
    $want = (Get-HoldSettings).look; $lf = Join-Path $Folder 'om3n-command-lights.json'
    if ($want -and (Test-Path $lf)) { $look = @((Get-Content $lf -Raw | ConvertFrom-Json).PSObject.Properties.Name | Where-Object { $_ -eq $want })[0] }
  } catch { }
  [pscustomobject]@{ lines = $lines; fan = "$(Get-FanSelection)"; look = "$look" }
}

function Get-HoldName([string]$kind, [string]$id, $entry) {
  if ($kind -eq 'cpu') {
    switch ($id) {
      '0x00000022' { return 'processor undervolt', ' mV' }
      '0x0000004F' { return 'processor cache undervolt', ' mV' }
      '0x00000030' { return 'processor power limit', ' W' }
    }
    if ("$($entry.name)" -match 'Max Turbo for (\d+) Cores') { return "top speed with $($Matches[1]) busy core(s)", '' }
    return 'processor setting', ''
  }
  switch ($id) {
    'OD_VOLTAGE' { return 'graphics voltage', ' mV' }
    'POWER_PERCENTAGE' { return 'graphics power limit', ' %' }
  }
  return ('graphics ' + $id.ToLower().Replace('_', ' ')), ''
}
function Get-HoldPlan {
  param($Wanted, $State, [ValidateSet('poll', 'unlock', 'start')][string]$When = 'poll', $Hub, [switch]$Explain, [switch]$ResetNew, [switch]$AppStart)
  $rows = New-Object Collections.ArrayList
  function Row($key, $action, $command, $reason) { [void]$rows.Add([pscustomobject]@{ key = $key; action = $action; command = $command; reason = $reason }) }
  function Prop($o, [string]$n) { if ($null -ne $o -and $o.PSObject.Properties[$n]) { $o.PSObject.Properties[$n].Value } }
  $held = @(if ($State -and $State.held) { $State.held.lines })
  foreach ($line in @($Wanted.lines)) {
    $w = @("$line" -split '\s+' | Where-Object { $_ })
    $arg = @{}; for ($i = 1; $i -lt $w.Count - 1; $i++) { if ($w[$i] -match '^-([A-Za-z]\w*)$') { $arg[$Matches[1]] = $w[$i + 1] } }
    $kind = $w[0]; $key = $null; $have = $null; $want = $null; $name = ''; $unit = ''
    try {
      if ($kind -eq 'cpu' -and $arg.ControlId -and $arg.ContainsKey('Value')) {
        $id = '0x{0:X8}' -f [uint32]$arg.ControlId; $key = "cpu:$id"; $want = [double]$arg.Value
        $c = Prop (Prop $State 'cpu') $id
        if ($null -ne $c) { $have = [double]$c.active }
        $name, $unit = Get-HoldName 'cpu' $id $c
      }
      elseif ($kind -eq 'gpu' -and $arg.Setting -and $arg.ContainsKey('Value')) {
        $key = "gpu:$($arg.Setting)"; $want = [double]$arg.Value
        $c = Prop (Prop (Prop $State 'gpu') 'settings') $arg.Setting
        if ($null -ne $c) { $have = [double]$c.current }
        $name, $unit = Get-HoldName 'gpu' $arg.Setting $c
      }
      elseif ($kind -eq 'gpu' -and $arg.FanCurve) {
        $key = 'gpu:fancurve'; $want = (@($arg.FanCurve -split ',') | ForEach-Object { [int]$_ }) -join ','; $name = 'graphics card fan curve'
        $s = Prop (Prop $State 'gpu') 'settings'
        $now = foreach ($i in 1..5) { (Prop $s "FAN_CURVE_TEMPERATURE_$i").current; (Prop $s "FAN_CURVE_SPEED_$i").current }
        if (@($now | Where-Object { $null -ne $_ }).Count -eq 10) { $have = $now -join ',' }
      }
    } catch { $key = $null }   # a line that does not parse is left alone, like one that cannot be read
    if (-not $key) { Row "line:$line" 'skip' $line 'this line cannot be read back from the PC, so it is left alone'; continue }
    if ($line -in $held) { Row $key 'skip' $line "the $name is held back after a crash until you put it back"; continue }
    if ($null -eq $have) { Row $key 'skip' $line "the $name could not be read just now, so nothing is done"; continue }
    $same = if ($want -is [double]) { [math]::Abs($have - $want) -lt 0.0005 } else { "$have" -eq "$want" }
    if ($same -and $key -eq 'gpu:fancurve' -and $ResetNew) { Row $key 'apply' $line $(if ($AppStart) { 'The app has just started and cannot tell whether the card is still running its fan from your curve (a graphics driver reset hands the fan back to the card), so your fan curve is sent again.' } else { 'The graphics driver was reset, which hands the fan back to the card: your fan curve is sent again.' }) }
    elseif ($same) { Row $key 'ok' $line "the $name is in force ($have$unit)" }
    else { Row $key 'apply' $line "The $name reads $have$unit and yours is $want${unit}: something replaced it." }
  }
  $core = $rows | Where-Object { $_.key -eq 'cpu:0x00000022' -and $_.action -eq 'apply' }
  $ring = $rows | Where-Object { $_.key -eq 'cpu:0x0000004F' -and $_.action -eq 'apply' }
  if ($core -and $ring -and ("$($core.command)" -replace '.*-Value\s+', '') -eq ("$($ring.command)" -replace '.*-Value\s+', '')) {
    $ring.action = 'skip'; $ring.reason = 'the processor cache undervolt follows the processor undervolt, which is being put back'
  }
  $fan = "$($Wanted.fan)"
  if ($fan -in 'quiet', 'normal', 'turbo') {
    $shown = @{ quiet = 'Quiet'; normal = 'Balanced'; turbo = 'Performance' }
    if ($When -ne 'poll') { Row 'fan' 'apply' "fan $fan" "The fan setting cannot be read back, so $($shown[$fan]) is sent again $(if ($When -eq 'unlock') { 'when the PC is unlocked' } else { 'after the app starts' }), in case something changed it." }
    elseif ($Hub -and $Hub.fan -and $Hub.fan -ne $fan) { Row 'fan' 'apply' "fan $fan" "Gaming Hub set the fans to $($shown[$Hub.fan]) and yours is $($shown[$fan])." }
    elseif ($Hub -and $Hub.fan) { Row 'fan' 'ok' "fan $fan" "Gaming Hub sent the fan setting you already have ($($shown[$fan]))" }
  }
  elseif ($fan -eq 'auto' -and ($When -ne 'poll' -or ($Hub -and $Hub.fan))) {
    Row 'fan' 'skip' '' 'the fans are on Om3n, which sets them again at its next change; sending a fixed setting would stop it'
  }
  if ($Wanted.look) {
    $cmd = if ("$($Wanted.look)" -match '\s') { "lights `"$($Wanted.look)`"" } else { "lights $($Wanted.look)" }
    if ($When -ne 'poll') { Row 'lights' 'apply' $cmd "The lights cannot be read back, so the $($Wanted.look) look is sent again $(if ($When -eq 'unlock') { 'when the PC is unlocked' } else { 'after the app starts' }), in case something changed them." }
    elseif ($Hub -and $Hub.lights -gt 0) { Row 'lights' 'apply' $cmd "Gaming Hub put its own lighting back, so the $($Wanted.look) look is sent again." }
  }
  if ($Explain) { $rows } else { $rows | Where-Object { $_.action -eq 'apply' } }
}

function Limit-HoldPlan {
  param($Plan, [datetime]$Now = (Get-Date), [int]$GapSec = 120, [int]$WindowSec = 600, [int]$Max = 3, [switch]$Peek)
  foreach ($r in @($Plan)) {
    if (-not $r) { continue }
    if ($r.action -ne 'apply') { $r; continue }
    $o = [pscustomobject]@{ key = $r.key; action = 'apply'; command = $r.command; reason = $r.reason }
    if ($script:holdStopped[$r.key]) {
      if ($script:holdStopped[$r.key] -eq $r.command) { $o.action = 'stopped'; $o; continue }
      $script:holdStopped.Remove($r.key); $script:holdHistory.Remove($r.key)   # the owner chose another value: start afresh
    }
    $times = @($script:holdHistory[$r.key] | Where-Object { $_ -and ($Now - $_).TotalSeconds -lt $WindowSec })
    if ($times.Count -ge $Max) {
      $o.action = 'stop'; $o.reason = "It was put back $Max times in $([int]($WindowSec / 60)) minutes and replaced again each time, so it is no longer being put back. Choose it again in the app, or restart the app, to resume."
      if (-not $Peek) { $script:holdStopped[$r.key] = $r.command }
    }
    elseif ($times.Count -and ($Now - $times[-1]).TotalSeconds -lt $GapSec) { $o.action = 'wait'; $o.reason = "It was put back $([int]($Now - $times[-1]).TotalSeconds) s ago; the next try is $GapSec s after that." }
    elseif (-not $Peek) { $script:holdHistory[$r.key] = @($times) + $Now }
    $o
  }
}

function Get-HoldHubWrites {
  param([string]$Path = '', [switch]$FromStart, $Track = $script:holdHubTrack)
  $r = [pscustomobject]@{ fan = ''; lights = 0; read = 0; file = '' }
  try {
    if (-not $Path) { $Path = Join-Path $env:LOCALAPPDATA ('Packages\AD2F1837.OMENCommandCenter_v10z8vjag6ke6\LocalCache\Local\HPOMEN\HPOMENBG_{0:yyyyMMdd}.log' -f (Get-Date)) }
    $r.file = $Path
    if (-not (Test-Path $Path)) { return $r }
    $fs = New-Object IO.FileStream $Path, ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]'ReadWrite, Delete')
    try {
      $pos = if ($Track.file -eq $Path) { [long]$Track.pos } elseif ($FromStart -or $Track.file) { 0 } else { $fs.Length }
      if ($pos -gt $fs.Length) { $pos = 0 }
      if ($fs.Length - $pos -gt 4MB) { $pos = $fs.Length - 4MB }   # never more than the newest 4 MB in one go
      [void]$fs.Seek($pos, 'Begin'); $buf = New-Object byte[] ($fs.Length - $pos); $n = $fs.Read($buf, 0, $buf.Length)
      $end = if ($n -gt 0) { [Array]::LastIndexOf($buf, [byte]10, $n - 1) } else { -1 }
      $Track.file = $Path; $Track.pos = $pos + $end + 1; $r.read = $end + 1
      if ($end -ge 0) {
        $mode = @{ L0 = 'quiet'; L1 = 'normal'; L2 = 'turbo' }
        foreach ($l in [Text.Encoding]::UTF8.GetString($buf, 0, $end + 1) -split "`n") {
          if ($l -match 'SetFanModeAsync\(\), newMode = (L[012])') { $r.fan = $mode[$Matches[1]] }
          elseif ($l -match 'ResetLighting Success .*Zone: Logo|MemoryLightingBg ResetLighting for UserUnlock Start') { $r.lights++ }
        }
      }
    } finally { $fs.Close() }
  } catch { }   # a log that cannot be read means nothing is known, which is the same as nothing sent
  $r
}

function Invoke-HoldCheck {
  param($State, [ValidateSet('poll', 'unlock', 'start')][string]$When = 'poll', [scriptblock]$Run, [scriptblock]$Log, [switch]$JobsRunning, [switch]$Simulate,
    [string]$Folder = (Join-Path $env:ProgramData 'SkYn3tLab'), $Hub)
  if (-not (Get-HoldSettings).on) { if ($Simulate) { [pscustomobject]@{ key = ''; action = 'off'; command = ''; reason = 'Hold my settings is switched off' } }; return }
  if ($JobsRunning) { if ($When -ne 'poll' -and -not $Simulate) { $script:holdPending = $When }; if ($Simulate) { [pscustomobject]@{ key = ''; action = 'busy'; command = ''; reason = 'a command is running; decided at the next check' } }; return }
  if ($When -eq 'poll' -and $script:holdPending) { $When = $script:holdPending }
  if (-not $Simulate) { $script:holdPending = '' }
  if (-not $PSBoundParameters.ContainsKey('Hub')) { $Hub = if ($Simulate) { $null } else { Get-HoldHubWrites } }
  $reset = "$(if ($State -and $State.PSObject.Properties['reset']) { $State.reset })"
  $resetNew = [bool]$reset -and $reset -ne $script:holdResetDone
  $rows = @(Limit-HoldPlan (Get-HoldPlan -Wanted (Get-HoldWanted $Folder) -State $State -When $When -Hub $Hub -Explain -ResetNew:$resetNew -AppStart:($null -eq $script:holdResetDone)) -Peek:$Simulate)
  if (-not $Simulate -and $reset) { $script:holdResetDone = $reset }
  if ($Simulate) { return $rows }
  foreach ($r in $rows) {
    if ($r.action -eq 'apply') { if ($Log) { & $Log "HOLD put back: $($r.reason)  -> om3n-command $($r.command)" }; if ($Run) { & $Run $r.command $r.reason } }
    elseif ($r.action -eq 'stop') { if ($Log) { & $Log "HOLD stopped for '$($r.command)': $($r.reason)" } }
  }
  $rows | Where-Object { $_.action -in 'apply', 'stop' }
}

function Register-HoldEvents([scriptblock]$onUnlock) {
  if (-not ('HoldEvents' -as [type])) {
    Add-Type @'
using System; using System.Threading; using Microsoft.Win32;
public static class HoldEvents {
  static int unlocked, hooked;
  public static int Count, ThreadId; public static string Last = "";
  static void OnSwitch(object s, SessionSwitchEventArgs e) {
    Last = e.Reason.ToString(); ThreadId = Thread.CurrentThread.ManagedThreadId;
    if (e.Reason == SessionSwitchReason.SessionUnlock) { Count++; Interlocked.Exchange(ref unlocked, 1); }
  }
  public static bool Hooked { get { return hooked == 1; } }
  public static void Hook() { if (Interlocked.Exchange(ref hooked, 1) == 0) SystemEvents.SessionSwitch += OnSwitch; }
  // SystemEvents is static: a handler left attached outlives its owner, so the app takes it off when it closes
  public static void Unhook() { if (Interlocked.Exchange(ref hooked, 0) == 1) SystemEvents.SessionSwitch -= OnSwitch; }
  public static bool Take() { return Interlocked.Exchange(ref unlocked, 0) == 1; }
  // for the self-test: the handler called as Windows would call it, with the given reason (7 lock, 8 unlock)
  public static void Pretend(int reason) { OnSwitch(null, new SessionSwitchEventArgs((SessionSwitchReason)reason)); }
}
'@
  }
  $script:holdOnUnlock = $onUnlock
  [HoldEvents]::Hook()
}
function Unregister-HoldEvents { if ('HoldEvents' -as [type]) { [HoldEvents]::Unhook() }; $script:holdOnUnlock = $null; $script:holdUnlockDue = $null }
function Invoke-HoldEvents([int]$DelaySec = 5) {
  if (-not ('HoldEvents' -as [type])) { return }
  if ([HoldEvents]::Take()) { $script:holdUnlockDue = (Get-Date).AddSeconds($DelaySec) }
  if ($script:holdUnlockDue -and (Get-Date) -ge $script:holdUnlockDue) { $script:holdUnlockDue = $null; if ($script:holdOnUnlock) { & $script:holdOnUnlock } }
}

function Test-HoldPlan {
  $bad = New-Object Collections.ArrayList; $script:holdChecks = 0
  function Check([string]$what, $got, $want) {
    $script:holdChecks++
    if ("$got" -ne "$want") { [void]$bad.Add("${what}: got '$got', expected '$want'"); "  FAIL $what -> '$got' (expected '$want')" } else { "  ok   $what -> '$got'" }
  }
  function Cmds($rows) { (@($rows | Where-Object { $_.action -eq 'apply' } | ForEach-Object { $_.command }) -join ' | ') }
  function State([double]$core, [double]$ring, [int]$volt, [string]$held = 'null') {
    ('{"errors":[],"cpu":{"0x00000022":{"name":"CpuVoltageOffset","active":' + $core + '},"0x0000004F":{"name":"Ring Voltage Offset","active":' + $ring + '},"0x00000061":{"name":"Max Turbo for 8 Cores","active":47}},' +
      '"gpu":{"settings":{"OD_VOLTAGE":{"current":' + $volt + '},"FAN_CURVE_TEMPERATURE_1":{"current":40},"FAN_CURVE_SPEED_1":{"current":20},"FAN_CURVE_TEMPERATURE_2":{"current":55},"FAN_CURVE_SPEED_2":{"current":30},"FAN_CURVE_TEMPERATURE_3":{"current":65},"FAN_CURVE_SPEED_3":{"current":45},"FAN_CURVE_TEMPERATURE_4":{"current":75},"FAN_CURVE_SPEED_4":{"current":60},"FAN_CURVE_TEMPERATURE_5":{"current":85},"FAN_CURVE_SPEED_5":{"current":80}}},' +
      '"fan":"turbo","held":' + $held + '}') | ConvertFrom-Json
  }
  $list = 'cpu -ControlId 0x22 -Value -90', 'cpu -ControlId 0x4F -Value -90', 'gpu -Setting OD_VOLTAGE -Value 1100'
  function Want($lines = $list, $fan = 'turbo', $look = 'Om3n') { [pscustomobject]@{ lines = @($lines); fan = $fan; look = $look } }
  $keep = $script:holdFile, $script:holdHistory, $script:holdStopped, $script:holdPending, $script:holdOnUnlock, $script:holdUnlockDue
  $tmp = Join-Path $env:TEMP "holdtest-$PID"; New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  try {
    'the decision (Get-HoldPlan)'
    Check 'all in force' (Cmds (Get-HoldPlan (Want) (State -90 -90 1100))) ''
    Check 'all in force, rows explained' ((Get-HoldPlan (Want) (State -90 -90 1100) -Explain | ForEach-Object { $_.action }) -join ',') 'ok,ok,ok'
    $p = @(Get-HoldPlan (Want) (State -100 -100 1100))
    Check 'undervolt replaced (both follow one write)' (Cmds $p) 'cpu -ControlId 0x22 -Value -90'
    Check 'undervolt replaced, the reason' $p[0].reason 'The processor undervolt reads -100 mV and yours is -90 mV: something replaced it.'
    Check 'only the cache undervolt replaced' (Cmds (Get-HoldPlan (Want) (State -90 -100 1100))) 'cpu -ControlId 0x4F -Value -90'
    Check 'undervolt gone after a restart (reads 0)' (Cmds (Get-HoldPlan (Want) (State 0 0 1100))) 'cpu -ControlId 0x22 -Value -90'
    $curve = 'gpu -FanCurve 40,20,55,30,65,45,75,60,85,80'
    Check 'fan curve reads as yours, no reset: left alone' (Cmds (Get-HoldPlan (Want @($curve)) (State -90 -90 1100))) ''
    Check 'fan curve reads as yours, after a driver reset: sent again' (Cmds (Get-HoldPlan (Want @($curve)) (State -90 -90 1100) -ResetNew)) $curve
    $p = @(Get-HoldPlan (Want) (State -90 -90 1150))
    Check 'graphics voltage replaced' (Cmds $p) 'gpu -Setting OD_VOLTAGE -Value 1100'
    Check 'graphics voltage replaced, the reason' $p[0].reason 'The graphics voltage reads 1150 mV and yours is 1100 mV: something replaced it.'
    Check 'both replaced' (Cmds (Get-HoldPlan (Want) (State -100 -100 1150))) 'cpu -ControlId 0x22 -Value -90 | gpu -Setting OD_VOLTAGE -Value 1100'
    Check 'nothing wanted' (Cmds (Get-HoldPlan (Want @() '' '') (State -100 -100 1150))) ''
    Check 'nothing wanted, at unlock' (Cmds (Get-HoldPlan (Want @() '' '') (State -100 -100 1150) -When unlock)) ''
    Check 'state unreadable (none)' (Cmds (Get-HoldPlan (Want) $null)) ''
    Check 'state unreadable, rows explained' ((Get-HoldPlan (Want) $null -Explain | ForEach-Object { $_.action }) -join ',') 'skip,skip,skip'
    $noCpu = '{"errors":["cpu: no control came back"],"gpu":{"settings":{"OD_VOLTAGE":{"current":1150}}},"held":null}' | ConvertFrom-Json
    Check 'processor part unreadable, graphics still compared' (Cmds (Get-HoldPlan (Want) $noCpu)) 'gpu -Setting OD_VOLTAGE -Value 1100'
    $heldState = State 0 0 1150 '{"crash":"2026-10-03 01:08:25","lines":["cpu -ControlId 0x22 -Value -90","cpu -ControlId 0x4F -Value -90"]}'
    Check 'undervolts held back after an unclean shutdown stay off; the rest is still put back' (Cmds (Get-HoldPlan (Want) $heldState)) 'gpu -Setting OD_VOLTAGE -Value 1100'
    Check 'control id given as a number' (Cmds (Get-HoldPlan (Want @('cpu -ControlId 34 -Value -90')) (State -100 -100 1100))) 'cpu -ControlId 34 -Value -90'
    Check 'another processor setting replaced' (Get-HoldPlan (Want @('cpu -ControlId 0x61 -Value 51')) (State -90 -90 1100))[0].reason 'The top speed with 8 busy core(s) reads 47 and yours is 51: something replaced it.'
    Check 'a line that cannot be read back' ((Get-HoldPlan (Want @('gpu -Feature antilag -Enable 1', 'fan turbo')) (State -90 -90 1100) -Explain | ForEach-Object { $_.action }) -join ',') 'skip,skip'
    $curve = 'gpu -FanCurve 40,20,55,30,65,45,75,60,85,80'
    Check 'graphics fan curve in force' (Cmds (Get-HoldPlan (Want @($curve)) (State -90 -90 1100))) ''
    Check 'graphics fan curve replaced' (Cmds (Get-HoldPlan (Want @('gpu -FanCurve 40,20,55,30,65,50,75,60,85,80')) (State -90 -90 1100))) 'gpu -FanCurve 40,20,55,30,65,50,75,60,85,80'
    Check 'unlock: fans and lighting sent again' (Cmds (Get-HoldPlan (Want) (State -90 -90 1100) -When unlock)) 'fan turbo | lights Om3n'
    Check 'unlock with the state unreadable' (Cmds (Get-HoldPlan (Want) $null -When unlock)) 'fan turbo | lights Om3n'
    Check 'start: the same as unlock' (Cmds (Get-HoldPlan (Want) (State -90 -90 1100) -When start)) 'fan turbo | lights Om3n'
    Check 'unlock, fans on Om3n, no look remembered' (Cmds (Get-HoldPlan (Want $list 'auto' '') (State -90 -90 1100) -When unlock)) ''
    Check 'unlock, a look with a space in its name' (Cmds (Get-HoldPlan (Want @() '' 'Night Red') $null -When unlock)) 'lights "Night Red"'
    $hub = [pscustomobject]@{ fan = 'normal'; lights = 0 }
    Check 'Gaming Hub set another fan mode' (Cmds (Get-HoldPlan (Want) (State -90 -90 1100) -Hub $hub)) 'fan turbo'
    Check 'Gaming Hub set another fan mode, the reason' (Get-HoldPlan (Want) (State -90 -90 1100) -Hub $hub)[0].reason 'Gaming Hub set the fans to Balanced and yours is Performance.'
    Check 'Gaming Hub sent the same fan mode' (Cmds (Get-HoldPlan (Want) (State -90 -90 1100) -Hub ([pscustomobject]@{ fan = 'turbo'; lights = 0 }))) ''
    Check 'Gaming Hub reset the lighting' (Cmds (Get-HoldPlan (Want) (State -90 -90 1100) -Hub ([pscustomobject]@{ fan = ''; lights = 2 }))) 'lights Om3n'
    Check 'Gaming Hub wrote nothing' (Cmds (Get-HoldPlan (Want) (State -90 -90 1100) -Hub ([pscustomobject]@{ fan = ''; lights = 0 }))) ''

    'the brake (Limit-HoldPlan)'
    $script:holdHistory = @{}; $script:holdStopped = @{}; $t = [datetime]'2026-10-03 12:00:00'
    $plan = { Get-HoldPlan (Want) (State -100 -100 1100) }
    $seq = foreach ($s in 0, 30, 121, 242, 363, 364, 2000) { (Limit-HoldPlan (& $plan) -Now $t.AddSeconds($s))[0].action }
    Check 'replaced again and again: at 0, 30, 121, 242, 363, 364, 2000 s' ($seq -join ',') 'apply,wait,apply,apply,stop,stopped,stopped'
    Check 'after giving up, another value chosen by the owner starts afresh' (Limit-HoldPlan (Get-HoldPlan (Want @('cpu -ControlId 0x22 -Value -80')) (State -100 -100 1100)) -Now $t.AddSeconds(2010))[0].action 'apply'
    $script:holdHistory = @{}; $script:holdStopped = @{}
    $seq = foreach ($s in 0, 700, 1400, 2100) { (Limit-HoldPlan (& $plan) -Now $t.AddSeconds($s))[0].action }
    Check 'replaced now and then (every 700 s) is always put back' ($seq -join ',') 'apply,apply,apply,apply'
    $script:holdHistory = @{}; $script:holdStopped = @{}
    [void](Limit-HoldPlan (& $plan) -Now $t -Peek)
    Check 'a simulation leaves the brake untouched' $script:holdHistory.Count 0
    [void](Limit-HoldPlan (& $plan) -Now $t)
    Check 'one setting braked, another still put back' ((Limit-HoldPlan (Get-HoldPlan (Want) (State -100 -100 1150)) -Now $t.AddSeconds(10) | ForEach-Object { $_.action }) -join ',') 'wait,apply'

    'the switch and the look (Get-HoldSettings / Set-HoldSettings)'
    $script:holdFile = Join-Path $tmp 'hold.json'
    $s = Get-HoldSettings; Check 'no file yet' "$($s.on) '$($s.look)'" "True ''"
    [void](Set-HoldSettings -Look 'Om3n'); $s = Get-HoldSettings; Check 'look remembered, switch untouched' "$($s.on) '$($s.look)'" "True 'Om3n'"
    [void](Set-HoldSettings -On $false); $s = Get-HoldSettings; Check 'switched off, look kept' "$($s.on) '$($s.look)'" "False 'Om3n'"
    Set-Content (Join-Path $tmp 'om3n-command-startup.txt') '# comment', 'cpu -ControlId 0x22 -Value -90', '', 'gpu -Setting OD_VOLTAGE -Value 1100'
    Set-Content (Join-Path $tmp 'om3n-command-lights.json') '{"Om3n":["Logo 113 15 250"]}'
    $w = Get-HoldWanted $tmp; Check 'wanted, from the files' "$($w.lines -join ' | ') / $($w.look)" 'cpu -ControlId 0x22 -Value -90 | gpu -Setting OD_VOLTAGE -Value 1100 / Om3n'
    [void](Set-HoldSettings -Look 'Gone'); Check 'a look that is no longer saved is dropped' "'$((Get-HoldWanted $tmp).look)'" "''"

    'one check, start to finish (Invoke-HoldCheck)'
    $ran = New-Object Collections.ArrayList; $logged = New-Object Collections.ArrayList
    $run = { param($c, $why) [void]$ran.Add($c) }.GetNewClosure(); $log = { param($x) [void]$logged.Add($x) }.GetNewClosure()
    $none = [pscustomobject]@{ fan = ''; lights = 0 }
    [void](Invoke-HoldCheck -State (State -100 -100 1100) -Run $run -Log $log -Folder $tmp -Hub $none); Check 'switched off: nothing runs' $ran.Count 0
    [void](Set-HoldSettings -On $true -Look 'Om3n'); $script:holdHistory = @{}; $script:holdStopped = @{}
    [void](Invoke-HoldCheck -State (State -100 -100 1100) -Run $run -Log $log -Folder $tmp -Hub $none -Simulate); Check 'simulate: nothing runs' $ran.Count 0
    [void](Invoke-HoldCheck -State (State -100 -100 1100) -Run $run -Log $log -Folder $tmp -Hub $none -JobsRunning); Check 'a command is running: nothing runs' $ran.Count 0
    [void](Invoke-HoldCheck -State (State -100 -100 1100) -Run $run -Log $log -Folder $tmp -Hub $none); Check 'replaced: the command is run' ($ran -join ' | ') 'cpu -ControlId 0x22 -Value -90'
    Check 'replaced: it is logged' $logged[0] 'HOLD put back: The processor undervolt reads -100 mV and yours is -90 mV: something replaced it.  -> om3n-command cpu -ControlId 0x22 -Value -90'
    [void](Invoke-HoldCheck -State (State -100 -100 1100) -Run $run -Log $log -Folder $tmp -Hub $none); Check 'replaced again straight away: the brake waits' $ran.Count 1
    $ran.Clear()
    [void](Invoke-HoldCheck -State (State -90 -90 1100) -When unlock -Run $run -Log $log -Folder $tmp -Hub $none -JobsRunning); Check 'unlock while a command runs: nothing yet' $ran.Count 0
    [void](Invoke-HoldCheck -State (State -90 -90 1100) -Run $run -Log $log -Folder $tmp -Hub $none); Check 'the remembered unlock is taken up at the next check' (@($ran | Where-Object { $_ -like 'lights*' }) -join '') 'lights Om3n'
    $ran.Clear(); [void](Invoke-HoldCheck -State (State -90 -90 1100) -Run $run -Log $log -Folder $tmp -Hub $none); Check 'and only once' $ran.Count 0

    "Gaming Hub's log (Get-HoldHubWrites), with real lines from this PC"
    $hl = Join-Path $tmp 'hub.log'; $tr = @{}
    $l1 = '2026-10-01 18:57:01.1000000 -04:00 [INF] [PID: 18256] [TID: 9] SetFanModeAsync(), newMode = L1'
    $l2 = '2026-10-01 18:57:02.1000000 -04:00 [INF] [PID: 18256] [TID: 9] ArticunoLightingControl::ResetLighting - ArticunoLightingControl ResetLighting Success !!!! (Zone: Logo, Mode: Static, Wake/Sleep: Wake)'
    $l3 = '2026-10-01 18:57:02.2000000 -04:00 [INF] [PID: 18256] [TID: 9] ArticunoLightingControl::ResetLighting - ArticunoLightingControl ResetLighting Success !!!! (Zone: CpuFan, Mode: Static, Wake/Sleep: Wake)'
    [IO.File]::WriteAllText($hl, "$l1`r`n$l2`r`n")
    $h = Get-HoldHubWrites -Path $hl -Track $tr; Check 'first look starts at the end' "$($h.fan)/$($h.lights)" '/0'
    [IO.File]::AppendAllText($hl, "$l3`r`n$l2`r`n" + ($l1 -replace 'L1', 'L2') + "`r`n" + $l1.Substring(0, 60))
    $h = Get-HoldHubWrites -Path $hl -Track $tr; Check 'new lines: last fan mode, lighting resets, the half-written line left' "$($h.fan)/$($h.lights)" 'turbo/1'
    [IO.File]::AppendAllText($hl, $l1.Substring(60) + "`r`n")
    $h = Get-HoldHubWrites -Path $hl -Track $tr; Check 'the line once it is whole' "$($h.fan)/$($h.lights)" 'normal/0'
    $h = Get-HoldHubWrites -Path $hl -Track $tr; Check 'nothing new' "$($h.fan)/$($h.lights)" '/0'
    $h = Get-HoldHubWrites -Path (Join-Path $tmp 'none.log') -Track $tr; Check 'no log file' "$($h.fan)/$($h.lights)" '/0'

    'the unlock hook (Register-HoldEvents / Invoke-HoldEvents)'
    $script:holdFired = 0
    Register-HoldEvents { $script:holdFired++ }
    Check 'registered with Windows' ([HoldEvents]::Hooked) 'True'
    [void][HoldEvents]::Take(); Invoke-HoldEvents 0; Check 'no unlock yet' $script:holdFired 0
    [HoldEvents]::Pretend(7); Invoke-HoldEvents 0; Check 'a lock is not an unlock' $script:holdFired 0
    [HoldEvents]::Pretend(8); Invoke-HoldEvents 0; Check 'an unlock calls the script block' $script:holdFired 1
    Invoke-HoldEvents 0; Check 'once per unlock' $script:holdFired 1
    [HoldEvents]::Pretend(8); Invoke-HoldEvents 3600; Check 'not before the delay' $script:holdFired 1
    Unregister-HoldEvents; Check 'taken off again' ([HoldEvents]::Hooked) 'False'
  } finally {
    $script:holdFile, $script:holdHistory, $script:holdStopped, $script:holdPending, $script:holdOnUnlock, $script:holdUnlockDue = $keep
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
  if ($bad.Count) { throw "holdtest FAILED, $($bad.Count) of $($script:holdChecks): $($bad -join '; ')" }
  "holdtest ok: $($script:holdChecks) checks"
}
