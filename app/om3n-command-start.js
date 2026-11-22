var shell = new ActiveXObject('WScript.Shell');
var env = shell.Environment('PROCESS');
var names = [];
for (var e = new Enumerator(env); !e.atEnd(); e.moveNext()) {
  var name = String(e.item()).split('=')[0];
  if (/^(COR_|COMPLUS_)/i.test(name)) names.push(name);
}
for (var i = 0; i < names.length; i++) env.Remove(names[i]);
var files = new ActiveXObject('Scripting.FileSystemObject');
var exe = files.BuildPath(files.GetParentFolderName(files.GetParentFolderName(WScript.ScriptFullName)), 'Om3n Command.exe');
var tray = WScript.Arguments.length === 1 && WScript.Arguments(0) === '-Tray';
shell.Run('"' + exe + '"' + (tray ? ' -Tray' : ''), 1, false);
