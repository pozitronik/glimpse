{RAII scope helper for TFrameExporter override-frames. Used as a local
 IInterface variable so Delphi's refcount triggers the destructor on exit:
 the destructor MUST clear the exporter's reference before freeing the
 bitmaps, or the exporter would see freed memory.}
unit uOverrideFramesScope;

interface

uses
  Vcl.Graphics,
  uFrameExport;

type
  IOverrideFramesScope = interface
    ['{2E7F8B1C-4A9D-4F3B-8E2A-7C5D9F1B3E22}']
  end;

  TOverrideFramesScope = class(TInterfacedObject, IOverrideFramesScope)
  strict private
    FExporter: TFrameExporter;
    FFrames: TArray<TBitmap>;
  public
    {Takes ownership of AFrames — callers MUST NOT free the bitmaps themselves.}
    constructor Create(AExporter: TFrameExporter; const AFrames: TArray<TBitmap>);
    destructor Destroy; override;
  end;

implementation

constructor TOverrideFramesScope.Create(AExporter: TFrameExporter;
  const AFrames: TArray<TBitmap>);
begin
  inherited Create;
  FExporter := AExporter;
  FFrames := AFrames;
  FExporter.SetOverrideFrames(FFrames);
end;

destructor TOverrideFramesScope.Destroy;
var
  I: Integer;
begin
  {Clear the exporter's reference BEFORE freeing the bitmaps — otherwise
   the exporter would hold pointers to freed memory.}
  if FExporter <> nil then
    FExporter.ClearOverrideFrames;
  for I := 0 to High(FFrames) do
    FFrames[I].Free;
  FFrames := nil;
  inherited;
end;

end.
