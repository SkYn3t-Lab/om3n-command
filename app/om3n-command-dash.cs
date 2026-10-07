using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

public static class Dash {
  public const int Keep = 180;           // history points per reading (180 x 1 s = 3 minutes)
  public static long Samples;            // how many readings have been taken: the recorder writes one line for each
  public static string Problems = "";    // a reading that could not be set up, with the reason
  static readonly object gate = new object();
  static Dictionary<string, double> now = new Dictionary<string, double>();
  static Dictionary<string, Queue<double>> hist = new Dictionary<string, Queue<double>>();
  static Thread worker;
  public static double TotalMemMB = 0;

  public static void Start(int periodMs) {
    if (worker != null) return;
    worker = new Thread(() => { try { Init(); } catch (Exception e) { Problems += "init: " + e.Message + "\n"; } while (true) { try { Sample(); } catch (Exception e) { Problems += "sample: " + e.Message + "\n"; } Thread.Sleep(periodMs); } });
    worker.IsBackground = true; worker.Start();
    var slowWorker = new Thread(Slow); slowWorker.IsBackground = true; slowWorker.Start();
  }
  static double driveTemp = double.NaN;
  static void Slow() {
    bool told = false;
    while (true) {
      try {
        double t = double.NaN;
        using (var s = new System.Management.ManagementObjectSearcher(@"root\Microsoft\Windows\Storage", "SELECT * FROM MSFT_PhysicalDisk"))
          foreach (System.Management.ManagementObject disk in s.Get())
            foreach (System.Management.ManagementBaseObject o in disk.GetRelated("MSFT_StorageReliabilityCounter")) {
              object v = o["Temperature"];
              if (v != null && Convert.ToDouble(v) > 0) t = double.IsNaN(t) ? Convert.ToDouble(v) : Math.Max(t, Convert.ToDouble(v));
            }
        driveTemp = t;
      } catch (Exception e) { if (!told) { Problems += "drive temperature: " + e.Message + "\n"; told = true; } }
      Thread.Sleep(30000);
    }
  }
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  public static string Foreground() {
    try { uint pid; GetWindowThreadProcessId(GetForegroundWindow(), out pid); return pid == 0 ? "" : Process.GetProcessById((int)pid).ProcessName; }
    catch { return ""; }
  }
  public static void LogCrashesTo(string path) {
    AppDomain.CurrentDomain.UnhandledException += (s, e) => {
      try {
        using (var fs = new System.IO.FileStream(path, System.IO.FileMode.Append, System.IO.FileAccess.Write, System.IO.FileShare.ReadWrite, 4096, System.IO.FileOptions.WriteThrough)) {
          var b = System.Text.Encoding.UTF8.GetBytes(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " APP CRASH (unhandled error, the app is closing): " + e.ExceptionObject + "\r\n");
          fs.Write(b, 0, b.Length); fs.Flush(true);
        }
      } catch { }
    };
  }
  public static Dictionary<string, double> Snapshot() { lock (gate) return new Dictionary<string, double>(now); }
  public static double[] History(string key) { lock (gate) { Queue<double> q; return hist.TryGetValue(key, out q) ? q.ToArray() : new double[0]; } }

  static PerformanceCounter cpuTemp, util, perf, freq, pkg, pp0, dram, avail, diskR, diskW, uptime;
  public static volatile bool Detail = false;
  static bool detailReady = false; static PerformanceCounter boardTemp;
  static List<PerformanceCounter> thrUtil = new List<PerformanceCounter>(), thrFreq = new List<PerformanceCounter>();
  static void InitDetail() {
    detailReady = true;
    var threads = new List<string>();
    foreach (var i in Instances("Processor Information")) { var p = i.Split(','); int a, b; if (p.Length == 2 && int.TryParse(p[0], out a) && int.TryParse(p[1], out b)) threads.Add(i); }
    threads.Sort((x, y) => int.Parse(x.Split(',')[1]).CompareTo(int.Parse(y.Split(',')[1])));
    foreach (var t in threads) { thrUtil.Add(Pc("Processor Information", "% Processor Utility", t)); thrFreq.Add(Pc("Processor Information", "Actual Frequency", t)); }
    foreach (var z in Instances("Thermal Zone Information")) if (z.IndexOf("hptz", StringComparison.OrdinalIgnoreCase) < 0) { boardTemp = Pc("Thermal Zone Information", "Temperature", z); break; }
  }
  static List<PerformanceCounter> netIn = new List<PerformanceCounter>(), netOut = new List<PerformanceCounter>(), vram = new List<PerformanceCounter>();
  static PerformanceCounter Pc(string cat, string counter, string inst) {
    if (inst == null) { Problems += cat + "\\" + counter + ": no matching instance\n"; return null; }
    try { var c = new PerformanceCounter(cat, counter, inst, true); c.NextValue(); return c; }
    catch (Exception e) { Problems += cat + "\\" + counter + ": " + e.Message + "\n"; return null; }
  }
  static string[] Instances(string cat) {
    try { return new PerformanceCounterCategory(cat).GetInstanceNames(); }
    catch (Exception e) { Problems += cat + ": " + e.Message + "\n"; return new string[0]; }
  }
  static string Find(string cat, string part) {
    foreach (var i in Instances(cat)) if (i.ToLowerInvariant().Contains(part)) return i;
    return null;
  }
  static void AddAll(List<PerformanceCounter> list, string cat, string counter) {
    foreach (var i in Instances(cat)) { var c = Pc(cat, counter, i); if (c != null) list.Add(c); }
  }

