param([switch]$NoRestart, [switch]$Repair)
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot.TrimEnd('\')
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Run this in PowerShell as administrator (right-click PowerShell, then Run as administrator).' }
$folders = 'app', 'tools', 'assets', 'defaults', 'docs'
$files = 'README.md', 'LICENSE', 'CHANGELOG.md', 'install.ps1', 'uninstall.ps1', 'repair.ps1'
foreach ($n in $folders + $files) { if (-not (Test-Path (Join-Path $src $n))) { throw "$n is missing from $src. Unpack the whole download and run install.ps1 from inside it." } }
. (Join-Path $src 'app\om3n-command-lib.ps1'); Protect-AppProcess
$dest = Join-Path $env:ProgramFiles 'Om3n Command'; $state = $omenState
$inPlace = ($src -ieq $dest)
$pc = Get-CimInstance Win32_ComputerSystem
if ("$($pc.Manufacturer) $($pc.Model)" -notmatch 'OMEN') { "warning: this PC reports '$($pc.Manufacturer) $($pc.Model)'. Om3n Command is for HP OMEN desktops: the controls this PC does not answer are hidden." }
function Invoke-Tool([string]$script, [string[]]$words) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest $script) @words 2>&1 | ForEach-Object { "$_" } }
function Get-Ours([string]$pattern) { @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='Om3n Command.exe'" | Where-Object { $_.CommandLine -match $pattern -and $_.CommandLine -notmatch 'SelfTest|OffScreen' }) }

$loopWords = $null
if (-not $NoRestart) {
  $loop = Get-Ours 'om3n-command\.ps1"? profile' | Select-Object -First 1
  if ($loop -and $loop.CommandLine -match '(-QuietBelow \d+ -TurboAbove \d+ -Hysteresis \d+)') { $loopWords = $Matches[1] }
  $running = @(Get-Ours '\\Om3n Command\.exe|om3n-command-ui\.ps1') + @(Get-Ours 'om3n-command\.ps1"? profile')
  $running | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  "stopped: $($running.Count) running part(s) of the app"
  Start-Sleep -Seconds 1
}

if ($inPlace) { "files: running from $dest, nothing to copy" }
else {
  if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
  foreach ($d in $folders) {
    $to = Join-Path $dest $d
    if (-not (Test-Path $to)) { New-Item -ItemType Directory -Path $to | Out-Null }
    Copy-Item (Join-Path $src "$d\*") $to -Recurse -Force
    $have = @(Get-ChildItem (Join-Path $src $d) -File | ForEach-Object Name)
    Get-ChildItem $to -File | Where-Object { $_.Name -notin $have } | Remove-Item -Force
  }
  foreach ($f in $files) { Copy-Item (Join-Path $src $f) $dest -Force }
  'Om3n Command.cmd', 'Om3n Command.vbs' | ForEach-Object { Remove-Item (Join-Path $dest $_) -Force -ErrorAction SilentlyContinue }
  "files: copied to $dest"
}
$build = @(Invoke-Tool 'app\om3n-command-build.ps1' @()) | Select-Object -Last 1
"program: $build"
if ($build -notlike 'BUILD built*' -and $build -notlike 'BUILD kept*') { throw "Om3n Command.exe could not be built: $build" }

if (-not (Test-Path $state)) { New-Item -ItemType Directory -Path $state | Out-Null }
function Set-Access([string]$path, [string[]]$grants) {
  $out = & icacls.exe $path /inheritance:r /grant:r @grants /Q 2>&1
  if ($LASTEXITCODE -ne 0) { throw "the permissions of $path could not be set: $out" }
}
$admins = '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F'
$owner = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
Set-Access $state ($admins + "*$($owner):(OI)(CI)RX")
& icacls.exe $state /remove:g '*S-1-5-32-545' /T /C /Q 2>&1 | Out-Null
foreach ($d in 'telemetry', 'temp', 'om3n-command-games') { if (-not (Test-Path (Join-Path $state $d))) { New-Item -ItemType Directory -Path (Join-Path $state $d) | Out-Null } }
foreach ($ours in @(Get-ChildItem $state -Force | Where-Object { $_.Name -like 'om3n-command*' -or $_.Name -in 'telemetry', 'temp' })) {
  foreach ($step in @('/setowner', '*S-1-5-32-544'), @('/reset')) {
    $out = & icacls.exe $ours.FullName @step /T /C /Q 2>&1
    if ($LASTEXITCODE -ne 0) { throw "the permissions of $($ours.FullName) could not be reset: $out" }
  }
}
foreach ($d in 'telemetry', 'temp') { Set-Access (Join-Path $state $d) $admins }
"settings: $state, changed only by Administrators and Windows"
$looks = Join-Path $state 'om3n-command-lights.json'
if (Test-Path $looks) { "settings: your saved looks are kept ($looks)" }

function Get-TaskWords([string]$name) { $t = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue; if ($t) { "$($t.Actions[0].Arguments)" } }
function Test-TaskHere([string]$name) { $w = Get-TaskWords $name; $null -ne $w -and $w -like "*$dest\*" }
function Test-StartsProgram([string]$name) { $t = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue; [bool]$t -and $t.Actions[0].Execute -eq (Join-Path $env:SystemRoot 'System32\wscript.exe') -and "$($t.Actions[0].Arguments)" -like "*`"$dest\app\om3n-command-start.js`"*" }
$tApp = 'SkYn3tLab-om3n-command-app'; $tOpen = 'SkYn3tLab-om3n-command-open'; $tList = 'SkYn3tLab-om3n-command-startup'; $tBoot = 'SkYn3tLab-om3n-command-lights-boot'
if ($Repair -or -not (Test-StartsProgram $tApp) -or -not (Test-StartsProgram $tOpen)) { Invoke-Tool 'app\om3n-command.ps1' 'app', 'on' | Select-Object -Last 1 } else { 'tasks: the two app tasks are in place' }
$w = Get-TaskWords $tList
if ($null -ne $w -and ($Repair -or -not (Test-TaskHere $tList))) { Invoke-Tool 'app\om3n-command.ps1' 'startup', 'on' | Select-Object -First 1 }
$w = Get-TaskWords $tBoot
if ($null -ne $w -and ($Repair -or -not (Test-TaskHere $tBoot))) {
  if ($w -match '-Look "?([^" ]+)') { Invoke-Tool 'app\lights-at-boot.ps1' 'on', $Matches[1] | Select-Object -First 1 }
  else { "warning: the sign-in screen lighting task names no look; set it again on the app's Lighting page" }
}

Invoke-Tool 'app\om3n-command-shortcut.ps1' @()
$check = @(Invoke-Tool 'app\om3n-command-check.ps1' @())
$bad = @($check | Where-Object { $_ -like 'PARSE *' -and $_ -notlike '* OK' })
$sched = New-Object -ComObject Schedule.Service; $sched.Connect()
foreach ($t in @($sched.GetFolder('\').GetTasks(0)) | Where-Object { $_.Name -like 'SkYn3tLab-om3n-command-*' }) {
  if ($t.GetSecurityDescriptor(4) -match '\(A;[^;]*;[^;]*;;;(BU|AU|IU|WD|S-1-5-32-545|S-1-5-11|S-1-5-4|S-1-1-0)\)') { $bad += "TASK $($t.Name) grants access to $($Matches[1])" }
}
"check: $(@($check | Where-Object { $_ -like 'PARSE * OK' }).Count) scripts read correctly, $($bad.Count) with errors"
$bad

if ($NoRestart) { 'not restarted: a running app keeps the code it started with (om3n-command.ps1 app restart)' }
else {
  Start-ScheduledTask -TaskName $tApp
  $list = Join-Path $state 'om3n-command-startup.txt'
  if (-not $loopWords -and (Test-Path $list)) {
    $line = @(Get-Content $list | Where-Object { $_ -match '^\s*fan auto (-QuietBelow \d+ -TurboAbove \d+ -Hysteresis \d+)' }) | Select-Object -First 1
    if ($line -and $line -match '(-QuietBelow \d+ -TurboAbove \d+ -Hysteresis \d+)') { $loopWords = $Matches[1] }
  }
  if ($loopWords) { Invoke-Tool 'app\om3n-command.ps1' (@('fan', 'auto') + ($loopWords -split ' ')) | Select-Object -First 1 }
  'started: Om3n Command is in the notification area (by the clock). The desktop shortcut opens its window.'
}
if ($bad) { exit 1 }
"RESULT installed in $dest"
