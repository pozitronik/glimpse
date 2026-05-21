{Shared type for the frame-export flow, kept in its own unit so TFrameSaver,
 TFrameCopier and the TFrameExporter facade can all reference it without a
 circular unit dependency.}
unit FrameExportTypes;

interface

uses
  System.SysUtils;

type
  {Invoked after the save dialog accepts so re-extraction happens only when
   the user has committed. The host sets and clears the render pipeline's
   override frames around AAction so the save picks up the re-extracted
   bitmaps. Nil = skip re-extract.}
  TReExtractAction = reference to procedure(const AIndices: TArray<Integer>; AAction: TProc);

implementation

end.
