/// Main plugin form, frame view control, and extraction worker thread.
/// The form is parented to TC's Lister window and hosts the toolbar and frame display.
unit uPluginForm;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.Math,
  Winapi.Windows, Winapi.Messages,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Buttons, Vcl.Graphics,
  uSettings, uFrameOffsets, uFFmpegExe;

const
  WM_FRAME_READY     = WM_USER + 100; { WParam=index, LParam=TBitmap ptr (0=error) }
  WM_EXTRACTION_DONE = WM_USER + 101; { extraction finished }

type
  TFrameCellState = (fcsPlaceholder, fcsLoaded, fcsError);

  TFrameCell = record
    State: TFrameCellState;
    Bitmap: TBitmap;
    Timecode: string;
    TimeOffset: Double;
  end;

  /// Worker thread that extracts frames sequentially via ffmpeg.exe.
  /// Posts WM_FRAME_READY for each frame and WM_EXTRACTION_DONE when finished.
  TExtractionThread = class(TThread)
  private
    FFFmpegPath: string;
    FFileName: string;
    FOffsets: TFrameOffsetArray;
    FTargetWnd: HWND;
  protected
    procedure Execute; override;
  public
    constructor Create(const AFFmpegPath, AFileName: string;
      const AOffsets: TFrameOffsetArray; ATargetWnd: HWND);
  end;

  /// Custom control that renders frame cells in grid or scroll layout.
  TFrameView = class(TCustomControl)
  private
    FCells: TArray<TFrameCell>;
    FViewMode: TViewMode;
    FBackColor: TColor;
    FAnimStep: Integer;
    FCellGap: Integer;
    FTimecodeHeight: Integer;
    function GetColumnCount: Integer;
    function GetCellImageSize: TSize;
    function GetCellRect(AIndex: Integer): TRect;
    function GetTimecodeRect(AIndex: Integer): TRect;
    procedure PaintCell(AIndex: Integer);
    procedure PaintPlaceholder(const ARect: TRect);
    procedure PaintLoadedFrame(AIndex: Integer; const ARect: TRect);
    procedure PaintArc(const ARect: TRect);
    procedure PaintTimecode(AIndex: Integer);
    procedure PaintErrorCell(const ARect: TRect);
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetCellCount(ACount: Integer; const AOffsets: TFrameOffsetArray);
    procedure SetFrame(AIndex: Integer; ABitmap: TBitmap);
    procedure SetCellError(AIndex: Integer);
    procedure ClearCells;
    function HasPlaceholders: Boolean;
    procedure AdvanceAnimation;
    procedure RecalcSize;
    property ViewMode: TViewMode read FViewMode write FViewMode;
    property BackColor: TColor read FBackColor write FBackColor;
  end;

  /// Plugin form created as a child of TC's Lister window.
  TPluginForm = class(TForm)
  private
    FFileName: string;
    FSettings: TPluginSettings;
    FFFmpegPath: string;
    FVideoInfo: TVideoInfo;
    FOffsets: TFrameOffsetArray;
    { Toolbar }
    FToolbar: TPanel;
    FLblFrames: TLabel;
    FEditFrameCount: TEdit;
    FUpDown: TUpDown;
    FBtnGrid: TSpeedButton;
    FBtnScroll: TSpeedButton;
    FCmbZoom: TComboBox;
    FProgressBar: TProgressBar;
    FLblProgress: TLabel;
    { Content }
    FScrollBox: TScrollBox;
    FFrameView: TFrameView;
    FLblError: TLabel;
    { Worker }
    FWorkerThread: TExtractionThread;
    FFramesLoaded: Integer;
    { Animation }
    FAnimTimer: TTimer;

    procedure CreateToolbar;
    procedure CreateFrameView;
    procedure CreateErrorLabel;
    procedure ApplySettings;
    procedure SetupPlaceholders;
    procedure ShowError(const AMessage: string);
    procedure HideError;
    procedure UpdateFrameViewSize;
    procedure StartExtraction;
    procedure StopExtraction;
    procedure DrainPendingFrameMessages;
    procedure UpdateProgress;
    procedure OnAnimTimer(Sender: TObject);
    procedure OnFrameCountChange(Sender: TObject);
    procedure OnViewModeClick(Sender: TObject);
    procedure OnZoomChange(Sender: TObject);
    procedure OnScrollBoxResize(Sender: TObject);
    procedure WMFrameReady(var Message: TMessage); message WM_FRAME_READY;
    procedure WMExtractionDone(var Message: TMessage); message WM_EXTRACTION_DONE;
  protected
    procedure Resize; override;
  public
    constructor CreateForPlugin(AParentWin: HWND; const AFileName: string;
      ASettings: TPluginSettings; const AFFmpegPath: string);
    destructor Destroy; override;
    procedure LoadFile(const AFileName: string);
  end;

