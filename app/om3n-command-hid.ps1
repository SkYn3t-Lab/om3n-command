if (-not ('Om3nLightHid' -as [type])) {
  Add-Type @'
using System; using System.ComponentModel; using System.Runtime.InteropServices; using System.Threading; using Microsoft.Win32.SafeHandles;
public static class Om3nLightHid {
  [StructLayout(LayoutKind.Sequential)] struct Attr { public int Size; public ushort Vid, Pid, Version; }
  [StructLayout(LayoutKind.Sequential)] struct IfData { public int Size; public Guid Class; public int Flags; public IntPtr Reserved; }
  [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid g);
  [DllImport("hid.dll")] static extern bool HidD_GetAttributes(SafeFileHandle h, ref Attr a);
  [DllImport("setupapi.dll", SetLastError=true)] static extern IntPtr SetupDiGetClassDevsW(ref Guid g, IntPtr enumerator, IntPtr hwnd, uint flags);
  [DllImport("setupapi.dll", SetLastError=true)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr set, IntPtr dev, ref Guid g, uint index, ref IfData d);
  [DllImport("setupapi.dll", SetLastError=true)] static extern bool SetupDiGetDeviceInterfaceDetailW(IntPtr set, ref IfData d, IntPtr detail, uint size, out uint needed, IntPtr dev);
  [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tmpl);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool WriteFile(SafeFileHandle h, IntPtr buf, uint n, IntPtr done, IntPtr ov);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadFile(SafeFileHandle h, IntPtr buf, uint n, IntPtr done, IntPtr ov);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetOverlappedResult(SafeFileHandle h, IntPtr ov, out uint n, bool wait);
  [DllImport("kernel32.dll")] static extern bool CancelIo(SafeFileHandle h);

  // the device path of the first present HID collection with this vendor and product id, or null
  public static string Find(int vid, int pid) {
    Guid g; HidD_GetHidGuid(out g);
    IntPtr set = SetupDiGetClassDevsW(ref g, IntPtr.Zero, IntPtr.Zero, 0x12);   // present devices, by interface
    if (set == new IntPtr(-1)) return null;
    try {
      for (uint i = 0; ; i++) {
        IfData d = new IfData(); d.Size = Marshal.SizeOf(typeof(IfData));
        if (!SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref g, i, ref d)) return null;
        uint need; SetupDiGetDeviceInterfaceDetailW(set, ref d, IntPtr.Zero, 0, out need, IntPtr.Zero);
        IntPtr mem = Marshal.AllocHGlobal((int)need);
        try {
          Marshal.WriteInt32(mem, IntPtr.Size == 8 ? 8 : 6);                    // cbSize of the detail header
          if (!SetupDiGetDeviceInterfaceDetailW(set, ref d, mem, need, out need, IntPtr.Zero)) continue;
          string path = Marshal.PtrToStringUni(IntPtr.Add(mem, 4));
          using (SafeFileHandle h = CreateFileW(path, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero)) {
            if (h.IsInvalid) continue;
            Attr a = new Attr(); a.Size = Marshal.SizeOf(typeof(Attr));
            if (HidD_GetAttributes(h, ref a) && a.Vid == vid && a.Pid == pid) return path;
          }
        } finally { Marshal.FreeHGlobal(mem); }
      }
    } finally { SetupDiDestroyDeviceInfoList(set); }
  }
  // as HP opens it: read and write, shared, overlapped
  public static SafeFileHandle Open(string path) {
    SafeFileHandle h = CreateFileW(path, 0xC0000000, 3, IntPtr.Zero, 3, 0x40000000, IntPtr.Zero);
    if (h.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
    return h;
  }
  // the buffer one command goes out in: 01, then the command in a 64-byte field
  public static byte[] Frame(byte[] command) {
    if (command.Length > 64) throw new ArgumentException("a command is at most 64 bytes");
    byte[] f = new byte[65]; f[0] = 1; Array.Copy(command, 0, f, 1, command.Length); return f;
  }
  static int Transfer(SafeFileHandle h, byte[] buf, bool write, int timeoutMs, out int error) {
    error = 0;
    IntPtr mem = Marshal.AllocHGlobal(buf.Length), ov = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(NativeOverlapped)));
    using (ManualResetEvent ev = new ManualResetEvent(false)) {
      try {
        Marshal.Copy(buf, 0, mem, buf.Length);
        NativeOverlapped o = new NativeOverlapped(); o.EventHandle = ev.SafeWaitHandle.DangerousGetHandle();
        Marshal.StructureToPtr(o, ov, false);
        bool ok = write ? WriteFile(h, mem, (uint)buf.Length, IntPtr.Zero, ov) : ReadFile(h, mem, (uint)buf.Length, IntPtr.Zero, ov);
        int e = ok ? 0 : Marshal.GetLastWin32Error();
        if (!ok && e != 997) { error = e; return -1; }                          // 997 = still in progress
        uint n;
        // on a timeout the request is cancelled and waited out, so Windows is no longer using the memory freed below
        if (!ev.WaitOne(timeoutMs)) { CancelIo(h); GetOverlappedResult(h, ov, out n, true); error = 1460; return -1; }
        if (!GetOverlappedResult(h, ov, out n, false)) { error = Marshal.GetLastWin32Error(); return -1; }
        if (!write) Marshal.Copy(mem, buf, 0, buf.Length);
        return (int)n;
      } finally { Marshal.FreeHGlobal(mem); Marshal.FreeHGlobal(ov); }
    }
  }
  // HP's libraries take this named mutex around every exchange so two writers never interleave; so do we
  static Mutex Take() {
    Mutex m = new Mutex(false, "Hp.Bridge.Client.SDKs.TyphonChasisLightingSDK");
    try { if (!m.WaitOne(3000)) { m.Dispose(); throw new TimeoutException("another program is talking to the lighting controller"); } }
    catch (AbandonedMutexException) { }                                         // its last holder died: it is ours now
    return m;
  }
  static int WriteOne(SafeFileHandle h, byte[] command) {
    int e; int n = Transfer(h, Frame(command), true, 3000, out e);
    if (n < 0) throw new Win32Exception(e);
    return n;
  }
  // sends each command in order; returns how many bytes Windows took for the last one. Throws if one is refused.
  public static int Send(SafeFileHandle h, byte[][] commands) {
    Mutex m = Take(); int n = 0;
    try { foreach (byte[] c in commands) n = WriteOne(h, c); } finally { m.ReleaseMutex(); m.Dispose(); }
    return n;
  }
  // sends one command and waits for the controller's answer: the report's bytes after its id byte, or null if none came
  public static byte[] Query(SafeFileHandle h, byte[] command, int timeoutMs) {
    Mutex m = Take();
    try {
      WriteOne(h, command);
      byte[] buf = new byte[65]; buf[0] = 1; int e;
      int n = Transfer(h, buf, false, timeoutMs, out e);
      if (n < 0) { if (e == 1460) return null; throw new Win32Exception(e); }
      byte[] r = new byte[Math.Max(0, n - 1)]; Array.Copy(buf, 1, r, 0, r.Length); return r;
    } finally { m.ReleaseMutex(); m.Dispose(); }
  }
}
'@
}

