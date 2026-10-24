unit SceneView;

{ Draws the duel scenes (see Scenes/Stage): a dark room with the vampire's
  portrait, a name plate and a box of text. UI code (uses Graphics); all the
  numbers it draws come from the Stage. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Graphics, IntfGraphics, GraphType, FPImage,
  Stage, Vampires, CardImages, Trophies;

const
  PortraitLevels = 12;               { brightness steps for fading a portrait }

{ Cuts S into lines no wider than MaxW pixels on C (its font must be set). The
  caller frees the list. }
function WrapText(C: TCanvas; const S: string; MaxW: Integer): TStringList;

type
  TSceneView = class
  private
    FMasters: array[0..PortraitCount - 1] of TFPMemoryImage;
    FScaled: array[0..PortraitCount - 1] of TFPMemoryImage;   { at the current size }
    FScaledW, FScaledH: array[0..PortraitCount - 1] of Integer;
    FShaded: array[0..PortraitCount - 1, 0..PortraitLevels] of TBitmap;
    FHouseKey: string;               { which house picture: the moon's colour (Cosmetics.HouseImageKey) }
    FHouseMaster: TFPMemoryImage;
    FHouse: TBitmap;                 { the house, scaled to cover FHouseW x FHouseH }
    FHouseW, FHouseH: Integer;
    FPanelHouse: TBitmap;            { the house cropped to fit the Free Play panel }
    FPanelHouseW, FPanelHouseH: Integer;
    FTrophyMasters: array[0..TrophyCount - 1] of TFPMemoryImage;
    FTrophyBmps: array[0..TrophyCount - 1] of TBitmap;     { at FTrophyH }
    FTrophyH: Integer;
    function Portrait(V, W, H: Integer; Brightness: Double): TBitmap;
    procedure DrawTextBox(C: TCanvas; const R: TRect; St: TStage; K: Double);
  public
    destructor Destroy; override;
    { Lays a see-through colour over R (Alpha 0 = nothing, 1 = solid). }
    procedure DrawOverlay(C: TCanvas; const R: TRect; Color: TColor; Alpha: Double);
    { The whole dialogue scene, filling R. }
    procedure DrawDialogue(C: TCanvas; const R: TRect; St: TStage);
    { The story's opening: the house on the hill with a box of text. }
    procedure DrawHouseScene(C: TCanvas; const R: TRect; St: TStage);
    { Which house picture to use; the pictures are rebuilt only when it changes. }
    procedure SetHouse(const AKey: string);
    { The house picture alone, filling R (cropped to fit), darkened by Dark (0..1). }
    procedure DrawHousePicture(C: TCanvas; const R: TRect; Dark: Double);
    { The house, the middle of the picture, framed to fill R (the Free Play panel). }
    procedure DrawHouseFramed(C: TCanvas; const R: TRect);
    { Trophy I as a small card picture, as tall as R and centred in it; a trophy
      not earned yet is an empty outlined tile of the same shape. }
    procedure DrawTrophy(C: TCanvas; I: Integer; const R: TRect; Earned: Boolean);
    { A vampire's portrait scaled to fill R (Brightness 1 = fully lit). }
    procedure DrawPortraitIn(C: TCanvas; V: Integer; const R: TRect;
      Brightness: Double);
  end;

implementation

const
  FontName = 'Times New Roman';      { a serif on both Windows and Linux }

destructor TSceneView.Destroy;
var
  V, L: Integer;
begin
  for V := 0 to PortraitCount - 1 do
  begin
    FMasters[V].Free;
    FScaled[V].Free;
    for L := 0 to PortraitLevels do FShaded[V, L].Free;
  end;
  FHouseMaster.Free;
  FHouse.Free;
  FPanelHouse.Free;
  for L := 0 to TrophyCount - 1 do
  begin
    FTrophyMasters[L].Free;
    FTrophyBmps[L].Free;
  end;
  inherited Destroy;
end;

procedure TSceneView.DrawOverlay(C: TCanvas; const R: TRect; Color: TColor;
  Alpha: Double);
var
  Li: TLazIntfImage;
  Bmp: TBitmap;
  X, Y, A: Integer;
  P: TFPColor;
begin
  if Alpha <= 0.004 then Exit;
  if Alpha >= 0.996 then
  begin
    C.Brush.Style := bsSolid;
    C.Brush.Color := Color;
    C.FillRect(R);
    Exit;
  end;
  A := Round(Alpha * 255);
  P.Red := Red(Color) * 257;
  P.Green := Green(Color) * 257;
  P.Blue := Blue(Color) * 257;
  P.Alpha := A * 257;
  Li := TLazIntfImage.Create(4, 4, [riqfRGB, riqfAlpha]);
  try
    for Y := 0 to 3 do
      for X := 0 to 3 do Li.Colors[X, Y] := P;
    Bmp := TBitmap.Create;
    try
      Bmp.LoadFromIntfImage(Li);
      C.StretchDraw(R, Bmp);
    finally
      Bmp.Free;
    end;
  finally
    Li.Free;
  end;
end;

{ The vampire's portrait at W x H, darkened to Brightness (0..1). The scaled
  picture is kept per size, and each brightness step is made once. }
procedure TSceneView.SetHouse(const AKey: string);
begin
  if AKey = FHouseKey then Exit;
  FHouseKey := AKey;
  FreeAndNil(FHouseMaster);
  FreeAndNil(FHouse);
  FreeAndNil(FPanelHouse);
  FHouseW := 0;
  FHouseH := 0;
  FPanelHouseW := 0;
  FPanelHouseH := 0;
end;

function TSceneView.Portrait(V, W, H: Integer; Brightness: Double): TBitmap;
var
  L, Lv: Integer;
begin
  if FMasters[V] = nil then
    FMasters[V] := LoadResourceImage(PortraitName(V));
  if (FScaled[V] = nil) or (FScaledW[V] <> W) or (FScaledH[V] <> H) then
  begin
    FScaled[V].Free;
    FScaled[V] := ScaleToImage(FMasters[V], W, H);
    FScaledW[V] := W;
    FScaledH[V] := H;
    for L := 0 to PortraitLevels do
    begin
      FShaded[V, L].Free;
      FShaded[V, L] := nil;
    end;
  end;
  Lv := Round(Brightness * PortraitLevels);
  if Lv < 0 then Lv := 0;
  if Lv > PortraitLevels then Lv := PortraitLevels;
  if FShaded[V, Lv] = nil then
    FShaded[V, Lv] := ImageToBitmap(FScaled[V], Lv / PortraitLevels);
  Result := FShaded[V, Lv];
end;

{ Cuts S into lines no wider than MaxW pixels on C (its font must be set).
  Words are split on spaces by hand: TStringList.DelimitedText would treat
  double quotes as quoting characters and swallow them. }
function WrapText(C: TCanvas; const S: string; MaxW: Integer): TStringList;
var
  I, Start: Integer;
  Line, Try_, Word: string;

  procedure TakeWord(const W: string);
  begin
    if W = '' then Exit;
    if Line = '' then Try_ := W else Try_ := Line + ' ' + W;
    if (C.TextWidth(Try_) > MaxW) and (Line <> '') then
    begin
      Result.Add(Line);
      Line := W;
    end
    else
      Line := Try_;
  end;

begin
  Result := TStringList.Create;
  Line := '';
  Start := 1;
  for I := 1 to Length(S) + 1 do
    if (I > Length(S)) or (S[I] = ' ') then
    begin
      Word := Copy(S, Start, I - Start);
      TakeWord(Word);
      Start := I + 1;
    end;
  if Line <> '' then Result.Add(Line);
end;

function Lerp(A, B: Integer; T: Double): Integer;
begin
  Result := Round(A + (B - A) * T);
end;

procedure TSceneView.DrawTextBox(C: TCanvas; const R: TRect; St: TStage; K: Double);
const
  BoxR = 22; BoxG = 13; BoxB = 28;
var
  Pad, Th, NameH, AreaTop, AreaBot, Y, I, X: Integer;
  Lines: TStringList;
  Fade, Pulse: Double;
  Hint: string;
begin
  Pad := Round(16 * K);
  Th := Max(1, Round(2 * K));
  { the box }
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(BoxR, BoxG, BoxB);
  C.Pen.Style := psSolid;
  C.Pen.Width := Th;
  C.Pen.Color := RGBToColor(201, 162, 74);
  C.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Round(14 * K), Round(14 * K));
  C.Pen.Width := 1;
  C.Pen.Color := RGBToColor(110, 90, 46);
  C.Brush.Style := bsClear;
  C.RoundRect(R.Left + Th * 3, R.Top + Th * 3, R.Right - Th * 3, R.Bottom - Th * 3,
    Round(10 * K), Round(10 * K));
  C.Brush.Style := bsClear;

  AreaTop := R.Top + Pad;
  AreaBot := R.Bottom - Pad;
  NameH := 0;
  C.Font.Name := FontName;
  { name plate }
  if St.SpeakerName <> '' then
  begin
    C.Font.Size := Max(9, Round(17 * K));
    C.Font.Style := [fsBold, fsItalic];
    C.Font.Color := RGBToColor(201, 162, 74);
    C.TextOut(R.Left + Pad, AreaTop, St.SpeakerName);
    X := R.Left + Pad + C.TextWidth(St.SpeakerName) + Round(14 * K);
    NameH := C.TextHeight(St.SpeakerName);
    if St.SpeakerTitle <> '' then
    begin
      C.Font.Size := Max(8, Round(12 * K));
      C.Font.Style := [fsItalic];
      C.Font.Color := RGBToColor(150, 125, 70);
      C.TextOut(X, AreaTop + NameH - C.TextHeight(St.SpeakerTitle) - Round(2 * K), St.SpeakerTitle);
    end;
    Inc(AreaTop, NameH + Round(8 * K));
  end;

  { the line of text, faded by blending its colour into the box }
  if St.Caption <> '' then
  begin
    Fade := St.Scalar[ssTextFade];
    if Fade < 0 then Fade := 0;
    if Fade > 1 then Fade := 1;
    C.Font.Size := Max(9, Round(16 * K));
    C.Font.Style := [];
    C.Font.Color := RGBToColor(Lerp(BoxR, 232, Fade), Lerp(BoxG, 224, Fade), Lerp(BoxB, 204, Fade));
    Lines := WrapText(C, St.Caption, R.Right - R.Left - 2 * Pad);
    try
      Th := C.TextHeight('Ag');
      Y := AreaTop + (AreaBot - AreaTop - Lines.Count * Th) div 2;
      if Y < AreaTop then Y := AreaTop;
      for I := 0 to Lines.Count - 1 do
      begin
        C.TextOut(R.Left + ((R.Right - R.Left) - C.TextWidth(Lines[I])) div 2, Y, Lines[I]);
        Inc(Y, Th);
      end;
    finally
      Lines.Free;
    end;
  end;

  { waiting for the player: a small gold arrow that pulses }
  if St.WaitingForClick and (St.Scalar[ssTextFade] >= 0.99) then
  begin
    Pulse := 0.5 + 0.5 * Sin(GetTickCount64 / 260.0);
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(Lerp(110, 240, Pulse), Lerp(90, 205, Pulse), Lerp(46, 110, Pulse));
    C.Pen.Color := C.Brush.Color;
    Th := Max(4, Round(7 * K));
    X := (R.Left + R.Right) div 2;
    Y := R.Bottom - Pad - Th;
    C.Polygon([Point(X - Th, Y - Th), Point(X + Th, Y - Th), Point(X, Y + Th)]);
    C.Brush.Style := bsClear;
  end;

  { a quiet reminder }
  Hint := 'click: next line     Esc: skip';
  C.Font.Size := Max(7, Round(9 * K));
  C.Font.Style := [];
  C.Font.Color := RGBToColor(80, 66, 40);
  C.TextOut(R.Right - Pad - C.TextWidth(Hint), R.Bottom - Pad - C.TextHeight(Hint) + Round(4 * K), Hint);
end;

procedure TSceneView.DrawPortraitIn(C: TCanvas; V: Integer; const R: TRect;
  Brightness: Double);
begin
  if (V < 0) or (V >= PortraitCount) then Exit;
  C.Draw(R.Left, R.Top, Portrait(V, R.Right - R.Left, R.Bottom - R.Top, Brightness));
end;

procedure TSceneView.DrawHousePicture(C: TCanvas; const R: TRect; Dark: Double);
const
  Aspect = 1600 / 1000;                 { the picture's shape }
var
  W, H, CW, CH, SX, SY: Integer;
  Img: TFPMemoryImage;
begin
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  if (W < 4) or (H < 4) then Exit;
  if W / H > Aspect then
  begin
    CW := W;
    CH := Round(W / Aspect);
  end
  else
  begin
    CH := H;
    CW := Round(H * Aspect);
  end;
  if (FHouse = nil) or (FHouseW <> CW) or (FHouseH <> CH) then
  begin
    if FHouseMaster = nil then
      if FHouseKey = '' then FHouseMaster := LoadResourceImage('house')
      else FHouseMaster := LoadResourceImage(FHouseKey);
    Img := ScaleToImage(FHouseMaster, CW, CH);
    try
      FHouse.Free;
      FHouse := ImageToBitmap(Img, 1);
    finally
      Img.Free;
    end;
    FHouseW := CW;
    FHouseH := CH;
  end;
  SX := (CW - W) div 2;                  { cut the sides, keep the middle }
  SY := (CH - H) div 2;
  C.CopyRect(R, FHouse.Canvas, Rect(SX, SY, SX + W, SY + H));
  DrawOverlay(C, R, RGBToColor(4, 4, 10), Dark);
end;

procedure TSceneView.DrawTrophy(C: TCanvas; I: Integer; const R: TRect; Earned: Boolean);
var
  H, W, X, J: Integer;
  Img: TFPMemoryImage;
begin
  H := R.Bottom - R.Top;
  if (H < 6) or (I < 0) or (I >= TrophyCount) then Exit;
  W := Round(H * 164 / 232);
  X := R.Left + ((R.Right - R.Left) - W) div 2;
  if Earned then
  begin
    if FTrophyH <> H then
    begin
      for J := 0 to TrophyCount - 1 do
      begin
        FTrophyBmps[J].Free;
        FTrophyBmps[J] := nil;
      end;
      FTrophyH := H;
    end;
    if FTrophyBmps[I] = nil then
    begin
      if FTrophyMasters[I] = nil then
        FTrophyMasters[I] := LoadResourceImage('special_trophy_' + TrophyKeys[TTrophy(I)]);
      Img := ScaleToImage(FTrophyMasters[I], W, H);
      try
        FTrophyBmps[I] := ImageToBitmap(Img, 1);
      finally
        Img.Free;
      end;
    end;
    C.Draw(X, R.Top, FTrophyBmps[I]);
  end
  else
  begin
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(30, 19, 38);
    C.Pen.Style := psSolid;
    C.Pen.Width := 1;
    C.Pen.Color := RGBToColor(110, 90, 46);
    C.RoundRect(X, R.Top, X + W, R.Top + H, Max(3, H div 8), Max(3, H div 8));
    C.Brush.Style := bsClear;
  end;
end;

procedure TSceneView.DrawHouseFramed(C: TCanvas; const R: TRect);
var
  W, H, CW, CH, SX, SY, X, Y: Integer;
  A: Double;
  Crop, Img: TFPMemoryImage;
begin
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  if (W < 8) or (H < 8) then Exit;
  if (FPanelHouse = nil) or (FPanelHouseW <> W) or (FPanelHouseH <> H) then
  begin
    if FHouseMaster = nil then
      if FHouseKey = '' then FHouseMaster := LoadResourceImage('house')
      else FHouseMaster := LoadResourceImage(FHouseKey);
    { the part of the picture that fits R's shape, centred on the house }
    A := W / H;
    CH := FHouseMaster.Height;
    CW := Round(CH * A);
    if CW > FHouseMaster.Width then
    begin
      CW := FHouseMaster.Width;
      CH := Round(CW / A);
    end;
    SX := (FHouseMaster.Width - CW) div 2;
    SY := Round(FHouseMaster.Height * 0.52 - CH / 2);
    if SY < 0 then SY := 0;
    if SY + CH > FHouseMaster.Height then SY := FHouseMaster.Height - CH;
    Crop := TFPMemoryImage.Create(CW, CH);
    try
      for Y := 0 to CH - 1 do
        for X := 0 to CW - 1 do
          Crop.Colors[X, Y] := FHouseMaster.Colors[SX + X, SY + Y];
      Img := ScaleToImage(Crop, W, H);
    finally
      Crop.Free;
    end;
    try
      FPanelHouse.Free;
      FPanelHouse := ImageToBitmap(Img, 1);
    finally
      Img.Free;
    end;
    FPanelHouseW := W;
    FPanelHouseH := H;
  end;
  C.Draw(R.Left, R.Top, FPanelHouse);
  C.Brush.Style := bsClear;                       { a thin gold frame, like the portraits }
  C.Pen.Style := psSolid;
  C.Pen.Width := 2;
  C.Pen.Color := RGBToColor(201, 162, 74);
  C.Rectangle(R.Left, R.Top, R.Right, R.Bottom);
  C.Pen.Width := 1;
end;

procedure TSceneView.DrawHouseScene(C: TCanvas; const R: TRect; St: TStage);
var
  W, H: Integer;
  K: Double;
  Box: TRect;
begin
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  K := Min(W / 1240, H / 584);
  if K < 0.4 then K := 0.4;
  DrawHousePicture(C, R, 0.12);
  Box := Rect(Round(W * 0.10), Round(H * 0.695), Round(W * 0.90), Round(H * 0.955));
  DrawTextBox(C, Box, St, K);
  DrawOverlay(C, R, RGBToColor(255, 255, 255), St.Scalar[ssFlashWhite]);
  DrawOverlay(C, R, RGBToColor(190, 10, 20), St.Scalar[ssFlashRed]);
end;

procedure TSceneView.DrawDialogue(C: TCanvas; const R: TRect; St: TStage);
var
  W, H, PW, PH, PX, PY, Base: Integer;
  K, Slide: Double;
  Box: TRect;
begin
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  K := Min(W / 1240, H / 584);
  if K < 0.4 then K := 0.4;

  { a darker room }
  DrawOverlay(C, R, RGBToColor(4, 6, 8), 0.62);

  { the portrait, sliding in from the left, shaking, fading to dark }
  if (St.PortraitId >= 0) and (St.PortraitId < PortraitCount) then
  begin
    PH := Round(H * 0.62);
    PW := Round(PH * 596 / 878);
    PY := Round(H * 0.035);
    Base := (W - PW) div 2;
    Slide := St.Scalar[ssPortraitSlide];
    PX := Base - Round((1 - Slide) * (Base + PW)) + Round(St.Scalar[ssPortraitDX] * PW);
    C.Draw(PX, PY, Portrait(St.PortraitId, PW, PH, St.Scalar[ssPortraitFade]));
  end;

  Box := Rect(Round(W * 0.10), Round(H * 0.695), Round(W * 0.90), Round(H * 0.955));
  DrawTextBox(C, Box, St, K);

  { flashes: white for the blow, red for the vampire's free round }
  DrawOverlay(C, R, RGBToColor(255, 255, 255), St.Scalar[ssFlashWhite]);
  DrawOverlay(C, R, RGBToColor(190, 10, 20), St.Scalar[ssFlashRed]);
end;

end.
