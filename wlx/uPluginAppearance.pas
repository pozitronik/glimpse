{Visual styling constants for the WLX plugin form — colours and font
 sizes that the form's controls reference but that have no semantic
 meaning beyond "this is what the error label should look like".

 Layout pixels live in uToolbarLayout; animation timing in uFrameView;
 viewport-refresh debounce in uExtractionController. This unit is
 deliberately tiny so adding a new colour or font size doesn't fight
 with any unrelated concern.}
unit uPluginAppearance;

interface

uses
  System.UITypes;

const
  {Greyed-out colour for the placeholder "error" label shown over the
   frame view when extraction hasn't started yet.}
  CLR_ERROR_LABEL = TColor($00888888);
  FONT_ERROR_LABEL = 11;

implementation

end.
