param([switch]$NoRestart, [switch]$Repair)
$ErrorActionPreference = 'Stop'
$dest = Join-Path $env:ProgramFiles 'Om3n Command'; $state = Join-Path $env:ProgramData 'SkYn3tLab'; $src = $PSScriptRoot.TrimEnd('\')
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Run this in PowerShell as administrator (right-click PowerShell, then Run as administrator).' }
$inPlace = ($src -ieq $dest)
$folders = 'app', 'tools', 'assets', 'defaults', 'docs'
$files = 'Om3n Command.cmd', 'Om3n Command.vbs', 'README.md', 'LICENSE', 'install.ps1', 'uninstall.ps1', 'repair.ps1'
foreach ($n in $folders + $files) { if (-not (Test-Path (Join-Path $src $n))) { throw "$n is missing from $src. Unpack the whole download and run install.ps1 from inside it." } }
$board = "$((Get-CimInstance Win32_BaseBoard).Product)"
if ($board -ne '8703') { "warning: this PC's board is '$board'. Om3n Command was written for the HP OMEN 30L (board 8703): its fan, lighting and memory commands will not work on another model." }
function Invoke-Tool([string]$script, [string[]]$words) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest $script) @words 2>&1 | ForEach-Object { "$_" } }
function Get-Ours([string]$pattern) { @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match $pattern -and $_.CommandLine -notmatch 'SelfTest|OffScreen' }) }

$loopWords = $null
if (-not $NoRestart) {
  $loop = Get-Ours 'om3n-command\.ps1"? profile' | Select-Object -First 1
  if ($loop -and $loop.CommandLine -match '(-QuietBelow \d+ -TurboAbove \d+ -Hysteresis \d+)') { $loopWords = $Matches[1] }
  $running = @(Get-Ours 'om3n-command-ui\.ps1') + @(Get-Ours 'om3n-command\.ps1"? profile')
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
  "files: copied to $dest"
}

if (-not (Test-Path $state)) { New-Item -ItemType Directory -Path $state | Out-Null }
$looks = Join-Path $state 'om3n-command-lights.json'
if (Test-Path $looks) { "settings: your saved looks are kept ($looks)" }
else { Copy-Item (Join-Path $dest 'defaults\om3n-command-lights.json') $looks; "settings: saved looks created from the default ($looks)" }

function Get-TaskWords([string]$name) { $t = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue; if ($t) { "$($t.Actions[0].Arguments)" } }
function Test-TaskHere([string]$name) { $w = Get-TaskWords $name; $null -ne $w -and $w -like "*$dest\*" }
$tApp = 'SkYn3tLab-om3n-command-app'; $tOpen = 'SkYn3tLab-om3n-command-open'; $tList = 'SkYn3tLab-om3n-command-startup'; $tBoot = 'SkYn3tLab-om3n-command-lights-boot'
if ($Repair -or -not (Test-TaskHere $tApp) -or -not (Test-TaskHere $tOpen)) { Invoke-Tool 'app\om3n-command.ps1' 'app', 'on' | Select-Object -Last 1 } else { 'tasks: the two app tasks are in place' }
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
