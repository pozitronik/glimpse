{ Frame filename generation for save operations.
  Pure string computation: no I/O, no UI. }
unit uFrameFileNames;

interface

uses
  uBitmapSaver;

{ Generates a frame filename from video path, frame index, time offset, and format.
  Pattern: <basename>_frame_<index+1:02d>_<HH-MM-SS.mmm>.<ext> }
function GenerateFrameFileName(const AVideoFileName: string;
  AFrameIndex: Integer; ATimeOffset: Double; AFormat: TSaveFormat): string;

{ Generates combined image filename: <basename>_combined.<ext> }
function GenerateCombinedFileName(const AVideoFileName: string;
  AFormat: TSaveFormat): string;

implementation

uses
  System.SysUtils, uFrameOffsets;

function GenerateFrameFileName(const AVideoFileName: string;
  AFrameIndex: Integer; ATimeOffset: Double; AFormat: TSaveFormat): string;
var
  BaseName: string;
begin
  BaseName := ChangeFileExt(ExtractFileName(AVideoFileName), '');
  Result := Format('%s_frame_%.2d_%s%s',
    [BaseName, AFrameIndex + 1, FormatTimecodeForFilename(ATimeOffset),
     SaveFormatExtension(AFormat)]);
end;

function GenerateCombinedFileName(const AVideoFileName: string;
  AFormat: TSaveFormat): string;
begin
  Result := ChangeFileExt(ExtractFileName(AVideoFileName), '') +
    '_combined' + SaveFormatExtension(AFormat);
end;

end.
