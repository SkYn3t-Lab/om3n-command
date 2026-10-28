$script:ddcTypeLoaded = $false
function Add-DdcType {
  if ($script:ddcTypeLoaded) { return }
  Add-Type -TypeDefinition @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public static class Ddc {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct PHYSICAL_MONITOR { public IntPtr h; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string desc; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
  public delegate bool MonitorEnumProc(IntPtr hMon, IntPtr hdc, ref RECT r, IntPtr d);
  [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnumProc p, IntPtr d);
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct MONITORINFOEX { public int cbSize; public RECT rcMonitor, rcWork; public uint dwFlags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szDevice; }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct DISPLAY_DEVICE { public int cb; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString; public uint StateFlags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey; }
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool GetMonitorInfoW(IntPtr h, ref MONITORINFOEX mi);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool EnumDisplayDevicesW(string dev, uint i, ref DISPLAY_DEVICE dd, uint flags);
  // the monitor's PnP device id (\\?\DISPLAY#<pnp id>#<instance>#{guid}), through its display device
  public static string DeviceId(IntPtr hMon) {
    var mi = new MONITORINFOEX(); mi.cbSize = Marshal.SizeOf(mi); if (!GetMonitorInfoW(hMon, ref mi)) return "";
    var dd = new DISPLAY_DEVICE(); dd.cb = Marshal.SizeOf(dd); if (!EnumDisplayDevicesW(mi.szDevice, 0, ref dd, 1)) return "";
    return dd.DeviceID ?? "";
  }
  [DllImport("dxva2.dll", SetLastError = true)] public static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr h, out uint n);
  [DllImport("dxva2.dll", SetLastError = true)] public static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr h, uint n, [Out] PHYSICAL_MONITOR[] arr);
  [DllImport("dxva2.dll", SetLastError = true)] public static extern bool GetCapabilitiesStringLength(IntPtr h, out uint len);
  [DllImport("dxva2.dll", SetLastError = true)] public static extern bool CapabilitiesRequestAndCapabilitiesReply(IntPtr h, StringBuilder sb, uint len);
  [DllImport("dxva2.dll", SetLastError = true)] public static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr h, byte code, out uint type, out uint cur, out uint max);
  [DllImport("dxva2.dll", SetLastError = true)] public static extern bool SetVCPFeature(IntPtr h, byte code, uint value);
  [DllImport("dxva2.dll", SetLastError = true)] public static extern bool DestroyPhysicalMonitors(uint n, PHYSICAL_MONITOR[] arr);
  // the high-level functions Microsoft documents for any monitor: capabilities, color temperature, the three gains
  [DllImport("dxva2.dll", SetLastError = true)] public static extern bool GetMonitorCapabilities(IntPtr h, out uint caps, out uint temps);
  [DllImport("dxva2.dll", SetLastError = true)] public static extern bool GetMonitorColorTemperature(IntPtr h, out int temp);
  [DllImport("dxva2.dll", SetLastError = true)] public static extern bool SetMonitorColorTemperature(IntPtr h, int temp);
  [DllImport("dxva2.dll", SetLastError = true)] public static extern bool GetMonitorRedGreenOrBlueGain(IntPtr h, int which, out uint min, out uint cur, out uint max);
  [DllImport("dxva2.dll", SetLastError = true)] public static extern bool SetMonitorRedGreenOrBlueGain(IntPtr h, int which, uint value);
  public static List<IntPtr> Monitors() {
    var l = new List<IntPtr>();
    EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate(IntPtr hMon, IntPtr hdc, ref RECT r, IntPtr d) { l.Add(hMon); return true; }, IntPtr.Zero);
    return l;
  }
}
"@
  $script:ddcTypeLoaded = $true
}

