param([uint32]$ControlId = 0, [string]$Value = '')
$ErrorActionPreference = 'Stop'
if ([bool]$ControlId -ne [bool]$Value) { throw 'to set a control give both -ControlId and -Value; give neither to read' }
$logs = Get-ChildItem "$env:ProgramData\Intel\Intel Extreme Tuning Utility\Logs" -Filter 'XtuCore*.log' | Sort-Object LastWriteTime -Descending
$before = (Get-Content $logs[0].FullName).Count
$src = @'
using System;
using System.Collections.Generic;
using System.ServiceModel;
using System.ServiceModel.Description;
using System.Text;
namespace IronCity.Common {
  [Serializable] public enum TuningErrorCode { DidNotAttempt, Success, UnknownTuningFailure, InvalidProposal, ReadOnlyControl, DisabledControl, ControlDoesNotExist, BlockedByISO, UndervoltProtection, UnsupportedValueRequested, IllegalVRAddress, TryAgain }
  [Serializable] public struct TuningResult {
    // filled in by the serializer, never by this code, which the compiler would otherwise report as an error
    #pragma warning disable 0649
    private Dictionary<uint, TuningErrorCode> __codes;
    #pragma warning restore 0649
    public TuningErrorCode GeneralCode { get; set; }
    public Dictionary<uint, TuningErrorCode> AllCodes { get { return __codes; } }
  }
  public struct SdkClientToken { public int ProcessId; }
}
namespace IronCity.Core {
  using IronCity.Common;
  public struct XtuTuningControl {
    public uint Id { get; set; }
    public decimal DefaultValue { get; set; }
    public decimal ActiveValue { get; set; }
    public decimal ProposedValue { get; set; }
    public decimal BootValue { get; set; }
    public bool RequiresReboot { get; set; }
    public List<decimal> SupportedValues { get; set; }
    public bool ReadOnly { get; set; }
    public bool Enabled { get; set; }
    public bool RealtimeOnly { get; set; }
    public bool IsFavoredCore { get; set; }
  }
  public struct XtuTuningProposal { public uint Id { get; set; } public decimal Value { get; set; } }
  public struct XtuTuningProposalResult {
    public uint Id { get; set; }
    public decimal Value { get; set; }
    public bool Enabled { get; set; }
    public bool RebootRequired { get; set; }
  }
  // only the operations this tool calls; parameter names are part of the message and match Intel's
  [ServiceContract] public interface IXtuTuning {
    [OperationContract] List<uint> GetControlIds();
    [OperationContract] XtuTuningControl GetControl(uint id);
    [OperationContract] int GetProcessorFamily();
    [OperationContract] bool GetDoRestoreUserValuesOnBoot();
    [OperationContract] void DiscardChanges(SdkClientToken clientToken, out List<XtuTuningProposalResult> changeList);
    [OperationContract] TuningResult ProposeChange(List<XtuTuningProposal> proposals, SdkClientToken clientToken, out List<XtuTuningProposalResult> proposalDelta, out bool requiresReboot, bool isProfile);
    [OperationContract] TuningResult ApplyChanges(bool forceReboot, int tuningDelay, SdkClientToken clientToken);
  }
}
public static class CpuTune {
  static IronCity.Core.IXtuTuning Open(out ChannelFactory<IronCity.Core.IXtuTuning> f) {
    var b = new NetNamedPipeBinding();
    b.MaxReceivedMessageSize = int.MaxValue;
    b.ReaderQuotas.MaxArrayLength = int.MaxValue; b.ReaderQuotas.MaxBytesPerRead = int.MaxValue; b.ReaderQuotas.MaxDepth = 64;
    b.ReaderQuotas.MaxNameTableCharCount = int.MaxValue; b.ReaderQuotas.MaxStringContentLength = int.MaxValue;
    f = new ChannelFactory<IronCity.Core.IXtuTuning>(b, new EndpointAddress("net.pipe://localhost/ExtremeTuningUtility/Tuning"));
    foreach (var op in f.Endpoint.Contract.Operations) { var d = op.Behaviors.Find<DataContractSerializerOperationBehavior>(); if (d != null) d.MaxItemsInObjectGraph = int.MaxValue; }
    f.Credentials.Windows.AllowedImpersonationLevel = System.Security.Principal.TokenImpersonationLevel.Impersonation;
    var ch = f.CreateChannel();
    ((IContextChannel)ch).OperationTimeout = TimeSpan.FromSeconds(30);
    return ch;
  }
  static void Close(object ch, ICommunicationObject f) { try { ((ICommunicationObject)ch).Abort(); } catch {} try { f.Abort(); } catch {} }
  static string Fail(Exception e) { while (e.InnerException != null) e = e.InnerException; return "FAILED: " + e.GetType().FullName + ": " + e.Message; }
  static string Codes(IronCity.Common.TuningResult r) {
    var sb = new StringBuilder("general=" + r.GeneralCode);
    if (r.AllCodes != null) foreach (var kv in r.AllCodes) sb.Append(string.Format(" 0x{0:X}={1}", kv.Key, kv.Value));
    return sb.ToString();
  }
  static Dictionary<uint, IronCity.Core.XtuTuningControl> Snapshot(IronCity.Core.IXtuTuning ch) {
    var d = new Dictionary<uint, IronCity.Core.XtuTuningControl>();
    foreach (uint id in ch.GetControlIds()) d[id] = ch.GetControl(id);
    return d;
  }
  public static string Read() {
    var sb = new StringBuilder(); ChannelFactory<IronCity.Core.IXtuTuning> f; var ch = Open(out f);
    try {
      sb.AppendLine("family=" + ch.GetProcessorFamily());
      sb.AppendLine("restoreOnBoot=" + ch.GetDoRestoreUserValuesOnBoot());
      var ids = ch.GetControlIds();
      sb.AppendLine("controls=" + ids.Count);
      foreach (uint id in ids) {
        var c = ch.GetControl(id); string range = "";
        if (c.SupportedValues != null && c.SupportedValues.Count > 0) {
          decimal lo = c.SupportedValues[0], hi = c.SupportedValues[0];
          foreach (decimal v in c.SupportedValues) { if (v < lo) lo = v; if (v > hi) hi = v; }
          range = lo + ".." + hi;
        }
        sb.AppendLine(string.Format("C|{0}|{1}|{2}|{3}|{4}|{5}|{6}", id, c.DefaultValue, c.ActiveValue, c.BootValue, c.ProposedValue, c.ReadOnly ? "ro" : "rw", range));
      }
    } catch (Exception e) { sb.AppendLine(Fail(e)); } finally { Close(ch, f); }
    return sb.ToString();
  }
  public static string Set(uint controlId, decimal value) {
    var sb = new StringBuilder(); ChannelFactory<IronCity.Core.IXtuTuning> f; var ch = Open(out f);
    try {
      var pre = Snapshot(ch);
      sb.AppendLine("controls=" + pre.Count);
      int pending = 0;
      foreach (var kv in pre) if (kv.Value.ProposedValue != kv.Value.ActiveValue) { pending++; sb.AppendLine(string.Format("PENDING 0x{0:X8} active={1} proposed={2}", kv.Key, kv.Value.ActiveValue, kv.Value.ProposedValue)); }
      if (pending > 0) { sb.AppendLine("ABORT: " + pending + " control(s) already have a pending proposal; nothing sent"); return sb.ToString(); }
      if (!pre.ContainsKey(controlId)) { sb.AppendLine(string.Format("ABORT: the service has no control 0x{0:X8}; nothing sent", controlId)); return sb.ToString(); }
      var c = pre[controlId];
      sb.AppendLine(string.Format("target 0x{0:X8}: default={1} active={2} boot={3} readOnly={4}", controlId, c.DefaultValue, c.ActiveValue, c.BootValue, c.ReadOnly));
      // Intel's own client sends its default token, a process id of 0
      var token = new IronCity.Common.SdkClientToken();
      var proposals = new List<IronCity.Core.XtuTuningProposal>();
      var p = new IronCity.Core.XtuTuningProposal(); p.Id = controlId; p.Value = value; proposals.Add(p);
      sb.AppendLine("proposing value " + p.Value);
      List<IronCity.Core.XtuTuningProposalResult> delta; bool reboot;
      var pr = ch.ProposeChange(proposals, token, out delta, out reboot, false);
      sb.AppendLine("ProposeChange -> " + Codes(pr) + " requiresReboot=" + reboot + " delta=" + (delta == null ? -1 : delta.Count));
      if (delta != null) foreach (var x in delta) sb.AppendLine(string.Format("  delta 0x{0:X8} value={1} enabled={2} reboot={3}", x.Id, x.Value, x.Enabled, x.RebootRequired));
      if (reboot) {
        List<IronCity.Core.XtuTuningProposalResult> dropped; ch.DiscardChanges(token, out dropped);
        sb.AppendLine("requiresReboot was true: discarded our proposal, nothing applied");
      } else {
        // 1 is the tuning delay Intel's client passes (its IntelOcSdkConstants.XtuTuningDelay)
        sb.AppendLine("ApplyChanges -> " + Codes(ch.ApplyChanges(false, 1, token)));
      }
      var post = Snapshot(ch);
      int changed = 0;
      foreach (var kv in post) {
        var a = pre[kv.Key]; var z = kv.Value;
        if (a.ActiveValue != z.ActiveValue || a.BootValue != z.BootValue || a.ProposedValue != z.ProposedValue) { changed++; sb.AppendLine(string.Format("CHANGED 0x{0:X8} active {1}->{2} boot {3}->{4} proposed {5}->{6}", kv.Key, a.ActiveValue, z.ActiveValue, a.BootValue, z.BootValue, a.ProposedValue, z.ProposedValue)); }
      }
      sb.AppendLine("controls changed by this run = " + changed);
    } catch (Exception e) { sb.AppendLine(Fail(e)); } finally { Close(ch, f); }
    return sb.ToString();
  }
}
'@
Add-Type -TypeDefinition $src -ReferencedAssemblies 'System.ServiceModel', 'System.Runtime.Serialization', 'System.Xml'
if ($ControlId) {
  [CpuTune]::Set($ControlId, [decimal]$Value)
  Start-Sleep -Seconds 3
  '--- lines the service logged during this run'
  Get-Content $logs[0].FullName | Select-Object -Skip $before | ForEach-Object { if ($_.Length -gt 170) { $_.Substring(0, 170) } else { $_ } } | Select-Object -First 40
  return
}
$names = @{}
foreach ($l in ($logs | Select-Object -First 40)) {
  Select-String -Path $l.FullName -Pattern '\[0x([0-9A-F]{8})\|([^\]]+)\]' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $names[[Convert]::ToUInt32($_.Groups[1].Value, 16)] = $_.Groups[2].Value }
}
'id         name                                             default    active      boot  proposed     range'
foreach ($line in ([CpuTune]::Read() -split "`r?`n")) {
  if ($line -like 'C|*') {
    $p = $line -split '\|'; $id = [uint32]$p[1]
    '0x{0:X8} {1,-46} {2,9} {3,9} {4,9} {5,9} {6,3} {7}' -f $id, $names[$id], $p[2], $p[3], $p[4], $p[5], $p[6], $p[7]
  } elseif ($line) { $line }
}
