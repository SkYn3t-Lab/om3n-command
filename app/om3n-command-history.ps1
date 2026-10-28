param([string]$HistoryTest = '', [string]$HistoryTestDir = '')

$historyDir = Join-Path $env:ProgramData 'SkYn3tLab\telemetry'
$alertsFile = Join-Path $env:ProgramData 'SkYn3tLab\om3n-command-alerts.json'
$historySpans = [ordered]@{
  '1h' = @{ name = 'Last hour'; hours = 1 }; '6h' = @{ name = '6 hours'; hours = 6 }
  '24h' = @{ name = '24 hours'; hours = 24 }; '7d' = @{ name = '7 days'; hours = 168 }
}

$historyCode = @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading.Tasks;

public class HistSeries {
  public string Key;
  public double[] Min, Max;     // per bucket; NaN where nothing was recorded
  public bool[] MinFirst;       // inside the bucket, did the low come before the high (the line is drawn in that order)
  public long[] MinSeq, MaxSeq;
  public double Lo = double.NaN, Hi = double.NaN, Sum;
  public long Count;
  public DateTime HiAt;         // when the highest value was read, and the program in front then
  public string HiFront = "";
  public double Avg { get { return Count > 0 ? Sum / Count : double.NaN; } }
}
public class HistResult {
  public DateTime From, To, First, Last;
  public int Buckets, Files, Filled;
  public long Rows, Skipped;
  public double Ms;
  public string Error = "";
  public Dictionary<string, HistSeries> Series = new Dictionary<string, HistSeries>();
}
public static class Hist {
  public static Task<HistResult> ReadAsync(string dir, DateTime from, DateTime to, int buckets) {
    return Task.Run(() => Read(dir, from, to, buckets));
  }
  // Every telemetry file whose date falls in the span, oldest first. Each file is read by its own header, because
  // the recorder sets a file aside (telemetry-<date>-until-<time>.csv) when its list of columns changes.
  public static HistResult Read(string dir, DateTime from, DateTime to, int buckets) {
    var sw = System.Diagnostics.Stopwatch.StartNew();
    var r = new HistResult { From = from, To = to, Buckets = buckets };
    try {
      long span = Math.Max(1, (to - from).Ticks), seq = 0;
      var filled = new bool[buckets];
      var inv = CultureInfo.InvariantCulture;
      if (!Directory.Exists(dir)) { r.Ms = sw.Elapsed.TotalMilliseconds; return r; }
      var files = Directory.GetFiles(dir, "telemetry-*.csv");
      Array.Sort(files, StringComparer.OrdinalIgnoreCase);
      foreach (var f in files) {
        string name = Path.GetFileName(f); DateTime day;
        if (name.Length < 20 || !DateTime.TryParseExact(name.Substring(10, 10), "yyyy-MM-dd", inv, DateTimeStyles.None, out day)) continue;
        if (day < from.Date || day > to.Date) continue;
        r.Files++;
        // the recorder has the newest file open and writes to it every second: share it rather than fail
        using (var fs = new FileStream(f, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete, 65536, FileOptions.SequentialScan))
        using (var sr = new StreamReader(fs, Encoding.UTF8, true, 65536)) {
          string line = sr.ReadLine();
          if (line == null) continue;
          string[] cols = line.Split(',');
          var map = new HistSeries[cols.Length];
          for (int i = 1; i < cols.Length; i++) {
            if (cols[i] == "foreground") continue;
            HistSeries s;
            if (!r.Series.TryGetValue(cols[i], out s)) {
              s = new HistSeries { Key = cols[i], Min = new double[buckets], Max = new double[buckets], MinFirst = new bool[buckets], MinSeq = new long[buckets], MaxSeq = new long[buckets] };
              for (int b = 0; b < buckets; b++) { s.Min[b] = double.NaN; s.Max[b] = double.NaN; }
              r.Series[cols[i]] = s;
            }
            map[i] = s;
          }
          int front = Array.IndexOf(cols, "foreground");
          while ((line = sr.ReadLine()) != null) {
            DateTime t;
            // a line cut short (the machine froze mid-write) or a stray header is counted, not trusted
            if (line.Length < 20 || line[19] != ',' || !Stamp(line, out t)) { r.Skipped++; continue; }
            if (t < from || t > to) continue;
            string[] p = line.Split(',');
            if (p.Length < cols.Length) { r.Skipped++; continue; }
            int bk = (int)Math.Min(buckets - 1, (t - from).Ticks * buckets / span);
            seq++; r.Rows++; filled[bk] = true;
            if (r.Rows == 1 || t < r.First) r.First = t;
            if (t > r.Last) r.Last = t;
            for (int i = 1; i < map.Length; i++) {
              var s = map[i]; double v;
              if (s == null || p[i].Length == 0 || !double.TryParse(p[i], NumberStyles.Float, inv, out v)) continue;
              s.Sum += v; s.Count++;
              if (double.IsNaN(s.Lo) || v < s.Lo) s.Lo = v;
              if (double.IsNaN(s.Hi) || v > s.Hi) { s.Hi = v; s.HiAt = t; s.HiFront = front >= 0 ? p[front] : ""; }
              if (double.IsNaN(s.Min[bk]) || v < s.Min[bk]) { s.Min[bk] = v; s.MinSeq[bk] = seq; }
              if (double.IsNaN(s.Max[bk]) || v > s.Max[bk]) { s.Max[bk] = v; s.MaxSeq[bk] = seq; }
            }
          }
        }
      }
      foreach (var s in r.Series.Values) for (int b = 0; b < buckets; b++) s.MinFirst[b] = s.MinSeq[b] <= s.MaxSeq[b];
      foreach (bool b in filled) if (b) r.Filled++;
    } catch (Exception e) { r.Error = e.Message; }
    r.Ms = sw.Elapsed.TotalMilliseconds;
    return r;
  }
  // "yyyy-MM-dd HH:mm:ss" at the start of a line, read digit by digit (a quarter of the time of DateTime.ParseExact)
  static bool Stamp(string l, out DateTime t) {
    t = DateTime.MinValue;
    int y = N(l, 0, 4), mo = N(l, 5, 2), d = N(l, 8, 2), h = N(l, 11, 2), mi = N(l, 14, 2), s = N(l, 17, 2);
    if (y < 2000 || mo < 1 || mo > 12 || d < 1 || d > DateTime.DaysInMonth(y, mo) || h < 0 || h > 23 || mi < 0 || mi > 59 || s < 0 || s > 59) return false;
    t = new DateTime(y, mo, d, h, mi, s);
    return true;
  }
  static int N(string l, int at, int len) {
    int v = 0;
    for (int i = at; i < at + len; i++) { int c = l[i] - '0'; if (c < 0 || c > 9) return -1; v = v * 10 + c; }
    return v;
  }
  // One reading as shapes for a chart w wide and h high whose scale runs lo..hi: [0] the lines, [1] the faint areas
  // under them, each as "x,y x,y ..." text that PointCollection.Parse takes. Both the low and the high of every
  // bucket are on the line, so a spike one reading long is still drawn after a week is cut down to 400 buckets.
  // A stretch with nothing recorded for 90 s or more (the PC off, the recorder stopped) ends the line: it is left
  // empty, not bridged.
  public static string[][] Shape(HistResult r, string key, double w, double h, double lo, double hi) {
    var lines = new List<string>(); var areas = new List<string>();
    HistSeries s;
    if (r == null || !r.Series.TryGetValue(key, out s) || w <= 0 || h <= 0 || hi <= lo) return new[] { new string[0], new string[0] };
    int n = r.Buckets;
    int gap = Math.Max(1, (int)Math.Ceiling(90 / ((r.To - r.From).TotalSeconds / n)));
    StringBuilder line = null, top = null; double x0 = 0, xl = 0, yl = 0; int prev = 0, pts = 0;
    for (int b = 0; b <= n; b++) {
      bool has = b < n && !double.IsNaN(s.Max[b]);
      if (line != null && (b == n || (has && b - prev > gap))) {
        // a lone reading has no length to draw: give it a short one
        if (pts == 1) { xl += 1.5; Pt(line, xl, yl); Pt(top, xl, yl); }
        Pt(top, xl, h); Pt(top, x0, h);
        lines.Add(line.ToString()); areas.Add(top.ToString()); line = null;
      }
      if (!has) continue;
      double x = (b + 0.5) * w / n, yMax = Y(s.Max[b], h, lo, hi), yMin = Y(s.Min[b], h, lo, hi);
      if (line == null) { line = new StringBuilder(); top = new StringBuilder(); x0 = x; pts = 0; }
      if (s.Min[b] == s.Max[b]) { Pt(line, x, yMax); pts++; }
      else if (s.MinFirst[b]) { Pt(line, x, yMin); Pt(line, x, yMax); pts += 2; }
      else { Pt(line, x, yMax); Pt(line, x, yMin); pts += 2; }
      Pt(top, x, yMax); xl = x; yl = yMax; prev = b;
    }
    return new[] { lines.ToArray(), areas.ToArray() };
  }
  static double Y(double v, double h, double lo, double hi) { return (h - 2) * (1 - Math.Max(0, Math.Min(1, (v - lo) / (hi - lo)))) + 1; }
  static void Pt(StringBuilder sb, double x, double y) {
    if (sb.Length > 0) sb.Append(' ');
    sb.Append(x.ToString("F1", CultureInfo.InvariantCulture)).Append(',').Append(y.ToString("F1", CultureInfo.InvariantCulture));
  }
}
'@
function Import-Hist { if (-not ('Hist' -as [type])) { Add-Type -TypeDefinition $historyCode } }

