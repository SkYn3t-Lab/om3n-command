param([switch]$SelfTest, [string]$ShotDir = '', [switch]$Exercise, [int]$OffScreenSeconds = 0, [int]$ShotWidth = 0, [int]$ShotHeight = 0, [string]$ShotName = '', [int]$ShotWarmSeconds = 0, [double]$ShotScale = 1, [switch]$Tray)
$ErrorActionPreference = 'Stop'
$appLog = Join-Path $env:ProgramData 'SkYn3tLab\om3n-command-app.log'
function Write-AppLog([string[]]$lines) {
  try {
    $fs = New-Object IO.FileStream $appLog, ([IO.FileMode]::Append), ([IO.FileAccess]::Write), ([IO.FileShare]::ReadWrite), 4096, ([IO.FileOptions]::WriteThrough)
    try { $b = [Text.Encoding]::UTF8.GetBytes(($lines -join "`r`n") + "`r`n"); $fs.Write($b, 0, $b.Length); $fs.Flush($true) } finally { $fs.Close() }
  } catch { }
}
function Write-AppError([string]$where, $err) {
  Write-AppLog @(("{0:yyyy-MM-dd HH:mm:ss} APP ERROR ($where): $err" -f (Get-Date)), "  at: $($err.ScriptStackTrace -replace "`r?`n", ' <- ')", "  page: $($state.page)")
}
try { if (-not (Test-Path (Split-Path $appLog))) { New-Item -ItemType Directory -Path (Split-Path $appLog) | Out-Null }
  if ((Test-Path $appLog) -and (Get-Item $appLog).Length -gt 5MB) { Move-Item $appLog "$appLog.1" -Force } } catch { }
trap { Write-AppError 'the app stopped' $_; break }
$ctl = Join-Path $PSScriptRoot 'om3n-command.ps1'
if (-not (Test-Path $ctl)) { throw "om3n-command.ps1 must sit beside this file ($ctl not found)" }
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')
if ((-not $admin -or [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') -and -not $SelfTest) {
  Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
  return
}
$showEvent = $null
if (-not $SelfTest) {
  $created = $false
  $showEvent = New-Object Threading.EventWaitHandle $false, ([Threading.EventResetMode]::AutoReset), 'Local\Om3nCommand-show', ([ref]$created)
  if (-not $created) { [void]$showEvent.Set(); return }
}
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing
. (Join-Path $PSScriptRoot 'om3n-command-lib.ps1')
. (Join-Path $PSScriptRoot 'om3n-command-page-more.ps1')
Import-Dash
. (Join-Path $PSScriptRoot 'om3n-command-blackbox.ps1') -Library
[Dash]::LogCrashesTo($appLog)
[Dash]::Start(1000)

[xml]$shell = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Om3n Command" Width="1180" Height="800" MinWidth="1040" MinHeight="600" Background="#0B0714" Foreground="#EDE4E1"
        FontFamily="Bahnschrift" FontSize="14" WindowStartupLocation="CenterScreen">
  <Window.Resources>
    <SolidColorBrush x:Key="Panel" Color="#171026"/>
    <SolidColorBrush x:Key="Line" Color="#2A1F3D"/>
    <SolidColorBrush x:Key="Dim" Color="#A396AE"/>
    <SolidColorBrush x:Key="Accent" Color="#7B2FF7"/>
    <SolidColorBrush x:Key="Hot" Color="#E41D20"/>
    <SolidColorBrush x:Key="AccentText" Color="#A795D6"/>
    <SolidColorBrush x:Key="Danger" Color="#E41D20"/>
    <SolidColorBrush x:Key="Warn" Color="#FFB020"/>
    <SolidColorBrush x:Key="Ink" Color="#EDE4E1"/>
    <SolidColorBrush x:Key="AccentLight" Color="#B28DFF"/>
    <SolidColorBrush x:Key="Good" Color="#3DD68C"/>
    <SolidColorBrush x:Key="Zone-sys" Color="#A396AE"/>
    <Style x:Key="Readout" TargetType="TextBlock"><Setter Property="FontStretch" Value="SemiCondensed"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="FontSize" Value="21"/></Style>
    <Style x:Key="Group" TargetType="TextBlock"><Setter Property="FontSize" Value="16"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Foreground" Value="#C4B5C9"/><Setter Property="Margin" Value="0,22,0,4"/></Style>
    <Style TargetType="TextBlock"><Setter Property="TextWrapping" Value="Wrap"/></Style>
    <Style x:Key="H1" TargetType="TextBlock"><Setter Property="FontSize" Value="30"/><Setter Property="FontWeight" Value="Bold"/><Setter Property="FontStretch" Value="Condensed"/><Setter Property="Margin" Value="0,0,0,4"/></Style>
    <Style x:Key="Sub" TargetType="TextBlock"><Setter Property="Foreground" Value="{StaticResource Dim}"/><Setter Property="Margin" Value="0,0,0,18"/><Setter Property="TextWrapping" Value="Wrap"/></Style>
    <Style x:Key="H2" TargetType="TextBlock"><Setter Property="FontSize" Value="15.5"/><Setter Property="FontWeight" Value="SemiBold"/></Style>
    <Style x:Key="Note" TargetType="TextBlock"><Setter Property="Foreground" Value="{StaticResource Dim}"/><Setter Property="FontSize" Value="12.5"/><Setter Property="TextWrapping" Value="Wrap"/></Style>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="Transparent"/><Setter Property="BorderBrush" Value="{StaticResource Line}"/><Setter Property="BorderThickness" Value="0,1,0,0"/>
      <Setter Property="CornerRadius" Value="0"/><Setter Property="Padding" Value="0,14,0,10"/><Setter Property="Margin" Value="0,0,0,8"/>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#EDE4E1"/><Setter Property="Background" Value="#2A1F3D"/><Setter Property="Padding" Value="14,7"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="7" Padding="{TemplateBinding Padding}">
          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.82"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
        </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}"><Setter Property="Background" Value="{StaticResource Accent}"/></Style>
    <Style x:Key="Nav" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#C4B5C9"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FontSize" Value="14"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton">
        <Grid Margin="0,1"><Border x:Name="b" Background="Transparent" Padding="24,9,14,9"><ContentPresenter/></Border>
          <Border x:Name="bar" Width="3" HorizontalAlignment="Left" Background="Transparent"/></Grid>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#181226"/></Trigger>
          <Trigger Property="IsChecked" Value="True"><Setter TargetName="bar" Property="Background" Value="#E41D20"/><Setter TargetName="b" Property="Background" Value="#160F2A"/><Setter Property="Foreground" Value="#ffffff"/></Trigger>
        </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Seg" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#EDE4E1"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Margin" Value="0,0,6,0"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton">
        <Border x:Name="b" Background="#171026" BorderBrush="#2A1F3D" BorderThickness="1" CornerRadius="4" Padding="14,6"><ContentPresenter/></Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#5E4590"/></Trigger>
          <Trigger Property="IsChecked" Value="True"><Setter TargetName="b" Property="Background" Value="#7B2FF7"/><Setter TargetName="b" Property="BorderBrush" Value="#7B2FF7"/></Trigger>
        </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Choice" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#EDE4E1"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Margin" Value="0,0,12,0"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RadioButton">
        <Border x:Name="b" Background="{StaticResource Panel}" BorderBrush="{StaticResource Line}" BorderThickness="2" CornerRadius="10" Padding="16,14" MinHeight="96">
          <ContentPresenter/></Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#5E4590"/></Trigger>
          <Trigger Property="IsChecked" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="{StaticResource Accent}"/><Setter TargetName="b" Property="Background" Value="#1C1238"/></Trigger>
        </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Switch" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox">
        <Grid Width="46" Height="24">
          <Border x:Name="t" Background="#352A4D" CornerRadius="12"/>
          <Ellipse x:Name="k" Width="18" Height="18" Fill="#ffffff" HorizontalAlignment="Left" Margin="3,0,0,0"/>
        </Grid>
        <ControlTemplate.Triggers>
          <Trigger Property="IsChecked" Value="True"><Setter TargetName="t" Property="Background" Value="{StaticResource Accent}"/><Setter TargetName="k" Property="HorizontalAlignment" Value="Right"/><Setter TargetName="k" Property="Margin" Value="0,0,3,0"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>
        </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Foreground" Value="#EDE4E1"/><Setter Property="MinWidth" Value="140"/><Setter Property="Height" Value="30"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBox">
        <Grid>
          <ToggleButton Focusable="False" ClickMode="Press" IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
            <ToggleButton.Template><ControlTemplate TargetType="ToggleButton">
              <Border x:Name="bd" Background="#171026" BorderBrush="#2A1F3D" BorderThickness="1" CornerRadius="4">
                <Path HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,10,0" Data="M0,0 L4,4 L8,0" Stroke="#C4B5C9" StrokeThickness="1.5"/></Border>
              <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="BorderBrush" Value="#5E4590"/></Trigger></ControlTemplate.Triggers>
            </ControlTemplate></ToggleButton.Template>
          </ToggleButton>
          <ContentPresenter IsHitTestVisible="False" Margin="10,0,28,0" VerticalAlignment="Center" Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"/>
          <Popup x:Name="PART_Popup" IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True" Focusable="False">
            <Border Background="#171026" BorderBrush="#5E4590" BorderThickness="1" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}" MaxHeight="320">
              <ScrollViewer><ItemsPresenter/></ScrollViewer></Border>
          </Popup>
        </Grid>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#EDE4E1"/><Setter Property="Padding" Value="10,6"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBoxItem">
        <Border x:Name="b" Background="Transparent" Padding="{TemplateBinding Padding}"><ContentPresenter/></Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="b" Property="Background" Value="#2A1F3D"/></Trigger>
          <Trigger Property="IsSelected" Value="True"><Setter Property="Foreground" Value="#A795D6"/></Trigger>
        </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="10"/><Setter Property="MinWidth" Value="10"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar">
        <Grid Background="Transparent"><Track x:Name="PART_Track" Orientation="{TemplateBinding Orientation}" IsDirectionReversed="True">
          <Track.Thumb><Thumb><Thumb.Template><ControlTemplate><Border Background="#352A4D" CornerRadius="4" Margin="2"/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
        </Track></Grid>
        <ControlTemplate.Triggers><Trigger Property="Orientation" Value="Horizontal"><Setter TargetName="PART_Track" Property="IsDirectionReversed" Value="False"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
      <Style.Triggers><Trigger Property="Orientation" Value="Horizontal"><Setter Property="Width" Value="Auto"/><Setter Property="MinWidth" Value="0"/><Setter Property="Height" Value="10"/></Trigger></Style.Triggers>
    </Style>
    <Style TargetType="Slider">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Slider">
        <Grid Height="22">
          <Border Height="3" Background="#2A1F3D" CornerRadius="1.5"/>
          <Track x:Name="PART_Track">
            <Track.DecreaseRepeatButton><RepeatButton Command="Slider.DecreaseLarge" Focusable="False"><RepeatButton.Template><ControlTemplate><Border Height="3" Background="#B28DFF" CornerRadius="1.5"/></ControlTemplate></RepeatButton.Template></RepeatButton></Track.DecreaseRepeatButton>
            <Track.IncreaseRepeatButton><RepeatButton Command="Slider.IncreaseLarge" Focusable="False"><RepeatButton.Template><ControlTemplate><Border Background="Transparent"/></ControlTemplate></RepeatButton.Template></RepeatButton></Track.IncreaseRepeatButton>
            <Track.Thumb><Thumb><Thumb.Template><ControlTemplate><Ellipse Width="16" Height="16" Fill="#EDE4E1" Stroke="#B28DFF" StrokeThickness="2"/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
          </Track>
        </Grid>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style TargetType="TextBox"><Setter Property="Background" Value="#07050B"/><Setter Property="Foreground" Value="#EDE4E1"/><Setter Property="BorderBrush" Value="{StaticResource Line}"/><Setter Property="Padding" Value="6,4"/><Setter Property="CaretBrush" Value="#ffffff"/></Style>
  </Window.Resources>
  <Grid Background="#0B0714">
    <Grid.ColumnDefinitions><ColumnDefinition Width="200"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <Border Grid.RowSpan="2" Background="#07050B" BorderBrush="{StaticResource Line}" BorderThickness="0,0,1,0">
      <Grid>
        <Image x:Name="Figure" VerticalAlignment="Bottom" Stretch="Uniform" IsHitTestVisible="False" Opacity="0.9"/>
        <StackPanel Margin="0,18,0,0">
          <Image x:Name="Wordmark" Width="150" HorizontalAlignment="Left" Margin="24,2,0,8"/>
          <StackPanel x:Name="WordText">
            <TextBlock FontSize="34" FontWeight="Bold" FontStretch="Condensed" Margin="24,0,0,0"><Run Text="Om"/><Run Text="3" Foreground="#E41D20"/><Run Text="n"/></TextBlock>
            <TextBlock Text="Command" FontSize="15" FontStretch="SemiCondensed" Foreground="#C4B5C9" Margin="25,-6,0,0"/>
          </StackPanel>
          <TextBlock x:Name="HostName" Foreground="{StaticResource AccentText}" FontSize="12" Margin="25,2,0,10"/>
          <StackPanel x:Name="Lights" Orientation="Horizontal" Margin="25,0,0,22" Height="4"/>
          <StackPanel x:Name="Nav"/>
        </StackPanel>
      </Grid>
    </Border>
    <ScrollViewer Grid.Column="1" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="Page" Margin="28,22,28,22"/></ScrollViewer>
    <Border Grid.Column="1" Grid.Row="1" Background="#07050B" BorderBrush="{StaticResource Line}" BorderThickness="0,1,0,0" Padding="28,7">
      <TextBlock x:Name="Busy" Foreground="{StaticResource Dim}" FontSize="12.5" Text="Ready"/>
    </Border>
  </Grid>
