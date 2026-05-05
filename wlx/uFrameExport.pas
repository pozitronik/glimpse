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
    {Optional save-resolution bitmaps supplied by the caller before a
     save/copy operation, indexed parallel to FFrameView cells. Bitmaps
     are non-owned references (typically owned by TFrameCache). When the
     SaveAtLiveResolution toggle is off, save paths prefer entries from
     this array over the live FFrameView bitmaps; nil entries fall back
     to the live cell. Set length 0 to disable.
     Lifetime: the caller (TPluginForm) sets this before invoking a save
     method and clears it after, so the exporter never owns the memory.}
    FOverrideFrames: TArray<TBitmap>;
    function ShowSaveDialog(const ATitle, ADefaultName: string; AOverwritePrompt: Boolean; out APath: string; out AFormat: TSaveFormat): Boolean;
    procedure SaveFramesToDir(const ADir: string; AFormat: TSaveFormat; ASelectedOnly: Boolean; const AFileName: string);
    {Returns the bitmap that the save/copy paths should consume for cell
     AIndex, honouring FOverrideFrames when set and the toggle is off.}
    function PickSaveBitmap(AIndex: Integer): TBitmap;
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
    {Returns the cell-index list a save / copy action will consume. Used
     by the form's WithReExtract wrapper to scope re-extraction to the
     frames the action actually reads.
     Single — one element if ResolveFrameIndex(AContextCellIndex) succeeds, empty otherwise.
     AllLoaded — every cell whose state is fcsLoaded.
     SelectedOrAll — selected loaded cells if any selection exists, else
     every loaded cell (mirrors the selection-aware semantics of SaveFrames).}
    function BuildSaveIndicesSingle(AContextCellIndex: Integer): TArray<Integer>;
    function BuildSaveIndicesAllLoaded: TArray<Integer>;
    function BuildSaveIndicesSelectedOrAll: TArray<Integer>;
    {Saves a single frame to a user-chosen file. Honours
     SaveAtLiveResolution: native frame size when off, on-screen cell
     size when on (letterbox in vmGrid/Filmstrip/Scroll/Single,
     crop-to-fill in vmSmartGrid).}
    procedure SaveFrame(const AFileName: string; AContextCellIndex: Integer);
    {Saves multiple frames as separate files. Selection-aware: when at
     least one frame is selected only those are written, otherwise every
     loaded frame is written. Per-frame resolution policy mirrors
     SaveFrame.}
    procedure SaveFrames(const AFileName: string);
    {Saves a combined image laid out per the live view mode:
     - vmGrid: regular grid, columns from live layout.
     - vmSmartGrid: smart layout (panel-aspect-driven row counts).
     - vmFilmstrip: one row of all cells.
     - vmScroll: one column of all cells.
     - vmSingle: degenerates to SaveFrame for the focused cell.
     Honours SaveAtLiveResolution.}
    procedure SaveView(const AFileName: string);
    procedure CopyFrame(AContextCellIndex: Integer);
    procedure CopyView;
    procedure UpdateBannerInfo(const AInfo: TBannerInfo);
    {Caller-supplied save-resolution bitmaps. Set before invoking a save
     or copy method when SaveAtLiveResolution is off and the caller has
     re-extracted at native (or capped) resolution; clear immediately
     after. Pass an empty array (or nil) to release. Bitmaps are not
     owned by the exporter.}
    procedure SetOverrideFrames(const AFrames: TArray<TBitmap>);
    procedure ClearOverrideFrames;
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

function TFrameExporter.BuildSaveIndicesSingle(AContextCellIndex: Integer): TArray<Integer>;
var
  Idx: Integer;
begin
  if ResolveFrameIndex(AContextCellIndex, Idx) then
    Result := TArray<Integer>.Create(Idx)
  else
    SetLength(Result, 0);
end;

function TFrameExporter.BuildSaveIndicesAllLoaded: TArray<Integer>;
var
  I: Integer;
begin
  SetLength(Result, 0);
  for I := 0 to FFrameView.CellCount - 1 do
    if FFrameView.CellState(I) = fcsLoaded then
      Result := Result + [I];
end;

function TFrameExporter.BuildSaveIndicesSelectedOrAll: TArray<Integer>;
var
  I: Integer;
  SelectedOnly: Boolean;
begin
  SetLength(Result, 0);
  SelectedOnly := FFrameView.SelectedCount > 0;
  for I := 0 to FFrameView.CellCount - 1 do
    if (FFrameView.CellState(I) = fcsLoaded) and ((not SelectedOnly) or FFrameView.CellSelected(I)) then
      Result := Result + [I];
