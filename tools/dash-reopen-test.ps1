Add-Type -TypeDefinition (Get-Content -Raw (Join-Path (Join-Path (Split-Path $PSScriptRoot) 'app') 'om3n-command-dash.cs')) -ReferencedAssemblies 'System.Management'
[Dash]::Start(500)
function Hot { $s = [Dash]::Snapshot(); if ($s.ContainsKey('gpuHot')) { $s['gpuHot'] } }
$until = (Get-Date).AddSeconds(20); while (-not (Hot) -and (Get-Date) -lt $until) { Start-Sleep -Milliseconds 300 }
"before: hotspot $(Hot) C, reopens $([Dash]::GpuReopens)"
[Dash]::ReopenNow = $true
$until = (Get-Date).AddSeconds(10); while ([Dash]::GpuReopens -lt 1 -and (Get-Date) -lt $until) { Start-Sleep -Milliseconds 200 }
Start-Sleep -Seconds 2
"after:  hotspot $(Hot) C, reopens $([Dash]::GpuReopens), problems '$([Dash]::Problems -replace "`n", ' | ')'"
if ((Hot) -and [Dash]::GpuReopens -ge 1) { 'reopen test: OK'; exit 0 } else { 'reopen test: FAILED'; exit 1 }
