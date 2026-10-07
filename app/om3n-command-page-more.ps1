function New-MoreCard($panel, [string]$title) {
  $c = X "<Border Style='{DynamicResource Card}'><StackPanel/></Border>"; [void]$panel.Children.Add($c)
  $h = X "<TextBlock Style='{DynamicResource H2}' Margin='0,0,0,6'/>"; $h.Text = $title; [void]$c.Child.Children.Add($h)
  $c.Child
}
function New-MoreChoice($choices, $value, $tag, [scriptblock]$onChange) {
  $c = New-Combo @($choices.Keys) '' $tag $null
  $c.SelectedIndex = -1; foreach ($k in $choices.Keys) { if ("$($choices[$k])" -eq "$value") { $c.SelectedItem = $k } }
  $c.Add_SelectionChanged($onChange); $c
}

$fanAutoFile = Join-Path $env:ProgramData 'SkYn3tLab\om3n-command-fanauto.json'
function Test-FanAutoPair($q, $t) { $q -is [int] -and $t -is [int] -and $q -ge 1 -and $t -le 110 -and ($t - 5) -gt $q }
function ConvertFrom-FanAutoCommandLine([string]$c) {
  if ($c -match 'om3n-command\.ps1"? profile' -and $c -match '-QuietBelow (\d+) -TurboAbove (\d+)') { @{ QuietBelow = [int]$Matches[1]; TurboAbove = [int]$Matches[2] } }
}
function Get-FanAuto {
  try {
    $pf = Join-Path $env:ProgramData 'SkYn3tLab\om3n-command-auto.pid'
    if (Test-Path $pf) {
      $r = ConvertFrom-FanAutoCommandLine (Get-CimInstance Win32_Process -Filter "ProcessId=$([int](Get-Content $pf -TotalCount 1))").CommandLine
      if ($r) { $r.from = 'running'; return $r }
    }
  } catch { }
  try {
    $j = Get-Content $fanAutoFile -Raw -ErrorAction Stop | ConvertFrom-Json
    if (Test-FanAutoPair ([int]$j.QuietBelow) ([int]$j.TurboAbove)) { return @{ QuietBelow = [int]$j.QuietBelow; TurboAbove = [int]$j.TurboAbove; from = 'saved' } }
  } catch { }
  @{ QuietBelow = 50; TurboAbove = 75; from = 'default' }
}
function Save-FanAuto([int]$quiet, [int]$turbo) {
  if (-not (Test-FanAutoPair $quiet $turbo)) { return }
  try {
    $dir = Split-Path $fanAutoFile; if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $new = [ordered]@{ QuietBelow = $quiet; TurboAbove = $turbo } | ConvertTo-Json -Compress
    $old = if (Test-Path $fanAutoFile) { "$(Get-Content $fanAutoFile -Raw)".Trim() }
    if ($new -ne $old) { Set-Content $fanAutoFile $new }
  } catch { Write-AppError 'saving the automatic fan temperatures' $_ }
}
function Get-FanAutoArgs { $a = Get-FanAuto; "-QuietBelow $($a.QuietBelow) -TurboAbove $($a.TurboAbove)" }
function Add-FansMore($panel) {
  if (-not $fanQuiet -or -not $fanTurbo) { return }
  $a = Get-FanAuto
  Set-SliderValue $fanQuiet $a.QuietBelow; Set-SliderValue $fanTurbo $a.TurboAbove
  $save = { Save-FanAuto ([int]$fanQuiet.FindName('s').Value) ([int]$fanTurbo.FindName('s').Value) }
  foreach ($p in $fanQuiet, $fanTurbo) { $s = $p.FindName('s'); $s.Add_LostMouseCapture($save); $s.Add_KeyUp($save) }
  Add-Note $panel 'The two temperatures are remembered for the next time you open the app.'
}

