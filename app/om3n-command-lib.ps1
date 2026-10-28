$omenState = Join-Path $env:ProgramData 'SkYn3tLab'

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