function Read-History([ValidateSet('1h', '6h', '24h', '7d')][string]$Span = '1h', [int]$Buckets = 400, [string]$Dir = $historyDir, [datetime]$To = (Get-Date), [switch]$Async) {
  Import-Hist
  $from = $To.AddHours(-$historySpans[$Span].hours)
  if ($Async) { [Hist]::ReadAsync($Dir, $from, $To, $Buckets) } else { [Hist]::Read($Dir, $from, $To, $Buckets) }
}

function Get-CrashReports([string]$Dir = $historyDir) {
  $inv = [Globalization.CultureInfo]::InvariantCulture
  foreach ($f in @(Get-ChildItem $Dir -Filter 'crash-*.txt' -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
    $back = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($f.BaseName.Substring(6), 'yyyyMMdd-HHmmss', $inv, 'None', [ref]$back)) { continue }
    $head = @(Get-Content $f.FullName -TotalCount 6 -ErrorAction SilentlyContinue)
    $bug = if (($head -join "`n") -match 'Bugcheck code:\s*(\d+)') { [int64]$Matches[1] } else { $null }
    $stopped = if (($head -join "`n") -match 'Last reading:\s*(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)') { [datetime]$Matches[1] } else { $null }
    $what = if ($null -eq $bug) { 'An unclean shutdown.' } elseif ($bug -eq 0) { 'No blue screen: a hard freeze, a reset or a loss of power.' } else { "A blue screen, code $bug." }
    $what += if ($stopped) { " The last reading before it was at $($stopped.ToString('HH:mm:ss'))." } else { ' No readings before it: the recorder was not running.' }
    [pscustomobject]@{ File = $f.FullName; Back = $back; Stopped = $stopped; At = $(if ($stopped) { $stopped } else { $back }); Bugcheck = $bug; Summary = $what }
  }
}

