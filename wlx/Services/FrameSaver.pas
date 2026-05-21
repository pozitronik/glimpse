{Save flows for the frame-export facade: save a single frame, save every
 (or selected) loaded frame to a directory, and save the combined view
 image. A plain class; TFrameExporter owns one and delegates to it.}
unit FrameSaver;

interface

uses
  FrameView, Settings, ExportTargetResolver, SaveDialogPresenter,
  FrameRenderPipeline, BitmapSaver, FrameExportTypes;

type
  TFrameSaver = class
  strict private
    FFrameView: TFrameView;
    FSettings: TPluginSettings;
    FResolver: TExportTargetResolver;
    FSaveDialog: TSaveDialogPresenter;
    FRenderPipeline: TFrameRenderPipeline;
    {The write step of SaveFrame, lifted out of an anonymous closure so it
     is a named, readable method rather than a buried TProc body.}
    procedure WriteFrameFile(AIndex: Integer; const APath: string; AFormat: TSaveFormat);
    {The write step of SaveView, likewise lifted out of a closure. Carries
     the OOM guard because a native combined image can exhaust the address
     space and the user needs a domain-specific message.}
    procedure WriteCombinedView(const APath: string; AFormat: TSaveFormat);
  public
    {All five collaborators are borrowed; TFrameExporter owns them.}
    constructor Create(AFrameView: TFrameView; ASettings: TPluginSettings;
      AResolver: TExportTargetResolver; ASaveDialog: TSaveDialogPresenter;
      ARenderPipeline: TFrameRenderPipeline);
    {Honours SaveAtLiveResolution. AReExtract runs only after the dialog
     accepts AND the user chose native resolution — keeps the dialog snappy.}
    procedure SaveFrame(const AFileName: string; AContextCellIndex: Integer; AReExtract: TReExtractAction = nil);
    {Selection-aware: writes only selected loaded frames when any are
     selected, otherwise every loaded frame.}
    procedure SaveFrames(const AFileName: string; AReExtract: TReExtractAction = nil);
    {AInitialLiveRes seeds the dialog checkbox on modern Windows; on legacy
     Windows it IS the persisted choice (no inline checkbox there).}
    procedure SaveView(const AFileName: string; AInitialLiveRes: Boolean; AReExtract: TReExtractAction = nil);
    {Dialog-free leaf of the SaveFrames pipeline: iterates loaded cells (or
     selected loaded cells when ASelectedOnly is True), formats per-frame
     names, and writes each through BitmapSaver.}
    procedure SaveFramesToDir(const ADir: string; AFormat: TSaveFormat; ASelectedOnly: Boolean; const AFileName: string);
  end;

implementation

uses
  System.SysUtils, System.Classes, System.UITypes,
  Vcl.Dialogs, Vcl.Graphics,
  FrameCellStore, FrameFileNames, Types;

constructor TFrameSaver.Create(AFrameView: TFrameView; ASettings: TPluginSettings;
  AResolver: TExportTargetResolver; ASaveDialog: TSaveDialogPresenter;
  ARenderPipeline: TFrameRenderPipeline);
begin
  inherited Create;
  FFrameView := AFrameView;
  FSettings := ASettings;
  FResolver := AResolver;
  FSaveDialog := ASaveDialog;
  FRenderPipeline := ARenderPipeline;
end;

procedure TFrameSaver.WriteFrameFile(AIndex: Integer; const APath: string; AFormat: TSaveFormat);
var
  Tmp: TBitmap;
begin
  if FSettings.SaveAtLiveResolution then
  begin
    Tmp := FRenderPipeline.RenderCellAtLiveSize(AIndex);
    try
      BitmapSaver.SaveBitmapToFile(Tmp, APath, AFormat, FSettings.JpegQuality, FSettings.PngCompression);
    finally
      Tmp.Free;
    end;
  end
  else
  begin
    {PickSaveBitmap returns a borrowed FFrameView-owned cell (nil for a
     not-loaded cell); skip a nil rather than hand it to the saver.}
    Tmp := FRenderPipeline.PickSaveBitmap(AIndex, False);
    if Tmp <> nil then
      BitmapSaver.SaveBitmapToFile(Tmp, APath, AFormat, FSettings.JpegQuality, FSettings.PngCompression);
  end;
end;

procedure TFrameSaver.WriteCombinedView(const APath: string; AFormat: TSaveFormat);
var
  Bmp: TBitmap;
begin
  {Native combined images can exhaust 32-bit address space; surface a
   domain-specific error instead of the generic OS message.}
  try
    Bmp := FRenderPipeline.RenderWithBanner(FRenderPipeline.RenderCombinedFromCells(FSettings.SaveAtLiveResolution));
    try
      FRenderPipeline.ApplyCombinedSizeCap(Bmp);
      BitmapSaver.SaveBitmapToFile(Bmp, APath, AFormat, FSettings.JpegQuality, FSettings.PngCompression);
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

