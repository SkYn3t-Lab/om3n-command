param([ValidateSet('', 'antilag', 'boost', 'sharpen', 'chill', 'framecap', 'led')][string]$Feature = '', [ValidateSet(-1, 0, 1)][int]$Enable = -1, [int]$Value = [int]::MinValue, [switch]$Simulate)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class AdlFeat {
  public delegate IntPtr Malloc(int size);
  static IntPtr Alloc(int size) { return Marshal.AllocCoTaskMem(size); }
  static Malloc keep = Alloc;
  const string D = "atiadlxx.dll";
  [DllImport(D)] static extern int ADL2_Main_Control_Create(Malloc cb, int connectedOnly, out IntPtr ctx);
  [DllImport(D)] static extern int ADL2_Main_Control_Destroy(IntPtr ctx);
  [DllImport(D)] static extern int ADL2_Adapter_NumberOfAdapters_Get(IntPtr ctx, out int n);
  [DllImport(D)] static extern int ADL2_Adapter_AdapterInfo_Get(IntPtr ctx, IntPtr info, int size);
  [DllImport(D)] static extern int ADL2_Overdrive_Caps(IntPtr ctx, int adapter, out int supported, out int enabled, out int version);
  [DllImport(D)] static extern int ADL2_DELAG_Settings_Get(IntPtr ctx, int adapter, [In, Out] int[] s);
  [DllImport(D)] static extern int ADL2_DELAG_Settings_Set(IntPtr ctx, int adapter, [In] int[] s, [In] int[] reason);
  [DllImport(D)] static extern int ADL2_BOOST_Settings_Get(IntPtr ctx, int adapter, [In, Out] int[] s);
  [DllImport(D)] static extern int ADL2_BOOST_Settings_Set(IntPtr ctx, int adapter, [In] int[] s, [In] int[] reason);
  [DllImport(D)] static extern int ADL2_RIS_Settings_Get(IntPtr ctx, int adapter, [In, Out] int[] s);
  [DllImport(D)] static extern int ADL2_RIS_Settings_Set(IntPtr ctx, int adapter, [In] int[] s, long reason);
  [DllImport(D)] static extern int ADL2_Chill_Caps_Get(IntPtr ctx, int adapter, out int supported, out int checkCaps);
  [DllImport(D)] static extern int ADL2_CHILL_SettingsX2_Get(IntPtr ctx, int adapter, [In, Out] int[] s);
  [DllImport(D)] static extern int ADL2_CHILL_SettingsX2_Set(IntPtr ctx, int adapter, [In] int[] s, [In] int[] reason);
  [DllImport(D)] static extern int ADL2_Adapter_Radeon_USB_LED_Support_Get(IntPtr ctx, int adapter, out byte supported);
  [DllImport(D)] static extern int ADL2_Adapter_Radeon_USB_LED_Supported_Controls_Get(IntPtr ctx, int adapter, out uint controls);
  [DllImport(D)] static extern int ADL2_FPS_Settings_Get(IntPtr ctx, int adapter, [In, Out] int[] s);   // ADLFPSSettingsOutput, 9 ints, size first
  [DllImport(D)] static extern int ADL2_FPS_Settings_Set(IntPtr ctx, int adapter, [In] int[] s);        // ADLFPSSettingsInput, 10 ints, size first
  [DllImport(D)] static extern int ADL2_FPS_Settings_Reset(IntPtr ctx, int adapter);
  static IntPtr ctx; static int adapter = -1;
  public static string Open() {
    int rc = ADL2_Main_Control_Create(keep, 1, out ctx); if (rc != 0) return "the driver interface did not open, rc=" + rc;
    int n; ADL2_Adapter_NumberOfAdapters_Get(ctx, out n);
    IntPtr buf = Marshal.AllocCoTaskMem(1572 * n); for (int i = 0; i < 1572 * n; i++) Marshal.WriteByte(buf, i, 0);
    ADL2_Adapter_AdapterInfo_Get(ctx, buf, 1572 * n);
    for (int i = 0; i < n && adapter < 0; i++) { int a = Marshal.ReadInt32(IntPtr.Add(buf, i * 1572), 4), s, e, v; if (ADL2_Overdrive_Caps(ctx, a, out s, out e, out v) == 0 && s == 1) adapter = a; }
    Marshal.FreeCoTaskMem(buf);
    return adapter < 0 ? "no Radeon answered (run this in the desktop session)" : "";
  }
  public static void Close() { if (ctx != IntPtr.Zero) ADL2_Main_Control_Destroy(ctx); }
  // name -> "rc|field values"
  public static string Get(string f) {
    int rc; int[] s;
    switch (f) {
      case "antilag": s = new int[6]; rc = ADL2_DELAG_Settings_Get(ctx, adapter, s); break;
      case "boost": s = new int[6]; rc = ADL2_BOOST_Settings_Get(ctx, adapter, s); break;
      case "sharpen": s = new int[5]; rc = ADL2_RIS_Settings_Get(ctx, adapter, s); break;
      case "chill": { int sup, caps; rc = ADL2_Chill_Caps_Get(ctx, adapter, out sup, out caps); var c = new int[7]; int rc2 = ADL2_CHILL_SettingsX2_Get(ctx, adapter, c); s = new int[] { sup, rc2, c[1], c[2], c[3], c[4], c[5], c[6] }; break; }
      case "framecap": s = new int[9]; s[0] = 36; rc = ADL2_FPS_Settings_Get(ctx, adapter, s); break;
      case "led": { byte b; uint c = 0; rc = ADL2_Adapter_Radeon_USB_LED_Support_Get(ctx, adapter, out b); int rc2 = b != 0 ? ADL2_Adapter_Radeon_USB_LED_Supported_Controls_Get(ctx, adapter, out c) : -1; s = new int[] { b, rc2, (int)c }; break; }
      default: return "?";
    }
    return rc + "|" + string.Join(",", Array.ConvertAll(s, x => x.ToString()));
  }
  // enable is 0 or 1; value is ignored when hasValue is false. Returns the driver's return code.
  // Each Set also takes AMD's "what changed" structure (ADL_*_NOTFICATION_REASON). On x64 a structure over 8 bytes
  // travels as a pointer, so the 12-byte ones are int arrays; the 8-byte sharpening one travels in a register.
  public static int Set(string f, int enable, bool hasValue, int value) {
    int[] s;
    switch (f) {
      case "antilag": s = new int[6]; ADL2_DELAG_Settings_Get(ctx, adapter, s); s[1] = enable; return ADL2_DELAG_Settings_Set(ctx, adapter, s, new int[] { 0, 1, 0 });
      case "boost": s = new int[6]; ADL2_BOOST_Settings_Get(ctx, adapter, s); s[1] = enable; if (hasValue) s[2] = value; return ADL2_BOOST_Settings_Set(ctx, adapter, s, new int[] { 0, 1, hasValue ? 1 : 0 });
      case "sharpen": s = new int[5]; ADL2_RIS_Settings_Get(ctx, adapter, s); bool e = s[0] != enable, d = hasValue && s[1] != value; s[0] = enable; if (hasValue) s[1] = value;
        return ADL2_RIS_Settings_Set(ctx, adapter, s, (e ? 1L : 0L) | ((d ? 1L : 0L) << 32));
      case "chill": s = new int[7]; ADL2_CHILL_SettingsX2_Get(ctx, adapter, s); s[1] = enable; return ADL2_CHILL_SettingsX2_Set(ctx, adapter, s, new int[] { 0, 1, 0, 0 });
      case "framecap": if (enable == 0) return ADL2_FPS_Settings_Reset(ctx, adapter); if (!hasValue) return -9998;
        return ADL2_FPS_Settings_Set(ctx, adapter, new int[] { 40, 1, value, value, 0, 0, 0, 0, 0, 0 });
    }
    return -9999;
  }
}
'@
$err = [AdlFeat]::Open(); if ($err) { throw $err }
function Show-Feature([string]$f) {
  $rc, $v = [AdlFeat]::Get($f) -split '\|'; $s = @($v -split ',' | ForEach-Object { [int]$_ })
  switch ($f) {
    'antilag' { 'Anti-Lag           rc={0}  on={1}  fps limit={2} (range {3}..{4} step {5})  hotkey={6}' -f $rc, $s[1], $s[2], $s[3], $s[4], $s[5], $s[0] }
    'boost' { 'Radeon Boost       rc={0}  on={1}  minimum resolution={2} % (range {3}..{4} step {5})  hotkey={6}' -f $rc, $s[1], $s[2], $s[3], $s[4], $s[5], $s[0] }
    'sharpen' { 'Image Sharpening   rc={0}  on={1}  sharpness={2} % (range {3}..{4} step {5})' -f $rc, $s[0], $s[1], $s[2], $s[3], $s[4] }
    'chill' { 'Radeon Chill       rc={0}  supported={1}  on={2}  fps min={3} max={4} (range {5}..{6} step {7})  (get rc={8})' -f $rc, $s[0], $s[2], $s[3], $s[4], $s[5], $s[6], $s[7], $s[1] }
    'framecap' { 'Frame rate target  rc={0}  on={1}  fps={2} (range {3}..{4})' -f $rc, $s[1], $s[3], $s[6], $s[5] }
    'led' { 'LED bar on the card rc={0}  supported={1}  controls=0x{2:X} (get rc={3})' -f $rc, $s[0], $s[2], $s[1] }
  }
}
try {
  if (-not $Feature) { 'antilag', 'boost', 'sharpen', 'chill', 'framecap', 'led' | ForEach-Object { Show-Feature $_ }; return }
  "before: $(Show-Feature $Feature)"
  if ($Enable -lt 0) { return }
  if ($Feature -eq 'led') { throw 'the LED bar is not supported on this card (see the status line); nothing to set' }
  $has = $Value -ne [int]::MinValue
  if ($Feature -eq 'framecap' -and $Enable -eq 1 -and -not $has) { throw 'the frame-rate target needs -Value <fps> to turn on' }
  if ($has) {
    $rc, $v = [AdlFeat]::Get($Feature) -split '\|'; $s = @($v -split ',' | ForEach-Object { [int]$_ })
    $lo, $hi = if ($Feature -eq 'sharpen') { $s[2], $s[3] } elseif ($Feature -eq 'boost') { $s[3], $s[4] } elseif ($Feature -eq 'framecap') { $s[6], $s[5] } else { throw "-Value does not apply to $Feature" }
    if ($Value -lt $lo -or $Value -gt $hi) { throw "$Value is outside the driver's range $lo..$hi; nothing sent" }
  }
  if ($Simulate) { "SIMULATE: would set $Feature on=$Enable$(if ($has) { " value=$Value" }); nothing sent"; return }
  "set: rc=$([AdlFeat]::Set($Feature, $Enable, $has, $(if ($has) { $Value } else { 0 })))  (0 = accepted)"
  "after:  $(Show-Feature $Feature)"
} finally { [AdlFeat]::Close() }
