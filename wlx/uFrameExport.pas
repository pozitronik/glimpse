{Frame export operations: save to file and copy to clipboard.
 Extracted from TPluginForm to isolate I/O from UI orchestration.}
unit uFrameExport;

interface

uses
  Vcl.Graphics,
  uFrameView, uSettings, uBitmapSaver, uCombinedImage, uFrameOffsets;

type
  {Handles save-to-file and copy-to-clipboard for video frames.}
  TFrameExporter = class
  strict private
    FFrameView: TFrameView;
    FSettings: TPluginSettings;
    FBannerInfo: TBannerInfo;
    function ShowSaveDialog(const ATitle, ADefaultName: string; AOverwritePrompt: Boolean; out APath: string; out AFormat: TSaveFormat): Boolean;
    procedure SaveFramesToDir(const ADir: string; AFormat: TSaveFormat; ASelectedOnly: Boolean; const AFileName: string);
    function CollectFramesAndOffsets(out AFrames: TArray<TBitmap>; out AOffsets: TFrameOffsetArray): Integer;
    procedure BuildGridStyle(out AGrid: TCombinedGridStyle);
    procedure BuildTimestampStyle(out ATs: TTimestampStyle);
    function CountLiveGridColumns: Integer;
    function ScaleBitmapLetterbox(ASrc: TBitmap; AW, AH: Integer; ABg: TColor): TBitmap;
    function ScaleBitmapCropToFill(ASrc: TBitmap; AW, AH: Integer): TBitmap;
    function RenderCellAtLiveSize(AIndex: Integer): TBitmap;
    function RenderGridCombinedAtLiveResolution: TBitmap;
    function RenderSmartCombinedFromCells: TBitmap;
  protected
    function RenderCombinedFromCells: TBitmap;
    function RenderWithBanner(ABmp: TBitmap): TBitmap;
  public
    constructor Create(AFrameView: TFrameView; ASettings: TPluginSettings);
    {Resolves which frame to act on: prefers AContextCellIndex, falls back
     to current frame index, then 0. Returns False if no loaded frame found.}
    function ResolveFrameIndex(AContextCellIndex: Integer; out AIndex: Integer): Boolean;
    procedure SaveSingleFrame(const AFileName: string; AContextCellIndex: Integer);
    procedure SaveSelectedFrames(const AFileName: string);
    procedure SaveCombinedFrame(const AFileName: string);
    procedure SaveAllFrames(const AFileName: string);
    procedure CopyFrameToClipboard(AContextCellIndex: Integer);
    procedure CopyAllToClipboard;
    procedure UpdateBannerInfo(const AInfo: TBannerInfo);
  end;

implementation

uses
  Winapi.Windows, Winapi.ShlObj,
  System.SysUtils, System.Types, System.Math,
  Vcl.Clipbrd, Vcl.Dialogs,
  uClipboardImage, uFrameFileNames, uPathExpand, uTypes,
  uViewModeLayout;

type
  {Re-bind TBitmap to the VCL class. Winapi.Windows (pulled in for
   IFileDialogCustomize support) declares its own TBITMAP record alias,
   which would otherwise shadow Vcl.Graphics.TBitmap throughout this
   implementation.}
  TBitmap = Vcl.Graphics.TBitmap;

const
  {Arbitrary control id for the inline 'save at live resolution' check button
   on the modern (Vista+) file save dialog. Must be unique within the dialog;
   1001 is well clear of any control ids the system uses.}
  ID_CHK_LIVE_RES = 1001;
  LIVE_RES_LABEL = 'Save at view resolution';

type
  {Bridges TFileSaveDialog with the Win32 IFileDialogCustomize interface,
   which the Delphi VCL wrapper does not expose. The check button must be
   added before the dialog window is created (DoOnExecute fires just
   before Show), and its final state must be read while the dialog is
   still alive (OnFileOkClick fires inside the modal loop). After the
   dialog closes, TCustomFileDialog clears its internal IFileDialog
   reference, so a query attempt after Execute returns is too late.}
  TLiveResDialogHook = class
  strict private
    FDialog: TCustomFileDialog;
    FInitialState: Boolean;
    FFinalState: Boolean;
    procedure HandleExecute(Sender: TObject);
    procedure HandleFileOkClick(Sender: TObject; var CanClose: Boolean);
  public
    constructor Create(ADialog: TCustomFileDialog; AInitialState: Boolean);
    procedure Attach;
    property FinalState: Boolean read FFinalState;
  end;

