param(
  [ValidateSet('GFXCLK_FMAX', 'GFXCLK_FMIN', 'UCLK_FMAX', 'POWER_PERCENTAGE', 'FAN_ZERORPM_CONTROL', 'OD_VOLTAGE', 'TDC_PERCENTAGE',
    'FAN_CURVE_TEMPERATURE_1', 'FAN_CURVE_SPEED_1', 'FAN_CURVE_TEMPERATURE_2', 'FAN_CURVE_SPEED_2', 'FAN_CURVE_TEMPERATURE_3', 'FAN_CURVE_SPEED_3',
    'FAN_CURVE_TEMPERATURE_4', 'FAN_CURVE_SPEED_4', 'FAN_CURVE_TEMPERATURE_5', 'FAN_CURVE_SPEED_5')][string]$Setting,
  [int]$Value = 0, [switch]$Reset, [switch]$Simulate, [string]$FanCurve = ''
)
$ErrorActionPreference = 'Stop'
$ids = @{ GFXCLK_FMAX = 0; GFXCLK_FMIN = 1; UCLK_FMAX = 8; POWER_PERCENTAGE = 9; FAN_ZERORPM_CONTROL = 15; OD_VOLTAGE = 37; TDC_PERCENTAGE = 47
  FAN_CURVE_TEMPERATURE_1 = 19; FAN_CURVE_SPEED_1 = 20; FAN_CURVE_TEMPERATURE_2 = 21; FAN_CURVE_SPEED_2 = 22; FAN_CURVE_TEMPERATURE_3 = 23
  FAN_CURVE_SPEED_3 = 24; FAN_CURVE_TEMPERATURE_4 = 25; FAN_CURVE_SPEED_4 = 26; FAN_CURVE_TEMPERATURE_5 = 27; FAN_CURVE_SPEED_5 = 28 }
