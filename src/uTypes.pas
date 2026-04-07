{ Shared type declarations used across multiple units.
  Extracted from uSettings to break unnecessary coupling. }
unit uTypes;

interface

type
  TFFmpegMode = (fmAuto, fmExe);
  TViewMode = (vmSmartGrid, vmGrid, vmScroll, vmFilmstrip, vmSingle);
  TZoomMode = (zmFitWindow, zmFitIfLarger, zmActual);

  { Bundles extraction parameters that travel together through the
    extraction pipeline (controller -> worker -> extractor). }
  TExtractionOptions = record
    UseBmpPipe: Boolean;
    MaxSide: Integer;
    HwAccel: Boolean;
    UseKeyframes: Boolean;
  end;

implementation

end.