$alertNames = [ordered]@{ cpuTemp = 'Processor'; gpuHot = 'Graphics card hotspot'; gpuMemTemp = 'Graphics memory'; driveTemp = 'System drive' }
function Get-AlertDefaults {
  @{ on = $true; trayTip = $true; sustainSec = 30; quietMin = 15; coolBy = 5
    limits = @{ cpuTemp = @{ on = $true; warn = 80; hot = 90 }; gpuHot = @{ on = $true; warn = 100; hot = 105 }; gpuMemTemp = @{ on = $true; warn = 90; hot = 100 }; driveTemp = @{ on = $true; warn = 84; hot = 88 } } }
}
function Get-AlertSettings([string]$Path = $alertsFile) {
  $s = Get-AlertDefaults
  $j = $null; try { $j = Get-Content $Path -Raw -ErrorAction Stop | ConvertFrom-Json } catch { }
  if ($j) {
    $num = { param($v, $lo, $hi, $default) $x = 0.0; if ($null -ne $v -and [double]::TryParse("$v", [ref]$x) -and $x -ge $lo -and $x -le $hi) { [int]$x } else { $default } }
    if ($null -ne $j.on) { $s.on = [bool]$j.on }
    if ($null -ne $j.trayTip) { $s.trayTip = [bool]$j.trayTip }
    $s.sustainSec = & $num $j.sustainSec 0 600 $s.sustainSec
    $s.quietMin = & $num $j.quietMin 0 1440 $s.quietMin
    $s.coolBy = & $num $j.coolBy 0 30 $s.coolBy
    foreach ($k in $alertNames.Keys) {
      if ($j.limits -and $j.limits.$k) {
        if ($null -ne $j.limits.$k.on) { $s.limits[$k].on = [bool]$j.limits.$k.on }
        $s.limits[$k].warn = & $num $j.limits.$k.warn 30 120 $s.limits[$k].warn
        $s.limits[$k].hot = & $num $j.limits.$k.hot 30 120 $s.limits[$k].hot
      }
      if ($s.limits[$k].hot -lt $s.limits[$k].warn) { $s.limits[$k].hot = $s.limits[$k].warn }
    }
  }
  $s
}
function Set-AlertSettings($Settings, [string]$Path = $alertsFile) {
  $Settings | ConvertTo-Json -Depth 4 | Set-Content $Path -Encoding UTF8
  if ($Path -eq $alertsFile) { $script:alertSettings = $Settings }   # the running app's tick uses them from the next reading
}

