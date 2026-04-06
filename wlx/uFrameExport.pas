{ Frame export operations: save to file and copy to clipboard.
  Extracted from TPluginForm to isolate I/O from UI orchestration. }
unit uFrameExport;

interface

uses
  Vcl.Graphics,
  uFrameView, uSettings, uBitmapSaver, uCombinedImage;

type
  { Handles save-to-file and copy-to-clipboard for video frames. }
  TFrameExporter = class
  strict private
    FFrameView: TFrameView;
    FSettings: TPluginSettings;
    FBannerInfo: TBannerInfo;
    function RenderFrameView: TBitmap;
    function RenderWithBanner(ABmp: TBitmap): TBitmap;
    function ShowSaveDialog(const ATitle, ADefaultName: string;
      AOverwritePrompt: Boolean; out APath: string;
      out AFormat: TSaveFormat): Boolean;
    procedure SaveFramesToDir(const ADir: string; AFormat: TSaveFormat;
      ASelectedOnly: Boolean; const AFileName: string);
  public
    constructor Create(AFrameView: TFrameView; ASettings: TPluginSettings);
    { Resolves which frame to act on: prefers AContextCellIndex, falls back
      to current frame index, then 0. Returns False if no loaded frame found. }
    function ResolveFrameIndex(AContextCellIndex: Integer;
      out AIndex: Integer): Boolean;
    procedure SaveSingleFrame(const AFileName: string;
      AContextCellIndex: Integer);
    procedure SaveSelectedFrames(const AFileName: string);
    procedure SaveCombinedFrame(const AFileName: string);
    procedure SaveAllFrames(const AFileName: string);
    procedure CopyFrameToClipboard(AContextCellIndex: Integer);
    procedure CopyAllToClipboard;
    procedure UpdateBannerInfo(const AInfo: TBannerInfo);
  end;

implementation

uses
  System.SysUtils, System.Types,
  Vcl.Clipbrd, Vcl.Dialogs, uFrameFileNames, uPathExpand;

{ TFrameExporter }

constructor TFrameExporter.Create(AFrameView: TFrameView;
  ASettings: TPluginSettings);
begin
  inherited Create;
  FFrameView := AFrameView;
  FSettings := ASettings;
end;

function TFrameExporter.ResolveFrameIndex(AContextCellIndex: Integer;
  out AIndex: Integer): Boolean;
begin
  Result := False;
  if FFrameView.CellCount = 0 then Exit;
  { Prefer the right-clicked cell, fall back to current frame, then index 0 }
  AIndex := AContextCellIndex;
  if (AIndex < 0) or (AIndex >= FFrameView.CellCount) then
    AIndex := FFrameView.CurrentFrameIndex;
  if (AIndex < 0) or (AIndex >= FFrameView.CellCount) then
    AIndex := 0;
  Result := FFrameView.CellState(AIndex) = fcsLoaded;
end;

function TFrameExporter.RenderFrameView: TBitmap;
begin
  Result := TBitmap.Create;
  Result.SetSize(FFrameView.Width, FFrameView.Height);
  Result.Canvas.Brush.Color := FFrameView.BackColor;
  Result.Canvas.FillRect(Rect(0, 0, Result.Width, Result.Height));
  FFrameView.PaintTo(Result.Canvas, 0, 0);
end;

function TFrameExporter.RenderWithBanner(ABmp: TBitmap): TBitmap;
begin
  if FSettings.ShowBanner then
  begin
    Result := PrependBanner(ABmp,
      FormatBannerLines(FBannerInfo),
      FSettings.TimestampFontName, FSettings.TimestampFontSize);
    ABmp.Free;
  end
  else
    Result := ABmp;
end;

procedure TFrameExporter.UpdateBannerInfo(const AInfo: TBannerInfo);
begin
  FBannerInfo := AInfo;
end;

function TFrameExporter.ShowSaveDialog(const ATitle, ADefaultName: string;
  AOverwritePrompt: Boolean; out APath: string;
  out AFormat: TSaveFormat): Boolean;
var
  Dlg: TSaveDialog;