$monitorSettings = @(
  @{ id = 'brightness';    label = 'Brightness';                 code = 0x10; page = -1;   kind = 'range'; min = 0; max = 100; canSet = $true;  wait = 100;  note = 'The backlight. 100 is what HP ships.' }
  @{ id = 'contrast';      label = 'Contrast';                   code = 0x12; page = -1;   kind = 'range'; min = 0; max = 100; canSet = $true;  wait = 100;  note = '' }
  @{ id = 'sharpness';     label = 'Sharpness';                  code = 0x87; page = -1;   kind = 'range'; min = 1; max = 7;   canSet = $true;  wait = 100;  note = 'The panel''s own sharpening, 1 to 7. The game''s upscaler already sharpens, so the middle is enough.' }
  @{ id = 'hpenhance';     label = 'HP Enhance+';                code = 0xEE; page = -1;   kind = 'choice'; map = [ordered]@{ '1' = 'Low'; '2' = 'Medium'; '3' = 'High' }; canSet = $true; wait = 350; note = 'Extra detail and contrast on top of the picture preset.' }
  @{ id = 'blackstretch';  label = 'Black stretch';              code = 0x2E; page = -1;   kind = 'choice'; map = [ordered]@{ '0' = 'Off'; '1' = 'Low'; '2' = 'Medium'; '3' = 'High' }; canSet = $true; wait = 350; note = 'Lifts the darkest tones so what hides in shadow is visible, at the cost of some depth in the blacks. Medium is a good game setting.' }
  @{ id = 'responsetime';  label = 'Response time';              code = 0xEB; page = 0;    kind = 'choice'; map = [ordered]@{ '1' = 'Level 1'; '2' = 'Level 2'; '3' = 'Level 3'; '4' = 'Level 4'; '5' = 'Level 5' }; canSet = $true; wait = 350; note = 'Pixel overdrive, 1 slow to 5 fastest. Too high leaves a bright halo behind moving edges: step back one if you see it.' }
  @{ id = 'mprt';          label = 'MPRT (backlight strobing)';  code = 0xE9; page = 0;    kind = 'choice'; map = [ordered]@{ '2' = 'Off'; '3' = 'Level 1'; '4' = 'Level 2'; '5' = 'Level 3'; '6' = 'Level 4'; '7' = 'Level 5' }; canSet = $true; wait = 350; note = 'Blinks the backlight to cut motion blur, which also dims the picture. HP''s 1 ms figure is this.' }
  @{ id = 'edgeprecision'; label = 'Edge precision';             code = 0xE9; page = 3;    kind = 'choice'; map = [ordered]@{ '1' = 'Off'; '2' = 'On' }; canSet = $false; wait = 350; note = 'Sharper outlines. Shown only: HP''s own app offers it on six other OMEN models, not the 34c.' }
  @{ id = 'shadowvision';  label = 'Shadow Vision';             code = 0xE9; page = 4; kind = 'choice'; map = [ordered]@{ '0' = 'Off'; '1' = 'On' }; canSet = $false; wait = 350; note = 'Lifts the darkest tones so what hides in shadow is visible. Shown only: HP''s own app offers it on six other OMEN models, and the 34c takes the write and keeps its value.' }
  @{ id = 'adaptivesync';  label = 'Adaptive-Sync';              code = 0xEC; page = 0;    kind = 'choice'; map = [ordered]@{ '0' = 'Off'; '1' = 'On' }; canSet = $true; wait = 4000; hpsync = $true; note = 'The panel follows the game''s frame rate instead of tearing or waiting for the next refresh. The screen goes black for a moment when this changes: the link is renegotiated.' }
  @{ id = 'fpscounter';    label = 'Frame rate counter';         code = 0xF4; page = 0;    kind = 'choice'; map = [ordered]@{ '0' = 'Off'; '1' = 'On' }; canSet = $true; wait = 350; note = 'The monitor''s own counter, drawn by the monitor: it shows the frames it actually receives.' }
  @{ id = 'fpslocation';   label = 'Counter position';           code = 0xF4; page = 2;    kind = 'choice'; map = [ordered]@{ '0' = 'Top left'; '1' = 'Top right'; '2' = 'Bottom left'; '3' = 'Bottom right' }; canSet = $true; wait = 350; note = '' }
  @{ id = 'crosshair';     label = 'Crosshair';                  code = 0xF4; page = 0x0A; kind = 'choice'; map = [ordered]@{ '0' = 'Off'; '1' = 'On' }; canSet = $true; wait = 350; note = 'A crosshair drawn by the monitor at the center of the screen.' }
  @{ id = 'crosshairstyle'; label = 'Crosshair style';           code = 0xF4; page = 0x11; kind = 'read'; canSet = $false; wait = 0; note = 'Shown as the monitor''s own number; the styles are picked in its menu.' }
  @{ id = 'picturemode';   label = 'Picture preset';             code = 0xDC; page = 0;    kind = 'read'; canSet = $false; wait = 0; note = 'The color preset, as the monitor numbers it (Gaming, Standard, Warm, Cool, Night, Native, Cinema). Pick it in the menu.' }
  @{ id = 'input';         label = 'Input';                      code = 0x60; page = -1;   kind = 'choice'; map = [ordered]@{ '15' = 'DisplayPort'; '17' = 'HDMI 1'; '18' = 'HDMI 2' }; canSet = $false; wait = 0; note = 'Switching the input from here would take the screen away from this PC, so it is not offered.' }
  @{ id = 'colortemp';     label = 'Color temperature';          hl = 'temp'; kind = 'choice'; canSet = $true; wait = 350; note = 'The white point. 6500 K is the daylight standard most content is made for.' }
  @{ id = 'gainred';       label = 'Red gain';                   hl = 'gain'; which = 0; kind = 'range'; canSet = $true; wait = 100; note = 'Fine color balance; only applies in a user color mode.' }
  @{ id = 'gaingreen';     label = 'Green gain';                 hl = 'gain'; which = 1; kind = 'range'; canSet = $true; wait = 100; note = '' }
  @{ id = 'gainblue';      label = 'Blue gain';                  hl = 'gain'; which = 2; kind = 'range'; canSet = $true; wait = 100; note = '' }
)
$monitorTempNames = @('unknown', '4000 K', '5000 K', '6500 K', '7500 K', '8200 K', '9300 K', '10000 K', '11500 K')

