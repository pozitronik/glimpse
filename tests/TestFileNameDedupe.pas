unit TestFileNameDedupe;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFileNameDedupe = class
  public
    { Deduplication }
    [Test] procedure TestDedupeEmptyInput;
    [Test] procedure TestDedupeNoCollisionsUnchanged;
    [Test] procedure TestDedupeTwoWayCollision;
    [Test] procedure TestDedupeThreeWayCollision;
    [Test] procedure TestDedupeSkipsLiteralOccupiedSlot;
    [Test] procedure TestDedupeIsCaseInsensitive;
    [Test] procedure TestDedupeNamesWithoutExtension;
  end;

implementation

uses
  System.SysUtils,
  uFileNameDedupe;

{ Deduplication }

procedure TTestFileNameDedupe.TestDedupeEmptyInput;
var
  Out_: TArray<string>;
begin
  Out_ := DeduplicateFileNames([]);
  Assert.AreEqual(0, Integer(Length(Out_)));
end;

procedure TTestFileNameDedupe.TestDedupeNoCollisionsUnchanged;
var
  Out_: TArray<string>;
begin
  Out_ := DeduplicateFileNames(['a.jpg', 'b.jpg', 'c.png']);
  Assert.AreEqual(3, Integer(Length(Out_)));
  Assert.AreEqual('a.jpg', Out_[0]);
  Assert.AreEqual('b.jpg', Out_[1]);
  Assert.AreEqual('c.png', Out_[2]);
end;

procedure TTestFileNameDedupe.TestDedupeTwoWayCollision;
var
  Out_: TArray<string>;
begin
  Out_ := DeduplicateFileNames(['poster.jpg', 'poster.jpg']);
  Assert.AreEqual('poster.jpg', Out_[0], 'First-defined keeps bare name');
  Assert.AreEqual('poster(2).jpg', Out_[1]);
end;

procedure TTestFileNameDedupe.TestDedupeThreeWayCollision;
var
  Out_: TArray<string>;
begin
  Out_ := DeduplicateFileNames(['poster.jpg', 'poster.jpg', 'poster.jpg']);
  Assert.AreEqual('poster.jpg', Out_[0]);
  Assert.AreEqual('poster(2).jpg', Out_[1]);
  Assert.AreEqual('poster(3).jpg', Out_[2]);
end;

procedure TTestFileNameDedupe.TestDedupeSkipsLiteralOccupiedSlot;
var
  Out_: TArray<string>;
begin
  { Literal "poster(2).jpg" is taken first; the natural collision suffix
    must increment past it. Order of definition matters: first-defined
    keeps the literal, the auto-deduped entry shifts to (3). }
  Out_ := DeduplicateFileNames(['poster(2).jpg', 'poster.jpg', 'poster.jpg']);
  Assert.AreEqual('poster(2).jpg', Out_[0]);
  Assert.AreEqual('poster.jpg', Out_[1]);
  Assert.AreEqual('poster(3).jpg', Out_[2],
    'Auto-dedupe must skip the literal (2) slot and land on (3)');
end;

procedure TTestFileNameDedupe.TestDedupeIsCaseInsensitive;
var
  Out_: TArray<string>;
begin
  { Windows treats "Poster.jpg" and "poster.jpg" as the same file, so the
    listing must, too — otherwise extracting both back-to-back would
    overwrite the first silently. }
  Out_ := DeduplicateFileNames(['Poster.jpg', 'poster.jpg']);
  Assert.AreEqual('Poster.jpg', Out_[0]);
  Assert.AreEqual('poster(2).jpg', Out_[1]);
end;

procedure TTestFileNameDedupe.TestDedupeNamesWithoutExtension;
var
  Out_: TArray<string>;
begin
  Out_ := DeduplicateFileNames(['foo', 'foo']);
  Assert.AreEqual('foo', Out_[0]);
  Assert.AreEqual('foo(2)', Out_[1]);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFileNameDedupe);

end.
