$ErrorActionPreference = 'Stop'
$target = Join-Path (Split-Path $PSScriptRoot) 'Om3n Command.vbs'
if (-not (Test-Path $target)) { throw "Om3n Command.vbs must be in the folder above this one ($target not found)" }
$desk = [Environment]::GetFolderPath('Desktop')
$link = Join-Path $desk 'Om3n Command.lnk'
$s = (New-Object -ComObject WScript.Shell).CreateShortcut($link)
$s.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'; $s.Arguments = "`"$target`""; $s.WorkingDirectory = $PSScriptRoot; $s.WindowStyle = 7; $s.Description = 'Om3n Command: fans, lighting, processor and graphics for this PC'
$s.IconLocation = "$(Join-Path (Split-Path $PSScriptRoot) 'assets\om3n-command.ico'),0"
$s.Save()
Add-Type -Namespace Om3n -Name Shell -MemberDefinition '[DllImport("shell32.dll")] public static extern void SHChangeNotify(int eventId, uint flags, IntPtr a, IntPtr b);'
[Om3n.Shell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
"shortcut written: $link -> $target"
