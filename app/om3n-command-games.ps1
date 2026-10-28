$gameStore = Join-Path $env:ProgramData 'SkYn3tLab\om3n-command-games'

$gameDefs = @{
  arc = @{
    name = 'ARC Raiders'; process = 'PioneerGame'
    files = @(
      @{ copy = 'Steam and Epic'; path = 'PioneerGame\Saved\Config\WindowsClient\GameUserSettings.ini' },
      @{ copy = 'Xbox app'; path = 'PioneerGame\Saved\Config\WinGDKClient\GameUserSettings_*.ini' }
    )
    keys = @(
      @{ k = 'sg.ViewDistanceQuality'; v = '4'; far = $true; d = 'How far objects are drawn in full. The end of distant pop-in.' },
      @{ k = 'sg.TextureQuality'; v = '4'; far = $true; d = 'Texture detail and how far it stays sharp. Costs video memory, not frames.' },
      @{ k = 'sg.LandscapeQuality'; v = '4'; far = $true; d = 'Ground detail at a distance.' },
      @{ k = 'sg.FoliageQuality'; v = '0'; far = $true; d = 'Grass and bush density. At 0 nothing drawn hides a prone player; trees follow the view distance.' },
      @{ k = 'sg.ShadowQuality'; v = '2'; far = $false; d = 'Shadow resolution and distance. High; Cinematic cost a third of the frames.' },
      @{ k = 'sg.ShadingQuality'; v = '2'; far = $false; d = 'Material detail. High.' },
      @{ k = 'sg.AntiAliasingQuality'; v = '2'; far = $false; d = 'Edge smoothing. FSR does this job, so High is enough.' },
      @{ k = 'sg.GlobalIlluminationQuality'; v = '1'; far = $false; d = 'Bounced light. Medium: it changes nothing at a distance.' },
      @{ k = 'sg.ReflectionQuality'; v = '1'; far = $false; d = 'Reflections. Medium.' },
      @{ k = 'sg.PostProcessQuality'; v = '1'; far = $false; d = 'Bloom, depth of field and the like. Medium.' },
      @{ k = 'sg.EffectsQuality'; v = '1'; far = $false; d = 'Particles and effects. Medium.' },
      @{ k = 'FSRMode'; v = 'Quality'; far = $false; d = 'Upscaling. Quality renders at 67 percent each way; NativeAA renders every pixel and is the sharpest at range.' },
      @{ k = 'FSRFrameGenerationMode'; v = 'Off'; far = $false; d = 'Frame generation. Off shows only rendered frames; On has the upscaler add a frame between each two, which doubles the shown rate for some input delay.' },
      @{ k = 'LensDistortionEnabled'; v = 'False'; far = $false; d = 'The camera lens warp at the edges of the screen. Off.' },
      @{ k = 'NvReflexMode'; v = 'Off'; far = $false; d = 'NVIDIA Reflex. Off on a Radeon; Anti-Lag 2 is its counterpart.' },
      @{ k = 'FrameRateLimit'; v = '165.000000'; far = $false; d = 'The most frames the game renders a second: the monitor''s rate without a frame generator, half of it with one on, since every second frame shown is then generated.' }
    )
    notes = @(
      'The game keeps one audio quality level and offers no choice of it in its Audio menu; nothing to set there.',
      'The game rewrites its file when it exits, so Apply and Revert refuse while it runs.'
    )
  }
}

function Get-GameDef([string]$id) {
  if (-not $gameDefs.ContainsKey($id)) { throw "no such game: $id (known: $($gameDefs.Keys -join ', '))" }
  $def = $gameDefs[$id]
  $own = Join-Path $gameStore "tuned-$id.json"
  if (-not (Test-Path $own)) { return $def }
  $picks = Get-Content $own -Raw | ConvertFrom-Json
  $copy = @{}; foreach ($e in $def.GetEnumerator()) { $copy[$e.Key] = $e.Value }
  $copy.keys = @(foreach ($k in $def.keys) { $n = @{}; foreach ($e in $k.GetEnumerator()) { $n[$e.Key] = $e.Value }; $n })
  foreach ($pk in $picks.PSObject.Properties) {
    $hit = $copy.keys | Where-Object { $_.k -eq $pk.Name }
    if (-not $hit) { throw "$own names $($pk.Name), which is not a setting of $($def.name)" }
    $hit.v = "$($pk.Value)"
  }
  $copy
}

