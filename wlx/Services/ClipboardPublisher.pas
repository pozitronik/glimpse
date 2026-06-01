{Pushes a finished TBitmap to the system clipboard, either as CF_HDROP
 (PNG to %TEMP%, then publish the path) or as the in-memory format
 strategies configured in IClipboardPolicy.GetClipboardFormats.}
unit ClipboardPublisher;

interface

uses
  System.Classes,
  Vcl.Graphics,
  Settings, SettingsInterfaces, BitmapWorkThread;

type
  {Re-aliased so existing imports of ClipboardPublisher resolve these names.}
  TClipboardPublishResult = BitmapWorkThread.TClipboardPublishResult;
  TAsyncTaskRunner = BitmapWorkThread.TAsyncTaskRunner;

const
  cprSuccess = BitmapWorkThread.cprSuccess;
  cprFailed = BitmapWorkThread.cprFailed;
  cprCancelled = BitmapWorkThread.cprCancelled;

{Delegates to BitmapWorkThread.RunBitmapWorkInModal; kept here so existing
 callers that import ClipboardPublisher do not need import changes.}
function RunBitmapWorkInModal(var ABitmap: Vcl.Graphics.TBitmap;
  const AStatusText: string;
  const AWork: TBitmapWorkProc;
  const APostWork: TBitmapWorkPostProc;
  const ARunner: TAsyncTaskRunner;
  out AOutcome: TBitmapWorkOutcome): TClipboardPublishResult;

{Composes user-facing dialog text for PublishAsImage failures.
 AFailedFormat empty = failure at clipboard-open stage. AIsCombinedView
 changes the remedy guidance (combined view has more knobs to lower).}
function BuildClipboardCopyFailureMessage(const AFailedFormat: string;
  AIsCombinedView: Boolean): string;

type
  TClipboardPublisher = class
  strict private
    FClipboardPolicy: IClipboardPolicy;
    FOnAsyncTaskRun: TAsyncTaskRunner;
    {Tracked so the next CF_HDROP copy can delete the previous file.
     NOT cleared on destruction: closing the Lister must not invalidate
     a CF_HDROP entry the user has not pasted yet — %TEMP% cleanup later.}
    FLastClipboardTempFile: string;
  public
    constructor Create(const AClipboardPolicy: IClipboardPolicy);
    {OWNERSHIP: takes ABitmap unconditionally (var; set to nil on entry).
     Callers MUST NOT touch ABitmap after the call.

     cprCancelled = silent; clipboard unchanged. cprFailed = caller should MessageDlg.}
    function PublishAsFileReference(var ABitmap: TBitmap): TClipboardPublishResult;
    {Same ownership/tri-state contract as PublishAsFileReference. On cprFailed
     AErrorMsg names the failing strategy (empty = clipboard-open stage).}
    function PublishAsImage(var ABitmap: TBitmap;
      ABackground: TColor; out AErrorMsg: string): TClipboardPublishResult;
    {Nil = synchronous no-UI (tests / standalone). Production wires to
     ProgressModalForm.RunWithProgress.}
    property OnAsyncTaskRun: TAsyncTaskRunner read FOnAsyncTaskRun write FOnAsyncTaskRun;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.UITypes,
  ClipboardImage, VclClipboard, ClipboardFileDrop, ClipboardFormatStrategies,
  ClipboardTemp, ClipboardTempResolver,
  SettingsGroups, BitmapSaver, Logging;

function BuildClipboardCopyFailureMessage(const AFailedFormat: string;
  AIsCombinedView: Boolean): string;
const
  REMEDY_COMBINED = 'Disable it on the Clipboard tab in Settings, ' +
    'enable "Copy to clipboard as a file reference", lower the Scale target, ' +
    'or reduce the frame count.';
  REMEDY_FRAME = 'Disable it on the Clipboard tab in Settings, ' +
    'or enable "Copy to clipboard as a file reference".';
var
  Remedy: string;
begin
  if AFailedFormat = '' then
  begin
    {Clipboard-open stage failure (system clipboard locked); no format name.}
    Exit('Clipboard write failed - could not open the system clipboard.' +
      sLineBreak + sLineBreak +
      'Try closing other clipboard-using apps and retry.');
  end;
  if AIsCombinedView then
    Remedy := REMEDY_COMBINED
  else
    Remedy := REMEDY_FRAME;
  Result := Format('Clipboard write failed: could not allocate memory for [%s].' +
    sLineBreak + sLineBreak +
    'The image is too large to copy with this format enabled. ' + Remedy,
    [AFailedFormat]);
end;

function RunBitmapWorkInModal(var ABitmap: Vcl.Graphics.TBitmap;
  const AStatusText: string;
  const AWork: TBitmapWorkProc;
  const APostWork: TBitmapWorkPostProc;
  const ARunner: TAsyncTaskRunner;
  out AOutcome: TBitmapWorkOutcome): TClipboardPublishResult;
