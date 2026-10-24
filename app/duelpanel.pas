unit DuelPanel;

{ The duel panel: a framed column on the left of the table showing who you are
  fighting, how many wins he has taken, and what the next win pays. UI code (uses Graphics); every
  number comes from DuelInfo. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Graphics, DuelInfo, SceneView, Trophies, Vampires;

{ Draws the panel filling R. View supplies (and caches) the portrait. In a duel
  (Info.Active) it shows the vampire; otherwise (Free Play) what a hand pays.
  Either way the stats block (cards left, stock, streak, turn-overs, coins) is at the foot. }
procedure DrawDuelPanel(C: TCanvas; const R: TRect; const Info: TDuelInfo;
  const Stats: TPanelStats; View: TSceneView);

implementation

const
  FontName = 'Times New Roman';

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

function Blood: TColor;
begin
  Result := RGBToColor(214, 80, 92);
end;

{ Draws Text centred across [Left, Right) at Y; returns the height used. }
function CenterText(C: TCanvas; Left, Right, Y: Integer; const Text: string): Integer;
begin
  C.TextOut(Left + ((Right - Left) - C.TextWidth(Text)) div 2, Y, Text);
  Result := C.TextHeight(Text);
end;

{ Wrapped, centred paragraph; returns the height used. }
function CenterWrapped(C: TCanvas; Left, Right, Y: Integer; const Text: string): Integer;
var
  L: TStringList;
  I, H: Integer;
begin
  Result := 0;
  L := WrapText(C, Text, Right - Left);
  try
    H := C.TextHeight('Ag');
    for I := 0 to L.Count - 1 do
    begin
      CenterText(C, Left, Right, Y + Result, L[I]);
      Inc(Result, H);
    end;
  finally
    L.Free;
  end;
end;

{ A label on the left and a value on the right of the same row. }
procedure Row(C: TCanvas; Left, Right, Y: Integer; const LabelText, Value: string;
  ValueColor: TColor);
begin
  C.Font.Color := DimGold;
  C.TextOut(Left, Y, LabelText);
  C.Font.Color := ValueColor;
  C.TextOut(Right - C.TextWidth(Value), Y, Value);
end;

{ Free Play: no vampire, just what the hand pays. }
procedure DrawFreePlay(C: TCanvas; X0, X1, Y, Bottom: Integer; K: Double;
  const S: TPanelStats; View: TSceneView);
var
  Txt: string;
  RowH: Integer;
begin
  C.Font.Name := FontName;
  C.Font.Size := Max(7, Round(10 * K));
  C.Font.Style := [fsBold];
  C.Font.Color := DimGold;
  Inc(Y, CenterText(C, X0, X1, Y, 'FREE PLAY'));
  Inc(Y, Round(10 * K));
  C.Pen.Style := psSolid;
  C.Pen.Width := 1;
  C.Pen.Color := RGBToColor(110, 90, 46);
  C.Line(X0, Y, X1, Y);
  Inc(Y, Round(8 * K));
  C.Font.Size := Max(7, Round(9 * K));
  Inc(Y, CenterText(C, X0, X1, Y, 'THIS HAND PAYS'));
  C.Font.Size := Max(7, Round(26 * K));
  C.Font.Color := Bone;
  if S.PayNow = 1 then Txt := '1 coin' else Txt := IntToStr(S.PayNow) + ' coins';
  Inc(Y, CenterText(C, X0, X1, Y, Txt));
  Inc(Y, Round(6 * K));
  C.Font.Size := Max(7, Round(11 * K));
  C.Font.Style := [];
  RowH := C.TextHeight('Ag') + Round(2 * K);
  Row(C, X0, X1, Y, 'Each win', '+' + IntToStr(S.PerWin), Bone);
  Inc(Y, RowH);
  if S.MissCut > 0 then
  begin
    Row(C, X0, X1, Y, Format('Missed moves (%d)', [S.Misses]), '-' + IntToStr(S.MissCut), Blood);
    Inc(Y, RowH);
  end;
  { the house fills what is left of the panel }
  Inc(Y, Round(8 * K));
  if Bottom - Round(8 * K) - Y >= Round(60 * K) then
    View.DrawHouseFramed(C, Rect(X0, Y, X1, Bottom - Round(8 * K)));
end;

{ Two label/value pairs on one row. }
procedure Pair(C: TCanvas; Left, Right, Y: Integer; const L1, V1, L2, V2: string);
var
  Mid, Gap: Integer;
begin
  Mid := (Left + Right) div 2;
  Gap := Max(4, (Right - Left) div 14);
  Row(C, Left, Mid - Gap, Y, L1, V1, Bone);
  Row(C, Mid + Gap, Right, Y, L2, V2, Bone);
end;

{ How tall the stats block is at scale K. }
function StatsHeight(C: TCanvas; K: Double): Integer;
begin
  C.Font.Name := FontName;
  C.Font.Style := [];
  C.Font.Size := Max(7, Round(11 * K));
  Result := Round(10 * K) + 3 * (C.TextHeight('Ag') + Round(2 * K));
end;

{ The trophy shelf: a divider, then a small card for each trophy (an empty tile
  for one not earned yet). Tapping it opens the trophy page (the controller). }
procedure DrawTrophyShelf(C: TCanvas; const L: TTrophyLayout; const S: TPanelStats;
  View: TSceneView);
var
  I: Integer;
begin
  if L.Shelf.Right <= L.Shelf.Left then Exit;
  C.Pen.Style := psSolid;
  C.Pen.Width := 1;
  C.Pen.Color := RGBToColor(110, 90, 46);
  C.Line(L.Shelf.Left, L.Shelf.Top - Max(2, (L.Reserved - (L.Shelf.Bottom - L.Shelf.Top)) div 2),
    L.Shelf.Right, L.Shelf.Top - Max(2, (L.Reserved - (L.Shelf.Bottom - L.Shelf.Top)) div 2));
  for I := 0 to TrophyCount - 1 do
    View.DrawTrophy(C, I, L.Slots[I], (S.Trophies shr I) and 1 = 1);
end;

{ A divider and the numbers: cards left and stock, streak and best, coins. }
procedure DrawStats(C: TCanvas; X0, X1, Y: Integer; K: Double; const S: TPanelStats);
var
  RowH: Integer;
begin
  C.Pen.Style := psSolid;
  C.Pen.Width := 1;
  C.Pen.Color := RGBToColor(110, 90, 46);
  C.Line(X0, Y, X1, Y);
  Inc(Y, Round(6 * K));
  C.Font.Name := FontName;
  C.Font.Size := Max(7, Round(11 * K));
  C.Font.Style := [];
  RowH := C.TextHeight('Ag') + Round(2 * K);
  Pair(C, X0, X1, Y, 'Cards left', IntToStr(S.Remaining), 'Stock', IntToStr(S.Stock));
  Inc(Y, RowH);
  Pair(C, X0, X1, Y, 'Streak', IntToStr(S.Streak), 'Best', IntToStr(S.BestStreak));
  Inc(Y, RowH);
  Pair(C, X0, X1, Y, 'Turn-overs', IntToStr(S.Recycles), 'Coins', IntToStr(S.Coins));
end;

procedure DrawDuelPanel(C: TCanvas; const R: TRect; const Info: TDuelInfo;
  const Stats: TPanelStats; View: TSceneView);
var
  W, H, Pad, X0, X1, Y, PH, PW, Th, RowH, Bottom, I, D, Gap, PX: Integer;
  K: Double;
  PR: TRect;
  TL: TTrophyLayout;
  S: string;

  function F(Size: Double): Integer;
  begin
    Result := Max(7, Round(Size * K));
  end;

begin
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  K := Min(W / 248, H / 524);
  if K < 0.5 then K := 0.5;
  Pad := Round(14 * K);
  Th := Max(1, Round(2 * K));
  X0 := R.Left + Pad;
  X1 := R.Right - Pad;
  TL := TrophyLayoutFor(R, False);
  Bottom := R.Bottom - Pad - TL.Reserved - StatsHeight(C, K);   { the stats block, and the trophy shelf under it, sit below }

  { the frame }
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(22, 13, 28);
  C.Pen.Style := psSolid;
  C.Pen.Width := Th;
  C.Pen.Color := Gold;
  C.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Round(14 * K), Round(14 * K));
  C.Pen.Width := 1;
  C.Pen.Color := RGBToColor(110, 90, 46);
  C.Brush.Style := bsClear;
  C.RoundRect(R.Left + Th * 3, R.Top + Th * 3, R.Right - Th * 3, R.Bottom - Th * 3,
    Round(10 * K), Round(10 * K));
  C.Font.Name := FontName;

  Y := R.Top + Pad;
  DrawStats(C, X0, X1, R.Bottom - Pad - TL.Reserved - StatsHeight(C, K) + Round(2 * K), K, Stats);
  DrawTrophyShelf(C, TL, Stats, View);
  C.Brush.Style := bsClear;
  if not Info.Active then
  begin
    DrawFreePlay(C, X0, X1, Y, Bottom, K, Stats, View);
    C.Brush.Style := bsSolid;
    Exit;
  end;

  { which duel }
  C.Font.Size := F(10);
  C.Font.Style := [fsBold];
  C.Font.Color := DimGold;
  Inc(Y, CenterText(C, X0, X1, Y, Format('DUEL %d OF %d', [Info.DuelNumber, Info.DuelCount])));
  Inc(Y, Round(6 * K));

  { the portrait: as tall as fits, but never more than 36% of the panel; when
    stuck, smaller (26%) so the prompt at the bottom always has room }
  if Info.StuckWaiting then PH := Round(H * 0.20) else PH := Round(H * 0.28);
  PH := PH - Round(TL.Reserved * 0.6);                { the shelf needs room too }
  PH := Min(Round((X1 - X0) * 878 / 596), PH);
  PW := Round(PH * 596 / 878);
  PR := Rect(R.Left + (W - PW) div 2, Y, R.Left + (W - PW) div 2 + PW, Y + PH);
  View.DrawPortraitIn(C, Info.Vampire, PR, 1);
  Inc(Y, PH + Round(8 * K));

  { name and title }
  C.Font.Size := F(15);
  C.Font.Style := [fsBold, fsItalic];
  C.Font.Color := Gold;
  Inc(Y, CenterWrapped(C, X0, X1, Y, Info.Name));
  C.Font.Size := F(11);
  C.Font.Style := [fsItalic];
  C.Font.Color := DimGold;
  Inc(Y, CenterWrapped(C, X0, X1, Y, Info.Title));
  Inc(Y, Round(6 * K));

  { the wins so far: one pip each, filled for a win }
  D := Max(6, Round(11 * K));
  Gap := Max(4, Round(7 * K));
  PX := R.Left + (W - (Info.WinsNeeded * D + (Info.WinsNeeded - 1) * Gap)) div 2;
  C.Pen.Style := psSolid;
  C.Pen.Width := Max(1, Round(K));
  C.Pen.Color := Gold;
  for I := 1 to Info.WinsNeeded do
  begin
    if I <= Info.Wins then
    begin
      C.Brush.Style := bsSolid;
      C.Brush.Color := Gold;
    end
    else
      C.Brush.Style := bsClear;
    C.Ellipse(PX, Y, PX + D, Y + D);
    Inc(PX, D + Gap);
  end;
  C.Brush.Style := bsClear;
  Inc(Y, D + Round(3 * K));
  C.Font.Size := F(10);
  C.Font.Style := [fsBold];
  C.Font.Color := DimGold;
  Inc(Y, CenterText(C, X0, X1, Y, Format('WINS %d OF %d', [Info.Wins, Info.WinsNeeded])));
  Inc(Y, Round(6 * K));

  { divider }
  C.Pen.Color := RGBToColor(110, 90, 46);
  C.Line(X0, Y, X1, Y);
  Inc(Y, Round(8 * K));

  { what the next win pays (the fifth is the kill) }
  C.Font.Size := F(9);
  C.Font.Style := [fsBold];
  C.Font.Color := DimGold;
  if Info.KillBonus > 0 then S := 'THE KILL PAYS' else S := 'THIS WIN PAYS';
  Inc(Y, CenterText(C, X0, X1, Y, S));
  C.Font.Size := F(26);
  C.Font.Style := [fsBold];
  C.Font.Color := Bone;
  if Info.PayNow = 1 then S := '1 coin' else S := IntToStr(Info.PayNow) + ' coins';
  Inc(Y, CenterText(C, X0, X1, Y, S));
  if Info.AtFloor then
  begin
    C.Font.Size := F(9);
    C.Font.Style := [fsItalic];
    C.Font.Color := DimGold;
    Inc(Y, CenterText(C, X0, X1, Y, '(the minimum)'));
  end;
  Inc(Y, Round(6 * K));

  { where it comes from }
  C.Font.Size := F(11);
  C.Font.Style := [];
  RowH := C.TextHeight('Ag') + Round(2 * K);
  Row(C, X0, X1, Y, 'Each win', '+' + IntToStr(Info.PerWin), Bone);
  Inc(Y, RowH);
  if Info.KillBonus > 0 then
  begin
    Row(C, X0, X1, Y, 'Kill bonus', '+' + IntToStr(Info.KillBonus), Bone);
    Inc(Y, RowH);
  end;
  if Info.LostHandsCut > 0 then
  begin
    Row(C, X0, X1, Y, Format('Lost hands (%d)', [Info.LostHands]), '-' + IntToStr(Info.LostHandsCut), Blood);
    Inc(Y, RowH);
  end;
  if Info.MissCut > 0 then
  begin
    Row(C, X0, X1, Y, Format('Missed moves (%d)', [Info.Misses]), '-' + IntToStr(Info.MissCut), Blood);
    Inc(Y, RowH);
  end;
  if Info.BiteCut > 0 then
  begin
    Row(C, X0, X1, Y, Format('Bitten cards (%d)', [Info.Bites]), '-' + IntToStr(Info.BiteCut), Blood);
    Inc(Y, RowH);
  end;

  { this vampire's rules: what makes his hands harder (one quiet line) }
  Inc(Y, Round(4 * K));
  C.Font.Size := F(10);
  C.Font.Style := [fsItalic];
  C.Font.Color := DimGold;
  if Info.Easy then S := 'the Easy rule' else S := 'plain Pyramid';
  Inc(Y, CenterWrapped(C, X0, X1, Y, TurnOvers(Info.Recycles) + ' of the stock; ' + S));
  if Info.HazardText <> '' then                       { and his trick }
  begin
    C.Font.Color := Blood;
    Inc(Y, CenterWrapped(C, X0, X1, Y, Info.HazardText));
  end;
  if Info.CrossText <> '' then                        { the silver cross }
  begin
    C.Font.Color := RGBToColor(205, 208, 224);
    Inc(Y, CenterWrapped(C, X0, X1, Y, Info.CrossText));
  end;

  { stuck, with an undo card that could still help }
  if Info.StuckWaiting then
  begin
    Inc(Y, Round(6 * K));
    C.Font.Size := F(11);
    C.Font.Style := [fsBold];
    C.Font.Color := Blood;
    if Y + 3 * C.TextHeight('Ag') <= Bottom then
      CenterWrapped(C, X0, X1, Y, 'No moves left. Use an undo or special card, or press New Game to concede.');
  end;
  C.Brush.Style := bsSolid;
end;

end.
