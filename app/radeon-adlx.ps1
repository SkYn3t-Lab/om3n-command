param([ValidateSet('', 'rsr', 'afmf', 'freesync', 'vsr', 'integerscaling')][string]$Feature = '', [int]$Display = -1, [ValidateSet(-1, 0, 1)][int]$Enable = -1, [switch]$Simulate, [string]$Setting = '', [int]$Value = [int]::MinValue, [switch]$ResetShaderCache)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class Adlx {
  [DllImport("amdadlx64.dll", CallingConvention = CallingConvention.Cdecl)] static extern int ADLXQueryFullVersion(out ulong version);
  [DllImport("amdadlx64.dll", CallingConvention = CallingConvention.Cdecl)] static extern int ADLXInitialize(ulong version, out IntPtr system);
  [DllImport("amdadlx64.dll", CallingConvention = CallingConvention.Cdecl)] static extern int ADLXTerminate();
  delegate int GetObj(IntPtr self, out IntPtr obj);
  delegate int GetObjFor(IntPtr self, IntPtr arg, out IntPtr obj);
  delegate int Query(IntPtr self, [MarshalAs(UnmanagedType.LPWStr)] string iid, out IntPtr obj);
  delegate int GetBool(IntPtr self, out byte value);
  delegate int SetBool(IntPtr self, byte value);
  delegate uint GetSize(IntPtr self);
  delegate int GetCount(IntPtr self, out uint count);
  delegate int ItemAt(IntPtr self, uint index, out IntPtr obj);
  delegate int GetStr(IntPtr self, out IntPtr text);
  delegate int Rel(IntPtr self);
  static T Fn<T>(IntPtr obj, int slot) where T : class {
    return (T)(object)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(Marshal.ReadIntPtr(obj), slot * IntPtr.Size), typeof(T));
  }
  static IntPtr sys, settings3d, settings3d1, dispSvc; static List<IntPtr> displays = new List<IntPtr>();
  public static List<string> Names = new List<string>();
  public static string Open() {
    ulong v; int rc = ADLXQueryFullVersion(out v); if (rc != 0) return "ADLXQueryFullVersion failed, rc=" + rc;
    rc = ADLXInitialize(v, out sys); if (rc != 0 || sys == IntPtr.Zero) return "ADLXInitialize failed, rc=" + rc + " (run this in the desktop session)";
    // IADLXSystem: 3 GetDisplaysServices, 7 Get3DSettingsServices
    if (Fn<GetObj>(sys, 7)(sys, out settings3d) != 0) settings3d = IntPtr.Zero;
    if (settings3d != IntPtr.Zero && Fn<Query>(settings3d, 2)(settings3d, "IADLX3DSettingsServices1", out settings3d1) != 0) settings3d1 = IntPtr.Zero;
    string note = "";
    int rcSvc = Fn<GetObj>(sys, 3)(sys, out dispSvc); if (rcSvc != 0) { dispSvc = IntPtr.Zero; note = " (display services rc=" + rcSvc + ")"; }
    if (dispSvc != IntPtr.Zero) {
      IntPtr list;                                               // IADLXDisplayServices: 4 GetDisplays
      uint count; int rcN = Fn<GetCount>(dispSvc, 3)(dispSvc, out count);   // 3 GetNumberOfDisplays
      int rcL = Fn<GetObj>(dispSvc, 4)(dispSvc, out list);
      note = " (driver counts " + count + " rc=" + rcN + ", list rc=" + rcL + ")";
      if (rcL == 0) {
        // list: 5 Begin, 6 End, 11 At_DisplayList (the typed form; the generic At at 7 hands back the base interface)
        uint first = Fn<GetSize>(list, 5)(list), last = Fn<GetSize>(list, 6)(list);
        note += " list " + first + ".." + last;
        for (uint i = first; i < last; i++) {
          IntPtr d; int rcA = Fn<ItemAt>(list, 11)(list, i, out d); if (rcA != 0) { note += " at" + i + "=" + rcA; continue; }
          IntPtr name; Fn<GetStr>(d, 6)(d, out name);            // IADLXDisplay: 6 Name
          displays.Add(d); Names.Add(Marshal.PtrToStringAnsi(name));
        }
      }
    }
    return "ADLX " + (v >> 48) + "." + ((v >> 32) & 0xFFFF) + "." + ((v >> 16) & 0xFFFF) + "." + (v & 0xFFFF) + ", displays " + displays.Count + (displays.Count == 0 ? note : "");
  }
  public static void Close() { try { ADLXTerminate(); } catch { } }
  delegate int GetInt(IntPtr self, out int value);
  delegate int SetInt(IntPtr self, int value);
  static IntPtr gpu;
  // the first GPU: IADLXSystem 1 GetGPUs; list 5 Begin, 11 At_GPUList
  static IntPtr Gpu() {
    if (gpu != IntPtr.Zero) return gpu;
    IntPtr list; if (Fn<GetObj>(sys, 1)(sys, out list) != 0) return IntPtr.Zero;
    IntPtr g; if (Fn<ItemAt>(list, 11)(list, Fn<GetSize>(list, 5)(list), out g) != 0) return IntPtr.Zero;
    return gpu = g;
  }
  // A per-GPU 3D setting: 'svcSlot' is its getter on IADLX3DSettingsServices (taking the GPU), then the object's own
  // slots. Returns "supported|value" or "ERR|reason"; isBool reads a one-byte flag instead of an int.
  public static string Get3D(int svcSlot, int getSlot, bool isBool) {
    IntPtr g = Gpu(); if (g == IntPtr.Zero || settings3d == IntPtr.Zero) return "ERR|no GPU or no 3D settings service";
    IntPtr o; int rc = Fn<GetObjFor>(settings3d, svcSlot)(settings3d, g, out o); if (rc != 0) return "ERR|the driver returned " + rc;
    byte s = 0; rc = Fn<GetBool>(o, 3)(o, out s); string v = "?";
    if (rc == 0 && s != 0) { if (isBool) { byte b; int r = Fn<GetBool>(o, getSlot)(o, out b); v = r == 0 ? b.ToString() : "?(" + r + ")"; } else { int i; int r = Fn<GetInt>(o, getSlot)(o, out i); v = r == 0 ? i.ToString() : "?(" + r + ")"; } }
    Fn<Rel>(o, 1)(o);
    return rc != 0 ? "ERR|IsSupported returned " + rc : s + "|" + v;
  }
  public static string Set3D(int svcSlot, int setSlot, bool isBool, int value) {
    IntPtr g = Gpu(); if (g == IntPtr.Zero || settings3d == IntPtr.Zero) return "ABORT: no GPU or no 3D settings service; nothing sent";
    IntPtr o; int rc = Fn<GetObjFor>(settings3d, svcSlot)(settings3d, g, out o); if (rc != 0) return "ABORT: the driver returned " + rc + "; nothing sent";
    byte s = 0; Fn<GetBool>(o, 3)(o, out s);
    if (s == 0) { Fn<Rel>(o, 1)(o); return "ABORT: the driver reports this setting unsupported; nothing sent"; }
    rc = isBool ? Fn<SetBool>(o, setSlot)(o, (byte)value) : (setSlot < 0 ? -1 : Fn<SetInt>(o, setSlot)(o, value));
    Fn<Rel>(o, 1)(o);
    return "rc=" + rc + (rc == 0 ? " (accepted)" : " (refused)");
  }
  // IADLX3DSettingsServices 15 GetResetShaderCache; the object has IsSupported at 3 and ResetShaderCache at 4
  public static string ResetShaderCache(bool simulate) {
    IntPtr g = Gpu(); if (g == IntPtr.Zero || settings3d == IntPtr.Zero) return "ABORT: no GPU or no 3D settings service; nothing done";
    IntPtr o; int rc = Fn<GetObjFor>(settings3d, 15)(settings3d, g, out o); if (rc != 0) return "ABORT: the driver returned " + rc + "; nothing done";
    byte s = 0; Fn<GetBool>(o, 3)(o, out s);
    string r = s == 0 ? "ABORT: the driver reports the shader-cache reset unsupported; nothing done" : simulate ? "supported; SIMULATE: nothing done" : "rc=" + Fn<Rel>(o, 4)(o) + " (0 = cache cleared)";
    Fn<Rel>(o, 1)(o); return r;
  }
  // the feature object, or IntPtr.Zero with a reason
  static IntPtr Feature(string f, int display, out string why) {
    IntPtr o = IntPtr.Zero; int rc = -1; why = "";
    switch (f) {
      case "rsr": if (settings3d == IntPtr.Zero) { why = "no 3D settings service"; return o; } rc = Fn<GetObj>(settings3d, 14)(settings3d, out o); break;
      case "afmf": if (settings3d1 == IntPtr.Zero) { why = "this driver has no IADLX3DSettingsServices1"; return o; } rc = Fn<GetObj>(settings3d1, 17)(settings3d1, out o); break;
      case "freesync": rc = Fn<GetObjFor>(dispSvc, 9)(dispSvc, displays[display], out o); break;
      case "vsr": rc = Fn<GetObjFor>(dispSvc, 10)(dispSvc, displays[display], out o); break;
      case "integerscaling": rc = Fn<GetObjFor>(dispSvc, 13)(dispSvc, displays[display], out o); break;
    }
    if (rc != 0) { why = "the driver returned " + rc; o = IntPtr.Zero; }
    return o;
  }
  // "supported|enabled" as 0/1, or "ERR|reason"
  public static string Get(string f, int display) {
    string why; IntPtr o = Feature(f, display, out why); if (o == IntPtr.Zero) return "ERR|" + why;
    byte s = 0, e = 0; int rc = Fn<GetBool>(o, 3)(o, out s); int rc2 = Fn<GetBool>(o, 4)(o, out e);
    Fn<Rel>(o, 1)(o);
    return rc != 0 ? "ERR|IsSupported returned " + rc : s + "|" + (rc2 == 0 ? e.ToString() : "?(" + rc2 + ")");
  }
  public static string Set(string f, int display, int enable) {
    string why; IntPtr o = Feature(f, display, out why); if (o == IntPtr.Zero) return "ABORT: " + why + "; nothing sent";
    byte s = 0; Fn<GetBool>(o, 3)(o, out s);
    if (s == 0) { Fn<Rel>(o, 1)(o); return "ABORT: the driver reports this feature unsupported; nothing sent"; }
    int rc = Fn<SetBool>(o, 5)(o, (byte)enable); Fn<Rel>(o, 1)(o);
    return "rc=" + rc + (rc == 0 ? " (accepted)" : " (refused)");
  }
}
'@
$open = [Adlx]::Open()
if ($open -notlike 'ADLX *') { throw $open }
$open
function Show-One([string]$f, [int]$d) {
  $s, $e = [Adlx]::Get($f, $d) -split '\|'
  $label = @{ rsr = 'Radeon Super Resolution'; afmf = 'Fluid Motion Frames'; freesync = 'freesync'; vsr = 'virtual super resolution'; integerscaling = 'integer scaling' }[$f]
  if ($s -eq 'ERR') { '{0,-26} not available: {1}' -f $label, $e } else { '{0,-26} supported={1} on={2}' -f $label, $s, $e }
}
$s3d = [ordered]@{
  enhancedsync = @{ svc = 7; get = 4; set = 5; bool = $true; label = 'Enhanced Sync'; values = 0, 1 }
  vsync        = @{ svc = 8; get = 5; set = 6; label = 'Wait for vertical refresh'; values = 0, 1, 2, 3; note = '0 always off, 1 off unless the app asks, 2 on unless the app asks, 3 always on' }
  aamode       = @{ svc = 10; get = 4; set = 7; label = 'Anti-aliasing mode'; values = 0, 1, 2; note = '0 use app settings, 1 enhance, 2 override' }
  aalevel      = @{ svc = 10; get = 5; set = 8; label = 'Anti-aliasing level'; values = 2, 4, 8 }
  aamethod     = @{ svc = 10; get = 6; set = 9; label = 'Anti-aliasing method'; values = 0, 1, 2; note = '0 multisampling, 1 adaptive, 2 supersampling' }
  maa          = @{ svc = 11; get = 4; set = 5; bool = $true; label = 'Morphological anti-aliasing'; values = 0, 1 }
  af           = @{ svc = 12; get = 4; set = 6; bool = $true; label = 'Anisotropic filtering'; values = 0, 1 }
  aflevel      = @{ svc = 12; get = 5; set = 7; label = 'Anisotropic filtering level'; values = 2, 4, 8, 16 }
  tessmode     = @{ svc = 13; get = 4; set = 6; label = 'Tessellation mode'; values = 0, 1, 2; note = '0 AMD optimized, 1 use app settings, 2 override' }
  tesslevel    = @{ svc = 13; get = 5; set = 7; label = 'Tessellation level'; values = 1, 2, 4, 6, 8, 16, 32, 64; note = '1 = off' }
}
function Show-3D([string]$k) {
  $d = $s3d[$k]; $s, $v = [Adlx]::Get3D($d.svc, $d.get, [bool]$d.bool) -split '\|'
  if ($s -eq 'ERR') { '{0,-14} {1,-28} not available: {2}' -f $k, $d.label, $v }
  else { '{0,-14} {1,-28} supported={2} value={3}{4}' -f $k, $d.label, $s, $v, $(if ($d.note) { "   ($($d.note))" }) }
}
try {
  if ($ResetShaderCache) { "shader cache reset: $([Adlx]::ResetShaderCache([bool]$Simulate))"; return }
  if ($Setting) {
    if (-not $s3d.Contains($Setting)) { throw "-Setting is one of: $($s3d.Keys -join ', ')" }
    "before: $(Show-3D $Setting)"
    if ($Value -eq [int]::MinValue) { return }
    if ($Value -notin $s3d[$Setting].values) { throw "$Value is not one of $($s3d[$Setting].values -join ', '); nothing sent" }
    if ($Simulate) { "SIMULATE: would set $Setting = $Value; nothing sent"; return }
    "set: $([Adlx]::Set3D($s3d[$Setting].svc, $s3d[$Setting].set, [bool]$s3d[$Setting].bool, $Value))"
    "after:  $(Show-3D $Setting)"
    return
  }
  if (-not $Feature) {
    Show-One rsr 0; Show-One afmf 0
    $s3d.Keys | ForEach-Object { Show-3D $_ }
    for ($k = 0; $k -lt [Adlx]::Names.Count; $k++) { "display $k`: $([Adlx]::Names[$k])"; 'freesync', 'vsr', 'integerscaling' | ForEach-Object { '    ' + (Show-One $_ $k) } }
    return
  }
  $perDisplay = $Feature -in 'freesync', 'vsr', 'integerscaling'
  if ($perDisplay -and ($Display -lt 0 -or $Display -ge [Adlx]::Names.Count)) { throw "-Display must be 0..$([Adlx]::Names.Count - 1)" }
  $d = if ($perDisplay) { $Display } else { 0 }
  "before: $(Show-One $Feature $d)"
  if ($Enable -lt 0) { return }
  if ($Simulate) { "SIMULATE: would set $Feature on=$Enable; nothing sent"; return }
  "set: $([Adlx]::Set($Feature, $d, $Enable))"
  "after:  $(Show-One $Feature $d)"
} finally { [Adlx]::Close() }