function Get-MonitorHlCaps($handle) {
  $c = [uint32]0; $t = [uint32]0
  if ([Ddc]::GetMonitorCapabilities($handle, [ref]$c, [ref]$t)) { return @{ ok = $true; caps = $c; temps = $t } }
  @{ ok = $false; err = "capabilities refused (error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))" }
}

function Read-MonitorHl($handle, $def, $hl) {
  if ($def.hl -eq 'temp') {
    $t = 0
    if (-not $hl.ok -or $hl.temps -eq 0 -or -not [Ddc]::GetMonitorColorTemperature($handle, [ref]$t)) { return @{ ok = $false; err = 'not offered by this monitor' } }
    $map = [ordered]@{}
    for ($i = 1; $i -lt $monitorTempNames.Count; $i++) { if ($hl.temps -band (1 -shl ($i - 1))) { $map["$i"] = $monitorTempNames[$i] } }
    return @{ ok = $true; value = [int]$t; map = $map; temps = $hl.temps }
  }
  $mn = [uint32]0; $cu = [uint32]0; $mx = [uint32]0
  if (-not [Ddc]::GetMonitorRedGreenOrBlueGain($handle, [int]$def.which, [ref]$mn, [ref]$cu, [ref]$mx)) { return @{ ok = $false; err = 'not offered by this monitor' } }
  @{ ok = $true; value = [int]$cu; min = [int]$mn; max = [int]$mx }
}

function Get-MonitorDef([string]$id) { $d = $monitorSettings | Where-Object { $_.id -eq $id }; if (-not $d) { throw "no such monitor setting: $id. One of: $(($monitorSettings | ForEach-Object { $_.id }) -join ', ')" }; $d }

function Get-CapsCodes([string]$caps) {
  $codes = @{}
  $at = $caps.IndexOf('vcp(')
  if ($at -lt 0) { return $codes }
  $depth = 0; $tok = ''
  for ($j = $at + 4; $j -lt $caps.Length; $j++) {
    $ch = $caps[$j]
    if ($ch -eq '(') { if ($depth -eq 0 -and $tok) { $codes[[Convert]::ToInt32($tok, 16)] = $true }; $tok = ''; $depth++ }
    elseif ($ch -eq ')') { if ($depth -eq 0) { if ($tok) { $codes[[Convert]::ToInt32($tok, 16)] = $true }; break }; $depth-- }
    elseif ($depth -eq 0) { if ($ch -match '[0-9A-Fa-f]') { $tok += $ch } elseif ($tok) { $codes[[Convert]::ToInt32($tok, 16)] = $true; $tok = '' } }
  }
  $codes
}

