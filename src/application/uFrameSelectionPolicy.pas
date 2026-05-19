{Frame-selection priority rules for "act on one cell" toolbar / hotkey
 commands. Operates on IFrameViewQuery to stay VCL-free and testable.}
unit uFrameSelectionPolicy;

interface

type
  {Read-only view of the frame-grid state needed by the selection
   policies. Adapter for tests; production wraps TFrameView.}
  IFrameViewQuery = interface
    ['{1E7B4F9A-3D5C-4A82-9B6E-C0F8D2A5E731}']
    function CellCount: Integer;
    function CurrentFrameIndex: Integer;
    function CellIsLoaded(AIndex: Integer): Boolean;
    function CellSelected(AIndex: Integer): Boolean;
    function IsSingleView: Boolean;
  end;

  TFrameSelectionPolicy = class
  public
    {Prefers AContextCellIndex, falls back to CurrentFrameIndex, then 0.
     Returns False when CellCount=0 or the picked cell is not loaded.}
    class function ResolveFrameIndex(const AView: IFrameViewQuery;
      AContextCellIndex: Integer; out AIndex: Integer): Boolean; static;

    {Selection-aware picker. Priority: selected loaded cell, context
     cell, single-view focused frame, cell 0. Returns -1 when nothing
     is loaded; callers must skip the action.}
    class function PickActionCell(const AView: IFrameViewQuery;
      AContextCellIndex: Integer): Integer; static;
  end;

implementation

class function TFrameSelectionPolicy.ResolveFrameIndex(const AView: IFrameViewQuery;
  AContextCellIndex: Integer; out AIndex: Integer): Boolean;
begin
  Result := False;
  if AView.CellCount = 0 then
    Exit;
  AIndex := AContextCellIndex;
  if (AIndex < 0) or (AIndex >= AView.CellCount) then
    AIndex := AView.CurrentFrameIndex;
  if (AIndex < 0) or (AIndex >= AView.CellCount) then
    AIndex := 0;
  Result := AView.CellIsLoaded(AIndex);
end;

class function TFrameSelectionPolicy.PickActionCell(const AView: IFrameViewQuery;
  AContextCellIndex: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to AView.CellCount - 1 do
    if AView.CellSelected(I) and AView.CellIsLoaded(I) then
      Exit(I);

  if (AContextCellIndex >= 0) and (AContextCellIndex < AView.CellCount)
    and AView.CellIsLoaded(AContextCellIndex) then
    Exit(AContextCellIndex);

  if AView.IsSingleView
    and (AView.CurrentFrameIndex >= 0) and (AView.CurrentFrameIndex < AView.CellCount)
    and AView.CellIsLoaded(AView.CurrentFrameIndex) then
    Exit(AView.CurrentFrameIndex);

  if (AView.CellCount > 0) and AView.CellIsLoaded(0) then
    Exit(0);

  Result := -1;
end;

end.
