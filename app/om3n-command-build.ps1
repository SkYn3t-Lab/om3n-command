param([switch]$Force, [switch]$Show)
$ErrorActionPreference = 'Stop'
$app = $PSScriptRoot; $root = Split-Path $app
$exe = Join-Path $root 'Om3n Command.exe'; $old = Join-Path $root 'Om3n Command.old.exe'
$cs = Join-Path $app 'om3n-command-host.cs'; $man = Join-Path $app 'om3n-command-host.manifest'
$ico = Join-Path $root 'assets\om3n-command.ico'
$m = Select-String -Path (Join-Path $app 'om3n-command.ps1') -Pattern "^\`$AppVersion = '([0-9.]+)'$" | Select-Object -First 1
if (-not $m) { 'BUILD FAILED: no $AppVersion in om3n-command.ps1'; exit 1 }
$version = $m.Matches[0].Groups[1].Value
$sha = [Security.Cryptography.SHA256]::Create()
$bytes = New-Object Collections.Generic.List[byte]
foreach ($f in $cs, $man, $ico) { $bytes.AddRange([IO.File]::ReadAllBytes($f)) }
$stamp = (($sha.ComputeHash($bytes.ToArray()) | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 12)
$want = "$version+$stamp"
$have = if (Test-Path $exe) { (Get-Item $exe).VersionInfo.ProductVersion } else { '' }
if ($Show) { "BUILD wants $want, the exe carries '$have'"; exit 0 }
if (Test-Path $old) { Remove-Item $old -Force -ErrorAction SilentlyContinue }
function Reset-ExeAccess { $r = & icacls $exe /reset /q; if ($LASTEXITCODE -ne 0) { "BUILD FAILED: icacls /reset said: $r"; exit 1 } }
if (-not $Force -and $have -eq $want) { Reset-ExeAccess; "BUILD kept $exe ($have)"; exit 0 }

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { "BUILD FAILED: the .NET Framework compiler is not at $csc"; exit 1 }
$sma = [PSObject].Assembly.Location
$work = Join-Path $env:TEMP "om3n-command-build-$PID"
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
  $info = Join-Path $work 'version.cs'
  $n = ($version -split '\.') + @('0', '0', '0') | Select-Object -First 4
  @(
    'using System.Reflection;'
    '[assembly: AssemblyTitle("Om3n Command")]'
    '[assembly: AssemblyProduct("Om3n Command")]'
    '[assembly: AssemblyCompany("SkYn3t Lab")]'
    '[assembly: AssemblyCopyright("MIT License")]'
    "[assembly: AssemblyVersion(`"$($n -join '.')`")]"
    "[assembly: AssemblyFileVersion(`"$($n -join '.')`")]"
    "[assembly: AssemblyInformationalVersion(`"$want`")]"
  ) | Set-Content -Path $info -Encoding UTF8
  $built = Join-Path $work 'Om3n Command.exe'
  $out = & $csc /nologo /target:winexe /platform:x64 /optimize+ "/win32icon:$ico" "/win32manifest:$man" "/reference:$sma" /reference:System.Windows.Forms.dll /reference:System.Core.dll /reference:Microsoft.CSharp.dll "/out:$built" $cs $info 2>&1
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $built)) { "BUILD FAILED: the compiler said:"; $out | ForEach-Object { "  $_" }; exit 1 }
  if (Test-Path $exe) {
    try { Remove-Item $exe -Force } catch { Move-Item $exe $old -Force }   # running: renamed out of the way
  }
  Move-Item $built $exe -Force
  Reset-ExeAccess
  $now = (Get-Item $exe).VersionInfo
  if ($now.ProductVersion -ne $want) { "BUILD FAILED: the new exe carries '$($now.ProductVersion)', not $want"; exit 1 }
  "BUILD built $exe ($want, $((Get-Item $exe).Length) bytes)$(if (Test-Path $old) { '; the running one was renamed to Om3n Command.old.exe' })"
} finally { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