constructor TLiveResDialogHook.Create(ADialog: TCustomFileDialog; AInitialState: Boolean);
begin
  inherited Create;
  FDialog := ADialog;
  FInitialState := AInitialState;
  FFinalState := AInitialState; {Preserve current value if the user cancels mid-flight.}
end;

procedure TLiveResDialogHook.Attach;
begin
  FDialog.OnExecute := HandleExecute;
  FDialog.OnFileOkClick := HandleFileOkClick;
end;

procedure TLiveResDialogHook.HandleExecute(Sender: TObject);
var
  Customize: IFileDialogCustomize;
begin
  if Supports(FDialog.Dialog, IFileDialogCustomize, Customize) then
    Customize.AddCheckButton(ID_CHK_LIVE_RES, LIVE_RES_LABEL, FInitialState);
end;

procedure TLiveResDialogHook.HandleFileOkClick(Sender: TObject; var CanClose: Boolean);
var
  Customize: IFileDialogCustomize;
  Checked: BOOL;
begin
  CanClose := True;
  if Supports(FDialog.Dialog, IFileDialogCustomize, Customize) then
  begin
    Checked := False;
    if Succeeded(Customize.GetCheckButtonState(ID_CHK_LIVE_RES, Checked)) then
      FFinalState := Checked;
  end;
end;

{TFrameExporter}

constructor TFrameExporter.Create(AFrameView: TFrameView; ASettings: TPluginSettings);
begin
  inherited Create;
  FFrameView := AFrameView;
  FSettings := ASettings;
end;

function TFrameExporter.ResolveFrameIndex(AContextCellIndex: Integer; out AIndex: Integer): Boolean;
begin
  Result := False;
  if FFrameView.CellCount = 0 then
    Exit;
  {Prefer the right-clicked cell, fall back to current frame, then index 0}
  AIndex := AContextCellIndex;
  if (AIndex < 0) or (AIndex >= FFrameView.CellCount) then
    AIndex := FFrameView.CurrentFrameIndex;
  if (AIndex < 0) or (AIndex >= FFrameView.CellCount) then
    AIndex := 0;
  Result := FFrameView.CellState(AIndex) = fcsLoaded;
end;

{Builds the frames + offsets arrays from the live cells.
 nil entries for placeholder/error cells; the renderer skips them.}
function TFrameExporter.CollectFramesAndOffsets(out AFrames: TArray<TBitmap>;
  out AOffsets: TFrameOffsetArray): Integer;
var
  I: Integer;
begin
  Result := FFrameView.CellCount;
  SetLength(AFrames, Result);
  SetLength(AOffsets, Result);
  for I := 0 to Result - 1 do
  begin
    if FFrameView.CellState(I) = fcsLoaded then
      AFrames[I] := FFrameView.CellBitmap(I)
    else
      AFrames[I] := nil;
    AOffsets[I].TimeOffset := FFrameView.CellTimeOffset(I);
  end;
end;

procedure TFrameExporter.BuildGridStyle(out AGrid: TCombinedGridStyle);
begin
  AGrid.Columns := 0; {auto columns (= ceil(sqrt(N))) by default; callers override when needed}
  AGrid.CellGap := FSettings.CellGap;
  AGrid.Border := FSettings.CombinedBorder;
  AGrid.Background := FSettings.Background;
  AGrid.BackgroundAlpha := FSettings.BackgroundAlpha;
end;

procedure TFrameExporter.BuildTimestampStyle(out ATs: TTimestampStyle);
begin
  ATs.Show := FFrameView.ShowTimecode;
  ATs.Corner := FSettings.TimestampCorner;
  ATs.FontName := FSettings.TimestampFontName;
  ATs.FontSize := FSettings.TimestampFontSize;
  ATs.FontStyles := []; {Match the WLX live view; WCX uses [fsBold]}
  ATs.BackColor := FSettings.TimecodeBackColor;
  ATs.BackAlpha := FSettings.TimecodeBackAlpha;
  ATs.TextColor := FSettings.TimestampTextColor;
  ATs.TextAlpha := FSettings.TimestampTextAlpha;