function Get-AlertDecision($Readings, $Settings, $State, [datetime]$Now, [string]$Foreground = '') {
  $new = @{}; $alerts = New-Object Collections.ArrayList; $why = New-Object Collections.ArrayList
  if (-not $Settings.on) { return @{ state = $new; alerts = @(); why = @('alerts are switched off: nothing is watched') } }
  foreach ($k in $alertNames.Keys) {
    $o = if ($State -and $State[$k]) { $State[$k] } else { @{} }
    $s = @{ on = [int]$o.on; since = $o.since; hotSince = $o.hotSince; lastAt = $o.lastAt; lastLevel = [int]$o.lastLevel }; $new[$k] = $s
    if ($Settings.limits[$k].on -eq $false) { $s.on = 0; $s.since = $null; $s.hotSince = $null; [void]$why.Add("${k}: its alert is switched off"); continue }
    $w = [double]$Settings.limits[$k].warn; $h = [Math]::Max($w, [double]$Settings.limits[$k].hot); $c = $w - [double]$Settings.coolBy
    if (-not $Readings -or -not $Readings.ContainsKey($k)) { $s.since = $null; $s.hotSince = $null; [void]$why.Add("${k}: no reading, nothing decided"); continue }
    $v = [double]$Readings[$k]; $vt = '{0:N0}' -f $v
    if ($v -lt $c) {
      [void]$why.Add($(if ($s.on) { "${k}: $vt is below $c (the $w line less $($Settings.coolBy)): the episode is over, re-armed" } else { "${k}: $vt is below the $w line" }))
      $s.on = 0; $s.since = $null; $s.hotSince = $null; continue
    }
    if ($v -lt $w) {
      [void]$why.Add($(if ($s.on) { "${k}: $vt is under the $w line but not yet below ${c}: same episode, nothing new" } elseif ($s.since) { "${k}: $vt dropped back under the $w line: the count starts again" } else { "${k}: $vt is below the $w line" }))
      $s.since = $null; $s.hotSince = $null; continue
    }
    if (-not $s.since) { $s.since = $Now }
    if ($v -ge $h) { if (-not $s.hotSince) { $s.hotSince = $Now } } else { $s.hotSince = $null }
    $held = ($Now - $s.since).TotalSeconds
    $level = 0; if ($held -ge $Settings.sustainSec) { $level = 1 }
    if ($s.hotSince -and ($Now - $s.hotSince).TotalSeconds -ge $Settings.sustainSec) { $level = 2 }
    if ($level -eq 0) { [void]$why.Add(("${k}: $vt is at or over the $w line for {0:N0} s of the $($Settings.sustainSec) s it must last: no alert yet" -f $held)); continue }
    $s.on = $level
    $quietLeft = if ($s.lastAt) { $Settings.quietMin * 60 - ($Now - $s.lastAt).TotalSeconds } else { 0 }
    if ($quietLeft -gt 0 -and $level -le $s.lastLevel) { [void]$why.Add(("${k}: $vt is hot, but an alert went out {0:N0} s ago: quiet for another {1:N0} s" -f ($Now - $s.lastAt).TotalSeconds, $quietLeft)); continue }
    $line = if ($level -eq 2) { $h } else { $w }
    $name = $alertNames[$k]
    $a = @{ key = $k; level = $level; value = $v
      title = "$name is $(if ($level -eq 2) { 'very hot' } else { 'hot' }): $vt C"
      text = "It has been at $line C or more for $($Settings.sustainSec) seconds.$(if ($Foreground) { " In front: $Foreground." })"
      icon = $(if ($level -eq 2) { 'Error' } else { 'Warning' })
      log = ("{0:yyyy-MM-dd HH:mm:ss} ALERT: $name $vt C, at $line C or more for $($Settings.sustainSec) s$(if ($Foreground) { " (in front: $Foreground)" })" -f $Now) }
    [void]$alerts.Add($a)
    [void]$why.Add("${k}: $vt held at or over $line for $($Settings.sustainSec) s: ALERT level $level$(if ($s.lastAt -and $quietLeft -gt 0) { ' (stronger than the last one, so the quiet period does not hold it)' })")
    $s.lastAt = $Now; $s.lastLevel = $level
  }
  @{ state = $new; alerts = @($alerts); why = @($why) }
}

