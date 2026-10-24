unit StoreView;

{ Draws the Store (Fenwick Grimm and his goods) and the tray of your own special
  cards over the table. UI code (uses Graphics). Everything it draws, and every
  rectangle, comes from the GameController, so a tap lands on what is drawn. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Graphics, FPImage, CardImages, SceneView,
  Specials, Cosmetics, GameController;

type
  TStoreView = class
  private
    FPortrait: TBitmap;
    FPW, FPH: Integer;
    FPortraitMaster: TFPMemoryImage;
    FMasters: array[0..OverlayArtCount - 1] of TFPMemoryImage;
    FIcons: array[0..OverlayArtCount - 1] of TBitmap;
    FIconSize: Integer;
    function Icon(Art, Size: Integer): TBitmap;
    procedure DrawPreview(C: TCanvas; const R: TRect; P: Integer; K: Double);
    function PortraitBmp(W, H: Integer): TBitmap;
    procedure TextIn(C: TCanvas; const R: TRect; const S: string);
  public
    destructor Destroy; override;
    { Draws the overlay the controller has open (nothing if none). }
    procedure Draw(C: TCanvas; Ctl: TGameController; Shade: TSceneView; const Full: TRect);
  end;

implementation

const
  FontName = 'Times New Roman';
  ArtKey: array[0..OverlayArtCount - 1] of string =
    ('extraturn', 'easyrule', 'dawn', 'wild', 'seer', 'stake', 'undo', 'hint',
     'trophy_firstwin', 'trophy_perfect', 'trophy_jack', 'trophy_queen', 'trophy_king', 'trophy_flawless',
     '', 'relic_garlic', 'relic_pick', 'relic_spoon', 'relic_locket', 'relic_moonstone');

function Gold: TColor;
begin
  Result := RGBToColor(201, 162, 74);
end;

function DimGold: TColor;
begin
  Result := RGBToColor(150, 125, 70);
end;

function Bone: TColor;
begin
  Result := RGBToColor(232, 224, 204);
end;

destructor TStoreView.Destroy;
var
  I: Integer;
begin
  FPortrait.Free;
  FPortraitMaster.Free;
  for I := 0 to OverlayArtCount - 1 do
  begin
    FMasters[I].Free;
    FIcons[I].Free;
  end;
  inherited Destroy;
end;

function TStoreView.PortraitBmp(W, H: Integer): TBitmap;
begin
  if FPortraitMaster = nil then FPortraitMaster := LoadResourceImage('shopkeeper');
  if (FPortrait = nil) or (FPW <> W) or (FPH <> H) then
  begin
    FPortrait.Free;
    FPortrait := ScaleToBitmap(FPortraitMaster, W, H);
    FPW := W;
    FPH := H;
  end;
  Result := FPortrait;
end;

{ A Style row's picture, drawn in code: a card back, a bit of the table cloth, or the moon. }
procedure TStoreView.DrawPreview(C: TCanvas; const R: TRect; P: Integer; K: Double);
var
  Kind, Item, I, Steps, CX, CY, Rad, W, H: Integer;
  F: Double;
  Cen, Edg: Integer;
begin
  Kind := (P - 1) div 16;
  Item := (P - 1) mod 16;
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  case Kind of
    0: DrawCardBackStyle(C, R, Item);
    1:
    begin
      { the felt: dark at the edge, lighter in the middle, with its frame }
      Cen := ClothColor(Item, 0);
      Edg := ClothColor(Item, 1);
      { the felt is dark: show it a little lighter so the swatch reads in a small picture }
      Cen := (Min(255, ColorR(Cen) * 17 div 8) shl 16) or (Min(255, ColorG(Cen) * 17 div 8) shl 8) or Min(255, ColorB(Cen) * 17 div 8);
      Edg := (Min(255, ColorR(Edg) * 17 div 8 + 14) shl 16) or (Min(255, ColorG(Edg) * 17 div 8 + 14) shl 8) or Min(255, ColorB(Edg) * 17 div 8 + 14);
      C.Pen.Style := psClear;
      C.Brush.Style := bsSolid;
      Steps := 6;
      for I := 0 to Steps do
      begin
        F := I / Steps;
        C.Brush.Color := RGBToColor(
          Round(ColorR(Edg) + (ColorR(Cen) - ColorR(Edg)) * F),
          Round(ColorG(Edg) + (ColorG(Cen) - ColorG(Edg)) * F),
          Round(ColorB(Edg) + (ColorB(Cen) - ColorB(Edg)) * F));
        C.RoundRect(R.Left + I * W div 14, R.Top + I * H div 14, R.Right - I * W div 14, R.Bottom - I * H div 14, 8, 8);
      end;
      C.Brush.Style := bsClear;
      C.Pen.Style := psSolid;
      C.Pen.Width := 1;
      C.Pen.Color := StyleColor(ClothColor(Item, 2));
      C.RoundRect(R.Left + 3, R.Top + 3, R.Right - 3, R.Bottom - 3, 6, 6);
    end;
  else
    begin
      { the moon in a night sky }
      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(22, 14, 36);
      C.Pen.Style := psSolid;
      C.Pen.Width := 1;
      C.Pen.Color := RGBToColor(80, 64, 40);
      C.RoundRect(R.Left, R.Top, R.Right, R.Bottom, 8, 8);
      CX := (R.Left + R.Right) div 2;
      CY := (R.Top + R.Bottom) div 2;
      Rad := Min(W, H) * 3 div 10;
      C.Brush.Color := StyleColor(MoonColor(Item, 0));
      C.Pen.Color := C.Brush.Color;
      C.Ellipse(CX - Rad, CY - Rad, CX + Rad, CY + Rad);
      if MoonColor(Item, 1) >= 0 then
      begin
        C.Brush.Style := bsClear;
        C.Pen.Color := StyleColor(MoonColor(Item, 1));
        C.Pen.Width := Max(1, Rad div 7);
        C.Ellipse(CX - Rad - 1, CY - Rad - 1, CX + Rad + 1, CY + Rad + 1);
        C.Pen.Width := 1;
      end;
    end;
  end;
  C.Brush.Style := bsClear;
end;

function TStoreView.Icon(Art, Size: Integer): TBitmap;
var
  I: Integer;
begin
  if FIconSize <> Size then
  begin
    for I := 0 to OverlayArtCount - 1 do
    begin
      FIcons[I].Free;
      FIcons[I] := nil;
    end;
    FIconSize := Size;
  end;
  if FMasters[Art] = nil then FMasters[Art] := LoadResourceImage('special_' + ArtKey[Art]);
  if FIcons[Art] = nil then
    FIcons[Art] := ScaleToBitmap(FMasters[Art], Round(Size * 164 / 232), Size);
  Result := FIcons[Art];
end;

{ Text clipped to R, as one line. }
procedure TStoreView.TextIn(C: TCanvas; const R: TRect; const S: string);
begin
  C.TextRect(R, R.Left, R.Top, S);
end;

procedure TStoreView.Draw(C: TCanvas; Ctl: TGameController; Shade: TSceneView;
  const Full: TRect);
var
  P, R, B, Sp, Pt, IconR: TRect;
  I, N, Th, RowH, IconH, Y, X, TW: Integer;
  K: Double;
  Row: TOverlayRow;
  Lines: TStringList;
  S: string;
begin
  if Ctl.Overlay = okNone then Exit;
  Shade.DrawOverlay(C, Full, RGBToColor(0, 0, 0), 0.72);
  P := Ctl.OverlayPanelRect;
  K := Min((P.Right - P.Left) / 1100, (P.Bottom - P.Top) / 560);
  if K < 0.7 then K := 0.7;
  if K > 1.5 then K := 1.5;
  Th := Max(1, Round(2 * K));

  { the panel }
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(22, 13, 28);
  C.Pen.Style := psSolid;
  C.Pen.Width := Th;
  C.Pen.Color := Gold;
  C.RoundRect(P.Left, P.Top, P.Right, P.Bottom, Round(16 * K), Round(16 * K));
  C.Pen.Width := 1;
  C.Pen.Color := RGBToColor(110, 90, 46);
  C.Brush.Style := bsClear;
  C.RoundRect(P.Left + Th * 3, P.Top + Th * 3, P.Right - Th * 3, P.Bottom - Th * 3,
    Round(12 * K), Round(12 * K));
  C.Font.Name := FontName;

  { his portrait }
  Pt := Ctl.OverlayPortraitRect;
  if Pt.Right > Pt.Left then
    C.Draw(Pt.Left, Pt.Top, PortraitBmp(Pt.Right - Pt.Left, Pt.Bottom - Pt.Top));

  { his words (or the tray's help) }
  Sp := Ctl.OverlaySpeechRect;
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(30, 19, 38);
  C.Pen.Color := RGBToColor(110, 90, 46);
  C.RoundRect(Sp.Left, Sp.Top, Sp.Right, Sp.Bottom, Round(10 * K), Round(10 * K));
  C.Brush.Style := bsClear;
  Y := Sp.Top + Round(8 * K);
  X := Sp.Left + Round(12 * K);
  if Ctl.Overlay = okStore then
  begin
    C.Font.Size := Max(10, Round(15 * K));
    C.Font.Style := [fsBold, fsItalic];
    C.Font.Color := Gold;
    C.TextOut(X, Y, Ctl.ShopkeeperName);
    TW := C.TextWidth(Ctl.ShopkeeperName);
    C.Font.Size := Max(8, Round(10 * K));
    C.Font.Style := [fsItalic];
    C.Font.Color := DimGold;
    C.TextOut(X + TW + Round(10 * K), Y + Round(4 * K), Ctl.ShopkeeperTitle);
    Inc(Y, C.TextHeight('Ag') + Round(8 * K));
  end
  else
  begin
    C.Font.Size := Max(10, Round(14 * K));
    C.Font.Style := [fsBold];
    C.Font.Color := Gold;
    C.TextOut(X, Y, Ctl.OverlayTitle);
    Inc(Y, C.TextHeight('Ag') + Round(4 * K));
  end;
  C.Font.Size := Max(9, Round(12 * K));
  C.Font.Style := [];
  C.Font.Color := Bone;
  Lines := WrapText(C, Ctl.OverlayLine, Sp.Right - Sp.Left - Round(24 * K));
  try
    for I := 0 to Lines.Count - 1 do
    begin
      if Y + C.TextHeight('Ag') > Sp.Bottom - Round(4 * K) then Break;
      C.TextOut(X, Y, Lines[I]);
      Inc(Y, C.TextHeight('Ag'));
    end;
  finally
    Lines.Free;
  end;
  if Ctl.OverlayHint <> '' then
  begin
    C.Font.Size := Max(8, Round(9 * K));
    C.Font.Style := [fsItalic];
    C.Font.Color := DimGold;
    S := Ctl.OverlayHint;
    C.TextOut(Sp.Right - C.TextWidth(S) - Round(12 * K), Sp.Bottom - C.TextHeight(S) - Round(6 * K), S);
  end;

  { the tabs above the rows (the Style page) }
  for I := 0 to Ctl.OverlayTabCount - 1 do
  begin
    R := Ctl.OverlayTabRect(I);
    C.Brush.Style := bsSolid;
    if Ctl.OverlayTabSelected(I) then
    begin
      C.Brush.Color := RGBToColor(201, 162, 74);
      C.Pen.Color := RGBToColor(150, 118, 46);
      C.Font.Color := RGBToColor(30, 19, 38);
    end
    else
    begin
      C.Brush.Color := RGBToColor(30, 19, 38);
      C.Pen.Color := RGBToColor(110, 90, 46);
      C.Font.Color := Bone;
    end;
    C.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Round(8 * K), Round(8 * K));
    C.Brush.Style := bsClear;
    C.Font.Size := Max(9, Round(12 * K));
    C.Font.Style := [fsBold];
    S := Ctl.OverlayTabCaption(I);
    C.TextOut(R.Left + ((R.Right - R.Left) - C.TextWidth(S)) div 2,
      R.Top + ((R.Bottom - R.Top) - C.TextHeight(S)) div 2, S);
  end;

  { the rows }
  N := Ctl.OverlayRowCount;
  for I := 0 to N - 1 do
  begin
    Row := Ctl.OverlayRow(I);
    R := Ctl.OverlayRowRect(I);
    B := Ctl.OverlayButtonRect(I);
    RowH := R.Bottom - R.Top;
    if Row.Header then
    begin
      { a heading: just gold text with a thin rule under it }
      C.Font.Size := Max(9, Min(Round(12 * K), (RowH - 2) * 3 div 5));
      C.Font.Style := [fsBold];
      C.Font.Color := Gold;
      C.TextOut(R.Left + 4, R.Top + (RowH - C.TextHeight('Ag')) div 2, Row.Title);
      C.Pen.Color := RGBToColor(110, 90, 46);
      C.Line(R.Left, R.Bottom - 1, R.Right, R.Bottom - 1);
      Continue;
    end;
    C.Brush.Style := bsSolid;
    if Row.Selected then C.Brush.Color := RGBToColor(46, 30, 56) else C.Brush.Color := RGBToColor(30, 19, 38);
    if Row.Selected then C.Pen.Color := Gold else C.Pen.Color := RGBToColor(80, 64, 40);
    C.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Round(8 * K), Round(8 * K));
    C.Brush.Style := bsClear;
    { the little card picture (the records page has none) }
    X := R.Left + Round(10 * K);
    if Row.Preview > 0 then
    begin
      IconH := RowH - 8;
      IconR := Rect(R.Left + 6, R.Top + 4, R.Left + 6 + Round(IconH * 164 / 232), R.Top + 4 + IconH);
      DrawPreview(C, IconR, Row.Preview, K);
      X := IconR.Right + Round(10 * K);
    end
    else if Row.Art >= 0 then
    begin
      IconH := RowH - 8;
      IconR := Rect(R.Left + 6, R.Top + 4, R.Left + 6 + Round(IconH * 164 / 232), R.Top + 4 + IconH);
      if Row.Art = ArtTrophyEmpty then
      begin
        { a trophy not earned yet: an empty tile, the same shape as the pictures }
        C.Brush.Style := bsSolid;
        C.Brush.Color := RGBToColor(22, 13, 28);
        C.Pen.Color := RGBToColor(110, 90, 46);
        C.RoundRect(IconR.Left, IconR.Top, IconR.Right, IconR.Bottom, Max(4, IconH div 8), Max(4, IconH div 8));
        C.Brush.Style := bsClear;
        C.Font.Size := Max(8, IconH div 2);
        C.Font.Style := [fsBold];
        C.Font.Color := RGBToColor(110, 90, 46);
        C.TextOut(IconR.Left + ((IconR.Right - IconR.Left) - C.TextWidth('?')) div 2,
          IconR.Top + (IconH - C.TextHeight('?')) div 2, '?');
      end
      else
        C.Draw(IconR.Left, IconR.Top, Icon(Row.Art, IconH));
      X := IconR.Right + Round(10 * K);
    end;
    if Row.Button2Text <> '' then TW := Ctl.OverlayButton2Rect(I).Left - 12
    else if Row.ButtonText <> '' then TW := B.Left - 70
    else if Row.Aside = '' then TW := R.Right - 12
    else TW := R.Right - 150;
    C.Font.Style := [fsBold];
    C.Font.Color := Bone;
    if RowH >= 28 then
    begin
      C.Font.Size := Max(9, Min(Round(13 * K), (RowH - 4) * 3 div 8));
      TextIn(C, Rect(X, R.Top + 3, TW, R.Top + 3 + C.TextHeight('Ag')), Row.Title);
      C.Font.Size := Max(8, Min(Round(10 * K), (RowH - 4) * 3 div 11));
      C.Font.Style := [];
      C.Font.Color := DimGold;
      TextIn(C, Rect(X, R.Top + 3 + C.TextHeight('Ag') + 1, TW, R.Bottom - 2), Row.Detail);
    end
    else
    begin
      C.Font.Size := Max(9, Min(Round(13 * K), (RowH - 2) * 3 div 5));       { short rows: one line }
      TextIn(C, Rect(X, R.Top + (RowH - C.TextHeight('Ag')) div 2, TW, R.Bottom - 1), Row.Title);
    end;
    { price, count or record }
    C.Font.Size := Max(9, Min(Round(12 * K), (RowH - 2) * 3 div 5));
    C.Font.Style := [fsBold];
    C.Font.Color := Gold;
    S := Row.Aside;
    if Row.ButtonText <> '' then
      C.TextOut(B.Left - C.TextWidth(S) - Round(10 * K), R.Top + (RowH - C.TextHeight(S)) div 2, S)
    else
      C.TextOut(R.Right - C.TextWidth(S) - Round(12 * K), R.Top + (RowH - C.TextHeight(S)) div 2, S);
    { the button }
    if Row.ButtonText <> '' then
    begin
      C.Brush.Style := bsSolid;
      if Row.ButtonEnabled then
      begin
        C.Brush.Color := RGBToColor(201, 162, 74);
        C.Pen.Color := RGBToColor(150, 118, 46);
        C.Font.Color := RGBToColor(30, 19, 38);
      end
      else
      begin
        C.Brush.Color := RGBToColor(46, 36, 54);
        C.Pen.Color := RGBToColor(70, 58, 44);
        C.Font.Color := RGBToColor(110, 98, 84);
      end;
      C.RoundRect(B.Left, B.Top, B.Right, B.Bottom, Round(8 * K), Round(8 * K));
      C.Brush.Style := bsClear;
      C.Font.Size := Max(9, Round(12 * K));
      C.Font.Style := [fsBold];
      S := Row.ButtonText;
      C.TextOut(B.Left + ((B.Right - B.Left) - C.TextWidth(S)) div 2,
        B.Top + ((B.Bottom - B.Top) - C.TextHeight(S)) div 2, S);
    end;
    { the second, smaller button (Delete on a saved game) }
    if Row.Button2Text <> '' then
    begin
      B := Ctl.OverlayButton2Rect(I);
      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(46, 30, 56);
      if Row.Button2Enabled then C.Pen.Color := RGBToColor(196, 60, 76) else C.Pen.Color := RGBToColor(70, 58, 44);
      C.RoundRect(B.Left, B.Top, B.Right, B.Bottom, Round(8 * K), Round(8 * K));
      C.Brush.Style := bsClear;
      C.Font.Size := Max(9, Round(12 * K));
      C.Font.Style := [fsBold];
      if Row.Button2Enabled then C.Font.Color := Bone else C.Font.Color := RGBToColor(110, 98, 84);
      S := Row.Button2Text;
      C.TextOut(B.Left + ((B.Right - B.Left) - C.TextWidth(S)) div 2,
        B.Top + ((B.Bottom - B.Top) - C.TextHeight(S)) div 2, S);
    end;
  end;

  { coins and the Leave / Close button }
  R := Ctl.OverlayFooterRect;
  C.Font.Size := Max(10, Round(14 * K));
  C.Font.Style := [fsBold];
  C.Font.Color := Gold;
  C.TextOut(R.Left, R.Top + ((R.Bottom - R.Top) - C.TextHeight('Ag')) div 2, Ctl.OverlayFooter);
  for I := 0 to Ctl.OverlayExtraCount - 1 do         { buttons beside Leave: the Store's Relics and Style }
  begin
    R := Ctl.OverlayExtraRect(I);
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(42, 29, 54);
    C.Pen.Color := RGBToColor(110, 90, 46);
    C.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Round(8 * K), Round(8 * K));
    C.Brush.Style := bsClear;
    C.Font.Color := Bone;
    S := Ctl.OverlayExtraCaption(I);
    C.TextOut(R.Left + ((R.Right - R.Left) - C.TextWidth(S)) div 2,
      R.Top + ((R.Bottom - R.Top) - C.TextHeight(S)) div 2, S);
  end;
  R := Ctl.OverlayLeaveRect;
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(42, 29, 54);
  C.Pen.Color := Gold;
  C.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Round(8 * K), Round(8 * K));
  C.Brush.Style := bsClear;
  C.Font.Color := Bone;
  S := Ctl.OverlayLeaveCaption;
  C.TextOut(R.Left + ((R.Right - R.Left) - C.TextWidth(S)) div 2,
    R.Top + ((R.Bottom - R.Top) - C.TextHeight(S)) div 2, S);
  C.Brush.Style := bsSolid;
end;

end.