function Get-ZoneMore($z) {
  $m = ''
  if ($null -ne $z.bright -and [int]$z.bright -ne 100) { $m += " -Brightness $([int]$z.bright)" }
  if ($z.effect -in 'wave', 'spiral' -and $z.dir) { $m += ' -Direction 1' }
  if ($z.extra -and $z.extra.Count -and $z.zone -ne 'Ram' -and $z.theme -eq 'custom' -and $z.effect -notin 'static', 'off') {
    $all = @($z.rgb -join ','); foreach ($c in $z.extra) { $all += ($c -join ',') }
    $m += " -Colors $($all -join ';')"
  }
  $m
}
function Read-ZoneMore($z, [string[]]$w) {
  for ($i = 1; $i -lt $w.Count - 1; $i++) {
    switch ($w[$i]) {
      '-Brightness' { $z.bright = [int]$w[$i + 1] }
      '-Direction' { $z.dir = [int]$w[$i + 1] }
      '-Colors' {
        $z.extra = New-Object Collections.ArrayList; $first = $true
        foreach ($t in ($w[$i + 1] -split ';')) { $c = @($t -split ',' | ForEach-Object { [int]$_ }); if ($first) { $z.rgb = $c; $first = $false } else { [void]$z.extra.Add($c) } }
      }
    }
  }
}
function Get-ZoneBright($z) { if ($null -eq $z.bright) { 100 } else { [int]$z.bright } }
function Get-SleepArgs([string]$k, [bool]$off) { if ($off) { "light $k -Effect off -State sleep" } else { "light $(Get-ZoneLine $zoneState[$k]) -State sleep" } }
function Get-LiveArgs([string]$kind, [string]$k, [int]$seconds, [string]$source, [int]$preset, [string]$band) {
  $z = $zoneState[$k]; $b = if ((Get-ZoneBright $z) -ne 100) { " -Brightness $(Get-ZoneBright $z)" } else { '' }
  if ($kind -eq 'vitals') { "light $k -Effect vitals -Source $source -Preset $preset -Seconds $seconds$b" }
  else { "light $k $($z.rgb -join ' ') -Effect audio -Band $band -Seconds $seconds$b" }
}
$liveSources = [ordered]@{ 'Processor temperature' = 'cputemp'; 'Processor load' = 'cpuload'; 'Graphics temperature' = 'gputemp'; 'Graphics load' = 'gpuload' }
$liveBands = [ordered]@{ 'Loudness' = 'level'; 'Bass' = 'bass'; 'Treble' = 'treble' }
$liveTimes = [ordered]@{ '1 minute' = 60; '5 minutes' = 300; '15 minutes' = 900; '1 hour' = 3600 }

$liveJob = $null
function Start-ParkedCtl([string]$arguments, [string]$doing, [int]$limitSec) {
  Stop-LiveEffect
  Start-Ctl $arguments $null $doing $limitSec
  $script:liveJob = $lastJob; $jobs.Remove($lastJob)
  if (-not $script:liveTimer) {
    $script:liveTimer = New-Object Windows.Threading.DispatcherTimer; $liveTimer.Interval = [TimeSpan]::FromSeconds(1)
    $liveTimer.Add_Tick({
        $j = $script:liveJob
        if (-not $j) { $liveTimer.Stop(); return }
        if ($j.p.HasExited -or ((Get-Date) - $j.started).TotalSeconds -ge $j.limit) { $script:liveJob = $null; [void]$jobs.Add($j); Update-LiveUi }
      })
  }
  $liveTimer.Start(); Update-LiveUi
}
function Stop-LiveEffect {
  $j = $script:liveJob; if (-not $j) { return }
  $script:liveJob = $null
  if (-not $j.p.HasExited) {
    try { $j.p.Kill() } catch { }
    $line = "{0:yyyy-MM-dd HH:mm:ss} > om3n-command $($j.args)   [stopped from the app after $([int]((Get-Date) - $j.started).TotalSeconds) s]" -f (Get-Date)
    [void]$activity.AppendLine($line); [void]$activity.AppendLine(); Write-AppLog $line
    $Busy.Text = 'Stopped the live effect.'; $Busy.Foreground = $win.FindResource('Dim')
  } else { [void]$jobs.Add($j) }
  Update-LiveUi
}
function Update-LiveUi { if ($liveUi -and $liveUi.stop) { $liveUi.stop.IsEnabled = [bool]$script:liveJob } }
function Start-LiveEffect([string]$kind) {
  $k = @($zoneNames.Keys | Where-Object { $zoneNames[$_] -eq $liveUi.zone.SelectedItem })[0]; $sec = $liveTimes[$liveUi.time.SelectedItem]
  $a = Get-LiveArgs $kind $k $sec $liveSources[$liveUi.source.SelectedItem] ($liveUi.preset.SelectedIndex + 1) $liveBands[$liveUi.band.SelectedItem]
  Start-ParkedCtl $a "Running a live effect on the $($zoneNames[$k].ToLower()) for $($liveUi.time.SelectedItem)..." ($sec + 30)
}

