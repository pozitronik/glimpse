{Smoke tests for the TFFmpegFrameExtractor adapter.
 The adapter is a thin forward to TFFmpegExe.ExtractFrame, so the interesting
 behaviour lives in uFFmpegExe (covered by TestFFmpegExe). Tests here just
 pin the adapter's construction contract and confirm it returns nil cleanly
 when the underlying ffmpeg exe is missing, rather than raising.}
unit TestFrameExtractor;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFFmpegFrameExtractor = class
  public
    [Test] procedure CreatesAsIFrameExtractor;
    [Test] procedure ExtractFrame_InvalidExePath_ReturnsNil;
    [Test] procedure ExtractFrame_InvalidExePath_DoesNotRaise;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Graphics,
  uTypes, uFrameExtractor;

function MakeOptions: TExtractionOptions;
begin
  Result := Default(TExtractionOptions);
  Result.UseBmpPipe := True;
  Result.MaxSide := 0;
end;

procedure TTestFFmpegFrameExtractor.CreatesAsIFrameExtractor;
var
  Extractor: IFrameExtractor;
begin
  {Interface handle keeps the refcounted instance alive for the scope —
   implicit release on exit also verifies no leak in Destroy.}
  Extractor := TFFmpegFrameExtractor.Create('C:\nowhere\ffmpeg.exe');
  Assert.IsNotNull(Extractor, 'Construction must yield a non-nil interface');
end;

procedure TTestFFmpegFrameExtractor.ExtractFrame_InvalidExePath_ReturnsNil;
var
  Extractor: IFrameExtractor;
  Bmp: TBitmap;
begin
  {When the configured ffmpeg exe does not exist, RunProcess under the hood
   fails with a non-zero exit and ExtractFrame returns nil. Guards against a
   regression to "return an empty bitmap" or "raise on missing executable".}
  Extractor := TFFmpegFrameExtractor.Create('C:\nowhere\ffmpeg_does_not_exist.exe');
  Bmp := Extractor.ExtractFrame('C:\nowhere\video.mp4', 0.0, MakeOptions);
  try
    Assert.IsNull(Bmp, 'Extraction with missing exe must fail closed by returning nil');
  finally
    Bmp.Free;
  end;
end;

procedure TTestFFmpegFrameExtractor.ExtractFrame_InvalidExePath_DoesNotRaise;
var
  Extractor: IFrameExtractor;
begin
  {Separate assertion style: Assert.WillNotRaise surfaces the specific
   exception class/message when the contract is violated, rather than
   a generic test failure.}
  Extractor := TFFmpegFrameExtractor.Create('');
  Assert.WillNotRaiseAny(
    procedure
    var
      Bmp: TBitmap;
    begin
      Bmp := Extractor.ExtractFrame('anywhere.mp4', 5.0, MakeOptions);
      Bmp.Free;
    end,
    'Empty ffmpeg path must be handled without raising');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFFmpegFrameExtractor);

end.