</Window>
'@
$win = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $shell))
function Get-Art([string]$name) {
  $f = Join-Path (Split-Path $PSScriptRoot) "assets\$name"; if (-not (Test-Path $f)) { return }
  $b = New-Object Windows.Media.Imaging.BitmapImage; $b.BeginInit(); $b.CacheOption = 'OnLoad'; $b.UriSource = New-Object Uri $f; $b.EndInit(); $b.Freeze(); $b
}
try {
  $a = Get-Art 'om3n-command-wordmark.png'; if ($a) { $win.FindName('Wordmark').Source = $a; $win.FindName('WordText').Visibility = 'Collapsed' }
  $a = Get-Art 'om3n-command-figure.png'; if ($a) { $win.FindName('Figure').Source = $a }
} catch { }
Add-Type -Namespace Om3n -Name Dwm -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);'
$win.Add_SourceInitialized({
    try {
      $h = (New-Object Windows.Interop.WindowInteropHelper $win).Handle
      foreach ($a in @(@(20, 1), @(34, 0x003D1F2A), @(35, 0x000B0507), @(36, 0x00E1E4ED))) { $v = [int]$a[1]; [void][Om3n.Dwm]::DwmSetWindowAttribute($h, $a[0], [ref]$v, 4) }
    } catch { }
  })
$Nav = $win.FindName('Nav'); $Page = $win.FindName('Page'); $Busy = $win.FindName('Busy')
$win.FindName('HostName').Text = if ($ShotName) { $ShotName } else { [Net.Dns]::GetHostName() }
$iconFile = Join-Path (Split-Path $PSScriptRoot) 'assets\om3n-command.ico'
$iconBytes = if (Test-Path $iconFile) { [IO.File]::ReadAllBytes($iconFile) }
if ($iconBytes) { $win.Icon = [Windows.Media.Imaging.BitmapFrame]::Create((New-Object IO.MemoryStream (, $iconBytes)), [Windows.Media.Imaging.BitmapCreateOptions]::None, [Windows.Media.Imaging.BitmapCacheOption]::OnLoad) }
$activity = New-Object Text.StringBuilder
$win.Dispatcher.Add_UnhandledException({
    param($sender, $e)
    $err = if ($e.Exception.ErrorRecord) { $e.Exception.ErrorRecord } else { $e.Exception }
    Write-AppError 'a control or timer' $err
    $e.Handled = $true
    $Busy.Text = "The app hit an error and carried on: $($e.Exception.Message)   (kept in the log; Activity page, Open the log folder)"; $Busy.Foreground = $win.FindResource('Hot')
  })
$state = @{ fan = (Get-FanSelection); page = 'Home' }

function X([string]$xaml) {
  [Windows.Markup.XamlReader]::Parse(($xaml -replace '^\s*<(\w+)', '<$1 xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'))
}
function New-Category([string]$title) {
  $c = X "<Border Background='{DynamicResource Panel}' BorderBrush='{DynamicResource Line}' BorderThickness='1' CornerRadius='6' Padding='14,10,14,6' Margin='0,0,0,14'><StackPanel><StackPanel Orientation='Horizontal' Margin='0,0,0,6'><Border Width='3' Height='16' CornerRadius='1.5' Background='{DynamicResource Accent}' Margin='0,0,9,0' VerticalAlignment='Center'/><TextBlock x:Name='h' FontSize='17' FontWeight='SemiBold' Foreground='{DynamicResource Ink}'/></StackPanel><StackPanel x:Name='b'/></StackPanel></Border>"
  $c.FindName('h').Text = $title
  @{ card = $c; body = $c.FindName('b') }
}
function Add-Title([string]$title, [string]$sub) {
  $Page.Children.Clear()
  $h = X "<TextBlock Style='{DynamicResource H1}'/>"; $h.Text = $title; [void]$Page.Children.Add($h)
  $s = X "<TextBlock Style='{DynamicResource Sub}'/>"; $s.Text = $sub; [void]$Page.Children.Add($s)
}
function Add-Card { $c = X "<Border Style='{DynamicResource Card}'><StackPanel/></Border>"; [void]$Page.Children.Add($c); $c.Child }
function Add-Row($panel, [string]$name, [string]$note, $control) {
  $g = X "<Grid Margin='0,6'><Grid.ColumnDefinitions><ColumnDefinition Width='*'/><ColumnDefinition Width='Auto'/></Grid.ColumnDefinitions><StackPanel VerticalAlignment='Center' Margin='0,0,18,0'><TextBlock x:Name='n' FontSize='14'/><TextBlock x:Name='d' Style='{DynamicResource Note}'/></StackPanel></Grid>"
  $g.FindName('n').Text = $name; $d = $g.FindName('d'); $d.Text = $note; if (-not $note) { $d.Visibility = 'Collapsed' }
  [Windows.Controls.Grid]::SetColumn($control, 1); $control.VerticalAlignment = 'Center'; [void]$g.Children.Add($control)
  [void]$panel.Children.Add($g); $g
}
function New-Switch([bool]$on, $tag, [scriptblock]$onClick) {
  $s = X "<CheckBox Style='{DynamicResource Switch}'/>"; $s.IsChecked = $on; $s.Tag = $tag; $s.Add_Click($onClick); $s
}
function New-Slider([double]$min, [double]$max, [double]$step, [double]$value, [string]$unit, $tag, [scriptblock]$onRelease) {
  $p = X "<StackPanel Orientation='Horizontal'><Slider x:Name='s' Width='230' IsSnapToTickEnabled='True' VerticalAlignment='Center'/><TextBlock x:Name='v' Width='78' TextAlignment='Right' VerticalAlignment='Center' FontWeight='SemiBold'/></StackPanel>"
  $s = $p.FindName('s'); $v = $p.FindName('v')
  $s.Minimum = $min; $s.Maximum = $max; $s.TickFrequency = $step; $s.SmallChange = $step; $s.LargeChange = $step; $s.Value = $value
  $s.Tag = @{ data = $tag; label = $v; unit = $unit; last = $value; action = $onRelease }
  $v.Text = "$value$unit"
  $s.Add_ValueChanged({ $this.Tag.label.Text = "$([Math]::Round($this.Value, 1))$($this.Tag.unit)" })
  $apply = { if ($this.Tag.last -ne $this.Value) { $this.Tag.last = $this.Value; & $this.Tag.action $this } }
  $s.Add_LostMouseCapture($apply); $s.Add_KeyUp($apply)
  $p
}
function Set-SliderValue($panel, [double]$v) {
  $s = $panel.FindName('s'); $s.Value = [Math]::Min($s.Maximum, [Math]::Max($s.Minimum, $v)); $s.Tag.last = $s.Value; $panel.IsEnabled = $true
}
function Set-ShotNeutral {
  if ($state.page -eq 'Home' -and $facts -and $facts.up) { $facts.up.Text = '2h 30m' }
  $todo = New-Object Collections.Stack; $todo.Push($win.Content)
  while ($todo.Count) {
    $e = $todo.Pop()
    if ($e -is [Windows.Controls.TextBlock] -or $e -is [Windows.Controls.TextBox]) {
      $t = "$($e.Text)"
      $u = $t -replace '(Monitor \d+): .+$', '$1' -replace '(?m)^(\s*display \d+: ).*?(\s+\(adapter)', '${1}Monitor$2'
      if ($u -cne $t) { $e.Text = $u }
    }
    for ($i = 0; $i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($e); $i++) { $todo.Push([Windows.Media.VisualTreeHelper]::GetChild($e, $i)) }
  }
}
function New-Combo([string[]]$items, [string]$selected, $tag, [scriptblock]$onChange) {
  $c = New-Object Windows.Controls.ComboBox; foreach ($i in $items) { [void]$c.Items.Add($i) }
  $c.SelectedItem = $(if ($items -contains $selected) { $selected } else { $items[0] }); $c.Tag = $tag
  if ($onChange) { $c.Add_SelectionChanged($onChange) }
  $c
}
function New-Button([string]$text, [scriptblock]$onClick, [switch]$Primary) {
  $b = X "<Button Margin='0,0,8,0'/>"; $b.Content = $text; if ($Primary) { $b.Style = $win.FindResource('Primary') }; $b.Add_Click($onClick); $b
}
function Add-Note($panel, [string]$text) { $t = X "<TextBlock Style='{DynamicResource Note}' Margin='0,6,0,0'/>"; $t.Text = $text; [void]$panel.Children.Add($t) }

$jobs = New-Object Collections.ArrayList
function Start-Ctl([string]$arguments, [scriptblock]$done, [string]$doing, [int]$limitSec = 60, [string]$File = '') {
  $run = if ($File) { Join-Path $PSScriptRoot $File } else { $script:ctl }
  $si = New-Object Diagnostics.ProcessStartInfo 'powershell.exe', "-NoProfile -ExecutionPolicy Bypass -File `"$run`" $arguments"
  $si.UseShellExecute = $false; $si.CreateNoWindow = $true; $si.RedirectStandardOutput = $true; $si.RedirectStandardError = $true
  $p = [Diagnostics.Process]::Start($si)
  $j = @{ p = $p; out = $p.StandardOutput.ReadToEndAsync(); err = $p.StandardError.ReadToEndAsync(); done = $done; args = $arguments; started = Get-Date; limit = $limitSec; name = $(if ($File) { $File -replace '\.ps1$', '' } else { 'om3n-command' }) }
  [void]$jobs.Add($j)
  $Busy.Text = $(if ($doing) { $doing } else { 'Working...' }); $Busy.Foreground = $win.FindResource('AccentText')
  $script:lastJob = $j
}
function Complete-Jobs {
  foreach ($j in @($jobs)) {
    $timedOut = $false
    if (-not $j.p.HasExited) {
      if (((Get-Date) - $j.started).TotalSeconds -lt $j.limit) { continue }
      try { $j.p.Kill() } catch { }
      $timedOut = $true
    } elseif (-not $j.out.IsCompleted) { continue }
    $jobs.Remove($j)
    $raw = if ($j.out.IsCompleted) { $j.out.Result } else { '' }
    $errText = if ($j.err.IsCompleted) { $j.err.Result } else { '' }
    $lines = @(($raw + "`n" + $errText) -split "`r?`n" | Where-Object { $_.Trim() })
    $code = if ($timedOut) { -1 } else { $j.p.ExitCode }
    $ms = [int]((Get-Date) - $j.started).TotalMilliseconds
    $shown = if ($j.args -like 'state*' -and $code -eq 0) { @("(state document, $($raw.Length) characters)") } else { $lines }
    $entry = @("{0:yyyy-MM-dd HH:mm:ss} > $($j.name) $($j.args)   [exit $code, $ms ms]" -f (Get-Date)) + @($shown | ForEach-Object { "  $_" })
    foreach ($l in $entry) { [void]$activity.AppendLine($l) }; [void]$activity.AppendLine()
    Write-AppLog $entry
    $bad = $null
    if ($timedOut) { $bad = "it was still running after $($j.limit) s and was stopped" }
    elseif ($code -ne 0) {
      $own = @(foreach ($l in $lines) { if ($l -match '^--- lines the service logged') { break }; $l })
      $bad = $own | Where-Object { $_ -cmatch 'ABORT|FAILED|REFUSED|general=' } | Select-Object -First 1
      if (-not $bad) { $bad = @($errText -split "`r?`n" | Where-Object { $_.Trim() })[0] }
      if (-not $bad) { $bad = "exit code $code" }
    }
    if ($jobs.Count -eq 0) {
      if ($bad) { $Busy.Text = "That did not work: $("$bad".Trim())   (details on the Activity page)"; $Busy.Foreground = $win.FindResource('Hot') }
      else { $Busy.Text = 'Done'; $Busy.Foreground = $win.FindResource('Dim') }
    }
    if ($j.switch) { $t = $lines -join ' '; $j.switch.IsChecked = ($t -match 'supported=1 (on|value)=1'); $j.switch.IsEnabled = ($t -match 'supported=1') }
    if ($j.done) { & $j.done $lines $raw ($code -eq 0) $j }
  }
}
$timer = New-Object Windows.Threading.DispatcherTimer; $timer.Interval = [TimeSpan]::FromMilliseconds(150); $timer.Add_Tick({
    Complete-Jobs
    if ($showEvent -and $showEvent.WaitOne(0)) { Show-Window }
    Invoke-HoldEvents
  }); $timer.Start()
function Show-Window { Write-AppLog ("{0:yyyy-MM-dd HH:mm:ss} WINDOW SHOWN (the icon was clicked, or the app was started again)" -f (Get-Date)); $win.Show(); if ($win.WindowState -eq 'Minimized') { $win.WindowState = 'Normal' }; [void]$win.Activate(); $win.Topmost = $true; $win.Topmost = $false }

function Read-State([string]$part = '', [scriptblock]$then) {
  Start-Ctl ("state $part").Trim() {
    param($lines, $raw, $ok, $job)
    if ($ok) {
      try {
        $s = $raw | ConvertFrom-Json
        if (-not $state.s) { $state.s = $s }
        else { foreach ($p in $s.PSObject.Properties) { $state.s | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force } }
        $state.sAt = Get-Date
        if ($s.errors) { $Busy.Text = "Could not read: $($s.errors -join '; ')"; $Busy.Foreground = $win.FindResource('Hot') }
      } catch { Write-AppError 'reading the state document' $_ }
    }
    Update-Home
    if ($job.then) { & $job.then $ok }
  } 'Reading the settings...'
  $lastJob.then = $then
}
function Read-Cpu { Read-State 'cpu' }
function Read-Gpu { Read-State 'gpu' }
function Get-Cpu([string]$id) { if ($state.s -and $state.s.cpu -and $state.s.cpu.$id) { $state.s.cpu.$id.active } }
function Get-GpuSetting([string]$name) { if ($state.s -and $state.s.gpu -and $state.s.gpu.settings.$name) { $state.s.gpu.settings.$name } }