end;

{Picks which bitmap to feed into the save/copy renderers for cell AIndex.
 With FOverrideFrames set and the live-resolution toggle off, prefers the
 override entry (typically a cache-owned save-resolution bitmap); a nil
 override entry falls back to the live cell so partial coverage degrades
 gracefully. With the toggle on, always uses the live cell since the
 toggle's contract is to mirror what is on screen.}
function TFrameExporter.PickSaveBitmap(AIndex: Integer): TBitmap;
begin
  Result := nil;
  if (not FSettings.SaveAtLiveResolution) and (AIndex >= 0) and (AIndex < Length(FOverrideFrames)) and (FOverrideFrames[AIndex] <> nil) then
    Exit(FOverrideFrames[AIndex]);
  if (AIndex >= 0) and (AIndex < FFrameView.CellCount) and (FFrameView.CellState(AIndex) = fcsLoaded) then
    Result := FFrameView.CellBitmap(AIndex);
end;

procedure TFrameExporter.SetOverrideFrames(const AFrames: TArray<TBitmap>);
begin
  FOverrideFrames := AFrames;
end;

procedure TFrameExporter.ClearOverrideFrames;
begin
  SetLength(FOverrideFrames, 0);
end;

{Builds the frames + offsets arrays for the renderer.
 Frame source is PickSaveBitmap so override entries (when set) take
 precedence over the live cells. Offsets always come from the live view.
 nil entries for placeholder/error/missing cells are passed through; the
 renderer skips them.}
function TFrameExporter.CollectFramesAndOffsets(out AFrames: TArray<TBitmap>; out AOffsets: TFrameOffsetArray): Integer;
var
  I: Integer;
begin
  Result := FFrameView.CellCount;
  SetLength(AFrames, Result);
  SetLength(AOffsets, Result);
  for I := 0 to Result - 1 do
  begin
    AFrames[I] := PickSaveBitmap(I);
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

{Counts the columns the live layout is currently using by iterating
 cells and counting those that share cell 0's top coordinate.
 Generalises across the three uniform-row modes:
 vmGrid      - cells in row 0 share Top, returns column count.
 vmFilmstrip - all cells share Top (one row), returns FrameCount.
 vmScroll    - only cell 0 has that Top (one column), returns 1.
 Used by the live-resolution save path; not called for vmSmartGrid
 (which has its own renderer) or vmSingle (which routes to SaveFrame).}
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

{Live-resolution variant of the uniform-grid render: cell pixel size
 matches what the live view is currently showing on screen, and the
 column count tracks the live layout. Used by vmGrid, vmFilmstrip, and
 vmScroll save/copy when SaveAtLiveResolution is on. Frames are
 pre-letterboxed to the live cell dimensions, then fed to the same
 uniform-grid renderer the native path uses. This keeps alpha lifting,
 timecode rendering, and border/gap math centralised.}
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
  end else begin
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

{Renders the frames into a single combined image laid out per the
 live view mode. Cell pixel size follows the SaveAtLiveResolution
 toggle in every mode:

 - vmSmartGrid: smart layout (panel-aspect-driven row counts);
 panel-pixel cells when the toggle is on, anchor-to-widest native
 cells when off. Handled by RenderSmartCombinedFromCells.
 - vmGrid / vmFilmstrip / vmScroll: uniform-row grid. When the toggle
 is on, all three route through RenderGridCombinedAtLiveResolution
 so cell pixels match the on-screen layout (vmFilmstrip = one wide
 row, vmScroll = one tall column, vmGrid = current column count).
 When off, they render at native cell size with Columns pinned to
 the view's natural shape.
 - vmSingle: caller (SaveView/CopyView) routes to single-frame paths
 before reaching this function, so vmSingle never reaches the
 regular grid renderer here.

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

  {The uniform-row modes (vmGrid, vmFilmstrip, vmScroll) all share the
   same live-resolution path: it picks Columns from the live layout
   via CountLiveGridColumns, which generalises across the three.}
  if FSettings.SaveAtLiveResolution and (FFrameView.ViewMode in [vmGrid, vmFilmstrip, vmScroll]) then
    Exit(RenderGridCombinedAtLiveResolution);

  N := CollectFramesAndOffsets(Frames, Offsets);
  if N = 0 then
    Exit(nil);

  BuildGridStyle(Grid);
  BuildTimestampStyle(Ts);

  {Native-resolution path for the uniform-row modes. Pin Columns to the
   live layout so the saved image preserves the on-screen arrangement:
   filmstrip is one wide row, scroll is one tall column, and vmGrid
   tracks the column count the live view is currently using (which
   varies with panel width, e.g. a narrow panel renders 9 frames as
   1x9 — without this, the saver would default to ceil(sqrt(N)) = 3x3
   and ignore the user's chosen aspect).}
  case FFrameView.ViewMode of
    vmGrid:
      Grid.Columns := CountLiveGridColumns;
    vmFilmstrip:
      Grid.Columns := N;
    vmScroll:
      Grid.Columns := 1;
  end;

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
            sfJPEG:
              ModernDlg.FileTypeIndex := 2;
            else
              ModernDlg.FileTypeIndex := 1;
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
              2:
                AFormat := sfJPEG;
              else
                AFormat := sfPNG;
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
      uBitmapSaver.SaveBitmapToFile(PickSaveBitmap(I), TargetPath, AFormat, FSettings.JpegQuality, FSettings.PngCompression);
  end;
end;

procedure TFrameExporter.SaveFrame(const AFileName: string; AContextCellIndex: Integer);
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
    uBitmapSaver.SaveBitmapToFile(PickSaveBitmap(Idx), Path, Fmt, FSettings.JpegQuality, FSettings.PngCompression);
end;

procedure TFrameExporter.SaveFrames(const AFileName: string);
var
  I, FirstIdx: Integer;
  Path: string;
  Fmt: TSaveFormat;
  SelectedOnly: Boolean;
begin
  if FFrameView.CellCount = 0 then
    Exit;

  {Selection-aware: any selection at all means "save just those";
   otherwise every loaded frame goes out. Replaces the historical
   pair (SaveAllFrames + SaveSelectedFrames) with one action.}
  SelectedOnly := FFrameView.SelectedCount > 0;

  {Sample filename uses the first frame that will actually be written
   so the user sees a meaningful default in the dialog.}
  FirstIdx := 0;
  if SelectedOnly then
    for I := 0 to FFrameView.CellCount - 1 do
      if FFrameView.CellSelected(I) then
      begin
        FirstIdx := I;
        Break;
      end;

  if not ShowSaveDialog('Save frames', GenerateFrameFileName(AFileName, FirstIdx, FFrameView.CellTimeOffset(FirstIdx), FSettings.SaveFormat), False, Path, Fmt) then
    Exit;

  SaveFramesToDir(IncludeTrailingPathDelimiter(ExtractFilePath(Path)), Fmt, SelectedOnly, AFileName);
end;

procedure TFrameExporter.SaveView(const AFileName: string);
var
  Bmp: TBitmap;
  Fmt: TSaveFormat;
  Path, BaseName: string;
begin
  if FFrameView.CellCount = 0 then
    Exit;

  {vmSingle's "view" is a single frame; route to SaveFrame so the user
   gets a single-frame artefact rather than a wasteful 1-cell combined.}
  if FFrameView.ViewMode = vmSingle then
  begin
    SaveFrame(AFileName, FFrameView.CurrentFrameIndex);
    Exit;
  end;

  BaseName := ChangeFileExt(ExtractFileName(AFileName), '');
  if not ShowSaveDialog('Save view', BaseName + '_view.png', True, Path, Fmt) then
    Exit;

  Bmp := RenderWithBanner(RenderCombinedFromCells);
  try
    uBitmapSaver.SaveBitmapToFile(Bmp, Path, Fmt, FSettings.JpegQuality, FSettings.PngCompression);
  finally
    Bmp.Free;
  end;
end;

procedure TFrameExporter.CopyFrame(AContextCellIndex: Integer);
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
    Clipboard.Assign(PickSaveBitmap(Idx));
end;

procedure TFrameExporter.CopyView;
var
  Bmp: TBitmap;
begin
  if FFrameView.CellCount = 0 then
    Exit;
  if FFrameView.ViewMode = vmSingle then
  begin
    CopyFrame(FFrameView.CurrentFrameIndex);
    Exit;
  end;
  Bmp := RenderWithBanner(RenderCombinedFromCells);
  try
    {Publishes CF_DIBV5 (alpha-aware) and CF_DIB (alpha pre-composited
     onto FSettings.Background) side-by-side, so modern paste targets
     keep the transparent gaps and legacy targets see a working opaque
     image instead of the broken paste they get from the OS's default
     CF_DIB synthesis. ABackground only matters when the rendered
     bitmap carries alpha; for opaque sources it is ignored.}
    CopyBitmapToClipboard(Bmp, FSettings.Background);
  finally
    Bmp.Free;
  end;
end;

end.
