$gameStore = Join-Path $env:ProgramData 'SkYn3tLab\om3n-command-games'

$gameDefs = @{
  arc = @{
    name = 'ARC Raiders'; process = 'PioneerGame'; root = 'LocalApplicationData'; sep = '='; fsr = $true
    scale = 'Quality groups run 0 Low, 1 Medium, 2 High, 3 Epic, 4 Cinematic (Unreal Engine''s scale).'
    files = @(
      @{ copy = 'Steam and Epic'; path = 'PioneerGame\Saved\Config\WindowsClient\GameUserSettings.ini' },
      @{ copy = 'Xbox app'; path = 'PioneerGame\Saved\Config\WinGDKClient\GameUserSettings_*.ini' }
    )
    keys = @(
      @{ k = 'sg.ViewDistanceQuality'; v = '4'; far = $true; d = 'How far objects are drawn in full. The end of distant pop-in.' },
      @{ k = 'sg.TextureQuality'; v = '4'; far = $true; d = 'Texture detail and how far it stays sharp. Costs video memory, not frames.' },
      @{ k = 'sg.LandscapeQuality'; v = '4'; far = $true; d = 'Ground detail at a distance.' },
      @{ k = 'sg.FoliageQuality'; v = '0'; far = $true; d = 'Grass and bush density. At 0 nothing drawn hides a prone player; trees follow the view distance.' },
      @{ k = 'sg.ShadowQuality'; v = '2'; far = $false; d = 'Shadow resolution and distance. Each step up costs frames; the top steps cost about a third of them.' },
      @{ k = 'sg.ShadingQuality'; v = '2'; far = $false; d = 'Material detail.' },
      @{ k = 'sg.AntiAliasingQuality'; v = '2'; far = $false; d = 'Edge smoothing. FSR smooths edges too, so the top steps add little.' },
      @{ k = 'sg.GlobalIlluminationQuality'; v = '1'; far = $false; d = 'Bounced light. It changes nothing at a distance.' },
      @{ k = 'sg.ReflectionQuality'; v = '1'; far = $false; d = 'Reflections.' },
      @{ k = 'sg.PostProcessQuality'; v = '1'; far = $false; d = 'Bloom, depth of field and the like. Lower blurs a target less.' },
      @{ k = 'sg.EffectsQuality'; v = '1'; far = $false; d = 'Particles and effects.' },
      @{ k = 'FSRMode'; v = 'Quality'; far = $false; d = 'Upscaling. Quality renders at 67 percent each way; NativeAA renders every pixel and is the sharpest at range.' },
      @{ k = 'FSRFrameGenerationMode'; v = 'Off'; far = $false; d = 'Frame generation. Off shows only rendered frames; On has the upscaler add a frame between each two, which doubles the shown rate for some input delay.' },
      @{ k = 'sg.ResolutionQuality'; v = '100'; far = $true; d = 'The resolution the game renders before upscaling, in percent. At 100 the FSR mode alone decides the render size.' },
      @{ k = 'ResolutionScalingMethod'; v = 'FSR'; far = $false; d = 'Which upscaler runs. FSR is AMD''s; the FSR mode below applies only with it.' },
      @{ k = 'bAntiLag2Enabled'; v = 'True'; far = $false; d = 'AMD Anti-Lag 2, built into the game: less delay between input and picture on a Radeon.' },
      @{ k = 'bUseVSync'; v = 'False'; far = $false; d = 'Vertical sync. Off leaves tearing to the frame limit and the monitor''s Adaptive-Sync, without its delay.' },
      @{ k = 'MotionBlurMode'; v = 'Off'; far = $false; d = 'Motion blur. Off keeps a moving target sharp.' },
      @{ k = 'LensDistortionEnabled'; v = 'False'; far = $false; d = 'The camera lens warp at the edges of the screen.' },
      @{ k = 'NvReflexMode'; v = 'Off'; far = $false; d = 'NVIDIA Reflex. It works only on NVIDIA cards; Anti-Lag 2 is the Radeon counterpart.' },
      @{ k = 'FrameRateLimit'; v = '165.000000'; far = $false; d = 'The most frames the game renders a second: the monitor''s rate without a frame generator, half of it with one on, since every second frame shown is then generated.' }
    )
    notes = @(
      'The game keeps one audio quality level and offers no choice of it in its Audio menu; nothing to set there.',
      'The game rewrites its file when it exits, so Apply and Revert refuse while it runs.'
    )
  }
  bf6 = @{
    name = 'Battlefield 6'; process = 'bf6'; root = 'MyDocuments'; sep = ' '; fsr = $false
    scale = 'Quality steps run from 0, the lowest, to 3, the highest the file holds; the menu names five steps (Low to Overkill) and EA publishes no table pairing them with the numbers.'
    files = @(
      @{ copy = 'EA app'; path = 'Battlefield 6\settings\PROFSAVEbf6mp_profile' },
      @{ copy = 'Steam'; path = 'Battlefield 6\settings\steam\PROFSAVEbf6mp_profile' }
    )
    keys = @(
      @{ k = 'GstRender.OverallGraphicsQuality'; v = '6'; far = $false; d = 'The preset. 6 is Custom; at 0 (Auto) the game picks the groups again at every start and undoes this set.' },
      @{ k = 'GstRender.TerrainQuality'; v = '3'; far = $true; d = 'Ground detail at a distance.' },
      @{ k = 'GstRender.TextureFiltering'; v = '3'; far = $true; d = 'Textures stay sharp at a slant and at range, for almost no frames.' },
      @{ k = 'GstRender.TextureQuality'; v = '1'; far = $true; d = 'Texture detail. Lower streams less texture data mid-fight, the candidate for the longest frames.' },
      @{ k = 'GstRender.MeshQuality'; v = '2'; far = $true; d = 'Object detail and how far it holds. It loads the processor, which limits this game''s dips.' },
      @{ k = 'GstRender.UndergrowthQuality'; v = '0'; far = $true; d = 'Grass and bushes. At 0 nothing drawn hides a prone player.' },
      @{ k = 'GstRender.ShadowQuality'; v = '0'; far = $false; d = 'Shadows. Lower darkens a target less.' },
      @{ k = 'GstRender.SunShadowQuality'; v = '0'; far = $false; d = 'Shadows cast by the sun.' },
      @{ k = 'GstRender.LocalLightShadowQuality'; v = '0'; far = $false; d = 'Shadows from lamps and fires.' },
      @{ k = 'GstRender.TransparentShadows'; v = '0'; far = $false; d = 'Shadows through smoke and glass.' },
      @{ k = 'GstRender.PostProcessQuality'; v = '0'; far = $false; d = 'Post-processing. Lower blurs a target less.' },
      @{ k = 'GstRender.EffectsQuality'; v = '0'; far = $false; d = 'Particles and explosions.' },
      @{ k = 'GstRender.ReflectionQuality'; v = '0'; far = $false; d = 'Reflections.' },
      @{ k = 'GstRender.ScreenSpaceReflections'; v = '0'; far = $false; d = 'Reflections drawn from what is on screen.' },
      @{ k = 'GstRender.VolumetricQuality'; v = '0'; far = $false; d = 'Fog and light shafts.' },
      @{ k = 'GstRender.LightingQuality'; v = '1'; far = $false; d = 'Lighting.' },
      @{ k = 'GstRender.AmbientOcclusion'; v = '0'; far = $false; d = 'Contact shadows in corners.' },
      @{ k = 'GstRender.WeaponDOF'; v = '0'; far = $false; d = 'The blur around the gun when aiming.' },
      @{ k = 'GstRender.LensDistortion'; v = '0'; far = $false; d = 'The camera lens warp at the edges of the screen.' },
      @{ k = 'GstRender.FrameRateLimiterEnable'; v = '1'; far = $false; d = 'The game''s own frame cap. On, the limit below holds.' },
      @{ k = 'GstRender.FrameRateLimit'; v = '144.000000'; far = $false; d = 'The most frames the game renders a second.' },
      @{ k = 'GstRender.FutureFrameRendering'; v = '1'; far = $false; d = 'The processor prepares the next frame while the card draws this one: smoother when the processor limits, for about one frame of input delay.' }
    )
    notes = @(
      'The game rewrites its profile when it exits, so Apply and Revert refuse while it runs.',
      'GstRender.AMDIntelAntiAliasing is left as it is: what its numbers mean is published nowhere.',
      'An Epic Games Store copy is not listed: its profile''s place has not been read from an installed copy.'
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
    $full = Join-Path ([Environment]::GetFolderPath($def.root)) $f.path
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
    $m = [regex]::Matches($text, '(?m)^' + [regex]::Escape($k.k) + [regex]::Escape($def.sep) + '([^\r\n]*)')
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
  for ($i = Get-Item -LiteralPath $file -Force; $i; $i = $(if ($i -is [IO.FileInfo]) { $i.Directory } else { $i.Parent })) {
    if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "REFUSED: $($i.FullName) is a link; nothing written to $file" }
  }
  $text = [IO.File]::ReadAllText($file)
  $new = $text
  foreach ($k in $values.Keys) {
    if ($null -eq $values[$k]) { throw "no value for $k" }
    $pattern = '(?m)^' + [regex]::Escape($k) + [regex]::Escape($def.sep) + '[^\r\n]*'
    $n = ([regex]::Matches($new, $pattern)).Count
    if ($n -ne 1) { throw "REFUSED: $k is in the file $n times, not once; nothing written to $file" }
    $new = [regex]::Replace($new, $pattern, ($k + $def.sep + $values[$k]).Replace('$', '$$'))
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
