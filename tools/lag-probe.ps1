param([int]$IdleSec = 5, [int]$Rounds = 2, [switch]$FanWrite)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System; using System.Diagnostics; using System.Threading;
public static class StallProbe {
  static volatile bool run; static Thread t; static long over1, over5, over20; static double max;
  public static void Start() {
    run = true; over1 = 0; over5 = 0; over20 = 0; max = 0;
    t = new Thread(() => {
      var sw = Stopwatch.StartNew(); double last = sw.Elapsed.TotalMilliseconds;
      while (run) {
        double now = sw.Elapsed.TotalMilliseconds; double g = now - last; last = now;
        if (g > 1) over1++; if (g > 5) over5++; if (g > 20) over20++; if (g > max) max = g;
      }
    });
    t.Priority = ThreadPriority.Highest; t.IsBackground = true; t.Start();
  }
  public static string Stop() {
    run = false; t.Join();
    return String.Format("gaps over 1 ms {0,4}, over 5 ms {1,3}, over 20 ms {2,3}, longest {3,6:F1} ms", over1, over5, over20, max);
  }
}
'@
[Diagnostics.Process]::GetCurrentProcess().PriorityClass = 'High'
function Measure-Step([string]$name, [string]$file, [string]$words = '') {
  [StallProbe]::Start(); $sw = [Diagnostics.Stopwatch]::StartNew()
  if ($file -eq 'idle') { Start-Sleep -Seconds $IdleSec }
  elseif ($file -eq 'none') { & powershell.exe -NoProfile -Command exit | Out-Null }
  else { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path (Join-Path (Split-Path $PSScriptRoot) 'app') $file) @($words -split ' ' | Where-Object { $_ }) 2>&1 | Out-Null }
  $ms = $sw.ElapsedMilliseconds
  '{0,-26} {1,5} ms  {2}' -f $name, $ms, [StallProbe]::Stop()
}
"lag probe on $([Net.Dns]::GetHostName()) at $((Get-Date).ToString('s')), priority $([Diagnostics.Process]::GetCurrentProcess().PriorityClass)"
if ($FanWrite) {
  $modeByte = @{ quiet = 0x10; normal = 0x20; turbo = 0x30 }
  $m = (Get-Content (Join-Path $env:ProgramData 'SkYn3tLab\om3n-command-fanmode.txt') -TotalCount 1).Trim()
  if (-not $modeByte.ContainsKey($m)) { throw "no fan mode on record ('$m'), so there is nothing safe to re-send" }
  $inst = Get-CimInstance -Namespace root\wmi -ClassName hpqBIntM
  $in = New-CimInstance -Namespace root\wmi -ClassName hpqBDataIn -ClientOnly -Property @{
    Sign = [byte[]](0x53, 0x45, 0x43, 0x55); Command = [uint32]0x20008; CommandType = [uint32]0x1A; Size = [uint32]4; hpqBData = [byte[]](0xFF, $modeByte[$m], 0, 0)
  }
  foreach ($r in 1..$Rounds) {
    [StallProbe]::Start(); Start-Sleep -Seconds 2; '{0,-26} {1,5} ms  {2}' -f 'idle', 2000, [StallProbe]::Stop()
    [StallProbe]::Start(); $sw = [Diagnostics.Stopwatch]::StartNew()
    $rc = (Invoke-CimMethod -InputObject $inst -MethodName hpqBIOSInt4 -Arguments @{ InData = $in }).OutData.rwReturnCode
    '{0,-26} {1,5} ms  {2}' -f "fan write ($m, code $rc)", $sw.ElapsedMilliseconds, [StallProbe]::Stop()
    [StallProbe]::Start(); $sw = [Diagnostics.Stopwatch]::StartNew()
    $null = (Get-Counter '\Thermal Zone Information(*)\Temperature').CounterSamples
    '{0,-26} {1,5} ms  {2}' -f 'temperature read', $sw.ElapsedMilliseconds, [StallProbe]::Stop()
  }
  return
}
if ($args) {
  foreach ($r in 1..$Rounds) { Measure-Step 'idle' 'idle'; Measure-Step "$args".Substring(0, [Math]::Min(26, "$args".Length)) 'om3n-command.ps1' "$args" }
  return
}
foreach ($r in 1..$Rounds) {
  Measure-Step 'idle' 'idle'
  Measure-Step 'new powershell' 'none'
  Measure-Step 'processor read' 'cpu-tune.ps1'
  Measure-Step 'graphics read' 'radeon-read.ps1'
  Measure-Step 'graphics features read' 'radeon-features.ps1'
  Measure-Step 'state (all of the above)' 'om3n-command.ps1' 'state'
}
