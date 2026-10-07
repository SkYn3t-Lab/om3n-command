param([string]$Script, [string]$User = $env:USERNAME, [int]$WaitSec = 60, [string]$ScriptArgs = '')
$ErrorActionPreference = 'Stop'
$out = [IO.Path]::ChangeExtension($Script, '.out.txt')
Remove-Item $out -ErrorAction SilentlyContinue
$name = 'SkYn3tLab-oneshot-' + [IO.Path]::GetFileNameWithoutExtension($Script) + '-' + $PID   # the process id keeps two runs of the same script name apart
$arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"try { & '$Script' $ScriptArgs *> '$out' } catch { `$_ | Out-String | Add-Content '$out'; exit 1 }`""
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
$principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Force | Out-Null
try {
  Start-ScheduledTask -TaskName $name
  $t = 0
  do { Start-Sleep -Seconds 2; $t += 2; $st = (Get-ScheduledTask -TaskName $name).State } while ($st -eq 'Running' -and $t -lt $WaitSec)
  "task state=$st after ${t}s  lastResult=0x$('{0:X}' -f (Get-ScheduledTaskInfo -TaskName $name).LastTaskResult)"
  if (Test-Path $out) { Get-Content $out } else { 'NO OUTPUT FILE' }
} finally {
  Unregister-ScheduledTask -TaskName $name -Confirm:$false
  "task removed = $(-not (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue))"
}
