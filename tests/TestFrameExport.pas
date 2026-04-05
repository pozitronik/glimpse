unit TestFrameExport;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestResolveFrameIndex = class
  public
    [Test] procedure TestContextCellPreferred;
    [Test] procedure TestFallsBackToCurrentFrame;
    [Test] procedure TestFallsBackToZero;
    [Test] procedure TestReturnsFalseWhenEmpty;
    [Test] procedure TestReturnsFalseWhenNotLoaded;
    [Test] procedure TestNegativeContextIgnored;
    [Test] procedure TestOutOfRangeContextIgnored;
  end;

implementation

uses
  System.SysUtils, System.Types, Vcl.Forms, Vcl.Controls, Vcl.Graphics,
  uFrameView, uFrameOffsets, uSettings, uFrameExport;

{ Helper: creates a temporary TFrameView parented to a form }
function CreateTestFrameView(AForm: TForm; ACellCount: Integer;
  const ALoadedIndices: array of Integer): TFrameView;
var
  Offsets: TFrameOffsetArray;
  I: Integer;
  Bmp: TBitmap;
begin
  Result := TFrameView.Create(AForm);
  Result.Parent := AForm;
  Result.SetViewport(800, 600);
  Result.AspectRatio := 9 / 16;

  SetLength(Offsets, ACellCount);
  for I := 0 to ACellCount - 1 do
  begin
    Offsets[I].Index := I + 1;
    Offsets[I].TimeOffset := I * 1.0;
  end;
  Result.SetCellCount(ACellCount, Offsets);

  for I := 0 to High(ALoadedIndices) do
  begin
    Bmp := TBitmap.Create;
    Bmp.SetSize(160, 90);
    Result.SetFrame(ALoadedIndices[I], Bmp);
  end;
end;

{ TTestResolveFrameIndex }

procedure TTestResolveFrameIndex.TestContextCellPreferred;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 2, 4]);
    Exporter := TFrameExporter.Create(View, nil);
    try
      Assert.IsTrue(Exporter.ResolveFrameIndex(2, Idx));
      Assert.AreEqual(2, Idx);
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestResolveFrameIndex.TestFallsBackToCurrentFrame;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 5, [0, 3]);
    View.CurrentFrameIndex := 3;
    Exporter := TFrameExporter.Create(View, nil);
    try
      { Context index -1 => falls back to CurrentFrameIndex }
      Assert.IsTrue(Exporter.ResolveFrameIndex(-1, Idx));
      Assert.AreEqual(3, Idx);
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestResolveFrameIndex.TestFallsBackToZero;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 3, [0]);
    View.CurrentFrameIndex := -1;
    Exporter := TFrameExporter.Create(View, nil);
    try
      Assert.IsTrue(Exporter.ResolveFrameIndex(-1, Idx));
      Assert.AreEqual(0, Idx);
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestResolveFrameIndex.TestReturnsFalseWhenEmpty;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 0, []);
    Exporter := TFrameExporter.Create(View, nil);
    try
      Assert.IsFalse(Exporter.ResolveFrameIndex(-1, Idx));
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestResolveFrameIndex.TestReturnsFalseWhenNotLoaded;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    { 3 cells, none loaded }
    View := CreateTestFrameView(Form, 3, []);
    Exporter := TFrameExporter.Create(View, nil);
    try
      Assert.IsFalse(Exporter.ResolveFrameIndex(1, Idx));
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestResolveFrameIndex.TestNegativeContextIgnored;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 3, [0, 1, 2]);
    View.CurrentFrameIndex := 1;
    Exporter := TFrameExporter.Create(View, nil);
    try
      Assert.IsTrue(Exporter.ResolveFrameIndex(-5, Idx));
      Assert.AreEqual(1, Idx);
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

procedure TTestResolveFrameIndex.TestOutOfRangeContextIgnored;
var
  Form: TForm;
  View: TFrameView;
  Exporter: TFrameExporter;
  Idx: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    View := CreateTestFrameView(Form, 3, [0, 1, 2]);
    View.CurrentFrameIndex := 2;
    Exporter := TFrameExporter.Create(View, nil);
    try
      Assert.IsTrue(Exporter.ResolveFrameIndex(99, Idx));
      Assert.AreEqual(2, Idx);
    finally
      Exporter.Free;
    end;
  finally
    Form.Free;
  end;
end;

end.
