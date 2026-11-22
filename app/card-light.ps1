param([ValidateSet('status', 'off', 'saved', 'known')][string]$Do = 'status', [switch]$Simulate, [string]$Pnp = '')
$ErrorActionPreference = 'Stop'
$knownCard = '^PCI\\VEN_1002&DEV_744C&SUBSYS_[0-9A-F]{4}1002'
if ($Do -eq 'known') { return ($Pnp -match $knownCard) }
$steps = @{
  off   = @(, [byte[]](0x41, 0x80)) + @(, [byte[]](0x51, 0x96, 0, 0, 0)) + @(, [byte[]](0x51, 0x28, 0, 0, 0xFE))
  saved = @(, [byte[]](0x41, 0x03)) + @(, [byte[]](0x50)) + @(, [byte[]](0x41, 0x00))
}
function Format-Bytes([byte[]]$b) { ($b | ForEach-Object { $_.ToString('X2') }) -join ' ' }
if ($Simulate) {
  if ($Do -eq 'status') { 'card light: SIMULATE, status reads 12 02 and 52 28' }
  else { "card light: SIMULATE $Do would send: $(($steps[$Do] | ForEach-Object { Format-Bytes $_ }) -join ' | ')" }
  return
}
if (-not ('CardLight' -as [type])) {
  Add-Type @'
using System;
using System.Runtime.InteropServices;
// native libraries only from System32, never the current or temp folder (Microsoft: DefaultDllImportSearchPathsAttribute)
[assembly: DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
public static class CardLight {
  public delegate IntPtr Malloc(int size);
  static readonly Malloc keep = s => Marshal.AllocHGlobal(s);
  [StructLayout(LayoutKind.Sequential)] struct I2C { public int Size, Line, Address, Offset, Action, Speed, DataSize; public IntPtr Data; }
  const string D = "atiadlxx.dll";
  [DllImport(D)] static extern int ADL_Main_Control_Create(Malloc cb, int connectedOnly);
  [DllImport(D)] static extern int ADL_Main_Control_Destroy();
  [DllImport(D)] static extern int ADL_Adapter_NumberOfAdapters_Get(out int n);
  [DllImport(D)] static extern int ADL_Adapter_AdapterInfo_Get(IntPtr info, int size);
  [DllImport(D)] static extern int ADL_Display_WriteAndReadSMUI2C(int adapter, ref I2C i2c);
  static int adapter = -1;
  static int Xfer(int address, int action, byte[] data) {
    IntPtr p = Marshal.AllocHGlobal(24);
    try {
      Marshal.Copy(new byte[24], 0, p, 24); Marshal.Copy(data, 0, p, data.Length);
      var x = new I2C { Size = Marshal.SizeOf(typeof(I2C)), Line = 0, Address = address, Offset = 0, Action = action, Speed = 100, DataSize = data.Length, Data = p };
      int rc = ADL_Display_WriteAndReadSMUI2C(adapter, ref x);
      Marshal.Copy(p, data, 0, data.Length);
      return rc;
    } finally { Marshal.FreeHGlobal(p); }
  }
  // one command (its first bytes; the rest of the 64 are zero), the 64-byte reply or null
  public static byte[] Send(byte[] head) {
    var cmd = new byte[64]; Array.Copy(head, cmd, head.Length);
    int[] off = { 0, 23, 46 }, len = { 23, 23, 18 };
    for (int attempt = 0; attempt < 3; attempt++) {
      bool ok = true;
      for (int k = 0; k < 3 && ok; k++) {
        var pkt = new byte[len[k] + 1];
        pkt[0] = (byte)((k == 0 ? 0x40 : 0) | (k == 2 ? 0x80 : 0) | off[k]);
        Array.Copy(cmd, off[k], pkt, 1, len[k]);
        ok = Xfer(0xB4, 2, pkt) == 0;
      }
      if (!ok) continue;
      System.Threading.Thread.Sleep(20);
      var reply = new byte[64];
      for (int k = 0; k < 3 && ok; k++) {
        var pkt = new byte[len[k] + 1];
        ok = Xfer(0xB5, 1, pkt) == 0;
        if (ok) Array.Copy(pkt, 1, reply, off[k], len[k]);
      }
      if (ok) return reply;
    }
    return null;
  }
  // "" when a controller answered, otherwise why not
  public static string Open(string knownCard) {
    if (ADL_Main_Control_Create(keep, 1) != 0) return "AMD's driver interface did not open";
    int n; ADL_Adapter_NumberOfAdapters_Get(out n);
    if (n < 1) return "no AMD graphics adapter";
    IntPtr buf = Marshal.AllocHGlobal(1572 * n);
    try {
      for (int i = 0; i < 1572 * n; i++) Marshal.WriteByte(buf, i, 0);
      ADL_Adapter_AdapterInfo_Get(buf, 1572 * n);
      // AdapterInfo (adl_structures.h): iAdapterIndex at 4, iVendorID (decimal 1002 for AMD) at 0x114, strPNPString at 0x520
      for (int i = 0; i < n && adapter < 0; i++) {
        IntPtr p = buf + 1572 * i;
        if (Marshal.ReadInt32(p, 0x114) != 1002) continue;
        // strPNPString at 0x520: never send even the find command to a card that is not a known one
        string pnp = Marshal.PtrToStringAnsi(p + 0x520) ?? "";
        if (!System.Text.RegularExpressions.Regex.IsMatch(pnp, knownCard, System.Text.RegularExpressions.RegexOptions.IgnoreCase)) continue;
        adapter = Marshal.ReadInt32(p, 4);
        var r = Send(new byte[] { 0x12, 0x02 });
        if (r == null || r[0] != 0x12 || r[1] != 0x02 || r[4] >= 2) adapter = -1;
      }
    } finally { Marshal.FreeHGlobal(buf); }
    return adapter < 0 ? "this graphics card has no lighting controller the app knows" : "";
  }
  public static void Close() { ADL_Main_Control_Destroy(); }
}
'@
}
$why = [CardLight]::Open($knownCard)
try {
  if ($why) { "card light: skipped, $why"; return }
  function Get-Mode { $r = [CardLight]::Send([byte[]](0x52, 0x28)); if (-not $r) { throw 'the card did not answer the mode read' }; $r[4] }
  if ($Do -eq 'status') { 'card light: controller found, mode 0x{0:X2} ({1})' -f ($m = Get-Mode), $(if ($m -eq 0xFE) { 'off' } else { 'lit' }); return }
  foreach ($s in $steps[$Do]) { if (-not [CardLight]::Send($s)) { throw "the card did not answer $(Format-Bytes $s)" } }
  $m = Get-Mode
  if ($Do -eq 'off' -and $m -ne 0xFE) { throw ('the card still reports mode 0x{0:X2} after Light Off' -f $m) }
  if ($Do -eq 'saved' -and $m -eq 0xFE) { 'card light: back on the lighting saved on the card, which is off' }
  elseif ($Do -eq 'saved') { 'card light: back on the lighting saved on the card (mode 0x{0:X2})' -f $m }
  else { 'card light: off' }
} finally { [CardLight]::Close() }
