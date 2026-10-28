$ErrorActionPreference = 'Stop'
$pm = 'SENSOR_MAXTYPES,CLK_GFXCLK,CLK_MEMCLK,CLK_SOCCLK,CLK_UVDCLK1,CLK_UVDCLK2,CLK_VCECLK,CLK_VCNCLK,TEMPERATURE_EDGE,TEMPERATURE_MEM,TEMPERATURE_VRVDDC,TEMPERATURE_VRMVDD,TEMPERATURE_LIQUID,TEMPERATURE_PLX,FAN_RPM,FAN_PERCENTAGE,SOC_VOLTAGE,SOC_POWER,SOC_CURRENT,INFO_ACTIVITY_GFX,INFO_ACTIVITY_MEM,GFX_VOLTAGE,MEM_VOLTAGE,ASIC_POWER,TEMPERATURE_VRSOC,TEMPERATURE_VRMVDD0,TEMPERATURE_VRMVDD1,TEMPERATURE_HOTSPOT,TEMPERATURE_GFX,TEMPERATURE_SOC,GFX_POWER,GFX_CURRENT,TEMPERATURE_CPU,CPU_POWER,CLK_CPUCLK,THROTTLER_STATUS,CLK_VCN1CLK1,CLK_VCN1CLK2,SMART_POWERSHIFT_CPU,SMART_POWERSHIFT_DGPU,BUS_SPEED,BUS_LANES,TEMPERATURE_LIQUID0,TEMPERATURE_LIQUID1,CLK_FCLK,THROTTLER_STATUS_CPU,SSPAIRED_ASICPOWER,SSTOTAL_POWERLIMIT,SSAPU_POWERLIMIT,SSDGPU_POWERLIMIT,TEMPERATURE_HOTSPOT_GCD,TEMPERATURE_HOTSPOT_MCD,THROTTLE_PERCENTAGE_TEMP_GFX,THROTTLE_PERCENTAGE_TEMP_MEM,THROTTLE_PERCENTAGE_TEMP_VR,THROTTLE_PERCENTAGE_POWER,THROTTLE_PERCENTAGE_TDC,THROTTLE_PERCENTAGE_VMAX,BUS_CURR_MAX_SPEED,RESERVED_1,RESERVED_2,RESERVED_3,RESERVED_4,RESERVED_5,RESERVED_6,RESERVED_7,RESERVED_8,RESERVED_9,RESERVED_10,RESERVED_11,RESERVED_12,CLK_NPUCLK,NPU_BUSY_AVG,BOARD_POWER,TEMPERATURE_INTAKE' -split ','
$od = 'GFXCLK_FMAX,GFXCLK_FMIN,GFXCLK_FREQ1,GFXCLK_VOLTAGE1,GFXCLK_FREQ2,GFXCLK_VOLTAGE2,GFXCLK_FREQ3,GFXCLK_VOLTAGE3,UCLK_FMAX,POWER_PERCENTAGE,FAN_MIN_SPEED,FAN_ACOUSTIC_LIMIT,FAN_TARGET_TEMP,OPERATING_TEMP_MAX,AC_TIMING,FAN_ZERORPM_CONTROL,AUTO_UV_ENGINE_CONTROL,AUTO_OC_ENGINE_CONTROL,AUTO_OC_MEMORY_CONTROL,FAN_CURVE_TEMPERATURE_1,FAN_CURVE_SPEED_1,FAN_CURVE_TEMPERATURE_2,FAN_CURVE_SPEED_2,FAN_CURVE_TEMPERATURE_3,FAN_CURVE_SPEED_3,FAN_CURVE_TEMPERATURE_4,FAN_CURVE_SPEED_4,FAN_CURVE_TEMPERATURE_5,FAN_CURVE_SPEED_5,WS_FAN_AUTO_FAN_ACOUSTIC_LIMIT,GFXCLK_CURVE_COEFFICIENT_A,GFXCLK_CURVE_COEFFICIENT_B,GFXCLK_CURVE_COEFFICIENT_C,GFXCLK_CURVE_VFT_FMIN,UCLK_FMIN,FAN_ZERO_RPM_STOP_TEMPERATURE,OPTIMZED_POWER_MODE,OD_VOLTAGE,ADV_OC_LIMITS_SETTING,PER_ZONE_GFX_VOLTAGE_OFFSET_POINT_1,PER_ZONE_GFX_VOLTAGE_OFFSET_POINT_2,PER_ZONE_GFX_VOLTAGE_OFFSET_POINT_3,PER_ZONE_GFX_VOLTAGE_OFFSET_POINT_4,PER_ZONE_GFX_VOLTAGE_OFFSET_POINT_5,PER_ZONE_GFX_VOLTAGE_OFFSET_POINT_6,AUTO_CURVE_OPTIMIZER_SETTING,GFX_VOLTAGE_LIMIT_SETTING,TDC_PERCENTAGE,FULL_CONTROL_MODE_SETTING,FULL_CONTROL_MODE_GFXCLK,FULL_CONTROL_MODE_UCLK,IDLE_POWER_SAVING_FEATURE_CONTROL,RUNTIME_POWER_SAVING_FEATURE_CONTROL,FULL_CONTROL_MODE_FEATURE_CONTROL,PER_ZONE_GFX_VOLTAGE_OFFSET_FREQ_ANCHOR_1,PER_ZONE_GFX_VOLTAGE_OFFSET_FREQ_ANCHOR_2,PER_ZONE_GFX_VOLTAGE_OFFSET_FREQ_ANCHOR_3,PER_ZONE_GFX_VOLTAGE_OFFSET_FREQ_ANCHOR_4,PER_ZONE_GFX_VOLTAGE_OFFSET_FREQ_ANCHOR_5,PER_ZONE_GFX_VOLTAGE_OFFSET_FREQ_ANCHOR_6,PER_ZONE_GFX_VOLTAGE_OFFSET_VOLTAGE_LIMIT,ACTIMING_PARAMETER_TRRDS,ACTIMING_PARAMETER_TCL,ACTIMING_PARAMETER_TCWL,ACTIMING_PARAMETER_TRCDRD,ACTIMING_PARAMETER_TRCDWR,ACTIMING_PARAMETER_TRAS,ACTIMING_PARAMETER_TRPAB,ACTIMING_PARAMETER_TRFC,ACTIMING_PARAMETER_TRFCPB,ACTIMING_PARAMETER_TRREFD,ACTIMING_PARAMETER_TREF,ACTIMING_PARAMETER_TWR,ACTIMING_PARAMETER_TWTRS,OVERDRIVE_INTERFACE_ID,AUTO_UV_ENGINE_V2_ID,POWER_GAUGE' -split ','
Add-Type @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public static class Adl {
  public delegate IntPtr Malloc(int size);
  static IntPtr Alloc(int size) { return Marshal.AllocCoTaskMem(size); }
  static Malloc keep = Alloc;
  const string D = "atiadlxx.dll";
  [DllImport(D)] static extern int ADL2_Main_Control_Create(Malloc cb, int connectedOnly, out IntPtr ctx);
  [DllImport(D)] static extern int ADL2_Main_Control_Destroy(IntPtr ctx);
  [DllImport(D)] static extern int ADL2_Adapter_NumberOfAdapters_Get(IntPtr ctx, out int n);
  [DllImport(D)] static extern int ADL2_Adapter_AdapterInfo_Get(IntPtr ctx, IntPtr info, int size);
  [DllImport(D)] static extern int ADL2_Adapter_Active_Get(IntPtr ctx, int adapter, out int active);
  [DllImport(D)] static extern int ADL2_Overdrive_Caps(IntPtr ctx, int adapter, out int supported, out int enabled, out int version);
  [DllImport(D)] static extern int ADL2_New_QueryPMLogData_Get(IntPtr ctx, int adapter, IntPtr output);
  [DllImport(D)] static extern int ADL2_Overdrive8_Init_SettingX2_Get(IntPtr ctx, int adapter, out int caps, ref int count, out IntPtr list);
  [DllImport(D)] static extern int ADL2_Overdrive8_Current_SettingX2_Get(IntPtr ctx, int adapter, ref int count, out IntPtr list);
  const int Od8Count = 77;     // OD8_COUNT in adl_defines.h
  const int InfoSize = 1572;   // AdapterInfo: 2 ints, char[256], 4 ints, 2 x char[256], 2 ints, 3 x char[256], 1 int
  public static List<string> Run() {
    var o = new List<string>(); IntPtr ctx;
    int rc = ADL2_Main_Control_Create(keep, 1, out ctx);
    o.Add("create rc=" + rc); if (rc != 0) return o;
    try {
      int n; ADL2_Adapter_NumberOfAdapters_Get(ctx, out n); o.Add("adapters=" + n);
      IntPtr buf = Marshal.AllocCoTaskMem(InfoSize * n);
      for (int i = 0; i < InfoSize * n; i++) Marshal.WriteByte(buf, i, 0);
      ADL2_Adapter_AdapterInfo_Get(ctx, buf, InfoSize * n);
      var seen = new HashSet<int>();
      for (int i = 0; i < n; i++) {
        IntPtr p = IntPtr.Add(buf, i * InfoSize);
        int idx = Marshal.ReadInt32(p, 4); int bus = Marshal.ReadInt32(p, 264); int vendor = Marshal.ReadInt32(p, 276);
        string name = Marshal.PtrToStringAnsi(IntPtr.Add(p, 280)); int present = Marshal.ReadInt32(p, 792);
        int active; ADL2_Adapter_Active_Get(ctx, idx, out active);
        o.Add(string.Format("adapter {0}: bus={1} vendor={2} present={3} active={4} {5}", idx, bus, vendor, present, active, name));
        // one query per physical card (several adapter entries share a bus). 'active' is session-scoped: it reads 0
        // for every adapter from an SSH session, so it is reported but not used to skip.
        if (!seen.Add(bus)) continue;
        int sup, en, ver; rc = ADL2_Overdrive_Caps(ctx, idx, out sup, out en, out ver);
        o.Add(string.Format("  overdrive: rc={0} supported={1} enabled={2} version={3}", rc, sup, en, ver));
        IntPtr pm = Marshal.AllocCoTaskMem(4 + 256 * 8);
        for (int k = 0; k < 4 + 256 * 8; k++) Marshal.WriteByte(pm, k, 0);
        rc = ADL2_New_QueryPMLogData_Get(ctx, idx, pm);
        o.Add("  sensors: rc=" + rc);
        if (rc == 0) for (int s = 0; s < 256; s++) if (Marshal.ReadInt32(pm, 4 + s * 8) != 0) o.Add("S|" + s + "|" + Marshal.ReadInt32(pm, 8 + s * 8));
        Marshal.FreeCoTaskMem(pm);
        int caps, cnt = Od8Count; IntPtr list;  // the count is in/out: AMD's sample passes OD8_COUNT in
        rc = ADL2_Overdrive8_Init_SettingX2_Get(ctx, idx, out caps, ref cnt, out list);
        o.Add(string.Format("  overdrive8 init: rc={0} capabilities=0x{1:X} features={2}", rc, caps, cnt));
        int ccnt = Od8Count; IntPtr cur = IntPtr.Zero; int rc2 = ADL2_Overdrive8_Current_SettingX2_Get(ctx, idx, ref ccnt, out cur);
        o.Add(string.Format("  overdrive8 current: rc={0} features={1}", rc2, ccnt));
        if (rc == 0) for (int f = 0; f < cnt; f++) {
          int fid = Marshal.ReadInt32(list, f * 16), mn = Marshal.ReadInt32(list, f * 16 + 4), mx = Marshal.ReadInt32(list, f * 16 + 8), df = Marshal.ReadInt32(list, f * 16 + 12);
          string c = (rc2 == 0 && f < ccnt) ? Marshal.ReadInt32(cur, f * 4).ToString() : "?";
          o.Add("O|" + f + "|" + fid + "|" + mn + "|" + mx + "|" + df + "|" + c);
        }
      }
      Marshal.FreeCoTaskMem(buf);
    } finally { ADL2_Main_Control_Destroy(ctx); }
    return o;
  }
}
'@
foreach ($l in [Adl]::Run()) {
  if ($l -like 'S|*') { $p = $l -split '\|'; '    sensor {0,3} {1,-28} = {2}' -f $p[1], $pm[[int]$p[1]], $p[2] }
  elseif ($l -like 'O|*') { $p = $l -split '\|'; if ([int]$p[3] -ne 0 -or [int]$p[4] -ne 0 -or [int]$p[5] -ne 0 -or $p[6] -ne '0') { '    setting {0,2} {1,-44} min={2,-7} max={3,-7} default={4,-7} current={5}  (featureID 0x{6:X})' -f $p[1], $od[[int]$p[1]], $p[3], $p[4], $p[5], $p[6], [int]$p[2] } }
  else { $l }
}
