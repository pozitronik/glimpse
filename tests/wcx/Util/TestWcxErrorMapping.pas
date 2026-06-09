{Pins the exception-to-WCX-error mapping table and the ANSI-header size
 clamp. Total Commander reacts to these codes (retry prompts, error
 dialogs), so a silently dropped mapping degrades every failure into the
 generic "disk write failed".}
unit TestWcxErrorMapping;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestWcxErrorMapping = class
  public
    [Test] procedure OutOfMemoryClass_MapsToNoMemory;
    [Test] procedure FileNotFoundClass_MapsToEOpen;
    [Test] procedure SubclassOfMappedClass_MatchesViaInheritance;
    [Test] procedure NilClass_FallsBackToWrite;
    [Test] procedure UnmappedClass_FallsBackToWrite;
    [Test] procedure ExceptionInstance_MapsByClassType;
    [Test] procedure NilException_FallsBackToWrite;
    [Test] procedure Clamp_Negative_ReturnsZero;
    [Test] procedure Clamp_Zero_ReturnsZero;
    [Test] procedure Clamp_InRange_ReturnsValue;
    [Test] procedure Clamp_MaxInt_ReturnsMaxInt;
    [Test] procedure Clamp_AboveMaxInt_SaturatesAtMaxInt;
  end;

implementation

uses
  System.SysUtils,
  WcxAPI, WcxErrorMapping;

type
  {Local subclass to pin the InheritsFrom matching: future subclasses of a
   mapped exception must resolve to the same WCX code.}
  ETestDerivedOutOfMemory = class(EOutOfMemory);

procedure TTestWcxErrorMapping.OutOfMemoryClass_MapsToNoMemory;
begin
  Assert.AreEqual(E_NO_MEMORY, ExceptionClassToWcxError(EOutOfMemory));
end;

procedure TTestWcxErrorMapping.FileNotFoundClass_MapsToEOpen;
begin
  Assert.AreEqual(E_EOPEN, ExceptionClassToWcxError(EFileNotFoundException));
end;

procedure TTestWcxErrorMapping.SubclassOfMappedClass_MatchesViaInheritance;
begin
  Assert.AreEqual(E_NO_MEMORY, ExceptionClassToWcxError(ETestDerivedOutOfMemory));
end;

procedure TTestWcxErrorMapping.NilClass_FallsBackToWrite;
begin
  Assert.AreEqual(E_EWRITE, ExceptionClassToWcxError(nil));
end;

procedure TTestWcxErrorMapping.UnmappedClass_FallsBackToWrite;
begin
  {The base Exception class is deliberately unmapped: anything not in the
   table must land on E_EWRITE rather than raising or returning garbage.}
  Assert.AreEqual(E_EWRITE, ExceptionClassToWcxError(Exception));
  Assert.AreEqual(E_EWRITE, ExceptionClassToWcxError(EAccessViolation));
end;

procedure TTestWcxErrorMapping.ExceptionInstance_MapsByClassType;
var
  E: Exception;
begin
  {EFileNotFoundException, not EOutOfMemory: EHeapException.FreeInstance
   refuses to deallocate (RTL preallocated-singleton mechanics), so an
   EOutOfMemory instance would be reported as a leak by FastMM.}
  E := EFileNotFoundException.Create('test');
  try
    Assert.AreEqual(E_EOPEN, ExceptionToWcxError(E));
  finally
    E.Free;
  end;
end;

procedure TTestWcxErrorMapping.NilException_FallsBackToWrite;
begin
  Assert.AreEqual(E_EWRITE, ExceptionToWcxError(nil));
end;

procedure TTestWcxErrorMapping.Clamp_Negative_ReturnsZero;
begin
  Assert.AreEqual(0, ClampSizeForAnsiHeader(-1));
  Assert.AreEqual(0, ClampSizeForAnsiHeader(Int64.MinValue));
end;

procedure TTestWcxErrorMapping.Clamp_Zero_ReturnsZero;
begin
  Assert.AreEqual(0, ClampSizeForAnsiHeader(0));
end;

procedure TTestWcxErrorMapping.Clamp_InRange_ReturnsValue;
begin
  Assert.AreEqual(123456, ClampSizeForAnsiHeader(123456));
end;

procedure TTestWcxErrorMapping.Clamp_MaxInt_ReturnsMaxInt;
begin
  Assert.AreEqual(MaxInt, ClampSizeForAnsiHeader(MaxInt));
end;

procedure TTestWcxErrorMapping.Clamp_AboveMaxInt_SaturatesAtMaxInt;
begin
  Assert.AreEqual(MaxInt, ClampSizeForAnsiHeader(Int64(MaxInt) + 1));
  {A ~5 GB combined image must surface as ~2 GB, not wrap negative.}
  Assert.AreEqual(MaxInt, ClampSizeForAnsiHeader(Int64(5) * 1024 * 1024 * 1024));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWcxErrorMapping);

end.
