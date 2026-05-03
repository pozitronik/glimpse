unit TestSettingsGroups;

{Direct tests for the three shared settings groups (TExtractionSettingsGroup,
 TBannerSettingsGroup, TTimestampSettingsGroup). The groups are exercised
 indirectly by TestSettings / TestWcxSettings round-trips, but those
 round-trips can mask group-level bugs by happening to compose with the
 owning settings class' own defaults. These tests pin the group contract
 directly:

 - Defaults populate every documented field.
 - Save then Load round-trips every field.
 - Load with missing keys preserves the record's current value (the
   "callers reset to defaults first" contract).
 - FontName empty-string fallback keeps the current value rather than
   storing the empty string verbatim. This is subtle: TIniFile.ReadString
   returns the default only when the key is absent, but when the key is
   present with an empty value it returns the empty string -- and the
   group code has an explicit Trim() guard for that case.
 - Numeric fields clamp to documented ranges.}

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestExtractionSettingsGroup = class
  strict private
    FTempDir: string;
    function MakeIniPath(const AName: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure Defaults_PopulatesEveryField;
    [Test] procedure SaveThenLoad_RoundTripsAllFields;
    [Test] procedure Load_MissingKeys_PreservesCurrentValues;
    [Test] procedure Load_FrameCountClamped;
    [Test] procedure Load_SkipEdgesClamped;
  end;

  [TestFixture]
  TTestBannerSettingsGroup = class
  strict private
    FTempDir: string;
    function MakeIniPath(const AName: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure Defaults_PopulatesEveryField;
    [Test] procedure SaveThenLoad_RoundTripsAllFields;
    [Test] procedure Load_MissingKeys_PreservesCurrentValues;
    [Test] procedure Load_EmptyFont_KeepsCurrentValue;
    [Test] procedure Load_WhitespaceFont_KeepsCurrentValue;
    [Test] procedure Load_FontSizeClampedHigh;
    [Test] procedure Load_FontSizeClampedLow;
    [Test] procedure Load_UnknownPosition_KeepsCurrent;
  end;

  [TestFixture]
  TTestTimestampSettingsGroup = class
  strict private
    FTempDir: string;
    function MakeIniPath(const AName: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure Defaults_PopulatesEveryField;
    [Test] procedure SaveThenLoad_RoundTripsAllFields;
    [Test] procedure Load_MissingKeys_PreservesCurrentValues;
    [Test] procedure Load_EmptyFont_KeepsCurrentValue;
    [Test] procedure Load_FontSizeClamped;
    [Test] procedure Load_TextAlphaClamped;
    [Test] procedure Load_UnknownCorner_KeepsCurrent;
    [Test] procedure SaveTo_HonoursShowKeyParameter;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.IniFiles, System.UITypes,
  uTypes, uDefaults, uSettingsGroups;

{TTestExtractionSettingsGroup}

procedure TTestExtractionSettingsGroup.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'VT_GroupsTest_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestExtractionSettingsGroup.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

function TTestExtractionSettingsGroup.MakeIniPath(const AName: string): string;
begin
  Result := TPath.Combine(FTempDir, AName);
end;

procedure TTestExtractionSettingsGroup.Defaults_PopulatesEveryField;
var
  G: TExtractionSettingsGroup;
begin
  G := TExtractionSettingsGroup.Defaults;
  Assert.AreEqual(DEF_FRAMES_COUNT, G.FramesCount);
  Assert.AreEqual(DEF_SKIP_EDGES, G.SkipEdgesPercent);
  Assert.AreEqual(DEF_MAX_WORKERS, G.MaxWorkers);
  Assert.AreEqual(DEF_MAX_THREADS, G.MaxThreads);
  Assert.AreEqual(DEF_USE_BMP_PIPE, G.UseBmpPipe);
  Assert.AreEqual(DEF_HW_ACCEL, G.HwAccel);
  Assert.AreEqual(DEF_USE_KEYFRAMES, G.UseKeyframes);
  Assert.AreEqual(DEF_RESPECT_ANAMORPHIC, G.RespectAnamorphic);
end;

procedure TTestExtractionSettingsGroup.SaveThenLoad_RoundTripsAllFields;
var
  IniPath: string;
  Ini: TIniFile;
  G1, G2: TExtractionSettingsGroup;
begin
  IniPath := MakeIniPath('extraction_rt.ini');
  G1 := TExtractionSettingsGroup.Defaults;
  G1.FramesCount := 12;
  G1.SkipEdgesPercent := 7;
  G1.MaxWorkers := 4;
  G1.MaxThreads := 8;
  G1.UseBmpPipe := not DEF_USE_BMP_PIPE;
  G1.HwAccel := not DEF_HW_ACCEL;
  G1.UseKeyframes := not DEF_USE_KEYFRAMES;
  G1.RespectAnamorphic := not DEF_RESPECT_ANAMORPHIC;

  Ini := TIniFile.Create(IniPath);
  try
    G1.SaveTo(Ini, 'extraction');
  finally
    Ini.Free;
  end;

  G2 := TExtractionSettingsGroup.Defaults;
  Ini := TIniFile.Create(IniPath);
  try
    G2.LoadFrom(Ini, 'extraction');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(G1.FramesCount, G2.FramesCount);
  Assert.AreEqual(G1.SkipEdgesPercent, G2.SkipEdgesPercent);
  Assert.AreEqual(G1.MaxWorkers, G2.MaxWorkers);
  Assert.AreEqual(G1.MaxThreads, G2.MaxThreads);
  Assert.AreEqual(G1.UseBmpPipe, G2.UseBmpPipe);
  Assert.AreEqual(G1.HwAccel, G2.HwAccel);
  Assert.AreEqual(G1.UseKeyframes, G2.UseKeyframes);
  Assert.AreEqual(G1.RespectAnamorphic, G2.RespectAnamorphic);
end;

procedure TTestExtractionSettingsGroup.Load_MissingKeys_PreservesCurrentValues;
var
  IniPath: string;
  Ini: TIniFile;
  G: TExtractionSettingsGroup;
begin
  {Empty section -> every key is absent. The "callers reset to defaults
   first" contract means the record's current values become the
   fallbacks, so an empty INI must leave every field unchanged from its
   pre-load value.}
  IniPath := MakeIniPath('extraction_empty.ini');
  TFile.WriteAllText(IniPath, '');

  G := TExtractionSettingsGroup.Defaults;
  G.FramesCount := 17;
  G.UseBmpPipe := False;

  Ini := TIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'extraction');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(17, G.FramesCount, 'Missing key must keep current value');
  Assert.IsFalse(G.UseBmpPipe, 'Missing bool key must keep current value');
end;

procedure TTestExtractionSettingsGroup.Load_FrameCountClamped;
var
  IniPath: string;
  Ini: TIniFile;
  G: TExtractionSettingsGroup;
begin
  IniPath := MakeIniPath('extraction_clamp_fc.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('extraction', 'FramesCount', 9999);
  finally
    Ini.Free;
  end;

  G := TExtractionSettingsGroup.Defaults;
  Ini := TIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'extraction');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(MAX_FRAMES_COUNT, G.FramesCount);
end;

procedure TTestExtractionSettingsGroup.Load_SkipEdgesClamped;
var
  IniPath: string;
  Ini: TIniFile;
  G: TExtractionSettingsGroup;
begin
  IniPath := MakeIniPath('extraction_clamp_skip.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('extraction', 'SkipEdges', -10);
  finally
    Ini.Free;
  end;

  G := TExtractionSettingsGroup.Defaults;
  Ini := TIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'extraction');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(MIN_SKIP_EDGES, G.SkipEdgesPercent);
end;

{TTestBannerSettingsGroup}

procedure TTestBannerSettingsGroup.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'VT_BannerTest_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestBannerSettingsGroup.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

function TTestBannerSettingsGroup.MakeIniPath(const AName: string): string;
begin
  Result := TPath.Combine(FTempDir, AName);
end;

procedure TTestBannerSettingsGroup.Defaults_PopulatesEveryField;
var
  G: TBannerSettingsGroup;
begin
  G := TBannerSettingsGroup.Defaults;
  Assert.IsFalse(G.Show, 'Show defaults off');
  Assert.AreEqual(DEF_BANNER_BACKGROUND, G.Background);
  Assert.AreEqual(DEF_BANNER_TEXT_COLOR, G.TextColor);
  Assert.AreEqual(DEF_BANNER_FONT_NAME, G.FontName);
  Assert.AreEqual(DEF_BANNER_FONT_SIZE, G.FontSize);
  Assert.AreEqual(DEF_BANNER_FONT_AUTO_SIZE, G.AutoSize);
  Assert.AreEqual(Ord(DEF_BANNER_POSITION), Ord(G.Position));
end;

procedure TTestBannerSettingsGroup.SaveThenLoad_RoundTripsAllFields;
var
  IniPath: string;
  Ini: TIniFile;
  G1, G2: TBannerSettingsGroup;
begin
  IniPath := MakeIniPath('banner_rt.ini');
  G1 := TBannerSettingsGroup.Defaults;
  G1.Show := True;
  G1.Background := TColor($00112233);
  G1.TextColor := TColor($00AABBCC);
  G1.FontName := 'Verdana';
  G1.FontSize := 14;
  G1.AutoSize := False;
  G1.Position := bpBottom;

  Ini := TIniFile.Create(IniPath);
  try
    G1.SaveTo(Ini, 'save');
  finally
    Ini.Free;
  end;

  G2 := TBannerSettingsGroup.Defaults;
  Ini := TIniFile.Create(IniPath);
  try
    G2.LoadFrom(Ini, 'save');
  finally
    Ini.Free;
  end;

  Assert.IsTrue(G2.Show);
  Assert.AreEqual(G1.Background, G2.Background);
  Assert.AreEqual(G1.TextColor, G2.TextColor);
  Assert.AreEqual(G1.FontName, G2.FontName);
  Assert.AreEqual(G1.FontSize, G2.FontSize);
  Assert.IsFalse(G2.AutoSize);
  Assert.AreEqual(Ord(G1.Position), Ord(G2.Position));
end;

procedure TTestBannerSettingsGroup.Load_MissingKeys_PreservesCurrentValues;
var
  IniPath: string;
  Ini: TIniFile;
  G: TBannerSettingsGroup;
begin
  IniPath := MakeIniPath('banner_empty.ini');
  TFile.WriteAllText(IniPath, '');

  G := TBannerSettingsGroup.Defaults;
  G.Show := True;
  G.FontName := 'PreservedFont';
  G.FontSize := 33;

  Ini := TIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'save');
  finally
    Ini.Free;
  end;

  Assert.IsTrue(G.Show);
  Assert.AreEqual('PreservedFont', G.FontName);
  Assert.AreEqual(33, G.FontSize);
end;

procedure TTestBannerSettingsGroup.Load_EmptyFont_KeepsCurrentValue;
var
  IniPath: string;
  Ini: TIniFile;
  G: TBannerSettingsGroup;
begin
  {Subtle TIniFile behaviour: an explicit "BannerFont=" with an empty
   value returns the empty string from ReadString (the default param is
   only used when the key is absent). The group code must catch this
   with a Trim() guard, otherwise the empty string would silently
   replace the current font name.}
  IniPath := MakeIniPath('banner_empty_font.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteString('save', 'BannerFont', '');
  finally
    Ini.Free;
  end;

  G := TBannerSettingsGroup.Defaults;
  G.FontName := 'IncomingFont';

  Ini := TIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'save');
  finally
    Ini.Free;
  end;

  Assert.AreEqual('IncomingFont', G.FontName,
    'Empty BannerFont in INI must not overwrite the current value');
end;

procedure TTestBannerSettingsGroup.Load_WhitespaceFont_KeepsCurrentValue;
var
  IniPath: string;
  Ini: TIniFile;
  G: TBannerSettingsGroup;
begin
  {Same fallback for whitespace-only -- the Trim() guard is the actual
   filter. Pinning this so the dialog cannot accidentally save a
   whitespace name and lose the user's font.}
  IniPath := MakeIniPath('banner_ws_font.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteString('save', 'BannerFont', '   ');
  finally
    Ini.Free;
  end;

  G := TBannerSettingsGroup.Defaults;
  G.FontName := 'IncomingFont';

  Ini := TIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'save');
  finally
    Ini.Free;
  end;

  Assert.AreEqual('IncomingFont', G.FontName);
end;

procedure TTestBannerSettingsGroup.Load_FontSizeClampedHigh;
var
  IniPath: string;
  Ini: TIniFile;
  G: TBannerSettingsGroup;
begin
  IniPath := MakeIniPath('banner_fs_hi.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('save', 'BannerFontSize', 9999);
  finally
    Ini.Free;
  end;

  G := TBannerSettingsGroup.Defaults;
  Ini := TIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'save');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(MAX_BANNER_FONT_SIZE, G.FontSize);
end;

procedure TTestBannerSettingsGroup.Load_FontSizeClampedLow;
var
  IniPath: string;
  Ini: TIniFile;
  G: TBannerSettingsGroup;
begin
  IniPath := MakeIniPath('banner_fs_lo.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('save', 'BannerFontSize', -50);
  finally
    Ini.Free;
  end;

  G := TBannerSettingsGroup.Defaults;
  Ini := TIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'save');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(MIN_BANNER_FONT_SIZE, G.FontSize);
end;

procedure TTestBannerSettingsGroup.Load_UnknownPosition_KeepsCurrent;
var
  IniPath: string;
  Ini: TIniFile;
  G: TBannerSettingsGroup;
begin
  {Unrecognised enum text falls back to the record's current value
   (StrToBannerPosition's contract); pinning that the group respects
   the contract rather than blindly assigning.}
  IniPath := MakeIniPath('banner_pos_unknown.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteString('save', 'BannerPosition', 'sideways');
  finally
    Ini.Free;
  end;

  G := TBannerSettingsGroup.Defaults;
  G.Position := bpBottom;

  Ini := TIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'save');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(Ord(bpBottom), Ord(G.Position));
end;

{TTestTimestampSettingsGroup}

procedure TTestTimestampSettingsGroup.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'VT_TsTest_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestTimestampSettingsGroup.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

function TTestTimestampSettingsGroup.MakeIniPath(const AName: string): string;
begin
  Result := TPath.Combine(FTempDir, AName);
end;

procedure TTestTimestampSettingsGroup.Defaults_PopulatesEveryField;
var
  G: TTimestampSettingsGroup;
begin
  G := TTimestampSettingsGroup.Defaults;
  Assert.IsTrue(G.Show);
  Assert.AreEqual(Ord(DEF_TIMESTAMP_CORNER), Ord(G.Corner));
  Assert.AreEqual(DEF_TIMESTAMP_FONT, G.FontName);
  Assert.AreEqual(DEF_TIMESTAMP_FONT_SIZE, G.FontSize);
  Assert.AreEqual(DEF_TC_BACK_COLOR, G.BackColor);
  Assert.AreEqual(Integer(DEF_TC_BACK_ALPHA), Integer(G.BackAlpha));
  Assert.AreEqual(DEF_TIMESTAMP_TEXT_COLOR, G.TextColor);
  Assert.AreEqual(Integer(DEF_TIMESTAMP_TEXT_ALPHA), Integer(G.TextAlpha));
end;

procedure TTestTimestampSettingsGroup.SaveThenLoad_RoundTripsAllFields;
var
  IniPath: string;
  Ini: TIniFile;
  G1, G2: TTimestampSettingsGroup;
begin
  IniPath := MakeIniPath('ts_rt.ini');
  G1 := TTimestampSettingsGroup.Defaults;
  G1.Show := False;
  G1.Corner := tcTopRight;
  G1.FontName := 'Tahoma';
  G1.FontSize := 11;
  G1.BackColor := TColor($00112233);
  G1.BackAlpha := 90;
  G1.TextColor := TColor($00FFEECC);
  G1.TextAlpha := 200;

  Ini := TIniFile.Create(IniPath);
  try
    G1.SaveTo(Ini, 'view', 'ShowTimecode');
  finally
    Ini.Free;
  end;

  G2 := TTimestampSettingsGroup.Defaults;
  Ini := TIniFile.Create(IniPath);
  try
    G2.LoadFrom(Ini, 'view', 'ShowTimecode');
  finally
    Ini.Free;
  end;

  Assert.IsFalse(G2.Show);
  Assert.AreEqual(Ord(G1.Corner), Ord(G2.Corner));
  Assert.AreEqual(G1.FontName, G2.FontName);
  Assert.AreEqual(G1.FontSize, G2.FontSize);
  Assert.AreEqual(G1.BackColor, G2.BackColor);
  Assert.AreEqual(Integer(G1.BackAlpha), Integer(G2.BackAlpha));
  Assert.AreEqual(G1.TextColor, G2.TextColor);
  Assert.AreEqual(Integer(G1.TextAlpha), Integer(G2.TextAlpha));
end;

procedure TTestTimestampSettingsGroup.Load_MissingKeys_PreservesCurrentValues;
var
  IniPath: string;
  Ini: TIniFile;
  G: TTimestampSettingsGroup;
begin
  IniPath := MakeIniPath('ts_empty.ini');
  TFile.WriteAllText(IniPath, '');

  G := TTimestampSettingsGroup.Defaults;
  G.Show := False;
  G.FontName := 'PreservedFont';
  G.TextAlpha := 17;

  Ini := TIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'view', 'ShowTimecode');
  finally
    Ini.Free;
  end;

  Assert.IsFalse(G.Show);
  Assert.AreEqual('PreservedFont', G.FontName);
  Assert.AreEqual(17, Integer(G.TextAlpha));
end;

procedure TTestTimestampSettingsGroup.Load_EmptyFont_KeepsCurrentValue;
var
  IniPath: string;
  Ini: TIniFile;
  G: TTimestampSettingsGroup;
begin
  IniPath := MakeIniPath('ts_empty_font.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteString('view', 'TimestampFont', '');
  finally
    Ini.Free;
  end;

  G := TTimestampSettingsGroup.Defaults;
  G.FontName := 'IncomingFont';

  Ini := TIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'view', 'ShowTimecode');
  finally
    Ini.Free;
  end;

  Assert.AreEqual('IncomingFont', G.FontName);
end;

procedure TTestTimestampSettingsGroup.Load_FontSizeClamped;
var
  IniPath: string;
  Ini: TIniFile;
  G: TTimestampSettingsGroup;
begin
  IniPath := MakeIniPath('ts_fs.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('view', 'TimestampFontSize', 9999);
  finally
    Ini.Free;
  end;

  G := TTimestampSettingsGroup.Defaults;
  Ini := TIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'view', 'ShowTimecode');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(MAX_TIMESTAMP_FONT_SIZE, G.FontSize);
end;

procedure TTestTimestampSettingsGroup.Load_TextAlphaClamped;
var
  IniPath: string;
  Ini: TIniFile;
  G: TTimestampSettingsGroup;
begin
  IniPath := MakeIniPath('ts_ta.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteInteger('view', 'TimestampTextAlpha', 9999);
  finally
    Ini.Free;
  end;

  G := TTimestampSettingsGroup.Defaults;
  Ini := TIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'view', 'ShowTimecode');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(Integer(MAX_TIMESTAMP_TEXT_ALPHA), Integer(G.TextAlpha));
end;

procedure TTestTimestampSettingsGroup.Load_UnknownCorner_KeepsCurrent;
var
  IniPath: string;
  Ini: TIniFile;
  G: TTimestampSettingsGroup;
begin
  IniPath := MakeIniPath('ts_corner.ini');
  Ini := TIniFile.Create(IniPath);
  try
    Ini.WriteString('view', 'TimestampCorner', 'middle');
  finally
    Ini.Free;
  end;

  G := TTimestampSettingsGroup.Defaults;
  G.Corner := tcTopRight;

  Ini := TIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'view', 'ShowTimecode');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(Ord(tcTopRight), Ord(G.Corner));
end;

procedure TTestTimestampSettingsGroup.SaveTo_HonoursShowKeyParameter;
var
  IniPath: string;
  Ini: TIniFile;
  G: TTimestampSettingsGroup;
  Wcx, Wlx: Boolean;
begin
  {WLX historically writes 'ShowTimecode'; WCX writes 'ShowTimestamp'.
   Pinning that the key-name parameter is honoured so the two plugins'
   INI files do not collide.}
  IniPath := MakeIniPath('ts_showkey.ini');
  G := TTimestampSettingsGroup.Defaults;
  G.Show := True;

  Ini := TIniFile.Create(IniPath);
  try
    G.SaveTo(Ini, 'combined', 'ShowTimestamp');
  finally
    Ini.Free;
  end;

  Ini := TIniFile.Create(IniPath);
  try
    {Read both keys; the WCX one was saved, the WLX one was not.}
    Wcx := Ini.ReadBool('combined', 'ShowTimestamp', False);
    Wlx := Ini.ReadBool('combined', 'ShowTimecode', True);
  finally
    Ini.Free;
  end;
  Assert.IsTrue(Wcx, 'ShowTimestamp must be present after SaveTo with that key');
  Assert.IsTrue(Wlx, 'ShowTimecode must be absent (default returned)');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExtractionSettingsGroup);
  TDUnitX.RegisterTestFixture(TTestBannerSettingsGroup);
  TDUnitX.RegisterTestFixture(TTestTimestampSettingsGroup);

end.
