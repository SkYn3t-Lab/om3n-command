$ErrorActionPreference = 'Stop'
$AppId = 'SkYn3tLab.Om3nCommand'   # keep equal to AppId in om3n-command-host.cs
$target = Join-Path (Split-Path $PSScriptRoot) 'Om3n Command.exe'
if (-not (Test-Path $target)) { throw "Om3n Command.exe is not in the folder above this one ($target not found)" }
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;
namespace Om3n {
  [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IShellLinkW {
    void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder f, int cch, IntPtr fd, uint flags);
    void GetIDList(out IntPtr pidl);
    void SetIDList(IntPtr pidl);
    void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder n, int cch);
    void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string n);
    void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder d, int cch);
    void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string d);
    void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder a, int cch);
    void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string a);
    void GetHotkey(out short k);
    void SetHotkey(short k);
    void GetShowCmd(out int c);
    void SetShowCmd(int c);
    void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder p, int cch, out int i);
    void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string p, int i);
    void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string p, uint reserved);
    void Resolve(IntPtr hwnd, uint flags);
    void SetPath([MarshalAs(UnmanagedType.LPWStr)] string p);
  }
  [StructLayout(LayoutKind.Sequential)] public struct PropertyKey { public Guid Fmtid; public uint Pid; }
  [StructLayout(LayoutKind.Sequential)] public struct PropVariant { public ushort Vt; ushort r1, r2, r3; public IntPtr P; IntPtr p2; }
  [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IPropertyStore {
    void GetCount(out uint c);
    void GetAt(uint i, out PropertyKey k);
    void GetValue(ref PropertyKey k, out PropVariant v);
    void SetValue(ref PropertyKey k, ref PropVariant v);
    void Commit();
  }
  public static class Link {
    [DllImport("ole32.dll")] static extern int PropVariantClear(ref PropVariant v);
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [DllImport("shell32.dll")] public static extern void SHChangeNotify(int eventId, uint flags, IntPtr a, IntPtr b);
    // PKEY_AppUserModel_ID (propkey.h)
    static PropertyKey AppIdKey = new PropertyKey { Fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), Pid = 5 };
    public static void Write(string path, string target, string description, string appId) {
      var link = (IShellLinkW)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("00021401-0000-0000-C000-000000000046")));
      link.SetPath(target);
      link.SetArguments("");
      link.SetWorkingDirectory(System.IO.Path.GetDirectoryName(target));
      link.SetIconLocation(target, 0);
      link.SetDescription(description);
      var store = (IPropertyStore)link;
      var v = new PropVariant { Vt = 31, P = Marshal.StringToCoTaskMemUni(appId) };   // VT_LPWSTR
      try { store.SetValue(ref AppIdKey, ref v); store.Commit(); } finally { PropVariantClear(ref v); }
      ((IPersistFile)link).Save(path, true);
    }
  }
}
'@
$description = 'Fans, lighting, processor and graphics for this PC'
foreach ($link in (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Om3n Command.lnk'),
                  (Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'Om3n Command.lnk')) {
  if (Test-Path -LiteralPath $link) { Remove-Item -LiteralPath $link -Force }
  [Om3n.Link]::Write($link, $target, $description, $AppId)
  "shortcut written: $link -> $target"
}
[Om3n.Link]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