function Show-Home {
  Add-Title 'Home' 'Live, every second. Each line is the last three minutes. Every reading drawn here is also written to the log.'
  $script:heldBar = X "<Border BorderBrush='{DynamicResource Warn}' BorderThickness='1' Background='{DynamicResource Panel}' Padding='16,12' Margin='0,0,0,18' Visibility='Collapsed'><StackPanel><TextBlock x:Name='T' TextWrapping='Wrap' Margin='0,0,0,10'/><StackPanel x:Name='B' Orientation='Horizontal'/></StackPanel></Border>"
  $script:heldText = $heldBar.FindName('T'); $hb = $heldBar.FindName('B')
  [void]$hb.Children.Add((New-Button 'Put it back now' { Start-Ctl 'startup restore' { Read-State } 'Putting the undervolt back...' } -Primary))
  [void]$hb.Children.Add((New-Button 'Take it off the sign-in list' { Start-Ctl 'startup drop' { Read-State } 'Taking the undervolt off the sign-in list...' }))
  [void]$Page.Children.Add($heldBar)
  $script:homeGrid = X "<Grid><Grid.ColumnDefinitions><ColumnDefinition Width='2*'/><ColumnDefinition Width='44'/><ColumnDefinition Width='*'/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition Height='Auto'/><RowDefinition Height='Auto'/></Grid.RowDefinitions><StackPanel x:Name='L' VerticalAlignment='Top'/><StackPanel x:Name='R' VerticalAlignment='Top' Grid.Column='2'/></Grid>"
  [void]$Page.Children.Add($homeGrid)
  $readCol = $homeGrid.FindName('L'); $sideCol = $homeGrid.FindName('R')

  $rows = @(
    @{ g = 'Processor' },
    @{ k = 'cpuTemp'; n = 'Temperature'; f = '{0:N0} C'; lo = 30; hi = 100; c = 'cpu'; warn = 80; hot = 90; d = { 'slows itself down at 100 C' } },
    @{ k = 'cpuLoad'; n = 'Load'; f = '{0:N0} %'; lo = 0; hi = 100; c = 'cpu'; d = { 'running at ' + (& $n 'cpuMHz' '{0:N0} MHz') } },
    @{ k = 'cpuW'; n = 'Power'; f = '{0:N0} W'; lo = 0; hi = 180; c = 'cpu'; warn = 125; hot = 170; d = { 'cores ' + (& $n 'coresW' '{0:N0} W') + ', memory ' + (& $n 'dramW' '{0:N1} W') } },
    @{ g = 'Graphics' },
    @{ k = 'gpuTemp'; n = 'Temperature'; f = '{0:N0} C'; lo = 30; hi = 100; c = 'gpu'; warn = 85; hot = 95; d = { 'edge of the chip' } },
    @{ k = 'gpuHot'; n = 'Hotspot'; f = '{0:N0} C'; lo = 30; hi = 110; c = 'gpu'; warn = 95; hot = 105; d = { 'hottest point on the chip' } },
    @{ k = 'gpuMemTemp'; n = 'Memory temperature'; f = '{0:N0} C'; lo = 30; hi = 105; c = 'gpu'; warn = 90; hot = 100; d = { 'the graphics memory chips' } },
    @{ k = 'gpuLoad'; n = 'Load'; f = '{0:N0} %'; lo = 0; hi = 100; c = 'gpu'; d = { 'core ' + (& $n 'gpuMHz' '{0:N0} MHz') + ', memory ' + (& $n 'gpuMemMHz' '{0:N0} MHz') } },
    @{ k = 'gpuW'; n = 'Power'; f = '{0:N0} W'; lo = 0; hi = 400; c = 'gpu'; warn = 355; hot = 400; d = { 'fan ' + (& $n 'gpuFanRpm' '{0:N0} rpm') + ', ' + (& $n 'gpuFanPct' '{0:N0} %') } },
    @{ k = 'vramGB'; n = 'Memory in use'; f = '{0:N1} GB'; lo = 0; hi = 24; c = 'gpu'; warn = 20.4; hot = 22.8; d = { 'of 24 GB' } },
    @{ g = 'System' },
    @{ k = 'memUsedGB'; n = 'Memory in use'; f = '{0:N1} GB'; lo = 0; hi = ([Dash]::TotalMemMB / 1024); c = 'sys'; warn = ([Dash]::TotalMemMB / 1024 * 0.85); hot = ([Dash]::TotalMemMB / 1024 * 0.95); d = { 'of ' + ('{0:N1} GB' -f ([Dash]::TotalMemMB / 1024)) } },
    @{ k = 'netInMbit'; n = 'Download'; f = '{0:N1} Mbit/s'; lo = 0; hi = 0; c = 'sys'; d = { 'upload ' + (& $n 'netOutMbit' '{0:N1} Mbit/s') } },
    @{ k = 'diskMB'; n = 'Drive activity'; f = '{0:N1} MB/s'; lo = 0; hi = 0; c = 'sys'; d = { 'read ' + (& $n 'diskReadMB' '{0:N1}') + ', write ' + (& $n 'diskWriteMB' '{0:N1} MB/s') } }
  )
  $script:strips = New-Object Collections.ArrayList
  $homeCols = "<Grid.ColumnDefinitions><ColumnDefinition Width='170'/><ColumnDefinition Width='34'/><ColumnDefinition Width='*'/><ColumnDefinition Width='112'/><ColumnDefinition Width='240'/></Grid.ColumnDefinitions>"
  $script:homeAxes = @()
  foreach ($where in 'Bottom', 'Top') {
    $ax = X "<Grid Height='20' Margin='15,0,15,0'>$homeCols<Canvas x:Name='c' Grid.Column='2'/></Grid>"; $script:homeAxes += @{ c = $ax.FindName('c'); w = 0; at = $where }
    if ($where -eq 'Bottom') { [void]$readCol.Children.Add($ax) } else { $script:homeAxisEnd = $ax }
  }
  foreach ($r in $rows) {
    if ($r.g) { $cat = New-Category $r.g; [void]$readCol.Children.Add($cat.card); continue }
    $row = X "<Border BorderBrush='{DynamicResource Line}' BorderThickness='0,0,0,1'><Grid Height='46'>$homeCols<TextBlock x:Name='n' VerticalAlignment='Center' FontSize='14'/><TextBlock x:Name='hi' Grid.Column='1' Style='{DynamicResource Note}' FontSize='10.5' TextAlignment='Right' VerticalAlignment='Top' Margin='0,1,6,0'/><TextBlock x:Name='lo' Grid.Column='1' Style='{DynamicResource Note}' FontSize='10.5' TextAlignment='Right' VerticalAlignment='Bottom' Margin='0,0,6,1'/><Border Grid.Column='2' Margin='0,5' BorderBrush='{DynamicResource Line}' BorderThickness='1,0,0,1'/><Canvas x:Name='c' Grid.Column='2' Margin='0,5' ClipToBounds='True'><Canvas x:Name='t'/><Line x:Name='w' Stroke='{DynamicResource Warn}' StrokeThickness='1' Opacity='0.6' StrokeDashArray='3 3' Visibility='Collapsed'/><Polygon x:Name='a'/><Polyline x:Name='p' StrokeThickness='1.4' StrokeLineJoin='Round'/></Canvas><TextBlock x:Name='v' Grid.Column='3' Style='{DynamicResource Readout}' TextAlignment='Right' VerticalAlignment='Center' Text='--'/><TextBlock x:Name='s' Grid.Column='4' Style='{DynamicResource Note}' Margin='18,0,0,0' VerticalAlignment='Center' TextWrapping='NoWrap' TextTrimming='CharacterEllipsis'/></Grid></Border>"
    $row.FindName('hi').Text = $(if ($r.hi -gt $r.lo) { "$([int]$r.hi)" } else { '' }); $row.FindName('lo').Text = "$([int]$r.lo)"
    $row.FindName('n').Text = $r.n
    $col = $win.FindResource('Zone-sys').Color
    $p = $row.FindName('p'); $p.Stroke = New-Object Windows.Media.SolidColorBrush $col
    $a = $row.FindName('a'); $a.Fill = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb(0x30, $col.R, $col.G, $col.B))
    [void]$strips.Add(@{ r = $r; v = $row.FindName('v'); s = $row.FindName('s'); c = $row.FindName('c'); p = $p; a = $a; col = $col; t = $row.FindName('t'); w = $row.FindName('w'); hi = $row.FindName('hi'); tw = ''; g = $row.Child })
    [void]$cat.body.Children.Add($row)
  }
  [void]$readCol.Children.Add($homeAxisEnd)

  $h = X "<TextBlock Style='{DynamicResource Group}' Text='Controls' Margin='0,0,0,8'/>"; [void]$sideCol.Children.Add($h)
  $seg = X "<StackPanel Orientation='Horizontal'/>"; $script:homeFan = @{}
  foreach ($f in @(@('quiet', 'Quiet'), @('normal', 'Balanced'), @('turbo', 'Performance'), @('auto', 'Om3n'))) {
    $r = X "<RadioButton Style='{DynamicResource Seg}' GroupName='homefan'/>"; $r.Content = $f[1]; $r.Tag = $f[0]; $r.IsChecked = ($state.fan -eq $f[0])
    $r.Add_Click({ $state.fan = $this.Tag; Start-Ctl "fan $($this.Tag)" $null 'Changing the fan setting...' })
    $script:homeFan[$f[0]] = $r; [void]$seg.Children.Add($r)
  }
  Add-Field $sideCol 'Case fans' '' $seg
  $script:homeCpuUv = New-Slider -150 0 5 0 ' mV' $null { param($sl) Start-Ctl "cpu -ControlId 0x22 -Value $([int]$sl.Value)" { param($r) if ("$r" -match 'ApplyChanges -> general=Success') { Read-Cpu; Save-Startup ([int]$homeCpuUv.FindName('s').Value) } } 'Changing the processor undervolt...' }
  $homeCpuUv.IsEnabled = $false
  Add-Field $sideCol 'Processor undervolt' 'Lower runs cooler. Too low crashes the PC; a restart puts it back at 0.' $homeCpuUv
  $script:homeGpuV = New-Slider 1000 1150 5 1150 ' mV' $null { param($sl) Start-Ctl "gpu -Setting OD_VOLTAGE -Value $([int]$sl.Value)" { param($r) & $gpuVoltDone $r; Read-Gpu } 'Setting the graphics voltage...' }
  $homeGpuV.IsEnabled = $false
  Add-Field $sideCol 'Graphics voltage' 'Stock is 1150 mV. Lower runs cooler; too low makes games crash.' $homeGpuV

  $h = X "<TextBlock Style='{DynamicResource Group}' Text='Graphics card fan'/>"; [void]$sideCol.Children.Add($h)
  $pseg = X "<StackPanel Orientation='Horizontal' Margin='0,0,0,8'/>"; $script:fanProfileButtons = @{}
  foreach ($p in @(@('card', 'Automatic'), @('amd', 'AMD'), @('smart', 'Om3n'))) {
    $b = X "<RadioButton Style='{DynamicResource Seg}' GroupName='gpufan'/>"; $b.Content = $p[1]; $b.Tag = $p[0]
    $b.Add_Click({ Set-FanProfile $this.Tag })
    $script:fanProfileButtons[$p[0]] = $b; [void]$pseg.Children.Add($b)
  }
  [void]$sideCol.Children.Add($pseg)
  $script:fanNote = X "<TextBlock Style='{DynamicResource Note}' Margin='0,0,0,8'/>"; [void]$sideCol.Children.Add($fanNote)
  [void]$sideCol.Children.Add((New-FanCurve))
  $script:fanNow = X "<TextBlock Style='{DynamicResource Note}' Margin='0,6,0,0' Text=' '/>"; [void]$sideCol.Children.Add($fanNow)
  $script:homeZero = New-Switch $false $null { $v = [int][bool]$this.IsChecked; Start-Ctl "gpu -Setting FAN_ZERORPM_CONTROL -Value $v" { param($r) if ("$r" -match '\(accepted\)' -and "$r" -match 'setting 15 now reads (\d+)') { $z = [int]$Matches[1]; Set-StartupLines '^gpu -Setting FAN_ZERORPM_CONTROL ' @($(if ($z -ne 1) { "gpu -Setting FAN_ZERORPM_CONTROL -Value $z" })) }; Read-Gpu } 'Changing the graphics fan stop...' }
  $homeZero.IsEnabled = $false
  $script:homeZeroRow = Add-Row $sideCol 'Stop the fan when the card is cool' '' $homeZero

  $h = X "<TextBlock Style='{DynamicResource Group}' Text='Lighting'/>"; [void]$sideCol.Children.Add($h)
  $looks = X "<WrapPanel/>"; [void]$sideCol.Children.Add($looks)
  foreach ($nm in (Get-LightProfiles).Keys) { $b = New-Button $nm { Set-HoldSettings -Look $this.Tag; Start-Ctl "lights $($this.Tag)" $null "Applying the $($this.Tag) lighting..." } -Primary; $b.Tag = $nm; [void]$looks.Children.Add($b) }

  $h = X "<TextBlock Style='{DynamicResource Group}' Text='Settings in force'/>"; [void]$sideCol.Children.Add($h)
  $grid2 = X "<UniformGrid Columns='2'/>"; [void]$sideCol.Children.Add($grid2)
  $script:facts = [ordered]@{}
  foreach ($f in @(@('top', 'Top speed'), @('tdp', 'Power limit'), @('drive', 'System drive'), @('intake', 'Air into graphics card'), @('gpuMv', 'Graphics core voltage'), @('up', 'Since restart'))) {
    $cell = X "<StackPanel Margin='0,0,16,12'><TextBlock x:Name='n' Style='{DynamicResource Note}'/><TextBlock x:Name='v' Style='{DynamicResource Readout}' FontSize='17' Text='--'/></StackPanel>"
    $cell.FindName('n').Text = $f[1]; $script:facts[$f[0]] = $cell.FindName('v'); [void]$grid2.Children.Add($cell)
  }

  Add-Field $sideCol 'Hold my settings' 'If OMEN Gaming Hub replaces your fan setting, lighting or undervolt, they are put back: when you unlock the PC, a minute after the app starts, and every 5 minutes.' (New-Switch ([bool](Get-HoldSettings).on) $null { Set-HoldSettings -On ([bool]$this.IsChecked) })
  $denied = @((Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' -Name LetAppsRunInBackground_ForceDenyTheseApps -ErrorAction SilentlyContinue).LetAppsRunInBackground_ForceDenyTheseApps) -match '^AD2F1837\.OMENCommandCenter'
  $script:vendorSwitch = New-Switch (-not $denied) $null { if ($this.IsChecked) { Start-Ctl 'on' $null 'Letting OMEN Gaming Hub and AMD Software start again...' 90 'vendor-startup.ps1' } else { Start-Ctl 'off -CloseNow' $null 'Stopping OMEN Gaming Hub and AMD Software from starting...' 90 'vendor-startup.ps1' } }
  Add-Field $sideCol 'OMEN Gaming Hub and AMD Software start with Windows' 'Off: neither starts when you sign in, HP''s background services are off and the running copies are closed, so only this app sets fans, lighting and voltages. OMEN Gaming Hub does not work until this is on again. AMD Software still opens by hand.' $vendorSwitch

  Set-HomeLayout
  Update-Dash; Update-Home
  if (-not $state.sAt -or ((Get-Date) - $state.sAt).TotalSeconds -gt 60) { Read-State }
}

function Add-Field($panel, [string]$name, [string]$note, $control) {
  $p = X "<StackPanel Margin='0,0,0,14'><TextBlock x:Name='n' FontSize='14'/><TextBlock x:Name='d' Style='{DynamicResource Note}'/></StackPanel>"
  $p.FindName('n').Text = $name; $d = $p.FindName('d'); $d.Text = $note; if (-not $note) { $d.Visibility = 'Collapsed' }
  $control.Margin = '0,6,0,0'; $control.HorizontalAlignment = 'Left'; [void]$p.Children.Add($control); [void]$panel.Children.Add($p)
}

function Set-HomeLayout {
  if ($state.page -ne 'Home' -or -not $homeGrid) { return }
  $R = $homeGrid.FindName('R'); $cols = $homeGrid.ColumnDefinitions
  if ($Page.ActualWidth -gt 0 -and $Page.ActualWidth -lt 1200) {
    $cols[1].Width = 0; $cols[2].Width = 0; $script:homeSide = $false
    [Windows.Controls.Grid]::SetRow($R, 1); [Windows.Controls.Grid]::SetColumn($R, 0); [Windows.Controls.Grid]::SetColumnSpan($R, 3); $R.Margin = '0,26,0,0'; $R.MaxWidth = 560; $R.HorizontalAlignment = 'Left'
  } else {
    $cols[1].Width = 44; $cols[2].Width = New-Object Windows.GridLength 1, 'Star'; $script:homeSide = $true   # readings two thirds of the width, controls one third
    [Windows.Controls.Grid]::SetRow($R, 0); [Windows.Controls.Grid]::SetColumn($R, 2); [Windows.Controls.Grid]::SetColumnSpan($R, 1); $R.Margin = '0'; $R.MaxWidth = [double]::PositiveInfinity
  }
}

function Set-HomeRowHeight {
  if ($state.page -ne 'Home' -or -not $homeGrid -or -not $strips -or -not $strips.Count) { return }
  $want = 46
  if ($homeSide) {
    $L = $homeGrid.FindName('L'); $R = $homeGrid.FindName('R'); $now = $strips[0].g.Height
    if ($L.ActualHeight -le 0 -or $R.ActualHeight -le 0) { return }
    $want = [Math]::Round([Math]::Max(46.0, [Math]::Min(150.0, ($R.ActualHeight - ($L.ActualHeight - $strips.Count * $now)) / $strips.Count)))
  }
  if ([Math]::Abs($want - $strips[0].g.Height) -ge 1) { foreach ($s in $strips) { $s.g.Height = $want } }
}

function New-FanCurve {
  $box = X "<Border Background='#07050B' BorderBrush='{DynamicResource Line}' BorderThickness='1' CornerRadius='4' Padding='10,10,14,8'><Canvas x:Name='cv' Height='190' Background='Transparent'/></Border>"
  $script:fc = @{ cv = $box.FindName('cv'); vals = $null; defs = $null; drag = -1; moved = $false; padL = 38; padB = 20 }
  $fc.cv.Add_SizeChanged({ Draw-FanCurve })
  $fc.cv.Add_MouseMove({
      param($s, $e)
      if ($fc.drag -lt 0) { return }
      $pt = $e.GetPosition($fc.cv); $i = $fc.drag; $v = $fc.vals
      $w = $fc.cv.ActualWidth - $fc.padL; $h = $fc.cv.ActualHeight - $fc.padB
      $t = [Math]::Round(20 + ($pt.X - $fc.padL) / $w * 80); $sp = [Math]::Round((1 - $pt.Y / $h) * 100)
      $tLo = if ($i -gt 0) { $v[2 * $i - 2] + 1 } else { 25 }; $tHi = if ($i -lt 4) { $v[2 * $i + 2] - 1 } else { 100 }
      $sLo = if ($i -gt 0) { $v[2 * $i - 1] } else { 23 }; $sHi = if ($i -lt 4) { $v[2 * $i + 3] } else { 100 }
      $v[2 * $i] = [int][Math]::Min($tHi, [Math]::Max($tLo, $t)); $v[2 * $i + 1] = [int][Math]::Min($sHi, [Math]::Max($sLo, $sp))
      $fc.moved = $true; Draw-FanCurve
    })
  $fc.cv.Add_MouseLeftButtonUp({
      if ($fc.drag -lt 0) { return }
      $fc.drag = -1; $fc.cv.ReleaseMouseCapture()
      if ($fc.moved) { $fc.moved = $false; Send-FanCurve $fc.vals }
      Draw-FanCurve
    })
  $box
}
$fanProfiles = [ordered]@{ smart = @(60, 23, 70, 36, 80, 60, 88, 80, 95, 100) }
$fanProfileFile = Join-Path $env:ProgramData 'SkYn3tLab\om3n-command-gpufan.txt'
function Get-FanProfile { try { (Get-Content $fanProfileFile -ErrorAction Stop | Select-Object -First 1).Trim() -replace '^(quiet|cool)$', 'smart' } catch { 'card' } }
function Show-FanProfile {
  if (-not $fanProfileButtons) { return }
  $p = Get-FanProfile; foreach ($k in $fanProfileButtons.Keys) { $fanProfileButtons[$k].IsChecked = ($k -eq $p -or ($k -eq 'smart' -and $p -eq 'custom')) }
  $fanNote.Text = @{ card = 'The card sets the fan speed itself, as from the factory. The curve below is not in use.'; amd = "AMD's curve. Drag a point to change it."; smart = "Om3n: AMD's curve made better. Quiet up to 60 C, then one even ramp with no jump at the end. Drag a point to change it."; custom = 'Om3n with your changes, sent when you let go of a point. Press Om3n to put its own curve back.' }[$p]
}
function Set-FanProfile([string]$name) {
  if ($name -eq 'card') {
    Start-Ctl 'gpu -FanCurve reset' { param($r) if ("$r" -match '\(accepted\)') { Set-Content $fanProfileFile 'card'; Set-StartupLines '^gpu -FanCurve ' @() }; Show-FanProfile; Draw-FanCurve } 'Handing the graphics fan back to the card...'
    return
  }
  $vals = if ($name -eq 'amd') { $fc.defs } else { $fanProfiles[$name] }
  if ($vals) { Send-FanCurve ([int[]]$vals) $name }
}
function Send-FanCurve([int[]]$vals, [string]$name = 'custom') {
  $csv = $vals -join ','
  $fc.pending = $name
  Start-Ctl "gpu -FanCurve $csv" {
    param($r)
    if ("$r" -match '\(accepted\)' -and "$r" -match 'sending: ([\d= ]+)') {
      $sent = ([regex]::Matches($Matches[1], '(\d+)=(\d+)') | Where-Object { [int]$_.Groups[1].Value -ge 19 -and [int]$_.Groups[1].Value -le 28 } | ForEach-Object { $_.Groups[2].Value }) -join ','
      Set-StartupLines '^gpu -FanCurve ' @($(if ($sent) { "gpu -FanCurve $sent" }))
      Set-Content $fanProfileFile $fc.pending
    }
    Read-Gpu
  } 'Setting the graphics card fan curve...'
}
function Draw-FanCurve {
  $cv = $fc.cv; $cv.Children.Clear()
  $W = $cv.ActualWidth; $H = $cv.ActualHeight; if ($W -le 0) { return }
  $pl = $fc.padL; $w = $W - $pl; $h = $H - $fc.padB
  $X = { param($t) $pl + ($t - 20) / 80 * $w }; $Y = { param($s) (1 - $s / 100) * $h }
  $dim = $win.FindResource('Dim'); $line = $win.FindResource('Line')
  foreach ($t in 40, 60, 80, 100) {
    $g = New-Object Windows.Shapes.Line; $g.X1 = & $X $t; $g.X2 = $g.X1; $g.Y1 = 0; $g.Y2 = $h; $g.Stroke = $line; [void]$cv.Children.Add($g)
    $lb = New-Object Windows.Controls.TextBlock; $lb.Text = "$t C"; $lb.FontSize = 11; $lb.Foreground = $dim; [Windows.Controls.Canvas]::SetLeft($lb, (& $X $t) - 14); [Windows.Controls.Canvas]::SetTop($lb, $h + 3); [void]$cv.Children.Add($lb)
  }
  foreach ($s in 25, 50, 75, 100) {
    $g = New-Object Windows.Shapes.Line; $g.X1 = $pl; $g.X2 = $W; $g.Y1 = & $Y $s; $g.Y2 = $g.Y1; $g.Stroke = $line; [void]$cv.Children.Add($g)
    $lb = New-Object Windows.Controls.TextBlock; $lb.Text = "$s %"; $lb.FontSize = 11; $lb.Foreground = $dim; [Windows.Controls.Canvas]::SetLeft($lb, 0); [Windows.Controls.Canvas]::SetTop($lb, (& $Y $s) - 7); [void]$cv.Children.Add($lb)
  }
  if (-not $fc.vals) {
    $lb = New-Object Windows.Controls.TextBlock; $lb.Text = 'Reading the curve from the card...'; $lb.Foreground = $dim; [Windows.Controls.Canvas]::SetLeft($lb, $pl + 12); [Windows.Controls.Canvas]::SetTop($lb, $h / 2 - 8); [void]$cv.Children.Add($lb); return
  }
  $v = $fc.vals; $mag = if ((Get-FanProfile) -eq 'card') { $win.FindResource('Zone-sys').Color } else { $win.FindResource('AccentLight').Color }
  $pts = New-Object Windows.Media.PointCollection
  $pts.Add((New-Object Windows.Point (& $X 20), (& $Y $v[1])))
  for ($i = 0; $i -lt 5; $i++) { $pts.Add((New-Object Windows.Point (& $X $v[2 * $i]), (& $Y $v[2 * $i + 1]))) }
  $pts.Add((New-Object Windows.Point (& $X 100), (& $Y $v[9])))
  $area = New-Object Windows.Shapes.Polygon; $ap = $pts.Clone(); $ap.Add((New-Object Windows.Point (& $X 100), $h)); $ap.Add((New-Object Windows.Point (& $X 20), $h)); $area.Points = $ap
  $area.Fill = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb(0x30, $mag.R, $mag.G, $mag.B)); [void]$cv.Children.Add($area)
  $pl2 = New-Object Windows.Shapes.Polyline; $pl2.Points = $pts; $pl2.Stroke = New-Object Windows.Media.SolidColorBrush $mag; $pl2.StrokeThickness = 2; [void]$cv.Children.Add($pl2)
  for ($i = 0; $i -lt 5; $i++) {
    $e = New-Object Windows.Shapes.Ellipse; $e.Width = 14; $e.Height = 14; $e.Fill = New-Object Windows.Media.SolidColorBrush $mag; $e.Stroke = $win.FindResource('Ink'); $e.StrokeThickness = 2; $e.Cursor = 'Hand'; $e.Tag = $i
    $e.ToolTip = "$($v[2 * $i]) C, $($v[2 * $i + 1]) %"
    [Windows.Controls.Canvas]::SetLeft($e, (& $X $v[2 * $i]) - 7); [Windows.Controls.Canvas]::SetTop($e, (& $Y $v[2 * $i + 1]) - 7)
    $e.Add_MouseLeftButtonDown({ param($s, $ev) $fc.drag = [int]$this.Tag; $fc.moved = $false; [void]$fc.cv.CaptureMouse(); $ev.Handled = $true })
    [void]$cv.Children.Add($e)
    if ($fc.drag -eq $i) {
      $lb = New-Object Windows.Controls.TextBlock; $lb.Text = "$($v[2 * $i]) C  $($v[2 * $i + 1]) %"; $lb.FontWeight = 'SemiBold'; $lb.Foreground = $win.FindResource('Ink')
      [Windows.Controls.Canvas]::SetLeft($lb, [Math]::Min($W - 80, (& $X $v[2 * $i]) + 10)); [Windows.Controls.Canvas]::SetTop($lb, [Math]::Max(0.0, (& $Y $v[2 * $i + 1]) - 22)); [void]$cv.Children.Add($lb)
    }
  }
}