  public delegate IntPtr Malloc(int size);
  static IntPtr Alloc(int size) { return Marshal.AllocCoTaskMem(size); }
  static Malloc keep = Alloc;        // held so the collector never frees the callback ADL keeps
  const string D = "atiadlxx.dll";
  [DllImport(D)] static extern int ADL2_Main_Control_Create(Malloc cb, int connectedOnly, out IntPtr ctx);
  [DllImport(D)] static extern int ADL2_Main_Control_Destroy(IntPtr ctx);
  [DllImport(D)] static extern int ADL2_Adapter_NumberOfAdapters_Get(IntPtr ctx, out int n);
  [DllImport(D)] static extern int ADL2_Adapter_AdapterInfo_Get(IntPtr ctx, IntPtr info, int size);
  [DllImport(D)] static extern int ADL2_New_QueryPMLogData_Get(IntPtr ctx, int adapter, IntPtr output);
  const int InfoSize = 1572;         // AdapterInfo, as in radeon-read.ps1
  const int PmSize = 4 + 256 * 8;    // ADLPMLogDataOutput: int size, then 256 x {supported, value}
  static IntPtr adl = IntPtr.Zero, pm = IntPtr.Zero; static int gpu = -1;
  const int GpuMissLimit = 7; static int gpuMiss = 0;
  public static int GpuReopens = 0; public static volatile bool ReopenNow = false;
  static void ReopenAdl() {
    GpuReopens++; gpuMiss = 0; ReopenNow = false;
    string told = Problems;          // a card that stays away is reported once, at the start, not at every retry
    try { if (adl != IntPtr.Zero) ADL2_Main_Control_Destroy(adl); } catch { }
    if (pm != IntPtr.Zero) Marshal.FreeCoTaskMem(pm);
    adl = IntPtr.Zero; pm = IntPtr.Zero; gpu = -1;
    InitAdl(); Problems = told;
  }
  static readonly Dictionary<int, string> sensors = new Dictionary<int, string> {
    {1, "gpuMHz"}, {2, "gpuMemMHz"}, {8, "gpuTemp"}, {9, "gpuMemTemp"}, {14, "gpuFanRpm"}, {15, "gpuFanPct"},
    {19, "gpuLoad"}, {20, "gpuMemLoad"}, {21, "gpuMv"}, {27, "gpuHot"}, {73, "gpuW"}, {74, "gpuIntake"}
  };
  static bool QueryPm(int adapter) {
    for (int k = 0; k < PmSize; k++) Marshal.WriteByte(pm, k, 0);   // zeroed, exactly as radeon-read.ps1 calls it
    return ADL2_New_QueryPMLogData_Get(adl, adapter, pm) == 0;
  }
  static void InitAdl() {
    try {
      if (ADL2_Main_Control_Create(keep, 1, out adl) != 0) { Problems += "ADL: driver interface did not start\n"; return; }
      int n; ADL2_Adapter_NumberOfAdapters_Get(adl, out n);
      IntPtr buf = Marshal.AllocCoTaskMem(InfoSize * n);
      for (int i = 0; i < InfoSize * n; i++) Marshal.WriteByte(buf, i, 0);
      ADL2_Adapter_AdapterInfo_Get(adl, buf, InfoSize * n);
      pm = Marshal.AllocCoTaskMem(PmSize);
      for (int i = 0; i < n && gpu < 0; i++) {
        int idx = Marshal.ReadInt32(IntPtr.Add(buf, i * InfoSize), 4);
        if (QueryPm(idx) && Marshal.ReadInt32(pm, 4 + 8 * 8) != 0) gpu = idx;
      }
      Marshal.FreeCoTaskMem(buf);
      if (gpu < 0) Problems += "ADL: no adapter answered with sensors\n";
    } catch (Exception e) { Problems += "ADL: " + e.Message + "\n"; }
  }

