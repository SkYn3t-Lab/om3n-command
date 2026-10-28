$games = @{ id = $(if ($gameDefs.Count) { @($gameDefs.Keys | Sort-Object)[0] } else { '' }); data = $null; panel = $null }
$gameCardTypicalW = 355

function Show-Games {
  Add-Title 'Games' 'Each game''s graphics settings as it keeps them on disk, the tuned set for this card, and a way back.'
  $row = X "<UniformGrid Columns='4' Margin='0,0,-12,2'/>"; [void]$Page.Children.Add($row)
  foreach ($id in @($gameDefs.Keys | Sort-Object)) {
    $r = X "<RadioButton Style='{DynamicResource Choice}' GroupName='game' Margin='0,0,12,12'><StackPanel><TextBlock x:Name='n' FontSize='16' FontWeight='SemiBold'/><TextBlock x:Name='d' Style='{DynamicResource Note}' Margin='0,4,0,0'/></StackPanel></RadioButton>"
    $r.FindName('n').Text = $gameDefs[$id].name; $r.FindName('d').Text = "Settings read from the game's own file. Process $($gameDefs[$id].process)."
    $r.Tag = $id; $r.IsChecked = ($games.id -eq $id)
    $r.Add_Click({ $games.id = $this.Tag; Show-GameDetail })
    [void]$row.Children.Add($r)
  }
  $script:gamePanel = X "<StackPanel/>"; [void]$Page.Children.Add($gamePanel); $games.panel = $gamePanel
  Show-GameDetail
}

function Show-GameDetail {
  if (-not $games.id) { return }
  $games.panel.Children.Clear()
  $bar = X "<StackPanel Orientation='Horizontal' Margin='0,0,0,10'/>"; [void]$games.panel.Children.Add($bar)
  $b = New-Button 'Apply the tuned set' { Start-Ctl "game $($games.id) -Action apply" { Show-GameDetail } 'Writing the tuned settings...' } -Primary; [void]$bar.Children.Add($b)
  $b = New-Button 'Revert' { Start-Ctl "game $($games.id) -Action revert" { Show-GameDetail } 'Putting the first-seen settings back...' }; [void]$bar.Children.Add($b)
  $b = New-Button 'Refresh' { Show-GameDetail }; [void]$bar.Children.Add($b)
  Start-Ctl "game $($games.id)" { param($l) try { $games.data = ($l -join "`n" | ConvertFrom-Json); Write-GameDetail } catch { Write-AppError 'reading the game settings' $_ } } 'Reading the game''s settings...'
}

$gameCols = "<Grid.ColumnDefinitions><ColumnDefinition Width='2*'/><ColumnDefinition Width='Auto' MinWidth='130'/><ColumnDefinition Width='Auto' MinWidth='130'/><ColumnDefinition Width='Auto' MinWidth='110'/></Grid.ColumnDefinitions>"