function Get-HeatColor($v, $warn, $hot) {
  $k = if ($null -eq $v -or $null -eq $warn) { 'Zone-sys' } elseif ($v -ge $hot) { 'Danger' } elseif ($v -ge $warn) { 'Warn' } else { 'Good' }
  $win.FindResource($k).Color
}
function Set-Heat($tb, $v, $warn, $hot) {
  $tb.Foreground = if ($null -eq $v -or $null -eq $warn) { $win.FindResource('Ink') } elseif ($v -ge $hot) { $win.FindResource('Danger') } elseif ($v -ge $warn) { $win.FindResource('Warn') } else { $win.FindResource('Ink') }
}
function Set-Trend($s, [double]$lo, [double]$hi) {
  $h = [Dash]::History($s.r.k); $w = $s.c.ActualWidth; $ht = $s.c.ActualHeight
  if ($w -le 0 -or $ht -le 0 -or $h.Count -lt 2) { return }
  if ($hi -le $lo) { $hi = [Math]::Max(1.0, ($h | Measure-Object -Maximum).Maximum * 1.15); $s.hi.Text = $(if ($hi -lt 10) { '{0:N1}' -f $hi } else { '{0:N0}' -f $hi }) }   # 0 = scale to what was seen
  if ($s.tw -ne "$w $ht") {
    $s.tw = "$w $ht"; $s.t.Children.Clear(); $line = $win.FindResource('Line')
    foreach ($ago in 30, 60, 90, 120, 150) { $l = New-Object Windows.Shapes.Line; $l.X1 = $l.X2 = $w * (1 - $ago / ([Dash]::Keep - 1)); $l.Y1 = 0; $l.Y2 = $ht; $l.Stroke = $line; $l.StrokeThickness = 1; [void]$s.t.Children.Add($l) }
    if ($null -ne $s.r.warn -and $s.r.warn -gt $lo -and $s.r.warn -lt $hi) { $y = ($ht - 2) * (1 - ($s.r.warn - $lo) / ($hi - $lo)) + 1; $s.w.X1 = 0; $s.w.X2 = $w; $s.w.Y1 = $s.w.Y2 = $y; $s.w.Visibility = 'Visible' }
  }
  $pts = New-Object Windows.Media.PointCollection
  $step = $w / ([Dash]::Keep - 1); $x0 = ([Dash]::Keep - $h.Count) * $step
  for ($i = 0; $i -lt $h.Count; $i++) {
    $f = [Math]::Max(0.0, [Math]::Min(1.0, ($h[$i] - $lo) / ($hi - $lo)))
    $pts.Add((New-Object Windows.Point (($x0 + $i * $step), (($ht - 2) * (1 - $f) + 1))))
  }
  $s.p.Points = $pts
  $area = $pts.Clone(); $area.Add((New-Object Windows.Point ($pts[$pts.Count - 1].X, $ht))); $area.Add((New-Object Windows.Point ($x0, $ht))); $s.a.Points = $area
}
function Set-HomeAxes {
  foreach ($ax in $homeAxes) {
    $w = $ax.c.ActualWidth; if ($w -le 0 -or $w -eq $ax.w) { continue }
    $ax.w = $w; $ax.c.Children.Clear()
    foreach ($m in @(@(179, '3 min ago'), @(120, '2 min'), @(60, '1 min'), @(0, 'now'))) {
      if ($w -lt 260 -and $m[0] -in 120, 60) { continue }   # a narrow chart has room for the two end labels only
      $tb = New-Object Windows.Controls.TextBlock; $tb.Text = $m[1]; $tb.Foreground = $win.FindResource('Dim'); $tb.FontSize = 11; $tb.Width = 70
      $x = $w * (1 - $m[0] / ([Dash]::Keep - 1))
      if ($m[0] -eq 179) { $tb.TextAlignment = 'Left' } elseif ($m[0] -eq 0) { $tb.TextAlignment = 'Right'; $x -= 70 } else { $tb.TextAlignment = 'Center'; $x -= 35 }
      [Windows.Controls.Canvas]::SetLeft($tb, $x); [Windows.Controls.Canvas]::SetTop($tb, $(if ($ax.at -eq 'Bottom') { 4 } else { 2 })); [void]$ax.c.Children.Add($tb)
    }
  }
}
function Update-Dash {
  if ($state.page -ne 'Home' -or -not $strips) { return }
  Set-HomeRowHeight
  Set-HomeAxes
  $d = [Dash]::Snapshot()
  $g = { param($k) if ($d.ContainsKey($k)) { $d[$k] } else { $null } }
  $n = { param($k, $fmt) $x = & $g $k; if ($null -eq $x) { '--' } else { $fmt -f $x } }
  foreach ($s in $strips) {
    $r = $s.r; $x = & $g $r.k
    $s.v.Text = if ($null -eq $x) { '--' } else { $r.f -f $x }
    $s.s.Text = & $r.d
    Set-Heat $s.v $x $r.warn $r.hot
    $col = Get-HeatColor $x $r.warn $r.hot
    if ($col -ne $s.col) {
      $s.col = $col; $s.p.Stroke = New-Object Windows.Media.SolidColorBrush $col
      $s.a.Fill = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb(0x30, $col.R, $col.G, $col.B))
    }
    Set-Trend $s $r.lo $r.hi
  }
  $facts.intake.Text = & $n 'gpuIntake' '{0:N0} C'
  $facts.drive.Text = & $n 'driveTemp' '{0:N0} C'
  if ($jobs.Count -eq 0) { $state.fan = Get-FanSelection; foreach ($k in $homeFan.Keys) { $homeFan[$k].IsChecked = ($k -eq $state.fan) } }
  if ($fanNow) { $fanNow.Text = 'Now: edge ' + (& $n 'gpuTemp' '{0:N0} C') + ', hotspot ' + (& $n 'gpuHot' '{0:N0} C') + ', fan ' + (& $n 'gpuFanPct' '{0:N0} %') + ' (' + (& $n 'gpuFanRpm' '{0:N0} rpm') + ')' }
  $facts.gpuMv.Text = & $n 'gpuMv' '{0:N0} mV'
  $u = & $g 'uptimeS'; $facts.up.Text = if ($null -eq $u) { '--' } else { $ts = [TimeSpan]::FromSeconds($u); if ($ts.Days) { '{0}d {1}h {2}m' -f $ts.Days, $ts.Hours, $ts.Minutes } else { '{0}h {1}m' -f $ts.Hours, $ts.Minutes } }
}
function Get-HeldWords($held) {
  (@($held.lines) | ForEach-Object {
      if ($_ -match 'cpu .*-ControlId\s+(0x22|34)\b.*-Value\s+(-?\d+)') { "processor $($Matches[2]) mV" }
      elseif ($_ -match 'cpu .*-ControlId\s+(0x4F|79)\b.*-Value\s+(-?\d+)') { "processor cache $($Matches[2]) mV" }
      elseif ($_ -match 'OD_VOLTAGE.*-Value\s+(\d+)') { "graphics $($Matches[1]) mV" } else { $_ } }) -join ', '
}
function Update-Home {
  if ($state.page -ne 'Home' -or -not $facts) { return }
  $held = if ($state.s) { $state.s.held }
  if ($held -and $heldBar) {
    $heldText.Text = if ("$($held.crash)" -match '^graphics driver reset (.+)') { "The graphics driver stopped responding and Windows reset it ($($Matches[1])). The reset put the card back to its stock voltage, and to be safe yours was not put back: $(Get-HeldWords $held). If you do nothing it returns at the next sign-in." }
    else { "The PC stopped without a clean shutdown (Windows recorded it when it started again, $($held.crash)). To be safe, the undervolt was not put back at this sign-in: $(Get-HeldWords $held). If you do nothing it returns at the next sign-in." }
    $heldBar.Visibility = 'Visible'
  } elseif ($heldBar) { $heldBar.Visibility = 'Collapsed' }
  $t1 = Get-GpuSetting 'FAN_CURVE_TEMPERATURE_1'
  if ($t1 -and $fc -and $fc.drag -lt 0) {
    $cur = @(); $def = @()
    foreach ($i in 1..5) { foreach ($k in 'TEMPERATURE', 'SPEED') { $x = Get-GpuSetting "FAN_CURVE_${k}_$i"; if ($x) { $cur += [int]$x.current; $def += [int]$x.default } } }
    if ($cur.Count -eq 10) { $fc.vals = [int[]]$cur; $fc.defs = [int[]]$def; Draw-FanCurve }
    Show-FanProfile
    $z = Get-GpuSetting 'FAN_ZERORPM_CONTROL'; if ($z) { $homeZero.IsChecked = ($z.current -eq 1); $homeZero.IsEnabled = $true }
    $st = Get-GpuSetting 'FAN_ZERO_RPM_STOP_TEMPERATURE'; if ($st) { $homeZeroRow.FindName('n').Text = "Stop the fan below $($st.current) C" }
  }
  $v = Get-GpuSetting 'OD_VOLTAGE'; if ($v) { Set-SliderValue $homeGpuV ([double]$v.current) }
  $mv = Get-Cpu '0x00000022'; $top = Get-Cpu '0x0000001D'; $all = Get-Cpu '0x00000061'; $tdp = Get-Cpu '0x00000030'
  if ($null -ne $mv) { Set-SliderValue $homeCpuUv ([double]$mv) }
  $facts.top.Text = if ($null -eq $top -or $null -eq $all) { '--' } elseif ($top -eq $all) { "$($top / 10) GHz, all cores" } else { "$($top / 10) to $($all / 10) GHz" }
  $facts.tdp.Text = if ($null -eq $tdp) { '--' } else { "$([int]$tdp) W" }
}

