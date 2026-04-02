/// Disk cache for extracted video frames.
/// Stores frames as PNG files in a sharded directory structure, keyed by
/// video file metadata and frame time offset. Provides LRU eviction.
unit uCache;

interface

uses
  System.SysUtils, System.IOUtils, System.Classes, System.Hash,
  System.Generics.Collections, System.Generics.Defaults,
  Vcl.Graphics, Vcl.Imaging.pngimage;

type
  TFrameCache = class
  strict private
    FCacheDir: string;
    FMaxSizeBytes: Int64;

    /// Builds the canonical string that uniquely identifies a cached frame.
    class function BuildKeyString(const AFilePath: string;
      AFileSize: Int64; AFileTime: TDateTime;
      ATimeOffset: Double): string; static;

    /// Hashes a key string to a 32-char lowercase hex MD5 digest.
    class function HashKey(const AKeyString: string): string; static;

    /// Maps a hash key to its full file path in the sharded directory.
    function KeyToPath(const AKey: string): string;

  public
    constructor Create(const ACacheDir: string; AMaxSizeMB: Integer);

    /// Generates a cache key for a frame by reading file metadata from disk.
    /// Returns empty string if the file cannot be stat'd.
    class function FrameKey(const AFilePath: string;
      ATimeOffset: Double): string; static;

    /// Tries to load a cached frame. Returns nil on miss or any error.
    /// Caller owns the returned bitmap.
    function TryGet(const AKey: string): TBitmap;

    /// Stores a frame bitmap as PNG in the cache. Silent on failure.
    procedure Put(const AKey: string; ABitmap: TBitmap);

    /// Deletes all cached files and recreates the root directory.
    procedure Clear;

    /// Evicts oldest-accessed files until total size <= MaxSizeBytes.
    procedure Evict;

    /// Returns total size of all cached PNG files in bytes.
    function GetTotalSize: Int64;

    property CacheDir: string read FCacheDir;
  end;

{$IFDEF DEBUG}
var
  GCacheLogPath: string;
{$ENDIF}

implementation

uses
  System.DateUtils;

{ Invariant format settings for deterministic key strings }
var
  InvFmt: TFormatSettings;

{$IFDEF DEBUG}
procedure CacheLog(const AMsg: string);
var
  F: TextFile;
begin
  if GCacheLogPath = '' then Exit;
  try
    AssignFile(F, GCacheLogPath);
    if FileExists(GCacheLogPath) then
      Append(F)
    else
      Rewrite(F);
    try
      WriteLn(F, FormatDateTime('hh:nn:ss.zzz', Now) + '  [Cache] ' + AMsg);
    finally
      CloseFile(F);
    end;
  except
  end;
end;
{$ENDIF}

{ TFrameCache }

constructor TFrameCache.Create(const ACacheDir: string; AMaxSizeMB: Integer);
begin
  inherited Create;
  FCacheDir := ACacheDir;
  FMaxSizeBytes := Int64(AMaxSizeMB) * 1024 * 1024;
  if not TDirectory.Exists(FCacheDir) then
    TDirectory.CreateDirectory(FCacheDir);
  {$IFDEF DEBUG}
  CacheLog('Create: dir=' + ACacheDir + ' maxMB=' + IntToStr(AMaxSizeMB));
  {$ENDIF}
end;

class function TFrameCache.BuildKeyString(const AFilePath: string;
  AFileSize: Int64; AFileTime: TDateTime; ATimeOffset: Double): string;
begin
  Result := AnsiLowerCase(AFilePath) + '|' +
    IntToStr(AFileSize) + '|' +
    FormatDateTime('yyyymmddhhnnsszzz', AFileTime) + '|' +
    Format('%.3f', [ATimeOffset], InvFmt);
end;

class function TFrameCache.HashKey(const AKeyString: string): string;
begin
  Result := THashMD5.GetHashString(AKeyString).ToLower;
end;

