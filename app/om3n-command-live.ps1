Add-Type @'
using System; using System.Runtime.InteropServices;
public static class Om3nLive {
  [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator { }
  [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDeviceEnumerator { int EnumAudioEndpoints(int flow, int mask, out IntPtr devices); int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice device); }
  [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IMMDevice { int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object o); }
  [Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioMeterInformation { int GetPeakValue(out float peak); }
  static IAudioMeterInformation meter;
  public static int AudioLevel() {
    if (meter == null) {
      var e = (IMMDeviceEnumerator)new MMDeviceEnumerator(); IMMDevice d;
      int hr = e.GetDefaultAudioEndpoint(0, 1, out d);   // render, multimedia
      if (hr != 0) throw new Exception("no default playback device (0x" + hr.ToString("X") + ")");
      Guid iid = typeof(IAudioMeterInformation).GUID; object o; hr = d.Activate(ref iid, 23, IntPtr.Zero, out o);
      if (hr != 0) throw new Exception("the playback device has no level meter (0x" + hr.ToString("X") + ")");
      meter = (IAudioMeterInformation)o;
    }
    float p; meter.GetPeakValue(out p); return (int)(p * 100);
  }
  // Bass and treble: capture what is playing (WASAPI loopback on the default output), split it with two one-pole
  // filters (below about 200 Hz, above about 2 kHz) and report each band's loudness as 0-100. The scale is this
  // tool's own; Gaming Hub's analysis and scale are not reproduced.
  [Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioClient {
    int Initialize(int shareMode, int flags, long bufferDuration, long periodicity, IntPtr format, IntPtr sessionGuid);
    int GetBufferSize(out uint frames); int GetStreamLatency(out long latency); int GetCurrentPadding(out uint frames);
    int IsFormatSupported(int shareMode, IntPtr format, out IntPtr closest); int GetMixFormat(out IntPtr format);
    int GetDevicePeriod(out long def, out long min); int Start(); int Stop(); int Reset(); int SetEventHandle(IntPtr h);
    int GetService(ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object service);
  }
  [Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAudioCaptureClient {
    int GetBuffer(out IntPtr data, out uint frames, out uint flags, out ulong devicePosition, out ulong qpcPosition);
    int ReleaseBuffer(uint frames); int GetNextPacketSize(out uint frames);
  }
  static IAudioClient client; static IAudioCaptureClient capture; static int channels, rate; static double lp, hpPrevIn, hpPrevOut;
  public static int[] AudioBands() {
    if (capture == null) {
      var e = (IMMDeviceEnumerator)new MMDeviceEnumerator(); IMMDevice d;
      if (e.GetDefaultAudioEndpoint(0, 1, out d) != 0) throw new Exception("no default playback device");
      Guid iid = typeof(IAudioClient).GUID; object o; if (d.Activate(ref iid, 23, IntPtr.Zero, out o) != 0) throw new Exception("the playback device gave no audio client");
      client = (IAudioClient)o; IntPtr fmt; client.GetMixFormat(out fmt);
      channels = Marshal.ReadInt16(fmt, 2); rate = Marshal.ReadInt32(fmt, 4);
      if (Marshal.ReadInt16(fmt, 14) != 32) throw new Exception("the playback format is not 32-bit float; bass and treble need that");
      int hr = client.Initialize(0, 0x00020000, 10000000, 0, fmt, IntPtr.Zero);    // shared mode, loopback, 1 s buffer
      if (hr != 0) throw new Exception("loopback capture did not start (0x" + hr.ToString("X") + ")");
      Guid cid = typeof(IAudioCaptureClient).GUID; object c; client.GetService(ref cid, out c); capture = (IAudioCaptureClient)c;
      client.Start();
    }
    double a = Math.Exp(-2 * Math.PI * 200.0 / rate), b = Math.Exp(-2 * Math.PI * 2000.0 / rate), low = 0, high = 0; long n = 0;
    uint next; capture.GetNextPacketSize(out next);
    while (next > 0) {
      IntPtr data; uint frames, flags; ulong p1, p2; if (capture.GetBuffer(out data, out frames, out flags, out p1, out p2) != 0) break;
      if ((flags & 2) == 0) {                                   // 2 = the packet is silence
        var buf = new float[frames * channels]; Marshal.Copy(data, buf, 0, buf.Length);
        for (int i = 0; i < frames; i++) {
          double x = 0; for (int ch = 0; ch < channels; ch++) x += buf[i * channels + ch]; x /= channels;
          lp = (1 - a) * x + a * lp;                             // low band
          double hp = b * (hpPrevOut + x - hpPrevIn); hpPrevIn = x; hpPrevOut = hp;   // high band
          low += lp * lp; high += hp * hp; n++;
        }
      }
      capture.ReleaseBuffer(frames); capture.GetNextPacketSize(out next);
    }
    if (n == 0) return new int[] { 0, 0 };
    return new int[] { (int)Math.Min(100, Math.Sqrt(low / n) * 400), (int)Math.Min(100, Math.Sqrt(high / n) * 400) };
  }
  public delegate IntPtr Malloc(int size);
  static IntPtr Alloc(int size) { return Marshal.AllocCoTaskMem(size); }
  static Malloc keep = Alloc;
  const string D = "atiadlxx.dll";
  [DllImport(D)] static extern int ADL2_Main_Control_Create(Malloc cb, int connectedOnly, out IntPtr ctx);
  [DllImport(D)] static extern int ADL2_Adapter_NumberOfAdapters_Get(IntPtr ctx, out int n);
  [DllImport(D)] static extern int ADL2_Adapter_AdapterInfo_Get(IntPtr ctx, IntPtr info, int size);
  [DllImport(D)] static extern int ADL2_New_QueryPMLogData_Get(IntPtr ctx, int adapter, IntPtr output);
  static IntPtr ctx = IntPtr.Zero; static int adapter = -1;
  // sensor 8 is TEMPERATURE_EDGE in AMD's sensor list
  public static int GpuTemp() {
    IntPtr pm = Marshal.AllocCoTaskMem(4 + 256 * 8);
    try {
      if (ctx == IntPtr.Zero) {
        if (ADL2_Main_Control_Create(keep, 1, out ctx) != 0) throw new Exception("the Radeon driver interface did not open");
        int n; ADL2_Adapter_NumberOfAdapters_Get(ctx, out n);
        IntPtr buf = Marshal.AllocCoTaskMem(1572 * n); for (int i = 0; i < 1572 * n; i++) Marshal.WriteByte(buf, i, 0);
        ADL2_Adapter_AdapterInfo_Get(ctx, buf, 1572 * n);
        for (int i = 0; i < n && adapter < 0; i++) {
          int a = Marshal.ReadInt32(IntPtr.Add(buf, i * 1572), 4);
          for (int k = 0; k < 4 + 256 * 8; k++) Marshal.WriteByte(pm, k, 0);
          if (ADL2_New_QueryPMLogData_Get(ctx, a, pm) == 0 && Marshal.ReadInt32(pm, 4 + 8 * 8) != 0) adapter = a;
        }
        Marshal.FreeCoTaskMem(buf);
        if (adapter < 0) throw new Exception("no Radeon answered the sensor query (run this in the desktop session)");
      }
      for (int k = 0; k < 4 + 256 * 8; k++) Marshal.WriteByte(pm, k, 0);
      if (ADL2_New_QueryPMLogData_Get(ctx, adapter, pm) != 0) throw new Exception("the Radeon sensor query failed");
      return Marshal.ReadInt32(pm, 8 + 8 * 8);
    } finally { Marshal.FreeCoTaskMem(pm); }
  }
}
'@
function Get-LiveValue([string]$source) {
  switch ($source) {
    'cpuload' { [int](Get-Counter '\Processor Information(_Total)\% Processor Utility').CounterSamples[0].CookedValue }
    'gpuload' { [int]((Get-Counter '\GPU Engine(*engtype_3D)\Utilization Percentage').CounterSamples | Measure-Object CookedValue -Sum).Sum }
    'cputemp' { [int](((Get-Counter '\Thermal Zone Information(*)\Temperature').CounterSamples | Where-Object { $_.InstanceName -match 'hptz' } | Select-Object -First 1).CookedValue - 273) }
    'gputemp' { [Om3nLive]::GpuTemp() }
    'audio' { [Om3nLive]::AudioLevel() }
    'bass' { [Om3nLive]::AudioBands()[0] }
    'treble' { [Om3nLive]::AudioBands()[1] }
    default { throw "unknown source '$source'" }
  }
}