function Invoke-OnMonitors([scriptblock]$body) {
  Add-DdcType
  $serials = @{}
  try { foreach ($w in Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorID -ErrorAction Stop) { $serials[$w.InstanceName -replace '^DISPLAY\\', '' -replace '_0$', ''] = -join ($w.SerialNumberID | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) } } catch { }
  $i = 0
  foreach ($hm in [Ddc]::Monitors()) {
    $dev = [Ddc]::DeviceId($hm); $serial = ''
    if ($dev -match '^\\\\\?\\DISPLAY#([^#]+)#([^#]+)#') { $serial = "$($serials[$Matches[1] + '\' + $Matches[2]])" }
    $n = [uint32]0
    if (-not [Ddc]::GetNumberOfPhysicalMonitorsFromHMONITOR($hm, [ref]$n) -or $n -lt 1) { $i++; continue }
    $arr = New-Object 'Ddc+PHYSICAL_MONITOR[]' $n
    if (-not [Ddc]::GetPhysicalMonitorsFromHMONITOR($hm, $n, $arr)) { $i++; continue }
    try {
      foreach ($pm in $arr) {
        $caps = ''; $len = [uint32]0
        if ([Ddc]::GetCapabilitiesStringLength($pm.h, [ref]$len) -and $len -gt 0) {
          $sb = New-Object Text.StringBuilder ([int]$len)
          if ([Ddc]::CapabilitiesRequestAndCapabilitiesReply($pm.h, $sb, $len)) { $caps = $sb.ToString() }
        }
        $model = $(if ($caps -match 'model\(([^)]*)\)') { $Matches[1] } else { '' })
        & $body @{ index = $i; handle = $pm.h; model = $model; caps = $caps; codes = Get-CapsCodes $caps; serial = $serial }
      }
    } finally { [void][Ddc]::DestroyPhysicalMonitors($n, $arr) }
    $i++
  }
}

function Read-MonitorRaw($handle, $def) {
  if ($def.page -ge 0) {
    if (-not [Ddc]::SetVCPFeature($handle, [byte]$def.code, [uint32](0x8000 -bor ($def.page -shl 8)))) { return @{ ok = $false; err = "page select refused (error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))" } }
    Start-Sleep -Milliseconds 80
  }
  $t = [uint32]0; $c = [uint32]0; $m = [uint32]0
  if (-not [Ddc]::GetVCPFeatureAndVCPFeatureReply($handle, [byte]$def.code, [ref]$t, [ref]$c, [ref]$m)) { return @{ ok = $false; err = "read refused (error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))" } }
  if ($def.page -ge 0 -and ($c -shr 8) -ne $def.page) { return @{ ok = $false; err = ("the answer is for page 0x{0:X2}, not 0x{1:X2}" -f ($c -shr 8), $def.page); raw = $c } }
  $v = $(if ($def.page -ge 0 -or $def.kind -eq 'choice') { $c -band 0xFF } else { $c })
  if ($def.hpsync) { $v = $(if ($c -eq 0 -or $c -eq 6) { 0 } else { 1 }) }
  @{ ok = $true; raw = $c; value = [int]$v; max = $m }
}

function Format-MonitorValue($def, [int]$value) {
  if ($def.kind -eq 'choice' -and $def.map.Contains("$value")) { return $def.map["$value"] }
  "$value"
}

function Get-MonitorReport([int]$Only = -1) {
  $out = New-Object Collections.ArrayList
  Invoke-OnMonitors {
    param($m)
    if ($Only -ge 0 -and $m.index -ne $Only) { return }
    $isOmen = $m.model -like 'OMEN*'
    $hl = Get-MonitorHlCaps $m.handle
    $rows = New-Object Collections.ArrayList
    foreach ($d in $monitorSettings) {
      if (-not $isOmen -and $d.page -ge 0) { continue }
      if (-not $d.hl -and -not $m.codes.Contains([int]$d.code)) { continue }
      $row = [ordered]@{ id = $d.id; label = $d.label; kind = $d.kind; canSet = [bool]$d.canSet; note = $d.note }
      if ($d.hl) {
        $r = Read-MonitorHl $m.handle $d $hl
        if (-not $r.ok) { if ($r.err -eq 'not offered by this monitor') { continue }; $row.error = $r.err; [void]$rows.Add($row); continue }
        $row.value = $r.value
        if ($d.hl -eq 'temp') { $row.display = $monitorTempNames[[Math]::Min($r.value, $monitorTempNames.Count - 1)]; $row.choices = @($r.map.Keys | ForEach-Object { [ordered]@{ value = [int]$_; label = $r.map[$_] } }) }
        else { $row.display = "$($r.value)"; $row.min = $r.min; $row.max = $r.max }
        [void]$rows.Add($row); continue
      }
      $r = Read-MonitorRaw $m.handle $d
      if ($r.ok) {
        $row.value = $r.value; $row.display = Format-MonitorValue $d $r.value
        if ($d.kind -eq 'range') { $row.min = $d.min; $row.max = $d.max }
        if ($d.kind -eq 'choice') { $row.choices = @($d.map.Keys | ForEach-Object { [ordered]@{ value = [int]$_; label = $d.map[$_] } }) }
      } else { $row.error = $r.err }
      [void]$rows.Add($row)
      Start-Sleep -Milliseconds 40
    }
    [void]$out.Add([ordered]@{ index = $m.index; model = $m.model; serial = $m.serial; omen = $isOmen; codes = @($m.codes.Keys | Sort-Object | ForEach-Object { '{0:X2}' -f $_ }); caps = $(if ($hl.ok) { '{0:X} temps {1:X}' -f $hl.caps, $hl.temps } else { $hl.err }); settings = @($rows) })
  }
  @($out)
}

