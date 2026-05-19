{Clipboard publish leaves: takes a finalised TBitmap and pushes it to
 the system clipboard either as CF_HDROP (file-reference; the bitmap is
 first encoded to a temp PNG and the path is published) or as the
 strategy-array of in-memory formats configured under
 FSettings.ClipboardFormats (CF_DIBV5 + CF_PNG + CF_DIB + CF_BITMAP by
 default).

 Extracted from TFrameExporter so the clipboard plumbing (modal runner,
 per-format strategy assembly, temp-file bookkeeping) lives apart from
 the render pipeline and the save-to-file paths. The publisher owns the
 "last temp file we published" handle so successive CF_HDROP copies can
 delete the previous artefact without dragging that bookkeeping back
 into the facade.

 Lifetime: the host-form callback (TAsyncTaskRunner) must remain valid
 for the duration of any Publish* call. The publisher does not own the
 callback; the caller wires it via the OnAsyncTaskRun property.}
unit uClipboardPublisher;

interface

uses
  System.Classes,
  Vcl.Graphics,
  uSettings, uBitmapWorkThread;

type
  {Outcome of a clipboard publish. The distinction matters for the
   call-site UI: cprFailed should surface a MessageDlg, cprCancelled
   should be silent (user's explicit choice), cprSuccess is the happy
   path.}
  TClipboardPublishResult = (cprSuccess, cprFailed, cprCancelled);

  {Runs AThread to completion inside a host-supplied modal "please wait"
   dialog. AText is the status message. Returns True when the thread
   completed normally; False when the user cancelled.}
  TAsyncTaskRunner = reference to function(AThread: TThread;
    const AText: string): Boolean;

{Runs AWork inside a TBitmapWorkThread, optionally hosted by ARunner
 (the host's modal "please wait" dialog). Returns a tri-state result:
 cprSuccess when the work succeeded, cprFailed when the work reported
 failure (or nil bitmap), cprCancelled when ARunner reported a user
 cancellation. AOutcome is populated with the worker's Outcome on the
 success/failed paths so the caller can log ErrorMsg or read other
 result fields; on cancel the outcome is left at default.

 OWNERSHIP: takes ABitmap unconditionally (var, sets to nil on entry).
 The thread frees it.

 On cancel the thread is detached (RequestCancel + the DLL pin) and the
 main thread does not wait for it; see TBitmapWorkThread.RequestCancel
 for the rationale. Callers MUST treat the returned cprCancelled as
 "thread is gone, results unreliable, do not inspect further".

 Pass ARunner=nil for synchronous, no-UI execution (tests / standalone).
 The function then runs the thread on the main thread via Start+WaitFor
 and treats the run as a success - cancellation is not possible in this
 mode by construction.}
function RunBitmapWorkInModal(var ABitmap: Vcl.Graphics.TBitmap;
  const AStatusText: string;
  const AWork: TBitmapWorkProc;
  const APostWork: TBitmapWorkPostProc;
  const ARunner: TAsyncTaskRunner;
  out AOutcome: TBitmapWorkOutcome): TClipboardPublishResult;

{Composes the user-facing message dialog text shown when
 PublishBitmapToClipboardAsImage returns cprFailed. AFailedFormat is the
 strategy name supplied by CopyBitmapToClipboard (empty when failure was
 not a per-strategy allocation, e.g. clipboard-open exhausted retries).
 AIsCombinedView changes the remedy guidance: combined-view callers can
 also lower the Scale target / reduce frame count, single-frame callers
 cannot. Exposed in the interface section so tests can pin the message
 text without needing the full WLX form harness.}
function BuildClipboardCopyFailureMessage(const AFailedFormat: string;
  AIsCombinedView: Boolean): string;

type
  {Publishes a bitmap to the system clipboard via two complementary
   paths (CF_HDROP file reference + in-memory format strategies).}
  TClipboardPublisher = class
  strict private
    FSettings: TPluginSettings;
    FOnAsyncTaskRun: TAsyncTaskRunner;
    {Path of the temp PNG we most recently wrote for the CF_HDROP
     "paste as file reference" toggle, or '' when nothing has been
     written this session. Tracked so the next copy can delete the
     previous file (at most one Glimpse clipboard temp exists at a
     time). NOT deleted on destructor: closing the Lister must not
     invalidate a CF_HDROP entry the user has not pasted yet - the
     system's %TEMP% cleanup catches the file later.}
    FLastClipboardTempFile: string;
  public
    constructor Create(ASettings: TPluginSettings);
    {Saves ABitmap to a fresh %TEMP%\glimpse_clip_*.png and publishes
     its path as CF_HDROP. Deletes the previous temp file if any.

     OWNERSHIP: takes ABitmap unconditionally. The parameter is a var
     ref so the function sets it to nil on entry; callers must NOT
     touch ABitmap after this call (a trailing ABitmap.Free is safe -
     Free on nil is a no-op).

     Returns cprSuccess on the happy path, cprCancelled when the user
     dismissed the modal progress dialog (silent - clipboard unchanged
     but no error to surface), cprFailed on bitmap save / clipboard
     publish failure (caller should MessageDlg).}
    function PublishAsFileReference(var ABitmap: TBitmap): TClipboardPublishResult;
    {Sibling of PublishAsFileReference for the in-memory clipboard
     path. Builds the per-format strategy array from
     FSettings.ClipboardFormats and feeds it to
     uClipboardImage.CopyBitmapToClipboard. Runs inside the same modal
     progress dialog so the lister stays responsive while large HGLOBAL
     buffers are being allocated and populated. Same ownership contract:
     takes ABitmap unconditionally, sets it to nil on entry. Same
     tri-state result. On cprFailed AErrorMsg names the failing strategy
     (when allocation failed) or is empty when the failure was at the
     clipboard-open stage; callers compose a richer MessageDlg from it.}
    function PublishAsImage(var ABitmap: TBitmap;
      ABackground: TColor; out AErrorMsg: string): TClipboardPublishResult;
    {Optional host-form hook that runs a worker thread inside a modal
     progress dialog. Wire to uProgressModalForm.RunWithProgress. Leave
     nil to fall back to synchronous, no-UI execution (tests / standalone).}
    property OnAsyncTaskRun: TAsyncTaskRunner read FOnAsyncTaskRun write FOnAsyncTaskRun;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.UITypes,
  uClipboardImage, uClipboardFileDrop, uClipboardFormatStrategies,
  uSettingsGroups, uDefaults, uBitmapSaver, uDebugLog;

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
    {Failure was at the clipboard-open stage (system clipboard locked by
     another process); format name does not apply.}
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
var
  TakenBmp: TBitmap;
  Thread: TBitmapWorkThread;
  TaskOk: Boolean;
begin
  Result := cprFailed;
  AOutcome := Default(TBitmapWorkOutcome);
  {Take ownership of the caller's bitmap up front. The local TakenBmp
   becomes the thread's bitmap; the caller's ABitmap is set to nil so
   any trailing try-finally Bmp.Free on the call site is a safe no-op
   regardless of outcome.}
  TakenBmp := ABitmap;
  ABitmap := nil;
  if TakenBmp = nil then
    Exit;

  Thread := TBitmapWorkThread.Create(TakenBmp, AWork, APostWork);
  try
    if Assigned(ARunner) then
      TaskOk := ARunner(Thread, AStatusText)
    else
    begin
      {Synchronous fallback for tests / standalone where no host modal
       is available. Cannot be cancelled in this mode.}
      Thread.Start;
      Thread.WaitFor;
      TaskOk := True;
    end;

    if not TaskOk then
    begin
      {User cancelled. RequestCancel pins the DLL and detaches via
       FreeOnTerminate; the thread runs to completion in the background
       and self-frees safely even if TC unloads the plugin a moment
       later. Null the local reference so the finally block does not
       double-free.}
      Thread.RequestCancel;
      Thread := nil;
      Exit(cprCancelled);
    end;

    AOutcome := Thread.Outcome;
    if AOutcome.Success then
      Result := cprSuccess
    else
      Result := cprFailed;
  finally
    if Assigned(Thread) then
      Thread.Free;
  end;
end;

{ TClipboardPublisher }

constructor TClipboardPublisher.Create(ASettings: TPluginSettings);
begin
  inherited Create;
  FSettings := ASettings;
end;

function TClipboardPublisher.PublishAsFileReference(var ABitmap: TBitmap): TClipboardPublishResult;
var
  NewPath, OldPath: string;
  Outcome: TBitmapWorkOutcome;
  WorkResult: TClipboardPublishResult;
begin
  {Fresh GUID-based name per call so concurrent TC lister windows do
   not collide on a single fixed filename. The previous file (if any)
   is deleted after the new one is successfully published, so at most
   one Glimpse clipboard temp lives in %TEMP% at a time.}
  NewPath := IncludeTrailingPathDelimiter(System.IOUtils.TPath.GetTempPath) +
    'glimpse_clip_' + TGuid.NewGuid.ToString + '.png';

  WorkResult := RunBitmapWorkInModal(ABitmap, 'Writing clipboard image...',
    procedure(ABmp: TBitmap; var AOut: TBitmapWorkOutcome)
    begin
      SaveBitmapToFile(ABmp, NewPath, sfPNG, DEF_JPEG_QUALITY, DEF_PNG_COMPRESSION);
      AOut.Success := True;
    end,
    procedure(const AOut: TBitmapWorkOutcome; ACancelled: Boolean)
    begin
      {User cancelled while we were encoding. The file is on disk but
       nobody will ever paste it - delete now so the temp folder stays
       tidy. SysUtils.DeleteFile silently no-ops if something else
       already removed the file.}
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

  {Work succeeded - now publish the on-disk file as CF_HDROP. Reset
   Result to cprFailed; the success path below promotes it back to
   cprSuccess only after the clipboard publish AND the temp-file
   bookkeeping have both completed.}
  Result := cprFailed;
  if not PutFilePathOnClipboard(NewPath) then
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
  {Capture the settings snapshot by value before crossing into the
   worker thread; the anonymous method below will reference these locals.
   Reading FSettings directly inside the worker would also work today
   (the values are immutable for the duration of the call) but the local
   snapshot makes the lifetime contract explicit.}
  FormatSettings := FSettings.ClipboardFormats;
  PngCompression := FSettings.PngCompression;
  Result := RunBitmapWorkInModal(ABitmap, 'Copying image to clipboard...',
    procedure(ABmp: TBitmap; var AOut: TBitmapWorkOutcome)
    var
      Strategies: TArray<IClipboardFormatStrategy>;
      FailedFormat: string;
    begin
      Strategies := BuildClipboardFormatStrategies(FormatSettings, PngCompression);
      AOut.Success := uClipboardImage.CopyBitmapToClipboard(ABmp, ABackground,
        Strategies, FailedFormat);
      {Carry the failed-format name back to the main thread via the
       existing ErrorMsg channel; empty when success or when failure was
       not a per-strategy allocation (clipboard open exhausted retries).}
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