if ($FanCurve -eq 'reset') { $curve = @(0) * 10 }
elseif ($FanCurve) {
  $curve = @($FanCurve -split ',' | ForEach-Object { [int]$_.Trim() })
  if ($curve.Count -ne 10) { throw '-FanCurve takes ten numbers: temperature,speed for each of the five points' }
} elseif (-not $Setting) { throw 'give -Setting <name> with -Value <number> or -Reset, or -FanCurve' }
elseif (-not $Reset -and -not $PSBoundParameters.ContainsKey('Value')) { throw 'give -Value <number> or -Reset' }
Add-Type @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class AdlSet {
  public delegate IntPtr Malloc(int size);
  static IntPtr Alloc(int size) { return Marshal.AllocCoTaskMem(size); }
  static Malloc keep = Alloc;
  const string D = "atiadlxx.dll";
  [DllImport(D)] static extern int ADL2_Main_Control_Create(Malloc cb, int connectedOnly, out IntPtr ctx);
  [DllImport(D)] static extern int ADL2_Main_Control_Destroy(IntPtr ctx);
  [DllImport(D)] static extern int ADL2_Adapter_NumberOfAdapters_Get(IntPtr ctx, out int n);
  [DllImport(D)] static extern int ADL2_Adapter_AdapterInfo_Get(IntPtr ctx, IntPtr info, int size);
  [DllImport(D)] static extern int ADL2_Overdrive8_Init_SettingX2_Get(IntPtr ctx, int adapter, out int caps, ref int count, out IntPtr list);
  [DllImport(D)] static extern int ADL2_Overdrive8_Current_SettingX2_Get(IntPtr ctx, int adapter, ref int count, out IntPtr list);
  [DllImport(D)] static extern int ADL2_Overdrive8_Setting_Set(IntPtr ctx, int adapter, IntPtr setSetting, IntPtr currentSetting);
  const int N = 77;            // OD8_COUNT
  const int InfoSize = 1572;   // AdapterInfo
  const int Mode = 36;         // OD8_OPTIMZED_POWER_MODE; 3 = manual
  static int[] Current(IntPtr ctx, int idx) {
    int cnt = N; IntPtr cur; int rc = ADL2_Overdrive8_Current_SettingX2_Get(ctx, idx, ref cnt, out cur);
    if (rc != 0) throw new Exception("reading the current settings failed, rc=" + rc);
    var a = new int[N]; for (int f = 0; f < cnt && f < N; f++) a[f] = Marshal.ReadInt32(cur, f * 4);
    return a;
  }
  // one ADL2_Overdrive8_Setting_Set call: 'req' maps setting index -> value; 'resets' are the settings sent with the reset flag
  static int Send(IntPtr ctx, int idx, Dictionary<int, int> req, ICollection<int> resets) {
    int setSize = 4 + N * 12, curSize = 4 + N * 4;
    IntPtr s = Marshal.AllocCoTaskMem(setSize), c = Marshal.AllocCoTaskMem(curSize);
    try {
      for (int i = 0; i < setSize; i++) Marshal.WriteByte(s, i, 0);
      for (int i = 0; i < curSize; i++) Marshal.WriteByte(c, i, 0);
      Marshal.WriteInt32(s, 0, N); Marshal.WriteInt32(c, 0, N);
      foreach (var kv in req) {
        Marshal.WriteInt32(s, 4 + kv.Key * 12, kv.Value);                       // value
        Marshal.WriteInt32(s, 4 + kv.Key * 12 + 4, 1);                          // requested
        Marshal.WriteInt32(s, 4 + kv.Key * 12 + 8, resets.Contains(kv.Key) ? 1 : 0);  // reset
      }
      return ADL2_Overdrive8_Setting_Set(ctx, idx, s, c);
    } finally { Marshal.FreeCoTaskMem(s); Marshal.FreeCoTaskMem(c); }
  }
  public static List<string> Run(int id, int value, bool reset, bool simulate) { return Run(new[] { id }, new[] { value }, reset, simulate); }
  public static List<string> Run(int[] ids, int[] values, bool reset, bool simulate) {
    int id = ids[0];
    var o = new List<string>(); IntPtr ctx;
    int rc = ADL2_Main_Control_Create(keep, 1, out ctx);
    if (rc != 0) { o.Add("FAILED: the driver interface did not open, rc=" + rc); return o; }
    try {
      int n; ADL2_Adapter_NumberOfAdapters_Get(ctx, out n);
      IntPtr buf = Marshal.AllocCoTaskMem(InfoSize * n);
      for (int i = 0; i < InfoSize * n; i++) Marshal.WriteByte(buf, i, 0);
      ADL2_Adapter_AdapterInfo_Get(ctx, buf, InfoSize * n);
      int idx = -1, caps = 0; IntPtr list = IntPtr.Zero;
      for (int i = 0; i < n && idx < 0; i++) {
        int a = Marshal.ReadInt32(IntPtr.Add(buf, i * InfoSize), 4); int cnt = N;
        if (ADL2_Overdrive8_Init_SettingX2_Get(ctx, a, out caps, ref cnt, out list) == 0) idx = a;
      }
      Marshal.FreeCoTaskMem(buf);
      if (idx < 0) { o.Add("FAILED: no adapter answered the tuning query (run this in the desktop session)"); return o; }
      int[] before = Current(ctx, idx);
      var req = new Dictionary<int, int>();
      for (int k = 0; k < ids.Length; k++) {
        int sid = ids[k];
        int mn = Marshal.ReadInt32(list, sid * 16 + 4), mx = Marshal.ReadInt32(list, sid * 16 + 8), df = Marshal.ReadInt32(list, sid * 16 + 12);
        int want = reset ? df : values[k];
        o.Add(string.Format("adapter {0}, setting {1}: range {2}..{3}, default {4}, current {5}, asked {6}{7}", idx, sid, mn, mx, df, before[sid], want, reset ? " (reset)" : ""));
        if (mn == 0 && mx == 0 && df == 0) { o.Add("ABORT: the driver reports no range for setting " + sid + " on this card; nothing sent"); return o; }
        if (want < mn || want > mx) { o.Add("ABORT: " + want + " is outside the driver's range for setting " + sid + "; nothing sent"); return o; }
        req[sid] = want;
      }
      // settings that travel as a group are sent together; members not asked for keep their current value
      var group = new List<int>();
      if (id <= 1) group.AddRange(new[] { 0, 1 });                                       // GPU clock limits
      else if (id >= 19 && id <= 28) for (int i = 19; i <= 28; i++) group.Add(i);       // fan curve
      else if (id == 8) group.AddRange(new[] { 8, 34 });                                 // memory clock limits
      foreach (int g in group) if (!req.ContainsKey(g)) req[g] = before[g];
      bool needManual = (caps & (1 << 16)) != 0 && before[Mode] != 3;
      if (needManual) o.Add("tuning mode is " + before[Mode] + ", not manual (3): it would be set to 3 first");
      var parts = new List<string>(); foreach (var kv in req) parts.Add(kv.Key + "=" + kv.Value);
      o.Add("sending: " + string.Join(" ", parts.ToArray()));
      if (simulate) { o.Add("SIMULATE: nothing sent"); return o; }
      if (needManual) {
        var m = new Dictionary<int, int>(); m[Mode] = 3; rc = Send(ctx, idx, m, new int[0]);
        o.Add("set manual tuning mode: rc=" + rc); if (rc != 0) { o.Add("ABORT: could not enter manual mode; the setting was not sent"); return o; }
      }
      rc = Send(ctx, idx, req, reset ? (ICollection<int>)ids : new int[0]);
      o.Add("ADL2_Overdrive8_Setting_Set: rc=" + rc + (rc == 0 ? " (accepted)" : " (REFUSED)"));
      int[] after = Current(ctx, idx); int changed = 0;
      for (int i = 0; i < N; i++) if (after[i] != before[i]) { changed++; o.Add(string.Format("CHANGED setting {0}: {1} -> {2}", i, before[i], after[i])); }
      o.Add("settings changed by this run = " + changed + "; setting " + id + " now reads " + after[id]);
    } catch (Exception e) { o.Add("FAILED: " + e.Message); }
    finally { ADL2_Main_Control_Destroy(ctx); }
    return o;
  }
}
'@
if ($FanCurve) {
  "radeon-set: fan curve $FanCurve"
  [AdlSet]::Run([int[]](19..28), [int[]]$curve, ($FanCurve -eq 'reset'), [bool]$Simulate)
} else {
  "radeon-set: $Setting"
  [AdlSet]::Run($ids[$Setting], $Value, [bool]$Reset, [bool]$Simulate)
}
