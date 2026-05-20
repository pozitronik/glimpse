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
   storing the empty string verbatim. This is subtle: TUnicodeIniFile.ReadString
   returns the default only when the key is absent; when the key is
   present with an empty value it returns the empty string, and the
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
    {ToExtractionOptions copies the four boolean fields and stamps the
     caller-supplied MaxSide. The owning export-boundary callers
     (WCX BuildExtractionOptions, WLX TPluginForm extraction kickoff)
     collapsed to one-line delegations; this fixture pins the contract.}
    [Test] procedure ToExtractionOptions_CopiesAllBooleanFields;
    [Test] procedure ToExtractionOptions_StampsCallerSuppliedMaxSide;
    [Test] procedure ToExtractionOptions_DefaultMaxSideIsZero;
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

  [TestFixture]
  TTestFFmpegSettingsGroup = class
  strict private
    FTempDir: string;
    function MakeIniPath(const AName: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure Defaults_PopulatesEveryField;
    [Test] procedure SaveThenLoad_RoundTripsAllFields;
    [Test] procedure Load_MissingMode_FallsBackToAuto;
  end;

  [TestFixture]
  TTestViewSettingsGroup = class
  strict private
    FTempDir: string;
    function MakeIniPath(const AName: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure Defaults_PopulatesEveryField;
    [Test] procedure Defaults_EveryModeZoomDefaultsFitWindow;
    [Test] procedure SaveThenLoad_RoundTripsAllFields;
    [Test] procedure SaveThenLoad_PerModeZoomSurvives;
    [Test] procedure Load_CellGapClampedNonNegative;
    [Test] procedure Load_CombinedBorderClampedNonNegative;
    [Test] procedure Load_MissingKeys_PreservesCurrentValues;
  end;

  [TestFixture]
  TTestSaveSettingsGroup = class
  strict private
    FTempDir: string;
    function MakeIniPath(const AName: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure Defaults_PopulatesEveryField;
    [Test] procedure SaveThenLoad_RoundTripsAllFields;
    [Test] procedure Load_JpegQualityClampedHigh;
    [Test] procedure Load_PngCompressionClampedHigh;
    [Test] procedure Load_FrameSidesClamped;
    [Test] procedure Load_EmptyExtensionList_FallsBackToDefault;
    [Test] procedure Load_CombinedMaxSideClamped;
  end;

  [TestFixture]
  TTestCacheSettingsGroup = class
  strict private
    FTempDir: string;
    function MakeIniPath(const AName: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure Defaults_PopulatesEveryField;
    [Test] procedure SaveThenLoad_RoundTripsAllFields;
    [Test] procedure Load_MaxSizeMBClampedLow;
    [Test] procedure Load_MaxSizeMBClampedHigh;
    [Test] procedure Load_RandomPercentClampedLow;
    [Test] procedure Load_RandomPercentClampedHigh;
  end;

  [TestFixture]
  TTestQuickViewSettingsGroup = class
  strict private
    FTempDir: string;
    function MakeIniPath(const AName: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure Defaults_PopulatesEveryField;
    [Test] procedure SaveThenLoad_RoundTripsAllFields;
    [Test] procedure Load_MissingKeys_PreservesCurrentValues;
  end;

  [TestFixture]
  TTestThumbnailsSettingsGroup = class
  strict private
    FTempDir: string;
    function MakeIniPath(const AName: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure Defaults_PopulatesEveryField;
    [Test] procedure SaveThenLoad_RoundTripsAllFields;
    [Test] procedure Load_PositionClampedHigh;
    [Test] procedure Load_GridFramesClampedHigh;
    [Test] procedure Load_GridFramesClampedLow;
    [Test] procedure Load_UnknownMode_FallsBackToSingle;
  end;

  [TestFixture]
  TTestStatusBarSettingsGroup = class
  strict private
    FTempDir: string;
    function MakeIniPath(const AName: string): string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure Defaults_PopulatesEveryField;
    [Test] procedure SaveThenLoad_RoundTripsAllFields;
    [Test] procedure Load_EmptyTemplate_FallsBackToDefault;
    [Test] procedure Load_EmptyFont_FallsBackToDefault;
    [Test] procedure Load_FontSizeClamped;
    [Test] procedure Load_HeightClamped;
    [Test] procedure Load_UnknownApplyMode_KeepsCurrent;
  end;

  {The settings groups depend on the IIniFile abstraction, so they
   round-trip through any implementation — exercised here with an
   in-memory fake, no file on disk.}
  [TestFixture]
  TTestIniFileSubstitution = class
  public
    [Test] procedure GroupRoundTripsThroughInjectedStore;
    [Test] procedure MissingKeysKeepDefaultsThroughInjectedStore;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.UITypes, System.Generics.Collections,
  BitmapSaver, StatusBarLayout, Types, Defaults, SettingsGroups, UnicodeIniFile,
  IniStore;

type
  {In-memory IIniFile so the settings groups can be exercised through
   the abstraction with no file on disk.}
  TFakeIniFile = class(TInterfacedObject, IIniFile)
  strict private
    FValues: TDictionary<string, string>;
    function Key(const ASection, AIdent: string): string;
  public
    constructor Create;
    destructor Destroy; override;
    function ReadString(const Section, Ident, Default: string): string;
    procedure WriteString(const Section, Ident, Value: string);
    function ReadInteger(const Section, Ident: string; Default: Longint): Longint;
    procedure WriteInteger(const Section, Ident: string; Value: Longint);
    function ReadBool(const Section, Ident: string; Default: Boolean): Boolean;
    procedure WriteBool(const Section, Ident: string; Value: Boolean);
    function ValueExists(const Section, Ident: string): Boolean;
    procedure UpdateFile;
  end;

constructor TFakeIniFile.Create;
begin
  inherited Create;
  FValues := TDictionary<string, string>.Create;
end;

destructor TFakeIniFile.Destroy;
begin
  FValues.Free;
  inherited;
end;

function TFakeIniFile.Key(const ASection, AIdent: string): string;
begin
  Result := ASection + '|' + AIdent;
end;

function TFakeIniFile.ReadString(const Section, Ident, Default: string): string;
begin
  if not FValues.TryGetValue(Key(Section, Ident), Result) then
    Result := Default;
end;

procedure TFakeIniFile.WriteString(const Section, Ident, Value: string);
begin
  FValues.AddOrSetValue(Key(Section, Ident), Value);
end;

function TFakeIniFile.ReadInteger(const Section, Ident: string; Default: Longint): Longint;
begin
  Result := StrToIntDef(ReadString(Section, Ident, ''), Default);
end;

procedure TFakeIniFile.WriteInteger(const Section, Ident: string; Value: Longint);
begin
  WriteString(Section, Ident, IntToStr(Value));
end;

function TFakeIniFile.ReadBool(const Section, Ident: string; Default: Boolean): Boolean;
begin
  Result := ReadInteger(Section, Ident, Ord(Default)) <> 0;
end;

procedure TFakeIniFile.WriteBool(const Section, Ident: string; Value: Boolean);
begin
  WriteInteger(Section, Ident, Ord(Value));
end;

function TFakeIniFile.ValueExists(const Section, Ident: string): Boolean;
begin
  Result := FValues.ContainsKey(Key(Section, Ident));
end;

procedure TFakeIniFile.UpdateFile;
begin
  {In-memory: nothing to flush.}
end;

{TTestIniFileSubstitution}

procedure TTestIniFileSubstitution.GroupRoundTripsThroughInjectedStore;
var
  Store: IIniFile;
  Src, Dst: TExtractionSettingsGroup;
begin
  {The four boolean fields carry no clamping, so a flipped value that
   survives Save->Load proves the data transited the injected store.}
  Store := TFakeIniFile.Create;
  Src := TExtractionSettingsGroup.Defaults;
  Src.UseBmpPipe := not Src.UseBmpPipe;
  Src.HwAccel := not Src.HwAccel;
  Src.UseKeyframes := not Src.UseKeyframes;
  Src.RespectAnamorphic := not Src.RespectAnamorphic;
  Src.SaveTo(Store, 'extraction');

  Dst := TExtractionSettingsGroup.Defaults;
  Dst.LoadFrom(Store, 'extraction');

  Assert.AreEqual(Src.UseBmpPipe, Dst.UseBmpPipe, 'UseBmpPipe must round-trip through the injected store');
  Assert.AreEqual(Src.HwAccel, Dst.HwAccel, 'HwAccel must round-trip');
  Assert.AreEqual(Src.UseKeyframes, Dst.UseKeyframes, 'UseKeyframes must round-trip');
  Assert.AreEqual(Src.RespectAnamorphic, Dst.RespectAnamorphic, 'RespectAnamorphic must round-trip');
end;

procedure TTestIniFileSubstitution.MissingKeysKeepDefaultsThroughInjectedStore;
var
  Store: IIniFile;
  Group: TExtractionSettingsGroup;
begin
  {Empty store: LoadFrom must leave every field at the record's current
   (defaults) value — the "callers reset to defaults first" contract,
   exercised through a non-TUnicodeIniFile store.}
  Store := TFakeIniFile.Create;
  Group := TExtractionSettingsGroup.Defaults;
  Group.LoadFrom(Store, 'extraction');
  Assert.AreEqual(TExtractionSettingsGroup.Defaults.MaxWorkers, Group.MaxWorkers,
    'Missing key must preserve the default MaxWorkers');
  Assert.AreEqual(TExtractionSettingsGroup.Defaults.HwAccel, Group.HwAccel,
    'Missing key must preserve the default HwAccel');
end;

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
  Ini: TUnicodeIniFile;
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

  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G1.SaveTo(Ini, 'extraction');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G2 := TExtractionSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
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
  Ini: TUnicodeIniFile;
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

  Ini := TUnicodeIniFile.Create(IniPath);
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
  Ini: TUnicodeIniFile;
  G: TExtractionSettingsGroup;
begin
  IniPath := MakeIniPath('extraction_clamp_fc.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('extraction', 'FramesCount', 9999);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TExtractionSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'extraction');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(MAX_FRAMES_COUNT, G.FramesCount);
end;

procedure TTestExtractionSettingsGroup.ToExtractionOptions_CopiesAllBooleanFields;
var
  G: TExtractionSettingsGroup;
  Opts: TExtractionOptions;
begin
  G := TExtractionSettingsGroup.Defaults;
  G.UseBmpPipe := True;
  G.HwAccel := False;
  G.UseKeyframes := True;
  G.RespectAnamorphic := False;

  Opts := G.ToExtractionOptions(0);
  Assert.IsTrue(Opts.UseBmpPipe);
  Assert.IsFalse(Opts.HwAccel);
  Assert.IsTrue(Opts.UseKeyframes);
  Assert.IsFalse(Opts.RespectAnamorphic);

  {Flip every flag and re-derive to prove the copy is per-field, not a
   shared template.}
  G.UseBmpPipe := False;
  G.HwAccel := True;
  G.UseKeyframes := False;
  G.RespectAnamorphic := True;
  Opts := G.ToExtractionOptions(0);
  Assert.IsFalse(Opts.UseBmpPipe);
  Assert.IsTrue(Opts.HwAccel);
  Assert.IsFalse(Opts.UseKeyframes);
  Assert.IsTrue(Opts.RespectAnamorphic);
end;

procedure TTestExtractionSettingsGroup.ToExtractionOptions_StampsCallerSuppliedMaxSide;
var
  G: TExtractionSettingsGroup;
begin
  G := TExtractionSettingsGroup.Defaults;
  Assert.AreEqual<Integer>(1280, G.ToExtractionOptions(1280).MaxSide);
  Assert.AreEqual<Integer>(4096, G.ToExtractionOptions(4096).MaxSide);
end;

procedure TTestExtractionSettingsGroup.ToExtractionOptions_DefaultMaxSideIsZero;
var
  G: TExtractionSettingsGroup;
begin
  {The optional-arg default is 0 so combined-mode callers can call
   ToExtractionOptions with no argument and get the "no scale limit"
   contract (the assembled grid is shrunk separately).}
  G := TExtractionSettingsGroup.Defaults;
  Assert.AreEqual<Integer>(0, G.ToExtractionOptions.MaxSide);
end;

procedure TTestExtractionSettingsGroup.Load_SkipEdgesClamped;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TExtractionSettingsGroup;
begin
  IniPath := MakeIniPath('extraction_clamp_skip.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('extraction', 'SkipEdges', -10);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TExtractionSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
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
  Ini: TUnicodeIniFile;
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

  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G1.SaveTo(Ini, 'save');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G2 := TBannerSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
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
  Ini: TUnicodeIniFile;
  G: TBannerSettingsGroup;
begin
  IniPath := MakeIniPath('banner_empty.ini');
  TFile.WriteAllText(IniPath, '');

  G := TBannerSettingsGroup.Defaults;
  G.Show := True;
  G.FontName := 'PreservedFont';
  G.FontSize := 33;

  Ini := TUnicodeIniFile.Create(IniPath);
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
  Ini: TUnicodeIniFile;
  G: TBannerSettingsGroup;
begin
  {Subtle TUnicodeIniFile behaviour: an explicit "BannerFont=" with an empty
   value returns the empty string from ReadString (the default param is
   only used when the key is absent). The group code must catch this
   with a Trim() guard, otherwise the empty string would silently
   replace the current font name.}
  IniPath := MakeIniPath('banner_empty_font.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteString('save', 'BannerFont', '');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TBannerSettingsGroup.Defaults;
  G.FontName := 'IncomingFont';

  Ini := TUnicodeIniFile.Create(IniPath);
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
  Ini: TUnicodeIniFile;
  G: TBannerSettingsGroup;
begin
  {Same fallback for whitespace-only — the Trim() guard is the
   actual filter. Pinning this so the dialog cannot accidentally
   save a whitespace name and lose the user's font.}
  IniPath := MakeIniPath('banner_ws_font.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteString('save', 'BannerFont', '   ');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TBannerSettingsGroup.Defaults;
  G.FontName := 'IncomingFont';

  Ini := TUnicodeIniFile.Create(IniPath);
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
  Ini: TUnicodeIniFile;
  G: TBannerSettingsGroup;
begin
  IniPath := MakeIniPath('banner_fs_hi.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('save', 'BannerFontSize', 9999);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TBannerSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
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
  Ini: TUnicodeIniFile;
  G: TBannerSettingsGroup;
begin
  IniPath := MakeIniPath('banner_fs_lo.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('save', 'BannerFontSize', -50);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TBannerSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
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
  Ini: TUnicodeIniFile;
  G: TBannerSettingsGroup;
begin
  {Unrecognised enum text falls back to the record's current value
   (StrToBannerPosition's contract); pinning that the group respects
   the contract rather than blindly assigning.}
  IniPath := MakeIniPath('banner_pos_unknown.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteString('save', 'BannerPosition', 'sideways');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TBannerSettingsGroup.Defaults;
  G.Position := bpBottom;

  Ini := TUnicodeIniFile.Create(IniPath);
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
  Ini: TUnicodeIniFile;
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

  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G1.SaveTo(Ini, 'view', 'ShowTimecode');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G2 := TTimestampSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
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
  Ini: TUnicodeIniFile;
  G: TTimestampSettingsGroup;
begin
  IniPath := MakeIniPath('ts_empty.ini');
  TFile.WriteAllText(IniPath, '');

  G := TTimestampSettingsGroup.Defaults;
  G.Show := False;
  G.FontName := 'PreservedFont';
  G.TextAlpha := 17;

  Ini := TUnicodeIniFile.Create(IniPath);
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
  Ini: TUnicodeIniFile;
  G: TTimestampSettingsGroup;
begin
  IniPath := MakeIniPath('ts_empty_font.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteString('view', 'TimestampFont', '');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TTimestampSettingsGroup.Defaults;
  G.FontName := 'IncomingFont';

  Ini := TUnicodeIniFile.Create(IniPath);
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
  Ini: TUnicodeIniFile;
  G: TTimestampSettingsGroup;
begin
  IniPath := MakeIniPath('ts_fs.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('view', 'TimestampFontSize', 9999);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TTimestampSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
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
  Ini: TUnicodeIniFile;
  G: TTimestampSettingsGroup;
begin
  IniPath := MakeIniPath('ts_ta.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('view', 'TimestampTextAlpha', 9999);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TTimestampSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
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
  Ini: TUnicodeIniFile;
  G: TTimestampSettingsGroup;
begin
  IniPath := MakeIniPath('ts_corner.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteString('view', 'TimestampCorner', 'middle');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TTimestampSettingsGroup.Defaults;
  G.Corner := tcTopRight;

  Ini := TUnicodeIniFile.Create(IniPath);
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
  Ini: TUnicodeIniFile;
  G: TTimestampSettingsGroup;
  Wcx, Wlx: Boolean;
begin
  {WLX historically writes 'ShowTimecode'; WCX writes 'ShowTimestamp'.
   Pinning that the key-name parameter is honoured so the two plugins'
   INI files do not collide.}
  IniPath := MakeIniPath('ts_showkey.ini');
  G := TTimestampSettingsGroup.Defaults;
  G.Show := True;

  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.SaveTo(Ini, 'combined', 'ShowTimestamp');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  Ini := TUnicodeIniFile.Create(IniPath);
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

{TTestFFmpegSettingsGroup}

procedure TTestFFmpegSettingsGroup.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'VT_FfmpegTest_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestFFmpegSettingsGroup.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

function TTestFFmpegSettingsGroup.MakeIniPath(const AName: string): string;
begin
  Result := TPath.Combine(FTempDir, AName);
end;

procedure TTestFFmpegSettingsGroup.Defaults_PopulatesEveryField;
var
  G: TFFmpegSettingsGroup;
begin
  G := TFFmpegSettingsGroup.Defaults;
  Assert.AreEqual(Ord(fmAuto), Ord(G.Mode));
  Assert.AreEqual('', G.ExePath);
  Assert.IsFalse(G.AutoDownloaded);
end;

procedure TTestFFmpegSettingsGroup.SaveThenLoad_RoundTripsAllFields;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G1, G2: TFFmpegSettingsGroup;
begin
  IniPath := MakeIniPath('ffmpeg_rt.ini');
  G1 := TFFmpegSettingsGroup.Defaults;
  G1.Mode := fmExe;
  G1.ExePath := 'C:\bin\ffmpeg.exe';
  G1.AutoDownloaded := True;

  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G1.SaveTo(Ini, 'ffmpeg');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G2 := TFFmpegSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G2.LoadFrom(Ini, 'ffmpeg');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(Ord(G1.Mode), Ord(G2.Mode));
  Assert.AreEqual(G1.ExePath, G2.ExePath);
  Assert.AreEqual(G1.AutoDownloaded, G2.AutoDownloaded);
end;

procedure TTestFFmpegSettingsGroup.Load_MissingMode_FallsBackToAuto;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TFFmpegSettingsGroup;
begin
  {The Mode load path uses StrToFFmpegMode(ReadString(...,'')) which falls
   back to fmAuto on empty input — preserving the historical TPluginSettings
   behaviour even if the caller seeded the record with fmExe.}
  IniPath := MakeIniPath('ffmpeg_missing_mode.ini');
  TFile.WriteAllText(IniPath, '');

  G := TFFmpegSettingsGroup.Defaults;
  G.Mode := fmExe;

  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'ffmpeg');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(Ord(fmAuto), Ord(G.Mode),
    'Missing/empty Mode must always resolve to fmAuto regardless of seed');
end;

{TTestViewSettingsGroup}

procedure TTestViewSettingsGroup.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'VT_ViewTest_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestViewSettingsGroup.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

function TTestViewSettingsGroup.MakeIniPath(const AName: string): string;
begin
  Result := TPath.Combine(FTempDir, AName);
end;

procedure TTestViewSettingsGroup.Defaults_PopulatesEveryField;
var
  G: TViewSettingsGroup;
begin
  G := TViewSettingsGroup.Defaults;
  Assert.AreEqual(Ord(vmGrid), Ord(G.Mode));
  Assert.AreEqual(Integer(TColor($001E1E1E)), Integer(G.Background));
  Assert.IsTrue(G.ShowToolbar);
  Assert.IsTrue(G.ShowStatusBar);
  Assert.AreEqual(0, G.CellGap);
  Assert.AreEqual(DEF_COMBINED_BORDER, G.CombinedBorder);
  Assert.AreEqual(Ord(pblAuto), Ord(G.ProgressBarLayout));
end;

procedure TTestViewSettingsGroup.Defaults_EveryModeZoomDefaultsFitWindow;
var
  G: TViewSettingsGroup;
  VM: TViewMode;
begin
  {Every view mode must default to zmFitWindow — the historical
   DEF_ZOOM_MODE. Pinning explicitly so a future enum addition forces an
   update to the defaults loop in TViewSettingsGroup.Defaults.}
  G := TViewSettingsGroup.Defaults;
  for VM := Low(TViewMode) to High(TViewMode) do
    Assert.AreEqual(Ord(zmFitWindow), Ord(G.ModeZoom[VM]),
      Format('ViewMode #%d must default to zmFitWindow', [Ord(VM)]));
end;

procedure TTestViewSettingsGroup.SaveThenLoad_RoundTripsAllFields;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G1, G2: TViewSettingsGroup;
begin
  IniPath := MakeIniPath('view_rt.ini');
  G1 := TViewSettingsGroup.Defaults;
  G1.Mode := vmScroll;
  G1.Background := TColor($00ABCDEF);
  G1.ShowToolbar := False;
  G1.ShowStatusBar := False;
  G1.CellGap := 12;
  G1.CombinedBorder := 5;
  G1.ProgressBarLayout := pblOverPanels;

  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G1.SaveTo(Ini, 'view');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G2 := TViewSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G2.LoadFrom(Ini, 'view');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(Ord(G1.Mode), Ord(G2.Mode));
  Assert.AreEqual(Integer(G1.Background), Integer(G2.Background));
  Assert.IsFalse(G2.ShowToolbar);
  Assert.IsFalse(G2.ShowStatusBar);
  Assert.AreEqual(G1.CellGap, G2.CellGap);
  Assert.AreEqual(G1.CombinedBorder, G2.CombinedBorder);
  Assert.AreEqual(Ord(G1.ProgressBarLayout), Ord(G2.ProgressBarLayout));
end;

procedure TTestViewSettingsGroup.SaveThenLoad_PerModeZoomSurvives;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G1, G2: TViewSettingsGroup;
  VM: TViewMode;
begin
  {The per-mode zoom table is the trickiest part of the view group —
   each mode persists into a sub-section named 'view.<modename>' under
   the key 'ZoomMode'. Mutating every mode to a different zoom and
   round-tripping pins both the section-naming convention and the array
   indexing.}
  IniPath := MakeIniPath('view_modezoom.ini');
  G1 := TViewSettingsGroup.Defaults;
  G1.ModeZoom[vmSmartGrid] := zmActual;
  G1.ModeZoom[vmGrid] := zmFitIfLarger;
  G1.ModeZoom[vmScroll] := zmActual;
  G1.ModeZoom[vmFilmstrip] := zmFitIfLarger;
  G1.ModeZoom[vmSingle] := zmActual;

  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G1.SaveTo(Ini, 'view');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G2 := TViewSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G2.LoadFrom(Ini, 'view');
  finally
    Ini.Free;
  end;

  for VM := Low(TViewMode) to High(TViewMode) do
    Assert.AreEqual(Ord(G1.ModeZoom[VM]), Ord(G2.ModeZoom[VM]),
      Format('ModeZoom must round-trip for ViewMode #%d', [Ord(VM)]));
end;

procedure TTestViewSettingsGroup.Load_CellGapClampedNonNegative;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TViewSettingsGroup;
begin
  IniPath := MakeIniPath('view_cellgap.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('view', 'CellGap', -100);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TViewSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'view');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(MIN_CELL_GAP, G.CellGap);
end;

procedure TTestViewSettingsGroup.Load_CombinedBorderClampedNonNegative;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TViewSettingsGroup;
begin
  IniPath := MakeIniPath('view_border.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('view', 'CombinedBorder', -50);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TViewSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'view');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(MIN_COMBINED_BORDER, G.CombinedBorder);
end;

procedure TTestViewSettingsGroup.Load_MissingKeys_PreservesCurrentValues;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TViewSettingsGroup;
begin
  IniPath := MakeIniPath('view_empty.ini');
  TFile.WriteAllText(IniPath, '');

  G := TViewSettingsGroup.Defaults;
  G.Background := TColor($00FFFFFF);
  G.ShowToolbar := False;
  G.CellGap := 17;

  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'view');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(Integer(TColor($00FFFFFF)), Integer(G.Background));
  Assert.IsFalse(G.ShowToolbar);
  Assert.AreEqual(17, G.CellGap);
end;

{TTestSaveSettingsGroup}

procedure TTestSaveSettingsGroup.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'VT_SaveTest_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestSaveSettingsGroup.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

function TTestSaveSettingsGroup.MakeIniPath(const AName: string): string;
begin
  Result := TPath.Combine(FTempDir, AName);
end;

procedure TTestSaveSettingsGroup.Defaults_PopulatesEveryField;
var
  G: TSaveSettingsGroup;
begin
  G := TSaveSettingsGroup.Defaults;
  Assert.AreEqual(Ord(DEF_SAVE_FORMAT), Ord(G.SaveFormat));
  Assert.AreEqual(DEF_JPEG_QUALITY, G.JpegQuality);
  Assert.AreEqual(DEF_PNG_COMPRESSION, G.PngCompression);
  Assert.AreEqual(Integer(DEF_BACKGROUND_ALPHA), Integer(G.BackgroundAlpha));
  Assert.AreEqual('', G.SaveFolder);
  Assert.AreEqual(DEF_SAVE_AT_LIVE_RESOLUTION, G.SaveAtLiveResolution);
  Assert.AreEqual(DEF_COPY_AT_LIVE_RESOLUTION, G.CopyAtLiveResolution);
  Assert.AreEqual(DEF_CLIPBOARD_AS_FILE_REFERENCE, G.ClipboardAsFileReference);
  Assert.AreEqual(DEF_COMBINED_MAX_SIDE, G.CombinedMaxSide);
  Assert.AreEqual(DEF_SCALED_EXTRACTION, G.ScaledExtraction);
  Assert.AreEqual(DEF_MIN_FRAME_SIDE, G.MinFrameSide);
  Assert.AreEqual(DEF_MAX_FRAME_SIDE, G.MaxFrameSide);
  Assert.AreEqual(DEF_AUTO_REFRESH_VIEWPORT, G.AutoRefreshOnViewportChange);
  Assert.AreEqual(DEF_EXTENSION_LIST, G.ExtensionList);
end;

procedure TTestSaveSettingsGroup.SaveThenLoad_RoundTripsAllFields;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G1, G2: TSaveSettingsGroup;
begin
  IniPath := MakeIniPath('save_rt.ini');
  G1 := TSaveSettingsGroup.Defaults;
  G1.SaveFormat := sfJPEG;
  G1.JpegQuality := 70;
  G1.PngCompression := 4;
  G1.BackgroundAlpha := 100;
  G1.SaveFolder := 'C:\out';
  G1.SaveAtLiveResolution := True;
  G1.CopyAtLiveResolution := True;
  G1.ClipboardAsFileReference := True;
  G1.CombinedMaxSide := 2000;
  G1.ScaledExtraction := True;
  G1.MinFrameSide := 200;
  G1.MaxFrameSide := 1000;
  G1.AutoRefreshOnViewportChange := False;
  G1.ExtensionList := 'mp4,mkv';

  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G1.SaveTo(Ini);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G2 := TSaveSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G2.LoadFrom(Ini);
  finally
    Ini.Free;
  end;

  Assert.AreEqual(Ord(G1.SaveFormat), Ord(G2.SaveFormat));
  Assert.AreEqual(G1.JpegQuality, G2.JpegQuality);
  Assert.AreEqual(G1.PngCompression, G2.PngCompression);
  Assert.AreEqual(Integer(G1.BackgroundAlpha), Integer(G2.BackgroundAlpha));
  Assert.AreEqual(G1.SaveFolder, G2.SaveFolder);
  Assert.IsTrue(G2.SaveAtLiveResolution);
  Assert.IsTrue(G2.CopyAtLiveResolution);
  Assert.IsTrue(G2.ClipboardAsFileReference);
  Assert.AreEqual(G1.CombinedMaxSide, G2.CombinedMaxSide);
  Assert.IsTrue(G2.ScaledExtraction);
  Assert.AreEqual(G1.MinFrameSide, G2.MinFrameSide);
  Assert.AreEqual(G1.MaxFrameSide, G2.MaxFrameSide);
  Assert.IsFalse(G2.AutoRefreshOnViewportChange);
  Assert.AreEqual(G1.ExtensionList, G2.ExtensionList);
end;

procedure TTestSaveSettingsGroup.Load_JpegQualityClampedHigh;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TSaveSettingsGroup;
begin
  IniPath := MakeIniPath('save_jq.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('save', 'JpegQuality', 9999);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TSaveSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini);
  finally
    Ini.Free;
  end;

  Assert.AreEqual(MAX_JPEG_QUALITY, G.JpegQuality);
end;

procedure TTestSaveSettingsGroup.Load_PngCompressionClampedHigh;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TSaveSettingsGroup;
begin
  IniPath := MakeIniPath('save_pc.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('save', 'PngCompression', 100);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TSaveSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini);
  finally
    Ini.Free;
  end;

  Assert.AreEqual(MAX_PNG_COMPRESSION, G.PngCompression);
end;

procedure TTestSaveSettingsGroup.Load_FrameSidesClamped;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TSaveSettingsGroup;
begin
  {Independent of the cross-field Min<=Max invariant (enforced by the
   owning TPluginSettings.Validate, NOT the group). The group's per-field
   clamps still kick in for individually out-of-range values.}
  IniPath := MakeIniPath('save_frame.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('extraction', 'MinFrameSide', 1);
    Ini.WriteInteger('extraction', 'MaxFrameSide', 99999);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TSaveSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini);
  finally
    Ini.Free;
  end;

  Assert.AreEqual(MIN_FRAME_SIDE, G.MinFrameSide);
  Assert.AreEqual(MAX_FRAME_SIDE, G.MaxFrameSide);
end;

procedure TTestSaveSettingsGroup.Load_EmptyExtensionList_FallsBackToDefault;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TSaveSettingsGroup;
begin
  {A cleared ExtensionList would strand the user with no recognised
   files. The group must fall back to DEF_EXTENSION_LIST when the value
   is empty or whitespace.}
  IniPath := MakeIniPath('save_ext.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteString('extensions', 'List', '   ');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TSaveSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini);
  finally
    Ini.Free;
  end;

  Assert.AreEqual(DEF_EXTENSION_LIST, G.ExtensionList);
end;

procedure TTestSaveSettingsGroup.Load_CombinedMaxSideClamped;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TSaveSettingsGroup;
begin
  IniPath := MakeIniPath('save_cm.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('save', 'CombinedMaxSide', 999999);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TSaveSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini);
  finally
    Ini.Free;
  end;

  Assert.AreEqual(MAX_COMBINED_MAX_SIDE, G.CombinedMaxSide);
end;

{TTestCacheSettingsGroup}

procedure TTestCacheSettingsGroup.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'VT_CacheTest_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestCacheSettingsGroup.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

function TTestCacheSettingsGroup.MakeIniPath(const AName: string): string;
begin
  Result := TPath.Combine(FTempDir, AName);
end;

procedure TTestCacheSettingsGroup.Defaults_PopulatesEveryField;
var
  G: TCacheSettingsGroup;
begin
  G := TCacheSettingsGroup.Defaults;
  Assert.IsTrue(G.Enabled);
  Assert.AreEqual('', G.Folder);
  Assert.AreEqual(500, G.MaxSizeMB);
  Assert.AreEqual(DEF_RANDOM_EXTRACTION, G.RandomExtraction);
  Assert.AreEqual(DEF_RANDOM_PERCENT, G.RandomPercent);
  Assert.AreEqual(DEF_CACHE_RANDOM_FRAMES, G.CacheRandomFrames);
end;

procedure TTestCacheSettingsGroup.SaveThenLoad_RoundTripsAllFields;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G1, G2: TCacheSettingsGroup;
begin
  IniPath := MakeIniPath('cache_rt.ini');
  G1 := TCacheSettingsGroup.Defaults;
  G1.Enabled := False;
  G1.Folder := 'C:\cache';
  G1.MaxSizeMB := 1234;
  G1.RandomExtraction := True;
  G1.RandomPercent := 33;
  G1.CacheRandomFrames := True;

  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G1.SaveTo(Ini);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G2 := TCacheSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G2.LoadFrom(Ini);
  finally
    Ini.Free;
  end;

  Assert.IsFalse(G2.Enabled);
  Assert.AreEqual(G1.Folder, G2.Folder);
  Assert.AreEqual(G1.MaxSizeMB, G2.MaxSizeMB);
  Assert.IsTrue(G2.RandomExtraction);
  Assert.AreEqual(G1.RandomPercent, G2.RandomPercent);
  Assert.IsTrue(G2.CacheRandomFrames);
end;

procedure TTestCacheSettingsGroup.Load_MaxSizeMBClampedLow;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TCacheSettingsGroup;
begin
  IniPath := MakeIniPath('cache_mlo.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('cache', 'MaxSizeMB', 1);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TCacheSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini);
  finally
    Ini.Free;
  end;

  Assert.AreEqual(10, G.MaxSizeMB);
end;

procedure TTestCacheSettingsGroup.Load_MaxSizeMBClampedHigh;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TCacheSettingsGroup;
begin
  IniPath := MakeIniPath('cache_mhi.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('cache', 'MaxSizeMB', 100000);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TCacheSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini);
  finally
    Ini.Free;
  end;

  Assert.AreEqual(10000, G.MaxSizeMB);
end;

procedure TTestCacheSettingsGroup.Load_RandomPercentClampedLow;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TCacheSettingsGroup;
begin
  IniPath := MakeIniPath('cache_rplo.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('extraction', 'RandomPercent', -50);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TCacheSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini);
  finally
    Ini.Free;
  end;

  Assert.AreEqual(MIN_RANDOM_PERCENT, G.RandomPercent);
end;

procedure TTestCacheSettingsGroup.Load_RandomPercentClampedHigh;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TCacheSettingsGroup;
begin
  IniPath := MakeIniPath('cache_rphi.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('extraction', 'RandomPercent', 9999);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TCacheSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini);
  finally
    Ini.Free;
  end;

  Assert.AreEqual(MAX_RANDOM_PERCENT, G.RandomPercent);
end;

{TTestQuickViewSettingsGroup}

procedure TTestQuickViewSettingsGroup.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'VT_QvTest_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestQuickViewSettingsGroup.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

function TTestQuickViewSettingsGroup.MakeIniPath(const AName: string): string;
begin
  Result := TPath.Combine(FTempDir, AName);
end;

procedure TTestQuickViewSettingsGroup.Defaults_PopulatesEveryField;
var
  G: TQuickViewSettingsGroup;
begin
  G := TQuickViewSettingsGroup.Defaults;
  Assert.IsTrue(G.DisableNavigation);
  Assert.IsTrue(G.HideToolbar);
  Assert.IsTrue(G.HideStatusBar);
end;

procedure TTestQuickViewSettingsGroup.SaveThenLoad_RoundTripsAllFields;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G1, G2: TQuickViewSettingsGroup;
begin
  IniPath := MakeIniPath('qv_rt.ini');
  G1 := TQuickViewSettingsGroup.Defaults;
  G1.DisableNavigation := False;
  G1.HideToolbar := False;
  G1.HideStatusBar := False;

  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G1.SaveTo(Ini, 'quickview');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G2 := TQuickViewSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G2.LoadFrom(Ini, 'quickview');
  finally
    Ini.Free;
  end;

  Assert.IsFalse(G2.DisableNavigation);
  Assert.IsFalse(G2.HideToolbar);
  Assert.IsFalse(G2.HideStatusBar);
end;

procedure TTestQuickViewSettingsGroup.Load_MissingKeys_PreservesCurrentValues;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TQuickViewSettingsGroup;
begin
  IniPath := MakeIniPath('qv_empty.ini');
  TFile.WriteAllText(IniPath, '');

  G := TQuickViewSettingsGroup.Defaults;
  G.DisableNavigation := False;
  G.HideToolbar := True;

  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'quickview');
  finally
    Ini.Free;
  end;

  Assert.IsFalse(G.DisableNavigation);
  Assert.IsTrue(G.HideToolbar);
end;

{TTestThumbnailsSettingsGroup}

procedure TTestThumbnailsSettingsGroup.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'VT_ThumbTest_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestThumbnailsSettingsGroup.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

function TTestThumbnailsSettingsGroup.MakeIniPath(const AName: string): string;
begin
  Result := TPath.Combine(FTempDir, AName);
end;

procedure TTestThumbnailsSettingsGroup.Defaults_PopulatesEveryField;
var
  G: TThumbnailsSettingsGroup;
begin
  G := TThumbnailsSettingsGroup.Defaults;
  Assert.AreEqual(DEF_THUMBNAILS_ENABLED, G.Enabled);
  Assert.AreEqual(Ord(DEF_THUMBNAIL_MODE), Ord(G.Mode));
  Assert.AreEqual(DEF_THUMBNAIL_POSITION, G.Position);
  Assert.AreEqual(DEF_THUMBNAIL_GRID_FRAMES, G.GridFrames);
end;

procedure TTestThumbnailsSettingsGroup.SaveThenLoad_RoundTripsAllFields;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G1, G2: TThumbnailsSettingsGroup;
begin
  IniPath := MakeIniPath('thumb_rt.ini');
  G1 := TThumbnailsSettingsGroup.Defaults;
  G1.Enabled := False;
  G1.Mode := tnmGrid;
  G1.Position := 25;
  G1.GridFrames := 9;

  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G1.SaveTo(Ini, 'thumbnails');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G2 := TThumbnailsSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G2.LoadFrom(Ini, 'thumbnails');
  finally
    Ini.Free;
  end;

  Assert.IsFalse(G2.Enabled);
  Assert.AreEqual(Ord(tnmGrid), Ord(G2.Mode));
  Assert.AreEqual(25, G2.Position);
  Assert.AreEqual(9, G2.GridFrames);
end;

procedure TTestThumbnailsSettingsGroup.Load_PositionClampedHigh;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TThumbnailsSettingsGroup;
begin
  IniPath := MakeIniPath('thumb_pos.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('thumbnails', 'Position', 999);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TThumbnailsSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'thumbnails');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(MAX_THUMBNAIL_POSITION, G.Position);
end;

procedure TTestThumbnailsSettingsGroup.Load_GridFramesClampedHigh;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TThumbnailsSettingsGroup;
begin
  IniPath := MakeIniPath('thumb_gfhi.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('thumbnails', 'GridFrames', 999);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TThumbnailsSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'thumbnails');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(MAX_THUMBNAIL_GRID_FRAMES, G.GridFrames);
end;

procedure TTestThumbnailsSettingsGroup.Load_GridFramesClampedLow;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TThumbnailsSettingsGroup;
begin
  IniPath := MakeIniPath('thumb_gflo.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('thumbnails', 'GridFrames', 0);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TThumbnailsSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'thumbnails');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(MIN_THUMBNAIL_GRID_FRAMES, G.GridFrames);
end;

procedure TTestThumbnailsSettingsGroup.Load_UnknownMode_FallsBackToSingle;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TThumbnailsSettingsGroup;
begin
  {StrToThumbnailMode returns tnmSingle for anything other than 'grid'
   (one-arg overload, hard-coded fallback). The group must inherit
   that behaviour rather than silently keeping the record's current value.}
  IniPath := MakeIniPath('thumb_mode.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteString('thumbnails', 'Mode', 'garbage');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TThumbnailsSettingsGroup.Defaults;
  G.Mode := tnmGrid;

  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'thumbnails');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(Ord(tnmSingle), Ord(G.Mode));
end;

{TTestStatusBarSettingsGroup}

procedure TTestStatusBarSettingsGroup.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'VT_SbTest_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestStatusBarSettingsGroup.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

function TTestStatusBarSettingsGroup.MakeIniPath(const AName: string): string;
begin
  Result := TPath.Combine(FTempDir, AName);
end;

procedure TTestStatusBarSettingsGroup.Defaults_PopulatesEveryField;
var
  G: TStatusBarSettingsGroup;
begin
  G := TStatusBarSettingsGroup.Defaults;
  Assert.AreEqual(DEF_STATUSBAR_TEMPLATE, G.Template);
  Assert.AreEqual(DEF_STATUSBAR_FONT_NAME, G.FontName);
  Assert.AreEqual(DEF_STATUSBAR_FONT_SIZE, G.FontSize);
  Assert.AreEqual(DEF_STATUSBAR_AUTO_WIDTH_LIVE, G.AutoWidthLive);
  Assert.AreEqual(DEF_STATUSBAR_STRETCH_PANELS, G.StretchPanels);
  Assert.AreEqual(DEF_STATUSBAR_HEIGHT, G.Height);
  Assert.AreEqual(Ord(DEF_STATUSBAR_HEIGHT_APPLY_MODE), Ord(G.HeightApplyMode));
end;

procedure TTestStatusBarSettingsGroup.SaveThenLoad_RoundTripsAllFields;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G1, G2: TStatusBarSettingsGroup;
begin
  IniPath := MakeIniPath('sb_rt.ini');
  G1 := TStatusBarSettingsGroup.Defaults;
  G1.Template := '%resolution%%fps%';
  G1.FontName := 'Segoe UI';
  G1.FontSize := 12;
  G1.AutoWidthLive := False;
  G1.StretchPanels := True;
  G1.Height := 40;
  G1.HeightApplyMode := sbhamQuickView;

  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G1.SaveTo(Ini, 'statusbar');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G2 := TStatusBarSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G2.LoadFrom(Ini, 'statusbar');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(G1.Template, G2.Template);
  Assert.AreEqual(G1.FontName, G2.FontName);
  Assert.AreEqual(G1.FontSize, G2.FontSize);
  Assert.IsFalse(G2.AutoWidthLive);
  Assert.IsTrue(G2.StretchPanels);
  Assert.AreEqual(G1.Height, G2.Height);
  Assert.AreEqual(Ord(G1.HeightApplyMode), Ord(G2.HeightApplyMode));
end;

procedure TTestStatusBarSettingsGroup.Load_EmptyTemplate_FallsBackToDefault;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TStatusBarSettingsGroup;
begin
  {Empty/whitespace template falls back to DEF_STATUSBAR_TEMPLATE rather
   than leaving the bar blank — same safety net as the pre-refactor
   TPluginSettings.Load.}
  IniPath := MakeIniPath('sb_empty_tpl.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteString('statusbar', 'Template', '   ');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TStatusBarSettingsGroup.Defaults;
  G.Template := 'foo';

  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'statusbar');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(DEF_STATUSBAR_TEMPLATE, G.Template);
end;

procedure TTestStatusBarSettingsGroup.Load_EmptyFont_FallsBackToDefault;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TStatusBarSettingsGroup;
begin
  IniPath := MakeIniPath('sb_empty_font.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteString('statusbar', 'FontName', '');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TStatusBarSettingsGroup.Defaults;
  G.FontName := 'CustomFont';

  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'statusbar');
  finally
    Ini.Free;
  end;

  {Unlike the banner/timestamp groups (which keep the record's current
   value), the status bar group falls back to the DEFAULT constant
   because it serves as the bar's permanent label-rendering font.}
  Assert.AreEqual(DEF_STATUSBAR_FONT_NAME, G.FontName);
end;

procedure TTestStatusBarSettingsGroup.Load_FontSizeClamped;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TStatusBarSettingsGroup;
begin
  IniPath := MakeIniPath('sb_fs.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('statusbar', 'FontSize', 9999);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TStatusBarSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'statusbar');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(MAX_STATUSBAR_FONT_SIZE, G.FontSize);
end;

procedure TTestStatusBarSettingsGroup.Load_HeightClamped;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TStatusBarSettingsGroup;
begin
  IniPath := MakeIniPath('sb_h.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteInteger('statusbar', 'Height', 9999);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TStatusBarSettingsGroup.Defaults;
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'statusbar');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(MAX_STATUSBAR_HEIGHT, G.Height);
end;

procedure TTestStatusBarSettingsGroup.Load_UnknownApplyMode_KeepsCurrent;
var
  IniPath: string;
  Ini: TUnicodeIniFile;
  G: TStatusBarSettingsGroup;
begin
  IniPath := MakeIniPath('sb_apply.ini');
  Ini := TUnicodeIniFile.Create(IniPath);
  try
    Ini.WriteString('statusbar', 'HeightApplyMode', 'unrecognised');
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  G := TStatusBarSettingsGroup.Defaults;
  G.HeightApplyMode := sbhamLister;

  Ini := TUnicodeIniFile.Create(IniPath);
  try
    G.LoadFrom(Ini, 'statusbar');
  finally
    Ini.Free;
  end;

  Assert.AreEqual(Ord(sbhamLister), Ord(G.HeightApplyMode));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExtractionSettingsGroup);
  TDUnitX.RegisterTestFixture(TTestBannerSettingsGroup);
  TDUnitX.RegisterTestFixture(TTestTimestampSettingsGroup);
  TDUnitX.RegisterTestFixture(TTestFFmpegSettingsGroup);
  TDUnitX.RegisterTestFixture(TTestViewSettingsGroup);
  TDUnitX.RegisterTestFixture(TTestSaveSettingsGroup);
  TDUnitX.RegisterTestFixture(TTestCacheSettingsGroup);
  TDUnitX.RegisterTestFixture(TTestQuickViewSettingsGroup);
  TDUnitX.RegisterTestFixture(TTestThumbnailsSettingsGroup);
  TDUnitX.RegisterTestFixture(TTestStatusBarSettingsGroup);
  TDUnitX.RegisterTestFixture(TTestIniFileSubstitution);

end.