  static void Init() {
    cpuTemp = Pc("Thermal Zone Information", "Temperature", Find("Thermal Zone Information", "hptz"));
    util = Pc("Processor Information", "% Processor Utility", "_Total");
    perf = Pc("Processor Information", "% Processor Performance", "_Total");
    freq = Pc("Processor Information", "Processor Frequency", "_Total");
    pkg = Pc("Energy Meter", "Power", Find("Energy Meter", "_pkg"));
    pp0 = Pc("Energy Meter", "Power", Find("Energy Meter", "_pp0"));
    dram = Pc("Energy Meter", "Power", Find("Energy Meter", "_dram"));
    avail = Pc("Memory", "Available MBytes", "");
    diskR = Pc("PhysicalDisk", "Disk Read Bytes/sec", "_Total");
    diskW = Pc("PhysicalDisk", "Disk Write Bytes/sec", "_Total");
    uptime = Pc("System", "System Up Time", "");
    AddAll(netIn, "Network Interface", "Bytes Received/sec");
    AddAll(netOut, "Network Interface", "Bytes Sent/sec");
    AddAll(vram, "GPU Adapter Memory", "Dedicated Usage");
    InitAdl();
  }

  static double V(PerformanceCounter c) { return c == null ? double.NaN : c.NextValue(); }
  static void Put(Dictionary<string, double> d, string k, double v) { if (!double.IsNaN(v) && !double.IsInfinity(v)) d[k] = v; }
  static double Sum(List<PerformanceCounter> l) { double s = 0; foreach (var c in l) { try { s += c.NextValue(); } catch { } } return s; }
  static double Max(List<PerformanceCounter> l) { double m = 0; foreach (var c in l) { try { m = Math.Max(m, c.NextValue()); } catch { } } return m; }

  static void Sample() {
    var d = new Dictionary<string, double>();
    Put(d, "cpuTemp", V(cpuTemp) - 273.15);
    Put(d, "cpuLoad", Math.Min(100, V(util)));
    Put(d, "cpuMHz", V(freq) * V(perf) / 100);
    Put(d, "cpuW", V(pkg) / 1000); Put(d, "coresW", V(pp0) / 1000); Put(d, "dramW", V(dram) / 1000);
    if (TotalMemMB > 0) { Put(d, "memUsedGB", (TotalMemMB - V(avail)) / 1024); Put(d, "memPct", 100 * (TotalMemMB - V(avail)) / TotalMemMB); }
    double dr = V(diskR) / 1048576, dw = V(diskW) / 1048576;
    Put(d, "diskReadMB", dr); Put(d, "diskWriteMB", dw); Put(d, "diskMB", dr + dw);
    Put(d, "netInMbit", Sum(netIn) * 8 / 1e6); Put(d, "netOutMbit", Sum(netOut) * 8 / 1e6);
    if (vram.Count > 0) Put(d, "vramGB", Max(vram) / 1073741824);
    Put(d, "uptimeS", V(uptime));
    Put(d, "driveTemp", driveTemp);
    bool card = false;
    if (gpu >= 0 && QueryPm(gpu))
      foreach (var s in sensors) if (Marshal.ReadInt32(pm, 4 + s.Key * 8) != 0) { d[s.Value] = Marshal.ReadInt32(pm, 8 + s.Key * 8); card = true; }
    if (Detail) {
      if (!detailReady) InitDetail();
      for (int i = 0; i < thrUtil.Count; i++) { Put(d, "thr" + i + "Load", Math.Min(100, V(thrUtil[i]))); Put(d, "thr" + i + "MHz", V(thrFreq[i])); }
      Put(d, "boardTemp", V(boardTemp) - 273.15);
      if (card) for (int id = 1; id < 256; id++) if (!sensors.ContainsKey(id) && (id < 52 || id > 57) && Marshal.ReadInt32(pm, 4 + id * 8) != 0) d["adl" + id] = Marshal.ReadInt32(pm, 8 + id * 8);
    }
    if (card) gpuMiss = 0; else gpuMiss++;
    if (ReopenNow || gpuMiss >= GpuMissLimit) ReopenAdl();
    lock (gate) {
      now = d; Samples++;
      foreach (var kv in d) {
        Queue<double> q;
        if (!hist.TryGetValue(kv.Key, out q)) { q = new Queue<double>(); hist[kv.Key] = q; }
        q.Enqueue(kv.Value); while (q.Count > Keep) q.Dequeue();
      }
    }
  }
}