function Show-Fans {
  Add-Title 'Fans' 'This PC has three fan settings. Pick one, or let the app switch between them by processor temperature.'
  $row = X "<UniformGrid Columns='4' Margin='0,0,-12,2'/>"; [void]$Page.Children.Add($row)
  $script:fanChoice = @{}
  foreach ($f in @(@('quiet', 'Quiet', 'Slowest fans. For desktop work.'), @('normal', 'Balanced', 'The everyday setting.'), @('turbo', 'Performance', 'Strongest cooling. For games.'), @('auto', 'Om3n', 'Switches between the three by processor temperature.'))) {
    $r = X "<RadioButton Style='{DynamicResource Choice}' GroupName='fan' Margin='0,0,12,12'><StackPanel><TextBlock x:Name='n' FontSize='16' FontWeight='SemiBold'/><TextBlock x:Name='d' Style='{DynamicResource Note}' Margin='0,4,0,0'/></StackPanel></RadioButton>"
    $r.FindName('n').Text = $f[1]; $r.FindName('d').Text = $f[2]; $r.Tag = $f[0]; $r.IsChecked = ($state.fan -eq $f[0])
    $r.Add_Click({
        $a = if ($this.Tag -eq 'auto') { "fan auto -QuietBelow $([int]$fanQuiet.FindName('s').Value) -TurboAbove $([int]$fanTurbo.FindName('s').Value)" } else { "fan $($this.Tag)" }
        $state.fan = $this.Tag
        Start-Ctl $a $null 'Changing the fan setting...'
      })
    $script:fanChoice[$f[0]] = $r; [void]$row.Children.Add($r)
  }
  $c = Add-Card
  [void]$c.Children.Add((X "<TextBlock Style='{DynamicResource H2}' Text='Om3n' Margin='0,0,0,6'/>"))
  $reapply = { if ($state.fan -eq 'auto') { Start-Ctl "fan auto -QuietBelow $([int]$fanQuiet.FindName('s').Value) -TurboAbove $([int]$fanTurbo.FindName('s').Value)" $null 'Updating the automatic fan setting...' } }
  $script:fanQuiet = New-Slider 35 60 1 50 ' C' $null $reapply
  $script:fanTurbo = New-Slider 65 90 1 75 ' C' $null $reapply
  [void](Add-Row $c 'Go quiet below' 'Under this temperature the fans drop to Quiet.' $fanQuiet)
  [void](Add-Row $c 'Go to Performance from' 'At this temperature and above the fans go to Performance. In between they stay on Balanced.' $fanTurbo)
  Add-Note $c 'Om3n keeps working until you pick another setting, and is started again at every sign-in.'
  Add-FansMore $c
}

