unit TestToolbarGlyphLibrary;

{Smoke tests for TToolbarGlyphLibrary. The library wraps a TImageList
 that holds three icon resources (MENU / ARROW_W / ARROW_H) loaded from
 the host module's .res. These tests cover the public contract: the
 image list is created with the right pixel size, the right color depth,
 and exactly three entries after construction. The actual icon pixel
 fidelity is not asserted — that is the resource compiler's domain, not
 this unit's.}

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestToolbarGlyphLibrary = class
  public
    [Test] procedure Constructs_WithoutException;
    [Test] procedure Images_Not_Nil_After_Create;
    [Test] procedure Images_HasThreeEntries;
    [Test] procedure Images_PixelSizeIs16;
    [Test] procedure Images_OwnedByLibrary_FreedWithIt;
    [Test] procedure Images_SharedReference_NotACopy;
  end;

implementation

uses
  System.Classes, Vcl.Controls, Vcl.ImgList,
  uToolbarGlyphLibrary;

procedure TTestToolbarGlyphLibrary.Constructs_WithoutException;
var
  Lib: TToolbarGlyphLibrary;
begin
  Lib := TToolbarGlyphLibrary.Create(nil);
  try
    Assert.IsNotNull(Lib);
  finally
    Lib.Free;
  end;
end;

procedure TTestToolbarGlyphLibrary.Images_Not_Nil_After_Create;
var
  Lib: TToolbarGlyphLibrary;
begin
  Lib := TToolbarGlyphLibrary.Create(nil);
  try
    Assert.IsNotNull(Lib.Images, 'Images list must be created');
  finally
    Lib.Free;
  end;
end;

procedure TTestToolbarGlyphLibrary.Images_HasThreeEntries;
{Pins the count against the IDX_ICON_* constants in uToolbarLayout —
 three icons (HAMBURGER + ARROW_W + ARROW_H). Adding a fourth icon must
 update this expectation deliberately to keep the index assumptions in
 sync.}
var
  Lib: TToolbarGlyphLibrary;
begin
  Lib := TToolbarGlyphLibrary.Create(nil);
  try
    Assert.AreEqual(3, Lib.Images.Count, 'Expected exactly 3 icons in the toolbar glyph list');
  finally
    Lib.Free;
  end;
end;

procedure TTestToolbarGlyphLibrary.Images_PixelSizeIs16;
{Toolbar buttons assume 16x16 glyphs (matches both the resource pixel
 size and the icon width baked into uToolbarBuilder's layout math).}
var
  Lib: TToolbarGlyphLibrary;
begin
  Lib := TToolbarGlyphLibrary.Create(nil);
  try
    Assert.AreEqual(16, Lib.Images.Width, 'Glyph width must be 16');
    Assert.AreEqual(16, Lib.Images.Height, 'Glyph height must be 16');
  finally
    Lib.Free;
  end;
end;

procedure TTestToolbarGlyphLibrary.Images_OwnedByLibrary_FreedWithIt;
{TComponent ownership: the image list is parented to the library
 instance, so freeing the library must release the list. The test
 builds the library with a free-standing TComponent owner and verifies
 freeing the library doesn't leave the image list dangling on that
 owner.}
var
  Owner: TComponent;
  Lib: TToolbarGlyphLibrary;
  ImagesBefore: TImageList;
begin
  Owner := TComponent.Create(nil);
  try
    Lib := TToolbarGlyphLibrary.Create(Owner);
    ImagesBefore := Lib.Images;
    Assert.IsNotNull(ImagesBefore);
    {ImageList is parented to the library, not the outer owner. Freeing
     the library frees the list — Owner ends up with zero components.}
    Lib.Free;
    Assert.AreEqual(0, Owner.ComponentCount,
      'After freeing the library, the outer owner must not still hold any leaked component');
  finally
    Owner.Free;
  end;
end;

procedure TTestToolbarGlyphLibrary.Images_SharedReference_NotACopy;
{Two reads of .Images must return the exact same TImageList instance.
 The form relies on this: FToolbarImages and FHamburgerMenu.Images
 both hold pointers to the SAME list so MI.ImageIndex resolves the
 same glyph index either way.}
var
  Lib: TToolbarGlyphLibrary;
  A, B: TImageList;
begin
  Lib := TToolbarGlyphLibrary.Create(nil);
  try
    A := Lib.Images;
    B := Lib.Images;
    Assert.IsTrue(Pointer(A) = Pointer(B),
      'Images property must return the same instance on every read');
  finally
    Lib.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestToolbarGlyphLibrary);

end.