function TFrameCache.KeyToPath(const AKey: string): string;
begin
  Result := TPath.Combine(
    TPath.Combine(FCacheDir, Copy(AKey, 1, 2)),
    AKey + '.png');
end;

class function TFrameCache.FrameKey(const AFilePath: string;
  ATimeOffset: Double): string;
var
  FileSize: Int64;
  FileTime: TDateTime;
  KeyStr: string;
begin
  Result := '';
  try
    if not TFile.Exists(AFilePath) then
      Exit;
    FileSize := TFile.GetSize(AFilePath);
    FileTime := TFile.GetLastWriteTime(AFilePath);
    KeyStr := BuildKeyString(AFilePath, FileSize, FileTime, ATimeOffset);
    Result := HashKey(KeyStr);
  except
    { File inaccessible -- return empty, caller treats as cache-disabled }
  end;
end;

function TFrameCache.TryGet(const AKey: string): TBitmap;
var
  Path: string;
  Data: TBytes;
  Stream: TMemoryStream;
  Png: TPngImage;
begin
  Result := nil;
  if AKey = '' then
    Exit;
  try
    Path := KeyToPath(AKey);
    if not TFile.Exists(Path) then
    begin
      {$IFDEF DEBUG}CacheLog('TryGet MISS (no file) key=' + AKey);{$ENDIF}
      Exit;
    end;

    Data := TFile.ReadAllBytes(Path);
    {$IFDEF DEBUG}CacheLog('TryGet key=' + AKey + ' fileBytes=' + IntToStr(Length(Data)));{$ENDIF}
    Stream := TMemoryStream.Create;
    try
      Stream.WriteBuffer(Data[0], Length(Data));
      Stream.Position := 0;
      Png := TPngImage.Create;
      try
        Png.LoadFromStream(Stream);
        {$IFDEF DEBUG}CacheLog('  PNG loaded: ' + IntToStr(Png.Width) + 'x' + IntToStr(Png.Height));{$ENDIF}
        Result := TBitmap.Create;
        Result.Assign(Png);
        Result.PixelFormat := pf24bit; { Force DIB for thread-safe rendering }
        {$IFDEF DEBUG}CacheLog('  BMP assigned: ' + IntToStr(Result.Width) + 'x' + IntToStr(Result.Height)
          + ' empty=' + BoolToStr(Result.Empty, True)
          + ' pf=' + IntToStr(Ord(Result.PixelFormat)));{$ENDIF}
      finally
        Png.Free;
      end;
    finally
      Stream.Free;
    end;
  except
    on E: Exception do
    begin
      {$IFDEF DEBUG}CacheLog('TryGet EXCEPTION key=' + AKey + ' ' + E.ClassName + ': ' + E.Message);{$ENDIF}
      FreeAndNil(Result);
    end;
  end;

  { Update access time for LRU tracking; isolated so a failure here
    cannot discard the successfully loaded bitmap. }
  if Result <> nil then
  try
    TFile.SetLastAccessTime(Path, Now);
  except
  end;
end;

procedure TFrameCache.Put(const AKey: string; ABitmap: TBitmap);
var
  FinalPath, TempPath, SubDir: string;
  Png: TPngImage;
