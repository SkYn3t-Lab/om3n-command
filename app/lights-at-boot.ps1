param([ValidateSet('show', 'on', 'off', 'run')][string]$Mode = 'show', [string]$Look = '')
$task = 'SkYn3tLab-om3n-command-lights-boot'; $tool = Join-Path $PSScriptRoot 'om3n-command.ps1'
$log = 'C:\ProgramData\SkYn3tLab\om3n-command-lights-boot.log'
switch ($Mode) {
  'on' {
    if (-not $Look) { throw 'name the look: lights-at-boot.ps1 on <look>' }
    $names = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tool lights | Where-Object { $_ -match '^\S' })
    if ($names -notcontains $Look) { throw "no lighting look named '$Look'; there is: $($names -join ', ')" }
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" run -Look `"$Look`""
    $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $task -Action $action -Trigger (New-ScheduledTaskTrigger -AtStartup) -Principal $principal -Force | Out-Null
  }
  'off' { Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue }
  'run' {
    foreach ($try in 1..6) {
      $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tool lights $Look 2>&1 | ForEach-Object { "$_" }
      $ok = $LASTEXITCODE -eq 0
      Add-Content $log ('{0:yyyy-MM-dd HH:mm:ss} try {1}, as {2}: {3} -> {4}' -f (Get-Date), $try, [Security.Principal.WindowsIdentity]::GetCurrent().Name, $(if ($ok) { 'ok' } else { "FAILED (exit $LASTEXITCODE)" }), (($out | Select-Object -Last 6) -join ' | '))
      if ($ok) { break }; Start-Sleep -Seconds 5
    }
    return
  }
}
$t = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
if ($t) { "lights at boot: on ($(($t.Actions[0].Arguments -replace '.* run -Look ', '')), task $($t.State))" } else { 'lights at boot: off' }
if (Test-Path $log) { "  last run: $(Get-Content $log -Tail 1)" }
