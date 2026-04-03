{ ffmpeg.exe backend: process execution, video probing, and frame extraction. }
unit uFFmpegExe;

interface

uses
  System.SysUtils, System.Classes, Winapi.Windows, Vcl.Graphics,
  uFrameOffsets;

type
  TVideoInfo = record
    Duration: Double;      { seconds; -1 if unknown }
    Width: Integer;
    Height: Integer;
    VideoCodec: string;
    IsValid: Boolean;      { True if at least duration was parsed }
    ErrorMessage: string;
  end;

  TFFmpegExe = class
  strict private
    FExePath: string;
  public
    constructor Create(const AExePath: string);

    { Probes a video file for metadata (duration, resolution, codec). }
    function ProbeVideo(const AFileName: string): TVideoInfo;

    { Extracts a single frame at the given time offset.
      Returns a new TBitmap on success, nil on failure. Caller owns the returned bitmap. }
    function ExtractFrame(const AFileName: string; ATimeOffset: Double): TBitmap;

    property ExePath: string read FExePath;
  end;

{ Parsing functions exposed for unit testing }

{ Parses duration from ffmpeg stderr output. Returns seconds, or -1 if not found. }
function ParseDuration(const AText: string): Double;

{ Parses video resolution from ffmpeg stderr output. }
function ParseResolution(const AText: string; out AWidth, AHeight: Integer): Boolean;

{ Parses video codec name from ffmpeg stderr output. }
function ParseVideoCodec(const AText: string): string;

{ Parses version string from `ffmpeg -version` output.
  Expects first line like "ffmpeg version 6.1.1 ...".
  Returns version string (e.g. "6.1.1") or empty if not recognized. }
function ParseFFmpegVersion(const AText: string): string;

{ Runs `ffmpeg -version` and returns the version string.
  Returns empty string if the executable is not a valid ffmpeg. }
function ValidateFFmpeg(const AExePath: string): string;

implementation

uses
  System.Math, Vcl.Imaging.pngimage;

{ Pipe reading helper }

function ReadPipeToEnd(APipe: THandle): TBytes;
var
  Buffer: array[0..4095] of Byte;
  BytesRead: DWORD;
  Stream: TBytesStream;
begin
  Stream := TBytesStream.Create;
  try
    repeat
      BytesRead := 0;
      if not ReadFile(APipe, Buffer, SizeOf(Buffer), BytesRead, nil) then
        Break;
      if BytesRead > 0 then
        Stream.WriteBuffer(Buffer, BytesRead);
    until BytesRead = 0;
    Result := Copy(Stream.Bytes, 0, Stream.Size);
  finally
    Stream.Free;
  end;
end;

{ Process execution }

{ Runs a process with redirected stdout/stderr, captures both outputs.
  Returns the process exit code, or -1 on launch failure or timeout. }
function RunProcess(const ACommandLine: string; out AStdOut, AStdErr: TBytes;
  ATimeoutMs: DWORD = 30000): Integer;
var
  SA: TSecurityAttributes;
  SI: TStartupInfo;
  PI: TProcessInformation;
  StdOutRead, StdOutWrite: THandle;
  StdErrRead, StdErrWrite: THandle;
  StdInRead, StdInWrite: THandle;
  CmdLine: string;
  StdErrThread: TThread;
  CapturedStdErr: TBytes;
  ExitCode: DWORD;