function Write-GameDetail {
  $d = $games.data; $p = $games.panel
  if (-not $d) { return }
  while ($p.Children.Count -gt 1) { $p.Children.RemoveAt(1) }
  if ($d.running) { Add-Note $p "$($d.name) is running. Apply and Revert wait until it is closed: the game rewrites its file when it exits." }

  $c = New-Category 'Where it is'; [void]$p.Children.Add($c.card)
  if (-not $d.files -or -not @($d.files).Count) { Add-Note $c.body "No settings file of $($d.name) was found on this PC. Start the game once; it writes the file on its first run." }
  foreach ($f in @($d.files)) {
    $t = X "<TextBlock FontSize='14' Margin='0,2'/>"; $t.Text = "$($f.copy): " + ($f.file -replace ('^' + [regex]::Escape($env:LOCALAPPDATA)), '%LOCALAPPDATA%'); [void]$c.body.Children.Add($t)
    $n = X "<TextBlock Style='{DynamicResource Note}' Margin='0,0,0,6'/>"
    $n.Text = $(if ($f.original) { 'A copy of this file as it was before the first Apply is kept; Revert writes those values back.' } else { 'Not changed by this app yet. The first Apply keeps a copy of the file as it is now, for Revert.' })
    [void]$c.body.Children.Add($n)
  }

  $c = New-Category 'Settings'; [void]$p.Children.Add($c.card)
  $copies = @($d.files | ForEach-Object { $_.copy })
  $head = X "<Grid Height='24' Margin='0,0,0,4'>$gameCols<TextBlock Style='{DynamicResource Note}' Text='Setting'/><TextBlock x:Name='c1' Grid.Column='1' Style='{DynamicResource Note}' TextAlignment='Right'/><TextBlock x:Name='c2' Grid.Column='2' Style='{DynamicResource Note}' TextAlignment='Right'/><TextBlock Grid.Column='3' Style='{DynamicResource Note}' TextAlignment='Right' Text='tuned'/></Grid>"
  $head.FindName('c1').Text = $(if ($copies.Count -ge 1) { $copies[0] } else { '' }); $head.FindName('c2').Text = $(if ($copies.Count -ge 2) { $copies[1] } else { '' })
  [void]$c.body.Children.Add($head)
  foreach ($k in @($d.keys)) {
    $row = X "<Border BorderBrush='{DynamicResource Line}' BorderThickness='0,0,0,1'><Grid Margin='0,5'>$gameCols<StackPanel VerticalAlignment='Center' Margin='0,0,12,0'><TextBlock x:Name='n' FontSize='14'/><TextBlock x:Name='d' Style='{DynamicResource Note}' TextWrapping='Wrap'/></StackPanel><TextBlock x:Name='v1' Grid.Column='1' Style='{DynamicResource Readout}' FontSize='14' TextAlignment='Right' VerticalAlignment='Center'/><TextBlock x:Name='v2' Grid.Column='2' Style='{DynamicResource Readout}' FontSize='14' TextAlignment='Right' VerticalAlignment='Center'/><TextBlock x:Name='t' Grid.Column='3' Style='{DynamicResource Readout}' FontSize='14' FontWeight='Normal' TextAlignment='Right' VerticalAlignment='Center'/></Grid></Border>"
    $row.FindName('n').Text = $k.k + $(if ($k.far) { '  (what you see far away)' } else { '' }); $row.FindName('d').Text = $k.d; $row.FindName('t').Text = $k.v
    $i = 1
    foreach ($f in @($d.files)) {
      if ($i -gt 2) { break }
      $tb = $row.FindName("v$i"); $cur = $f.values.($k.k)
      $tb.Text = $(if ($null -eq $cur) { '--' } else { "$cur" })
      if ("$cur" -ne $k.v) { $tb.Foreground = $win.FindResource('AccentText') }
      $i++
    }
    [void]$c.body.Children.Add($row)
  }
  Add-Note $c.body 'Quality groups run 0 Low, 1 Medium, 2 High, 3 Epic, 4 Cinematic. The settings marked (what you see far away) are the ones that end distant pop-in and show a player at range; the rest cost frames without changing what is visible at a distance, so they are the ones to lower first.'

  $c = New-Category 'By resolution'; [void]$p.Children.Add($c.card)
  if ($d.display -and $d.display.width) {
    $t = X "<TextBlock FontSize='14' Margin='0,2,0,6'/>"; $t.Text = "Your monitor is $($d.display.width) x $($d.display.height). What the game renders in each FSR mode, and the share of the native pixels:"; [void]$c.body.Children.Add($t)
    $fsrCols = "<Grid.ColumnDefinitions><ColumnDefinition Width='*'/><ColumnDefinition Width='Auto' MinWidth='150'/><ColumnDefinition Width='Auto' MinWidth='110'/></Grid.ColumnDefinitions>"
    foreach ($m in @($d.fsr)) {
      $row = X "<Border BorderBrush='{DynamicResource Line}' BorderThickness='0,0,0,1'><Grid Height='28'>$fsrCols<TextBlock x:Name='n' FontSize='14' VerticalAlignment='Center'/><TextBlock x:Name='r' Grid.Column='1' Style='{DynamicResource Readout}' FontSize='14' FontWeight='Normal' TextAlignment='Right' VerticalAlignment='Center'/><TextBlock x:Name='s' Grid.Column='2' Style='{DynamicResource Readout}' FontSize='14' FontWeight='Normal' TextAlignment='Right' VerticalAlignment='Center'/></Grid></Border>"
      $row.FindName('n').Text = $m.mode; $row.FindName('r').Text = "$($m.width) x $($m.height)"; $row.FindName('s').Text = "$($m.share) %"
      [void]$c.body.Children.Add($row)
    }
    Add-Note $c.body 'Frames follow the pixels rendered when the card is the limit. NativeAA is the sharpest at range; Quality keeps distant figures readable at well under half the pixels; Balanced and below soften them. The view distance, texture, landscape and foliage settings do not change with resolution: keep them as they are and move only the FSR mode.'
  } else { Add-Note $c.body 'The monitor''s resolution could not be read.' }
  if ($d.session) {
    $s = $d.session
    $t = X "<TextBlock FontSize='14' Margin='0,10,0,2'/>"; $t.Text = "Last session recorded: $($s.start), $($s.minutes) min. Card $($s.gpuW) W average ($($s.gpuWMax) W peak) at $($s.gpuLoad) % load, $($s.gpuMHz) MHz, hotspot up to $($s.gpuHot) C, video memory up to $($s.vramGB) GB. Processor $($s.cpuLoad) % load, up to $($s.cpuTemp) C."
    [void]$c.body.Children.Add($t)
    if ($s.fps -gt 0) { Add-Note $c.body "Frames: $($s.fps) a second on average, $($s.fpsMin) at the lowest second, the driver's own count." }
    if ($s.frameMs -gt 0) { Add-Note $c.body "Longest frame: $($s.frameMs) ms in a typical second, $($s.frameMsMax) ms at the worst; above 16 ms is a stutter you can see at 60 and more." }
    $verdict = $(if ($s.gpuLoad -ge 85 -and $s.gpuW -ge 0.8 * $gameCardTypicalW) { 'The card was working at its power limit: lowering settings that do not reduce pixels buys little. More frames come from a lighter FSR mode or a higher power limit (Graphics page).' }
      elseif ($s.gpuLoad -lt 70) { 'The card had room to spare: something else held the frame rate, the processor or the frame cap.' }
      else { 'The card was busy but under its power limit.' })
    Add-Note $c.body $verdict
  } else { Add-Note $c.body 'No session of this game in the recorder yet: play once with the recorder on and this shows what the card did.' }

  if ($d.notes) { $c = New-Category 'Notes'; [void]$p.Children.Add($c.card); foreach ($n in @($d.notes)) { Add-Note $c.body $n } }
}