function Get-GameFiles($def) {
  $out = @()
  foreach ($f in $def.files) {
    $full = Join-Path $env:LOCALAPPDATA $f.path
    $hits = @(Get-ChildItem -Path $full -File -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($h in $hits) { $out += @{ copy = $f.copy; file = $h.FullName } }
  }
  $out
}

function Read-GameValues($def, [string]$file) {
  $o = [ordered]@{}
  if (-not (Test-Path $file)) { return $o }
  $text = [IO.File]::ReadAllText($file)
  foreach ($k in $def.keys) {
    $m = [regex]::Matches($text, '(?m)^' + [regex]::Escape($k.k) + '=([^\r\n]*)')
    $o[$k.k] = $(if ($m.Count -eq 1) { $m[0].Groups[1].Value } elseif ($m.Count -eq 0) { $null } else { "($($m.Count) lines)" })
  }
  $o
}

function Get-GameOriginalPath([string]$id, [string]$file) { Join-Path $gameStore ("$id-" + (Split-Path -Leaf (Split-Path -Parent $file)) + '-' + (Split-Path -Leaf $file)) }
function Get-GameOriginal($def, [string]$id, [string]$file) {
  $p = Get-GameOriginalPath $id $file
  if (Test-Path $p) { Read-GameValues $def $p } else { $null }
}

function Set-GameValues($def, [string]$id, [string]$file, $values) {
  $text = [IO.File]::ReadAllText($file)
  $new = $text
  foreach ($k in $values.Keys) {
    if ($null -eq $values[$k]) { throw "no value for $k" }
    $pattern = '(?m)^' + [regex]::Escape($k) + '=[^\r\n]*'
    $n = ([regex]::Matches($new, $pattern)).Count
    if ($n -ne 1) { throw "REFUSED: $k is in the file $n times, not once; nothing written to $file" }
    $new = [regex]::Replace($new, $pattern, ($k + '=' + $values[$k]))
  }
  if ($new -eq $text) { return 'already as requested' }
  if (-not (Test-Path $gameStore)) { New-Item -ItemType Directory -Path $gameStore -Force | Out-Null }
  $orig = Get-GameOriginalPath $id $file
  if (-not (Test-Path $orig)) { Copy-Item $file $orig }
  Copy-Item $file ($file + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
  [IO.File]::WriteAllText($file, $new, (New-Object Text.UTF8Encoding($false)))
  'written'
}

function Get-GameSession($def) {
  $tdir = Join-Path $env:ProgramData 'SkYn3tLab\telemetry'
  $files = @(Get-ChildItem $tdir -Filter 'telemetry-*.csv' -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 2)
  if (-not $files) { return $null }
  $rows = @(); foreach ($f in $files) { $rows += @(Import-Csv $f.FullName | Where-Object { $_.foreground -eq $def.process }) }
  if (-not $rows) { return $null }
  $last = @(); $prev = $null
  foreach ($r in $rows) {
    $t = [datetime]::ParseExact($r.time, 'yyyy-MM-dd HH:mm:ss', $null)
    if ($prev -and ($t - $prev).TotalMinutes -gt 10) { $last = @() }
    $last += $r; $prev = $t
  }
  $n = $last.Count; if ($n -lt 30) { return $null }
  $avg = { param($c) ($last | ForEach-Object { [double]$_.$c } | Measure-Object -Average).Average }
  $max = { param($c) ($last | ForEach-Object { [double]$_.$c } | Measure-Object -Maximum).Maximum }
  $fpsRows = @($last | Where-Object { "$($_.fps)" -ne '' -and [double]$_.fps -gt 0 } | ForEach-Object { [double]$_.fps })
  $frameRows = @($last | Where-Object { "$($_.frameMs)" -ne '' -and [double]$_.frameMs -gt 0 } | ForEach-Object { [double]$_.frameMs })
  [ordered]@{
    start = $last[0].time; minutes = [int](([datetime]::ParseExact($last[-1].time, 'yyyy-MM-dd HH:mm:ss', $null) - [datetime]::ParseExact($last[0].time, 'yyyy-MM-dd HH:mm:ss', $null)).TotalMinutes)
    gpuW = [int](& $avg 'gpuW'); gpuWMax = [int](& $max 'gpuW'); gpuLoad = [int](& $avg 'gpuLoad'); gpuMHz = [int](& $avg 'gpuMHz'); gpuHot = [int](& $max 'gpuHot')
    vramGB = [math]::Round((& $max 'vramGB'), 1); cpuLoad = [int](& $avg 'cpuLoad'); cpuTemp = [int](& $max 'cpuTemp')
    fps = $(if ($fpsRows.Count) { [int]($fpsRows | Measure-Object -Average).Average } else { 0 }); fpsMin = $(if ($fpsRows.Count) { [int]($fpsRows | Measure-Object -Minimum).Minimum } else { 0 })
    frameMs = $(if ($frameRows.Count) { [math]::Round(($frameRows | Measure-Object -Average).Average, 1) } else { 0 }); frameMsMax = $(if ($frameRows.Count) { [math]::Round(($frameRows | Measure-Object -Maximum).Maximum, 1) } else { 0 })
  }
}

function Get-FsrTable([int]$w, [int]$h) {
  $native = $w * $h
  foreach ($m in @(@('NativeAA', 1.0), @('Quality', 1.5), @('Balanced', 1.7), @('Performance', 2.0), @('UltraPerformance', 3.0))) {
    $rw = [int][math]::Round($w / $m[1]); $rh = [int][math]::Round($h / $m[1])
    [ordered]@{ mode = $m[0]; factor = $m[1]; width = $rw; height = $rh; share = [int][math]::Round(100 * $rw * $rh / $native) }
  }
}
