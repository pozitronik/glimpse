{Clipboard-copy flows for the frame-export facade: copy a single frame and
 copy the combined view image. A plain class; TFrameExporter owns one and
 delegates to it.}
unit FrameCopier;

interface

uses
  FrameView, Settings, ExportTargetResolver, ClipboardPublisher,
  FrameRenderPipeline, FrameExportTypes;

type
  TFrameCopier = class
  strict private
    FFrameView: TFrameView;
    FSettings: TPluginSettings;
    FResolver: TExportTargetResolver;
    FClipboardPublisher: TClipboardPublisher;
    FRenderPipeline: TFrameRenderPipeline;
    {The write step of CopyFrame, lifted out of an anonymous closure into a
     named method. ACopyLiveRes is sampled once by CopyFrame and threaded
     in so a settings change while the action is queued cannot disagree
     with the resolution that was promised.}
    procedure WriteFrameToClipboard(AIndex: Integer; ACopyLiveRes: Boolean);
    {The write step of CopyView, likewise lifted out of a closure. Carries
     the OOM guard because a native combined image can exhaust the address
     space and the user needs a domain-specific message.}
    procedure WriteCombinedToClipboard(AForceLiveRes: Boolean);
  public
    {All five collaborators are borrowed; TFrameExporter owns them.}
    constructor Create(AFrameView: TFrameView; ASettings: TPluginSettings;
      AResolver: TExportTargetResolver; AClipboardPublisher: TClipboardPublisher;
      ARenderPipeline: TFrameRenderPipeline);
    {Honours CopyAtLiveResolution. AReExtract fires when native is requested
     AND live cells are not already at native size.}
    procedure CopyFrame(AContextCellIndex: Integer; AReExtract: TReExtractAction = nil);
    {AForceLiveRes overrides SaveAtLiveResolution for this call only (no persist).}
    procedure CopyView(AForceLiveRes: Boolean; AReExtract: TReExtractAction = nil);
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  Vcl.Dialogs, Vcl.Graphics,
  Types;

constructor TFrameCopier.Create(AFrameView: TFrameView; ASettings: TPluginSettings;
  AResolver: TExportTargetResolver; AClipboardPublisher: TClipboardPublisher;
  ARenderPipeline: TFrameRenderPipeline);
begin
  inherited Create;
  FFrameView := AFrameView;
  FSettings := ASettings;
  FResolver := AResolver;
  FClipboardPublisher := AClipboardPublisher;
  FRenderPipeline := ARenderPipeline;
end;

procedure TFrameCopier.WriteFrameToClipboard(AIndex: Integer; ACopyLiveRes: Boolean);
var
`  ToPublish: TBitmap;
  ErrMsg: string;
begin
  {Acquire one bitmap this method owns: RenderCellAtLiveSize returns a
   fresh bitmap; PickSaveBitmap returns an FFrameView-owned cell, so it is
   cloned below. The publisher takes ownership of whatever it is handed.}
  if ACopyLiveRes then
    ToPublish := FRenderPipeline.RenderCellAtLiveSize(AIndex)
  else
    ToPublish := TBitmap.Create;
  try
    if not ACopyLiveRes then
      ToPublish.Assign(FRenderPipeline.PickSaveBitmap(AIndex, False));
    {PublishAs* take ToPublish unconditionally and nil it; the finally
     Free is a nil-safe guard for the path where a publish raises before
     taking ownership.}
    if FSettings.ClipboardAsFileReference then
    begin
      if FClipboardPublisher.PublishAsFileReference(ToPublish) = cprFailed then
        MessageDlg('Clipboard write failed - could not write the temp PNG or publish CF_HDROP. Check %TEMP% has free space and is writable.', mtError, [mbOK], 0);
    end
    else if FClipboardPublisher.PublishAsImage(ToPublish, FSettings.Background, ErrMsg) = cprFailed then
      MessageDlg(BuildClipboardCopyFailureMessage(ErrMsg, False), mtError, [mbOK], 0);
  finally
    ToPublish.Free;
  end;
end;

procedure TFrameCopier.WriteCombinedToClipboard(AForceLiveRes: Boolean);
var
  Bmp: TBitmap;
  ErrMsg: string;
begin
  {CopyBitmapToClipboard fails silently when GlobalAlloc returns 0 for an
   oversized image; the try/except surfaces OOM with a domain-specific
   message instead of the generic OS one.}
  try
    Bmp := FRenderPipeline.RenderWithBanner(FRenderPipeline.RenderCombinedFromCells(AForceLiveRes));
    try
      FRenderPipeline.ApplyCombinedSizeCap(Bmp);
      {Strategy array from ClipboardFormats: legacy targets see opaque
       pixels flattened against FSettings.Background; alpha-aware targets
       see transparent cell gaps via CF_DIBV5.}
      if FSettings.ClipboardAsFileReference then
      begin
        if FClipboardPublisher.PublishAsFileReference(Bmp) = cprFailed then
          MessageDlg('Clipboard write failed - could not write the temp PNG or publish CF_HDROP. Check %TEMP% has free space and is writable.', mtError, [mbOK], 0);
      end
      else if FClipboardPublisher.PublishAsImage(Bmp, FSettings.Background, ErrMsg) = cprFailed then
        MessageDlg(BuildClipboardCopyFailureMessage(ErrMsg, True), mtError, [mbOK], 0);
    finally
      Bmp.Free;
    end;
  except
    on E: EOutOfMemory do
      MessageDlg(Format('Out of memory while building the combined image (%s).' + sLineBreak + sLineBreak + 'The image is too large for this build. Lower the Scale target in Settings, reduce the frame count, or use the 64-bit plugin variant.', [E.Message]), mtError, [mbOK], 0);
    on E: EOutOfResources do
      MessageDlg(Format('Out of system resources while building the combined image (%s).' + sLineBreak + sLineBreak + 'The image is too large. Lower the Scale target in Settings or reduce the frame count.', [E.Message]), mtError, [mbOK], 0);
  end;
end;

procedure TFrameCopier.CopyFrame(AContextCellIndex: Integer; AReExtract: TReExtractAction);
var
  Idx: Integer;
  CopyLiveRes: Boolean;
  WriteAction: TProc;
begin
  if not FResolver.ResolveFrameIndex(AContextCellIndex, Idx) then
    Exit;

  {Single-frame uses CF_BITMAP only (broadest compatibility, frames are
   opaque pf24bit). CopyView needs CF_DIBV5 for cell-gap transparency —
   do NOT collapse the two paths.}
  CopyLiveRes := FSettings.CopyAtLiveResolution;

  WriteAction := procedure begin WriteFrameToClipboard(Idx, CopyLiveRes) end;

  if (not CopyLiveRes) and Assigned(AReExtract) then
    AReExtract([Idx], WriteAction)
  else
    WriteAction;
end;

procedure TFrameCopier.CopyView(AForceLiveRes: Boolean; AReExtract: TReExtractAction);
var
  WriteAction: TProc;
begin
  if FFrameView.CellCount = 0 then
    Exit;
  if FFrameView.ViewMode = vmSingle then
  begin
    {vmSingle's "view" is one frame; route to the single-frame path.}
    CopyFrame(FFrameView.CurrentFrameIndex);
    Exit;
  end;

  WriteAction := procedure begin WriteCombinedToClipboard(AForceLiveRes) end;

  if (not AForceLiveRes) and Assigned(AReExtract) then
    AReExtract(FResolver.BuildSaveIndicesAllLoaded, WriteAction)
  else
    WriteAction;
end;

end.
