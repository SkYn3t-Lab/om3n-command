param([switch]$RemoveData, [switch]$KeepVendorOff)
$ErrorActionPreference = 'Stop'
$dest = Join-Path $env:ProgramFiles 'Om3n Command'; $state = Join-Path $env:ProgramData 'SkYn3tLab'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Run this in PowerShell as administrator (right-click PowerShell, then Run as administrator).' }

$running = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'om3n-command-ui\.ps1|om3n-command\.ps1"? profile' })
$running | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
"stopped: $($running.Count) running part(s) of the app"

$vendor = Join-Path $dest 'app\vendor-startup.ps1'
if ($KeepVendorOff) { 'vendor programs: left as they are' }
elseif (Test-Path $vendor) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $vendor on 2>&1 | Select-Object -Last 3 | ForEach-Object { "vendor programs: $_" } }
else { "vendor programs: $vendor is not there, so nothing was changed" }

$tasks = @(Get-ScheduledTask -TaskName 'SkYn3tLab-om3n-command-*' -ErrorAction SilentlyContinue)
$tasks | ForEach-Object { Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false }
"tasks: $($tasks.Count) removed"
$link = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Om3n Command.lnk'
if (Test-Path $link) { Remove-Item $link -Force; 'shortcut: removed from your desktop' } else { 'shortcut: none on your desktop' }

Set-Location $env:TEMP
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force; "files: $dest deleted" } else { "files: $dest was not there" }

if ($RemoveData) {
  $mine = @(Get-ChildItem $state -File -Filter 'om3n-command-*' -ErrorAction SilentlyContinue)
  $mine | Remove-Item -Force
  $t = Join-Path $state 'telemetry'; if (Test-Path $t) { Remove-Item $t -Recurse -Force }
  "data: $($mine.Count) settings and log files and the recorded readings deleted from $state"
} else { "data: your settings, logs and recorded readings are kept in $state (uninstall.ps1 -RemoveData deletes them)" }
'RESULT uninstalled. The fan setting and any undervolt stay as they are until Windows is restarted.'