begin
  Result := False;
  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Title := ATitle;
    Dlg.Filter := 'PNG image (*.png)|*.png|JPEG image (*.jpg)|*.jpg';
    case FSettings.SaveFormat of
      sfJPEG: Dlg.FilterIndex := 2;
    else
      Dlg.FilterIndex := 1;
    end;
    Dlg.DefaultExt := 'png';
    Dlg.FileName := ADefaultName;
    if FSettings.SaveFolder <> '' then
      Dlg.InitialDir := ExpandEnvVars(FSettings.SaveFolder);
    if AOverwritePrompt then
      Dlg.Options := Dlg.Options + [ofOverwritePrompt];

    if Dlg.Execute then
    begin
      case Dlg.FilterIndex of
        2: AFormat := sfJPEG;
      else
        AFormat := sfPNG;
      end;
      APath := Dlg.FileName;
      FSettings.SaveFolder := ExtractFilePath(Dlg.FileName);
      FSettings.Save;
      Result := True;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TFrameExporter.SaveFramesToDir(const ADir: string;
  AFormat: TSaveFormat; ASelectedOnly: Boolean; const AFileName: string);
var
  I: Integer;
begin
  for I := 0 to FFrameView.CellCount - 1 do
  begin
    if ASelectedOnly and not FFrameView.CellSelected(I) then Continue;
    if FFrameView.CellState(I) <> fcsLoaded then Continue;
    uBitmapSaver.SaveBitmapToFile(FFrameView.CellBitmap(I),
      ADir + GenerateFrameFileName(AFileName, I,
        FFrameView.CellTimeOffset(I), AFormat),
      AFormat, FSettings.JpegQuality, FSettings.PngCompression);
  end;
end;

procedure TFrameExporter.SaveSingleFrame(const AFileName: string;
  AContextCellIndex: Integer);
var
  Idx: Integer;
  Fmt: TSaveFormat;
  Path: string;
begin
  if not ResolveFrameIndex(AContextCellIndex, Idx) then Exit;

  if ShowSaveDialog('Save frame',
    GenerateFrameFileName(AFileName, Idx,
      FFrameView.CellTimeOffset(Idx), FSettings.SaveFormat),
    True, Path, Fmt) then
    uBitmapSaver.SaveBitmapToFile(FFrameView.CellBitmap(Idx), Path, Fmt,
      FSettings.JpegQuality, FSettings.PngCompression);
end;

procedure TFrameExporter.SaveSelectedFrames(const AFileName: string);
var
  I, FirstSel: Integer;
  Path: string;
  Fmt: TSaveFormat;
begin
  if FFrameView.SelectedCount < 2 then Exit;

  { Find first selected frame for the sample filename }
  FirstSel := 0;
  for I := 0 to FFrameView.CellCount - 1 do
    if FFrameView.CellSelected(I) then begin FirstSel := I; Break; end;

  if not ShowSaveDialog('Save selected frames',
    GenerateFrameFileName(AFileName, FirstSel,
      FFrameView.CellTimeOffset(FirstSel), FSettings.SaveFormat),
    False, Path, Fmt) then
    Exit;

  SaveFramesToDir(IncludeTrailingPathDelimiter(ExtractFilePath(Path)),
    Fmt, True, AFileName);
end;

procedure TFrameExporter.SaveCombinedFrame(const AFileName: string);
var
  Bmp: TBitmap;
  Fmt: TSaveFormat;
  Path, BaseName: string;
begin
  if FFrameView.CellCount = 0 then Exit;

  BaseName := ChangeFileExt(ExtractFileName(AFileName), '');
  if not ShowSaveDialog('Save combined image', BaseName + '_combined.png',
    True, Path, Fmt) then
    Exit;

  Bmp := RenderWithBanner(RenderFrameView);
  try
    uBitmapSaver.SaveBitmapToFile(Bmp, Path, Fmt,
      FSettings.JpegQuality, FSettings.PngCompression);
  finally
    Bmp.Free;
  end;
end;

procedure TFrameExporter.SaveAllFrames(const AFileName: string);
var
  Path: string;
  Fmt: TSaveFormat;
begin
  if FFrameView.CellCount = 0 then Exit;

  if not ShowSaveDialog('Save all frames',
    GenerateFrameFileName(AFileName, 0,
      FFrameView.CellTimeOffset(0), FSettings.SaveFormat),
    False, Path, Fmt) then
    Exit;

  SaveFramesToDir(IncludeTrailingPathDelimiter(ExtractFilePath(Path)),
    Fmt, False, AFileName);
end;

procedure TFrameExporter.CopyFrameToClipboard(AContextCellIndex: Integer);
var
  Idx: Integer;
begin
  if not ResolveFrameIndex(AContextCellIndex, Idx) then Exit;
  Clipboard.Assign(FFrameView.CellBitmap(Idx));
end;

procedure TFrameExporter.CopyAllToClipboard;
var
  Bmp: TBitmap;
begin
  if FFrameView.CellCount = 0 then Exit;
  Bmp := RenderWithBanner(RenderFrameView);
  try
    Clipboard.Assign(Bmp);
  finally
    Bmp.Free;
  end;
end;

end.
