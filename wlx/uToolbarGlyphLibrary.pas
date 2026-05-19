{Toolbar glyph image-list wrapper. Icons are loaded from the host module's
 embedded .res; load order MUST match the IDX_ICON_* constants in
 uToolbarLayout.}
unit uToolbarGlyphLibrary;

interface

uses
  System.Classes, Vcl.Controls, Vcl.ImgList;

type
  TToolbarGlyphLibrary = class(TComponent)
  strict private
    FImages: TImageList;
  public
    constructor Create(AOwner: TComponent); override;
    {Owned via TComponent ownership; consumers borrow the reference — never free directly.}
    property Images: TImageList read FImages;
  end;

implementation

uses
  Vcl.Graphics, Winapi.Windows;

const
  ICON_W = 16;

procedure LoadIconResourceToImageList(AImageList: TImageList; const AResName: string);
var
  Icon: TIcon;
begin
  Icon := TIcon.Create;
  try
    Icon.LoadFromResourceName(HInstance, AResName);
    AImageList.AddIcon(Icon);
  finally
    Icon.Free;
  end;
end;

constructor TToolbarGlyphLibrary.Create(AOwner: TComponent);
begin
  inherited;
  FImages := TImageList.Create(Self);
  FImages.SetSize(ICON_W, ICON_W);
  FImages.ColorDepth := cd32Bit;
  {ICON resources are used instead of Unicode chars because Tahoma/MS Sans
   Serif (TC's Lister default font) does not reliably cover U+2261/U+2194/U+2195.
   Load order MUST match IDX_ICON_* in uToolbarLayout.}
  LoadIconResourceToImageList(FImages, 'MENU');
  LoadIconResourceToImageList(FImages, 'ARROW_W');
  LoadIconResourceToImageList(FImages, 'ARROW_H');
end;

end.