function Get-LightProfiles {
  $f = Join-Path $env:ProgramData 'SkYn3tLab\om3n-command-lights.json'; $o = [ordered]@{}
  if (Test-Path $f) { $j = Get-Content $f -Raw | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $o[$p.Name] = @($p.Value) } }
  $o
}
$zoneNames = [ordered]@{ Logo = 'Front logo'; InternalBar = 'Inside light bar'; FrontFan = 'Front fan'; CpuFan = 'Processor cooler'; Ram = 'Memory' }
$effects = [ordered]@{ 'Solid colour' = 'static'; 'Breathing' = 'breathing'; 'Colour cycle' = 'cycle'; 'Blinking' = 'blinking'; 'Wave' = 'wave'; 'Spiral' = 'spiral'; 'Off' = 'off' }
$themes = [ordered]@{ 'My colour' = 'custom'; 'Galaxy' = 'galaxy'; 'Volcano' = 'volcano'; 'Jungle' = 'jungle'; 'Ocean' = 'ocean'; 'Omen' = 'omen'; 'Unicorn' = 'unicorn'; 'Arcane' = 'arcane'; 'Valorant' = 'valorant'; 'HyperX' = 'hyperx' }
$zoneState = @{}
function Read-ProfileLine([string]$line) {
  $w = @($line -split ' ' | Where-Object { $_ }); $z = @{ zone = $w[0]; rgb = @(255, 255, 255); effect = 'static'; theme = 'custom'; speed = 'medium' }
  if ($w.Count -ge 4 -and $w[1] -match '^\d+$') { $z.rgb = @([int]$w[1], [int]$w[2], [int]$w[3]) }
  for ($i = 1; $i -lt $w.Count - 1; $i++) { switch ($w[$i]) { '-Effect' { $z.effect = $w[$i + 1] } '-Theme' { $z.theme = $w[$i + 1] } '-Speed' { $z.speed = $w[$i + 1] } } }
  Read-ZoneMore $z $w
  $z
}
function Get-ZoneLine($z) {
  if ($z.effect -eq 'off') { return "$($z.zone) -Effect off" }
  if ($z.effect -eq 'static') { return "$($z.zone) $($z.rgb -join ' ')$(Get-ZoneMore $z)" }
  if ($z.theme -ne 'custom') { return "$($z.zone) -Effect $($z.effect) -Theme $($z.theme) -Speed $($z.speed)$(Get-ZoneMore $z)" }
  "$($z.zone) $($z.rgb -join ' ') -Effect $($z.effect) -Speed $($z.speed)$(Get-ZoneMore $z)"
}
function Initialize-Zones([string]$profileName) {
  $p = Get-LightProfiles; $lines = if ($profileName -and $p.Contains($profileName)) { $p[$profileName] } elseif ($p.Count) { @($p.Values)[0] } else { @() }
  foreach ($k in $zoneNames.Keys) { $zoneState[$k] = @{ zone = $k; rgb = @(255, 255, 255); effect = 'static'; theme = 'custom'; speed = 'medium' } }
  foreach ($l in $lines) { $z = Read-ProfileLine $l; if ($zoneNames.Contains($z.zone)) { $zoneState[$z.zone] = $z } }
}
Initialize-Zones ''
function Show-Lighting {
  Add-Title 'Lighting' 'Pick a saved look, or set each light yourself. Click a colour box to choose a colour.'
  $c = Add-Card
  [void]$c.Children.Add((X "<TextBlock Style='{DynamicResource H2}' Text='Saved looks' Margin='0,0,0,8'/>"))
  $wrap = X "<WrapPanel/>"; [void]$c.Children.Add($wrap); $script:lookButtons = @()
  foreach ($n in (Get-LightProfiles).Keys) {
    $b = New-Button $n { Initialize-Zones $this.Tag; Set-HoldSettings -Look $this.Tag; Start-Ctl "lights $($this.Tag)" $null "Applying the $($this.Tag) look..."; Show-Lighting } -Primary; $b.Tag = $n; [void]$wrap.Children.Add($b); $script:lookButtons += $b
  }
  $save = X "<StackPanel Orientation='Horizontal' Margin='0,12,0,0'><TextBlock Text='Save what is set below as' VerticalAlignment='Center' Margin='0,0,8,0'/><TextBox x:Name='name' Width='150' VerticalAlignment='Center'/></StackPanel>"
  $script:saveName = $save.FindName('name')
  [void]$save.Children.Add((New-Button 'Save look' {
        $n = $saveName.Text.Trim(); if ($n -notmatch '^[\w][\w -]{0,30}$') { $Busy.Text = 'Give the look a short name (letters, numbers, spaces).'; $Busy.Foreground = $win.FindResource('Hot'); return }
        $p = Get-LightProfiles; $p[$n] = @($zoneNames.Keys | ForEach-Object { Get-ZoneLine $zoneState[$_] })
        $p | ConvertTo-Json | Set-Content (Join-Path $env:ProgramData 'SkYn3tLab\om3n-command-lights.json'); $Busy.Text = "Saved the look '$n'."; Show-Lighting; Show-LightStrip
      }))
  $save.Children[2].Margin = '8,0,0,0'; [void]$c.Children.Add($save)
  $bt = Get-ScheduledTask -TaskName 'SkYn3tLab-om3n-command-lights-boot' -ErrorAction SilentlyContinue
  $bootLook = if ($bt -and $bt.Actions[0].Arguments -match ' run -Look "(.+)"$') { $Matches[1] } else { 'Off' }
  $script:bootCombo = New-Combo (@('Off') + @((Get-LightProfiles).Keys)) $bootLook $null { $l = "$($this.SelectedItem)"; if ($l -eq 'Off') { Start-Ctl 'off' $null 'Turning off the look at the sign-in screen...' 60 'lights-at-boot.ps1' } else { Start-Ctl "on `"$l`"" $null "The $l look will be set when Windows starts..." 60 'lights-at-boot.ps1' } }
  $bootCombo.Width = 150
  [void](Add-Row $c 'At the sign-in screen' 'A saved look set when Windows starts, before you sign in. A look you change later is picked up the next time Windows starts.' $bootCombo)

  $c2 = Add-Card
  [void]$c2.Children.Add((X "<TextBlock Style='{DynamicResource H2}' Text='Each light' Margin='0,0,0,6'/>"))
  foreach ($k in $zoneNames.Keys) {
    $z = $zoneState[$k]
    $g = X "<Grid Margin='0,7'><Grid.ColumnDefinitions><ColumnDefinition Width='150'/><ColumnDefinition Width='54'/><ColumnDefinition Width='150'/><ColumnDefinition Width='140'/><ColumnDefinition Width='110'/><ColumnDefinition Width='*'/></Grid.ColumnDefinitions><TextBlock x:Name='n' VerticalAlignment='Center' FontSize='14'/><Button x:Name='sw' Grid.Column='1' Width='40' Height='28' Padding='0' HorizontalAlignment='Left' ToolTip='Choose a colour'/></Grid>"
    $g.FindName('n').Text = $zoneNames[$k]
    $sw = $g.FindName('sw'); $sw.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb($z.rgb[0], $z.rgb[1], $z.rgb[2])); $sw.Tag = $k
    $sw.Add_Click({
        $z = $zoneState[$this.Tag]; $d = New-Object Windows.Forms.ColorDialog; $d.FullOpen = $true; $d.Color = [Drawing.Color]::FromArgb($z.rgb[0], $z.rgb[1], $z.rgb[2])
        if ($d.ShowDialog() -eq 'OK') { $z.rgb = @($d.Color.R, $d.Color.G, $d.Color.B); $z.theme = 'custom'; Send-Zone $this.Tag; Show-Lighting }
      })
    $fx = if ($k -eq 'Ram') { @($effects.Keys | Where-Object { $_ -ne 'Spiral' }) } else { @($effects.Keys) }
    $e = New-Combo $fx (@($effects.Keys | Where-Object { $effects[$_] -eq $z.effect })[0]) $k { $zoneState[$this.Tag].effect = $effects[$this.SelectedItem]; Send-Zone $this.Tag; Show-Lighting }
    [Windows.Controls.Grid]::SetColumn($e, 2); $e.Margin = '0,0,10,0'; [void]$g.Children.Add($e)
    if ($z.effect -notin 'static', 'off') {
      $th = if ($k -eq 'Ram') { @('My colour', 'Galaxy') } else { @($themes.Keys) }
      $t = New-Combo $th (@($themes.Keys | Where-Object { $themes[$_] -eq $z.theme })[0]) $k { $zoneState[$this.Tag].theme = $themes[$this.SelectedItem]; Send-Zone $this.Tag }
      [Windows.Controls.Grid]::SetColumn($t, 3); $t.Margin = '0,0,10,0'; [void]$g.Children.Add($t)
      $sp = New-Combo @('slow', 'medium', 'fast') $z.speed $k { $zoneState[$this.Tag].speed = $this.SelectedItem; Send-Zone $this.Tag }
      [Windows.Controls.Grid]::SetColumn($sp, 4); $sp.MinWidth = 90; [void]$g.Children.Add($sp)
    }
    [void]$c2.Children.Add($g)
  }
  Add-Note $c2 'Changes apply as soon as you make them. While OMEN Gaming Hub is installed it puts its own colours back when you unlock the PC; with Hold my settings on (Home), the look you last pressed returns a few seconds later.'
  Add-LightingMore $Page
}
function Send-Zone([string]$k) { Start-Ctl "light $(Get-ZoneLine $zoneState[$k])" $null "Setting the $($zoneNames[$k].ToLower())..." }

function Show-Cpu {
  Add-Title 'Processor' 'The top speed the processor may reach, by how many cores are busy. Higher is faster and hotter.'
  $c = Add-Card
  $script:cpuPanel = $c
  [void]$c.Children.Add((X "<TextBlock Text='Reading the processor settings...' Style='{DynamicResource Note}'/>"))
  $script:cpuVoltPanel = Add-Card
  [void]$cpuVoltPanel.Children.Add((X "<TextBlock Style='{DynamicResource H2}' Text='Voltage' Margin='0,0,0,4'/>"))
  $c2 = Add-Card
  [void](Add-Row $c2 'Everything the processor service offers' 'Voltages, power limits and every other control, as a list on the Activity page.' (New-Button 'Show the full list' { Start-Ctl 'cpu' { Select-Page 'Activity' } 'Reading the processor settings...' }))
  Read-State 'cpu' {
    param($ok)
    if ($state.page -ne 'Processor') { return }
    $cpuPanel.Children.Clear()
    $rows = @(if ($state.s -and $state.s.cpu) { $state.s.cpu.PSObject.Properties | Where-Object { $_.Value.name -match '^Max Turbo for (\d) Cores$' } | ForEach-Object { $null = $_.Value.name -match '^Max Turbo for (\d) Cores$'; @{ id = $_.Name; cores = [int]$Matches[1]; def = [int]$_.Value.default; now = [int]$_.Value.active } } | Sort-Object { $_.cores } })
    if (-not $ok -or -not $rows) { [void]$cpuPanel.Children.Add((X "<TextBlock Text='The processor settings could not be read. See the Activity page.'/>")); return }
    foreach ($r in $rows) {
      $s = New-Slider 30 53 1 $r.now '' $r { param($sl) Start-Ctl "cpu -ControlId $($sl.Tag.data.id) -Value $([int]$sl.Value)" $null 'Changing the processor speed limit...' }
      $s.FindName('s').Tag.unit = '00 MHz'; $s.FindName('v').Text = "$($r.now)00 MHz"
      [void](Add-Row $cpuPanel "$($r.cores) core$(if ($r.cores -gt 1) { 's' }) busy" "Factory setting $($r.def)00 MHz" $s)
    }
    Add-Note $cpuPanel 'A change takes effect straight away and lasts until the next restart or until OMEN Gaming Hub applies its own profile.'
    $mv = Get-Cpu '0x00000022'; if ($null -eq $mv) { $mv = 0 }
    $script:cpuVolt = New-Slider -150 0 5 ([int]$mv) ' mV' $null { param($sl) Start-Ctl "cpu -ControlId 0x22 -Value $([int]$sl.Value)" { param($r, $raw, $ok) if ($ok -and $cpuKeep.IsChecked) { Save-Startup } } 'Changing the processor voltage...' }
    [void](Add-Row $cpuVoltPanel 'Voltage offset (undervolt)' 'Lower runs cooler. Too low makes the PC crash or freeze; if that happens, restart and it is back at 0.' $cpuVolt)
    $script:cpuKeep = New-Switch $false $null { if ($this.IsChecked) { Save-Startup; Start-Ctl 'startup on' $null 'Turning on the sign-in setting...' } else { Start-Ctl 'startup off' $null 'Turning off the sign-in setting...' } }
    [void](Add-Row $cpuVoltPanel 'Put the voltage offset back at every sign-in' 'A restart resets it to 0. With this on, the app sets it again a minute after you sign in.' $cpuKeep)
    $cpuKeep.IsChecked = [bool](Get-ScheduledTask -TaskName 'SkYn3tLab-om3n-command-startup' -ErrorAction SilentlyContinue)
  }
  Add-MemoryProfile $Page
}

function Save-Startup($v) {
  if ($null -eq $v) { $v = [int]$cpuVolt.FindName('s').Value }
  Set-StartupLines '^cpu -ControlId 0x(22|4F) ' @("cpu -ControlId 0x22 -Value $v", "cpu -ControlId 0x4F -Value $v")
}
$gpuVoltDone = { param($r) if ("$r" -match '\(accepted\)' -and "$r" -match 'setting 37 now reads (\d+)') { $v = [int]$Matches[1]; Set-StartupLines '^gpu -Setting OD_VOLTAGE ' @($(if ($v -lt 1150) { "gpu -Setting OD_VOLTAGE -Value $v" })) } }
function Set-StartupLines([string]$pattern, [string[]]$lines) {
  $f = Join-Path $env:ProgramData 'SkYn3tLab\om3n-command-startup.txt'
  $keep = @(if (Test-Path $f) { Get-Content $f | Where-Object { $_.Trim() -and $_ -notmatch '^\s*#' -and $_ -notmatch $pattern } })
  Set-Content $f (@('# om3n-command commands to run at every sign-in, one per line (see "om3n-command.ps1 startup"). Written by the app.') + $keep + @($lines | Where-Object { $_ }))
}
function Show-Graphics {
  Add-Title 'Graphics' 'Radeon RX 7900 XTX features. Each switch takes effect straight away.'
  $c = Add-Card; $script:gfxPanel = $c
  [void]$c.Children.Add((X "<TextBlock Text='Reading the graphics settings...' Style='{DynamicResource Note}'/>"))
  $script:featureClick = { $on = [int][bool]$this.IsChecked; $t = $this.Tag; Start-Ctl "gpu $($t.arg) $(if ($t.kind -eq 'setting') { "-Value $on" } else { "-Enable $on$(if ($on -and $t.value) { " -Value $($t.value)" })" })" $null "Turning $($t.name) $(if ($on) { 'on' } else { 'off' })..." }
  Read-State 'gpu' {
    param($ok)
    if ($state.page -ne 'Graphics') { return }
    $gfxPanel.Children.Clear()
    $g = if ($state.s) { $state.s.gpu }
    if (-not $ok -or -not $g -or -not $g.settings) { [void]$gfxPanel.Children.Add((X "<TextBlock Text='The graphics settings could not be read. See the Activity page.'/>")); return }
    $sens = $g.sensors; $f = $g.features
    if ($sens.TEMPERATURE_EDGE) { Add-Note $gfxPanel "Right now: $($sens.TEMPERATURE_EDGE) C, hottest spot $($sens.TEMPERATURE_HOTSPOT) C, fan $($sens.FAN_RPM) rpm, drawing $($sens.BOARD_POWER) W." }
    $on = { param($name) [bool]($f.$name -and $f.$name.on -eq 1) }
    [void](Add-Row $gfxPanel 'Anti-Lag' 'Cuts the delay between your input and the picture.' (New-Switch (& $on 'Anti-Lag') @{ arg = '-Feature antilag'; name = 'Anti-Lag' } $featureClick))
    [void](Add-Row $gfxPanel 'Radeon Boost' 'Lowers the resolution briefly during fast motion for more frames.' (New-Switch (& $on 'Radeon Boost') @{ arg = '-Feature boost'; name = 'Radeon Boost' } $featureClick))
    [void](Add-Row $gfxPanel 'Radeon Chill' 'Lowers the frame rate when little is moving, to run cooler and quieter.' (New-Switch (& $on 'Radeon Chill') @{ arg = '-Feature chill'; name = 'Radeon Chill' } $featureClick))
    $sharp = if ($f.'Image Sharpening' -and $null -ne $f.'Image Sharpening'.sharpness) { [int]$f.'Image Sharpening'.sharpness } else { 80 }
    [void](Add-Row $gfxPanel 'Image Sharpening' 'Makes the picture crisper.' (New-Switch (& $on 'Image Sharpening') @{ arg = '-Feature sharpen'; name = 'Image Sharpening'; value = $sharp } $featureClick))
    [void](Add-Row $gfxPanel 'Sharpening strength' '' (New-Slider 10 100 10 $sharp ' %' $null { param($sl) Start-Ctl "gpu -Feature sharpen -Enable 1 -Value $([int]$sl.Value)" { Show-Graphics } 'Setting the sharpening strength...' }))
    $cap = if ($f.'Frame rate target' -and $null -ne $f.'Frame rate target'.fps) { [int]$f.'Frame rate target'.fps } else { 60 }
    [void](Add-Row $gfxPanel 'Frame rate limit' 'Stops games drawing more frames than this.' (New-Switch (& $on 'Frame rate target') @{ arg = '-Feature framecap'; name = 'the frame rate limit'; value = $cap } $featureClick))
    [void](Add-Row $gfxPanel 'Limit' '' (New-Slider 30 300 5 ([Math]::Min(300, [Math]::Max(30, $cap))) ' fps' $null { param($sl) Start-Ctl "gpu -Feature framecap -Enable 1 -Value $([int]$sl.Value)" { Show-Graphics } 'Setting the frame rate limit...' }))
    $pw = $g.settings.POWER_PERCENTAGE
    if ($pw) { [void](Add-Row $gfxPanel 'Power limit' 'How much power the card may draw compared with normal. More is faster and hotter.' (New-Slider $pw.min $pw.max 1 $pw.current ' %' $null { param($sl) Start-Ctl "gpu -Setting POWER_PERCENTAGE -Value $([int]$sl.Value)" $null 'Setting the power limit...' })) }
    $gv = $g.settings.OD_VOLTAGE
    if ($gv) {
      [void](Add-Row $gfxPanel 'Voltage (undervolt)' "The highest voltage the chip may use; stock is $($gv.default) mV. Lower runs cooler and quieter. Too low makes games crash or the screen freeze for a moment." (New-Slider 1000 $gv.max 5 ([Math]::Min($gv.max, [Math]::Max(1000, $gv.current))) ' mV' $null {
            param($sl)
            Start-Ctl "gpu -Setting OD_VOLTAGE -Value $([int]$sl.Value)" $gpuVoltDone 'Setting the graphics voltage...' }))
    }
    $script:gfxLate = Add-Card
    foreach ($x in @(@('-Feature rsr', 'Radeon Super Resolution', 'Renders games at a lower resolution and scales them up for more frames.', 'feature'), @('-Feature afmf', 'Fluid Motion Frames', 'Adds generated frames between real ones for a smoother picture.', 'feature'), @('-Setting enhancedsync', 'Enhanced Sync', 'Reduces tearing without the delay of V-Sync.', 'setting'))) {
      $sw = New-Switch $false @{ arg = $x[0]; name = $x[1]; kind = $x[3] } $featureClick; $sw.IsEnabled = $false
      [void](Add-Row $gfxLate $x[1] $x[2] $sw)
      Start-Ctl "gpu $($x[0])" $null 'Reading the graphics settings...'
      $lastJob.switch = $sw
    }
    Add-GraphicsMore $Page
  }
}

function Show-Displays {
  Add-Title 'Displays' 'Picture settings for each monitor. Slide and let go to apply.'
  $script:dispHost = X "<StackPanel/>"; [void]$Page.Children.Add($dispHost)
  [void]$dispHost.Children.Add((X "<TextBlock Text='Reading the monitors...' Style='{DynamicResource Note}'/>"))
  Start-Ctl 'display' {
    param($l)
    if ($state.page -ne 'Displays') { return }
    $dispHost.Children.Clear(); $panel = $null; $n = -1
    $labels = @{ brightness = @('Brightness', ''); contrast = @('Contrast', ''); saturation = @('Colour strength', ''); hue = @('Tint', ''); temperature = @('Warmth', ' K') }
    foreach ($line in $l) {
      if ($line -match '^\s*through the newer interface') { break }
      if ($line -match '^display (\d+): (.+?)\s+\(adapter') {
        $n = [int]$Matches[1]; $card = X "<Border Style='{DynamicResource Card}'><StackPanel/></Border>"; [void]$dispHost.Children.Add($card); $panel = $card.Child
        $h = X "<TextBlock Style='{DynamicResource H2}' Margin='0,0,0,6'/>"; $h.Text = "Monitor $($n + 1): $($Matches[2])"; [void]$panel.Children.Add($h); continue
      }
      if (-not $panel) { continue }
      if ($line -match '^\s+(brightness|contrast|saturation|hue|temperature)\s+current=(-?\d+) default=(-?\d+) range (-?\d+)\.\.(-?\d+) step (\d+)') {
        $k = $Matches[1]; $tag = @{ display = $n; set = $k }
        $s = New-Slider ([int]$Matches[4]) ([int]$Matches[5]) ([int]$Matches[6]) ([int]$Matches[2]) $labels[$k][1] $tag { param($sl) Start-Ctl "display -Display $($sl.Tag.data.display) -Set $($sl.Tag.data.set) -Value $([int]$sl.Value)" $null 'Changing the picture...' }
        [void](Add-Row $panel $labels[$k][0] "Normal is $($Matches[3])$($labels[$k][1])" $s)
      } elseif ($line -match '^\s+gpuscaling\s+supported=1 current=(\d)') {
        [void](Add-Row $panel 'Scale small resolutions to fill the screen' '' (New-Switch ($Matches[1] -eq '1') @{ display = $n } { Start-Ctl "display -Display $($this.Tag.display) -Set gpuscaling -Value $([int][bool]$this.IsChecked)" $null 'Changing the scaling...' }))
      } elseif ($line -match '^\s+hdr\s+supported=1 on=(\d)') {
        [void](Add-Row $panel 'HDR' 'The screen goes black for a moment when this changes.' (New-Switch ($Matches[1] -eq '1') @{ display = $n } { Start-Ctl "display -Display $($this.Tag.display) -Set hdr -Value $([int][bool]$this.IsChecked)" $null 'Changing HDR...' }))
      }
    }
    if ($n -lt 0) { [void]$dispHost.Children.Add((X "<TextBlock Text='No monitor answered. See the Activity page.'/>")) }
  } 'Reading the monitors...'
}

function Show-Text([string]$title, [string]$sub, [string]$command, [string]$doing) {
  Add-Title $title $sub
  $bar = X "<StackPanel Orientation='Horizontal' Margin='0,0,0,10'/>"; [void]$Page.Children.Add($bar)
  $script:textBox = X "<TextBox IsReadOnly='True' FontFamily='Consolas' FontSize='12.5' BorderThickness='0' Background='#171026' Padding='14' TextWrapping='NoWrap' HorizontalScrollBarVisibility='Auto' MinHeight='420'/>"
  [void]$Page.Children.Add($textBox)
  if ($command) {
    $b = New-Button 'Refresh' { Start-Ctl $this.Tag.c { param($l) $textBox.Text = ($l -join "`r`n") } $this.Tag.d }; $b.Tag = @{ c = $command; d = $doing }; [void]$bar.Children.Add($b)
    Start-Ctl $command { param($l) $textBox.Text = ($l -join "`r`n") } $doing
  } else {
    $textBox.Text = $activity.ToString(); $textBox.ScrollToEnd()
    [void]$bar.Children.Add((New-Button 'Open the log folder' { Start-Process explorer.exe (Join-Path $env:ProgramData 'SkYn3tLab') }))
    [void]$bar.Children.Add((New-Button 'Newest crash report' { Start-Ctl 'log crash' { param($l) $textBox.Text = ($l -join "`r`n") } 'Reading the newest crash report...' }))
    [void]$bar.Children.Add((New-Button 'Settings changed' { Start-Ctl 'log changes' { param($l) $textBox.Text = ($l -join "`r`n") } 'Reading the settings journal...' }))
    [void]$bar.Children.Add((New-Button 'Recorder state' { Start-Ctl 'log' { param($l) $textBox.Text = ($l -join "`r`n") } 'Reading the black box state...' }))
  }
}

function Show-LightStrip {
  $strip = $win.FindName('Lights'); $strip.Children.Clear()
  $look = (Get-LightProfiles).Values | Select-Object -First 1
  foreach ($line in @($look)) {
    if ("$line" -match '^\w+\s+(\d+)\s+(\d+)\s+(\d+)') {
      $b = New-Object Windows.Controls.Border; $b.Width = 26; $b.Margin = '0,0,4,0'; $b.CornerRadius = 2
      $b.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb([byte]$Matches[1], [byte]$Matches[2], [byte]$Matches[3]))
      [void]$strip.Children.Add($b)
    }
  }
}
Show-LightStrip
. (Join-Path $PSScriptRoot 'om3n-command-history.ps1')
. (Join-Path $PSScriptRoot 'om3n-command-page-history.ps1')
. (Join-Path $PSScriptRoot 'om3n-command-page-sensors.ps1')
. (Join-Path $PSScriptRoot 'om3n-command-hold.ps1')
$holdRun = { param($c, $why) Start-Ctl $c { Read-State } "Holding your settings: $why" }
$holdLog = { param($t) Write-AppLog ("{0:yyyy-MM-dd HH:mm:ss} $t" -f (Get-Date)) }
$script:holdWhen = 'poll'
function Start-Hold([string]$when = 'poll') {
  if (-not (Get-HoldSettings).on) { return }
  $script:holdWhen = $when
  Read-State '' { try { [void](Invoke-HoldCheck -State $state.s -When $holdWhen -Run $holdRun -Log $holdLog -JobsRunning:($jobs.Count -gt 0)) } catch { Write-AppError 'holding the settings' $_ } }
}
$pages = [ordered]@{
  Home = { Show-Home }; Fans = { Show-Fans }; Lighting = { Show-Lighting }; Processor = { Show-Cpu }; Graphics = { Show-Graphics }; Displays = { Show-Displays }
  Sensors = { Show-Sensors }
  Logging = { Show-Logging }
  Alerts = { Show-Alerts }
  Activity = { Show-Text 'Activity' 'Every command this app has run, and what came back. The same goes into the log, with crash reports and the readings recorded in the background.' '' '' }
}
function Select-Page([string]$name) { $state.page = $name; $navButtons[$name].IsChecked = $true; [Dash]::Detail = ($name -eq 'Sensors'); & $pages[$name] }
$navButtons = @{}
foreach ($n in $pages.Keys) {
  $r = X "<RadioButton Style='{DynamicResource Nav}' GroupName='nav'/>"; $r.Content = $n; $r.Tag = $n; $r.Add_Click({ Select-Page $this.Tag }); $navButtons[$n] = $r; [void]$Nav.Children.Add($r)
}
$Page.Add_SizeChanged({ Set-HomeLayout; Set-SensorsLayout })
$dashTimer = New-Object Windows.Threading.DispatcherTimer; $dashTimer.Interval = [TimeSpan]::FromMilliseconds(1000)
$dashTimer.Add_Tick({
    foreach ($a in @(Get-LiveAlerts)) { Write-AppLog $a.log; if ($trayIcon) { $trayIcon.ShowBalloonTip(10000, $a.title, $a.text, [Windows.Forms.ToolTipIcon]$a.icon) } }
    Update-SensorStats
    if ($state.page -eq 'Home' -and $win.IsVisible -and $win.WindowState -ne 'Minimized') { Update-Dash }
    if ($state.page -eq 'Sensors' -and $win.IsVisible -and $win.WindowState -ne 'Minimized') { Update-Sensors }
  })

if ($SelfTest) {
  $win.WindowStartupLocation = 'Manual'; if ($ShotWidth) { $win.Width = $ShotWidth }; if ($ShotHeight) { $win.Height = $ShotHeight }; $win.Left = -12000; $win.Top = 0; $win.ShowInTaskbar = $false; $win.ShowActivated = $false; $win.Show()
  function Wait-Jobs { $end = (Get-Date).AddSeconds(40); do { $f = New-Object Windows.Threading.DispatcherFrame; $null = $win.Dispatcher.BeginInvoke([Action] { $f.Continue = $false }, [Windows.Threading.DispatcherPriority]::Background); [Windows.Threading.Dispatcher]::PushFrame($f); Start-Sleep -Milliseconds 100 } while ($jobs.Count -gt 0 -and (Get-Date) -lt $end); 1..3 | ForEach-Object { $f = New-Object Windows.Threading.DispatcherFrame; $null = $win.Dispatcher.BeginInvoke([Action] { $f.Continue = $false }, [Windows.Threading.DispatcherPriority]::Background); [Windows.Threading.Dispatcher]::PushFrame($f) } }
  foreach ($n in $pages.Keys) {
    Select-Page $n; Wait-Jobs
    if ($n -eq 'Home' -and $ShotWarmSeconds) { $end = (Get-Date).AddSeconds($ShotWarmSeconds); while ((Get-Date) -lt $end) { Wait-Jobs; Start-Sleep -Milliseconds 400 }; Update-Dash; Wait-Jobs }
    if ($n -eq 'Logging') { while ($hist.task) { Wait-Jobs }; Wait-Jobs }
    if ($n -eq 'Sensors') {
      $end = (Get-Date).AddSeconds($(if ($ShotName) { 30 } else { 4 })); while ((Get-Date) -lt $end) { Wait-Jobs; Start-Sleep -Milliseconds 900; Update-SensorStats }
      Update-Sensors; Wait-Jobs
      "selftest: sensors page: $($sens.rows.Count) readings in $(@($sens.panels.Values | Where-Object { $_.order.Count }).Count) groups; threads = $(@($sens.rows.Keys | Where-Object { $_ -match '^thr\d+Load$' }).Count); driver's other readings = $(@($sens.rows.Keys | Where-Object { $_ -match '^adl' }).Count)"
    }
    if ($n -eq 'Home') {
      $end = (Get-Date).AddSeconds(15); while ((Get-Date) -lt $end) { Wait-Jobs; Start-Sleep -Milliseconds 500 }
      Update-Dash; Update-Home; Wait-Jobs
      'selftest: home rows: ' + (($strips | ForEach-Object { "$($_.r.k)=$($_.v.Text)" }) -join '  ')
      'selftest: home facts: ' + (($facts.Keys | ForEach-Object { "$_=$($facts[$_].Text)" }) -join '  ')
      "selftest: fan curve drawn with $($fc.cv.Children.Count) shapes on $([int]$fc.cv.ActualWidth) x $([int]$fc.cv.ActualHeight)"
      "selftest: fan curve = $($fc.vals -join ',') (AMD's: $($fc.defs -join ',')); fan stop switch = $($homeZero.IsChecked); layout = $(if ([Windows.Controls.Grid]::GetColumn($homeGrid.FindName('R')) -eq 2) { 'side by side' } else { 'stacked' }) at page width $([int]$Page.ActualWidth); columns $([int]$homeGrid.FindName('L').ActualWidth) and $([int]$homeGrid.FindName('R').ActualWidth) wide, $([int]$homeGrid.FindName('L').ActualHeight) and $([int]$homeGrid.FindName('R').ActualHeight) tall, chart rows $($strips[0].g.Height) high"
      if ([Dash]::Problems) { 'selftest: sampler problems: ' + ([Dash]::Problems -replace "`n", ' | ') }
      $real = $state.s.held
      $state.s | Add-Member -NotePropertyName held -NotePropertyValue ([pscustomobject]@{ crash = '2026-01-01 00:00:00'; lines = @('cpu -ControlId 0x22 -Value -90', 'gpu -Setting OD_VOLTAGE -Value 1100') }) -Force
      Update-Home; "selftest: crash banner with a made-up held list: $($heldBar.Visibility): $($heldText.Text)"
      $state.s | Add-Member -NotePropertyName held -NotePropertyValue $real -Force
      Update-Home; "selftest: crash banner with the real state: $($heldBar.Visibility)"
      Wait-Jobs   # let the window lay the page out again before its picture is taken
    }
    "selftest: page $n built, $($Page.Children.Count) blocks, status bar '$($Busy.Text)'"
    if ($ShotName) { Set-ShotNeutral; Wait-Jobs }
    if ($ShotDir) {
      $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]($win.ActualWidth * $ShotScale)), ([int]($win.ActualHeight * $ShotScale)), (96 * $ShotScale), (96 * $ShotScale), ([Windows.Media.PixelFormats]::Pbgra32)
      $bmp.Render($win.Content); $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder; $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
      $fs = [IO.File]::Create((Join-Path $ShotDir "om3n-command-$n.png")); $enc.Save($fs); $fs.Close()
    }
  }
  if ($Exercise) {
    $click = { param($c) $c.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
    Select-Page "Fans"; Wait-Jobs; if ($state.fan) { & $click $fanChoice[$state.fan]; Wait-Jobs; "selftest: pressed the fan choice already in force ($($state.fan)); status bar: $($Busy.Text)" }
    Select-Page "Lighting"; Wait-Jobs; if ($lookButtons) { & $click $lookButtons[0]; Wait-Jobs; "selftest: pressed the saved look $($lookButtons[0].Tag); status bar: $($Busy.Text)" }
    $signIn = { "$((Get-Content (Join-Path $env:ProgramData 'SkYn3tLab\om3n-command-startup.txt')) -match 'FanCurve')" }
    Select-Page "Home"; Wait-Jobs
    $wasFan = Get-FanProfile
    if ($wasFan -eq 'custom') { "selftest: graphics fan buttons not pressed: the owner's own curve is in force" }
    foreach ($p in $(if ($wasFan -eq 'custom') { @() } else { @('smart', 'card') + @($wasFan | Where-Object { $_ -ne 'card' -and $fanProfileButtons[$_] }) })) { & $click $fanProfileButtons[$p]; Wait-Jobs; "selftest: pressed graphics fan '$p'; remembered profile = $(Get-FanProfile); sign-in line = '$(& $signIn)'; status bar: $($Busy.Text)" }
    "selftest: last commands run:"; ($activity.ToString() -split "`r?`n" | Where-Object { $_ -match "^> |written to the controller|accepted|fan selection:" } | Select-Object -Last 9) | ForEach-Object { "    $_" }
  }
  "selftest: fan selection read = $($state.fan)   lighting profiles = $((Get-LightProfiles).Keys -join ',')"
  Start-Ctl 'fan bogus' $null 'selftest'; Wait-Jobs; "selftest: a failing command -> status bar: $($Busy.Text)"
  Start-Ctl 'sensors' $null 'selftest' 1; Wait-Jobs; "selftest: a command over its 1 s limit -> status bar: $($Busy.Text)"
  $n0 = @(Get-Content $appLog -ErrorAction SilentlyContinue).Count
  $null = $win.Dispatcher.BeginInvoke([Action] { throw 'selftest: a deliberate error, to prove errors are logged' }); Wait-Jobs
  $new = @(Get-Content $appLog | Select-Object -Skip $n0)
  "selftest: error capture = $(if ($new -match 'APP ERROR .*deliberate error') { 'logged' } else { 'NOT LOGGED' }); app still running = $($win.IsVisible); status bar: $($Busy.Text)"
  Invoke-MoreSelfTest $ShotDir
  $win.Close(); return
}
$script:started = $false
function Start-App {
  if ($started) { return }; $script:started = $true
  Select-Page 'Home'; $dashTimer.Start()
  $script:readyMs = [int]((Get-Date) - [Diagnostics.Process]::GetCurrentProcess().StartTime).TotalMilliseconds
  Write-AppLog ("{0:yyyy-MM-dd HH:mm:ss} APP OPENED (process $PID, ready in $readyMs ms$(if ($Tray) { ', in the notification area' })$(if ($OffScreenSeconds) { ', off-screen check' }))" -f (Get-Date))
  $script:probe = New-Object Windows.Threading.DispatcherTimer; $probe.Interval = [TimeSpan]::FromSeconds(12)
  $probe.Add_Tick({ $probe.Stop(); if ([Dash]::Problems) { Write-AppLog ("{0:yyyy-MM-dd HH:mm:ss} READINGS NOT AVAILABLE: $([Dash]::Problems -replace "`n", ' | ')" -f (Get-Date)) } }); $probe.Start()
  Start-Recorder
  Start-TrayIcon
  Register-HoldEvents { Start-Hold 'unlock' }
  $script:holdFirst = New-Object Windows.Threading.DispatcherTimer; $holdFirst.Interval = [TimeSpan]::FromSeconds(60)
  $holdFirst.Add_Tick({ $holdFirst.Stop(); Start-Hold 'start' }); $holdFirst.Start()
  $script:holdPoll = New-Object Windows.Threading.DispatcherTimer; $holdPoll.Interval = [TimeSpan]::FromMinutes(5)
  $holdPoll.Add_Tick({ if ($jobs.Count -eq 0) { Start-Hold 'poll' } }); $holdPoll.Start()
}
$win.Add_ContentRendered({ Start-App })

$script:recMutex = $null; $script:recording = $false
function Start-Recorder {
  try {
    $script:recMutex = New-Object Threading.Mutex $false, 'Global\SkYn3tLab-om3n-command-blackbox'
    try { $script:recording = $recMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $script:recording = $true }
    if (-not $recording) { Write-AppLog ("{0:yyyy-MM-dd HH:mm:ss} RECORDER not started here: another one is running" -f (Get-Date)); return }
    $script:recOff = Join-Path $bbDir 'recording-off.txt'
    $script:recTimer = New-Object Windows.Threading.DispatcherTimer; $recTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $script:recFirst = $true
    $recTimer.Add_Tick({
        try {
          $n = [Dash]::Samples; if ($n -eq $script:recSeen) { return }; $script:recSeen = $n
          if ($recFirst) {
            $script:recFirst = $false
            $r = Write-CrashReport; if ($r) { Write-AppLog ("{0:yyyy-MM-dd HH:mm:ss} $r" -f (Get-Date)) }
            Remove-OldReadings
            Write-AppLog ("{0:yyyy-MM-dd HH:mm:ss} RECORDER running in the app, one reading every $EverySec s in $bbDir" -f (Get-Date))
          }
          if (-not (Test-Path $recOff)) { Write-Reading }
          $r = Write-ResetReport; if ($r) { Write-AppLog ("{0:yyyy-MM-dd HH:mm:ss} $r" -f (Get-Date)) }
          if ($trayIcon) { $d = [Dash]::Snapshot(); $trayIcon.Text = "Om3n Command`nProcessor $([int]$d['cpuTemp']) C, graphics $([int]$d['gpuTemp']) C" }
        } catch { Write-AppError 'recording a reading' $_ }
      })
    $recTimer.Start()
  } catch { Write-AppError 'starting the recorder' $_ }
}

