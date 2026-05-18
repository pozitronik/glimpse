unit TestVideoInfo;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestVideoInfoIsValid = class
  public
    {IsValid is now a derived method (Duration > 0) rather than a stored
     field. The two former writers (ProbeVideo, TProbeCache.TryGet)
     used to set it explicitly; the methodisation removes the drift
     hazard. Tests pin the contract: positive duration is valid, every
     other case is invalid.}
    [Test] procedure ZeroDuration_IsInvalid;
    [Test] procedure NegativeDuration_IsInvalid;
    [Test] procedure PositiveDuration_IsValid;
    {Default(TVideoInfo) gives Duration=0 -> IsValid=False — pre-fill
     guarantee for callers that initialise via Default(...) and then
     populate.}
    [Test] procedure DefaultRecord_IsInvalid;
  end;

  [TestFixture]
  TTestVideoInfoHasAudio = class
  public
    {HasAudio is sourced from AudioCodec being non-empty. ffmpeg only
     emits the audio-codec line when an audio stream is present, so
     the empty-string check is a faithful proxy.}
    [Test] procedure EmptyAudioCodec_NoAudio;
    [Test] procedure NonEmptyAudioCodec_HasAudio;
  end;

  [TestFixture]
  TTestVideoInfoRecalcDisplayDimensions = class
  public
    {SAR=1:1 is the dominant case; display dims must mirror storage.}
    [Test] procedure Sar1x1_DisplayMatchesStorage;
    {Anamorphic sources (e.g. PAL DVD 720x576 SAR=64:45) display as
     ~1024x576. The exact rounding rule (Round) is part of the
     contract; if rendering ever shows fractional pixel artefacts we
     need to revisit it intentionally rather than discover the drift.}
    [Test] procedure SarAnamorphicPal_ScalesWidth_LeavesHeight;
    {Square-pixel HD (1920x1080 SAR=1:1).}
    [Test] procedure SarSquareHd_PassesThrough;
    {Missing SampleAspect (D=0) falls back to storage. Cache entries
     pre-SAR had no SampleAspect keys; StrToIntDef returns 0 for
     missing keys; the math must degrade gracefully rather than divide
     by zero.}
    [Test] procedure ZeroSampleAspectD_FallsBackToStorage;
    [Test] procedure ZeroWidth_FallsBackToStorage;
    {Idempotent: calling repeatedly must return the same dimensions.
     Required because TProbeCache.TryGet calls it during load even
     when DisplayWidth/Height are already populated from the cache —
     production behaviour for forward-written entries depends on this.}
    [Test] procedure RepeatedCalls_AreIdempotent;
  end;

implementation

uses
  uVideoInfo;

{ TTestVideoInfoIsValid }

procedure TTestVideoInfoIsValid.ZeroDuration_IsInvalid;
var
  Info: TVideoInfo;
begin
  Info := Default(TVideoInfo);
  Info.Duration := 0;
  Assert.IsFalse(Info.IsValid);
end;

procedure TTestVideoInfoIsValid.NegativeDuration_IsInvalid;
var
  Info: TVideoInfo;
begin
  Info := Default(TVideoInfo);
  Info.Duration := -1;
  Assert.IsFalse(Info.IsValid, 'Probe sentinel -1 must surface as invalid');
end;

procedure TTestVideoInfoIsValid.PositiveDuration_IsValid;
var
  Info: TVideoInfo;
begin
  Info := Default(TVideoInfo);
  Info.Duration := 0.001;
  Assert.IsTrue(Info.IsValid, 'Any positive duration counts as valid');
end;

procedure TTestVideoInfoIsValid.DefaultRecord_IsInvalid;
var
  Info: TVideoInfo;
begin
  Info := Default(TVideoInfo);
  Assert.IsFalse(Info.IsValid,
    'Default(TVideoInfo) gives Duration=0; IsValid must return False');
end;

{ TTestVideoInfoHasAudio }

procedure TTestVideoInfoHasAudio.EmptyAudioCodec_NoAudio;
var
  Info: TVideoInfo;
begin
  Info := Default(TVideoInfo);
  Assert.IsFalse(Info.HasAudio);
end;