function Add-LightingMore($panel) {
  $c = New-MoreCard $panel 'Brightness, direction and more colours'
  $cols = "<Grid.ColumnDefinitions><ColumnDefinition Width='150'/><ColumnDefinition Width='54'/><ColumnDefinition Width='150'/><ColumnDefinition Width='140'/><ColumnDefinition Width='*'/></Grid.ColumnDefinitions>"
  [void]$c.Children.Add((X "<Grid Margin='0,0,0,2'>$cols<TextBlock Grid.Column='2' Style='{DynamicResource Note}' Text='Brightness'/><TextBlock Grid.Column='3' Style='{DynamicResource Note}' Text='Direction'/><TextBlock Grid.Column='4' Style='{DynamicResource Note}' Text='More colours'/></Grid>"))
  foreach ($k in $zoneNames.Keys) {
    $z = $zoneState[$k]
    $g = X "<Grid Margin='0,7'>$cols<TextBlock x:Name='n' VerticalAlignment='Center' FontSize='14'/></Grid>"
    $g.FindName('n').Text = $zoneNames[$k]
    $b = New-Combo @('100 %', '75 %', '50 %', '25 %', '0 %') "$(Get-ZoneBright $z) %" $k { $zoneState[$this.Tag].bright = [int]("$($this.SelectedItem)" -replace '\D'); Send-Zone $this.Tag }
    [Windows.Controls.Grid]::SetColumn($b, 2); $b.Margin = '0,0,10,0'; $b.IsEnabled = ($z.effect -ne 'off'); [void]$g.Children.Add($b)
    if ($z.effect -in 'wave', 'spiral') {
      $d = New-Combo @('One way', 'The other way') $(if ($z.dir) { 'The other way' } else { 'One way' }) $k { $zoneState[$this.Tag].dir = $this.SelectedIndex; Send-Zone $this.Tag }
      [Windows.Controls.Grid]::SetColumn($d, 3); $d.MinWidth = 120; $d.Margin = '0,0,10,0'; [void]$g.Children.Add($d)
    }
    if ($k -ne 'Ram' -and $z.theme -eq 'custom' -and $z.effect -notin 'static', 'off') {
      $w = X "<StackPanel Orientation='Horizontal'/>"; [Windows.Controls.Grid]::SetColumn($w, 4); [void]$g.Children.Add($w)
      $i = 0
      foreach ($e in @($z.extra)) {
        if ($null -eq $e) { continue }
        $s = X "<Button Width='28' Height='28' Padding='0' Margin='0,0,6,0' ToolTip='Take this colour out'/>"
        $s.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb($e[0], $e[1], $e[2])); $s.Tag = @{ k = $k; i = $i }
        $s.Add_Click({ $zoneState[$this.Tag.k].extra.RemoveAt($this.Tag.i); Send-Zone $this.Tag.k; Show-Lighting })
        [void]$w.Children.Add($s); $i++
      }
      if ($i -lt 5) {
        $add = New-Button 'Add a colour' {
          $z = $zoneState[$this.Tag]; $d = New-Object Windows.Forms.ColorDialog; $d.FullOpen = $true
          if ($d.ShowDialog() -eq 'OK') { if (-not $z.extra) { $z.extra = New-Object Collections.ArrayList }; [void]$z.extra.Add(@([int]$d.Color.R, [int]$d.Color.G, [int]$d.Color.B)); Send-Zone $this.Tag; Show-Lighting }
        }
        $add.Tag = $k; [void]$w.Children.Add($add)
      }
    }
    [void]$c.Children.Add($g)
  }
  Add-Note $c 'Direction is for Wave and Spiral. More colours are for an animated effect in your own colour on the case lights: the effect moves through them in order.'

  $c2 = New-MoreCard $panel 'While the PC sleeps'
  foreach ($k in @($zoneNames.Keys | Where-Object { $_ -ne 'Ram' })) {
    $p = X "<StackPanel Orientation='Horizontal'/>"
    $same = New-Button 'Same as when awake' { Start-Ctl (Get-SleepArgs $this.Tag $false) $null "Setting the sleep lighting of the $($zoneNames[$this.Tag].ToLower())..." }; $same.Tag = $k
    $off = New-Button 'Off' { Start-Ctl (Get-SleepArgs $this.Tag $true) $null "Turning the $($zoneNames[$this.Tag].ToLower()) off for sleep..." }; $off.Tag = $k; $off.Margin = '0'
    [void]$p.Children.Add($same); [void]$p.Children.Add($off)
    [void](Add-Row $c2 $zoneNames[$k] '' $p)
  }
  Add-Note $c2 'Same as when awake copies what the light is set to on this page. The PC cannot report its sleep lighting, so nothing here shows which one is in force.'

  $c3 = New-MoreCard $panel 'Live effects'
  $script:liveUi = @{}
  $liveUi.zone = New-Combo @($zoneNames.Keys | Where-Object { $_ -ne 'Ram' } | ForEach-Object { $zoneNames[$_] }) $zoneNames['FrontFan'] $null $null
  $liveUi.time = New-Combo @($liveTimes.Keys) '5 minutes' $null $null
  $liveUi.stop = New-Button 'Stop' { Stop-LiveEffect }; $liveUi.stop.Margin = '0'
  $p = X "<StackPanel Orientation='Horizontal'/>"; $liveUi.zone.Margin = '0,0,8,0'; $liveUi.time.Margin = '0,0,8,0'; $liveUi.time.MinWidth = 110
  [void]$p.Children.Add($liveUi.zone); [void]$p.Children.Add($liveUi.time); [void]$p.Children.Add($liveUi.stop)
  [void](Add-Row $c3 'Which light, and for how long' '' $p)
  $liveUi.source = New-Combo @($liveSources.Keys) '' $null $null
  $liveUi.preset = New-Combo @('Colour range 1', 'Colour range 2') '' $null $null
  $p = X "<StackPanel Orientation='Horizontal'/>"; $liveUi.source.Margin = '0,0,8,0'; $liveUi.preset.Margin = '0,0,8,0'; $liveUi.preset.MinWidth = 130
  $go = New-Button 'Start' { Start-LiveEffect 'vitals' } -Primary; $go.Margin = '0'
  [void]$p.Children.Add($liveUi.source); [void]$p.Children.Add($liveUi.preset); [void]$p.Children.Add($go)
  [void](Add-Row $c3 'Follow a reading' 'The colour moves from cool to hot with the processor or the graphics card.' $p)
  $liveUi.band = New-Combo @($liveBands.Keys) '' $null $null
  $p = X "<StackPanel Orientation='Horizontal'/>"; $liveUi.band.Margin = '0,0,8,0'
  $go = New-Button 'Start' { Start-LiveEffect 'audio' } -Primary; $go.Margin = '0'
  [void]$p.Children.Add($liveUi.band); [void]$p.Children.Add($go)
  [void](Add-Row $c3 'Pulse with sound' 'The light pulses in its own colour with what is playing.' $p)
  Add-Note $c3 'A live effect runs for the time chosen, or until you press Stop. Afterwards the light keeps its last colour: choose its effect again, or press a saved look, to put it back.'
  Update-LiveUi
}