procedure TFrameSaver.SaveFramesToDir(const ADir: string; AFormat: TSaveFormat; ASelectedOnly: Boolean; const AFileName: string);
var
  I: Integer;
  Tmp: TBitmap;
  TargetPath: string;
begin
  for I := 0 to FFrameView.CellCount - 1 do
  begin
    if ASelectedOnly and not FFrameView.CellSelected(I) then
      Continue;
    if FFrameView.CellState(I) <> fcsLoaded then
      Continue;
    TargetPath := ADir + GenerateFrameFileName(AFileName, I, FFrameView.CellTimeOffset(I), AFormat);
    if FSettings.SaveAtLiveResolution then
    begin
      Tmp := FRenderPipeline.RenderCellAtLiveSize(I);
      try
        BitmapSaver.SaveBitmapToFile(Tmp, TargetPath, AFormat, FSettings.JpegQuality, FSettings.PngCompression);
      finally
        Tmp.Free;
      end;
    end
    else
    begin
      Tmp := FRenderPipeline.PickSaveBitmap(I, False);
      if Tmp <> nil then
        BitmapSaver.SaveBitmapToFile(Tmp, TargetPath, AFormat, FSettings.JpegQuality, FSettings.PngCompression);
    end;
  end;
end;

procedure TFrameSaver.SaveFrame(const AFileName: string; AContextCellIndex: Integer; AReExtract: TReExtractAction);
var
  Idx: Integer;
  Fmt: TSaveFormat;
  Path: string;
  WriteAction: TProc;
begin
  if not FResolver.ResolveFrameIndex(AContextCellIndex, Idx) then
    Exit;

  {Dialog FIRST so the user gets immediate feedback; the seconds-long
   re-extract runs only after the user commits AND picks native resolution.}
  if not FSaveDialog.Show('Save frame', GenerateFrameFileName(AFileName, Idx, FFrameView.CellTimeOffset(Idx), FSettings.SaveFormat), True, FSettings.SaveAtLiveResolution, Path, Fmt) then
    Exit;

  WriteAction := procedure begin WriteFrameFile(Idx, Path, Fmt) end;

  if (not FSettings.SaveAtLiveResolution) and Assigned(AReExtract) then
    AReExtract([Idx], WriteAction)
  else
    WriteAction;
end;

procedure TFrameSaver.SaveFrames(const AFileName: string; AReExtract: TReExtractAction);
var
  I, FirstIdx: Integer;
  Path: string;
  Fmt: TSaveFormat;
  SelectedOnly: Boolean;
  WriteAction: TProc;
  Indices: TArray<Integer>;
begin
  if FFrameView.CellCount = 0 then
    Exit;

  {Selection-aware: any selection = save just those; else every loaded frame.}
  SelectedOnly := FFrameView.SelectedCount > 0;

  {Sample filename uses the first frame that will actually be written.}
  FirstIdx := 0;
  if SelectedOnly then
    for I := 0 to FFrameView.CellCount - 1 do
      if FFrameView.CellSelected(I) then
      begin
        FirstIdx := I;
        Break;
      end;

  if not FSaveDialog.Show('Save frames', GenerateFrameFileName(AFileName, FirstIdx, FFrameView.CellTimeOffset(FirstIdx), FSettings.SaveFormat), False, FSettings.SaveAtLiveResolution, Path, Fmt) then
    Exit;

  WriteAction := procedure
    begin
      SaveFramesToDir(IncludeTrailingPathDelimiter(ExtractFilePath(Path)), Fmt, SelectedOnly, AFileName);
    end;

  if (not FSettings.SaveAtLiveResolution) and Assigned(AReExtract) then
  begin
    Indices := FResolver.BuildSaveIndicesSelectedOrAll;
    AReExtract(Indices, WriteAction);
  end
  else
    WriteAction;
end;

procedure TFrameSaver.SaveView(const AFileName: string; AInitialLiveRes: Boolean; AReExtract: TReExtractAction);
var
  Fmt: TSaveFormat;
  Path, BaseName: string;
  WriteAction: TProc;
begin
  if FFrameView.CellCount = 0 then
    Exit;

  {vmSingle's "view" is a single frame; route to SaveFrame. The per-call
   AInitialLiveRes is intentionally NOT threaded through — the view/frame
   distinction collapses here.}
  if FFrameView.ViewMode = vmSingle then
  begin
    SaveFrame(AFileName, FFrameView.CurrentFrameIndex, AReExtract);
    Exit;
  end;

  BaseName := ChangeFileExt(ExtractFileName(AFileName), '');
  if not FSaveDialog.Show('Save view', BaseName + '_view.png', True, AInitialLiveRes, Path, Fmt) then
    Exit;

  WriteAction := procedure begin WriteCombinedView(Path, Fmt) end;

  if (not FSettings.SaveAtLiveResolution) and Assigned(AReExtract) then
    AReExtract(FResolver.BuildSaveIndicesAllLoaded, WriteAction)
  else
    WriteAction;
end;

end.
