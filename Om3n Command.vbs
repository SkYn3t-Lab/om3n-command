Set sh = CreateObject("WScript.Shell")
rc = sh.Run("schtasks.exe /run /tn ""SkYn3tLab-om3n-command-open""", 0, True)
If rc <> 0 Then
  cmd = Left(WScript.ScriptFullName, Len(WScript.ScriptFullName) - 4) & ".cmd"
  sh.Run """" & cmd & """", 0, False
End If