function Get-MemoryArgs([int]$speed) { "memory $speed" }
function Add-MemoryProfile($panel) {
  $script:mem = @{ panel = (New-MoreCard $panel 'Memory speed'); page = $state.page }
  Add-Note $mem.panel 'Reading the memory profile...'
  Start-Ctl 'memory' {
    param($lines, $raw, $ok)
    if ($state.page -ne $mem.page) { return }
    $p = $mem.panel; while ($p.Children.Count -gt 1) { $p.Children.RemoveAt(1) }
    $m = [regex]::Match(($lines -join "`n"), 'memory: in use (\d+) MHz; profiles on offer (\d+) and (\d+) MHz; switching supported = (True|False)')
    if (-not $ok -or -not $m.Success) { Add-Note $p 'The memory profile could not be read. See the Activity page.'; return }
    $mem.inUse = [int]$m.Groups[1].Value; $mem.can = ($m.Groups[4].Value -eq 'True'); $mem.radios = @{}
    $seg = X "<StackPanel Orientation='Horizontal'/>"
    foreach ($s in @([int]$m.Groups[2].Value, [int]$m.Groups[3].Value | Select-Object -Unique)) {
      $r = X "<RadioButton Style='{DynamicResource Seg}' GroupName='memspeed'/>"; $r.Content = "$s MHz"; $r.Tag = $s; $r.IsChecked = ($s -eq $mem.inUse); $r.IsEnabled = $mem.can
      $r.Add_Click({ Show-MemoryConfirm ([int]$this.Tag) })
      $mem.radios[$s] = $r; [void]$seg.Children.Add($r)
    }
    $r.Margin = '0'   # the last one ends at the page's right edge, like every other control
    $note = if ($mem.can) { "In use now: $($mem.inUse) MHz. Another speed is a BIOS setting: it takes effect after a restart, not before." } else { "In use now: $($mem.inUse) MHz. This PC's BIOS does not offer a choice of memory speed." }
    [void](Add-Row $p 'Speed from the next restart' $note $seg)
    $mem.bar = X "<Border BorderBrush='{DynamicResource Warn}' BorderThickness='1' Background='{DynamicResource Panel}' Padding='16,12' Margin='0,8,0,0' Visibility='Collapsed'><StackPanel><TextBlock x:Name='T' TextWrapping='Wrap' Margin='0,0,0,10'/><StackPanel x:Name='B' Orientation='Horizontal'/></StackPanel></Border>"
    $mem.text = $mem.bar.FindName('T')
    $mem.yes = New-Button 'Yes, set it for the next restart' {
        $mem.bar.Visibility = 'Collapsed'
        Start-Ctl (Get-MemoryArgs ([int]$this.Tag)) {
          param($lines, $raw, $ok, $job)
          $s = [int]($job.args -replace '\D')
          $mem.result.Text = if ($ok -and "$lines" -match 'memory: accepted') { "$s MHz is set for the next restart. Until then the memory runs at $($mem.inUse) MHz." } else { 'The BIOS did not take the setting. See the Activity page.' }
          if (-not ($ok -and "$lines" -match 'memory: accepted')) { $mem.radios[$mem.inUse].IsChecked = $true }
        } 'Setting the memory speed for the next restart...'
      } -Primary
    [void]$mem.bar.FindName('B').Children.Add($mem.yes)
    [void]$mem.bar.FindName('B').Children.Add((New-Button 'Cancel' { $mem.bar.Visibility = 'Collapsed'; $mem.radios[$mem.inUse].IsChecked = $true }))
    [void]$p.Children.Add($mem.bar)
    $mem.result = X "<TextBlock Style='{DynamicResource Note}' Margin='0,6,0,0'/>"; [void]$p.Children.Add($mem.result)
  } 'Reading the memory profile...'
}
function Show-MemoryConfirm([int]$speed) {
  $mem.result.Text = ''
  $mem.text.Text = $(if ($speed -eq $mem.inUse) { "$speed MHz is the speed in use now. Sending it again makes the next restart keep it, in case another speed was chosen earlier. " } else { "Set the memory to $speed MHz from the next restart? " }) +
    'This writes a BIOS setting. Nothing changes until you restart; the BIOS then tests the memory at that speed, so that one start-up takes longer. This app has only ever rehearsed this write, never sent it for real.'
  $mem.yes.Tag = $speed; $mem.bar.Visibility = 'Visible'
}

