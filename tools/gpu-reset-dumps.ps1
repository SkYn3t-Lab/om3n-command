param([int]$Last = 5)
$kd = Get-ChildItem 'C:\Program Files\WindowsApps\Microsoft.WinDbg*\amd64\kd.exe' -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -Last 1
if (-not $kd) { 'kd.exe not found: install WinDbg (winget install Microsoft.WinDbg)'; exit 1 }
"kd: $($kd.FullName)"
$dumps = Get-ChildItem 'C:\Windows\LiveKernelReports\WATCHDOG\WATCHDOG-*.dmp' | Sort-Object LastWriteTime | Select-Object -Last $Last
foreach ($d in $dumps) {
  "==== {0:yyyy-MM-dd HH:mm:ss}  {1}  {2:N0} KB" -f $d.LastWriteTime, $d.Name, ($d.Length / 1KB)
  $o = & $kd.FullName -z $d.FullName -y 'srv*C:\symbols*https://msdl.microsoft.com/download/symbols' -c '!analyze -v; q' 2>&1 | ForEach-Object { "$_" }
  $o | Where-Object { $_ -match '^(BUGCHECK_CODE|BUGCHECK_P\d|PROCESS_NAME|MODULE_NAME|IMAGE_NAME|IMAGE_VERSION|FAILURE_BUCKET_ID|SYMBOL_NAME|TAG_NOT_DEFINED|VIDEO_ENGINE|Arg\d|DUMP_FILE_ATTRIBUTES|OS_VERSION|BUILDLAB_STR)' -or $_ -match 'Tdr|TDR_|Engine|Recovery' } | Select-Object -First 26 | ForEach-Object { '   ' + $_.Substring(0, [Math]::Min(170, $_.Length)) }
  $i = [array]::IndexOf($o, ($o | Where-Object { $_ -match '^STACK_TEXT' } | Select-Object -First 1))
  if ($i -ge 0) { '   stack:'; $o[($i + 1)..($i + 12)] | Where-Object { $_.Trim() } | ForEach-Object { '     ' + ($_ -replace '^[0-9a-f`]+\s+[0-9a-f`]+\s+:\s+[0-9a-f` ]+:\s*', '').Substring(0, [Math]::Min(110, ($_ -replace '^[0-9a-f`]+\s+[0-9a-f`]+\s+:\s+[0-9a-f` ]+:\s*', '').Length)) } }
}
