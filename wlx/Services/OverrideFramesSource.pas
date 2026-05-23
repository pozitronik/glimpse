{Source-of-truth selector for the bitmap that save/copy paths should
 consume for a given cell. Honours the host-supplied override-frames
 array (typically native-resolution re-extracts from TFrameCache) when
 SaveAtLiveResolution is off; falls back to the live FrameView cell
 otherwise. Bitmaps are not owned; the host that supplied them controls
 lifetime.}
unit OverrideFramesSource;

interface

uses
  Vcl.Graphics,
  FrameView, FrameCellStore;

type
  TOverrideFramesSource = class
  strict private
    FFrameView: TFrameView;
    {Indexed parallel to FFrameView cells. Non-owned (typically owned by
     TFrameCache). nil entries fall back to the live cell. Length 0 disables.}
    FOverrideFrames: TArray<Vcl.Graphics.TBitmap>;
  public
    {AFrameView is borrowed.}
    constructor Create(AFrameView: TFrameView);
    {Returns the bitmap save/copy paths should consume for cell AIndex,
     honouring FOverrideFrames when set and ALiveResolutionIntent is off.
     ALiveResolutionIntent True ignores any override and uses the live
     cell. Returns nil when the cell is not loaded.}
    function PickSaveBitmap(AIndex: Integer; ALiveResolutionIntent: Boolean): Vcl.Graphics.TBitmap;
    {Set before invoking a save/copy when SaveAtLiveResolution is off and
     the caller has re-extracted at native (or capped) resolution; clear
     immediately after. Bitmaps are not owned by the source.}
    procedure SetOverrideFrames(const AFrames: TArray<Vcl.Graphics.TBitmap>);
    procedure ClearOverrideFrames;
  end;

implementation

constructor TOverrideFramesSource.Create(AFrameView: TFrameView);
begin
  inherited Create;
  FFrameView := AFrameView;
end;

function TOverrideFramesSource.PickSaveBitmap(AIndex: Integer; ALiveResolutionIntent: Boolean): Vcl.Graphics.TBitmap;
begin
  Result := nil;
  if (not ALiveResolutionIntent) and (AIndex >= 0) and (AIndex < Length(FOverrideFrames)) and (FOverrideFrames[AIndex] <> nil) then
    Exit(FOverrideFrames[AIndex]);
  if (AIndex >= 0) and (AIndex < FFrameView.CellCount) and (FFrameView.CellState(AIndex) = fcsLoaded) then
    Result := FFrameView.CellBitmap(AIndex);
end;

procedure TOverrideFramesSource.SetOverrideFrames(const AFrames: TArray<Vcl.Graphics.TBitmap>);
begin
  FOverrideFrames := AFrames;
end;

procedure TOverrideFramesSource.ClearOverrideFrames;
begin
  SetLength(FOverrideFrames, 0);
end;

end.