end;

{Counts the columns the live grid layout is currently using by iterating
 cells and counting those that share row 0's top coordinate. Reliable for
 vmGrid because row tops are uniform there. Used only by the live-res
 grid save path, so it is never called for smart, single, filmstrip, or
 scroll modes.}
function TFrameExporter.CountLiveGridColumns: Integer;
var
  R0: TRect;
  I: Integer;
begin
  Result := 0;
  if FFrameView.CellCount = 0 then
    Exit(1);
  R0 := FFrameView.GetCellRect(0);
  for I := 0 to FFrameView.CellCount - 1 do
    if FFrameView.GetCellRect(I).Top = R0.Top then
      Inc(Result);
  if Result < 1 then
    Result := 1;
end;

{Letterbox-scales ASrc to fit AW x AH, filling unused area with ABg.
 Mirrors TFrameView.PaintLoadedFrame (vmGrid live view) so saved cells
 look identical to what the user sees when SaveAtLiveResolution is on.
 Caller owns the returned bitmap.}
function TFrameExporter.ScaleBitmapLetterbox(ASrc: TBitmap; AW, AH: Integer; ABg: TColor): TBitmap;
var
  Scale: Double;
  DW, DH: Integer;
  DstR: TRect;
begin
  Result := TBitmap.Create;
  try
    Result.PixelFormat := pf24bit;
    Result.SetSize(AW, AH);
    Result.Canvas.Brush.Color := ABg;
    Result.Canvas.FillRect(Rect(0, 0, AW, AH));
    if (ASrc = nil) or (ASrc.Width <= 0) or (ASrc.Height <= 0) then
      Exit;
    Scale := Min(AW / ASrc.Width, AH / ASrc.Height);
    DW := Max(1, Round(ASrc.Width * Scale));
    DH := Max(1, Round(ASrc.Height * Scale));
    DstR.Left := (AW - DW) div 2;
    DstR.Top := (AH - DH) div 2;
    DstR.Right := DstR.Left + DW;
    DstR.Bottom := DstR.Top + DH;
    SetStretchBltMode(Result.Canvas.Handle, HALFTONE);
    SetBrushOrgEx(Result.Canvas.Handle, 0, 0, nil);
    Result.Canvas.StretchDraw(DstR, ASrc);
  except
    Result.Free;
    raise;
  end;
end;

{Crop-to-fill scaling. Mirrors TFrameView.PaintCropToFill (vmSmartGrid
 live view) so saved smart-grid cells preserve aspect ratio without
 letterbox bands. Caller owns the returned bitmap.}
function TFrameExporter.ScaleBitmapCropToFill(ASrc: TBitmap; AW, AH: Integer): TBitmap;
var
  Scale: Double;
  SrcW, SrcH: Integer;
  SrcR: TRect;
begin
  Result := TBitmap.Create;
  try
    Result.PixelFormat := pf24bit;
    Result.SetSize(AW, AH);
    if (ASrc = nil) or (ASrc.Width <= 0) or (ASrc.Height <= 0) then
    begin
      Result.Canvas.Brush.Color := FSettings.Background;
      Result.Canvas.FillRect(Rect(0, 0, AW, AH));
      Exit;
    end;
    Scale := Max(AW / ASrc.Width, AH / ASrc.Height);
    SrcW := Min(ASrc.Width, Round(AW / Scale));
    SrcH := Min(ASrc.Height, Round(AH / Scale));
    SrcR.Left := (ASrc.Width - SrcW) div 2;
    SrcR.Top := (ASrc.Height - SrcH) div 2;
    SrcR.Right := SrcR.Left + SrcW;
    SrcR.Bottom := SrcR.Top + SrcH;
    SetStretchBltMode(Result.Canvas.Handle, HALFTONE);
    SetBrushOrgEx(Result.Canvas.Handle, 0, 0, nil);
    Result.Canvas.CopyRect(Rect(0, 0, AW, AH), ASrc.Canvas, SrcR);
  except
    Result.Free;
    raise;
  end;
end;