begin
  Result := BitmapWorkThread.RunBitmapWorkInModal(ABitmap, AStatusText,
    AWork, APostWork, ARunner, AOutcome);
end;

{ TClipboardPublisher }

constructor TClipboardPublisher.Create(const AClipboardPolicy: IClipboardPolicy);
begin
  inherited Create;
  FClipboardPolicy := AClipboardPolicy;
end;

function TClipboardPublisher.PublishAsFileReference(var ABitmap: TBitmap): TClipboardPublishResult;
var
  NewPath, OldPath: string;
  Outcome: TBitmapWorkOutcome;
  WorkResult: TClipboardPublishResult;
  Fmt: TSaveFormat;
  JpegQuality, PngCompression: Integer;
begin
  {Snapshot the format + quality knobs before crossing into the worker.
   Format selects the encoder (PNG lossless / JPG lossy); quality comes
   from the shared Clipboard-tab JpegQuality / PngCompression — the same
   pair that drives the direct-publish clipboard strategies.}
  Fmt := FClipboardPolicy.GetClipboardFileReferenceFormat;
  JpegQuality := FClipboardPolicy.GetJpegQuality;
  PngCompression := FClipboardPolicy.GetPngCompression;

  {GUID-based name so concurrent TC lister windows do not collide.
   Previous file is deleted on success — at most one Glimpse temp lives at a
   time. The folder is the user-configured temp (env vars expanded, system
   %TEMP% fallback); the prefix is shared with the sweeper and the extension
   follows the chosen format.}
  NewPath := ResolveClipboardTempFolder(FClipboardPolicy.GetClipboardTempFolder) +
    CLIPBOARD_TEMP_PREFIX + TGuid.NewGuid.ToString + SaveFormatExtension(Fmt);

  WorkResult := RunBitmapWorkInModal(ABitmap, 'Writing clipboard image...',
    procedure(ABmp: TBitmap; var AOut: TBitmapWorkOutcome)
    begin
      SaveBitmapToFile(ABmp, NewPath, Fmt, JpegQuality, PngCompression);
      AOut.Success := True;
    end,
    procedure(const AOut: TBitmapWorkOutcome; ACancelled: Boolean)
    begin
      {Encode succeeded but user cancelled — nobody will paste, so delete.}
      if AOut.Success and ACancelled then
        System.SysUtils.DeleteFile(NewPath);
    end,
    FOnAsyncTaskRun,
    Outcome);

  if WorkResult = cprCancelled then
    Exit(cprCancelled);
  if WorkResult = cprFailed then
  begin
    DebugLog('FrameExport',
      Format('PublishAsFileReference: SaveBitmapToFile failed: %s',
        [Outcome.ErrorMsg]));
    Exit(cprFailed);
  end;

  {Reset to cprFailed; promote to cprSuccess only after publish AND
   temp-file bookkeeping both complete.}
  Result := cprFailed;
  if not CreateFileDropClipboard.PutFilePathOnClipboard(NewPath) then
  begin
    System.SysUtils.DeleteFile(NewPath);
    Exit;
  end;
  OldPath := FLastClipboardTempFile;
  FLastClipboardTempFile := NewPath;
  if (OldPath <> '') and (OldPath <> NewPath) then
    System.SysUtils.DeleteFile(OldPath);
  Result := cprSuccess;
end;

function TClipboardPublisher.PublishAsImage(var ABitmap: TBitmap;
  ABackground: TColor; out AErrorMsg: string): TClipboardPublishResult;
var
  Outcome: TBitmapWorkOutcome;
  FormatSettings: TClipboardFormatsGroup;
  PngCompression: Integer;
begin
  AErrorMsg := '';
  {Snapshot settings before crossing into the worker — keeps the lifetime contract explicit.}
  FormatSettings := FClipboardPolicy.GetClipboardFormats;
  PngCompression := FClipboardPolicy.GetPngCompression;
  Result := RunBitmapWorkInModal(ABitmap, 'Copying image to clipboard...',
    procedure(ABmp: TBitmap; var AOut: TBitmapWorkOutcome)
    var
      Strategies: TArray<IClipboardFormatStrategy>;
      FailedFormat: string;
    begin
      Strategies := BuildClipboardFormatStrategies(FormatSettings, PngCompression);
      AOut.Success := ClipboardImage.CopyBitmapToClipboard(ABmp, ABackground,
        Strategies, CreateImageClipboard, FailedFormat);
      {Carry failing-strategy name back to the main thread via ErrorMsg.}
      if not AOut.Success then
        AOut.ErrorMsg := FailedFormat;
    end,
    nil,
    FOnAsyncTaskRun,
    Outcome);
  if Result = cprFailed then
    AErrorMsg := Outcome.ErrorMsg;
end;

end.