$script:trayIcon = $null; $script:quitting = $false; $script:toldTray = $false
function Stop-App { $script:quitting = $true; $win.Close() }
function Start-TrayIcon {
  try {
    $script:trayIcon = New-Object Windows.Forms.NotifyIcon
    $trayIcon.Icon = if ($iconBytes) { New-Object Drawing.Icon (New-Object IO.MemoryStream (, $iconBytes)), 16, 16 } else { [Drawing.SystemIcons]::Application }
    $trayIcon.Text = 'Om3n Command'
    $menu = New-Object Windows.Forms.ContextMenuStrip
    [void]$menu.Items.Add('Open Om3n Command', $null, { Show-Window })
    [void]$menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    foreach ($f in @(@('quiet', 'Fans: Quiet'), @('normal', 'Fans: Balanced'), @('turbo', 'Fans: Performance'), @('auto', 'Fans: Om3n'))) {
      $i = $menu.Items.Add($f[1]); $i.Tag = $f[0]
      $i.Add_Click({ Start-Ctl "fan $($this.Tag)" { Read-State } 'Setting the fans...' })
    }
    [void]$menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    [void]$menu.Items.Add('Quit', $null, { Stop-App })
    $menu.Add_Opening({ $now = Get-FanSelection; foreach ($i in $this.Items) { if ($i -is [Windows.Forms.ToolStripMenuItem] -and $i.Tag) { $i.Checked = ($i.Tag -eq $now) } } })
    $trayIcon.ContextMenuStrip = $menu
    $trayIcon.Add_MouseClick({ if ($_.Button -eq 'Left') { Show-Window } })
    $trayIcon.Visible = $true
  } catch { Write-AppError 'starting the notification-area icon' $_ }
}
$winFile = Join-Path $env:ProgramData 'SkYn3tLab\om3n-command-window.json'
$wa = [Windows.SystemParameters]::WorkArea
$saved = $null; try { $saved = Get-Content $winFile -Raw -ErrorAction Stop | ConvertFrom-Json } catch { }
$onScreen = $saved -and $saved.Width -ge $win.MinWidth -and $saved.Height -ge $win.MinHeight -and
  $saved.Left -ge [Windows.SystemParameters]::VirtualScreenLeft - 50 -and $saved.Top -ge [Windows.SystemParameters]::VirtualScreenTop - 50 -and
  $saved.Left + 100 -le [Windows.SystemParameters]::VirtualScreenLeft + [Windows.SystemParameters]::VirtualScreenWidth -and
  $saved.Top + 100 -le [Windows.SystemParameters]::VirtualScreenTop + [Windows.SystemParameters]::VirtualScreenHeight