implementation

const
  TOOLBAR_HEIGHT = 34;
  CELL_GAP       = 4;
  TIMECODE_H     = 20;
  ASPECT_RATIO   = 9.0 / 16.0; { 16:9 video }

{ TExtractionThread }

constructor TExtractionThread.Create(const AFFmpegPath, AFileName: string;
  const AOffsets: TFrameOffsetArray; ATargetWnd: HWND);
begin
  inherited Create(True); { suspended }
  FreeOnTerminate := False;
  FFFmpegPath := AFFmpegPath;
  FFileName := AFileName;
  FOffsets := Copy(AOffsets);
  FTargetWnd := ATargetWnd;
end;

procedure TExtractionThread.Execute;
var
  FFmpeg: TFFmpegExe;
  Bmp: TBitmap;
  I: Integer;
begin
  FFmpeg := TFFmpegExe.Create(FFFmpegPath);
  try
    for I := 0 to High(FOffsets) do
    begin
      if Terminated then
        Exit;

      Bmp := FFmpeg.ExtractFrame(FFileName, FOffsets[I].TimeOffset);

      if Terminated then
      begin
        Bmp.Free;
        Exit;
      end;

      { Transfer bitmap ownership to the UI thread via PostMessage }
      PostMessage(FTargetWnd, WM_FRAME_READY, WPARAM(I), LPARAM(Bmp));
    end;
  finally
    FFmpeg.Free;
  end;

  if not Terminated then
    PostMessage(FTargetWnd, WM_EXTRACTION_DONE, 0, 0);
end;

{ TFrameView }

constructor TFrameView.Create(AOwner: TComponent);
begin
  inherited;
  DoubleBuffered := True;
  FCellGap := CELL_GAP;
  FTimecodeHeight := TIMECODE_H;
  FBackColor := DEF_BACKGROUND;
  FViewMode := vmGrid;
  FAnimStep := 0;
end;

procedure TFrameView.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  Message.Result := 1;
end;

function TFrameView.GetColumnCount: Integer;
begin
  if (FViewMode = vmScroll) or (Length(FCells) <= 1) then
    Result := 1
  else
    Result := Max(1, Floor(Sqrt(Length(FCells))));
end;

function TFrameView.GetCellImageSize: TSize;
var
  Cols, AvailW: Integer;
begin
  Cols := GetColumnCount;
  AvailW := ClientWidth - (Cols + 1) * FCellGap;
  Result.cx := Max(1, AvailW div Cols);
  Result.cy := Max(1, Round(Result.cx * ASPECT_RATIO));
end;

function TFrameView.GetCellRect(AIndex: Integer): TRect;
var
  Cols, Col, Row: Integer;
  Sz: TSize;
  RowH: Integer;
begin
  Cols := GetColumnCount;
  Sz := GetCellImageSize;
  Col := AIndex mod Cols;
  Row := AIndex div Cols;
  RowH := Sz.cy + FTimecodeHeight + FCellGap;

  Result.Left   := FCellGap + Col * (Sz.cx + FCellGap);
  Result.Top    := FCellGap + Row * RowH;
  Result.Right  := Result.Left + Sz.cx;
  Result.Bottom := Result.Top + Sz.cy;
end;

function TFrameView.GetTimecodeRect(AIndex: Integer): TRect;
var
  CR: TRect;
begin
  CR := GetCellRect(AIndex);
  Result := Rect(CR.Left, CR.Bottom, CR.Right, CR.Bottom + FTimecodeHeight);
end;

procedure TFrameView.Paint;
var
  I: Integer;
begin
  Canvas.Brush.Color := FBackColor;
  Canvas.FillRect(ClientRect);
  for I := 0 to High(FCells) do
    PaintCell(I);
end;

procedure TFrameView.PaintCell(AIndex: Integer);
var
  R: TRect;
begin
  R := GetCellRect(AIndex);
  case FCells[AIndex].State of
    fcsPlaceholder: PaintPlaceholder(R);
    fcsLoaded:      PaintLoadedFrame(AIndex, R);
    fcsError:       PaintErrorCell(R);
  end;
  PaintTimecode(AIndex);