function Get-LiveAlerts {
  if (-not $script:alertSettings) { $script:alertSettings = Get-AlertSettings }
  $r = Get-AlertDecision ([Dash]::Snapshot()) $script:alertSettings $script:alertState (Get-Date) ([Dash]::Foreground())
  $script:alertState = $r.state
  $r.alerts
}

function Test-AlertDecision {
  $set = Get-AlertDefaults; $t0 = [datetime]'2026-01-01 12:00:00'; $st = $null; $ok = $true
  "alert decision check: processor line $($set.limits.cpuTemp.warn) C, strong line $($set.limits.cpuTemp.hot) C, must last $($set.sustainSec) s, quiet $($set.quietMin) min, over below $($set.limits.cpuTemp.warn - $set.coolBy) C"
  $steps = @(
    @(0, 70, 0, 'below the line'),
    @(5, 85, 0, 'a spike begins'),
    @(10, 72, 0, 'the spike ended after 5 s: shorter than it must last'),
    @(60, 82, 0, 'over the line, 0 s'),
    @(75, 83, 0, 'over the line, 15 s'),
    @(79, 78, 0, 'dipped under the line before 30 s: the count starts again'),
    @(80, 82, 0, 'over again, 0 s'),
    @(95, 84, 0, 'over, 15 s'),
    @(110, 85, 1, 'over for 30 s: alert'),
    @(120, 86, 0, 'still hot inside the quiet period: no repeat'),
    @(130, 78, 0, 'under the line but not 5 C under: same episode'),
    @(140, 86, 0, 'over the line again in the same episode: counted afresh, nothing new'),
    @(200, 74, 0, 'cooled below 75: episode over, re-armed'),
    @(260, 85, 0, 'a new episode begins, 0 s'),
    @(290, 86, 0, 'new episode has lasted 30 s, but 180 s after the last alert: held by the quiet period'),
    @(1011, 86, 1, 'still hot and the 15 min quiet period is over: alert again'),
    @(1020, 95, 0, 'over the strong line, 0 s (quiet period for the weaker alert)'),
    @(1050, 96, 2, 'over the strong line for 30 s: stronger alert at once, quiet period or not'),
    @(1060, 97, 0, 'still very hot inside the quiet period: no repeat'),
    @(1070, $null, 0, 'no reading: nothing decided')
  )
  foreach ($s in $steps) {
    $read = @{ gpuHot = 60.0 }; if ($null -ne $s[1]) { $read.cpuTemp = [double]$s[1] }
    $r = Get-AlertDecision $read $set $st $t0.AddSeconds($s[0]) 'game'; $st = $r.state
    $got = [int](@($r.alerts | Where-Object { $_.key -eq 'cpuTemp' } | ForEach-Object { $_.level }) + 0 | Measure-Object -Maximum).Maximum
    $pass = ($got -eq $s[2]) -and (@($r.alerts).Count -eq [int]($s[2] -gt 0)); if (-not $pass) { $ok = $false }
    '{0}  t={1,4} s  processor {2,-4} expect {3} got {4}   [{5}]' -f $(if ($pass) { 'ok  ' } else { 'FAIL' }), $s[0], $(if ($null -eq $s[1]) { 'none' } else { $s[1] }), $s[2], $got, $s[3]
    '        why: ' + (@($r.why | Where-Object { $_ -like 'cpuTemp*' }) -join '; ')
    foreach ($a in $r.alerts) { "        notification: [$($a.icon)] $($a.title) | $($a.text)"; "        log line:     $($a.log)" }
  }
  $st = $null; $n = 0
  foreach ($sec in 0, 30) { $r = Get-AlertDecision @{ driveTemp = 85.0 } $set $st $t0.AddSeconds($sec); $st = $r.state; $n += @($r.alerts).Count }
  $pass = ($n -eq 1 -and $r.alerts[0].key -eq 'driveTemp'); if (-not $pass) { $ok = $false }
  "$(if ($pass) { 'ok  ' } else { 'FAIL' })  system drive at 85 for 30 s -> $n alert: $($r.alerts[0].title) | $($r.alerts[0].text)"
  $off = Get-AlertDefaults; $off.on = $false
  $r = Get-AlertDecision @{ cpuTemp = 99.0 } $off $st $t0.AddSeconds(5000)
  $pass = (@($r.alerts).Count -eq 0); if (-not $pass) { $ok = $false }
  "$(if ($pass) { 'ok  ' } else { 'FAIL' })  alerts switched off, processor 99 -> $(@($r.alerts).Count) alerts   why: $($r.why -join '; ')"
  "alert decision check: $(if ($ok) { 'every step matched' } else { 'A STEP DID NOT MATCH' })"
  if (-not $ok) { $script:historyTestFailed = $true }
}

