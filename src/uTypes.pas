{ Shared type declarations used across multiple units.
  Extracted from uSettings to break unnecessary coupling. }
unit uTypes;

interface

type
  TFFmpegMode = (fmAuto, fmExe);
  TViewMode = (vmSmartGrid, vmGrid, vmScroll, vmFilmstrip, vmSingle);
  TZoomMode = (zmFitWindow, zmFitIfLarger, zmActual);

implementation

end.