procedure TTestVideoInfoHasAudio.NonEmptyAudioCodec_HasAudio;
var
  Info: TVideoInfo;
begin
  Info := Default(TVideoInfo);
  Info.AudioCodec := 'aac';
  Assert.IsTrue(Info.HasAudio);
end;

{ TTestVideoInfoRecalcDisplayDimensions }

procedure TTestVideoInfoRecalcDisplayDimensions.Sar1x1_DisplayMatchesStorage;
var
  Info: TVideoInfo;
begin
  Info := Default(TVideoInfo);
  Info.Width := 640;
  Info.Height := 480;
  Info.SampleAspectN := 1;
  Info.SampleAspectD := 1;
  Info.RecalcDisplayDimensions;
  Assert.AreEqual<Integer>(640, Info.DisplayWidth);
  Assert.AreEqual<Integer>(480, Info.DisplayHeight);
end;

procedure TTestVideoInfoRecalcDisplayDimensions.SarAnamorphicPal_ScalesWidth_LeavesHeight;
var
  Info: TVideoInfo;
begin
  {PAL DVD: 720x576 storage, SAR=64:45 -> 1024x576 display.
   720 * 64 / 45 = 1024 exactly.}
  Info := Default(TVideoInfo);
  Info.Width := 720;
  Info.Height := 576;
  Info.SampleAspectN := 64;
  Info.SampleAspectD := 45;
  Info.RecalcDisplayDimensions;
  Assert.AreEqual<Integer>(1024, Info.DisplayWidth);
  Assert.AreEqual<Integer>(576, Info.DisplayHeight,
    'Anamorphic SAR scales width only; height passes through');
end;

procedure TTestVideoInfoRecalcDisplayDimensions.SarSquareHd_PassesThrough;
var
  Info: TVideoInfo;
begin
  Info := Default(TVideoInfo);
  Info.Width := 1920;
  Info.Height := 1080;
  Info.SampleAspectN := 1;
  Info.SampleAspectD := 1;
  Info.RecalcDisplayDimensions;
  Assert.AreEqual<Integer>(1920, Info.DisplayWidth);
  Assert.AreEqual<Integer>(1080, Info.DisplayHeight);
end;

procedure TTestVideoInfoRecalcDisplayDimensions.ZeroSampleAspectD_FallsBackToStorage;
var
  Info: TVideoInfo;
begin
  {Pre-SAR cache entries had no SampleAspect keys; StrToIntDef returns
   0 for missing. RecalcDisplayDimensions must NOT divide by zero;
   instead it falls back to storage = display.}
  Info := Default(TVideoInfo);
  Info.Width := 800;
  Info.Height := 600;
  Info.SampleAspectN := 0;
  Info.SampleAspectD := 0;
  Info.RecalcDisplayDimensions;
  Assert.AreEqual<Integer>(800, Info.DisplayWidth);
  Assert.AreEqual<Integer>(600, Info.DisplayHeight);
end;

procedure TTestVideoInfoRecalcDisplayDimensions.ZeroWidth_FallsBackToStorage;
var
  Info: TVideoInfo;
begin
  Info := Default(TVideoInfo);
  Info.Width := 0;
  Info.Height := 0;
  Info.SampleAspectN := 16;
  Info.SampleAspectD := 9;
  Info.RecalcDisplayDimensions;
  Assert.AreEqual<Integer>(0, Info.DisplayWidth);
  Assert.AreEqual<Integer>(0, Info.DisplayHeight);
end;

procedure TTestVideoInfoRecalcDisplayDimensions.RepeatedCalls_AreIdempotent;
var
  Info: TVideoInfo;
  W1, H1, W2, H2: Integer;
begin
  Info := Default(TVideoInfo);
  Info.Width := 720;
  Info.Height := 576;
  Info.SampleAspectN := 64;
  Info.SampleAspectD := 45;
  Info.RecalcDisplayDimensions;
  W1 := Info.DisplayWidth;
  H1 := Info.DisplayHeight;
  Info.RecalcDisplayDimensions;
  W2 := Info.DisplayWidth;
  H2 := Info.DisplayHeight;
  Assert.AreEqual<Integer>(W1, W2);
  Assert.AreEqual<Integer>(H1, H2);
end;

end.
