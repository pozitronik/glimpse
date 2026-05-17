{Frame export operations: save to file and copy to clipboard.
 Extracted from TPluginForm to isolate I/O from UI orchestration.}
unit uFrameExport;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Graphics,
  uFrameView, uSettings, uBitmapSaver, uCombinedImage, uFrameOffsets;

type
  {Callback the host injects so the save methods can request a re-extract
   at native resolution AFTER their dialog has been confirmed (instead of
   the dispatch wrapping the entire flow in a re-extract upfront, which
   blocked TC for seconds before the dialog even appeared). The host's
   implementation is expected to set/clear FOverrideFrames around AAction
   so PickSaveBitmap picks up the re-extracted bitmaps. Pass nil to skip
   the re-extract path entirely (the save then uses live cells only).}
  TReExtractAction = reference to procedure(const AIndices: TArray<Integer>; AAction: TProc);

  {Runs AThread to completion inside a host-supplied modal "please wait"
   dialog. AText is the status message. Returns True when the thread
   completed normally; False when the user cancelled.}
  TAsyncTaskRunner = reference to function(AThread: TThread;
    const AText: string): Boolean;

  {Outcome of a clipboard publish via PublishBitmapAsFileReference.
   The distinction matters for the call-site UI: cprFailed should
   surface a MessageDlg, cprCancelled should be silent (user's
   explicit choice), cprSuccess is the happy path.}
  TClipboardPublishResult = (cprSuccess, cprFailed, cprCancelled);

  {Handles save-to-file and copy-to-clipboard for video frames.}
  TFrameExporter = class
  strict private
    FFrameView: TFrameView;
    FSettings: TPluginSettings;
    FBannerInfo: TBannerInfo;
    {Optional save-resolution bitmaps supplied by the caller before a
     save/copy operation, indexed parallel to FFrameView cells. Bitmaps
     are non-owned references (typically owned by TFrameCache). When the
     SaveAtLiveResolution toggle is off, save paths prefer entries from
     this array over the live FFrameView bitmaps; nil entries fall back
     to the live cell. Set length 0 to disable.
     Lifetime: the caller (TPluginForm) sets this before invoking a save
     method and clears it after, so the exporter never owns the memory.}
    FOverrideFrames: TArray<TBitmap>;
    {Path of the temp PNG we most recently wrote for the CF_HDROP
     "paste as file reference" toggle, or '' when nothing has been
     written this session. Tracked so the next copy can delete the
     previous file (at most one Glimpse clipboard temp exists at a
     time). NOT deleted on destructor: closing the Lister must not
     invalidate a CF_HDROP entry the user has not pasted yet — the
     system's %TEMP% cleanup catches the file later.}
    FLastClipboardTempFile: string;
    FOnAsyncTaskRun: TAsyncTaskRunner;
    {Opens the file dialog and returns the chosen path/format. The
     AInitialLiveRes value seeds the dialog: on modern Windows it is the
     starting state of the inline 'Save at view resolution' check button
     (the user can flip it before accept, and the final state is what
     gets persisted via FSettings.SaveAtLiveResolution); on legacy
     Windows the dialog has no checkbox, so the seed becomes the
     authoritative value and is persisted directly.}
    function ShowSaveDialog(const ATitle, ADefaultName: string; AOverwritePrompt: Boolean; AInitialLiveRes: Boolean; out APath: string; out AFormat: TSaveFormat): Boolean;
    {Returns the bitmap that the save/copy paths should consume for cell
     AIndex, honouring FOverrideFrames when set and the toggle is off.}
    function PickSaveBitmap(AIndex: Integer): TBitmap;
    function CollectFramesAndOffsets(out AFrames: TArray<TBitmap>; out AOffsets: TFrameOffsetArray): Integer;
    procedure BuildGridStyle(out AGrid: TCombinedGridStyle);
    procedure BuildTimestampStyle(out ATs: TTimestampStyle);
    function CountLiveGridColumns: Integer;
  protected
    {Render helpers exposed at protected scope so a test subclass can
     exercise them directly. They are pipeline internals; production
     code reaches them only through SaveFrame / SaveView / CopyFrame.}
    {Pulls the panel-inner dimensions and the smart-grid arrangement
     parameters that RenderSmartCombinedFromCells and PredictCombinedSize
     both need. Centralises the FrameView fallback to a 16:9 box and the
     per-mode column policy in a single place so render and predict
     cannot disagree.}
    procedure GetSmartGridParameters(out APanelInnerW, APanelInnerH: Integer; out AAspectRatio: Double);
    procedure ComputeSmartCombinedLayout(AForceLiveRes: Boolean; const AFrames: TArray<TBitmap>; out AOutputW, AOutputH: Integer; out ARowCounts: TArray<Integer>);
    {Resolves cell pixel size and column count for a uniform-grid render
     in either live (panel-pixel) or native (frame-pixel) mode. Used by
     RenderGridCombinedAtLiveResolution, RenderCombinedFromCells (native
     branch) and PredictCombinedSize so a future change to the per-mode
     column rule or to the cell-bitmap fallback applies everywhere.}
    procedure ComputeUniformLayoutInputs(AForceLiveRes: Boolean; out ACols, ACellW, ACellH: Integer);
    function ScaleBitmapLetterbox(ASrc: TBitmap; AW, AH: Integer; ABg: TColor): TBitmap;
    function ScaleBitmapCropToFill(ASrc: TBitmap; AW, AH: Integer): TBitmap;
    function RenderCellAtLiveSize(AIndex: Integer): TBitmap;
    function RenderGridCombinedAtLiveResolution: TBitmap;
    function RenderSmartCombinedFromCells: TBitmap;
    function RenderCombinedFromCells: TBitmap;
    function RenderWithBanner(ABmp: TBitmap): TBitmap;
    {Saves ABitmap to a fresh %TEMP%\glimpse_clip_*.png and publishes
     its path as CF_HDROP. Deletes the previous temp file if any.

     OWNERSHIP: takes ABitmap unconditionally. The parameter is a var
     ref so the function sets it to nil on entry; callers must NOT
     touch ABitmap after this call (a trailing ABitmap.Free is safe —
     Free on nil is a no-op).

     Returns cprSuccess on the happy path, cprCancelled when the user
     dismissed the modal progress dialog (silent — clipboard unchanged
     but no error to surface), cprFailed on bitmap save / clipboard
     publish failure (caller should MessageDlg).}
    function PublishBitmapAsFileReference(var ABitmap: TBitmap): TClipboardPublishResult;
    {Sibling of PublishBitmapAsFileReference for the in-memory clipboard
     path (CF_DIBV5 + CF_DIB for pf32bit, CF_BITMAP for pf24bit via
     uClipboardImage.CopyBitmapToClipboard). Runs inside the same modal
     progress dialog so the lister stays responsive while large
     HGLOBAL buffers are being allocated and populated. Same ownership
     contract: takes ABitmap unconditionally, sets it to nil on entry.
     Same tri-state result.}
    function PublishBitmapToClipboardAsImage(var ABitmap: TBitmap;
      ABackground: TColor): TClipboardPublishResult;
    {Shrinks ABmp in place when FSettings.CombinedMaxSide > 0 and the bitmap's
     longer side exceeds the cap. The original is freed and replaced with a
     downscaled copy. No-op when the cap is 0 (unlimited) or the bitmap
     already fits. Centralises the policy used by SaveView and CopyView.}
    procedure ApplyCombinedSizeCap(var ABmp: TBitmap);
    procedure SaveFramesToDir(const ADir: string; AFormat: TSaveFormat; ASelectedOnly: Boolean; const AFileName: string);
  public
    constructor Create(AFrameView: TFrameView; ASettings: TPluginSettings);
    {Optional host-form hook that runs a worker thread inside a modal
     progress dialog. Wire to uProgressModalForm.RunWithProgress. Leave
     nil to fall back to synchronous, no-UI execution (tests / standalone).}
    property OnAsyncTaskRun: TAsyncTaskRunner read FOnAsyncTaskRun write FOnAsyncTaskRun;
    {Resolves which frame to act on: prefers AContextCellIndex, falls back
     to current frame index, then 0. Returns False if no loaded frame found.}
    function ResolveFrameIndex(AContextCellIndex: Integer; out AIndex: Integer): Boolean;
    {Selection-aware singular-action resolver. Picks the cell that a
     toolbar / hotkey "Save frame" or "Copy frame" should act on.
     Priority:
       1. AContextCellIndex when in range and loaded — used by the
          right-click context menu so the menu acts on the right-clicked
          cell regardless of the current selection.
       2. First selected loaded cell — covers Ctrl+click selecting a
          frame and then triggering Save/Copy via toolbar or hotkey.
          Multi-selection collapses to the first selected: the action is
          singular by design (clipboard holds one image, save dialog is
          one filename), so picking deterministically beats refusing.
       3. CurrentFrameIndex (single-view focus) when loaded.
       4. Cell 0 when loaded.
       5. -1 when nothing usable is loaded — caller must skip the action.
     Distinct from ResolveFrameIndex: that helper preserves legacy
     semantics where -1 simply normalises to CurrentFrameIndex / 0 and
     never consults the selection set. Both coexist; this one drives the
     dispatch policy for Save/Copy frame.}
    function PickActionCell(AContextCellIndex: Integer): Integer;
    {Returns the cell-index list a save / copy action will consume. Used
     by the form's WithReExtract wrapper to scope re-extraction to the
     frames the action actually reads.
     Single — one element if ResolveFrameIndex(AContextCellIndex) succeeds, empty otherwise.
     AllLoaded — every cell whose state is fcsLoaded.
     SelectedOrAll — selected loaded cells if any selection exists, else
     every loaded cell (mirrors the selection-aware semantics of SaveFrames).}
    function BuildSaveIndicesSingle(AContextCellIndex: Integer): TArray<Integer>;
    function BuildSaveIndicesAllLoaded: TArray<Integer>;
    function BuildSaveIndicesSelectedOrAll: TArray<Integer>;
    {Saves a single frame to a user-chosen file. Honours
     SaveAtLiveResolution: native frame size when off, on-screen cell
     size when on (letterbox in vmGrid/Filmstrip/Scroll/Single,
     crop-to-fill in vmSmartGrid).
     AReExtract is invoked after the dialog accepts iff the user chose
     native resolution; the host wraps re-extract via WithReExtract so
     the dialog appears immediately and the re-extract work runs only
     when the user has committed to the save.}
    procedure SaveFrame(const AFileName: string; AContextCellIndex: Integer; AReExtract: TReExtractAction = nil);
    {Saves multiple frames as separate files. Selection-aware: when at
     least one frame is selected only those are written, otherwise every
     loaded frame is written. Per-frame resolution policy mirrors
     SaveFrame. AReExtract gates the post-dialog re-extract the same way
     SaveFrame does.}
    procedure SaveFrames(const AFileName: string; AReExtract: TReExtractAction = nil);
    {Saves a combined image of every loaded cell. AInitialLiveRes seeds
     the file dialog's "Save at view resolution" checkbox on modern
     Windows (the user can flip it before accepting); on legacy Windows,
     where the dialog has no checkbox, the seed is the authoritative
     value and is persisted as the new SaveAtLiveResolution.
     Layout per the live view mode (vmGrid: live columns, vmSmartGrid:
     smart panel-aspect rows, vmFilmstrip: one row, vmScroll: one
     column, vmSingle: degenerates to SaveFrame).
     AReExtract gates the post-dialog re-extract the same way SaveFrame
     does.}
    procedure SaveView(const AFileName: string; AInitialLiveRes: Boolean; AReExtract: TReExtractAction = nil);
    {Copies a single frame to the clipboard. Honours the persisted
     CopyAtLiveResolution: live = render at on-screen cell size and
     publish; native = publish the cell's native bitmap. AReExtract is
     invoked when native resolution is requested AND the live cells
     are not already at native size — so the clipboard receives true
     native pixels rather than the viewport-scaled live cell. Mirrors
     the CopyView pattern.}
    procedure CopyFrame(AContextCellIndex: Integer; AReExtract: TReExtractAction = nil);
    {Copies a combined image of every loaded cell to the clipboard.
     AForceLiveRes overrides FSettings.SaveAtLiveResolution for this call
     only (no persist); set True to copy at panel pixel size, False to
     copy at native frame size. AReExtract gates the pre-copy re-extract:
     when AForceLiveRes is False and AReExtract is supplied, the host
     re-extracts at native resolution before the copy so the clipboard
     receives true native-resolution pixels rather than the
     viewport-scaled live cells.}
    procedure CopyView(AForceLiveRes: Boolean; AReExtract: TReExtractAction = nil);
    {Predicts the pixel dimensions the rendered combined image would have
     for a one-shot resolution choice, before banner attachment and before
     the CombinedMaxSide cap. Mirrors the layout math in
     RenderCombinedFromCells / RenderSmartCombinedFromCells /
     RenderGridCombinedAtLiveResolution; banner height is intentionally
     omitted (it adds a small variable height that is hard to predict
     without setting up a canvas). Returns 0,0 when there are no cells.
     Used by the toolbar dropdown to label the Save view / Copy view
     variants with their predicted output size.}
    procedure PredictCombinedSize(AForceLiveRes: Boolean; out AW, AH: Integer);
    {Predicts the rendered combined-image dimensions and the post-cap
     dimensions for a one-shot resolution choice. ACappedW/H equal AW/H
     when the FSettings.CombinedMaxSide cap does not apply (cap=0 or
     image already fits). Returns False when no frames are loaded yet.}
    function PredictDisplayedSize(AForceLiveRes: Boolean; out AW, AH, ACappedW, ACappedH: Integer): Boolean;
    {Returns the bracketed dimension suffix used on the Save/Copy view
     dropdown menu items, e.g. " [1920x1080]" or
     " [19200x10800 -> 8192x4608]" when CombinedMaxSide caps the output.
     Empty string when no frames are loaded yet.}
    function FormatPredictedSize(AForceLiveRes: Boolean): string;
    procedure UpdateBannerInfo(const AInfo: TBannerInfo);
    {Caller-supplied save-resolution bitmaps. Set before invoking a save
     or copy method when SaveAtLiveResolution is off and the caller has
     re-extracted at native (or capped) resolution; clear immediately
     after. Pass an empty array (or nil) to release. Bitmaps are not
     owned by the exporter.}
    procedure SetOverrideFrames(const AFrames: TArray<TBitmap>);
    procedure ClearOverrideFrames;
  end;

implementation

uses
  Winapi.Windows, Winapi.ShlObj,
  System.Types, System.Math, System.UITypes, System.IOUtils,
  Vcl.Clipbrd, Vcl.Dialogs,
  uClipboardImage, uFrameFileNames, uPathExpand, uTypes,
  uViewModeLayout, uBitmapResize, uPlatformDetect, uDefaults, uDebugLog,
  uProgressModalForm;

type
  {Re-bind TBitmap to the VCL class. Winapi.Windows (pulled in for
   IFileDialogCustomize support) declares its own TBITMAP record alias,
   which would otherwise shadow Vcl.Graphics.TBitmap throughout this
   implementation.}
  TBitmap = Vcl.Graphics.TBitmap;

const
  {Arbitrary control id for the inline 'save at live resolution' check button
   on the modern (Vista+) file save dialog. Must be unique within the dialog;
   1001 is well clear of any control ids the system uses.}
  ID_CHK_LIVE_RES = 1001;
  LIVE_RES_LABEL = 'Save at view resolution';

type
  {Bridges TFileSaveDialog with the Win32 IFileDialogCustomize interface,
   which the Delphi VCL wrapper does not expose. The check button must be
   added before the dialog window is created (DoOnExecute fires just
   before Show), and its final state must be read while the dialog is
   still alive (OnFileOkClick fires inside the modal loop). After the
   dialog closes, TCustomFileDialog clears its internal IFileDialog
   reference, so a query attempt after Execute returns is too late.}
  TLiveResDialogHook = class
  strict private
    FDialog: TCustomFileDialog;
    FInitialState: Boolean;
    FFinalState: Boolean;
    procedure HandleExecute(Sender: TObject);
    procedure HandleFileOkClick(Sender: TObject; var CanClose: Boolean);
  public
    constructor Create(ADialog: TCustomFileDialog; AInitialState: Boolean);
    procedure Attach;
    property FinalState: Boolean read FFinalState;
  end;

constructor TLiveResDialogHook.Create(ADialog: TCustomFileDialog; AInitialState: Boolean);
begin
  inherited Create;
  FDialog := ADialog;
  FInitialState := AInitialState;
  FFinalState := AInitialState; {Preserve current value if the user cancels mid-flight.}
end;

procedure TLiveResDialogHook.Attach;
begin
  FDialog.OnExecute := HandleExecute;
  FDialog.OnFileOkClick := HandleFileOkClick;
end;

procedure TLiveResDialogHook.HandleExecute(Sender: TObject);
var
  Customize: IFileDialogCustomize;
begin
  if Supports(FDialog.Dialog, IFileDialogCustomize, Customize) then
    Customize.AddCheckButton(ID_CHK_LIVE_RES, LIVE_RES_LABEL, FInitialState);
end;

procedure TLiveResDialogHook.HandleFileOkClick(Sender: TObject; var CanClose: Boolean);
var
  Customize: IFileDialogCustomize;
  Checked: BOOL;
begin
  CanClose := True;
  if Supports(FDialog.Dialog, IFileDialogCustomize, Customize) then
  begin
    Checked := False;
    if Succeeded(Customize.GetCheckButtonState(ID_CHK_LIVE_RES, Checked)) then
      FFinalState := Checked;
  end;
end;

{TFrameExporter}

constructor TFrameExporter.Create(AFrameView: TFrameView; ASettings: TPluginSettings);
begin
  inherited Create;
  FFrameView := AFrameView;
  FSettings := ASettings;
end;

type
  {Background encoder for the file-reference clipboard copy path. Owns
   the bitmap from construction; destructor frees it. SaveBitmapToFile
   cannot be interrupted partway, so RequestCancel marks the operation
   as cancelled and arranges deletion of the file Execute will write,
   then lets Execute run to natural completion. Main thread treats
   cancel as "throw away the result" — it never waits for the encode
   to finish.}
  TFileWriteThread = class(TThread, IModalThreadCompletion)
  private
    FBmp: TBitmap;
    FPath: string;
    {Set by RequestCancel on the main thread, checked by Execute on
     the worker thread after the encode completes. Boolean writes are
     atomic on word-aligned storage so no critical section is needed.}
    FCancelled: Boolean;
    {Invoked from the worker thread context at the very end of Execute,
     after SaveBitmapToFile returns and any cancel-driven cleanup. The
     uProgressModalForm RunWithProgress helper wires this to a
     PostMessage that closes the modal dialog; tests and standalone
     callers leave it nil and use Thread.WaitFor instead.}
    FOnComplete: TProc;
    procedure SetCompletionCallback(ACallback: TProc);
    {Non-refcounted IInterface implementation. The thread's lifetime is
     managed explicitly by the caller (Free or FreeOnTerminate), not by
     reference counting on interface variables.}
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  public
    SaveOk: Boolean;
    ErrorMsg: string;
    {Takes ownership of ABmp. Destructor frees it whether or not
     Execute ran.}
    constructor Create(ABmp: TBitmap; const APath: string); reintroduce;
    destructor Destroy; override;
    {Marks the operation cancelled and arranges the thread to self-
     destruct after Execute finishes. After calling, the main thread
     MUST NOT touch the thread reference — it will be freed
     asynchronously.}
    procedure RequestCancel;
  protected
    procedure Execute; override;
  end;

  {Sibling of TFileWriteThread for the in-memory clipboard path: hands
   the bitmap to uClipboardImage.CopyBitmapToClipboard inside the modal
   so the lister doesn't freeze while the (potentially huge) HGLOBAL is
   allocated and populated. CopyBitmapToClipboard is opaque from the
   outside the same way SaveBitmapToFile is, so cancel applies the
   same trade-off: pin the DLL, detach, let the worker finish in the
   background without freezing the close path.}
  TClipboardWriteThread = class(TThread, IModalThreadCompletion)
  private
    FBmp: TBitmap;
    FBackground: TColor;
    FCancelled: Boolean;
    FOnComplete: TProc;
    procedure SetCompletionCallback(ACallback: TProc);
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  public
    Success: Boolean;
    ErrorMsg: string;
    constructor Create(ABmp: TBitmap; ABackground: TColor); reintroduce;
    destructor Destroy; override;
    {Same cancel contract as TFileWriteThread — sets flag, pins DLL,
     sets FreeOnTerminate. Main thread MUST NOT touch the thread
     reference after calling.}
    procedure RequestCancel;
  protected
    procedure Execute; override;
  end;

constructor TFileWriteThread.Create(ABmp: TBitmap; const APath: string);
begin
  inherited Create(True);
  FBmp := ABmp;
  FPath := APath;
end;

destructor TFileWriteThread.Destroy;
begin
  FBmp.Free;
  inherited;
end;

procedure TFileWriteThread.Execute;
begin
  try
    SaveBitmapToFile(FBmp, FPath, sfPNG, DEF_JPEG_QUALITY, DEF_PNG_COMPRESSION);
    SaveOk := True;
    if FCancelled then
      {User cancelled while we were encoding. The file is on disk but
       nobody will ever paste it — delete now so the temp folder stays
       tidy. SysUtils.DeleteFile silently no-ops if something else
       already removed the file.}
      System.SysUtils.DeleteFile(FPath);
  except
    on E: Exception do
    begin
      SaveOk := False;
      ErrorMsg := E.Message;
    end;
  end;
  if Assigned(FOnComplete) then
    {Runs on worker thread. The callback (set by RunWithProgress) is a
     PostMessage to the modal's HWND — PostMessage is thread-safe and
     the message routes back to the main thread's message loop.}
    FOnComplete;
end;

procedure TFileWriteThread.RequestCancel;
var
  ModuleName: array[0..MAX_PATH - 1] of Char;
begin
  {Pin this DLL via an extra LoadLibrary refcount so the worker thread
   can run to completion even if TC unloads the WLX plugin the instant
   the user closes the Lister. Without the pin, TC's FreeLibrary would
   unmap our code while the thread is still executing inside it (in
   SaveBitmapToFile / TPngImage) — instant crash. The pin is never
   released; the OS reclaims the DLL handle on TC exit. One pin per
   cancelled-and-detached thread, only when the user actually cancels,
   so the per-session cost is negligible.}
  GetModuleFileName(HInstance, ModuleName, Length(ModuleName));
  LoadLibrary(ModuleName);
  FCancelled := True;
  {FreeOnTerminate hands the thread's lifetime to the thread itself:
   when Execute returns, TThread.AfterTerminate frees us, our
   destructor frees the owned bitmap. Main thread doesn't wait.}
  FreeOnTerminate := True;
end;

procedure TFileWriteThread.SetCompletionCallback(ACallback: TProc);
begin
  FOnComplete := ACallback;
end;

function TFileWriteThread.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
    Result := S_OK
  else
    Result := E_NOINTERFACE;
end;

function TFileWriteThread._AddRef: Integer;
begin
  {No-op ref counting — TObject convention, matches TInterfacedObject's
   contract for explicitly-managed lifetime objects. Returns -1 to
   signal "ref counting disabled" to debug tools.}
  Result := -1;
end;

function TFileWriteThread._Release: Integer;
begin
  Result := -1;
end;

constructor TClipboardWriteThread.Create(ABmp: TBitmap; ABackground: TColor);
begin
  inherited Create(True);
  FBmp := ABmp;
  FBackground := ABackground;
end;

destructor TClipboardWriteThread.Destroy;
begin
  FBmp.Free;
  inherited;
end;

procedure TClipboardWriteThread.Execute;
begin
  try
    Success := uClipboardImage.CopyBitmapToClipboard(FBmp, FBackground);
  except
    on E: Exception do
    begin
      Success := False;
      ErrorMsg := E.Message;
    end;
  end;
  if Assigned(FOnComplete) then
    FOnComplete;
end;

procedure TClipboardWriteThread.RequestCancel;
var
  ModuleName: array[0..MAX_PATH - 1] of Char;
begin
  {Mirror of TFileWriteThread.RequestCancel — see the long comment
   there for the rationale (DLL pin + detach so closing the lister
   right after cancel doesn't crash on unmapped code).}
  GetModuleFileName(HInstance, ModuleName, Length(ModuleName));
  LoadLibrary(ModuleName);
  FCancelled := True;
  FreeOnTerminate := True;
end;

procedure TClipboardWriteThread.SetCompletionCallback(ACallback: TProc);
begin
  FOnComplete := ACallback;
end;

function TClipboardWriteThread.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
    Result := S_OK
  else
    Result := E_NOINTERFACE;
end;

function TClipboardWriteThread._AddRef: Integer;
begin
  Result := -1;
end;

function TClipboardWriteThread._Release: Integer;
begin
  Result := -1;
end;

function TFrameExporter.PublishBitmapAsFileReference(var ABitmap: TBitmap): TClipboardPublishResult;
var
  NewPath, OldPath: string;
  Thread: TFileWriteThread;
  TakenBmp: TBitmap;
  TaskOk: Boolean;
begin
  Result := cprFailed;
  {Take ownership of the caller's bitmap up front. The local TakenBmp
   becomes the thread's bitmap; the caller's ABitmap is set to nil so
   any trailing try-finally Bmp.Free is a safe no-op regardless of
   outcome (success, error, cancellation).}
  TakenBmp := ABitmap;
  ABitmap := nil;
  if TakenBmp = nil then
    Exit;

  {Fresh GUID-based name per call so concurrent TC lister windows
   don't collide on a single fixed filename. The previous file (if
   any) is deleted after the new one is successfully published, so
   at most one Glimpse clipboard temp lives in %TEMP% at a time.}
  NewPath := IncludeTrailingPathDelimiter(System.IOUtils.TPath.GetTempPath) +
    'glimpse_clip_' + TGuid.NewGuid.ToString + '.png';
  Thread := TFileWriteThread.Create(TakenBmp, NewPath);
  try
    if Assigned(FOnAsyncTaskRun) then
      TaskOk := FOnAsyncTaskRun(Thread, 'Writing clipboard image...')
    else
    begin
      {No host-form UI available (tests / standalone). Run synchronously
       on the main thread — no feedback but functionally correct.}
      Thread.Start;
      Thread.WaitFor;
      TaskOk := True;
    end;

    if not TaskOk then
    begin
      {User cancelled. RequestCancel pins the DLL and sets
       FreeOnTerminate, so the thread runs to completion in the
       background and self-frees safely even if TC unloads the
       plugin a moment later. Null the local reference so the
       finally block doesn't double-free.}
      Thread.RequestCancel;
      Thread := nil;
      Exit(cprCancelled);
    end;

    if not Thread.SaveOk then
    begin
      DebugLog('FrameExport',
        Format('PublishBitmapAsFileReference: SaveBitmapToFile failed: %s',
          [Thread.ErrorMsg]));
      Exit;
    end;

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
  finally
    if Assigned(Thread) then
      Thread.Free;
  end;
end;

function TFrameExporter.PublishBitmapToClipboardAsImage(var ABitmap: TBitmap;
  ABackground: TColor): TClipboardPublishResult;
var
  TakenBmp: TBitmap;
  Thread: TClipboardWriteThread;
  TaskOk: Boolean;
begin
  Result := cprFailed;
  {Same ownership-transfer + tri-state pattern as
   PublishBitmapAsFileReference (see that function for the rationale).
   The in-memory clipboard write happens off-thread inside the modal
   progress dialog so the lister doesn't freeze while CF_DIBV5 +
   CF_DIB HGLOBALs (each up to hundreds of MB for a 4K combined
   image) are being allocated and populated.}
  TakenBmp := ABitmap;
  ABitmap := nil;
  if TakenBmp = nil then
    Exit;

  Thread := TClipboardWriteThread.Create(TakenBmp, ABackground);
  try
    if Assigned(FOnAsyncTaskRun) then
      TaskOk := FOnAsyncTaskRun(Thread, 'Copying image to clipboard...')
    else
    begin
      Thread.Start;
      Thread.WaitFor;
      TaskOk := True;
    end;

    if not TaskOk then
    begin
      Thread.RequestCancel;
      Thread := nil;
      Exit(cprCancelled);
    end;

    if not Thread.Success then
      Exit;
    Result := cprSuccess;
  finally
    if Assigned(Thread) then
      Thread.Free;
  end;
end;

function TFrameExporter.ResolveFrameIndex(AContextCellIndex: Integer; out AIndex: Integer): Boolean;
begin
  Result := False;
  if FFrameView.CellCount = 0 then
    Exit;
  {Prefer the right-clicked cell, fall back to current frame, then index 0}
  AIndex := AContextCellIndex;
  if (AIndex < 0) or (AIndex >= FFrameView.CellCount) then
    AIndex := FFrameView.CurrentFrameIndex;
  if (AIndex < 0) or (AIndex >= FFrameView.CellCount) then
    AIndex := 0;
  Result := FFrameView.CellState(AIndex) = fcsLoaded;
end;

function TFrameExporter.PickActionCell(AContextCellIndex: Integer): Integer;
var
  I: Integer;
begin
  {Priority order, "selection-first":

     1. First selected loaded cell — selection is a longer-lived, more
        deliberate gesture than a right-click and so wins even when the
        right-click happened on a different cell. Matches TC's own
        context-menu rule (right-clicking anywhere acts on the selection
        when one exists).
     2. Explicit context (right-click) — only consulted when no
        selection exists. Lets a no-selection user click any cell and
        get that one operated on.
     3. Single-view focused frame — there is exactly one visible frame
        and it is the natural target.
     4. Cell 0 — last-ditch fallback so the action does something
        rather than silently no-op when the user has neither selected
        nor pointed at anything.
     5. -1 when nothing is loaded; the caller must skip the action.}

  {1. First selected loaded cell.}
  for I := 0 to FFrameView.CellCount - 1 do
    if FFrameView.CellSelected(I) and (FFrameView.CellState(I) = fcsLoaded) then
      Exit(I);

  {2. Explicit context (right-click) when it points to a loaded cell.}
  if (AContextCellIndex >= 0) and (AContextCellIndex < FFrameView.CellCount) and (FFrameView.CellState(AContextCellIndex) = fcsLoaded) then
    Exit(AContextCellIndex);

  {3. Single-view focused frame.}
  if (FFrameView.ViewMode = vmSingle) and (FFrameView.CurrentFrameIndex >= 0) and (FFrameView.CurrentFrameIndex < FFrameView.CellCount) and
    (FFrameView.CellState(FFrameView.CurrentFrameIndex) = fcsLoaded) then
    Exit(FFrameView.CurrentFrameIndex);

  {4. Cell 0.}
  if (FFrameView.CellCount > 0) and (FFrameView.CellState(0) = fcsLoaded) then
    Exit(0);

  {5. Nothing loaded — caller must skip the action.}
  Result := -1;
end;

function TFrameExporter.BuildSaveIndicesSingle(AContextCellIndex: Integer): TArray<Integer>;
var
  Idx: Integer;
begin
  if ResolveFrameIndex(AContextCellIndex, Idx) then
    Result := TArray<Integer>.Create(Idx)
  else
    SetLength(Result, 0);
end;

function TFrameExporter.BuildSaveIndicesAllLoaded: TArray<Integer>;
var
  I: Integer;
begin
  SetLength(Result, 0);
  for I := 0 to FFrameView.CellCount - 1 do
    if FFrameView.CellState(I) = fcsLoaded then
      Result := Result + [I];
end;

function TFrameExporter.BuildSaveIndicesSelectedOrAll: TArray<Integer>;
var
  I: Integer;
  SelectedOnly: Boolean;
begin
  SetLength(Result, 0);
  SelectedOnly := FFrameView.SelectedCount > 0;
  for I := 0 to FFrameView.CellCount - 1 do
    if (FFrameView.CellState(I) = fcsLoaded) and ((not SelectedOnly) or FFrameView.CellSelected(I)) then
      Result := Result + [I];
end;

{Picks which bitmap to feed into the save/copy renderers for cell AIndex.
 With FOverrideFrames set and the live-resolution toggle off, prefers the
 override entry (typically a cache-owned save-resolution bitmap); a nil
 override entry falls back to the live cell so partial coverage degrades
 gracefully. With the toggle on, always uses the live cell since the
 toggle's contract is to mirror what is on screen.}
function TFrameExporter.PickSaveBitmap(AIndex: Integer): TBitmap;
begin
  Result := nil;
  if (not FSettings.SaveAtLiveResolution) and (AIndex >= 0) and (AIndex < Length(FOverrideFrames)) and (FOverrideFrames[AIndex] <> nil) then
    Exit(FOverrideFrames[AIndex]);
  if (AIndex >= 0) and (AIndex < FFrameView.CellCount) and (FFrameView.CellState(AIndex) = fcsLoaded) then
    Result := FFrameView.CellBitmap(AIndex);
end;

procedure TFrameExporter.SetOverrideFrames(const AFrames: TArray<TBitmap>);
begin
  FOverrideFrames := AFrames;
end;

procedure TFrameExporter.ClearOverrideFrames;
begin
  SetLength(FOverrideFrames, 0);
end;

{Builds the frames + offsets arrays for the renderer.
 Frame source is PickSaveBitmap so override entries (when set) take
 precedence over the live cells. Offsets always come from the live view.
 nil entries for placeholder/error/missing cells are passed through; the
 renderer skips them.}
function TFrameExporter.CollectFramesAndOffsets(out AFrames: TArray<TBitmap>; out AOffsets: TFrameOffsetArray): Integer;
var
  I: Integer;
begin
  Result := FFrameView.CellCount;
  SetLength(AFrames, Result);
  SetLength(AOffsets, Result);
  for I := 0 to Result - 1 do
  begin
    AFrames[I] := PickSaveBitmap(I);
    AOffsets[I].TimeOffset := FFrameView.CellTimeOffset(I);
  end;
end;

procedure TFrameExporter.BuildGridStyle(out AGrid: TCombinedGridStyle);
begin
  AGrid.Columns := 0; {auto columns (= ceil(sqrt(N))) by default; callers override when needed}
  AGrid.CellGap := FSettings.CellGap;
  AGrid.Border := FSettings.CombinedBorder;
  AGrid.Background := FSettings.Background;
  AGrid.BackgroundAlpha := FSettings.BackgroundAlpha;
end;

procedure TFrameExporter.BuildTimestampStyle(out ATs: TTimestampStyle);
begin
  ATs.Show := FFrameView.ShowTimecode;
  ATs.Corner := FSettings.TimestampCorner;
  ATs.FontName := FSettings.TimestampFontName;
  ATs.FontSize := FSettings.TimestampFontSize;
  ATs.FontStyles := []; {Match the WLX live view; WCX uses [fsBold]}
  ATs.BackColor := FSettings.TimecodeBackColor;
  ATs.BackAlpha := FSettings.TimecodeBackAlpha;
  ATs.TextColor := FSettings.TimestampTextColor;
  ATs.TextAlpha := FSettings.TimestampTextAlpha;
end;

{Counts the columns the live layout is currently using by iterating
 cells and counting those that share cell 0's top coordinate.
 Generalises across the three uniform-row modes:
 vmGrid      - cells in row 0 share Top, returns column count.
 vmFilmstrip - all cells share Top (one row), returns FrameCount.
 vmScroll    - only cell 0 has that Top (one column), returns 1.
 Used by the live-resolution save path; not called for vmSmartGrid
 (which has its own renderer) or vmSingle (which routes to SaveFrame).}
function TFrameExporter.CountLiveGridColumns: Integer;
var
  R0: TRect;
  I: Integer;
begin
  Result := 0;
  if FFrameView.CellCount = 0 then
    Exit(1);
  R0 := FFrameView.GetCellRect(0);
  for I := 0 to FFrameView.CellCount - 1 do
    if FFrameView.GetCellRect(I).Top = R0.Top then
      Inc(Result);
  if Result < 1 then
    Result := 1;
end;

{Letterbox-scales ASrc to fit AW x AH, filling unused area with ABg.
 Mirrors TFrameView.PaintLoadedFrame (vmGrid live view) so saved cells
 look identical to what the user sees when SaveAtLiveResolution is on.
 Caller owns the returned bitmap.}
function TFrameExporter.ScaleBitmapLetterbox(ASrc: TBitmap; AW, AH: Integer; ABg: TColor): TBitmap;
var
  Scale: Double;
  DW, DH: Integer;
  DstR: TRect;
begin
  Result := TBitmap.Create;
  try
    Result.PixelFormat := pf24bit;
    Result.SetSize(AW, AH);
    Result.Canvas.Brush.Color := ABg;
    Result.Canvas.FillRect(Rect(0, 0, AW, AH));
    if (ASrc = nil) or (ASrc.Width <= 0) or (ASrc.Height <= 0) then
      Exit;
    Scale := Min(AW / ASrc.Width, AH / ASrc.Height);
    DW := Max(1, Round(ASrc.Width * Scale));
    DH := Max(1, Round(ASrc.Height * Scale));
    DstR.Left := (AW - DW) div 2;
    DstR.Top := (AH - DH) div 2;
    DstR.Right := DstR.Left + DW;
    DstR.Bottom := DstR.Top + DH;
    SetStretchBltMode(Result.Canvas.Handle, HALFTONE);
    SetBrushOrgEx(Result.Canvas.Handle, 0, 0, nil);
    Result.Canvas.StretchDraw(DstR, ASrc);
  except
    Result.Free;
    raise;
  end;
end;

{Crop-to-fill scaling. Mirrors TFrameView.PaintCropToFill (vmSmartGrid
 live view) so saved smart-grid cells preserve aspect ratio without
 letterbox bands. Caller owns the returned bitmap.}
function TFrameExporter.ScaleBitmapCropToFill(ASrc: TBitmap; AW, AH: Integer): TBitmap;
var
  Scale: Double;
  SrcW, SrcH: Integer;
  SrcR: TRect;
begin
  Result := TBitmap.Create;
  try
    Result.PixelFormat := pf24bit;
    Result.SetSize(AW, AH);
    if (ASrc = nil) or (ASrc.Width <= 0) or (ASrc.Height <= 0) then
    begin
      Result.Canvas.Brush.Color := FSettings.Background;
      Result.Canvas.FillRect(Rect(0, 0, AW, AH));
      Exit;
    end;
    Scale := Max(AW / ASrc.Width, AH / ASrc.Height);
    SrcW := Min(ASrc.Width, Round(AW / Scale));
    SrcH := Min(ASrc.Height, Round(AH / Scale));
    SrcR.Left := (ASrc.Width - SrcW) div 2;
    SrcR.Top := (ASrc.Height - SrcH) div 2;
    SrcR.Right := SrcR.Left + SrcW;
    SrcR.Bottom := SrcR.Top + SrcH;
    SetStretchBltMode(Result.Canvas.Handle, HALFTONE);
    SetBrushOrgEx(Result.Canvas.Handle, 0, 0, nil);
    Result.Canvas.CopyRect(Rect(0, 0, AW, AH), ASrc.Canvas, SrcR);
  except
    Result.Free;
    raise;
  end;
end;

{Renders a single cell at the size and fitting mode the live view is
 currently using for that cell. vmSmartGrid uses crop-to-fill; every
 other mode uses letterbox-fit. Used by single-frame save and clipboard
 copy when SaveAtLiveResolution is on.}
function TFrameExporter.RenderCellAtLiveSize(AIndex: Integer): TBitmap;
var
  Src: TBitmap;
  R: TRect;
  W, H: Integer;
begin
  Src := FFrameView.CellBitmap(AIndex);
  R := FFrameView.GetCellRect(AIndex);
  W := Max(1, R.Width);
  H := Max(1, R.Height);
  if FFrameView.ViewMode = vmSmartGrid then
    Result := ScaleBitmapCropToFill(Src, W, H)
  else
    Result := ScaleBitmapLetterbox(Src, W, H, FSettings.Background);
end;

procedure TFrameExporter.GetSmartGridParameters(out APanelInnerW, APanelInnerH: Integer; out AAspectRatio: Double);
begin
  {Panel inner area drives the smart-grid arrangement. Falls back to a
   16:9 box when the FrameView has not been sized yet (e.g., save
   triggered before the lister fully laid out).}
  APanelInnerW := Max(1, FFrameView.BaseW - 2 * FFrameView.CellMargin);
  APanelInnerH := Max(1, FFrameView.BaseH - 2 * FFrameView.CellMargin);
  if (APanelInnerW <= 1) or (APanelInnerH <= 1) then
  begin
    APanelInnerW := 1600;
    APanelInnerH := 900;
  end;
  AAspectRatio := FFrameView.AspectRatio;
  if AAspectRatio <= 0 then
    AAspectRatio := 9.0 / 16.0;
end;

procedure TFrameExporter.ComputeSmartCombinedLayout(AForceLiveRes: Boolean; const AFrames: TArray<TBitmap>; out AOutputW, AOutputH: Integer; out ARowCounts: TArray<Integer>);
var
  N, I, Border, Gap, MaxCells, NativeW, InnerW, InnerH: Integer;
  PanelInnerW, PanelInnerH: Integer;
  AspectRatio: Double;
  Bmp: TBitmap;
begin
  AOutputW := 0;
  AOutputH := 0;
  SetLength(ARowCounts, 0);

  N := Length(AFrames);
  if N = 0 then
    N := FFrameView.CellCount;
  if N = 0 then
    Exit;

  Border := Max(0, FSettings.CombinedBorder);
  Gap := Max(0, FSettings.CellGap);

  GetSmartGridParameters(PanelInnerW, PanelInnerH, AspectRatio);
  ARowCounts := ComputeSmartGridRows(N, PanelInnerW, PanelInnerH, Gap, AspectRatio);
  if Length(ARowCounts) = 0 then
    Exit;

  if AForceLiveRes then
  begin
    {Pixel-faithful to the live view: total output = panel size, inner
     area = panel inner. Border setting still wraps the inner area so
     saved images and live view stay visually consistent.}
    InnerW := PanelInnerW;
    InnerH := PanelInnerH;
  end else begin
    {Native: anchor inner_W to the widest row, then preserve the panel's
     inner aspect ratio so rows look the same as on screen. NativeW comes
     from the first non-nil frame; uniform across a video. Frames passed
     by the renderer are preferred so override-frames (set by re-extract)
     are honoured; the predictor passes nil so we fall back to FrameView
     cells.}
    MaxCells := 1;
    for I := 0 to High(ARowCounts) do
      if ARowCounts[I] > MaxCells then
        MaxCells := ARowCounts[I];

    NativeW := 320;
    if Length(AFrames) > 0 then
    begin
      for I := 0 to High(AFrames) do
        if (AFrames[I] <> nil) and (AFrames[I].Width > 0) then
        begin
          NativeW := AFrames[I].Width;
          Break;
        end;
    end else begin
      for I := 0 to N - 1 do
      begin
        Bmp := FFrameView.CellBitmap(I);
        if (Bmp <> nil) and (Bmp.Width > 0) then
        begin
          NativeW := Bmp.Width;
          Break;
        end;
      end;
    end;

    InnerW := MaxCells * NativeW + Max(MaxCells - 1, 0) * Gap;
    InnerH := Max(1, Round(InnerW * (PanelInnerH / PanelInnerW)));
  end;

  AOutputW := InnerW + 2 * Border;
  AOutputH := InnerH + 2 * Border;
end;

procedure TFrameExporter.ComputeUniformLayoutInputs(AForceLiveRes: Boolean; out ACols, ACellW, ACellH: Integer);
var
  N, I: Integer;
  CellRect: TRect;
  Bmp: TBitmap;
begin
  N := FFrameView.CellCount;
  if AForceLiveRes then
  begin
    CellRect := FFrameView.GetCellRect(0);
    ACellW := Max(1, CellRect.Width);
    ACellH := Max(1, CellRect.Height);
    ACols := CountLiveGridColumns;
  end else begin
    {Native cell size from first non-nil cell bitmap; matches the
     fallback RenderCombinedImage uses when scanning AFrames internally.}
    ACellW := 320;
    ACellH := 240;
    for I := 0 to N - 1 do
    begin
      Bmp := FFrameView.CellBitmap(I);
      if Bmp <> nil then
      begin
        ACellW := Bmp.Width;
        ACellH := Bmp.Height;
        Break;
      end;
    end;
    case FFrameView.ViewMode of
      vmFilmstrip:
        ACols := N;
      vmScroll:
        ACols := 1;
    else
      ACols := CountLiveGridColumns;
    end;
  end;
  if ACols < 1 then
    ACols := 1;
end;

{Live-resolution variant of the uniform-grid render: cell pixel size
 matches what the live view is currently showing on screen, and the
 column count tracks the live layout. Used by vmGrid, vmFilmstrip, and
 vmScroll save/copy when SaveAtLiveResolution is on. Frames are
 pre-letterboxed to the live cell dimensions, then fed to the same
 uniform-grid renderer the native path uses. This keeps alpha lifting,
 timecode rendering, and border/gap math centralised.}
function TFrameExporter.RenderGridCombinedAtLiveResolution: TBitmap;
var
  Frames, Scaled: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Ts: TTimestampStyle;
  CellW, CellH, Cols, I, N: Integer;
begin
  N := CollectFramesAndOffsets(Frames, Offsets);
  if N = 0 then
    Exit(nil);

  ComputeUniformLayoutInputs(True, Cols, CellW, CellH);

  BuildGridStyle(Grid);
  Grid.Columns := Cols;
  BuildTimestampStyle(Ts);

  SetLength(Scaled, N);
  try
    for I := 0 to N - 1 do
      if Frames[I] <> nil then
        Scaled[I] := ScaleBitmapLetterbox(Frames[I], CellW, CellH, FSettings.Background)
      else
        Scaled[I] := nil;

    Result := RenderCombinedImage(Scaled, Offsets, Grid, Ts);
  finally
    for I := 0 to High(Scaled) do
      Scaled[I].Free;
  end;
end;

{Renders the live smart-grid arrangement to a combined image. Row counts
 come from ComputeSmartGridRows fed with the panel's inner aspect ratio,
 so the saved arrangement matches what the user sees at the moment of
 save. Output dimensions follow the FSettings.SaveAtLiveResolution toggle:
 - True: panel inner area + Border (pixel-faithful to the live view)
 - False: anchor to the row with the most cells, sized at native frame
 width; total inner aspect ratio still tracks the panel so rows look
 the same shape as on screen.}
function TFrameExporter.RenderSmartCombinedFromCells: TBitmap;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Ts: TTimestampStyle;
  RowCounts: TArray<Integer>;
  N, OutputW, OutputH: Integer;
begin
  N := CollectFramesAndOffsets(Frames, Offsets);
  if N = 0 then
    Exit(nil);

  ComputeSmartCombinedLayout(FSettings.SaveAtLiveResolution, Frames, OutputW, OutputH, RowCounts);
  if Length(RowCounts) = 0 then
    Exit(nil);

  BuildGridStyle(Grid);
  BuildTimestampStyle(Ts);
  Result := RenderSmartCombinedImage(Frames, Offsets, RowCounts, OutputW, OutputH, Grid, Ts);
end;

{Renders the frames into a single combined image laid out per the
 live view mode. Cell pixel size follows the SaveAtLiveResolution
 toggle in every mode:

 - vmSmartGrid: smart layout (panel-aspect-driven row counts);
 panel-pixel cells when the toggle is on, anchor-to-widest native
 cells when off. Handled by RenderSmartCombinedFromCells.
 - vmGrid / vmFilmstrip / vmScroll: uniform-row grid. When the toggle
 is on, all three route through RenderGridCombinedAtLiveResolution
 so cell pixels match the on-screen layout (vmFilmstrip = one wide
 row, vmScroll = one tall column, vmGrid = current column count).
 When off, they render at native cell size with Columns pinned to
 the view's natural shape.
 - vmSingle: caller (SaveView/CopyView) routes to single-frame paths
 before reaching this function, so vmSingle never reaches the
 regular grid renderer here.

 Returns nil only when there are no cells; placeholder/error cells are
 passed through as nil bitmaps and skipped by the renderer.}
function TFrameExporter.RenderCombinedFromCells: TBitmap;
var
  Frames: TArray<TBitmap>;
  Offsets: TFrameOffsetArray;
  Grid: TCombinedGridStyle;
  Ts: TTimestampStyle;
  N, Cols, CellW, CellH: Integer;
begin
  if FFrameView.ViewMode = vmSmartGrid then
    Exit(RenderSmartCombinedFromCells);

  {The uniform-row modes (vmGrid, vmFilmstrip, vmScroll) all share the
   same live-resolution path: it picks Columns from the live layout
   via CountLiveGridColumns, which generalises across the three.}
  if FSettings.SaveAtLiveResolution and (FFrameView.ViewMode in [vmGrid, vmFilmstrip, vmScroll]) then
    Exit(RenderGridCombinedAtLiveResolution);

  N := CollectFramesAndOffsets(Frames, Offsets);
  if N = 0 then
    Exit(nil);

  BuildGridStyle(Grid);
  BuildTimestampStyle(Ts);

  {Native-resolution path for the uniform-row modes. Cell pixel size
   comes from the first non-nil frame; columns follow the live layout
   so the saved image preserves the on-screen arrangement (filmstrip =
   one wide row, scroll = one tall column, vmGrid = current live column
   count). ComputeUniformLayoutInputs centralises both rules so render
   and PredictCombinedSize stay in lockstep.}
  ComputeUniformLayoutInputs(False, Cols, CellW, CellH);
  Grid.Columns := Cols;
  Result := RenderCombinedImage(Frames, Offsets, Grid, Ts);
end;

function TFrameExporter.RenderWithBanner(ABmp: TBitmap): TBitmap;
var
  Style: TBannerStyle;
begin
  if FSettings.ShowBanner then
  begin
    Style.Background := FSettings.BannerBackground;
    Style.TextColor := FSettings.BannerTextColor;
    Style.FontName := FSettings.BannerFontName;
    Style.FontSize := FSettings.BannerFontSize;
    Style.AutoSize := FSettings.BannerFontAutoSize;
    Style.Position := FSettings.BannerPosition;
    Result := AttachBanner(ABmp, FormatBannerLines(FBannerInfo), Style);
    ABmp.Free;
  end
  else
    Result := ABmp;
end;

procedure TFrameExporter.PredictCombinedSize(AForceLiveRes: Boolean; out AW, AH: Integer);
var
  N, Cols, CellW, CellH, Border, Gap: Integer;
  CellRect: TRect;
  RowCounts: TArray<Integer>;
  Bmp: TBitmap;
  EmptyFrames: TArray<TBitmap>;
  Sz: TPoint;
begin
  AW := 0;
  AH := 0;
  N := FFrameView.CellCount;
  if N = 0 then
    Exit;

  {vmSingle: SaveView/CopyView degenerate to single-frame paths so the
   "view"-level resolution is the focused frame's dimensions.}
  if FFrameView.ViewMode = vmSingle then
  begin
    if AForceLiveRes then
    begin
      CellRect := FFrameView.GetCellRect(FFrameView.CurrentFrameIndex);
      AW := Max(1, CellRect.Width);
      AH := Max(1, CellRect.Height);
    end else begin
      AW := 320;
      AH := 240;
      Bmp := FFrameView.CellBitmap(FFrameView.CurrentFrameIndex);
      if (Bmp <> nil) and (Bmp.Width > 0) then
      begin
        AW := Bmp.Width;
        AH := Bmp.Height;
      end;
    end;
    Exit;
  end;

  if FFrameView.ViewMode = vmSmartGrid then
  begin
    SetLength(EmptyFrames, 0);
    ComputeSmartCombinedLayout(AForceLiveRes, EmptyFrames, AW, AH, RowCounts);
    Exit;
  end;

  {Uniform-row modes (vmGrid, vmFilmstrip, vmScroll).}
  Border := Max(0, FSettings.CombinedBorder);
  Gap := Max(0, FSettings.CellGap);
  ComputeUniformLayoutInputs(AForceLiveRes, Cols, CellW, CellH);
  Sz := ComputeCombinedImageSize(N, Cols, CellW, CellH, Border, Gap);
  AW := Sz.X;
  AH := Sz.Y;
end;

function TFrameExporter.PredictDisplayedSize(AForceLiveRes: Boolean; out AW, AH, ACappedW, ACappedH: Integer): Boolean;
begin
  AW := 0;
  AH := 0;
  ACappedW := 0;
  ACappedH := 0;
  Result := False;
  PredictCombinedSize(AForceLiveRes, AW, AH);
  if (AW <= 0) or (AH <= 0) then
    Exit;
  ComputeCappedSize(AW, AH, FSettings.CombinedMaxSide, ACappedW, ACappedH);
  Result := True;
end;

function TFrameExporter.FormatPredictedSize(AForceLiveRes: Boolean): string;
var
  W, H, CW, CH: Integer;
begin
  Result := '';
  if not PredictDisplayedSize(AForceLiveRes, W, H, CW, CH) then
    Exit;
  if (CW <> W) or (CH <> H) then
    Result := Format(' [%dx%d%s%dx%d]', [W, H, ResolutionTransformGlyph, CW, CH])
  else
    Result := Format(' [%dx%d]', [W, H]);
end;

procedure TFrameExporter.ApplyCombinedSizeCap(var ABmp: TBitmap);
var
  Shrunk: TBitmap;
begin
  if (ABmp = nil) or (FSettings.CombinedMaxSide <= 0) then
    Exit;
  Shrunk := DownscaleBitmapToFit(ABmp, FSettings.CombinedMaxSide);
  if Shrunk = nil then
    Exit; {Already fits - keep the original.}
  ABmp.Free;
  ABmp := Shrunk;
end;

procedure TFrameExporter.UpdateBannerInfo(const AInfo: TBannerInfo);
begin
  FBannerInfo := AInfo;
end;

function TFrameExporter.ShowSaveDialog(const ATitle, ADefaultName: string; AOverwritePrompt: Boolean; AInitialLiveRes: Boolean; out APath: string; out AFormat: TSaveFormat): Boolean;
var
  ModernDlg: TFileSaveDialog;
  Hook: TLiveResDialogHook;
  PngType, JpegType: TFileTypeItem;
  LegacyDlg: TSaveDialog;
  ModernHandled: Boolean;
begin
  Result := False;
  ModernHandled := False;

  {Modern Vista+ dialog with an inline 'live resolution' check button.
   Falls through to the legacy TSaveDialog if the platform refuses the
   modern dialog (pre-Vista or unusual COM environments). The legacy
   path has no checkbox; the same toggle is reachable via the settings
   dialog there or via the toolbar's Save view dropdown.}
  if Win32MajorVersion >= 6 then
  begin
    try
      ModernDlg := TFileSaveDialog.Create(nil);
      try
        Hook := TLiveResDialogHook.Create(ModernDlg, AInitialLiveRes);
        try
          ModernDlg.Title := ATitle;

          PngType := ModernDlg.FileTypes.Add;
          PngType.DisplayName := 'PNG image';
          PngType.FileMask := '*.png';
          JpegType := ModernDlg.FileTypes.Add;
          JpegType.DisplayName := 'JPEG image';
          JpegType.FileMask := '*.jpg';

          case FSettings.SaveFormat of
            sfJPEG:
              ModernDlg.FileTypeIndex := 2;
            else
              ModernDlg.FileTypeIndex := 1;
          end;
          ModernDlg.DefaultExtension := 'png';
          ModernDlg.FileName := ADefaultName;
          if FSettings.SaveFolder <> '' then
            ModernDlg.DefaultFolder := ExpandEnvVars(FSettings.SaveFolder);
          if AOverwritePrompt then
            ModernDlg.Options := ModernDlg.Options + [fdoOverWritePrompt]
          else
            ModernDlg.Options := ModernDlg.Options - [fdoOverWritePrompt];

          Hook.Attach;

          if ModernDlg.Execute then
          begin
            case ModernDlg.FileTypeIndex of
              2:
                AFormat := sfJPEG;
              else
                AFormat := sfPNG;
            end;
            APath := ModernDlg.FileName;
            FSettings.SaveFolder := ExtractFilePath(ModernDlg.FileName);
            FSettings.SaveAtLiveResolution := Hook.FinalState;
            FSettings.Save;
            Result := True;
          end;
          ModernHandled := True;
        finally
          Hook.Free;
        end;
      finally
        ModernDlg.Free;
      end;
    except
      on EPlatformVersionException do
        ModernHandled := False; {Defer to legacy dialog below.}
    end;
  end;

  if ModernHandled then
    Exit;

  LegacyDlg := TSaveDialog.Create(nil);
  try
    LegacyDlg.Title := ATitle;
    LegacyDlg.Filter := 'PNG image (*.png)|*.png|JPEG image (*.jpg)|*.jpg';
    case FSettings.SaveFormat of
      sfJPEG:
        LegacyDlg.FilterIndex := 2;
      else
        LegacyDlg.FilterIndex := 1;
    end;
    LegacyDlg.DefaultExt := 'png';
    LegacyDlg.FileName := ADefaultName;
    if FSettings.SaveFolder <> '' then
      LegacyDlg.InitialDir := ExpandEnvVars(FSettings.SaveFolder);
    if AOverwritePrompt then
      LegacyDlg.Options := LegacyDlg.Options + [ofOverwritePrompt];

    if LegacyDlg.Execute then
    begin
      case LegacyDlg.FilterIndex of
        2:
          AFormat := sfJPEG;
        else
          AFormat := sfPNG;
      end;
      APath := LegacyDlg.FileName;
      FSettings.SaveFolder := ExtractFilePath(LegacyDlg.FileName);
      {No dialog override available on legacy Windows, so the caller's
       seed becomes the persisted choice.}
      FSettings.SaveAtLiveResolution := AInitialLiveRes;
      FSettings.Save;
      Result := True;
    end;
  finally
    LegacyDlg.Free;
  end;
end;

procedure TFrameExporter.SaveFramesToDir(const ADir: string; AFormat: TSaveFormat; ASelectedOnly: Boolean; const AFileName: string);
var
  I: Integer;
  Tmp: TBitmap;
  TargetPath: string;
begin
  for I := 0 to FFrameView.CellCount - 1 do
  begin
    if ASelectedOnly and not FFrameView.CellSelected(I) then
      Continue;
    if FFrameView.CellState(I) <> fcsLoaded then
      Continue;
    TargetPath := ADir + GenerateFrameFileName(AFileName, I, FFrameView.CellTimeOffset(I), AFormat);
    if FSettings.SaveAtLiveResolution then
    begin
      Tmp := RenderCellAtLiveSize(I);
      try
        uBitmapSaver.SaveBitmapToFile(Tmp, TargetPath, AFormat, FSettings.JpegQuality, FSettings.PngCompression);
      finally
        Tmp.Free;
      end;
    end
    else
      uBitmapSaver.SaveBitmapToFile(PickSaveBitmap(I), TargetPath, AFormat, FSettings.JpegQuality, FSettings.PngCompression);
  end;
end;

procedure TFrameExporter.SaveFrame(const AFileName: string; AContextCellIndex: Integer; AReExtract: TReExtractAction);
var
  Idx: Integer;
  Fmt: TSaveFormat;
  Path: string;
  WriteAction: TProc;
begin
  if not ResolveFrameIndex(AContextCellIndex, Idx) then
    Exit;

  {Dialog FIRST so the user gets immediate feedback. The seconds-long
   re-extract that may follow runs only after the user has committed to
   the save (and only when they picked native resolution); previously it
   ran upfront, freezing TC for seconds before the dialog even appeared.}
  if not ShowSaveDialog('Save frame', GenerateFrameFileName(AFileName, Idx, FFrameView.CellTimeOffset(Idx), FSettings.SaveFormat), True, FSettings.SaveAtLiveResolution, Path, Fmt) then
    Exit;

  WriteAction := procedure
    var
      Tmp: TBitmap;
    begin
      if FSettings.SaveAtLiveResolution then
      begin
        Tmp := RenderCellAtLiveSize(Idx);
        try
          uBitmapSaver.SaveBitmapToFile(Tmp, Path, Fmt, FSettings.JpegQuality, FSettings.PngCompression);
        finally
          Tmp.Free;
        end;
      end
      else
        uBitmapSaver.SaveBitmapToFile(PickSaveBitmap(Idx), Path, Fmt, FSettings.JpegQuality, FSettings.PngCompression);
    end;

  {Native-resolution path may need re-extract; defer to host. Live-
   resolution path uses on-screen cells directly, no re-extract needed.}
  if (not FSettings.SaveAtLiveResolution) and Assigned(AReExtract) then
    AReExtract([Idx], WriteAction)
  else
    WriteAction;
end;

procedure TFrameExporter.SaveFrames(const AFileName: string; AReExtract: TReExtractAction);
var
  I, FirstIdx: Integer;
  Path: string;
  Fmt: TSaveFormat;
  SelectedOnly: Boolean;
  WriteAction: TProc;
  Indices: TArray<Integer>;
begin
  if FFrameView.CellCount = 0 then
    Exit;

  {Selection-aware: any selection at all means "save just those";
   otherwise every loaded frame goes out. Replaces the historical
   pair (SaveAllFrames + SaveSelectedFrames) with one action.}
  SelectedOnly := FFrameView.SelectedCount > 0;

  {Sample filename uses the first frame that will actually be written
   so the user sees a meaningful default in the dialog.}
  FirstIdx := 0;
  if SelectedOnly then
    for I := 0 to FFrameView.CellCount - 1 do
      if FFrameView.CellSelected(I) then
      begin
        FirstIdx := I;
        Break;
      end;

  {Dialog first; re-extract (if needed) only after the user accepts.
   See SaveFrame for the rationale.}
  if not ShowSaveDialog('Save frames', GenerateFrameFileName(AFileName, FirstIdx, FFrameView.CellTimeOffset(FirstIdx), FSettings.SaveFormat), False, FSettings.SaveAtLiveResolution, Path, Fmt) then
    Exit;

  WriteAction := procedure
    begin
      SaveFramesToDir(IncludeTrailingPathDelimiter(ExtractFilePath(Path)), Fmt, SelectedOnly, AFileName);
    end;

  if (not FSettings.SaveAtLiveResolution) and Assigned(AReExtract) then
  begin
    Indices := BuildSaveIndicesSelectedOrAll;
    AReExtract(Indices, WriteAction);
  end
  else
    WriteAction;
end;

procedure TFrameExporter.SaveView(const AFileName: string; AInitialLiveRes: Boolean; AReExtract: TReExtractAction);
var
  Fmt: TSaveFormat;
  Path, BaseName: string;
  WriteAction: TProc;
begin
  if FFrameView.CellCount = 0 then
    Exit;

  {vmSingle's "view" is a single frame; route to SaveFrame so the user
   gets a single-frame artefact rather than a wasteful 1-cell combined.
   SaveFrame uses the persisted setting for its dialog seed; the
   distinction between "view" and "frame" loses meaning here so the
   per-call AInitialLiveRes override is intentionally not threaded
   through.}
  if FFrameView.ViewMode = vmSingle then
  begin
    SaveFrame(AFileName, FFrameView.CurrentFrameIndex, AReExtract);
    Exit;
  end;

  BaseName := ChangeFileExt(ExtractFileName(AFileName), '');
  {Dialog first; the rendering + re-extract that may follow run only
   after the user accepts. See SaveFrame for the rationale.}
  if not ShowSaveDialog('Save view', BaseName + '_view.png', True, AInitialLiveRes, Path, Fmt) then
    Exit;

  WriteAction := procedure
    var
      Bmp: TBitmap;
    begin
      {Rendering the combined image at native size for many cells can blow
       past 32-bit address space (or simply exhaust the heap). Catch the
       memory exceptions here and surface a domain-specific error so the
       user gets a hint about the cause and possible workarounds, rather
       than the host's generic OS-level message.}
      try
        Bmp := RenderWithBanner(RenderCombinedFromCells);
        try
          ApplyCombinedSizeCap(Bmp);
          uBitmapSaver.SaveBitmapToFile(Bmp, Path, Fmt, FSettings.JpegQuality, FSettings.PngCompression);
        finally
          Bmp.Free;
        end;
      except
        on E: EOutOfMemory do
          MessageDlg(Format('Out of memory while building the combined image (%s).' + sLineBreak + sLineBreak + 'The image is too large for this build. Lower the Scale target in Settings, reduce the frame count, or use the 64-bit plugin variant.', [E.Message]), mtError, [mbOK], 0);
        on E: EOutOfResources do
          MessageDlg(Format('Out of system resources while building the combined image (%s).' + sLineBreak + sLineBreak + 'The image is too large. Lower the Scale target in Settings or reduce the frame count.', [E.Message]), mtError, [mbOK], 0);
      end;
    end;

  if (not FSettings.SaveAtLiveResolution) and Assigned(AReExtract) then
    AReExtract(BuildSaveIndicesAllLoaded, WriteAction)
  else
    WriteAction;
end;

procedure TFrameExporter.CopyFrame(AContextCellIndex: Integer; AReExtract: TReExtractAction);
var
  Idx: Integer;
  WriteAction: TProc;
  PriorLiveRes: Boolean;
begin
  if not ResolveFrameIndex(AContextCellIndex, Idx) then
    Exit;

  {Single-frame copies publish CF_BITMAP only (via Clipboard.Assign),
   not the CF_DIBV5 + CF_DIB pair CopyView uses. The decoder pipeline
   produces pf24bit frames (TFrameView.SetFrame asserts the contract)
   so there is no alpha channel to preserve — every paste target gets
   the same opaque pixels regardless of which DIB variant it asks for,
   and CF_BITMAP is the broadest-compatibility format. CopyView differs
   because the combined image carries cell-gap transparency that only
   CF_DIBV5 can round-trip; do not collapse the two paths.

   The render path reads FSettings.SaveAtLiveResolution; we temp-flip it
   to CopyAtLiveResolution for the duration of this call so the copy
   surface honours its own setting. AReExtract sees the flipped value
   too (it queries SaveAtLiveResolution to decide whether re-extract is
   needed), so the gate is consistent across render and re-extract.}
  WriteAction := procedure
    var
      Tmp, Source: TBitmap;
      OwnsSource: Boolean;
    begin
      {Pick the bitmap that becomes the clipboard payload. The
       file-reference path needs the bitmap object to encode to PNG;
       the legacy path hands it to VCL's Clipboard.Assign which
       publishes CF_BITMAP. Resolution choice (live vs native) is the
       same for both paths — temp-flipped to CopyAtLiveResolution
       earlier so SaveAtLiveResolution reads as the copy-side intent.}
      if FSettings.SaveAtLiveResolution then
      begin
        Source := RenderCellAtLiveSize(Idx);
        OwnsSource := True;
      end
      else
      begin
        Source := PickSaveBitmap(Idx);
        OwnsSource := False;
      end;
      try
        if FSettings.ClipboardAsFileReference then
        begin
          {File-reference path takes ownership. When OwnsSource is True
           we hand Source directly; when False (PickSaveBitmap returned
           a bitmap that lives in FFrameView), we must clone it first —
           cell bitmaps belong to the view and can't be transferred to
           the worker thread which would free them on completion.}
          if OwnsSource then
          begin
            if PublishBitmapAsFileReference(Source) = cprFailed then
              MessageDlg('Clipboard write failed - could not write the temp PNG or publish CF_HDROP. Check %TEMP% has free space and is writable.', mtError, [mbOK], 0);
            {PublishBitmapAsFileReference set Source to nil; don't double-free.}
            OwnsSource := False;
          end
          else
          begin
            Tmp := TBitmap.Create;
            try
              Tmp.Assign(Source);
              if PublishBitmapAsFileReference(Tmp) = cprFailed then
                MessageDlg('Clipboard write failed - could not write the temp PNG or publish CF_HDROP. Check %TEMP% has free space and is writable.', mtError, [mbOK], 0);
            finally
              {PublishBitmapAsFileReference set Tmp to nil on success or
               kept ownership on the cancel path; either way Free on nil
               is safe and Free on a real bitmap covers the early-exit
               case before the call.}
              Tmp.Free;
            end;
          end;
        end
        else
        begin
          {In-memory clipboard path. Same owned-vs-clone rule as the
           file-reference branch above — PublishBitmapToClipboardAsImage
           takes ownership of the bitmap, so an unowned PickSaveBitmap
           result must be cloned first to keep the FFrameView cell
           intact.}
          if OwnsSource then
          begin
            if PublishBitmapToClipboardAsImage(Source, FSettings.Background) = cprFailed then
              MessageDlg('Clipboard write failed - the frame is too large to copy.' + sLineBreak + sLineBreak + 'Use the 64-bit plugin variant, or enable "Copy to clipboard as a file reference" on the Save tab.', mtError, [mbOK], 0);
            OwnsSource := False;
          end
          else
          begin
            Tmp := TBitmap.Create;
            try
              Tmp.Assign(Source);
              if PublishBitmapToClipboardAsImage(Tmp, FSettings.Background) = cprFailed then
                MessageDlg('Clipboard write failed - the frame is too large to copy.' + sLineBreak + sLineBreak + 'Use the 64-bit plugin variant, or enable "Copy to clipboard as a file reference" on the Save tab.', mtError, [mbOK], 0);
            finally
              Tmp.Free;
            end;
          end;
        end;
      finally
        if OwnsSource then
        begin
          Tmp := Source;
          Tmp.Free;
        end;
      end;
    end;

  PriorLiveRes := FSettings.SaveAtLiveResolution;
  FSettings.SaveAtLiveResolution := FSettings.CopyAtLiveResolution;
  try
    if (not FSettings.SaveAtLiveResolution) and Assigned(AReExtract) then
      AReExtract([Idx], WriteAction)
    else
      WriteAction;
  finally
    FSettings.SaveAtLiveResolution := PriorLiveRes;
  end;
end;

procedure TFrameExporter.CopyView(AForceLiveRes: Boolean; AReExtract: TReExtractAction);
var
  WriteAction: TProc;
  PriorLiveRes: Boolean;
begin
  if FFrameView.CellCount = 0 then
    Exit;
  if FFrameView.ViewMode = vmSingle then
  begin
    CopyFrame(FFrameView.CurrentFrameIndex);
    Exit;
  end;

  {The render pipeline reads FSettings.SaveAtLiveResolution to decide live
   vs native; for a one-shot dropdown choice we flip it for the duration
   of this call only and restore in finally. No FSettings.Save call -
   the persisted value is unchanged, only the in-memory copy briefly.}
  PriorLiveRes := FSettings.SaveAtLiveResolution;

  WriteAction := procedure
    var
      Bmp: TBitmap;
    begin
      {Same OOM-safety wrapper as SaveView, plus a check for the silent
       failure path inside CopyBitmapToClipboard: when GlobalAlloc returns
       0 mid-publish the helper bails with Result := False without raising,
       which historically meant the user saw the clipboard simply not
       change. Surface that as an explicit error too.}
      try
        Bmp := RenderWithBanner(RenderCombinedFromCells);
        try
          ApplyCombinedSizeCap(Bmp);
          {Publishes CF_DIBV5 (alpha-aware) and CF_DIB (alpha pre-composited
           onto FSettings.Background) side-by-side, so modern paste targets
           keep the transparent gaps and legacy targets see a working opaque
           image instead of the broken paste they get from the OS's default
           CF_DIB synthesis. ABackground only matters when the rendered
           bitmap carries alpha; for opaque sources it is ignored.}
          if FSettings.ClipboardAsFileReference then
          begin
            if PublishBitmapAsFileReference(Bmp) = cprFailed then
              MessageDlg('Clipboard write failed - could not write the temp PNG or publish CF_HDROP. Check %TEMP% has free space and is writable.', mtError, [mbOK], 0);
          end
          else if PublishBitmapToClipboardAsImage(Bmp, FSettings.Background) = cprFailed then
            MessageDlg('Clipboard write failed - the combined image is too large to copy.' + sLineBreak + sLineBreak + 'Lower the Scale target in Settings, reduce the frame count, or use Save view to write the image to a file instead.', mtError, [mbOK], 0);
        finally
          Bmp.Free;
        end;
      except
        on E: EOutOfMemory do
          MessageDlg(Format('Out of memory while building the combined image (%s).' + sLineBreak + sLineBreak + 'The image is too large for this build. Lower the Scale target in Settings, reduce the frame count, or use the 64-bit plugin variant.', [E.Message]), mtError, [mbOK], 0);
        on E: EOutOfResources do
          MessageDlg(Format('Out of system resources while building the combined image (%s).' + sLineBreak + sLineBreak + 'The image is too large. Lower the Scale target in Settings or reduce the frame count.', [E.Message]), mtError, [mbOK], 0);
      end;
    end;

  FSettings.SaveAtLiveResolution := AForceLiveRes;
  try
    if (not AForceLiveRes) and Assigned(AReExtract) then
      AReExtract(BuildSaveIndicesAllLoaded, WriteAction)
    else
      WriteAction;
  finally
    FSettings.SaveAtLiveResolution := PriorLiveRes;
  end;
end;

end.
