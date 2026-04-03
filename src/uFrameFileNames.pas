{ Frame filename generation for save operations.
  Pure string computation: no I/O, no UI. }
unit uFrameFileNames;

interface

uses
  uSettings;

{ Returns the file extension for a save format, including the dot. }
function SaveFormatExtension(AFormat: TSaveFormat): string;

{ Generates a frame filename from video path, frame index, time offset, and format.
  Pattern: <basename>_frame_<index+1:02d>_<HH-MM-SS.mmm>.<ext> }
function GenerateFrameFileName(const AVideoFileName: string;
  AFrameIndex: Integer; ATimeOffset: Double; AFormat: TSaveFormat): string;

implementation

uses
  System.SysUtils, uFrameOffsets;

function SaveFormatExtension(AFormat: TSaveFormat): string;
begin
  case AFormat of
    sfJPEG: Result := '.jpg';
  else
    Result := '.png';
  end;
end;

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

end.