end;

procedure TFrameView.PaintPlaceholder(const ARect: TRect);
begin
  Canvas.Brush.Color := $002D2D2D;
  Canvas.Pen.Style := psClear;
  Canvas.Rectangle(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom);
  PaintArc(ARect);
end;

procedure TFrameView.PaintLoadedFrame(AIndex: Integer; const ARect: TRect);
var
  Bmp: TBitmap;
  DstR: TRect;
  Scale: Double;
  DW, DH: Integer;
begin
  Bmp := FCells[AIndex].Bitmap;
  if Bmp = nil then
  begin
    PaintPlaceholder(ARect);
    Exit;
  end;
  { Scale to fit cell, maintaining aspect ratio }
  Scale := Min(ARect.Width / Max(1, Bmp.Width),
               ARect.Height / Max(1, Bmp.Height));
  DW := Round(Bmp.Width * Scale);
  DH := Round(Bmp.Height * Scale);
  DstR.Left   := ARect.Left + (ARect.Width - DW) div 2;
  DstR.Top    := ARect.Top + (ARect.Height - DH) div 2;
  DstR.Right  := DstR.Left + DW;
  DstR.Bottom := DstR.Top + DH;

  { Fill letterbox area }
  Canvas.Brush.Color := $002D2D2D;
  Canvas.FillRect(ARect);
  Canvas.StretchDraw(DstR, Bmp);
end;

procedure TFrameView.PaintArc(const ARect: TRect);
var
  CX, CY, Radius, I: Integer;
  StartAngle, Angle: Double;
  X, Y: Integer;
const
  ARC_SPAN = 90.0;
  SEGMENTS = 12;
begin
  CX := (ARect.Left + ARect.Right) div 2;
  CY := (ARect.Top + ARect.Bottom) div 2;
  Radius := Min(ARect.Width, ARect.Height) div 8;
  if Radius < 5 then Exit;

  StartAngle := FAnimStep * 45.0;
  Canvas.Pen.Color := $00707070;
  Canvas.Pen.Width := 3;
  Canvas.Pen.Style := psSolid;

  for I := 0 to SEGMENTS do
  begin
    Angle := DegToRad(StartAngle + I * ARC_SPAN / SEGMENTS);
    X := CX + Round(Radius * Cos(Angle));
    Y := CY - Round(Radius * Sin(Angle));
    if I = 0 then
      Canvas.MoveTo(X, Y)
    else
      Canvas.LineTo(X, Y);
  end;
end;

procedure TFrameView.PaintTimecode(AIndex: Integer);
var
  R: TRect;
begin
  R := GetTimecodeRect(AIndex);
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 8;
  if FCells[AIndex].State = fcsLoaded then
    Canvas.Font.Color := $00AAAAAA
  else
    Canvas.Font.Color := $00555555;
  Canvas.Brush.Style := bsClear;
  DrawText(Canvas.Handle, PChar(FCells[AIndex].Timecode), -1, R,
    DT_CENTER or DT_VCENTER or DT_SINGLELINE);
end;

procedure TFrameView.PaintErrorCell(const ARect: TRect);
var
  R: TRect;
begin
  Canvas.Brush.Color := $002D2D2D;
  Canvas.Pen.Style := psClear;
  Canvas.Rectangle(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom);
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 9;
  Canvas.Font.Color := $004040FF;
  Canvas.Brush.Style := bsClear;
  R := ARect;
  DrawText(Canvas.Handle, 'Error', -1, R, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
end;

procedure TFrameView.SetCellCount(ACount: Integer; const AOffsets: TFrameOffsetArray);
var
  I: Integer;
begin
  SetLength(FCells, ACount);
  for I := 0 to ACount - 1 do
  begin
    FCells[I].State := fcsPlaceholder;
    FCells[I].Bitmap := nil;
    if (AOffsets <> nil) and (I < Length(AOffsets)) then
    begin
      FCells[I].Timecode := FormatTimecode(AOffsets[I].TimeOffset);
      FCells[I].TimeOffset := AOffsets[I].TimeOffset;
    end
    else
    begin
      FCells[I].Timecode := '';
      FCells[I].TimeOffset := 0;
    end;
  end;
end;

procedure TFrameView.SetFrame(AIndex: Integer; ABitmap: TBitmap);
begin
  if (AIndex >= 0) and (AIndex < Length(FCells)) then
  begin
    FCells[AIndex].State := fcsLoaded;
    FCells[AIndex].Bitmap := ABitmap;
    Invalidate;
  end;
end;

procedure TFrameView.SetCellError(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < Length(FCells)) then
  begin
    FCells[AIndex].State := fcsError;
    Invalidate;
  end;
end;

procedure TFrameView.ClearCells;
var
  I: Integer;
begin
  for I := 0 to High(FCells) do
    FreeAndNil(FCells[I].Bitmap);
  SetLength(FCells, 0);
end;

function TFrameView.HasPlaceholders: Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FCells) do
    if FCells[I].State = fcsPlaceholder then
      Exit(True);
  Result := False;