$moreLimits = [ordered]@{
  GFXCLK_FMAX    = @{ name = 'Highest graphics clock'; unit = ' MHz'; step = 10; note = 'Higher is faster and hotter; too high makes games crash.' }
  GFXCLK_FMIN    = @{ name = 'Lowest graphics clock'; unit = ' MHz'; step = 10; note = 'The speed the chip never drops below.' }
  UCLK_FMAX      = @{ name = 'Highest memory clock'; unit = ' MHz'; step = 10; note = 'For the graphics memory. Too high shows as flicker or wrong colours.' }
  TDC_PERCENTAGE = @{ name = 'Current limit'; unit = ' %'; step = 1; note = 'How much current the chip may draw compared with normal. Lower runs cooler and slower.' }
}
function Get-GpuLimitArgs([string]$id, [int]$value) { "gpu -Setting $id -Value $value" }
$more3d = [ordered]@{
  vsync     = @{ name = 'Wait for vertical refresh (V-Sync)'; note = 'Shows a frame only when the monitor is ready for it, which stops tearing.'; choices = [ordered]@{ 'Always off' = 0; 'Off, unless the game asks' = 1; 'On, unless the game asks' = 2; 'Always on' = 3 } }
  aamode    = @{ name = 'Anti-aliasing'; note = 'Smooths jagged edges.'; choices = [ordered]@{ 'Let the game decide' = 0; 'Enhance the game setting' = 1; 'Override the game' = 2 } }
  aalevel   = @{ name = 'Anti-aliasing level'; note = 'Used when anti-aliasing is not left to the game.'; choices = [ordered]@{ '2x' = 2; '4x' = 4; '8x' = 8 } }
  aamethod  = @{ name = 'Anti-aliasing method'; note = 'Supersampling looks best and costs the most.'; choices = [ordered]@{ 'Multisampling' = 0; 'Adaptive multisampling' = 1; 'Supersampling' = 2 } }
  maa       = @{ name = 'Morphological anti-aliasing'; note = 'Smooths edges in every game, and softens the picture a little.'; switch = $true }
  af        = @{ name = 'Anisotropic filtering'; note = 'Keeps surfaces sharp at a distance, at the level below.'; switch = $true }
  aflevel   = @{ name = 'Anisotropic filtering level'; note = 'Used when anisotropic filtering is on.'; choices = [ordered]@{ '2x' = 2; '4x' = 4; '8x' = 8; '16x' = 16 } }
  tessmode  = @{ name = 'Tessellation'; note = 'How much fine surface detail is drawn.'; choices = [ordered]@{ 'AMD optimized' = 0; 'Let the game decide' = 1; 'Override the game' = 2 } }
  tesslevel = @{ name = 'Tessellation level'; note = 'Used when tessellation overrides the game.'; choices = [ordered]@{ 'Off' = 1; '2x' = 2; '4x' = 4; '6x' = 6; '8x' = 8; '16x' = 16; '32x' = 32; '64x' = 64 } }
}
function Get-Gpu3dArgs([string]$id, [int]$value) { "gpu -Setting $id -Value $value" }
function Read-More3d {
  Start-Ctl 'display' {
    param($lines, $raw, $ok)
    if ($state.page -ne $gfxMore.page) { return }
    $p = $gfxMore.panel3d; while ($p.Children.Count -gt 1) { $p.Children.RemoveAt(1) }
    $gfxMore.now = @{}; $seen = $false
    foreach ($l in $lines) {
      if ($l -match 'through the newer interface') { $seen = $true; continue }
      if ($seen -and $l -match '^\s*(\w+)\s+.*?supported=(\d) value=(-?\d+)') { if ($Matches[2] -eq '1') { $gfxMore.now[$Matches[1]] = [int]$Matches[3] } }
    }
    foreach ($k in $more3d.Keys) {
      if (-not $gfxMore.now.ContainsKey($k)) { continue }   # the driver reports it unsupported, or did not answer: no control
      $d = $more3d[$k]; $v = $gfxMore.now[$k]
      $ctl = if ($d.switch) { New-Switch ($v -eq 1) @{ arg = "-Setting $k"; name = $d.name; kind = 'setting' } $featureClick }
      else { New-MoreChoice $d.choices $v @{ id = $k; choices = $d.choices; name = $d.name } { if ($null -ne $this.SelectedItem) { Start-Ctl (Get-Gpu3dArgs $this.Tag.id $this.Tag.choices[$this.SelectedItem]) { Read-More3d } "Setting $($this.Tag.name.ToLower())..." } } }
      [void](Add-Row $p $d.name $d.note $ctl)
    }
    if (-not $gfxMore.now.Count) { Add-Note $p 'The 3D settings could not be read. See the Activity page.' }
    $clear = New-Button 'Clear it' { Start-Ctl 'gpu -Setting shadercache -Reset' $null 'Clearing the shader cache...' }; $clear.Margin = '0'
    [void](Add-Row $p 'Shader cache' 'Clears the shaders the driver has stored. Games build them again the next time they start, so that start is slower.' $clear)
  } 'Reading the 3D settings...'
}
function Add-GraphicsMore($panel) {
  $script:gfxMore = @{ page = $state.page; sliders = [ordered]@{} }
  $c = New-MoreCard $panel 'Clock and current limits'
  foreach ($k in $moreLimits.Keys) {
    $s = Get-GpuSetting $k; $d = $moreLimits[$k]
    if (-not $s -or $s.max -le $s.min) { continue }   # no range from the driver: the card does not have this limit
    $now = [Math]::Min($s.max, [Math]::Max($s.min, $s.current))
    $tag = @{ id = $k; name = $d.name; was = [int]$now; btn = $null }
    $sl = New-Slider $s.min $s.max $d.step $now $d.unit $tag { param($sl) $sl.Tag.data.btn.IsEnabled = ([int]$sl.Value -ne $sl.Tag.data.was) }
    $btn = New-Button 'Set' { $sl = $this.Tag; $this.IsEnabled = $false; Start-Ctl (Get-GpuLimitArgs $sl.Tag.data.id ([int]$sl.Value)) { Read-Gpu } "Setting the $($sl.Tag.data.name.ToLower())..." }
    $btn.Tag = $sl.FindName('s'); $btn.IsEnabled = $false; $btn.Margin = '10,0,0,0'; $tag.btn = $btn
    $row = X "<StackPanel Orientation='Horizontal'/>"; [void]$row.Children.Add($sl); [void]$row.Children.Add($btn)
    $gfxMore.sliders[$k] = $sl
    [void](Add-Row $c $d.name "$($d.note) Factory setting $($s.default)$($d.unit)." $row)
  }
  if ($gfxMore.sliders.Count) { Add-Note $c 'Move a slider, then press Set. Nothing is sent until you do; it then takes effect straight away.' }
  else { Add-Note $c 'The limits could not be read. See the Activity page.' }
  $gfxMore.panel3d = New-MoreCard $panel '3D settings'
  Add-Note $gfxMore.panel3d 'Reading the 3D settings...'
  Read-More3d
}

