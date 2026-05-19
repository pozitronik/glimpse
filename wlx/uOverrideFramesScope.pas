{RAII scope helper for TFrameExporter override-frames.

 Step 107 (N1): TPluginForm.WithReExtract had two nested try-finally
 blocks coordinating (1) the exporter override-frames set/clear cycle
 and (2) the bitmap-array free. The nesting was correct but read like
 a small puzzle. Rewriting both lifetimes as a single TInterfacedObject
 scope collapses the dance: constructor takes ownership of both
 concerns, destructor unwinds them in the right order.

 The scope is used as a local `IInterface`-typed variable in WithReExtract;
 Delphi releases the reference when the procedure exits, which triggers
 the destructor → ClearOverrideFrames → free bitmaps. The order matters
 (the exporter must NOT see freed bitmaps) and is enforced by destructor
 sequencing here, not by caller discipline.}
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
    {Takes ownership of AFrames (callers MUST NOT free the bitmaps
     themselves). Sets them on AExporter as override frames; the
     destructor clears the override before freeing the bitmaps so
     the exporter never sees freed memory.}
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
  {Order matters: clear the exporter's reference to the bitmaps BEFORE
   freeing them. ClearOverrideFrames does not free the bitmaps itself
   (the exporter never owned them); after this call the exporter holds
   no references to FFrames so freeing each bitmap below is safe.}
  if FExporter <> nil then
    FExporter.ClearOverrideFrames;
  for I := 0 to High(FFrames) do
    FFrames[I].Free;
  FFrames := nil;
  inherited;
end;

end.
