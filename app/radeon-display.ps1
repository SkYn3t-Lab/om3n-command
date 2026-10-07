param([int]$Display = -1, [ValidateSet('', 'freesync', 'gpuscaling', 'hdr', 'colordepth', 'pixelformat', 'brightness', 'contrast', 'saturation', 'hue', 'temperature')][string]$Set = '', [int]$Value = [int]::MinValue, [switch]$Simulate, [switch]$Raw)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class AdlDisp {
  public delegate IntPtr Malloc(int size);
  static IntPtr Alloc(int size) { return Marshal.AllocCoTaskMem(size); }
  static Malloc keep = Alloc;
  const string D = "atiadlxx.dll";
  [DllImport(D)] static extern int ADL2_Main_Control_Create(Malloc cb, int connectedOnly, out IntPtr ctx);
  [DllImport(D)] static extern int ADL2_Main_Control_Destroy(IntPtr ctx);
  [DllImport(D)] static extern int ADL2_Adapter_NumberOfAdapters_Get(IntPtr ctx, out int n);
  [DllImport(D)] static extern int ADL2_Adapter_AdapterInfo_Get(IntPtr ctx, IntPtr info, int size);
  [DllImport(D)] static extern int ADL2_Display_DisplayInfo_Get(IntPtr ctx, int adapter, out int n, out IntPtr info, int forceDetect);
  [DllImport(D)] static extern int ADL2_Display_FreeSyncState_Get(IntPtr ctx, int adapter, int display, out int current, out int def, out int minHz, out int maxHz);
  [DllImport(D)] static extern int ADL2_Display_FreeSyncState_Set(IntPtr ctx, int adapter, int display, int setting, int refreshMicroHz);
  [DllImport(D)] static extern int ADL2_DFP_GPUScalingEnable_Get(IntPtr ctx, int adapter, int display, out int support, out int current, out int def);
  [DllImport(D)] static extern int ADL2_DFP_GPUScalingEnable_Set(IntPtr ctx, int adapter, int display, int current);
  [DllImport(D)] static extern int ADL2_Display_ColorDepth_Get(IntPtr ctx, int adapter, int display, out int depth);
  [DllImport(D)] static extern int ADL2_Display_ColorDepth_Set(IntPtr ctx, int adapter, int display, int depth);
  [DllImport(D)] static extern int ADL2_Display_SupportedColorDepth_Get(IntPtr ctx, int adapter, int display, out int depth);
  [DllImport(D)] static extern int ADL2_Display_PixelFormat_Get(IntPtr ctx, int adapter, int display, out int format);
  [DllImport(D)] static extern int ADL2_Display_PixelFormat_Set(IntPtr ctx, int adapter, int display, int format);
  [DllImport(D)] static extern int ADL2_Display_SupportedPixelFormat_Get(IntPtr ctx, int adapter, int display, out int format);
  [DllImport(D)] static extern int ADL2_Display_HDRState_Get(IntPtr ctx, int adapter, [In] int[] displayId, out int support, out int enable);
  [DllImport(D)] static extern int ADL2_Display_HDRState_Set(IntPtr ctx, int adapter, [In] int[] displayId, int enable);
  [DllImport(D)] static extern int ADL2_Display_Color_Get(IntPtr ctx, int adapter, int display, int type, out int current, out int def, out int min, out int max, out int step);
  [DllImport(D)] static extern int ADL2_Display_Color_Set(IntPtr ctx, int adapter, int display, int type, int current);
  const int InfoSize = 552;   // ADLDisplayInfo: ADLDisplayID (4 ints), int, 2 x char[256], 5 ints
  static IntPtr ctx; static List<int> adapters = new List<int>();
  public class Disp { public int Adapter, Index; public int[] Id; public string Name; }
  public static List<Disp> List = new List<Disp>();
  public static List<string> Raw = new List<string>();   // every entry the driver listed, for -Raw
  static readonly string[] colourNames = { "brightness", "contrast", "saturation", "hue", "temperature" };
  static readonly int[] colourTypes = { 1, 2, 4, 8, 16 };   // ADL_DISPLAY_COLOR_*
  public static string Open() {
    int rc = ADL2_Main_Control_Create(keep, 1, out ctx); if (rc != 0) return "the driver interface did not open, rc=" + rc;
    int n; ADL2_Adapter_NumberOfAdapters_Get(ctx, out n);
    IntPtr buf = Marshal.AllocCoTaskMem(1572 * n); for (int i = 0; i < 1572 * n; i++) Marshal.WriteByte(buf, i, 0);
    ADL2_Adapter_AdapterInfo_Get(ctx, buf, 1572 * n);
    var seen = new HashSet<string>();
    for (int i = 0; i < n; i++) {
      int a = Marshal.ReadInt32(IntPtr.Add(buf, i * 1572), 4); int cnt; IntPtr info;
      if (ADL2_Display_DisplayInfo_Get(ctx, a, out cnt, out info, 0) != 0) continue;
      for (int d = 0; d < cnt; d++) {
        IntPtr p = IntPtr.Add(info, d * InfoSize);
        int value = Marshal.ReadInt32(p, 548);                      // iDisplayInfoValue: bit 0 connected, bit 1 mapped
        var id = new int[4]; Marshal.Copy(p, id, 0, 4);
        Raw.Add(string.Format("adapter {0} entry {1}: id {2},{3},{4},{5} value=0x{6:X} {7}", a, d, id[0], id[1], id[2], id[3], value, Marshal.PtrToStringAnsi(IntPtr.Add(p, 20))));
        if ((value & 3) != 3) continue;
        // every display is listed under the first adapter entry; the one that drives it is iDisplayLogicalAdapterIndex
        string name = Marshal.PtrToStringAnsi(IntPtr.Add(p, 20));
        if (id[2] < 0 || !seen.Add(id[0].ToString())) continue;
        List.Add(new Disp { Adapter = id[2], Index = id[0], Id = id, Name = name });
      }
    }
    Marshal.FreeCoTaskMem(buf);
    return List.Count == 0 ? "no connected display was reported (run this in the desktop session)" : "";
  }
  public static void Close() { if (ctx != IntPtr.Zero) ADL2_Main_Control_Destroy(ctx); }
  public static List<string> Show(int k) {
    var o = new List<string>(); var d = List[k]; int a = d.Adapter, i = d.Index, rc, x, y, z, w, v;
    o.Add(string.Format("display {0}: {1}  (adapter {2}, display index {3})", k, d.Name, a, i));
    rc = ADL2_Display_FreeSyncState_Get(ctx, a, i, out x, out y, out z, out w);
    o.Add(rc == 0 ? string.Format("    freesync     current={0} default={1} range {2:F0}-{3:F0} Hz", x, y, z / 1e6, w / 1e6) : "    freesync     not reported (rc=" + rc + ")");
    rc = ADL2_DFP_GPUScalingEnable_Get(ctx, a, i, out x, out y, out z);
    o.Add(rc == 0 ? string.Format("    gpuscaling   supported={0} current={1} default={2}", x, y, z) : "    gpuscaling   not reported (rc=" + rc + ")");
    rc = ADL2_Display_HDRState_Get(ctx, a, d.Id, out x, out y);
    o.Add(rc == 0 ? string.Format("    hdr          supported={0} on={1}", x, y) : "    hdr          not reported (rc=" + rc + ")");
    rc = ADL2_Display_ColorDepth_Get(ctx, a, i, out x); int rc2 = ADL2_Display_SupportedColorDepth_Get(ctx, a, i, out y);
    o.Add(rc == 0 ? string.Format("    colordepth   current={0} supported mask=0x{1:X}  (1=6 bpc 2=8 4=10 8=12 16=14 32=16)", x, rc2 == 0 ? y : 0) : "    colordepth   not reported (rc=" + rc + ")");
    rc = ADL2_Display_PixelFormat_Get(ctx, a, i, out x); rc2 = ADL2_Display_SupportedPixelFormat_Get(ctx, a, i, out y);
    o.Add(rc == 0 ? string.Format("    pixelformat  current={0} supported mask=0x{1:X}  (1=RGB full 2=YCbCr444 4=YCbCr422 8=RGB limited 16=YCbCr420)", x, rc2 == 0 ? y : 0) : "    pixelformat  not reported (rc=" + rc + ")");
    for (int c = 0; c < colourTypes.Length; c++) {
      rc = ADL2_Display_Color_Get(ctx, a, i, colourTypes[c], out x, out y, out z, out w, out v);
      o.Add(rc == 0 ? string.Format("    {0,-12} current={1} default={2} range {3}..{4} step {5}", colourNames[c], x, y, z, w, v) : string.Format("    {0,-12} not reported (rc={1})", colourNames[c], rc));
    }
    return o;
  }
  // returns "ABORT: ..." or "rc=N"
  public static string Set(int k, string what, int value, bool simulate) {
    var d = List[k]; int a = d.Adapter, i = d.Index, x, y, z, w, v, rc;
    int c = Array.IndexOf(colourNames, what);
    if (c >= 0) {
      rc = ADL2_Display_Color_Get(ctx, a, i, colourTypes[c], out x, out y, out z, out w, out v);
      if (rc != 0) return "ABORT: this display does not report " + what + " (rc=" + rc + "); nothing sent";
      if (value < z || value > w) return "ABORT: " + value + " is outside the range " + z + ".." + w + "; nothing sent";
      return simulate ? "SIMULATE: nothing sent" : "rc=" + ADL2_Display_Color_Set(ctx, a, i, colourTypes[c], value);
    }
    switch (what) {
      case "freesync":
        rc = ADL2_Display_FreeSyncState_Get(ctx, a, i, out x, out y, out z, out w);
        if (rc != 0) return "ABORT: this display does not report FreeSync (rc=" + rc + "); nothing sent";
        if (value != 0 && value != 1) return "ABORT: freesync takes 0 or 1; nothing sent";
        // AMD's sample turns it on with the display's maximum refresh rate and off with 0
        return simulate ? "SIMULATE: nothing sent" : "rc=" + ADL2_Display_FreeSyncState_Set(ctx, a, i, value, value == 1 ? w : 0);
      case "gpuscaling":
        rc = ADL2_DFP_GPUScalingEnable_Get(ctx, a, i, out x, out y, out z);
        if (rc != 0 || x == 0) return "ABORT: GPU scaling is not supported on this display; nothing sent";
        if (value != 0 && value != 1) return "ABORT: gpuscaling takes 0 or 1; nothing sent";
        return simulate ? "SIMULATE: nothing sent" : "rc=" + ADL2_DFP_GPUScalingEnable_Set(ctx, a, i, value);
      case "hdr":
        rc = ADL2_Display_HDRState_Get(ctx, a, d.Id, out x, out y);
        if (rc != 0 || x == 0) return "ABORT: HDR is not supported on this display; nothing sent";
        if (value != 0 && value != 1) return "ABORT: hdr takes 0 or 1; nothing sent";
        return simulate ? "SIMULATE: nothing sent" : "rc=" + ADL2_Display_HDRState_Set(ctx, a, d.Id, value);
      case "colordepth":
        rc = ADL2_Display_SupportedColorDepth_Get(ctx, a, i, out x);
        if (rc != 0 || (x & value) == 0 || (value & (value - 1)) != 0) return "ABORT: colour depth " + value + " is not one bit of the supported mask 0x" + x.ToString("X") + "; nothing sent";
        return simulate ? "SIMULATE: nothing sent" : "rc=" + ADL2_Display_ColorDepth_Set(ctx, a, i, value);
      case "pixelformat":
        rc = ADL2_Display_SupportedPixelFormat_Get(ctx, a, i, out x);
        if (rc != 0 || (x & value) == 0 || (value & (value - 1)) != 0) return "ABORT: pixel format " + value + " is not one bit of the supported mask 0x" + x.ToString("X") + "; nothing sent";
        return simulate ? "SIMULATE: nothing sent" : "rc=" + ADL2_Display_PixelFormat_Set(ctx, a, i, value);
    }
    return "ABORT: unknown setting";
  }
}
'@
$err = [AdlDisp]::Open(); if ($err -and -not $Raw) { throw $err }
try {
  if ($Raw) { [AdlDisp]::Raw; return }
  if (-not $Set) { for ($k = 0; $k -lt [AdlDisp]::List.Count; $k++) { [AdlDisp]::Show($k) }; return }
  if ($Display -lt 0 -or $Display -ge [AdlDisp]::List.Count) { throw "-Display must be 0..$([AdlDisp]::List.Count - 1) (see the plain listing)" }
  if ($Value -eq [int]::MinValue) { throw 'give -Value' }
  "set $Set = $Value on display $Display`: $([AdlDisp]::Set($Display, $Set, $Value, [bool]$Simulate))"
  [AdlDisp]::Show($Display)
} finally { [AdlDisp]::Close() }