function Set-MonitorSetting([int]$Index, [string]$Id, [int]$Value, [switch]$Simulate) {
  $def = Get-MonitorDef $Id
  if (-not $def.canSet) { return "(REFUSED) $($def.label) is shown only; $($def.note)" }
  if ($def.kind -eq 'range' -and ($Value -lt $def.min -or $Value -gt $def.max)) { return "(REFUSED) $($def.label) takes $($def.min) to $($def.max), not $Value" }
  if ($def.kind -eq 'choice' -and -not $def.map.Contains("$Value")) { return "(REFUSED) $($def.label) takes $(($def.map.Keys | ForEach-Object { "$_ ($($def.map[$_]))" }) -join ', '), not $Value" }
  $lines = New-Object Collections.ArrayList
  $st = @{ found = $false }
  Invoke-OnMonitors {
    param($m)
    if ($Index -ge 0) { if ($m.index -ne $Index) { return } } elseif ($m.model -notlike 'OMEN*') { return }
    if ($st.found) { return }
    $st.found = $true
    if ($def.page -ge 0 -and $m.model -notlike 'OMEN*') { [void]$lines.Add("(REFUSED) monitor $($m.index) ($($m.model)) is not an OMEN: $($def.label) is one of HP's own settings"); return }
    if (-not $def.hl -and -not $m.codes.Contains([int]$def.code)) { [void]$lines.Add("(REFUSED) monitor $($m.index) ($($m.model)) does not list $($def.label) (code 0x{0:X2}) among what it accepts" -f $def.code); return }
    if ($def.hl) {
      $hl = Get-MonitorHlCaps $m.handle
      $before = Read-MonitorHl $m.handle $def $hl
      if (-not $before.ok) { [void]$lines.Add("(REFUSED) $($def.label) on monitor $($m.index) ($($m.model)): $($before.err)"); return }
      if ($def.hl -eq 'temp') {
        if (-not $before.map.Contains("$Value")) { [void]$lines.Add("(REFUSED) $($def.label) on this monitor takes $(($before.map.Keys | ForEach-Object { "$_ ($($before.map[$_]))" }) -join ', '), not $Value"); return }
        $was = $monitorTempNames[[Math]::Min($before.value, $monitorTempNames.Count - 1)]; $want = $before.map["$Value"]
      } else {
        if ($Value -lt $before.min -or $Value -gt $before.max) { [void]$lines.Add("(REFUSED) $($def.label) on this monitor takes $($before.min) to $($before.max), not $Value"); return }
        $was = "$($before.value)"; $want = "$Value"
      }
      $head = "monitor $($m.index) ($($m.model)): $($def.label) $was -> $want"
      if ($Simulate) { [void]$lines.Add("$head -- SIMULATE, nothing is sent"); return }
      $ok = $(if ($def.hl -eq 'temp') { [Ddc]::SetMonitorColorTemperature($m.handle, [int]$Value) } else { [Ddc]::SetMonitorRedGreenOrBlueGain($m.handle, [int]$def.which, [uint32]$Value) })
      if (-not $ok) { [void]$lines.Add("$head FAILED: the monitor refused the write (error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"); return }
      Start-Sleep -Milliseconds $def.wait
      $after = Read-MonitorHl $m.handle $def $hl
      if (-not $after.ok) { [void]$lines.Add("$head sent; read back FAILED: $($after.err)"); return }
      if ($after.value -eq $Value) { [void]$lines.Add("$head sent, read back $want") } else { [void]$lines.Add("$head sent, but it reads back $($after.value): FAILED") }
      return
    }
    $before = Read-MonitorRaw $m.handle $def
    $was = $(if ($before.ok) { Format-MonitorValue $def $before.value } else { "unreadable ($($before.err))" })
    if ($def.hpsync) {
      if (-not $before.ok) { [void]$lines.Add("(REFUSED) $($def.label) could not be read first: $($before.err)"); return }
      $wire = [uint32]$(if ($before.raw -lt 6) { $Value } else { $Value + 6 })
    } elseif ($def.page -ge 0) { $wire = [uint32](($def.page -shl 8) -bor $Value) } else { $wire = [uint32]$Value }
    $want = Format-MonitorValue $def $Value
    $head = "monitor $($m.index) ($($m.model)): $($def.label) $was -> $want (code 0x{0:X2} = 0x{1:X4})" -f $def.code, $wire
    if ($Simulate) { [void]$lines.Add("$head -- SIMULATE, nothing is sent"); return }
    $ok = $false
    foreach ($try in 1..5) { if ([Ddc]::SetVCPFeature($m.handle, [byte]$def.code, $wire)) { $ok = $true; break }; Start-Sleep -Milliseconds 50 }
    if (-not $ok) { [void]$lines.Add("$head FAILED: the monitor refused the write (error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"); return }
    Start-Sleep -Milliseconds $def.wait
    $after = Read-MonitorRaw $m.handle $def
    if (-not $after.ok -and $def.hpsync) { Start-Sleep -Milliseconds 3000; $after = Read-MonitorRaw $m.handle $def }
    if (-not $after.ok) { [void]$lines.Add("$head sent; read back FAILED: $($after.err)"); return }
    $now = Format-MonitorValue $def $after.value
    if ($after.value -eq $Value) { [void]$lines.Add("$head sent, read back $now") } else { [void]$lines.Add("$head sent, but it reads back ${now}: FAILED") }
  }
  if (-not $st.found) { [void]$lines.Add("(REFUSED) no monitor $(if ($Index -ge 0) { "with index $Index" } else { 'of HP''s OMEN line' }) answered") }
  @($lines)
}

