$hist = @{ span = '1h'; task = $null; result = $null; crashes = @(); strips = $null; axes = $null; timer = $null; sized = $false; sliders = @{}; spans = @{} }

function Get-HistoryRows {
  $mem = if ([Dash]::TotalMemMB -gt 0) { [Math]::Ceiling([Dash]::TotalMemMB / 1024) } else { 32 }
  @(
    @{ g = 'Processor' },
    @{ k = 'cpuTemp'; n = 'Temperature'; f = '{0:N0} C'; lo = 30; hi = 100; c = 'cpu'; alert = $true },
    @{ k = 'cpuLoad'; n = 'Load'; f = '{0:N0} %'; lo = 0; hi = 100; c = 'cpu' },
    @{ k = 'cpuW'; n = 'Power'; f = '{0:N0} W'; lo = 0; hi = 180; c = 'cpu'; warn = 125; hot = 170 },
    @{ g = 'Graphics' },
    @{ k = 'gpuTemp'; n = 'Temperature'; f = '{0:N0} C'; lo = 30; hi = 100; c = 'gpu'; warn = 85; hot = 95 },
    @{ k = 'gpuHot'; n = 'Hotspot'; f = '{0:N0} C'; lo = 30; hi = 110; c = 'gpu'; alert = $true },
    @{ k = 'gpuMemTemp'; n = 'Memory temperature'; f = '{0:N0} C'; lo = 30; hi = 105; c = 'gpu'; alert = $true },
    @{ k = 'gpuLoad'; n = 'Load'; f = '{0:N0} %'; lo = 0; hi = 100; c = 'gpu' },
    @{ k = 'gpuW'; n = 'Power'; f = '{0:N0} W'; lo = 0; hi = 400; c = 'gpu'; warn = 355; hot = 400 },
    @{ k = 'gpuFanPct'; n = 'Fan'; f = '{0:N0} %'; lo = 0; hi = 100; c = 'gpu' },
    @{ k = 'vramGB'; n = 'Memory in use'; f = '{0:N1} GB'; lo = 0; hi = 24; c = 'gpu'; warn = 20.4; hot = 22.8 },
    @{ g = 'System' },
    @{ k = 'memUsedGB'; n = 'Memory in use'; f = '{0:N1} GB'; lo = 0; hi = $mem; c = 'sys'; warn = ($mem * 0.85); hot = ($mem * 0.95) },
    @{ k = 'driveTemp'; n = 'Drive temperature'; f = '{0:N0} C'; lo = 20; hi = 90; c = 'sys'; alert = $true }
  )
}

$histCols = "<Grid.ColumnDefinitions><ColumnDefinition Width='170'/><ColumnDefinition Width='34'/><ColumnDefinition Width='*'/><ColumnDefinition Width='78'/><ColumnDefinition Width='78'/><ColumnDefinition Width='78'/></Grid.ColumnDefinitions>"

