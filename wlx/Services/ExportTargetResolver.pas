{Resolves which frame indices an export action operates on. Wraps the
 frame view in a VCL-free IFrameViewQuery so the selection rules stay in
 the domain TFrameSelectionPolicy. A plain class; TFrameExporter owns one.}
unit ExportTargetResolver;

interface

uses
  FrameView;

type
  TExportTargetResolver = class
  strict private
    FFrameView: TFrameView;
  public
    {AFrameView is borrowed; TFrameExporter owns it.}
    constructor Create(AFrameView: TFrameView);
    {Prefers AContextCellIndex, falls back to CurrentFrameIndex, then 0.
     Returns False when no loaded frame is found.}
    function ResolveFrameIndex(AContextCellIndex: Integer; out AIndex: Integer): Boolean;
    {Selection-aware singular-action resolver. Priority:
       1. AContextCellIndex when in range and loaded.
       2. First selected loaded cell (multi-selection collapses by design).
       3. CurrentFrameIndex when loaded.
       4. Cell 0 when loaded.
       5. -1 when nothing usable.
     Differs from ResolveFrameIndex (which never consults selection).}
    function PickActionCell(AContextCellIndex: Integer): Integer;
    {Single = one element when ResolveFrameIndex succeeds; AllLoaded = every
     fcsLoaded cell; SelectedOrAll = selection when non-empty, else all loaded.}
    function BuildSaveIndicesSingle(AContextCellIndex: Integer): TArray<Integer>;
    function BuildSaveIndicesAllLoaded: TArray<Integer>;
    function BuildSaveIndicesSelectedOrAll: TArray<Integer>;
  end;

implementation

uses
  Types,
  FrameCellStore,
  FrameSelectionPolicy;

type
  {Production IFrameViewQuery adapter over a TFrameView. The selection
   policy operates on this thin read-only view so its rules live in a
   VCL-free unit. Constructed and freed per resolution call; the adapter
   is stateless beyond holding a FFrameView reference.}
  TFrameViewQueryAdapter = class(TInterfacedObject, IFrameViewQuery)
  strict private
    FFrameView: TFrameView;
  public
    constructor Create(AFrameView: TFrameView);
    function CellCount: Integer;
    function CurrentFrameIndex: Integer;
    function CellIsLoaded(AIndex: Integer): Boolean;
    function CellSelected(AIndex: Integer): Boolean;
    function IsSingleView: Boolean;
  end;

constructor TExportTargetResolver.Create(AFrameView: TFrameView);
begin
  inherited Create;
  FFrameView := AFrameView;
end;

function TExportTargetResolver.ResolveFrameIndex(AContextCellIndex: Integer; out AIndex: Integer): Boolean;
var
  View: IFrameViewQuery;
begin
  {Explicit local needed: passing TFrameViewQueryAdapter.Create directly
   into a const-interface param skips the AddRef/Release pair and leaks.}
  View := TFrameViewQueryAdapter.Create(FFrameView);
  Result := TFrameSelectionPolicy.ResolveFrameIndex(View, AContextCellIndex, AIndex);
end;

function TExportTargetResolver.PickActionCell(AContextCellIndex: Integer): Integer;
var
  View: IFrameViewQuery;
begin
  View := TFrameViewQueryAdapter.Create(FFrameView);
  Result := TFrameSelectionPolicy.PickActionCell(View, AContextCellIndex);
end;

function TExportTargetResolver.BuildSaveIndicesSingle(AContextCellIndex: Integer): TArray<Integer>;
var
  Idx: Integer;
begin
  if ResolveFrameIndex(AContextCellIndex, Idx) then
    Result := TArray<Integer>.Create(Idx)
  else
    SetLength(Result, 0);
end;

function TExportTargetResolver.BuildSaveIndicesAllLoaded: TArray<Integer>;
var
  I: Integer;
begin
  SetLength(Result, 0);
  for I := 0 to FFrameView.CellCount - 1 do
    if FFrameView.CellState(I) = fcsLoaded then
      Result := Result + [I];
end;

function TExportTargetResolver.BuildSaveIndicesSelectedOrAll: TArray<Integer>;
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

{ TFrameViewQueryAdapter }

constructor TFrameViewQueryAdapter.Create(AFrameView: TFrameView);
begin
  inherited Create;
  FFrameView := AFrameView;
end;

function TFrameViewQueryAdapter.CellCount: Integer;
begin
  Result := FFrameView.CellCount;
end;

function TFrameViewQueryAdapter.CurrentFrameIndex: Integer;
begin
  Result := FFrameView.CurrentFrameIndex;
end;

function TFrameViewQueryAdapter.CellIsLoaded(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < FFrameView.CellCount)
    and (FFrameView.CellState(AIndex) = fcsLoaded);
end;

function TFrameViewQueryAdapter.CellSelected(AIndex: Integer): Boolean;
begin
  Result := FFrameView.CellSelected(AIndex);
end;

function TFrameViewQueryAdapter.IsSingleView: Boolean;
begin
  Result := FFrameView.ViewMode = vmSingle;
end;

end.
