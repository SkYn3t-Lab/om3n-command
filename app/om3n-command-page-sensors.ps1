$sens = @{ stats = @{}; rows = @{}; panels = @{}; since = (Get-Date); names = $null }
$sensorSpec = @(
  @{ g = 'Processor'; k = 'cpuTemp'; n = 'Temperature'; f = '{0:N0} C'; warn = 80; hot = 90 },
  @{ g = 'Processor'; k = 'boardTemp'; n = 'Board temperature'; f = '{0:N0} C' },
  @{ g = 'Processor'; k = 'cpuLoad'; n = 'Load, all threads'; f = '{0:N0} %' },
  @{ g = 'Processor'; k = 'cpuMHz'; n = 'Clock'; f = '{0:N0} MHz' },
  @{ g = 'Processor'; k = 'cpuW'; n = 'Power, whole processor'; f = '{0:N1} W'; warn = 125; hot = 170 },
  @{ g = 'Processor'; k = 'coresW'; n = 'Power, cores'; f = '{0:N1} W' },
  @{ g = 'Processor'; k = 'dramW'; n = 'Power, memory'; f = '{0:N1} W' },
  @{ g = 'Graphics'; k = 'gpuTemp'; n = 'Temperature, edge of the chip'; f = '{0:N0} C'; warn = 85; hot = 95 },
  @{ g = 'Graphics'; k = 'gpuHot'; n = 'Hotspot'; f = '{0:N0} C'; warn = 95; hot = 105 },
  @{ g = 'Graphics'; k = 'gpuMemTemp'; n = 'Memory temperature'; f = '{0:N0} C'; warn = 90; hot = 100 },
  @{ g = 'Graphics'; k = 'gpuIntake'; n = 'Air into the card'; f = '{0:N0} C' },
  @{ g = 'Graphics'; k = 'gpuLoad'; n = 'Load'; f = '{0:N0} %' },
  @{ g = 'Graphics'; k = 'gpuMemLoad'; n = 'Memory controller load'; f = '{0:N0} %' },
  @{ g = 'Graphics'; k = 'gpuMHz'; n = 'Core clock'; f = '{0:N0} MHz' },
  @{ g = 'Graphics'; k = 'gpuMemMHz'; n = 'Memory clock'; f = '{0:N0} MHz' },
  @{ g = 'Graphics'; k = 'gpuMv'; n = 'Core voltage'; f = '{0:N0} mV' },
  @{ g = 'Graphics'; k = 'gpuW'; n = 'Board power'; f = '{0:N0} W'; warn = 355; hot = 400 },
  @{ g = 'Graphics'; k = 'gpuFanRpm'; n = 'Fan speed'; f = '{0:N0} rpm' },
  @{ g = 'Graphics'; k = 'gpuFanPct'; n = 'Fan'; f = '{0:N0} %' },
  @{ g = 'Graphics'; k = 'vramGB'; n = 'Memory in use'; f = '{0:N1} GB'; warn = 20.4; hot = 22.8 },
  @{ g = 'System'; k = 'memUsedGB'; n = 'Memory in use'; f = '{0:N1} GB' },
  @{ g = 'System'; k = 'memPct'; n = 'Memory in use, share'; f = '{0:N0} %'; warn = 85; hot = 95 },
  @{ g = 'System'; k = 'netInMbit'; n = 'Download'; f = '{0:N1} Mbit/s' },
  @{ g = 'System'; k = 'netOutMbit'; n = 'Upload'; f = '{0:N1} Mbit/s' },
  @{ g = 'System'; k = 'diskReadMB'; n = 'Drive read'; f = '{0:N1} MB/s' },
  @{ g = 'System'; k = 'diskWriteMB'; n = 'Drive write'; f = '{0:N1} MB/s' },
  @{ g = 'System'; k = 'driveTemp'; n = 'System drive temperature'; f = '{0:N0} C'; warn = 84; hot = 88 }
)
$sensorGroups = 'Processor', 'Processor threads, load', 'Processor threads, clock', 'Graphics', 'Graphics, the driver''s other readings', 'System'
$sensorSkip = 'diskMB', 'uptimeS'    # a sum of two rows already shown, and a clock, not a reading