function Test-AlertSettings([string]$Path) {
  Remove-Item $Path -ErrorAction SilentlyContinue
  $d = Get-AlertSettings $Path; "no file            -> on=$($d.on) processor $($d.limits.cpuTemp.warn)/$($d.limits.cpuTemp.hot) hotspot $($d.limits.gpuHot.warn)/$($d.limits.gpuHot.hot) graphics memory $($d.limits.gpuMemTemp.warn)/$($d.limits.gpuMemTemp.hot) drive $($d.limits.driveTemp.warn)/$($d.limits.driveTemp.hot) lasts $($d.sustainSec) s quiet $($d.quietMin) min"
  $d.limits.cpuTemp.warn = 77; $d.on = $false; $d.quietMin = 5; Set-AlertSettings $d $Path
  $r = Get-AlertSettings $Path; "saved 77, off, 5   -> on=$($r.on) processor $($r.limits.cpuTemp.warn)/$($r.limits.cpuTemp.hot) quiet $($r.quietMin) min   file: $((Get-Content $Path -Raw) -replace '\s+', ' ')"
  Set-Content $Path '{ "on": true, "sustainSec": "abc", "limits": { "cpuTemp": { "warn": 500, "hot": 60 } } }'
  $r = Get-AlertSettings $Path; "nonsense values    -> lasts $($r.sustainSec) s (default kept), processor $($r.limits.cpuTemp.warn)/$($r.limits.cpuTemp.hot) (500 refused; a strong line under the line is raised to it)"
  Set-Content $Path '{ not json'
  $r = Get-AlertSettings $Path; "damaged file       -> on=$($r.on) processor $($r.limits.cpuTemp.warn)/$($r.limits.cpuTemp.hot) (defaults)"
  Remove-Item $Path
}