{Renders a single cell at the size and fitting mode the live view is
 currently using for that cell. vmSmartGrid uses crop-to-fill; every
 other mode uses letterbox-fit. Used by single-frame save and clipboard
 copy when SaveAtLiveResolution is on.}
function TFrameExporter.RenderCellAtLiveSize(AIndex: Integer): TBitmap;
var
  Src: TBitmap;
  R: TRect;
  W, H: Integer;
begin
  Src := FFrameView.CellBitmap(AIndex);
  R := FFrameView.GetCellRect(AIndex);
  W := Max(1, R.Width);
  H := Max(1, R.Height);
  if FFrameView.ViewMode = vmSmartGrid then
    Result := ScaleBitmapCropToFill(Src, W, H)
  else
    Result := ScaleBitmapLetterbox(Src, W, H, FSettings.Background);
end;

{Live-resolution variant of the grid render: cell pixel size matches what
 vmGrid is currently showing on screen, and the column count tracks the
 live layout. Frames are pre-letterboxed to the live cell dimensions, then
 fed to the same uniform-grid renderer the native path uses. This keeps
 alpha lifting, timecode rendering, and border/gap math centralised.}
function TFrameExporter.RenderGridCombinedAtLiveResolution: TBitmap;
var
  Frames, Scaled: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Ts: TTimestampStyle;
  CellRect: TRect;
  CellW, CellH, Cols, I, N: Integer;
begin
  N := CollectFramesAndOffsets(Frames, Offsets);
  if N = 0 then
    Exit(nil);

  CellRect := FFrameView.GetCellRect(0);
  CellW := Max(1, CellRect.Width);
  CellH := Max(1, CellRect.Height);
  Cols := CountLiveGridColumns;

  BuildGridStyle(Grid);
  Grid.Columns := Cols;
  BuildTimestampStyle(Ts);

  SetLength(Scaled, N);
  try
    for I := 0 to N - 1 do
      if Frames[I] <> nil then
        Scaled[I] := ScaleBitmapLetterbox(Frames[I], CellW, CellH, FSettings.Background)
      else
        Scaled[I] := nil;

    Result := RenderCombinedImage(Scaled, Offsets, Grid, Ts);
  finally
    for I := 0 to High(Scaled) do
      Scaled[I].Free;
  end;
end;

{Renders the live smart-grid arrangement to a combined image. Row counts
 come from ComputeSmartGridRows fed with the panel's inner aspect ratio,
 so the saved arrangement matches what the user sees at the moment of
 save. Output dimensions follow the FSettings.SaveAtLiveResolution toggle:
 - True: panel inner area + Border (pixel-faithful to the live view)
 - False: anchor to the row with the most cells, sized at native frame
   width; total inner aspect ratio still tracks the panel so rows look
   the same shape as on screen.}
function TFrameExporter.RenderSmartCombinedFromCells: TBitmap;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Ts: TTimestampStyle;
  RowCounts: TArray<Integer>;
  N, I, Border, Gap: Integer;
  PanelInnerW, PanelInnerH: Integer;
  OutputW, OutputH, InnerW, InnerH: Integer;
  MaxCells, NativeW: Integer;
  AspectRatio: Double;