function Get-MonitorDump([int]$Only = -1) {
  $paged = @(0xE1, 0xE9, 0xEB, 0xEC, 0xF4, 0xDC)
  $lines = New-Object Collections.ArrayList
  Invoke-OnMonitors {
    param($m)
    if ($Only -ge 0 -and $m.index -ne $Only) { return }
    [void]$lines.Add(("monitor {0} {1} serial {2}" -f $m.index, $m.model, $m.serial))
    foreach ($code in ($m.codes.Keys | Sort-Object)) {
      $t = [uint32]0; $c = [uint32]0; $x = [uint32]0
      if ([Ddc]::GetVCPFeatureAndVCPFeatureReply($m.handle, [byte]$code, [ref]$t, [ref]$c, [ref]$x)) { [void]$lines.Add(("{0:X2} plain raw=0x{1:X4} max=0x{2:X4}" -f $code, $c, $x)) }
      else { [void]$lines.Add(("{0:X2} plain refused" -f $code)) }
      Start-Sleep -Milliseconds 40
      if ($m.model -notlike 'OMEN*' -or $code -notin $paged) { continue }
      for ($pg = 0; $pg -le 0x12; $pg++) {
        $r = Read-MonitorRaw $m.handle @{ code = $code; page = $pg; kind = 'read' }
        if ($r.ok) { [void]$lines.Add(("{0:X2} page 0x{1:X2} raw=0x{2:X4} max=0x{3:X4}" -f $code, $pg, $r.raw, $r.max)) }
        elseif ($null -ne $r.raw) { [void]$lines.Add(("{0:X2} page 0x{1:X2} answered 0x{2:X4} (another page)" -f $code, $pg, $r.raw)) }
        else { [void]$lines.Add(("{0:X2} page 0x{1:X2} {2}" -f $code, $pg, $r.err)) }
        Start-Sleep -Milliseconds 40
      }
    }
  }
  @($lines)
}