function Get-AdlNames {
  if ($null -ne $sens.names) { return $sens.names }
  $sens.names = @()
  try {
    $l = Get-Content (Join-Path $PSScriptRoot 'radeon-read.ps1') | Where-Object { $_ -match '^\$pm = ''([^'']+)''' } | Select-Object -First 1
    if ($l -and $l -match '^\$pm = ''([^'']+)''') { $sens.names = @($Matches[1] -split ',') }
  } catch { }
  $sens.names
}
function Get-SensorPlace([string]$k) {
  if ($k -match '^thr(\d+)Load$') { return @{ g = 'Processor threads, load'; k = $k; n = "Thread $($Matches[1])"; f = '{0:N0} %'; o = [int]$Matches[1] } }
  if ($k -match '^thr(\d+)MHz$') { return @{ g = 'Processor threads, clock'; k = $k; n = "Thread $($Matches[1])"; f = '{0:N0} MHz'; o = [int]$Matches[1] } }
  if ($k -match '^adl(\d+)$') {
    $i = [int]$Matches[1]; $names = Get-AdlNames
    $n = if ($i -lt $names.Count -and $names[$i]) { ($names[$i] -replace '_', ' ').ToLower() } else { "sensor $i" }
    return @{ g = 'Graphics, the driver''s other readings'; k = $k; n = $n; f = '{0:N0}'; o = $i }
  }
  @{ g = 'System'; k = $k; n = $k; f = '{0:N1}'; o = 999 }
}

function Update-SensorStats {
  $d = [Dash]::Snapshot()
  foreach ($k in $d.Keys) {
    $v = $d[$k]; $s = $sens.stats[$k]
    if (-not $s) { $sens.stats[$k] = @{ lo = $v; hi = $v; sum = $v; n = 1 } }
    else { if ($v -lt $s.lo) { $s.lo = $v }; if ($v -gt $s.hi) { $s.hi = $v }; $s.sum += $v; $s.n++ }
  }
}

$sensCols = "<Grid.ColumnDefinitions><ColumnDefinition Width='*'/><ColumnDefinition Width='104'/><ColumnDefinition Width='92'/><ColumnDefinition Width='92'/><ColumnDefinition Width='92'/></Grid.ColumnDefinitions>"
$sensorLeft = 'Processor', 'Processor threads, load', 'Processor threads, clock'

function Set-SensorsLayout {
  if ($state.page -ne 'Sensors' -or -not $sens.grid) { return }
  $R = $sens.grid.FindName('R'); $cols = $sens.grid.ColumnDefinitions
  if ($Page.ActualWidth -gt 0 -and $Page.ActualWidth -lt 1200) {
    $cols[1].Width = 0; $cols[2].Width = 0
    [Windows.Controls.Grid]::SetRow($R, 1); [Windows.Controls.Grid]::SetColumn($R, 0); [Windows.Controls.Grid]::SetColumnSpan($R, 3); $R.Margin = '0,22,0,0'
  } else {
    $cols[1].Width = 44; $cols[2].Width = New-Object Windows.GridLength 1, 'Star'
    [Windows.Controls.Grid]::SetRow($R, 0); [Windows.Controls.Grid]::SetColumn($R, 2); [Windows.Controls.Grid]::SetColumnSpan($R, 1); $R.Margin = '0'
  }
}

