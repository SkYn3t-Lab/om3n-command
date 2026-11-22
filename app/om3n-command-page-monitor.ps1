function Add-MonitorMenuCards($panel, $cards) {
  $script:monCards = $cards
  $script:monHost = X "<StackPanel/>"; [void]$panel.Children.Add($monHost)
  [void]$monHost.Children.Add((X "<TextBlock Text='Reading the monitors&apos; own menus...' Style='{DynamicResource Note}' Margin='0,8,0,0'/>"))
  Start-Ctl 'monitor' {
    param($l)
    if ($state.page -ne 'Displays') { return }
    $monHost.Children.Clear()
    $data = $null
    try { $data = @((($l -join "`n") | ConvertFrom-Json) | ForEach-Object { $_ }) } catch { Write-AppError 'reading the monitor menus' $_; return }
    foreach ($m in $data) {
      $body = $null
      if ($m.serial -and $monCards -and $monCards.Contains("$($m.serial)")) {
        $body = $monCards["$($m.serial)"]
        $h = X "<TextBlock Style='{DynamicResource H2}' FontSize='14' Margin='0,12,0,2'/>"; $h.Text = 'Its own menu'; [void]$body.Children.Add($h)
      } else {
        $card = X "<Border Style='{DynamicResource Card}'><StackPanel/></Border>"; [void]$monHost.Children.Add($card); $body = $card.Child
        $h = X "<TextBlock Style='{DynamicResource H2}' Margin='0,0,0,2'/>"; $h.Text = "$($m.model): its own menu"; [void]$body.Children.Add($h)
      }
      Add-Note $body $(if ($m.omen) { 'What the joystick menu holds, read from the monitor through the display cable and written the same way. A change is read back from the monitor.' } else { 'The settings this monitor offers over the display cable. Its maker''s own settings are not published, so only the standard ones are here.' })
      foreach ($s in @($m.settings)) {
        $tag = @{ display = $m.index; id = $s.id }
        if ($s.error) { [void](Add-Row $body $s.label "Not answered: $($s.error)" (X "<TextBlock Text='--' Style='{DynamicResource Readout}'/>")); continue }
        if (-not $s.canSet) {
          $t = X "<TextBlock Style='{DynamicResource Readout}' FontSize='14'/>"; $t.Text = "$($s.display)"
          [void](Add-Row $body $s.label $s.note $t); continue
        }
        if ($s.kind -eq 'range') {
          $sl = New-Slider ([double]$s.min) ([double]$s.max) 1 ([double]$s.value) '' $tag { param($x) Start-Ctl "monitor -Display $($x.Tag.data.display) -Set $($x.Tag.data.id) -Value $([int]$x.Value)" $null 'Changing the monitor setting...' }
          [void](Add-Row $body $s.label $s.note $sl); continue
        }
        $choices = @($s.choices)
        if ($choices.Count -eq 2 -and ($choices | Where-Object { $_.label -eq 'Off' })) {
          $on = @($choices | Where-Object { $_.label -ne 'Off' })[0].value; $off = @($choices | Where-Object { $_.label -eq 'Off' })[0].value
          $tag.on = $on; $tag.off = $off
          $sw = New-Switch ($s.value -eq $on) $tag { Start-Ctl "monitor -Display $($this.Tag.display) -Set $($this.Tag.id) -Value $(if ($this.IsChecked) { $this.Tag.on } else { $this.Tag.off })" $null 'Changing the monitor setting...' }
          [void](Add-Row $body $s.label $s.note $sw); continue
        }
        $labels = @($choices | ForEach-Object { $_.label }); $tag.choices = $choices
        $cb = New-Combo $labels "$($s.display)" $tag {
          $pick = @($this.Tag.choices | Where-Object { $_.label -eq "$($this.SelectedItem)" })[0]
          if ($pick) { Start-Ctl "monitor -Display $($this.Tag.display) -Set $($this.Tag.id) -Value $($pick.value)" $null 'Changing the monitor setting...' }
        }
        [void](Add-Row $body $s.label $s.note $cb)
      }
    }
    if (-not $data.Count) { [void]$monHost.Children.Add((X "<TextBlock Text='No monitor answered over the cable. A monitor whose menu has DDC/CI off does not answer.' Style='{DynamicResource Note}'/>")) }
  } 'Reading the monitors'' own menus...' 90
}