function Test-History([string]$Dir = $historyDir, [datetime]$To = (Get-Date)) {
  $sw = [Diagnostics.Stopwatch]::StartNew(); Import-Hist; "compiling the reader: $([int]$sw.Elapsed.TotalMilliseconds) ms (once per start of the app, on the first visit to History)"
  "folder: $Dir"
  Get-ChildItem $Dir -Filter 'telemetry-*.csv' | Sort-Object Name | ForEach-Object { '  {0}  {1:N0} bytes' -f $_.Name, $_.Length }
  foreach ($span in $historySpans.Keys) {
    $sw.Restart(); $r = Read-History -Span $span -Dir $Dir -To $To; $first = $sw.Elapsed.TotalMilliseconds
    $sw.Restart(); $r = Read-History -Span $span -Dir $Dir -To $To; $again = $sw.Elapsed.TotalMilliseconds
    $sw.Restart(); $task = Read-History -Span $span -Dir $Dir -To $To -Async; $handed = $sw.Elapsed.TotalMilliseconds; [void]$task.Wait(30000)
    ''
    '{0,-9} files {1}, rows {2:N0}, lines skipped {3}, buckets with readings {4} of {5}, from {6:MM-dd HH:mm:ss} to {7:MM-dd HH:mm:ss}' -f $historySpans[$span].name, $r.Files, $r.Rows, $r.Skipped, $r.Filled, $r.Buckets, $r.First, $r.Last
    '          read: {0:N1} ms first call, {1:N1} ms again; in the background the caller got control back after {2:N2} ms and the task ended with {3:N0} rows{4}' -f $first, $again, $handed, $task.Result.Rows, $(if ($r.Error) { "; ERROR $($r.Error)" })
    foreach ($s in $r.Series.Values) {
      '          {0,-11} lowest {1,8:N1}  average {2,8:N1}  highest {3,8:N1}  ({4:N0} values; highest at {5:MM-dd HH:mm:ss}, in front: {6})' -f $s.Key, $s.Lo, $s.Avg, $s.Hi, $s.Count, $s.HiAt, $s.HiFront
    }
    $sw.Restart(); $shape = [Hist]::Shape($r, 'cpuTemp', 560, 36, 30, 100)
    '          shapes for a 560 x 36 chart of cpuTemp: {0} line(s), {1:N0} characters, {2:N2} ms' -f $shape[0].Count, (($shape[0] | Measure-Object Length -Sum).Sum), $sw.Elapsed.TotalMilliseconds
  }
  ''
  'crash reports:'; $c = @(Get-CrashReports $Dir); if (-not $c) { '  none' }
  foreach ($x in $c) { "  came back $($x.Back.ToString('yyyy-MM-dd HH:mm:ss')); marked at $($x.At.ToString('yyyy-MM-dd HH:mm:ss')); $($x.Summary)" }
}

