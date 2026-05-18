{Frame-selection priority rules for "act on one cell" toolbar / hotkey
 commands (Save frame, Copy frame, Open externally).

 Two policies live here:

 - ResolveFrameIndex: legacy "first usable cell" picker. Prefers the
   explicit context (right-clicked cell), falls back to the current
   focused frame, then to cell 0. Returns False when nothing usable
   is loaded. Selection is NOT consulted — used by code paths that
   pre-date the selection feature.

 - PickActionCell: selection-aware picker for modern Save/Copy/Open
   dispatch. First selected loaded cell wins (selection is a more
   deliberate gesture than a right-click). Then the right-clicked
   context cell. Then the single-view focused frame. Then cell 0.
   Returns -1 when nothing is loaded.

 Both policies operate on a tiny IFrameViewQuery interface rather than
 directly on TFrameView so the rules are testable without VCL and
 without dragging in the TFrameCellState enum (the policy only checks
 "is this cell loaded?" — IFrameViewQuery answers that as a Boolean).
 The TFrameView adapter lives in the caller (uFrameExport).}
unit uFrameSelectionPolicy;

interface

type
  {Read-only view of the frame-grid state needed by the selection
   policies. Implementations adapt over a real TFrameView in production
   or return canned values in tests.}
  IFrameViewQuery = interface
    ['{1E7B4F9A-3D5C-4A82-9B6E-C0F8D2A5E731}']
    function CellCount: Integer;
    function CurrentFrameIndex: Integer;
    {True iff the cell at AIndex has finished extracting and holds a
     bitmap (TFrameCellState = fcsLoaded). False for placeholder /
     error / out-of-range indices.}
    function CellIsLoaded(AIndex: Integer): Boolean;
    function CellSelected(AIndex: Integer): Boolean;
    {True iff the view is currently in vmSingle mode (one large frame
     fills the viewport). Used to elevate CurrentFrameIndex's priority
     in the selection-aware picker because it is then visually the
     "focused" frame.}
    function IsSingleView: Boolean;
  end;

  TFrameSelectionPolicy = class
  public
    {Legacy resolver: prefers AContextCellIndex, falls back to
     CurrentFrameIndex, then 0. Returns True with AIndex populated when
     the picked cell is loaded; False when CellCount=0 or the picked
     cell is not loaded.}
    class function ResolveFrameIndex(const AView: IFrameViewQuery;
      AContextCellIndex: Integer; out AIndex: Integer): Boolean; static;

    {Selection-aware picker. Priority:
       1. First selected loaded cell — selection wins over right-click
          because it is a longer-lived, more deliberate gesture.
       2. Right-clicked context cell when it is loaded.
       3. CurrentFrameIndex when in single-view mode and loaded.
       4. Cell 0 when loaded.
       5. -1 when nothing is loaded; callers must skip the action.}
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
  {1. First selected loaded cell.}
  for I := 0 to AView.CellCount - 1 do
    if AView.CellSelected(I) and AView.CellIsLoaded(I) then
      Exit(I);

  {2. Explicit context (right-click) when it points to a loaded cell.}
  if (AContextCellIndex >= 0) and (AContextCellIndex < AView.CellCount)
    and AView.CellIsLoaded(AContextCellIndex) then
    Exit(AContextCellIndex);

  {3. Single-view focused frame.}
  if AView.IsSingleView
    and (AView.CurrentFrameIndex >= 0) and (AView.CurrentFrameIndex < AView.CellCount)
    and AView.CellIsLoaded(AView.CurrentFrameIndex) then
    Exit(AView.CurrentFrameIndex);

  {4. Cell 0.}
  if (AView.CellCount > 0) and AView.CellIsLoaded(0) then
    Exit(0);

  {5. Nothing loaded — caller must skip the action.}
  Result := -1;
end;

end.
