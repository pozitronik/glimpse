{Pins that TPluginSettings actually satisfies each of the 6 narrow
 settings interfaces and that getter/setter readback matches the
 underlying flat property. The interfaces are pure contracts, so this
 is the one seam that can break silently.}
unit TestSettingsInterfaces;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSettingsInterfaces = class
  public
    [Test] procedure TPluginSettings_ImplementsITimecodeStyleProvider;
    [Test] procedure TPluginSettings_ImplementsIBannerStyleProvider;
    [Test] procedure TPluginSettings_ImplementsISaveFormatPolicy;
    [Test] procedure TPluginSettings_ImplementsIRenderSizePolicy;
    [Test] procedure TPluginSettings_ImplementsIRenderColorPolicy;
    [Test] procedure TPluginSettings_ImplementsIClipboardPolicy;
    [Test] procedure SaveFormatPolicy_SetSaveFolder_RoundTrips;
    [Test] procedure SaveFormatPolicy_SetSaveAtLiveResolution_RoundTrips;
    [Test] procedure NoRefCount_InterfaceRefRelease_DoesNotFreeInstance;
  end;

implementation

uses
  System.SysUtils, System.UITypes,
  Vcl.Graphics,
  BitmapSaver,
  Settings, SettingsInterfaces;

procedure TTestSettingsInterfaces.TPluginSettings_ImplementsITimecodeStyleProvider;
var
  S: TPluginSettings;
  P: ITimecodeStyleProvider;
begin
  S := TPluginSettings.Create('');
  try
    S.TimestampFontSize := 17;
    P := S;
    Assert.AreEqual(17, P.GetTimestamp.FontSize,
      'ITimecodeStyleProvider.GetTimestamp must reflect the underlying group');
  finally
    S.Free;
  end;
end;

procedure TTestSettingsInterfaces.TPluginSettings_ImplementsIBannerStyleProvider;
var
  S: TPluginSettings;
  P: IBannerStyleProvider;
begin
  S := TPluginSettings.Create('');
  try
    S.ShowBanner := True;
    S.BannerFontSize := 22;
    P := S;
    Assert.IsTrue(P.GetShowBanner, 'GetShowBanner reflects the underlying toggle');
    Assert.AreEqual(22, P.GetBanner.FontSize,
      'GetBanner.FontSize reflects the underlying group');
  finally
    S.Free;
  end;
end;

procedure TTestSettingsInterfaces.TPluginSettings_ImplementsISaveFormatPolicy;
var
  S: TPluginSettings;
  P: ISaveFormatPolicy;
begin
  S := TPluginSettings.Create('');
  try
    S.SaveFormat := sfJPEG;
    S.SaveFolder := 'C:\out';
    S.SaveAtLiveResolution := True;
    S.CopyAtLiveResolution := False;
    P := S;
    Assert.IsTrue(P.GetSaveFormat = sfJPEG);
    Assert.AreEqual('C:\out', P.GetSaveFolder);
    Assert.IsTrue(P.GetSaveAtLiveResolution);
    Assert.IsFalse(P.GetCopyAtLiveResolution);
  finally
    S.Free;
  end;
end;

procedure TTestSettingsInterfaces.TPluginSettings_ImplementsIRenderSizePolicy;
var
  S: TPluginSettings;
  P: IRenderSizePolicy;
begin
  S := TPluginSettings.Create('');
  try
    S.CombinedMaxSide := 4096;
    P := S;
    Assert.AreEqual(4096, P.GetCombinedMaxSide,
      'IRenderSizePolicy.GetCombinedMaxSide must reflect the underlying property');
  finally
    S.Free;
  end;
end;

procedure TTestSettingsInterfaces.TPluginSettings_ImplementsIRenderColorPolicy;
var
  S: TPluginSettings;
  P: IRenderColorPolicy;
begin
  S := TPluginSettings.Create('');
  try
    S.Background := clNavy;
    S.BackgroundAlpha := 200;
    S.CellGap := 7;
    S.CombinedBorder := 9;
    P := S;
    Assert.IsTrue(P.GetBackground = clNavy);
    Assert.AreEqual(200, Integer(P.GetBackgroundAlpha));
    Assert.AreEqual(7, P.GetCellGap);
    Assert.AreEqual(9, P.GetCombinedBorder);
  finally
    S.Free;
  end;
end;

procedure TTestSettingsInterfaces.TPluginSettings_ImplementsIClipboardPolicy;
var
  S: TPluginSettings;
  P: IClipboardPolicy;
begin
  S := TPluginSettings.Create('');
  try
    S.PublishAlphaAwareBitmap := True;
    S.PublishCompressedPng := False;
    S.ClipboardAsFileReference := True;
    S.PngCompression := 7;
    P := S;
    Assert.IsTrue(P.GetClipboardFormats.PublishAlphaAwareBitmap,
      'GetClipboardFormats reflects the underlying group');
    Assert.IsFalse(P.GetClipboardFormats.PublishCompressedPng);
    Assert.IsTrue(P.GetClipboardAsFileReference);
    Assert.AreEqual(7, P.GetPngCompression);
  finally
    S.Free;
  end;
end;

procedure TTestSettingsInterfaces.SaveFormatPolicy_SetSaveFolder_RoundTrips;
var
  S: TPluginSettings;
  P: ISaveFormatPolicy;
begin
  S := TPluginSettings.Create('');
  try
    P := S;
    P.SetSaveFolder('D:\frames');
    Assert.AreEqual('D:\frames', S.SaveFolder,
      'SetSaveFolder writes through to the underlying property');
    Assert.AreEqual('D:\frames', P.GetSaveFolder,
      'And the getter reads the same value back');
  finally
    S.Free;
  end;
end;

procedure TTestSettingsInterfaces.SaveFormatPolicy_SetSaveAtLiveResolution_RoundTrips;
var
  S: TPluginSettings;
  P: ISaveFormatPolicy;
begin
  S := TPluginSettings.Create('');
  try
    P := S;
    P.SetSaveAtLiveResolution(True);
    Assert.IsTrue(S.SaveAtLiveResolution, 'Setter writes through');
    P.SetSaveAtLiveResolution(False);
    Assert.IsFalse(S.SaveAtLiveResolution, 'Setter writes False as well');
  finally
    S.Free;
  end;
end;

procedure TTestSettingsInterfaces.NoRefCount_InterfaceRefRelease_DoesNotFreeInstance;
var
  S: TPluginSettings;
  P: IRenderColorPolicy;
  CallSurvives: Boolean;
begin
  {The dangerous regression: TPluginSettings derives from TNoRefCountObject
   so an interface reference going out of scope must NOT free the
   instance (the WLX form owns its lifetime manually). If the wrong
   base class were chosen the assert below would never run — the
   instance would have been freed under our feet.}
  S := TPluginSettings.Create('');
  try
    P := S;
    S.SaveFolder := 'check';
    P := nil; {Drops the only interface reference.}
    {Now read through the class ref. If the interface release had freed
     the instance, this would access freed memory and typically crash
     or return garbage.}
    CallSurvives := S.SaveFolder = 'check';
    Assert.IsTrue(CallSurvives,
      'Interface release must not free the instance (TNoRefCountObject contract)');
  finally
    S.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSettingsInterfaces);

end.
