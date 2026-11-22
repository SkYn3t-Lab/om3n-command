using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Windows.Forms;

[assembly: DefaultDllImportSearchPaths(DllImportSearchPath.System32)]

static class Om3nCommand
{
    const string OpenTask = "SkYn3tLab-om3n-command-open";
    static readonly string[] Unattended = { "-tray", "-selftest", "-offscreenseconds" };

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetDefaultDllDirectories(uint directoryFlags);
    const uint LoadLibrarySearchApplicationDir = 0x200, LoadLibrarySearchSystem32 = 0x800;

    const string AppId = "SkYn3tLab.Om3nCommand";   // keep equal to AppId in om3n-command-shortcut.ps1
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

    [STAThread]
    static int Main(string[] args)
    {
        try
        {
            if (!SetDefaultDllDirectories(LoadLibrarySearchApplicationDir | LoadLibrarySearchSystem32)) { throw new Win32Exception(); }
            Marshal.ThrowExceptionForHR(SetCurrentProcessExplicitAppUserModelID(AppId));
            if (!IsAdministrator()) { return Elevate(args); }
            string script = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, @"app\om3n-command-ui.ps1");
            if (!File.Exists(script)) { throw new FileNotFoundException("A file of the app is missing: " + script); }
            return RunWindow(script, args);
        }
        catch (Exception e)
        {
            Log("could not start: " + e.GetType().Name + ": " + e.Message);
            if (!IsUnattended(args)) { ShowError(e.Message); }
            return 1;
        }
    }

    static bool IsAdministrator()
    {
        return new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
    }

    static int Elevate(string[] args)
    {
        if (args.Length == 0 && RunTask(OpenTask)) { return 0; }
        var start = new ProcessStartInfo(Application.ExecutablePath, JoinArguments(args)) { UseShellExecute = true, Verb = "runas" };
        try { Process.Start(start); return 0; }
        catch (Win32Exception e) { if (e.NativeErrorCode == 1223) { return 1; } throw; }
    }

    static bool RunTask(string name)
    {
        try
        {
            dynamic service = Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service"));
            service.Connect();
            service.GetFolder("\\").GetTask(name).Run(null);
            return true;
        }
        catch (COMException) { return false; }
    }

    static string JoinArguments(string[] args)
    {
        var line = new StringBuilder();
        foreach (string a in args)
        {
            if (line.Length > 0) { line.Append(' '); }
            line.Append('"');
            int slashes = 0;
            foreach (char c in a)
            {
                if (c == '\\') { slashes++; continue; }
                line.Append('\\', c == '"' ? slashes * 2 + 1 : slashes).Append(c);
                slashes = 0;
            }
            line.Append('\\', slashes * 2).Append('"');
        }
        return line.ToString();
    }

    static InitialSessionState CreateSession()
    {
        InitialSessionState session = InitialSessionState.CreateDefault();
        session.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
        session.ApartmentState = System.Threading.ApartmentState.STA;
        session.ThreadOptions = PSThreadOptions.UseCurrentThread;
        return session;
    }

    static int RunWindow(string script, string[] args)
    {
        using (Runspace runspace = RunspaceFactory.CreateRunspace(CreateSession()))
        {
            runspace.Open();
            using (PowerShell window = PowerShell.Create())
            {
                window.Runspace = runspace;
                window.AddCommand(script);
                AddArguments(window, args);
                window.Invoke();
                if (window.Streams.Error.Count > 0) { Log("ended with " + window.Streams.Error.Count + " error(s); the first: " + window.Streams.Error[0]); }
            }
            object code = runspace.SessionStateProxy.GetVariable("LASTEXITCODE");
            return code is int ? (int)code : 0;
        }
    }

    static void AddArguments(PowerShell window, string[] args)
    {
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i].Length < 2 || args[i][0] != '-') { continue; }
            string name = args[i].Substring(1);
            bool hasValue = i + 1 < args.Length && !args[i + 1].StartsWith("-");
            if (hasValue) { window.AddParameter(name, args[++i]); } else { window.AddParameter(name, true); }
        }
    }

    static bool IsUnattended(string[] args)
    {
        foreach (string a in args) { if (Array.IndexOf(Unattended, a.ToLowerInvariant()) >= 0) { return true; } }
        return false;
    }

    static void ShowError(string message)
    {
        try { MessageBox.Show("Om3n Command could not start.\r\n\r\n" + message, "Om3n Command", MessageBoxButtons.OK, MessageBoxIcon.Error); }
        catch (Exception) { }
    }

    static void Log(string line)
    {
        try
        {
            string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "SkYn3tLab");
            Directory.CreateDirectory(dir);
            string stamped = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " APP " + line + "\r\n";
            File.AppendAllText(Path.Combine(dir, "om3n-command-app.log"), stamped, Encoding.UTF8);
        }
        catch (Exception) { }
    }
}