end;

procedure TFrameView.AdvanceAnimation;
begin
  FAnimStep := (FAnimStep + 1) mod 8;
  Invalidate;
end;

procedure TFrameView.RecalcSize;
var
  Cols, Rows: Integer;
  Sz: TSize;
begin
  if Length(FCells) = 0 then
  begin
    Height := 0;
    Exit;
  end;
  Cols := GetColumnCount;
  Sz := GetCellImageSize;
  Rows := Ceil(Length(FCells) / Cols);
  Height := FCellGap + Rows * (Sz.cy + FTimecodeHeight + FCellGap);
end;

{ TPluginForm }

constructor TPluginForm.CreateForPlugin(AParentWin: HWND; const AFileName: string;
  ASettings: TPluginSettings; const AFFmpegPath: string);
var
  R: TRect;
begin
  CreateNew(nil);
  BorderStyle := bsNone;

  FSettings := ASettings;
  FFFmpegPath := AFFmpegPath;

  Winapi.Windows.GetClientRect(AParentWin, R);
  SetBounds(0, 0, R.Right, R.Bottom);

  CreateToolbar;
  CreateFrameView;
  CreateErrorLabel;
  ApplySettings;

  ParentWindow := AParentWin;
  Visible := True;

  FAnimTimer := TTimer.Create(Self);
  FAnimTimer.Interval := 80;
  FAnimTimer.OnTimer := OnAnimTimer;
  FAnimTimer.Enabled := True;

  LoadFile(AFileName);
end;

destructor TPluginForm.Destroy;
begin
  if Assigned(FAnimTimer) then
    FAnimTimer.Enabled := False;
  StopExtraction;
  DrainPendingFrameMessages;
  FFrameView.ClearCells;
  inherited;
end;

procedure TPluginForm.CreateToolbar;
var
  X, CY: Integer;
begin
  FToolbar := TPanel.Create(Self);
  FToolbar.Parent := Self;
  FToolbar.Align := alTop;
  FToolbar.Height := TOOLBAR_HEIGHT;
  FToolbar.BevelOuter := bvNone;
  FToolbar.ParentBackground := False;

  CY := (TOOLBAR_HEIGHT - 22) div 2;
  X := 8;

  FLblFrames := TLabel.Create(FToolbar);
  FLblFrames.Parent := FToolbar;
  FLblFrames.Caption := 'Frames:';
  FLblFrames.AutoSize := True;
  FLblFrames.Left := X;
  FLblFrames.Top := CY + 3;
  Inc(X, FLblFrames.Width + 4);

  FEditFrameCount := TEdit.Create(FToolbar);
  FEditFrameCount.Parent := FToolbar;
  FEditFrameCount.SetBounds(X, CY, 40, 22);
  FEditFrameCount.ReadOnly := True;
  FEditFrameCount.OnChange := OnFrameCountChange;

  FUpDown := TUpDown.Create(FToolbar);
  FUpDown.Parent := FToolbar;
  FUpDown.Associate := FEditFrameCount;
  FUpDown.Min := 1;
  FUpDown.Max := 99;
  Inc(X, 40 + FUpDown.Width + 14);

  FBtnGrid := TSpeedButton.Create(FToolbar);
  FBtnGrid.Parent := FToolbar;
  FBtnGrid.SetBounds(X, CY, 48, 22);
  FBtnGrid.GroupIndex := 1;
  FBtnGrid.AllowAllUp := False;
  FBtnGrid.Caption := 'Grid';
  FBtnGrid.OnClick := OnViewModeClick;
  Inc(X, 50);

  FBtnScroll := TSpeedButton.Create(FToolbar);
  FBtnScroll.Parent := FToolbar;
  FBtnScroll.SetBounds(X, CY, 48, 22);
  FBtnScroll.GroupIndex := 1;
  FBtnScroll.AllowAllUp := False;
  FBtnScroll.Caption := 'Scroll';
  FBtnScroll.OnClick := OnViewModeClick;
  Inc(X, 60);

  FCmbZoom := TComboBox.Create(FToolbar);
  FCmbZoom.Parent := FToolbar;
  FCmbZoom.Style := csDropDownList;
  FCmbZoom.SetBounds(X, CY, 110, 22);
  FCmbZoom.Items.Add('Fit window');
  FCmbZoom.Items.Add('Fit if larger');
  FCmbZoom.Items.Add('100%');
  FCmbZoom.OnChange := OnZoomChange;
  Inc(X, 120);

  FProgressBar := TProgressBar.Create(FToolbar);
  FProgressBar.Parent := FToolbar;
  FProgressBar.SetBounds(X, CY + 3, 120, 16);
  FProgressBar.Visible := False;

  FLblProgress := TLabel.Create(FToolbar);
  FLblProgress.Parent := FToolbar;
  FLblProgress.AutoSize := True;
  FLblProgress.Left := X + 125;
  FLblProgress.Top := CY + 3;
  FLblProgress.Visible := False;