function Show-Logging {
  Add-Title 'Logging' 'What the recorder wrote down: one reading a second, kept for 14 days. The charts follow it: they are read again every few seconds while this page is open.'
  $hist.alert = Get-AlertSettings
  $seg = X "<StackPanel Orientation='Horizontal'/>"; [void]$Page.Children.Add($seg)
  foreach ($k in $historySpans.Keys) {
    $r = X "<RadioButton Style='{DynamicResource Seg}' GroupName='histspan'/>"; $r.Content = $historySpans[$k].name; $r.Tag = $k; $r.IsChecked = ($k -eq $hist.span)
    $r.Add_Click({ $hist.span = $this.Tag; Start-HistoryLoad }); $hist.spans[$k] = $r; [void]$seg.Children.Add($r)
  }
  $hist.summary = X "<TextBlock Style='{DynamicResource Note}' Margin='0,10,0,14' Text=' '/>"; [void]$Page.Children.Add($hist.summary)

  $hist.strips = New-Object Collections.ArrayList; $hist.axes = New-Object Collections.ArrayList
  $top = X "<Grid Height='34' Margin='15,0,15,0'>$histCols<Canvas x:Name='c' Grid.Column='2'/><TextBlock Grid.Column='3' Style='{DynamicResource Note}' TextAlignment='Right' VerticalAlignment='Bottom' Text='lowest'/><TextBlock Grid.Column='4' Style='{DynamicResource Note}' TextAlignment='Right' VerticalAlignment='Bottom' Text='average'/><TextBlock Grid.Column='5' Style='{DynamicResource Note}' TextAlignment='Right' VerticalAlignment='Bottom' Text='highest'/></Grid>"
  [void]$Page.Children.Add($top); [void]$hist.axes.Add(@{ c = $top.FindName('c'); marks = $true })
  foreach ($r in (Get-HistoryRows)) {
    if ($r.g) { $cat = New-Category $r.g; [void]$Page.Children.Add($cat.card); continue }
    $row = X "<Border BorderBrush='{DynamicResource Line}' BorderThickness='0,0,0,1'><Grid Height='46'>$histCols<TextBlock x:Name='n' VerticalAlignment='Center' FontSize='14'/><TextBlock x:Name='hi' Grid.Column='1' Style='{DynamicResource Note}' FontSize='10.5' TextAlignment='Right' VerticalAlignment='Top' Margin='0,1,6,0'/><TextBlock x:Name='lo' Grid.Column='1' Style='{DynamicResource Note}' FontSize='10.5' TextAlignment='Right' VerticalAlignment='Bottom' Margin='0,0,6,1'/><Border Grid.Column='2' Margin='0,5' BorderBrush='{DynamicResource Line}' BorderThickness='1,0,0,1'/><Canvas x:Name='c' Grid.Column='2' Margin='0,5' ClipToBounds='True'/><TextBlock x:Name='a' Grid.Column='3' Style='{DynamicResource Readout}' FontSize='16' TextAlignment='Right' VerticalAlignment='Center' Text='--'/><TextBlock x:Name='b' Grid.Column='4' Style='{DynamicResource Readout}' FontSize='16' TextAlignment='Right' VerticalAlignment='Center' Text='--'/><TextBlock x:Name='m' Grid.Column='5' Style='{DynamicResource Readout}' FontSize='16' TextAlignment='Right' VerticalAlignment='Center' Text='--'/></Grid></Border>"
    $row.FindName('n').Text = $r.n; $row.FindName('hi').Text = "$($r.hi)"; $row.FindName('lo').Text = "$($r.lo)"
    [void]$hist.strips.Add(@{ r = $r; c = $row.FindName('c'); a = $row.FindName('a'); b = $row.FindName('b'); m = $row.FindName('m'); col = $win.FindResource('Zone-sys').Color })
    [void]$cat.body.Children.Add($row)
  }
  $bottom = X "<Grid Height='20' Margin='15,0,15,0'>$histCols<Canvas x:Name='c' Grid.Column='2'/></Grid>"
  [void]$Page.Children.Add($bottom); [void]$hist.axes.Add(@{ c = $bottom.FindName('c'); marks = $false })

  [void]$Page.Children.Add((X "<TextBlock Style='{DynamicResource Group}' Text='Hottest moments'/>"))
  $hist.hottest = X "<StackPanel/>"; [void]$Page.Children.Add($hist.hottest)

  [void]$Page.Children.Add((X "<TextBlock Style='{DynamicResource Group}' Text='Crash reports'/>"))
  $hist.crashes = @(Get-CrashReports)
  $cp = X "<StackPanel/>"; [void]$Page.Children.Add($cp)
  if (-not $hist.crashes) { Add-Note $cp 'None in the last 14 days.' }
  foreach ($c in $hist.crashes) {
    $b = New-Button 'Open' { Start-Process notepad.exe "`"$($this.Tag)`"" }; $b.Tag = $c.File
    [void](Add-Row $cp $c.Back.ToString('ddd d MMM yyyy, HH:mm') $c.Summary $b)
  }
  Add-Note $cp 'Written when Windows comes back after stopping without a clean shutdown. Each is marked in red on the charts above.'

  [void]$Page.Children.Add((X "<TextBlock Style='{DynamicResource Group}' Text='Graphics driver resets'/>"))
  $rp = X "<StackPanel/>"; [void]$Page.Children.Add($rp)
  $resets = @(Get-ChildItem $historyDir -Filter 'reset-*.txt' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 10)
  if (-not $resets) { Add-Note $rp 'None since reports began on 4 October 2026.' }
  foreach ($f in $resets) {
    $at = [datetime]::MinValue; if (-not [datetime]::TryParseExact($f.BaseName.Substring(6), 'yyyyMMdd-HHmmss', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$at)) { continue }
    $b = New-Button 'Open' { Start-Process notepad.exe "`"$($this.Tag)`"" }; $b.Tag = $f.FullName
    [void](Add-Row $rp $at.ToString('ddd d MMM yyyy, HH:mm:ss') 'The card stopped answering and Windows restarted its driver.' $b)
  }
  Add-Note $rp 'Written within seconds of a reset: the readings for three minutes before it, what was set and what was running.'

  if (-not $hist.sized) { $hist.sized = $true; $Page.Add_SizeChanged({ Update-History }) }
  if (-not $hist.live) {
    $hist.live = New-Object Windows.Threading.DispatcherTimer; $hist.live.Interval = [TimeSpan]::FromSeconds(5); $hist.liveAt = Get-Date
    $hist.live.Add_Tick({
        if ($state.page -ne 'Logging' -or -not $win.IsVisible -or $win.WindowState -eq 'Minimized' -or $hist.task) { return }
        $every = if ($hist.span -eq @($historySpans.Keys)[0]) { 5 } else { 30 }
        if (((Get-Date) - $hist.liveAt).TotalSeconds -lt $every - 0.5) { return }
        $hist.liveAt = Get-Date; Start-HistoryLoad -Quiet
      })
    $hist.live.Start()
  }
  Start-HistoryLoad
}

function Show-Alerts {
  Add-Title 'Alerts' 'When the app tells you a reading runs hot, and from which temperature.'
  $hist.alert = Get-AlertSettings
  [void]$Page.Children.Add((X "<TextBlock Style='{DynamicResource Group}' Text='Temperature alerts' Margin='0,0,0,4'/>"))
  $ap = X "<StackPanel/>"; [void]$Page.Children.Add($ap)
  [void](Add-Row $ap 'Tell me when it runs hot' 'A Windows notification from the icon by the clock, and a line in the log.' (New-Switch $hist.alert.on $null { $hist.alert.on = [bool]$this.IsChecked; Save-HistoryAlerts }))
  $head = X "<StackPanel Orientation='Horizontal'><TextBlock Style='{DynamicResource Note}' Width='336' Text='Alert from'/><TextBlock Style='{DynamicResource Note}' Width='308' Text='Stronger alert from'/></StackPanel>"
  [void](Add-Row $ap '' '' $head)
  $setLimit = {
    param($sl) $d = $sl.Tag.data; $lim = $hist.alert.limits[$d.k]; $lim[$d.f] = [int]$sl.Value
    if ($lim.hot -lt $lim.warn) { $o = if ($d.f -eq 'warn') { 'hot' } else { 'warn' }; $lim[$o] = [int]$sl.Value; Set-SliderValue $hist.sliders["$($d.k).$o"] $sl.Value }
    Save-HistoryAlerts; Update-History
  }
  foreach ($k in $alertNames.Keys) {
    $two = X "<StackPanel Orientation='Horizontal'/>"
    foreach ($f in 'warn', 'hot') { $s = New-Slider 40 110 1 $hist.alert.limits[$k][$f] ' C' @{ k = $k; f = $f } $setLimit; $hist.sliders["$k.$f"] = $s; if ($f -eq 'warn') { $s.Margin = '0,0,28,0' }; [void]$two.Children.Add($s) }
    $sw = New-Switch ($hist.alert.limits[$k].on -ne $false) @{ k = $k } { $hist.alert.limits[$this.Tag.k].on = [bool]$this.IsChecked; Save-HistoryAlerts }; $sw.Margin = '20,0,0,0'; $sw.VerticalAlignment = 'Center'; [void]$two.Children.Add($sw)
    [void](Add-Row $ap $alertNames[$k] '' $two)
  }
  [void](Add-Row $ap 'Only once it has lasted' 'A short spike raises nothing.' (New-Slider 0 120 5 $hist.alert.sustainSec ' s' $null { param($sl) $hist.alert.sustainSec = [int]$sl.Value; Save-HistoryAlerts }))
  [void](Add-Row $ap 'Then stay quiet for' 'No second alert for the same reading in this time, unless it reaches the stronger line.' (New-Slider 1 60 1 $hist.alert.quietMin ' min' $null { param($sl) $hist.alert.quietMin = [int]$sl.Value; Save-HistoryAlerts }))
  [void](Add-Row $ap 'Tell me the app is still running' 'Shown once each time the app runs, when you first close its window.' (New-Switch ($hist.alert.trayTip -ne $false) $null { $hist.alert.trayTip = [bool]$this.IsChecked; Save-HistoryAlerts }))
  Add-Note $ap "The switch beside each reading turns that reading's alert off or on. These are the only notifications the app shows. The dashed lines on the Logging page's charts are these alert lines. An episode is over once the reading is $($hist.alert.coolBy) C under its line."
}

function Save-HistoryAlerts { Set-AlertSettings $hist.alert; $Busy.Text = 'Saved the alert settings.'; $Busy.Foreground = $win.FindResource('Dim') }

function Start-HistoryLoad([switch]$Quiet) {
  $hist.task = Read-History -Span $hist.span -Async
  $hist.quiet = [bool]$Quiet
  if ($hist.spans[$hist.span]) { $hist.spans[$hist.span].IsChecked = $true }
  if (-not $Quiet) { $Busy.Text = 'Reading the recorded readings...'; $Busy.Foreground = $win.FindResource('AccentText') }
  if (-not $hist.timer) {
    $hist.timer = New-Object Windows.Threading.DispatcherTimer; $hist.timer.Interval = [TimeSpan]::FromMilliseconds(60)
    $hist.timer.Add_Tick({
        if ($hist.task -and -not $hist.task.IsCompleted) { return }
        $hist.timer.Stop(); $t = $hist.task; $hist.task = $null
        if (-not $t) { return }
        $hist.result = $t.Result
        if ($hist.result.Error) { $Busy.Text = "Could not read the recorded readings: $($hist.result.Error)"; $Busy.Foreground = $win.FindResource('Hot'); Write-AppLog ("{0:yyyy-MM-dd HH:mm:ss} HISTORY: could not read: $($hist.result.Error)" -f (Get-Date)) }
        elseif (-not $hist.quiet) { $Busy.Text = 'Done'; $Busy.Foreground = $win.FindResource('Dim') }
        Update-History
      })
  }
  $hist.timer.Start()
}

function Get-HistoryTicks([datetime]$from, [datetime]$to) {
  $hours = ($to - $from).TotalHours
  $step = if ($hours -le 1.5) { 10 } elseif ($hours -le 8) { 60 } elseif ($hours -le 30) { 240 } else { 1440 }
  $t = $from.Date; while ($t -lt $from) { $t = $t.AddMinutes($step) }
  while ($t -le $to) { @{ t = $t; text = $(if ($step -eq 1440) { $t.ToString('ddd d') } else { $t.ToString('HH:mm') }) }; $t = $t.AddMinutes($step) }
}

function Update-History {
  if ($state.page -ne 'Logging' -or -not $hist.result -or -not $hist.strips) { return }
  $r = $hist.result; $span = ($r.To - $r.From).TotalSeconds
  $ticks = @(Get-HistoryTicks $r.From $r.To)
  $marks = @($hist.crashes | Where-Object { $_.At -ge $r.From -and $_.At -le $r.To })
  $line = $win.FindResource('Line'); $dim = $win.FindResource('Dim'); $hot = $win.FindResource('Hot'); $warn = $win.FindResource('Warn')
  $vline = { param($canvas, $x, $y1, $y2, $brush) $l = New-Object Windows.Shapes.Line; $l.X1 = $x; $l.X2 = $x; $l.Y1 = $y1; $l.Y2 = $y2; $l.Stroke = $brush; $l.StrokeThickness = 1; $l.SnapsToDevicePixels = $true; [void]$canvas.Children.Add($l) }

  foreach ($ax in $hist.axes) {
    $c = $ax.c; $w = $c.ActualWidth; $c.Children.Clear(); if ($w -le 0) { continue }
    $y = if ($ax.marks) { 17 } else { 3 }
    foreach ($t in $ticks) {
      $x = ($t.t - $r.From).TotalSeconds / $span * $w; if ($x -lt 18 -or $x -gt $w - 18) { continue }   # a label must not hang over the edge
      $tb = New-Object Windows.Controls.TextBlock; $tb.Text = $t.text; $tb.Foreground = $dim; $tb.FontSize = 11; $tb.Width = 60; $tb.TextAlignment = 'Center'
      [Windows.Controls.Canvas]::SetLeft($tb, $x - 30); [Windows.Controls.Canvas]::SetTop($tb, $y); [void]$c.Children.Add($tb)
    }
    if ($ax.marks) {
      $lastX = -1000
      foreach ($m in ($marks | Sort-Object At)) {
        $x = ($m.At - $r.From).TotalSeconds / $span * $w
        & $vline $c $x 1 14 $hot   # beside its own label only: the row below belongs to the clock times
        if ($x - $lastX -lt 96) { continue }   # two shutdowns close together share one label
        $tb = New-Object Windows.Controls.TextBlock; $tb.Text = "stopped $($m.At.ToString('HH:mm'))"; $tb.Foreground = $hot; $tb.FontSize = 11; $tb.Width = 90
        if ($x -gt $w - 96) { $tb.TextAlignment = 'Right'; [Windows.Controls.Canvas]::SetLeft($tb, $x - 94) } else { [Windows.Controls.Canvas]::SetLeft($tb, $x + 4) }
        [Windows.Controls.Canvas]::SetTop($tb, 0); [void]$c.Children.Add($tb); $lastX = $x
      }
    }
  }

  foreach ($s in $hist.strips) {
    $k = $s.r.k; $c = $s.c; $w = $c.ActualWidth; $h = $c.ActualHeight; $c.Children.Clear()
    $ser = $null; if ($r.Series.ContainsKey($k)) { $ser = $r.Series[$k] }
    $has = $ser -and $ser.Count -gt 0
    $wl = $s.r.warn; $hl = $s.r.hot; if ($s.r.alert) { $wl = $hist.alert.limits[$k].warn; $hl = $hist.alert.limits[$k].hot }
    $s.a.Text = if ($has) { $s.r.f -f $ser.Lo } else { '--' }
    $s.b.Text = if ($has) { $s.r.f -f $ser.Avg } else { '--' }
    $s.m.Text = if ($has) { $s.r.f -f $ser.Hi } else { '--' }
    Set-Heat $s.m $(if ($has) { $ser.Hi }) $wl $hl
    $s.col = Get-HeatColor $(if ($has) { $ser.Hi }) $wl $hl
    if ($w -le 0 -or $h -le 0) { continue }
    foreach ($t in $ticks) { $x = ($t.t - $r.From).TotalSeconds / $span * $w; if ($x -ge 18 -and $x -le $w - 18) { & $vline $c $x 0 $h $line } }
    if ($s.r.alert -and $hist.alert.on -and $wl -gt $s.r.lo -and $wl -lt $s.r.hi) {
      $y = ($h - 2) * (1 - ($wl - $s.r.lo) / ($s.r.hi - $s.r.lo)) + 1
      $l = New-Object Windows.Shapes.Line; $l.X1 = 0; $l.X2 = $w; $l.Y1 = $y; $l.Y2 = $y; $l.Stroke = $warn; $l.StrokeThickness = 1; $l.Opacity = 0.6
      $l.StrokeDashArray = New-Object Windows.Media.DoubleCollection; $l.StrokeDashArray.Add(3); $l.StrokeDashArray.Add(3); [void]$c.Children.Add($l)
    }
    if ($has) {
      $shape = [Hist]::Shape($r, $k, $w, $h, $s.r.lo, $s.r.hi)
      foreach ($a in $shape[1]) { $p = New-Object Windows.Shapes.Polygon; $p.Fill = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb(0x30, $s.col.R, $s.col.G, $s.col.B)); $p.Points = [Windows.Media.PointCollection]::Parse($a); [void]$c.Children.Add($p) }
      foreach ($a in $shape[0]) { $p = New-Object Windows.Shapes.Polyline; $p.Stroke = New-Object Windows.Media.SolidColorBrush $s.col; $p.StrokeThickness = 1.4; $p.StrokeLineJoin = 'Round'; $p.Points = [Windows.Media.PointCollection]::Parse($a); [void]$c.Children.Add($p) }
    }
    foreach ($m in $marks) { & $vline $c (($m.At - $r.From).TotalSeconds / $span * $w) 0 $h $hot }
  }

  $when = { param($t) if ($t.Date -eq (Get-Date).Date) { $t.ToString('HH:mm:ss') } else { $t.ToString('ddd d MMM, HH:mm:ss') } }
  $hist.summary.Text = if ($r.Error) { "The recorded readings could not be read: $($r.Error)" }
  elseif ($r.Rows -eq 0) { 'Nothing was recorded in this time. The recorder runs from sign-in; the Activity page shows its state.' }
  else { "{0:N0} readings, from {1} to {2}. Read in {3:N0} ms.{4}" -f $r.Rows, (& $when $r.First), (& $when $r.Last), $r.Ms, $(if ($marks) { " $($marks.Count) unclean shutdown$(if ($marks.Count -ne 1) { 's' }) in this time, marked in red." }) }

  $hist.hottest.Children.Clear()
  foreach ($k in $alertNames.Keys) {
    $ser = $null; if ($r.Series.ContainsKey($k)) { $ser = $r.Series[$k] }
    $tb = X "<TextBlock VerticalAlignment='Center'/>"
    $tb.Text = if ($ser -and $ser.Count -gt 0) { "{0:N0} C at {1}, with {2} in front" -f $ser.Hi, (& $when $ser.HiAt), $(if ($ser.HiFront) { $ser.HiFront } else { 'nothing' }) } else { 'no readings in this time' }
    [void](Add-Row $hist.hottest $alertNames[$k] '' $tb)
  }
}