function Show-Sensors {
  Add-Title 'Sensors' 'Every reading this PC offers without a driver of its own, live, once a second.'
  $sens.rows = @{}; $sens.panels = @{}
  $bar = X "<StackPanel Orientation='Horizontal' Margin='0,0,0,10'/>"; [void]$Page.Children.Add($bar)
  [void]$bar.Children.Add((New-Button 'Start lowest, highest and average again' { $sens.stats = @{}; $sens.since = Get-Date; Update-SensorStats; Update-Sensors }))
  $sens.sinceText = X "<TextBlock Style='{DynamicResource Note}' VerticalAlignment='Center' Margin='14,0,0,0'/>"; [void]$bar.Children.Add($sens.sinceText)
  $sens.grid = X "<Grid><Grid.ColumnDefinitions><ColumnDefinition Width='*'/><ColumnDefinition Width='44'/><ColumnDefinition Width='*'/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition Height='Auto'/><RowDefinition Height='Auto'/></Grid.RowDefinitions><StackPanel x:Name='L'/><StackPanel x:Name='R' Grid.Column='2'/></Grid>"
  [void]$Page.Children.Add($sens.grid)
  $side = @{ L = $sens.grid.FindName('L'); R = $sens.grid.FindName('R') }
  foreach ($c in 'L', 'R') {
    [void]$side[$c].Children.Add((X "<Grid Height='24' Margin='15,0,15,0'>$sensCols<TextBlock Grid.Column='1' Style='{DynamicResource Note}' TextAlignment='Right' Text='now'/><TextBlock Grid.Column='2' Style='{DynamicResource Note}' TextAlignment='Right' Text='lowest'/><TextBlock Grid.Column='3' Style='{DynamicResource Note}' TextAlignment='Right' Text='highest'/><TextBlock Grid.Column='4' Style='{DynamicResource Note}' TextAlignment='Right' Text='average'/></Grid>"))
  }
  foreach ($g in $sensorGroups) {
    $c = if ($g -in $sensorLeft) { 'L' } else { 'R' }
    $cat = New-Category $g; $cat.card.Visibility = 'Collapsed'; [void]$side[$c].Children.Add($cat.card); $sens.panels[$g] = @{ head = $cat.card; panel = $cat.body; order = New-Object Collections.ArrayList }
  }
  Set-SensorsLayout
  $n = X "<StackPanel Margin='0,18,0,0'/>"; [void]$Page.Children.Add($n)
  Add-Note $n 'The thread readings and the graphics driver''s other readings are sampled only while this page is open, so their lowest, highest and average cover that time. The driver''s other readings carry AMD''s own names and are shown as the driver reports them, without a unit.'
  Add-Note $n 'Not on this page, because Windows offers them only through a kernel driver this app does not have: a temperature per processor core, the motherboard''s voltages, and the speeds of the case fans and the pump.'
  [Dash]::Detail = $true
  Update-Sensors
}

function Update-Sensors {
  if ($state.page -ne 'Sensors' -or -not $sens.panels.Count) { return }
  $d = [Dash]::Snapshot()
  foreach ($k in $d.Keys) {
    if ($sens.rows.ContainsKey($k) -or $k -in $sensorSkip) { continue }
    $spec = $null; $i = 0; foreach ($s in $sensorSpec) { if ($s.k -eq $k) { $spec = $s; $spec.o = $i; break }; $i++ }
    if (-not $spec) { $spec = Get-SensorPlace $k }
    $row = X "<Border BorderBrush='{DynamicResource Line}' BorderThickness='0,0,0,1'><Grid Height='30'>$sensCols<TextBlock x:Name='n' VerticalAlignment='Center' FontSize='14'/><TextBlock x:Name='v' Grid.Column='1' Style='{DynamicResource Readout}' FontSize='16' TextAlignment='Right' VerticalAlignment='Center'/><TextBlock x:Name='lo' Grid.Column='2' Style='{DynamicResource Readout}' FontSize='14' FontWeight='Normal' TextAlignment='Right' VerticalAlignment='Center'/><TextBlock x:Name='hi' Grid.Column='3' Style='{DynamicResource Readout}' FontSize='14' FontWeight='Normal' TextAlignment='Right' VerticalAlignment='Center'/><TextBlock x:Name='av' Grid.Column='4' Style='{DynamicResource Readout}' FontSize='14' FontWeight='Normal' TextAlignment='Right' VerticalAlignment='Center'/></Grid></Border>"
    $row.FindName('n').Text = $spec.n
    $grp = $sens.panels[$spec.g]
    $at = 0; while ($at -lt $grp.order.Count -and $grp.order[$at] -le $spec.o) { $at++ }
    $grp.order.Insert($at, $spec.o); $grp.panel.Children.Insert($at, $row); $grp.head.Visibility = 'Visible'
    $sens.rows[$k] = @{ spec = $spec; v = $row.FindName('v'); lo = $row.FindName('lo'); hi = $row.FindName('hi'); av = $row.FindName('av') }
  }
  foreach ($k in $sens.rows.Keys) {
    $r = $sens.rows[$k]; $f = $r.spec.f; $s = $sens.stats[$k]
    if ($d.ContainsKey($k)) { $r.v.Text = $f -f $d[$k]; Set-Heat $r.v $d[$k] $r.spec.warn $r.spec.hot } else { $r.v.Text = '--' }
    if ($s) { $r.lo.Text = $f -f $s.lo; $r.hi.Text = $f -f $s.hi; $r.av.Text = $f -f ($s.sum / $s.n); Set-Heat $r.hi $s.hi $r.spec.warn $r.spec.hot }
  }
  $sens.sinceText.Text = "Lowest, highest and average since $($sens.since.ToString('HH:mm:ss')). $($sens.rows.Count) readings."
}