$win.WindowStartupLocation = 'Manual'
if ($onScreen) { $win.Left = $saved.Left; $win.Top = $saved.Top; $win.Width = $saved.Width; $win.Height = $saved.Height; if ($saved.Maximized) { $win.WindowState = 'Maximized' } }
else { $win.Width = [Math]::Max($win.MinWidth, $wa.Width * 0.85); $win.Height = [Math]::Max($win.MinHeight, $wa.Height * 0.85); $win.Left = $wa.Left + ($wa.Width - $win.Width) / 2; $win.Top = $wa.Top + ($wa.Height - $win.Height) / 2 }
function Save-WindowPlace {
  if ($OffScreenSeconds -or -not $win.IsVisible) { return }
  $b = if ($win.WindowState -eq 'Normal') { New-Object Windows.Rect $win.Left, $win.Top, $win.Width, $win.Height } else { $win.RestoreBounds }
  try { @{ Left = $b.Left; Top = $b.Top; Width = $b.Width; Height = $b.Height; Maximized = ($win.WindowState -eq 'Maximized') } | ConvertTo-Json | Set-Content $winFile } catch { }
}
$win.Add_Closing({
    Save-WindowPlace
    if (-not $quitting -and $trayIcon) {
      $_.Cancel = $true; $win.Hide()
      Write-AppLog ("{0:yyyy-MM-dd HH:mm:ss} WINDOW CLOSED, still running in the notification area" -f (Get-Date))
      if (-not $toldTray -and (Get-AlertSettings).trayTip) { $script:toldTray = $true; $trayIcon.ShowBalloonTip(4000, 'Om3n Command is still running', 'It keeps recording and holding your settings. Click the icon to open it; right-click it to quit.', 'None') }
      return
    }
    Write-AppLog ("{0:yyyy-MM-dd HH:mm:ss} APP CLOSED (process $PID)" -f (Get-Date))
  })
$win.Add_Closed({
    if ($recTimer) { $recTimer.Stop() }
    try { Unregister-HoldEvents } catch { }
    try { Stop-LiveEffect } catch { }   # a vitals or audio effect started here must not outlive the app
    if ($recording) { try { $recMutex.ReleaseMutex() } catch { } }
    if ($trayIcon) { $trayIcon.Visible = $false; $trayIcon.Dispose() }
    $win.Dispatcher.InvokeShutdown()
  })
if ($OffScreenSeconds) {
  $win.WindowStartupLocation = "Manual"; $win.Left = -12000; $win.Top = 0; $win.ShowInTaskbar = $false; $win.ShowActivated = $false
  $close = New-Object Windows.Threading.DispatcherTimer; $close.Interval = [TimeSpan]::FromSeconds($OffScreenSeconds); $close.Add_Tick({ $close.Stop(); $script:quitting = $true; $win.Close() }); $close.Start()
  $script:hideCheck = 'not run'
  $hide = New-Object Windows.Threading.DispatcherTimer; $hide.Interval = [TimeSpan]::FromSeconds([Math]::Max(2, $OffScreenSeconds / 2)); $hide.Add_Tick({ $hide.Stop()
      Show-Window; $v1 = $win.IsVisible; $win.Close(); $v2 = $win.IsVisible; Show-Window; $v3 = $win.IsVisible
      $script:hideCheck = "opened = $v1; after closing it: window visible = $v2, app still running = $(-not $win.Dispatcher.HasShutdownStarted); opened again = $v3" }); $hide.Start()
}
if ($Tray) { Start-App } else { $win.Show() }
[Windows.Threading.Dispatcher]::Run()
if ($OffScreenSeconds) { "close to the notification area: $hideCheck" }
if ($OffScreenSeconds) { "tray and recorder: icon made = $([bool]$trayIcon); recording here = $recording; started in the notification area = $([bool]$Tray); window was visible = $(-not $Tray)" }
if ($OffScreenSeconds) { "app start: first page on screen $readyMs ms after the process started" }
if ($OffScreenSeconds) { "window size from start-up: $([int]$win.Width) x $([int]$win.Height) (saved place used = $([bool]$onScreen); work area $([int]$wa.Width) x $([int]$wa.Height))" }
if ($OffScreenSeconds) { "normal start-up ran: page $($state.page), fan selection read = $($state.fan), processor row = $($strips[0].v.Text), graphics row = $($strips[3].v.Text), points drawn = $($strips[0].p.Points.Count), status bar = $($Busy.Text)" }