$script:LightZones = @{ Logo = 0; InternalBar = 1; FrontFan = 2; CpuFan = 3 }

function New-LightCommand {
  param([byte]$Mode, [byte]$CommandZone, [byte]$StateByte, [byte[]]$Info = @(), [byte]$Packages = 1, [byte]$Index = 0,
    [byte]$Brightness = 0, [byte]$ArraySize = 0, [byte]$ThemeIndex = 0, [byte]$SpeedByte = 0, [byte]$Direction = 0)
  if ($Info.Length -gt 40) { throw "a command carries at most 40 info bytes, not $($Info.Length)" }
  $b = [byte[]]::new(62)
  $b[0] = 62; $b[1] = 18; $b[2] = $Mode; $b[3] = $Packages; $b[4] = $Index
  if ($Info.Length) { [Array]::Copy($Info, 0, $b, 7, $Info.Length) }
  $b[47] = $Brightness; $b[48] = $ArraySize; $b[53] = $CommandZone; $b[54] = $StateByte
  $b[55] = $ThemeIndex; $b[56] = $SpeedByte; $b[57] = $Direction
  , $b
}

function Get-LightPackets {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('Logo', 'InternalBar', 'FrontFan', 'CpuFan')][string]$Zone,
    [ValidateSet('static', 'off', 'breathing', 'cycle', 'blinking', 'wave', 'spiral', 'vitals', 'audio')][string]$Effect = 'static',
    [int[][]]$Colors = @(),
    [ValidateSet('custom', 'galaxy', 'volcano', 'jungle', 'ocean')][string]$Theme = 'custom',
    [ValidateSet('slow', 'medium', 'fast')][string]$Speed = 'medium',
    [ValidateSet(0, 1)][int]$Direction = 0,
    [ValidateRange(0, 100)][int]$Brightness = 100,
    [ValidateSet('wake', 'sleep')][string]$State = 'wake',
    [ValidateRange(0, 100)][int]$Value = 0,
    [ValidateSet(1, 2)][int]$Preset = 1
  )
  foreach ($c in $Colors) { if ($c.Count -ne 3 -or ($c | Where-Object { $_ -lt 0 -or $_ -gt 255 })) { throw "a colour is three numbers 0-255, not '$($c -join ', ')'" } }
  $needsColour = $Effect -in 'static', 'audio' -or ($Effect -in 'breathing', 'cycle', 'blinking', 'wave', 'spiral' -and $Theme -eq 'custom')
  if ($needsColour -and -not $Colors.Count) { throw "$Effect needs a colour" }
  $zi = [byte]($script:LightZones[$Zone] + 1)      # the controller counts zones from 1
  $st = [byte]@{ wake = 1; sleep = 2 }[$State]
  $out = New-Object 'System.Collections.Generic.List[byte[]]'
  switch ($Effect) {
    'static' {
      $info = [byte[]]::new(3 * $zi)
      for ($k = 0; $k -lt $zi; $k++) { for ($j = 0; $j -lt 3; $j++) { $info[3 * $k + $j] = [byte]$Colors[0][$j] } }
      $out.Add((New-LightCommand -Mode 1 -CommandZone $zi -StateByte $st -Info $info -Packages 1 -Index 1 -Brightness $Brightness -ArraySize 2))
    }
    'off' { $out.Add((New-LightCommand -Mode 5 -CommandZone $zi -StateByte $st -Packages 1 -Index 0 -ArraySize 0)) }
    'vitals' {
      $info = [byte[]]::new(21)
      for ($k = 0; $k -lt 7; $k++) { $info[3 * $k] = [byte]$Value; $info[3 * $k + 1] = [byte]($Preset - 1) }
      $out.Add((New-LightCommand -Mode 3 -CommandZone $zi -StateByte $st -Info $info -Packages 1 -Index 1 -Brightness $Brightness -ArraySize 7))
    }
    'audio' {
      $info = [byte[]]::new(28)
      for ($k = 0; $k -lt 7; $k++) { $info[4 * $k] = [byte]$Value; for ($j = 0; $j -lt 3; $j++) { $info[4 * $k + 1 + $j] = [byte]$Colors[0][$j] } }
      $out.Add((New-LightCommand -Mode 4 -CommandZone $zi -StateByte $st -Info $info -Packages 1 -Index 0 -Brightness $Brightness -ArraySize 7))
    }
    default {
      $mode = [byte]@{ breathing = 6; cycle = 7; blinking = 8; wave = 9; spiral = 10 }[$Effect]
      $rows = New-Object 'System.Collections.Generic.List[object]'
      if ($Theme -ne 'custom') { $rows.Add($null) }
      elseif ($Effect -eq 'wave') { foreach ($k in 0..5) { $rows.Add($Colors[$k % $Colors.Count]) } }
      else { foreach ($c in $Colors) { $rows.Add($c) } }
      if ($rows.Count -gt 255) { throw 'too many colours' }
      $dir = if ($Effect -in 'wave', 'spiral') { $Direction } else { 0 }
      for ($r = 0; $r -lt $rows.Count; $r++) {
        $info = [byte[]]::new(21)
        if ($rows[$r]) { for ($j = 0; $j -lt 3; $j++) { $info[3 * ($zi - 1) + $j] = [byte]$rows[$r][$j] } }
        $out.Add((New-LightCommand -Mode $mode -CommandZone $zi -StateByte $st -Info $info -Packages $rows.Count -Index ($r + 1) -Brightness $Brightness -ArraySize 10 `
              -ThemeIndex (@{ custom = 0; galaxy = 1; volcano = 2; jungle = 3; ocean = 4 }[$Theme]) -SpeedByte (@{ slow = 1; medium = 2; fast = 3 }[$Speed]) -Direction $dir))
      }
    }
  }
  , $out.ToArray()
}

function Format-LightBytes([byte[]]$b) { ($b | ForEach-Object { '{0:X2}' -f $_ }) -join ' ' }

function Open-LightController {
  $path = [Om3nLightHid]::Find(0x103C, 0x84FD)
  if (-not $path) { throw 'the case lighting controller (USB 103C:84FD) is not present' }
  [Om3nLightHid]::Open($path)
}
function Close-LightController($Handle) { if ($Handle) { $Handle.Dispose() } }
function Send-LightPackets($Handle, [byte[][]]$Packets) { [Om3nLightHid]::Send($Handle, $Packets) }

function Send-LightZone {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('Logo', 'InternalBar', 'FrontFan', 'CpuFan')][string]$Zone,
    [ValidateSet('static', 'off', 'breathing', 'cycle', 'blinking', 'wave', 'spiral', 'vitals', 'audio')][string]$Effect = 'static',
    [int[][]]$Colors = @(),
    [ValidateSet('custom', 'galaxy', 'volcano', 'jungle', 'ocean')][string]$Theme = 'custom',
    [ValidateSet('slow', 'medium', 'fast')][string]$Speed = 'medium',
    [ValidateSet(0, 1)][int]$Direction = 0,
    [ValidateRange(0, 100)][int]$Brightness = 100,
    [ValidateSet('wake', 'sleep')][string]$State = 'wake',
    [ValidateRange(0, 100)][int]$Value = 0,
    [ValidateSet(1, 2)][int]$Preset = 1,
    [switch]$Simulate
  )
  $null = $PSBoundParameters.Remove('Simulate')
  $packets = Get-LightPackets @PSBoundParameters
  if ($Simulate) {
    "light: $Zone $Effect -- SIMULATE, nothing is opened or sent; $($packets.Count) write(s) of 65 bytes:"
    foreach ($p in $packets) { '  ' + (Format-LightBytes ([Om3nLightHid]::Frame($p))) }
    return
  }
  $h = Open-LightController
  try { $n = Send-LightPackets $h $packets } finally { Close-LightController $h }
  "light: $Zone $Effect, $($packets.Count) command(s) written to the controller, Windows took $n bytes of the last"
}

function Get-LightFirmware {
  $cmd = [byte[]]::new(62); $cmd[1] = 32
  $h = Open-LightController
  try { , [Om3nLightHid]::Query($h, $cmd, 3000) } finally { Close-LightController $h }
}