function Invoke-MoreSelfTest([string]$ShotDir = '') {
  $run = {
    param([string]$a)
    Start-Ctl $a { param($lines, $raw, $ok) $script:moreOut = @($lines); $script:moreOk = $ok } 'moretest'; Wait-Jobs
    "moretest: > om3n-command $a   [ok=$moreOk]"; $moreOut | Where-Object { $_ -match '^light:|^memory:|^adapter \d+, setting|sending:|SIMULATE|before:|ABORT|FAILED|shader cache|would write' } | Select-Object -First 4 | ForEach-Object { "moretest:     $_" }
  }
  $shot = {
    param([string]$name)
    if (-not $ShotDir) { return }
    Wait-Jobs
    $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$win.ActualWidth), ([int]$win.ActualHeight), 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($win.Content); $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder; $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $fs = [IO.File]::Create((Join-Path $ShotDir "om3n-command-more-$name.png")); $enc.Save($fs); $fs.Close()
  }
  $a = Get-FanAuto; "moretest: fan auto read: quiet below $($a.QuietBelow), performance from $($a.TurboAbove), from '$($a.from)' (file $fanAutoFile, present = $(Test-Path $fanAutoFile))"
  "moretest: Om3n would send: fan auto $(Get-FanAutoArgs)"
  $realFile = $fanAutoFile; $script:fanAutoFile = Join-Path $env:TEMP 'om3n-command-fanauto-selftest.json'
  try {
  Select-Page 'Fans'; Wait-Jobs
  "moretest: with the rehearsal file: Fans sliders show $([int]$fanQuiet.FindName('s').Value) and $([int]$fanTurbo.FindName('s').Value)"
  Save-FanAuto 44 81; $a = Get-FanAuto; "moretest: after Save-FanAuto 44 81: read $($a.QuietBelow) / $($a.TurboAbove) from '$($a.from)'; file holds $(Get-Content $fanAutoFile -Raw)".Trim()
  Save-FanAuto 60 65; $a = Get-FanAuto; "moretest: after Save-FanAuto 60 65 (a pair the tool refuses): read $($a.QuietBelow) / $($a.TurboAbove), unchanged = $($a.QuietBelow -eq 44)"
  Select-Page 'Fans'; Wait-Jobs; "moretest: Fans page rebuilt: sliders show $([int]$fanQuiet.FindName('s').Value) and $([int]$fanTurbo.FindName('s').Value)"; & $shot 'Fans-remembered'
  Set-Content $fanAutoFile '{"QuietBelow":"x"}'; $a = Get-FanAuto; "moretest: with a damaged file: read $($a.QuietBelow) / $($a.TurboAbove) from '$($a.from)'"
  Remove-Item $fanAutoFile; $a = Get-FanAuto; "moretest: with no file: read $($a.QuietBelow) / $($a.TurboAbove) from '$($a.from)'"
  } finally { Remove-Item $fanAutoFile -ErrorAction SilentlyContinue; $script:fanAutoFile = $realFile }
  $r = ConvertFrom-FanAutoCommandLine '"powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\x\om3n-command.ps1" profile -Seconds 0 -Background -QuietBelow 47 -TurboAbove 82 -Hysteresis 5 -Interval 5'
  "moretest: the running loop's command line reads as $($r.QuietBelow) / $($r.TurboAbove); another process's reads as '$(ConvertFrom-FanAutoCommandLine 'notepad.exe -QuietBelow 1 -TurboAbove 2')'"
  foreach ($k in $zoneNames.Keys) { "moretest: zone line: light $(Get-ZoneLine $zoneState[$k])" }
  $z = $zoneState['FrontFan']; $z.effect = 'wave'; $z.bright = 50; $z.dir = 1; $z.extra = New-Object Collections.ArrayList; [void]$z.extra.Add(@(0, 200, 255)); [void]$z.extra.Add(@(255, 255, 255))
  $zoneState['Logo'].bright = 25; $zoneState['Ram'].effect = 'wave'; $zoneState['Ram'].dir = 1; $zoneState['Ram'].bright = 75; $zoneState['CpuFan'].effect = 'spiral'; $zoneState['CpuFan'].theme = 'galaxy'; $zoneState['CpuFan'].dir = 1
  $lines = @($zoneNames.Keys | ForEach-Object { Get-ZoneLine $zoneState[$_] })
  foreach ($l in $lines) { & $run "light $l -Simulate" }
  $back = Read-ProfileLine $lines[2]; "moretest: read back from a saved look: '$($lines[2])' -> '$(Get-ZoneLine $back)' (same = $((Get-ZoneLine $back) -eq $lines[2]))"
  & $run "$(Get-SleepArgs 'FrontFan' $false) -Simulate"; & $run "$(Get-SleepArgs 'Logo' $true) -Simulate"
  & $run "$(Get-LiveArgs 'vitals' 'FrontFan' 300 'gputemp' 2 '') -Simulate"; & $run "$(Get-LiveArgs 'audio' 'Logo' 60 '' 0 'bass') -Simulate"
  Select-Page 'Lighting'; Wait-Jobs; & $shot 'Lighting-filled'
  $n0 = $activity.Length
  Start-ParkedCtl "$(Get-LiveArgs 'vitals' 'FrontFan' 300 'cputemp' 1 '') -Simulate" 'moretest' 330
  "moretest: live effect started: set aside = $([bool]$liveJob), on the job list = $($jobs.Count), Stop enabled = $($liveUi.stop.IsEnabled)"
  $end = (Get-Date).AddSeconds(15); while ($liveJob -and (Get-Date) -lt $end) { Wait-Jobs; Start-Sleep -Milliseconds 300 }; Wait-Jobs
  "moretest: live effect ended: set aside = $([bool]$liveJob), Stop enabled = $($liveUi.stop.IsEnabled), status bar '$($Busy.Text)', logged: $(($activity.ToString().Substring($n0) -split "`r?`n" | Where-Object { $_ -match '^\S.*> |light:' }) -join ' | ')"
  $n0 = $activity.Length
  Start-ParkedCtl 'profile -Simulate -Seconds 20' 'moretest' 50; $p = $liveJob.p; Start-Sleep -Seconds 3; Wait-Jobs
  "moretest: a long command set aside: running = $(-not $p.HasExited), Stop enabled = $($liveUi.stop.IsEnabled)"
  Stop-LiveEffect; [void]$p.WaitForExit(3000)
  "moretest: after Stop: running = $(-not $p.HasExited), set aside = $([bool]$liveJob), Stop enabled = $($liveUi.stop.IsEnabled), status bar '$($Busy.Text)', logged: $(($activity.ToString().Substring($n0) -split "`r?`n" | Where-Object { $_ -match '> ' }) -join ' | ')"
  Initialize-Zones ''
  $click = { param($c) $c.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
  Select-Page 'Processor'; Wait-Jobs
  "moretest: memory read: in use $($mem.inUse) MHz, choices $(($mem.radios.Keys | Sort-Object) -join ' and '), switching possible = $($mem.can), question shown = $($mem.bar.Visibility)"
  $other = @($mem.radios.Keys | Where-Object { $_ -ne $mem.inUse })[0]
  $mem.radios[$other].IsChecked = $true; & $click $mem.radios[$other]
  "moretest: pressed $other MHz: question shown = $($mem.bar.Visibility); Yes would send: om3n-command $(Get-MemoryArgs ([int]$mem.yes.Tag)); jobs started = $($jobs.Count)"
  "moretest: question text: $($mem.text.Text)"
  & $shot 'Processor-memory-question'
  & $click $mem.bar.FindName('B').Children[1]
  "moretest: pressed Cancel: question shown = $($mem.bar.Visibility), selected again = $(@($mem.radios.Keys | Where-Object { $mem.radios[$_].IsChecked }) -join ',') MHz, jobs started = $($jobs.Count)"
  & $click $mem.radios[$mem.inUse]; "moretest: pressed the speed in use: $($mem.text.Text.Substring(0, 60))..."; & $click $mem.bar.FindName('B').Children[1]
  & $run "$(Get-MemoryArgs $other) -Simulate"; & $run "$(Get-MemoryArgs $mem.inUse) -Simulate"
  Select-Page 'Graphics'; Wait-Jobs
  foreach ($k in $gfxMore.sliders.Keys) { $s = $gfxMore.sliders[$k].FindName('s'); "moretest: slider $k shows $($s.Value) in $($s.Minimum)..$($s.Maximum)"; & $run "$(Get-GpuLimitArgs $k ([int]$s.Value)) -Simulate" }
  "moretest: 3D settings read: $(($gfxMore.now.Keys | Sort-Object | ForEach-Object { "$_=$($gfxMore.now[$_])" }) -join ' ')"
  foreach ($k in $more3d.Keys) {
    if (-not $gfxMore.now.ContainsKey($k)) { "moretest: $k not offered by the driver: no control"; continue }
    $v = $gfxMore.now[$k]; if (-not $more3d[$k].switch -and $more3d[$k].choices.Values -notcontains $v) { $v = @($more3d[$k].choices.Values)[0] }
    & $run "$(Get-Gpu3dArgs $k $v) -Simulate"
  }
  & $run 'gpu -Setting shadercache -Simulate'; & $run 'gpu -Feature led'
}
