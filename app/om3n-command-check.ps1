$root = Split-Path $PSScriptRoot
$all = Get-ChildItem $root -Recurse -File | Where-Object { $_.Name -notlike '*.out.txt' } | Sort-Object FullName
foreach ($f in $all) {
  $name = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
  if ($f.Extension -eq '.ps1') {
    $t = $null; $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$t, [ref]$e)
    if ($e) { foreach ($x in $e) { 'PARSE {0} line {1} col {2}: {3}' -f $name, $x.Extent.StartLineNumber, $x.Extent.StartColumnNumber, $x.Message } }
    else { "PARSE $name OK" }
  }
  'HASH {0} {1}' -f (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLower(), $name
}
