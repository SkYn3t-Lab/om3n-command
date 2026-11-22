param([ValidateSet('show','off','on')][string]$Mode = 'show', [switch]$CloseNow)
$tasks = 'OmenInstallMonitor*', 'OmenOverlay*', 'StartCN', 'StartDVR'
$services = 'HPOmenCap', 'HPAppHelperCap', 'HPDiagsCap', 'HPNetworkCap', 'HPSysInfoCap', 'HpTouchpointAnalyticsService'
$hub = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\AD2F1837.OMENCommandCenter_v10z8vjag6ke6\OmenBackground'
$bgKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'; $bgName = 'LetAppsRunInBackground_ForceDenyTheseApps'; $hubPfn = 'AD2F1837.OMENCommandCenter_v10z8vjag6ke6'
function Get-BgDenied { @((Get-ItemProperty $bgKey -Name $bgName -ErrorAction SilentlyContinue).$bgName | Where-Object { $_ }) }
$running = 'OmenCommandCenterBackground', 'OmenBGMonitor', 'OmenInstallMonitor', 'OverlayHelper', 'RadeonSoftware', 'cncmd', 'AMDRSServ', 'AMDRSSrcExt', 'amdow'

if ($Mode -eq 'off') {
  Get-ScheduledTask -TaskName $tasks -ErrorAction SilentlyContinue | Disable-ScheduledTask | Out-Null
  if (Test-Path $hub) { Set-ItemProperty $hub -Name State -Value 1 -Type DWord }
  if (-not (Test-Path $bgKey)) { New-Item $bgKey -Force | Out-Null }
  if ($null -eq (Get-ItemProperty $bgKey -Name LetAppsRunInBackground -ErrorAction SilentlyContinue)) { New-ItemProperty $bgKey -Name LetAppsRunInBackground -Value 0 -PropertyType DWord | Out-Null }
  New-ItemProperty $bgKey -Name $bgName -Value ([string[]]@(@(Get-BgDenied) + $hubPfn | Select-Object -Unique)) -PropertyType MultiString -Force | Out-Null
  Get-Service $services -ErrorAction SilentlyContinue | Set-Service -StartupType Disabled
  if ($CloseNow) {
    Stop-Process -Name $running -Force -ErrorAction SilentlyContinue
    Get-Service $services -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
  }
}
if ($Mode -eq 'on') {
  Get-ScheduledTask -TaskName $tasks -ErrorAction SilentlyContinue | Enable-ScheduledTask | Out-Null
  if (Test-Path $hub) { Set-ItemProperty $hub -Name State -Value 2 -Type DWord }
  $left = [string[]]@(Get-BgDenied | Where-Object { $_ -ne $hubPfn })
  if ($left) { New-ItemProperty $bgKey -Name $bgName -Value $left -PropertyType MultiString -Force | Out-Null } else { Remove-ItemProperty $bgKey -Name $bgName -ErrorAction SilentlyContinue }
  Get-Service $services -ErrorAction SilentlyContinue | Set-Service -StartupType Automatic
  Get-Service $services -ErrorAction SilentlyContinue | Start-Service -ErrorAction SilentlyContinue
}

Get-ScheduledTask -TaskName $tasks -ErrorAction SilentlyContinue | ForEach-Object { '{0,-9} task {1}' -f $(if ($_.State -eq 'Disabled') { 'off' } else { 'on' }), ($_.TaskName -replace '-sid-.*', '') }
if (Test-Path $hub) { '{0,-9} Gaming Hub startup task' -f $(if ((Get-ItemProperty $hub).State -eq 2) { 'on' } else { 'off' }) } else { 'missing   Gaming Hub startup task' }
'{0,-9} Gaming Hub background tasks' -f $(if ((Get-BgDenied) -contains $hubPfn) { 'off' } else { 'on' })
Get-Service $services -ErrorAction SilentlyContinue | ForEach-Object { '{0,-9} service {1} ({2})' -f $(if ($_.StartType -eq 'Disabled') { 'off' } else { 'on' }), $_.Name, "$($_.Status)".ToLower() }
$up = Get-Process -Name $running -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name -Unique
if ($up) { 'running:  ' + ($up -join ', ') } else { 'running:  none' }