begin
  N := CollectFramesAndOffsets(Frames, Offsets);
  if N = 0 then
    Exit(nil);

  BuildGridStyle(Grid);
  BuildTimestampStyle(Ts);
  Border := Max(0, Grid.Border);
  Gap := Max(0, Grid.CellGap);

  {Panel inner area drives the smart-grid arrangement. Falls back to a
   16:9 box when the FrameView has not been sized yet (e.g., save
   triggered before the lister fully laid out).}
  PanelInnerW := Max(1, FFrameView.BaseW - 2 * FFrameView.CellMargin);
  PanelInnerH := Max(1, FFrameView.BaseH - 2 * FFrameView.CellMargin);
  if (PanelInnerW <= 1) or (PanelInnerH <= 1) then
  begin
    PanelInnerW := 1600;
    PanelInnerH := 900;
  end;

  AspectRatio := FFrameView.AspectRatio;
  if AspectRatio <= 0 then
    AspectRatio := 9.0 / 16.0;

  RowCounts := ComputeSmartGridRows(N, PanelInnerW, PanelInnerH, Gap, AspectRatio);
  if Length(RowCounts) = 0 then
    Exit(nil);

  if FSettings.SaveAtLiveResolution then
  begin
    {Pixel-faithful to the live view: total output = panel size, inner
     area = panel inner. Border setting still wraps the inner area so
     saved images and live view stay visually consistent.}
    InnerW := PanelInnerW;
    InnerH := PanelInnerH;
    OutputW := InnerW + 2 * Border;
    OutputH := InnerH + 2 * Border;
  end
  else
  begin
    {Native: anchor inner_W to the widest row, then preserve the panel's
     inner aspect ratio so rows look the same as on screen. NativeW comes
     from the first non-nil frame; uniform across a video.}
    MaxCells := 1;
    for I := 0 to High(RowCounts) do
      if RowCounts[I] > MaxCells then
        MaxCells := RowCounts[I];

    NativeW := 320;
    for I := 0 to N - 1 do
      if (Frames[I] <> nil) and (Frames[I].Width > 0) then
      begin
        NativeW := Frames[I].Width;
        Break;
      end;

    InnerW := MaxCells * NativeW + Max(MaxCells - 1, 0) * Gap;
    InnerH := Max(1, Round(InnerW * (PanelInnerH / PanelInnerW)));
    OutputW := InnerW + 2 * Border;
    OutputH := InnerH + 2 * Border;
  end;

  Result := RenderSmartCombinedImage(Frames, Offsets, RowCounts, OutputW, OutputH, Grid, Ts);
end;

{Renders the frames into a single combined image. The exact layout
 depends on the live view mode and the SaveAtLiveResolution setting:

 - vmSmartGrid: smart layout, arrangement matches what the user sees;
   pixel size follows SaveAtLiveResolution (panel size when on, native
   anchored to widest row when off).
 - vmGrid: regular grid; cell size and column count follow the live
   layout when SaveAtLiveResolution is on, native otherwise.
 - vmFilmstrip / vmScroll / vmSingle: regular grid at native frame
   size, irrespective of the toggle. These layouts do not have a
   meaningful "combined image" interpretation, so the historical
   view-mode-independent behaviour is preserved for them.

 Returns nil only when there are no cells; placeholder/error cells are
 passed through as nil bitmaps and skipped by the renderer.}
function TFrameExporter.RenderCombinedFromCells: TBitmap;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Ts: TTimestampStyle;
  N: Integer;
begin
  if FFrameView.ViewMode = vmSmartGrid then
    Exit(RenderSmartCombinedFromCells);

  if FSettings.SaveAtLiveResolution and (FFrameView.ViewMode = vmGrid) then
    Exit(RenderGridCombinedAtLiveResolution);

  N := CollectFramesAndOffsets(Frames, Offsets);
  if N = 0 then
    Exit(nil);

  BuildGridStyle(Grid);
  BuildTimestampStyle(Ts);

  Result := RenderCombinedImage(Frames, Offsets, Grid, Ts);
end;

function TFrameExporter.RenderWithBanner(ABmp: TBitmap): TBitmap;
var
  Style: TBannerStyle;
begin
  if FSettings.ShowBanner then
  begin
    Style.Background := FSettings.BannerBackground;
    Style.TextColor := FSettings.BannerTextColor;
    Style.FontName := FSettings.BannerFontName;
    Style.FontSize := FSettings.BannerFontSize;
    Style.AutoSize := FSettings.BannerFontAutoSize;
    Style.Position := FSettings.BannerPosition;
    Result := AttachBanner(ABmp, FormatBannerLines(FBannerInfo), Style);
    ABmp.Free;
  end
  else
    Result := ABmp;
end;

procedure TFrameExporter.UpdateBannerInfo(const AInfo: TBannerInfo);
begin
  FBannerInfo := AInfo;
end;

function TFrameExporter.ShowSaveDialog(const ATitle, ADefaultName: string; AOverwritePrompt: Boolean; out APath: string; out AFormat: TSaveFormat): Boolean;
var
  ModernDlg: TFileSaveDialog;
  Hook: TLiveResDialogHook;
  PngType, JpegType: TFileTypeItem;
  LegacyDlg: TSaveDialog;
  ModernHandled: Boolean;