function Test-HistoryScale([string]$Scratch) {
  if (-not $Scratch -or [IO.Path]::GetFullPath($Scratch).TrimEnd('\') -eq [IO.Path]::GetFullPath($historyDir).TrimEnd('\')) { 'give an empty scratch folder, not the real one'; return }
  if (-not (Test-Path $Scratch)) { New-Item -ItemType Directory $Scratch | Out-Null }
  $src = Get-ChildItem $historyDir -Filter 'telemetry-*.csv' | Sort-Object LastWriteTime | Select-Object -Last 1
  $real = @(Get-Content $src.FullName); $header = $real[0]; $body = @($real | Select-Object -Skip 1 | Where-Object { $_.Length -gt 20 })
  $end = [datetime]'2026-01-08 00:00:00'; $start = $end.AddDays(-7); $n = 0; $sw = [Diagnostics.Stopwatch]::StartNew()
  $spikeAt = $end.AddDays(-3).AddHours(2); $gapFrom = $end.AddHours(-30); $gapTo = $gapFrom.AddHours(2)
  $cpuCol = [Array]::IndexOf($header.Split(','), 'cpuTemp')
  for ($day = $start; $day -lt $end; $day = $day.AddDays(1)) {
    $w = New-Object IO.StreamWriter (Join-Path $Scratch ('telemetry-{0:yyyy-MM-dd}.csv' -f $day)); $w.WriteLine($header)
    for ($t = $day; $t -lt $day.AddDays(1); $t = $t.AddSeconds(5)) {
      if ($t -ge $gapFrom -and $t -lt $gapTo) { continue }
      $l = $body[$n % $body.Count].Substring(19)
      if ($t -eq $spikeAt) { $p = $l.Split(','); $p[$cpuCol] = '99.5'; $l = $p -join ',' }   # one reading, 5 s long
      $w.WriteLine($t.ToString('yyyy-MM-dd HH:mm:ss') + $l); $n++
    }
    if ($day.AddDays(1) -eq $end) { $w.Write('2026-01-07 23:59:5') }   # a line the machine never finished
    $w.Close()
  }
  "wrote $('{0:N0}' -f $n) made-up lines into $Scratch in $([int]$sw.Elapsed.TotalSeconds) s ($('{0:N1}' -f ((Get-ChildItem $Scratch -Filter 'telemetry-*.csv' | Measure-Object Length -Sum).Sum / 1MB)) MB); spike 99.5 at $($spikeAt.ToString('MM-dd HH:mm:ss')), nothing from $($gapFrom.ToString('MM-dd HH:mm')) to $($gapTo.ToString('MM-dd HH:mm'))"
  Test-History $Scratch $end.AddSeconds(-1)
  $r = Read-History -Span 7d -Dir $Scratch -To $end.AddSeconds(-1)
  $s = $r.Series['cpuTemp']; $b = [int][Math]::Floor(($spikeAt - $r.From).Ticks * $r.Buckets / ($r.To - $r.From).Ticks)
  "the 5 s spike after cutting 7 days down to $($r.Buckets) buckets: highest $($s.Hi) at $($s.HiAt.ToString('MM-dd HH:mm:ss')); its bucket holds low $($s.Min[$b]) high $($s.Max[$b]) -> $(if ($s.Max[$b] -eq 99.5) { 'kept' } else { 'LOST' })"
  $shape = [Hist]::Shape($r, 'cpuTemp', 560, 36, 30, 100)
  "the 2 h gap: the 7-day line is drawn in $($shape[0].Count) pieces -> $(if ($shape[0].Count -eq 2) { 'left empty, not bridged' } else { 'NOT AS EXPECTED' })"
}

if ($HistoryTest -eq 'alerts') { Test-AlertDecision; if ($HistoryTestDir) { ''; Test-AlertSettings (Join-Path $HistoryTestDir 'alerts-check.json') } }
elseif ($HistoryTest -eq 'history') { if ($HistoryTestDir) { Test-History $HistoryTestDir } else { Test-History } }
elseif ($HistoryTest -eq 'scale') { Test-HistoryScale $HistoryTestDir }
if ($HistoryTest -and $historyTestFailed) { exit 2 }
