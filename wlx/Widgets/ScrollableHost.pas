{Abstraction for a scrollable container that hosts the frame view. The
 view applies wheel-driven scrolling through this interface so it does
 not reach into a TScrollBox parent. The form (or a test) supplies the
 concrete adapter; FrameView falls through to inherited handling when
 no host is wired.}
unit ScrollableHost;

interface

uses
  Vcl.Forms;

type
  IScrollableHost = interface
    ['{3E5A8B27-4F61-4D89-A3B0-9C7D2E5F0468}']
    {Apply a wheel-delta scroll along the corresponding axis. ADelta is
     the WM_MOUSEWHEEL delta as received by the caller (positive = wheel
     away from user). The implementer translates it to its own scroll
     position semantics.}
    procedure ScrollHorz(ADelta: Integer);
    procedure ScrollVert(ADelta: Integer);
  end;

  {Adapter that drives a TScrollBox's horizontal and vertical scroll
   bars from wheel deltas. AScrollBox is borrowed — its owner (typically
   the hosting form) keeps the lifetime.}
  TScrollBoxScrollableHost = class(TInterfacedObject, IScrollableHost)
  strict private
    FScrollBox: TScrollBox;
  public
    constructor Create(AScrollBox: TScrollBox);
    procedure ScrollHorz(ADelta: Integer);
    procedure ScrollVert(ADelta: Integer);
  end;

implementation

constructor TScrollBoxScrollableHost.Create(AScrollBox: TScrollBox);
begin
  inherited Create;
  FScrollBox := AScrollBox;
end;

procedure TScrollBoxScrollableHost.ScrollHorz(ADelta: Integer);
begin
  FScrollBox.HorzScrollBar.Position := FScrollBox.HorzScrollBar.Position - ADelta;
end;

procedure TScrollBoxScrollableHost.ScrollVert(ADelta: Integer);
begin
  FScrollBox.VertScrollBar.Position := FScrollBox.VertScrollBar.Position - ADelta;
end;

end.