begin
  if (AKey = '') or (ABitmap = nil) then
    Exit;
  {$IFDEF DEBUG}CacheLog('Put key=' + AKey + ' bmp=' + IntToStr(ABitmap.Width) + 'x' + IntToStr(ABitmap.Height));{$ENDIF}
  try
    FinalPath := KeyToPath(AKey);
    SubDir := ExtractFilePath(FinalPath);
    if not TDirectory.Exists(SubDir) then
      TDirectory.CreateDirectory(SubDir);

    { Write to temp file, then rename for atomicity }
    TempPath := TPath.Combine(FCacheDir, TGUID.NewGuid.ToString + '.tmp');
    Png := TPngImage.Create;
    try
      Png.Assign(ABitmap);
      Png.CompressionLevel := 1; { Fast compression for cache writes }
      Png.SaveToFile(TempPath);
      {$IFDEF DEBUG}CacheLog('  saved tmp=' + TempPath + ' pngSize=' + IntToStr(TFile.GetSize(TempPath)));{$ENDIF}
    finally
      Png.Free;
    end;

    { Atomic rename; overwrite if exists (benign race from parallel TC) }
    if TFile.Exists(FinalPath) then
      TFile.Delete(FinalPath);
    TFile.Move(TempPath, FinalPath);
    {$IFDEF DEBUG}CacheLog('  moved to ' + FinalPath);{$ENDIF}
  except
    on E: Exception do
    begin
      {$IFDEF DEBUG}CacheLog('Put EXCEPTION key=' + AKey + ' ' + E.ClassName + ': ' + E.Message);{$ENDIF}
      try
        if TFile.Exists(TempPath) then
          TFile.Delete(TempPath);
      except
      end;
    end;
  end;
end;

procedure TFrameCache.Clear;
begin
  try
    if TDirectory.Exists(FCacheDir) then
      TDirectory.Delete(FCacheDir, True);
    TDirectory.CreateDirectory(FCacheDir);
  except
  end;
end;

procedure TFrameCache.Evict;
type
  TCacheFileInfo = record
    Path: string;
    Size: Int64;
    AccessTime: TDateTime;
  end;
var
  Files: TArray<string>;
  Infos: TList<TCacheFileInfo>;
  Info: TCacheFileInfo;
  TotalSize: Int64;
  FileName: string;
  Dirs: TArray<string>;
  Dir: string;
begin
  if not TDirectory.Exists(FCacheDir) then
    Exit;

  try
    Files := TDirectory.GetFiles(FCacheDir, '*.png', TSearchOption.soAllDirectories);
  except
    Exit;
  end;

  Infos := TList<TCacheFileInfo>.Create;
  try
    TotalSize := 0;
    for FileName in Files do
    begin
      try
        Info.Path := FileName;
        Info.Size := TFile.GetSize(FileName);
        Info.AccessTime := TFile.GetLastAccessTime(FileName);
        Infos.Add(Info);
        TotalSize := TotalSize + Info.Size;
      except
        { Skip files we cannot stat }
      end;
    end;

    if TotalSize <= FMaxSizeBytes then
      Exit;

    { Sort by access time ascending (oldest first) }
    Infos.Sort(TComparer<TCacheFileInfo>.Construct(
      function(const A, B: TCacheFileInfo): Integer
      begin
        Result := CompareDateTime(A.AccessTime, B.AccessTime);
      end));

    { Delete oldest files until within budget }
    for Info in Infos do
    begin
      if TotalSize <= FMaxSizeBytes then
        Break;
      try
        TFile.Delete(Info.Path);
        TotalSize := TotalSize - Info.Size;
      except
        { File may be locked by another TC instance }
      end;
    end;

    { Clean up empty subdirectories }
    try
      Dirs := TDirectory.GetDirectories(FCacheDir);
      for Dir in Dirs do
      begin
        try
          if Length(TDirectory.GetFiles(Dir)) = 0 then
            TDirectory.Delete(Dir, False);
        except
        end;
      end;
    except
    end;
  finally
    Infos.Free;
  end;
end;

function TFrameCache.GetTotalSize: Int64;
var
  Files: TArray<string>;
  FileName: string;
begin
  Result := 0;
  if not TDirectory.Exists(FCacheDir) then
    Exit;
  try
    Files := TDirectory.GetFiles(FCacheDir, '*.png', TSearchOption.soAllDirectories);
    for FileName in Files do
    begin
      try
        Result := Result + TFile.GetSize(FileName);
      except
      end;
    end;
  except
  end;
end;

initialization
  InvFmt := TFormatSettings.Invariant;

end.