begin
  Result := -1;
  AStdOut := nil;
  AStdErr := nil;

  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;
  SA.lpSecurityDescriptor := nil;

  if not CreatePipe(StdOutRead, StdOutWrite, @SA, 0) then
    Exit;
  if not CreatePipe(StdErrRead, StdErrWrite, @SA, 0) then
  begin
    CloseHandle(StdOutRead);
    CloseHandle(StdOutWrite);
    Exit;
  end;
  { Empty stdin so ffmpeg does not attempt interactive reads }
  if not CreatePipe(StdInRead, StdInWrite, @SA, 1) then
  begin
    CloseHandle(StdOutRead);
    CloseHandle(StdOutWrite);
    CloseHandle(StdErrRead);
    CloseHandle(StdErrWrite);
    Exit;
  end;
  CloseHandle(StdInWrite);

  { Parent-side read handles must not be inherited }
  SetHandleInformation(StdOutRead, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(StdErrRead, HANDLE_FLAG_INHERIT, 0);

  ZeroMemory(@SI, SizeOf(SI));
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  SI.hStdInput := StdInRead;
  SI.hStdOutput := StdOutWrite;
  SI.hStdError := StdErrWrite;
  SI.wShowWindow := SW_HIDE;

  ZeroMemory(@PI, SizeOf(PI));

  CmdLine := ACommandLine;
  UniqueString(CmdLine);

  if not CreateProcess(nil, PChar(CmdLine), nil, nil, True,
    CREATE_NO_WINDOW, nil, nil, SI, PI) then
  begin
    CloseHandle(StdOutRead);
    CloseHandle(StdOutWrite);
    CloseHandle(StdErrRead);
    CloseHandle(StdErrWrite);
    CloseHandle(StdInRead);
    Exit;
  end;

  { Child now owns the write ends; close them in parent }
  CloseHandle(StdOutWrite);
  CloseHandle(StdErrWrite);
  CloseHandle(StdInRead);

  { Read stderr on a background thread to prevent pipe deadlock }
  StdErrThread := TThread.CreateAnonymousThread(
    procedure
    begin
      CapturedStdErr := ReadPipeToEnd(StdErrRead);
    end
  );
  StdErrThread.FreeOnTerminate := False;
  StdErrThread.Start;

  { Read stdout on the calling thread }
  AStdOut := ReadPipeToEnd(StdOutRead);

  StdErrThread.WaitFor;
  AStdErr := CapturedStdErr;
  StdErrThread.Free;

  if WaitForSingleObject(PI.hProcess, ATimeoutMs) = WAIT_OBJECT_0 then
  begin
    GetExitCodeProcess(PI.hProcess, ExitCode);
    Result := Integer(ExitCode);
  end
  else
  begin
    TerminateProcess(PI.hProcess, 1);
    Result := -1;
  end;

  CloseHandle(StdOutRead);
  CloseHandle(StdErrRead);
  CloseHandle(PI.hProcess);
  CloseHandle(PI.hThread);
end;

{ PNG conversion }

function PngBytesToBitmap(const AData: TBytes): TBitmap;
var
  Stream: TMemoryStream;
  Png: TPngImage;
begin
  Stream := TMemoryStream.Create;
  try
    Stream.WriteBuffer(AData[0], Length(AData));
    Stream.Position := 0;
    Png := TPngImage.Create;
    try
      Png.LoadFromStream(Stream);
      Result := TBitmap.Create;
      Result.Assign(Png);
      Result.PixelFormat := pf24bit; { Force DIB for thread-safe rendering }
    finally
      Png.Free;
    end;
  finally
    Stream.Free;
  end;
end;

{ Parsing }

function ParseDuration(const AText: string): Double;
var
  P: Integer;
  TimeStr: string;
  Parts: TArray<string>;
  H, M, S: Integer;
  DotPos: Integer;
  FracStr: string;
  Frac: Double;
begin
  Result := -1;

  P := Pos('Duration:', AText);
  if P = 0 then
    Exit;
  P := P + Length('Duration:');

  { Skip whitespace }
  while (P <= Length(AText)) and (AText[P] = ' ') do
    Inc(P);

  { Read until comma, newline, or end }
  TimeStr := '';
  while (P <= Length(AText)) and not CharInSet(AText[P], [',', #13, #10]) do
  begin
    TimeStr := TimeStr + AText[P];
    Inc(P);
  end;
  TimeStr := Trim(TimeStr);

  if (TimeStr = '') or SameText(TimeStr, 'N/A') then
    Exit;

  { Expected: HH:MM:SS.ff }
  Parts := TimeStr.Split([':']);
  if Length(Parts) <> 3 then
    Exit;

  H := StrToIntDef(Parts[0], -1);
  M := StrToIntDef(Parts[1], -1);
  if (H < 0) or (M < 0) then
    Exit;

  DotPos := Pos('.', Parts[2]);
  if DotPos > 0 then
  begin
    S := StrToIntDef(Copy(Parts[2], 1, DotPos - 1), -1);
    FracStr := Copy(Parts[2], DotPos + 1, Length(Parts[2]) - DotPos);
    if (FracStr = '') or (S < 0) then
      Exit;
    Frac := StrToIntDef(FracStr, 0) / Power(10, Length(FracStr));
  end
  else
  begin
    S := StrToIntDef(Parts[2], -1);
    Frac := 0;
  end;

  if S < 0 then
    Exit;

  Result := H * 3600.0 + M * 60.0 + S + Frac;
end;

function ParseResolution(const AText: string; out AWidth, AHeight: Integer): Boolean;
var
  VideoPos, P, I: Integer;
  WidthStr, HeightStr: string;
begin
  Result := False;
  AWidth := 0;
  AHeight := 0;

  VideoPos := Pos('Video:', AText);
  if VideoPos = 0 then
    Exit;

  { Scan for NNNxNNN pattern after "Video:" }
  P := VideoPos + 6;
  while P < Length(AText) - 1 do
  begin
    if (AText[P] = 'x') and
       CharInSet(AText[P - 1], ['0'..'9']) and
       CharInSet(AText[P + 1], ['0'..'9']) then
    begin
      { Walk backwards for width digits }
      I := P - 1;
      while (I > VideoPos) and CharInSet(AText[I], ['0'..'9']) do
        Dec(I);
      WidthStr := Copy(AText, I + 1, P - I - 1);

      { Walk forwards for height digits }
      I := P + 1;
      while (I <= Length(AText)) and CharInSet(AText[I], ['0'..'9']) do
        Inc(I);
      HeightStr := Copy(AText, P + 1, I - P - 1);

      AWidth := StrToIntDef(WidthStr, 0);
      AHeight := StrToIntDef(HeightStr, 0);

      { Require at least 2-digit width and height to avoid false matches like "0x1A" }
      if (Length(WidthStr) >= 2) and (Length(HeightStr) >= 2) and
         (AWidth > 0) and (AHeight > 0) then
      begin
        Result := True;
        Exit;
      end;
    end;
    Inc(P);
  end;
end;

function ParseVideoCodec(const AText: string): string;
var
  P, Start: Integer;
begin
  Result := '';

  P := Pos('Video:', AText);
  if P = 0 then
    Exit;
  P := P + Length('Video:');

  { Skip whitespace }
  while (P <= Length(AText)) and (AText[P] = ' ') do
    Inc(P);

  { Read word characters }
  Start := P;
  while (P <= Length(AText)) and CharInSet(AText[P], ['a'..'z', 'A'..'Z', '0'..'9', '_']) do
    Inc(P);

  if P > Start then
    Result := Copy(AText, Start, P - Start);
end;

function ParseFFmpegVersion(const AText: string): string;
var
  Line, Prefix: string;
  P, Start: Integer;
begin
  Result := '';
  if AText = '' then
    Exit;

  { Take first line only }
  P := Pos(#10, AText);
  if P > 0 then
    Line := Copy(AText, 1, P - 1)
  else
    Line := AText;
  Line := Trim(Line.Replace(#13, ''));

  Prefix := 'ffmpeg version ';
  if not Line.StartsWith(Prefix, True) then
    Exit;

  { Extract version token (everything up to the next space or dash) }
  P := Length(Prefix) + 1;
  Start := P;
  while (P <= Length(Line)) and not CharInSet(Line[P], [' ', '-']) do
    Inc(P);

  if P > Start then
    Result := Copy(Line, Start, P - Start);
end;

function ValidateFFmpeg(const AExePath: string): string;
var
  CmdLine: string;
  StdOut, StdErr: TBytes;
  Output: string;
begin
  Result := '';
  CmdLine := Format('"%s" -version', [AExePath]);
  if RunProcess(CmdLine, StdOut, StdErr, 5000) <> 0 then
    Exit;
  if Length(StdOut) > 0 then
    Output := TEncoding.UTF8.GetString(StdOut)
  else if Length(StdErr) > 0 then
    Output := TEncoding.UTF8.GetString(StdErr)
  else
    Exit;
  Result := ParseFFmpegVersion(Output);
end;

{ TFFmpegExe }

constructor TFFmpegExe.Create(const AExePath: string);
begin
  inherited Create;
  FExePath := AExePath;
end;

function TFFmpegExe.ProbeVideo(const AFileName: string): TVideoInfo;
var
  CmdLine: string;
  StdOut, StdErr: TBytes;
  StdErrStr: string;
begin
  Result := Default(TVideoInfo);
  Result.Duration := -1;

  CmdLine := Format('"%s" -nostdin -hide_banner -i "%s"', [FExePath, AFileName]);
  { Exit code 1 is expected: "no output file specified" }
  RunProcess(CmdLine, StdOut, StdErr, 10000);

  if Length(StdErr) = 0 then
  begin
    Result.ErrorMessage := 'No output from ffmpeg';
    Exit;
  end;

  StdErrStr := TEncoding.UTF8.GetString(StdErr);
  Result.Duration := ParseDuration(StdErrStr);
  ParseResolution(StdErrStr, Result.Width, Result.Height);
  Result.VideoCodec := ParseVideoCodec(StdErrStr);
  Result.IsValid := Result.Duration > 0;

  if not Result.IsValid then
    Result.ErrorMessage := 'Could not parse video metadata';
end;

function TFFmpegExe.ExtractFrame(const AFileName: string; ATimeOffset: Double): TBitmap;
var
  CmdLine: string;
  StdOut, StdErr: TBytes;
  ExitCode: Integer;
begin
  Result := nil;

  CmdLine := Format('"%s" -nostdin -loglevel error -ss %s -i "%s" ' +
    '-frames:v 1 -q:v 2 -f image2pipe -vcodec png pipe:1',
    [FExePath,
     Format('%.3f', [ATimeOffset], TFormatSettings.Invariant),
     AFileName]);

  ExitCode := RunProcess(CmdLine, StdOut, StdErr);
  if (ExitCode <> 0) or (Length(StdOut) < 8) then
    Exit;

  try
    Result := PngBytesToBitmap(StdOut);
  except
    FreeAndNil(Result);
  end;
end;

end.
