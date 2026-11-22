$d = $PSScriptRoot; $ctl = Join-Path $d 'om3n-command.ps1'
function Time-Run([string]$exeArgs) {
  $si = New-Object Diagnostics.ProcessStartInfo 'powershell.exe', $exeArgs
  $si.UseShellExecute = $false; $si.CreateNoWindow = $true; $si.RedirectStandardOutput = $true; $si.RedirectStandardError = $true
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $p = [Diagnostics.Process]::Start($si); $e = $p.StandardError.ReadToEndAsync(); $null = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
  [int]$sw.ElapsedMilliseconds
}
'{0,-34} {1}' -f 'powershell -NoProfile, nothing', ((1..3 | ForEach-Object { Time-Run '-NoProfile -Command exit' }) -join '  ')
foreach ($a in 'selftest', 'status', 'cpu', 'gpu', 'gpu -Feature rsr', 'gpu -Setting enhancedsync', 'display', 'sensors', 'startup', 'log', 'lights') {
  '{0,-34} {1}' -f "om3n-command $a", ((1..3 | ForEach-Object { Time-Run "-NoProfile -ExecutionPolicy Bypass -File `"$ctl`" $a" }) -join '  ')
}
'{0,-34} {1}' -f 'app: start, 1 s open, close', ((1..2 | ForEach-Object { Time-Run "-NoProfile -STA -ExecutionPolicy Bypass -File `"$(Join-Path $d 'om3n-command-ui.ps1')`" -OffScreenSeconds 1" }) -join '  ')
"files: $((Get-ChildItem $d -File).Count), $([int]((Get-ChildItem $d -File | Measure-Object Length -Sum).Sum / 1KB)) KB; app log $([int]((Get-Item C:\ProgramData\SkYn3tLab\om3n-command-app.log).Length / 1KB)) KB"
