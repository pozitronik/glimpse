{WCX plugin API types and constants.
 Based on Total Commander WCX plugin interface specification.}
unit uWcxAPI;

interface

uses
  Winapi.Windows;

const
  {OpenArchive open modes}
  PK_OM_LIST = 0;
  PK_OM_EXTRACT = 1;

  {ProcessFile operations}
  PK_SKIP = 0;
  PK_TEST = 1;
  PK_EXTRACT = 2;

  {Return codes}
  E_SUCCESS = 0;
  E_END_ARCHIVE = 10;
  E_NO_MEMORY = 11;
  E_BAD_DATA = 12;
  E_BAD_ARCHIVE = 13;
  E_UNKNOWN_FORMAT = 14;
  E_EOPEN = 15;
  E_ECREATE = 16;
  E_ECLOSE = 17;
  E_EREAD = 18;
  E_EWRITE = 19;
  E_NOT_SUPPORTED = 24;

  {GetPackerCaps flags}
  PK_CAPS_NEW = 1;
  PK_CAPS_MODIFY = 2;
  PK_CAPS_MULTIPLE = 4;
  PK_CAPS_DELETE = 8;
  PK_CAPS_OPTIONS = 16;
  PK_CAPS_MEMPACK = 32;
  PK_CAPS_BY_CONTENT = 64;
  PK_CAPS_SEARCHTEXT = 128;
  PK_CAPS_HIDE = 256;
  PK_CAPS_ENCRYPT = 512;

  {Background flags for OpenArchive}
  BACKGROUND_UNPACK = 1;
  BACKGROUND_PACK = 2;
  BACKGROUND_MEMPACK = 4;

type
  TOpenArchiveData = record
    ArcName: PAnsiChar;
    OpenMode: Integer;
    OpenResult: Integer;
    CmtBuf: PAnsiChar;
    CmtBufSize: Integer;
    CmtSize: Integer;
    CmtState: Integer;
  end;

  POpenArchiveData = ^TOpenArchiveData;

  TOpenArchiveDataW = record
    ArcName: PWideChar;
    OpenMode: Integer;
    OpenResult: Integer;
    CmtBuf: PWideChar;
    CmtBufSize: Integer;
    CmtSize: Integer;
    CmtState: Integer;
  end;

  POpenArchiveDataW = ^TOpenArchiveDataW;

  THeaderData = record
    ArcName: array [0 .. 259] of AnsiChar;
    FileName: array [0 .. 259] of AnsiChar;
    Flags: Integer;
    PackSize: Integer;
    UnpSize: Integer;
    HostOS: Integer;
    FileCRC: Integer;
    FileTime: Integer;
    UnpVer: Integer;
    Method: Integer;
    FileAttr: Integer;
    CmtBuf: PAnsiChar;
    CmtBufSize: Integer;
    CmtSize: Integer;
    CmtState: Integer;
  end;

  PHeaderData = ^THeaderData;

  THeaderDataExW = record
    ArcName: array [0 .. 1023] of WideChar;
    FileName: array [0 .. 1023] of WideChar;
    Flags: Integer;
    PackSize: DWORD;
    PackSizeHigh: DWORD;
    UnpSize: DWORD;
    UnpSizeHigh: DWORD;
    HostOS: Integer;
    FileCRC: Integer;
    FileTime: Integer;
    UnpVer: Integer;
    Method: Integer;
    FileAttr: Integer;
    Reserved: array [0 .. 1023] of AnsiChar;
  end;

  PHeaderDataExW = ^THeaderDataExW;

  TChangeVolProc = function(ArcName: PAnsiChar; Mode: Integer): Integer; stdcall;
  TChangeVolProcW = function(ArcName: PWideChar; Mode: Integer): Integer; stdcall;
  TProcessDataProc = function(FileName: PAnsiChar; Size: Integer): Integer; stdcall;
  TProcessDataProcW = function(FileName: PWideChar; Size: Integer): Integer; stdcall;

  {Default params structure passed by TC}
  TWcxDefaultParams = record
    Size: Integer;
    PluginInterfaceVersionLow: DWORD;
    PluginInterfaceVersionHi: DWORD;
    DefaultIniName: array [0 .. MAX_PATH - 1] of AnsiChar;
  end;

  PWcxDefaultParams = ^TWcxDefaultParams;

implementation

end.
