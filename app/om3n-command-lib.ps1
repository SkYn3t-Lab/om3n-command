$omenState = Join-Path $env:ProgramData 'SkYn3tLab'

function Protect-AppProcess {
  $win = [Environment]::GetFolderPath('Windows')
  $drive = Split-Path $win -Qualifier
  $cv = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion'
  $profiles = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList')
  $data = "$($profiles.GetValue('ProgramData', '%SystemDrive%\ProgramData', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames))" -replace '(?i)%SystemDrive%', $drive
  $me = $profiles.OpenSubKey([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
  $env:SystemRoot = $win; $env:windir = $win; $env:SystemDrive = $drive
  $env:ProgramData = $data; $env:ALLUSERSPROFILE = $data
  $env:ProgramFiles = (Get-ItemProperty $cv).ProgramFilesDir; $env:CommonProgramFiles = (Get-ItemProperty $cv).CommonFilesDir
  if ($me) {
    $profileDir = "$($me.GetValue('ProfileImagePath', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames))" -replace '(?i)%SystemDrive%', $drive
    if ($profileDir) { $env:USERPROFILE = $profileDir; $env:LOCALAPPDATA = Join-Path $profileDir 'AppData\Local'; $env:APPDATA = Join-Path $profileDir 'AppData\Roaming' }
  }
  $script:omenState = Join-Path $data 'SkYn3tLab'
  $env:PSModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules;$win\system32\WindowsPowerShell\v1.0\Modules"
  foreach ($v in @(Get-ChildItem Env: | Where-Object { $_.Name -match '^(COR_|COMPlus_)' -or $_.Name -eq 'PSExecutionPolicyPreference' })) { Remove-Item "Env:\$($v.Name)" -ErrorAction SilentlyContinue }
  $elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  $tmp = Join-Path $omenState 'temp'
  if ($elevated -and (Test-Path -LiteralPath $tmp -PathType Container)) { $env:TMP = $tmp; $env:TEMP = $tmp }
}

$lookNamePattern = '^[A-Za-z0-9][A-Za-z0-9_-]{0,30}$'

function Get-Looks([string]$Folder = $omenState) {
  $o = [ordered]@{}
  foreach ($f in (Join-Path (Split-Path $PSScriptRoot) 'defaults\om3n-command-lights.json'), (Join-Path $Folder 'om3n-command-lights.json')) {
    if (-not (Test-Path $f)) { continue }
    $j = Get-Content $f -Raw | ConvertFrom-Json
    foreach ($p in $j.PSObject.Properties) { if ($p.Name -match $lookNamePattern) { $o[$p.Name] = @($p.Value | ForEach-Object { "$_" }) } }
  }
  $o
}

function Import-Dash {
  if (-not ('Dash' -as [type])) {
    Add-Type -TypeDefinition (Get-Content -Raw (Join-Path $PSScriptRoot 'om3n-command-dash.cs')) -ReferencedAssemblies 'System.Management'
  }
  if ([Dash]::TotalMemMB -le 0) { [Dash]::TotalMemMB = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB }
}

function Get-FanSelection {
  try {
    $pidFile = Join-Path $omenState 'om3n-command-auto.pid'
    if (Test-Path $pidFile) {
      $p = Get-Process -Id ([int](Get-Content $pidFile -TotalCount 1)) -ErrorAction SilentlyContinue
      if ($p -and $p.ProcessName -eq 'powershell') { return 'auto' }
    }
    $m = (Get-Content (Join-Path $omenState 'om3n-command-fanmode.txt') -TotalCount 1 -ErrorAction Stop).Trim()
    if ($m -in 'quiet', 'normal', 'turbo') { return $m }
  } catch { }
  ''
}