end;

procedure TPluginForm.CreateFrameView;
begin
  FScrollBox := TScrollBox.Create(Self);
  FScrollBox.Parent := Self;
  FScrollBox.Align := alClient;
  FScrollBox.BorderStyle := bsNone;
  FScrollBox.HorzScrollBar.Visible := False;
  FScrollBox.OnResize := OnScrollBoxResize;

  FFrameView := TFrameView.Create(FScrollBox);
  FFrameView.Parent := FScrollBox;
  FFrameView.Left := 0;
  FFrameView.Top := 0;
end;

procedure TPluginForm.CreateErrorLabel;
begin
  FLblError := TLabel.Create(Self);
  FLblError.Parent := FScrollBox;
  FLblError.Align := alClient;
  FLblError.Alignment := taCenter;
  FLblError.Layout := tlCenter;
  FLblError.Font.Size := 11;
  FLblError.Font.Color := $00888888;
  FLblError.WordWrap := True;
  FLblError.Visible := False;
end;

procedure TPluginForm.ApplySettings;
begin
  if FSettings = nil then Exit;

  FUpDown.Position := FSettings.DefaultN;
  FBtnGrid.Down := FSettings.ViewMode = vmGrid;
  FBtnScroll.Down := FSettings.ViewMode = vmScroll;
  FCmbZoom.ItemIndex := Ord(FSettings.ZoomMode);
  FFrameView.ViewMode := FSettings.ViewMode;
  FFrameView.BackColor := FSettings.Background;
  FScrollBox.Color := FSettings.Background;
  Color := FSettings.Background;
end;

procedure TPluginForm.LoadFile(const AFileName: string);
var
  FFmpeg: TFFmpegExe;