begin
  Result := False;
  ModernHandled := False;

  {Modern Vista+ dialog with an inline 'live resolution' check button.
   Falls through to the legacy TSaveDialog if the platform refuses the
   modern dialog (pre-Vista or unusual COM environments). The legacy
   path has no checkbox; the same toggle is reachable via the settings
   dialog there.}
  if Win32MajorVersion >= 6 then
  begin
    try
      ModernDlg := TFileSaveDialog.Create(nil);
      try
        Hook := TLiveResDialogHook.Create(ModernDlg, FSettings.SaveAtLiveResolution);
        try
          ModernDlg.Title := ATitle;

          PngType := ModernDlg.FileTypes.Add;
          PngType.DisplayName := 'PNG image';
          PngType.FileMask := '*.png';
          JpegType := ModernDlg.FileTypes.Add;
          JpegType.DisplayName := 'JPEG image';
          JpegType.FileMask := '*.jpg';

          case FSettings.SaveFormat of
            sfJPEG: ModernDlg.FileTypeIndex := 2;
            else    ModernDlg.FileTypeIndex := 1;
          end;
          ModernDlg.DefaultExtension := 'png';
          ModernDlg.FileName := ADefaultName;
          if FSettings.SaveFolder <> '' then
            ModernDlg.DefaultFolder := ExpandEnvVars(FSettings.SaveFolder);
          if AOverwritePrompt then
            ModernDlg.Options := ModernDlg.Options + [fdoOverWritePrompt]
          else
            ModernDlg.Options := ModernDlg.Options - [fdoOverWritePrompt];

          Hook.Attach;

          if ModernDlg.Execute then
          begin
            case ModernDlg.FileTypeIndex of
              2: AFormat := sfJPEG;
              else AFormat := sfPNG;
            end;
            APath := ModernDlg.FileName;
            FSettings.SaveFolder := ExtractFilePath(ModernDlg.FileName);
            FSettings.SaveAtLiveResolution := Hook.FinalState;
            FSettings.Save;
            Result := True;
          end;
          ModernHandled := True;
        finally
          Hook.Free;
        end;
      finally
        ModernDlg.Free;
      end;
    except
      on EPlatformVersionException do
        ModernHandled := False; {Defer to legacy dialog below.}
    end;
  end;

  if ModernHandled then
    Exit;

  LegacyDlg := TSaveDialog.Create(nil);
  try
    LegacyDlg.Title := ATitle;
    LegacyDlg.Filter := 'PNG image (*.png)|*.png|JPEG image (*.jpg)|*.jpg';
    case FSettings.SaveFormat of
      sfJPEG:
        LegacyDlg.FilterIndex := 2;
      else
        LegacyDlg.FilterIndex := 1;
    end;
    LegacyDlg.DefaultExt := 'png';
    LegacyDlg.FileName := ADefaultName;
    if FSettings.SaveFolder <> '' then
      LegacyDlg.InitialDir := ExpandEnvVars(FSettings.SaveFolder);
    if AOverwritePrompt then
      LegacyDlg.Options := LegacyDlg.Options + [ofOverwritePrompt];

    if LegacyDlg.Execute then
    begin
      case LegacyDlg.FilterIndex of
        2:
          AFormat := sfJPEG;
        else
          AFormat := sfPNG;
      end;
      APath := LegacyDlg.FileName;
      FSettings.SaveFolder := ExtractFilePath(LegacyDlg.FileName);
      FSettings.Save;
      Result := True;
    end;
  finally
    LegacyDlg.Free;
  end;
end;

procedure TFrameExporter.SaveFramesToDir(const ADir: string; AFormat: TSaveFormat; ASelectedOnly: Boolean; const AFileName: string);
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
      Tmp := RenderCellAtLiveSize(I);
      try
        uBitmapSaver.SaveBitmapToFile(Tmp, TargetPath, AFormat, FSettings.JpegQuality, FSettings.PngCompression);
      finally
        Tmp.Free;
      end;
    end
    else
      uBitmapSaver.SaveBitmapToFile(FFrameView.CellBitmap(I), TargetPath, AFormat, FSettings.JpegQuality, FSettings.PngCompression);
  end;
end;

