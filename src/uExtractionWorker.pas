{ Worker thread that extracts video frames via ffmpeg.exe.
  Stores results in a thread-safe queue and posts WM notifications
  to the owner window for UI-thread pickup. }
unit uExtractionWorker;

interface

uses
  System.Classes, System.SyncObjs, System.Generics.Collections,
  Winapi.Windows, Winapi.Messages,
  Vcl.Graphics,
  uFrameOffsets, uFFmpegExe, uCache;

const
  WM_FRAME_READY     = WM_USER + 100; { Notification: pending frames available in queue }
  WM_EXTRACTION_DONE = WM_USER + 101; { Extraction finished }

type
  { Extracted frame awaiting delivery to UI thread }
  TPendingFrame = record
    Index: Integer;
    Bitmap: TBitmap; { nil = extraction error }
  end;

  { Worker thread that extracts frames sequentially via ffmpeg.exe.
    Stores results in a thread-safe queue and posts notifications. }
  TExtractionThread = class(TThread)
  private
    FFFmpegPath: string;
    FFileName: string;
    FOffsets: TFrameOffsetArray;
    FNotifyWnd: HWND;
    FQueue: TList<TPendingFrame>;
    FQueueLock: TCriticalSection;
    FCache: IFrameCache;
    FActiveWorkerCount: PInteger; { shared counter; last thread posts WM_EXTRACTION_DONE }
    FUseBmpPipe: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const AFFmpegPath, AFileName: string;
      const AOffsets: TFrameOffsetArray; ANotifyWnd: HWND;
      AQueue: TList<TPendingFrame>; AQueueLock: TCriticalSection;
      const ACache: IFrameCache; AActiveWorkerCount: PInteger;
      AUseBmpPipe: Boolean);
  end;

implementation

uses
  System.SysUtils
  {$IFDEF DEBUG}, uDebugLog{$ENDIF};

{$IFDEF DEBUG}
procedure ThreadLog(const AMsg: string);
begin
  DebugLog('Thread', AMsg);
end;
{$ENDIF}

constructor TExtractionThread.Create(const AFFmpegPath, AFileName: string;
  const AOffsets: TFrameOffsetArray; ANotifyWnd: HWND;
  AQueue: TList<TPendingFrame>; AQueueLock: TCriticalSection;
  const ACache: IFrameCache; AActiveWorkerCount: PInteger;
  AUseBmpPipe: Boolean);
begin
  inherited Create(True); { suspended }
  FreeOnTerminate := False;
  FFFmpegPath := AFFmpegPath;
  FFileName := AFileName;
  FOffsets := Copy(AOffsets);
  FNotifyWnd := ANotifyWnd;
  FQueue := AQueue;
  FQueueLock := AQueueLock;
  FCache := ACache;
  FActiveWorkerCount := AActiveWorkerCount;
  FUseBmpPipe := AUseBmpPipe;
end;

procedure TExtractionThread.Execute;
var
  FFmpeg: TFFmpegExe;
  Bmp: TBitmap;
  Frame: TPendingFrame;
  I, CellIdx: Integer;
  Source: string;
begin
  {$IFDEF DEBUG}ThreadLog(Format('Execute START frames=%d', [Length(FOffsets)]));{$ENDIF}
  try
    FFmpeg := TFFmpegExe.Create(FFFmpegPath);
    try
      for I := 0 to High(FOffsets) do
      begin
        if Terminated then
        begin
          {$IFDEF DEBUG}ThreadLog(Format('Execute TERMINATED at i=%d', [I]));{$ENDIF}
          Exit;
        end;

        CellIdx := FOffsets[I].Index - 1; { 1-based offset index to 0-based cell index }
        Bmp := nil;

        try
          Source := 'none';

          Bmp := FCache.TryGet(FFileName, FOffsets[I].TimeOffset);
          if Bmp <> nil then
            Source := 'cache';

          { Cache miss: extract via ffmpeg }
          if Bmp = nil then
          begin
            Bmp := FFmpeg.ExtractFrame(FFileName, FOffsets[I].TimeOffset, FUseBmpPipe);
            if Bmp <> nil then
            begin
              Source := 'ffmpeg';
              FCache.Put(FFileName, FOffsets[I].TimeOffset, Bmp);
            end;
          end;

          {$IFDEF DEBUG}
          if Bmp <> nil then
            ThreadLog(Format('Frame[%d] source=%s size=%dx%d empty=%s',
              [CellIdx, Source, Bmp.Width, Bmp.Height, BoolToStr(Bmp.Empty, True)]))
          else
            ThreadLog(Format('Frame[%d] source=%s Bmp=NIL', [CellIdx, Source]));
          {$ENDIF}
        except
          on E: Exception do
          begin
            {$IFDEF DEBUG}
            ThreadLog(Format('Frame[%d] EXCEPTION: %s: %s', [CellIdx, E.ClassName, E.Message]));
            {$ENDIF}
            FreeAndNil(Bmp);
          end;
        end;

        if Terminated then
        begin
          Bmp.Free;
          Exit;
        end;

        { Enqueue frame for the UI thread; PostMessage is just a notification.
          Bitmap = nil signals an error placeholder to the UI. }
        Frame.Index := CellIdx;
        Frame.Bitmap := Bmp;
        FQueueLock.Enter;
        try
          FQueue.Add(Frame);
        finally
          FQueueLock.Leave;
        end;
        PostMessage(FNotifyWnd, WM_FRAME_READY, 0, 0);
      end;
    finally
      FFmpeg.Free;
    end;
  finally
    { Always decrement; last worker to finish notifies the UI }
    if InterlockedDecrement(FActiveWorkerCount^) = 0 then
      if not Terminated then
        PostMessage(FNotifyWnd, WM_EXTRACTION_DONE, 0, 0);
  end;
end;

end.