begin
  FFileName := AFileName;
  StopExtraction;
  DrainPendingFrameMessages;
  FFrameView.ClearCells;
  FVideoInfo := Default(TVideoInfo);

  if FFFmpegPath = '' then
  begin
    ShowError('ffmpeg not found.'#13#10'Press F2 to configure.');
    Exit;
  end;

  { Probe video metadata synchronously (fast, reads only header) }
  FFmpeg := TFFmpegExe.Create(FFFmpegPath);
  try
    FVideoInfo := FFmpeg.ProbeVideo(FFileName);
  finally
    FFmpeg.Free;
  end;

  if not FVideoInfo.IsValid then
  begin
    ShowError('Could not read video file.'#13#10 + FVideoInfo.ErrorMessage);
    Exit;
  end;

  SetupPlaceholders;
  HideError;
  StartExtraction;
end;

procedure TPluginForm.SetupPlaceholders;
begin
  FOffsets := CalculateFrameOffsets(FVideoInfo.Duration,
    FUpDown.Position, FSettings.SkipEdgesPercent);

  FFrameView.SetCellCount(Length(FOffsets), FOffsets);
  UpdateFrameViewSize;
end;

procedure TPluginForm.StartExtraction;
begin
  StopExtraction;
  FFramesLoaded := 0;

  { Show progress in marquee mode until first frame arrives }
  FProgressBar.Style := pbstMarquee;
  FProgressBar.Visible := True;
  FLblProgress.Caption := 'Extracting...';
  FLblProgress.Visible := True;

  FAnimTimer.Enabled := True;

  FWorkerThread := TExtractionThread.Create(FFFmpegPath, FFileName, FOffsets, Handle);
  FWorkerThread.Start;
end;

procedure TPluginForm.StopExtraction;
begin
  if Assigned(FWorkerThread) then
  begin
    FWorkerThread.Terminate;
    FWorkerThread.WaitFor;
    FreeAndNil(FWorkerThread);
  end;
end;

procedure TPluginForm.DrainPendingFrameMessages;
var
  Msg: TMsg;
begin
  { Remove pending WM_FRAME_READY messages and free their bitmap payloads
    to prevent leaks when the window is being torn down or reloaded }
  while PeekMessage(Msg, Handle, WM_FRAME_READY, WM_FRAME_READY, PM_REMOVE) do
  begin
    if Msg.lParam <> 0 then
      TObject(Msg.lParam).Free;
  end;
  { Also discard any pending done notification }
  PeekMessage(Msg, Handle, WM_EXTRACTION_DONE, WM_EXTRACTION_DONE, PM_REMOVE);
end;

procedure TPluginForm.UpdateProgress;
begin
  if FFramesLoaded >= Length(FOffsets) then
  begin
    FProgressBar.Visible := False;
    FLblProgress.Visible := False;
    FAnimTimer.Enabled := FFrameView.HasPlaceholders;
  end
  else if FFramesLoaded > 0 then
  begin
    { Switch from marquee to ranged after first frame }
    FProgressBar.Style := pbstNormal;
    FProgressBar.Max := Length(FOffsets);
    FProgressBar.Position := FFramesLoaded;
    FLblProgress.Caption := Format('Extracting... (%d/%d)',
      [FFramesLoaded, Length(FOffsets)]);
  end;
end;

procedure TPluginForm.WMFrameReady(var Message: TMessage);
var
  Index: Integer;
  Bmp: TBitmap;
begin
  Index := Integer(Message.WParam);
  Bmp := TBitmap(Message.LParam);

  if Bmp <> nil then
    FFrameView.SetFrame(Index, Bmp)
  else
    FFrameView.SetCellError(Index);

  Inc(FFramesLoaded);
  UpdateProgress;
end;

procedure TPluginForm.WMExtractionDone(var Message: TMessage);
begin
  FProgressBar.Visible := False;
  FLblProgress.Visible := False;
  FAnimTimer.Enabled := FFrameView.HasPlaceholders;
end;

procedure TPluginForm.ShowError(const AMessage: string);
begin
  FFrameView.Visible := False;
  FLblError.Caption := AMessage;
  FLblError.Visible := True;
  FAnimTimer.Enabled := False;
  FProgressBar.Visible := False;
  FLblProgress.Visible := False;
end;

procedure TPluginForm.HideError;
begin
  FLblError.Visible := False;
  FFrameView.Visible := True;
  FAnimTimer.Enabled := True;
end;

procedure TPluginForm.UpdateFrameViewSize;
begin
  FFrameView.Width := FScrollBox.ClientWidth;
  FFrameView.RecalcSize;
  FFrameView.Invalidate;
end;

procedure TPluginForm.Resize;
begin
  inherited;
  if Assigned(FFrameView) and FFrameView.Visible then
    UpdateFrameViewSize;
end;

procedure TPluginForm.OnScrollBoxResize(Sender: TObject);
begin
  if Assigned(FFrameView) and FFrameView.Visible then
    UpdateFrameViewSize;
end;

procedure TPluginForm.OnAnimTimer(Sender: TObject);
begin
  if Assigned(FFrameView) and FFrameView.Visible then
    FFrameView.AdvanceAnimation;
end;

procedure TPluginForm.OnFrameCountChange(Sender: TObject);
begin
  if not FVideoInfo.IsValid then Exit;
  StopExtraction;
  DrainPendingFrameMessages;
  FFrameView.ClearCells;
  SetupPlaceholders;
  StartExtraction;
end;

procedure TPluginForm.OnViewModeClick(Sender: TObject);
begin
  if FBtnGrid.Down then
    FFrameView.ViewMode := vmGrid
  else
    FFrameView.ViewMode := vmScroll;
  UpdateFrameViewSize;
end;

procedure TPluginForm.OnZoomChange(Sender: TObject);
begin
  { Phase 7: apply zoom mode }
end;

end.