procedure TFrameExporter.SaveSingleFrame(const AFileName: string; AContextCellIndex: Integer);
var
  Idx: Integer;
  Fmt: TSaveFormat;
  Path: string;
  Tmp: TBitmap;
begin
  if not ResolveFrameIndex(AContextCellIndex, Idx) then
    Exit;

  if not ShowSaveDialog('Save frame', GenerateFrameFileName(AFileName, Idx, FFrameView.CellTimeOffset(Idx), FSettings.SaveFormat), True, Path, Fmt) then
    Exit;

  if FSettings.SaveAtLiveResolution then
  begin
    Tmp := RenderCellAtLiveSize(Idx);
    try
      uBitmapSaver.SaveBitmapToFile(Tmp, Path, Fmt, FSettings.JpegQuality, FSettings.PngCompression);
    finally
      Tmp.Free;
    end;
  end
  else
    uBitmapSaver.SaveBitmapToFile(FFrameView.CellBitmap(Idx), Path, Fmt, FSettings.JpegQuality, FSettings.PngCompression);
end;

procedure TFrameExporter.SaveSelectedFrames(const AFileName: string);
var
  I, FirstSel: Integer;
  Path: string;
  Fmt: TSaveFormat;
begin
  if FFrameView.SelectedCount < 2 then
    Exit;

  {Find first selected frame for the sample filename}
  FirstSel := 0;
  for I := 0 to FFrameView.CellCount - 1 do
    if FFrameView.CellSelected(I) then
    begin
      FirstSel := I;
      Break;
    end;

  if not ShowSaveDialog('Save selected frames', GenerateFrameFileName(AFileName, FirstSel, FFrameView.CellTimeOffset(FirstSel), FSettings.SaveFormat), False, Path, Fmt) then
    Exit;

  SaveFramesToDir(IncludeTrailingPathDelimiter(ExtractFilePath(Path)), Fmt, True, AFileName);
end;

procedure TFrameExporter.SaveCombinedFrame(const AFileName: string);
var
  Bmp: TBitmap;
  Fmt: TSaveFormat;
  Path, BaseName: string;
begin
  if FFrameView.CellCount = 0 then
    Exit;

  BaseName := ChangeFileExt(ExtractFileName(AFileName), '');
  if not ShowSaveDialog('Save combined image', BaseName + '_combined.png', True, Path, Fmt) then
    Exit;

  Bmp := RenderWithBanner(RenderCombinedFromCells);
  try
    uBitmapSaver.SaveBitmapToFile(Bmp, Path, Fmt, FSettings.JpegQuality, FSettings.PngCompression);
  finally
    Bmp.Free;
  end;
end;

procedure TFrameExporter.SaveAllFrames(const AFileName: string);
var
  Path: string;
  Fmt: TSaveFormat;
begin
  if FFrameView.CellCount = 0 then
    Exit;

  if not ShowSaveDialog('Save all frames', GenerateFrameFileName(AFileName, 0, FFrameView.CellTimeOffset(0), FSettings.SaveFormat), False, Path, Fmt) then
    Exit;

  SaveFramesToDir(IncludeTrailingPathDelimiter(ExtractFilePath(Path)), Fmt, False, AFileName);
end;

procedure TFrameExporter.CopyFrameToClipboard(AContextCellIndex: Integer);
var
  Idx: Integer;
  Tmp: TBitmap;
begin
  if not ResolveFrameIndex(AContextCellIndex, Idx) then
    Exit;
  if FSettings.SaveAtLiveResolution then
  begin
    Tmp := RenderCellAtLiveSize(Idx);
    try
      Clipboard.Assign(Tmp);
    finally
      Tmp.Free;
    end;
  end
  else
    Clipboard.Assign(FFrameView.CellBitmap(Idx));
end;

procedure TFrameExporter.CopyAllToClipboard;
var
  Bmp: TBitmap;
begin
  if FFrameView.CellCount = 0 then
    Exit;
  Bmp := RenderWithBanner(RenderCombinedFromCells);
  try
    {Push as CF_DIBV5 when the rendered bitmap carries alpha so paste
     targets that honour ARGB receive transparent gaps; falls through to
     standard CF_DIB / CF_BITMAP for opaque sources.}
    CopyBitmapToClipboard(Bmp);
  finally
    Bmp.Free;
  end;
end;

end.
