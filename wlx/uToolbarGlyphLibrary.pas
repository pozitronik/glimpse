{Toolbar glyph image-list wrapper.

 Owns a TImageList holding the three toolbar icons (HAMBURGER, ARROW_W,
 ARROW_H) loaded from embedded .res resources at construction. Lives
 alongside the form so it can share its image-list handle with
 FHamburgerMenu and the toolbar button bar - those keep a pointer to
 the same TImageList for the lifetime of the form.

 The icon resources themselves are embedded by the host module's .res
 file (the $R icons.res directive on uPluginForm); HInstance resolves
 to that module at runtime so this unit does not need its own $R
 directive.

 Index constants live in uToolbarLayout (IDX_ICON_HAMBURGER /
 IDX_ICON_ARROW_W / IDX_ICON_ARROW_H); the order of LoadIconResource
 calls below MUST stay in lockstep with them.}
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
    {Shared image-list owned by Self (via TComponent ownership). Toolbar
     buttons, mode buttons, and the hamburger menu all keep a pointer to
     this same instance — never freed directly.}
    property Images: TImageList read FImages;
  end;

implementation

uses
  Vcl.Graphics, Winapi.Windows;

const
  ICON_W = 16;

{Loads one ICON resource named AResName from the host module's .res and
 appends it to AImageList. Icons preserve their alpha channel natively
 through TImageList.AddIcon; no manual scanline copy is needed. Lifted
 here from uPluginForm so the resource-loading detail stays with the
 image-list owner.}
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
  {Toolbar glyphs are loaded from embedded ICON resources rather than
   relying on Unicode characters: the runtime font (Tahoma/MS Sans Serif
   under TC's Lister window) does not reliably cover U+2261/U+2194/U+2195.
   Order MUST match the IDX_ICON_* constants in uToolbarLayout
   (HAMBURGER = 0, ARROW_W = 1, ARROW_H = 2).}
  LoadIconResourceToImageList(FImages, 'MENU');
  LoadIconResourceToImageList(FImages, 'ARROW_W');
  LoadIconResourceToImageList(FImages, 'ARROW_H');
end;

end.
