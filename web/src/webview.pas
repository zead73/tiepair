unit WebView;

{ Draws the game on an HTML canvas: the table and cards, the "you won" picture,
  the dialogue scenes and the duel panel. It is the web counterpart of the
  desktop's MainForm painting, SceneView, DuelPanel, TableBg and CardImages;
  every number it draws comes from the GameController (and the Stage and
  DuelInfo behind it), so the two front ends cannot disagree about the game.
  Coordinates are CSS pixels; the canvas is scaled for the screen's density. }

{$mode objfpc}{$H+}

interface

uses
  JS, Web, SysUtils, Math, Types, Cards, Pyramid, Stage, Vampires, DuelInfo,
  Trophies, Cosmetics, GameController;

const
  PortraitLevels = 12;               { brightness steps for fading a portrait }

type
  TWebView = class
  private
    FCtx: TJSCanvasRenderingContext2D;
    FW, FH: Integer;                 { drawing area, CSS pixels }
    FDpr: Double;
    FCtl: TGameController;
    FBack: TJSHTMLCanvasElement;     { the card back at FBackW x FBackH }
    FBackW, FBackH, FBackStyle: Integer;    { the size and style of the cached card back }
    FShaded: array[0..PortraitCount - 1, 0..PortraitLevels] of TJSHTMLCanvasElement;
    FShadedW, FShadedH: array[0..PortraitCount - 1] of Integer;
    FTouch: Boolean;
    FOriginY: Integer;               { where the drawing area starts down the canvas (VR puts a toolbar above it) }
    procedure PaintInner(W, H: Integer; Dpr: Double);
    function Face(const C: TCard): TJSObject;
    function Portrait(V, W, H: Integer; Brightness: Double): TJSObject;
    function BackCard(W, H: Integer): TJSObject;
    procedure Rgb(const Id: string; R, G, B: Integer);
    procedure RRect(X, Y, W, H, R: Double);
    procedure SetFont(Px: Double; Bold, Italic: Boolean);
    function TextW(const S: string): Double;
    procedure Text(const S: string; X, Y: Double);
    function CenterText(Left, Right, Y: Double; const S: string; Px: Double): Double;
    function CenterWrapped(Left, Right, Y: Double; const S: string; Px: Double): Double;
    procedure FillColor(R, G, B: Integer; A: Double = 1);
    procedure StrokeColor(R, G, B: Integer);
    procedure DrawOverlay(R, G, B: Integer; Alpha: Double);
    procedure DrawTableBackground;
    procedure DrawCardBackAt(const R: TRect);
    procedure DrawCard(const R: TRect; const C: TCard; FaceUp, Playable: Boolean);
    procedure DrawTableContents;
    procedure DrawMark(const R: TRect; Kind: Integer);
    procedure DrawRing(const R: TRect; Kind: Integer);
    procedure DrawPile(const R: TRect; ACount: Integer; ARecycle: Boolean);
    procedure DrawDealing;
    procedure DrawStageCard(Slot: Integer);
    procedure DrawWinScreen(const Msg: string);
    procedure DrawDialogue;
    procedure DrawHouseCover(Dark: Double);
    procedure DrawHouseScene;
    procedure DrawMenu;
    procedure DrawTextBox(X, Y, W, H: Double; K: Double);
    procedure DrawPortraitIn(V: Integer; X, Y, W, H: Double; Brightness: Double);
    procedure DrawPanel;
    procedure DrawOverlayUi;
    procedure ClipText(const R: TRect; const S: string; X, Y: Double);
    procedure DrawPanelColumn(const R: TRect; const Info: TDuelInfo; const St: TPanelStats);
    procedure DrawPanelStrip(const R: TRect; const Info: TDuelInfo; const St: TPanelStats);
    procedure DrawStatsBlock(X0, X1, Y, K: Double; const St: TPanelStats);
    procedure DrawTrophyShelf(const L: TTrophyLayout; const St: TPanelStats);
    function BackCardStyled(W, H, AStyle: Integer): TJSObject;
    procedure DrawStylePreview(const R: TRect; P: Integer);
    procedure DrawFreeColumn(X0, X1, Y, Bottom, K: Double; const St: TPanelStats);
    procedure DrawFreeStrip(const R: TRect; const St: TPanelStats);
    procedure PanelFrame(const R: TRect; K: Double);
    procedure Pips(CX, Y: Double; const Info: TDuelInfo; K: Double);
    procedure Row(Left, Right, Y: Double; const LabelText, Value: string; Px: Double;
      R, G, B: Integer);
  public
    constructor Create(ACtx: TJSCanvasRenderingContext2D; ACtl: TGameController);
    { Draws everything for an area of W x H CSS pixels; Dpr = device pixels per
      CSS pixel (the canvas must already have that many pixels). }
    procedure Paint(W, H: Integer; Dpr: Double);
    { VR with a 3D table: only the duel panel is drawn, on a clear background (the cards,
      the cloth and the rest are 3D objects there). }
    procedure PaintHud(W, H: Integer; Dpr: Double);
    { A vampire's mark as the 2D table draws it, onto R of this view's canvas. }
    procedure DrawMarkAt(const R: TRect; Kind: Integer);
    { The card back in the chosen style, at W x H CSS pixels (cached). }
    function BackCardCanvas(W, H: Integer): TJSObject;
    property TouchScreen: Boolean read FTouch write FTouch;
    { The drawing area starts OriginY CSS pixels down the canvas, and nothing is drawn
      outside it (0 for the page's own canvas). }
    property OriginY: Integer read FOriginY write FOriginY;
  end;

implementation

const
  FontStack = '"Times New Roman", Georgia, "Liberation Serif", serif';
  PtToPx = 4 / 3;                    { the desktop's sizes are in points }

function Lerp(A, B: Integer; T: Double): Integer;
begin
  Result := Round(A + (B - A) * T);
end;

function ImageOf(const Key: string): TJSObject; external name 'TCGlue.getImage';

procedure GradStop(Gr: TJSCanvasGradient; Pos: Double; const Col: string);
begin
  asm
    Gr.addColorStop(Pos, Col);
  end;
end;

constructor TWebView.Create(ACtx: TJSCanvasRenderingContext2D; ACtl: TGameController);
begin
  inherited Create;
  FCtx := ACtx;
  FCtl := ACtl;
  FDpr := 1;
end;

{ ---- small drawing helpers ---- }

procedure TWebView.FillColor(R, G, B: Integer; A: Double);
begin
  if A >= 1 then
    FCtx.fillStyle := Format('rgb(%d,%d,%d)', [R, G, B])
  else
    FCtx.fillStyle := Format('rgba(%d,%d,%d,%s)', [R, G, B, FloatToStr(A)]);
end;

procedure TWebView.StrokeColor(R, G, B: Integer);
begin
  FCtx.strokeStyle := Format('rgb(%d,%d,%d)', [R, G, B]);
end;

procedure TWebView.Rgb(const Id: string; R, G, B: Integer);
begin
  if Id = 'fill' then FillColor(R, G, B) else StrokeColor(R, G, B);
end;

{ A rounded-rectangle path (not drawn yet). }
procedure TWebView.RRect(X, Y, W, H, R: Double);
begin
  if R > W / 2 then R := W / 2;
  if R > H / 2 then R := H / 2;
  FCtx.beginPath;
  FCtx.moveTo(X + R, Y);
  FCtx.arcTo(X + W, Y, X + W, Y + H, R);
  FCtx.arcTo(X + W, Y + H, X, Y + H, R);
  FCtx.arcTo(X, Y + H, X, Y, R);
  FCtx.arcTo(X, Y, X + W, Y, R);
  FCtx.closePath;
end;

procedure TWebView.SetFont(Px: Double; Bold, Italic: Boolean);
var
  S: string;
begin
  S := '';
  if Italic then S := 'italic ';
  if Bold then S := S + 'bold ';
  FCtx.font := S + IntToStr(Round(Px)) + 'px ' + FontStack;
end;

function TWebView.TextW(const S: string): Double;
begin
  Result := FCtx.measureText(S).width;
end;

procedure TWebView.Text(const S: string; X, Y: Double);
begin
  FCtx.fillText(S, X, Y);
end;

{ Centred across [Left, Right) at Y; returns the line height used. }
function TWebView.CenterText(Left, Right, Y: Double; const S: string; Px: Double): Double;
begin
  Text(S, Left + ((Right - Left) - TextW(S)) / 2, Y);
  Result := Px * 1.22;
end;

{ Cuts S into lines no wider than MaxW (the font must be set). }
function WrapLines(V: TWebView; const S: string; MaxW: Double): TJSArray; forward;

{ A wrapped, centred paragraph; returns the height used. }
function TWebView.CenterWrapped(Left, Right, Y: Double; const S: string; Px: Double): Double;
var
  Lines: TJSArray;
  I: Integer;
begin
  Lines := WrapLines(Self, S, Right - Left);
  Result := 0;
  for I := 0 to Lines.length - 1 do
  begin
    CenterText(Left, Right, Y + Result, string(Lines[I]), Px);
    Result := Result + Px * 1.22;
  end;
end;

function WrapLines(V: TWebView; const S: string; MaxW: Double): TJSArray;
var
  I, Start: Integer;
  Line, Attempt, Word: string;

  procedure TakeWord(const W: string);
  begin
    if W = '' then Exit;
    if Line = '' then Attempt := W else Attempt := Line + ' ' + W;
    if (V.TextW(Attempt) > MaxW) and (Line <> '') then
    begin
      Result.push(Line);
      Line := W;
    end
    else
      Line := Attempt;
  end;

begin
  Result := TJSArray.new;
  Line := '';
  Start := 1;
  for I := 1 to Length(S) + 1 do
    if (I > Length(S)) or (S[I] = ' ') then
    begin
      Word := Copy(S, Start, I - Start);
      TakeWord(Word);
      Start := I + 1;
    end;
  if Line <> '' then Result.push(Line);
end;

procedure TWebView.DrawOverlay(R, G, B: Integer; Alpha: Double);
begin
  if Alpha <= 0.004 then Exit;
  if Alpha > 1 then Alpha := 1;
  FillColor(R, G, B, Alpha);
  FCtx.fillRect(0, 0, FW, FH);
end;

{ ---- pictures ---- }

function TWebView.Face(const C: TCard): TJSObject;
const
  Suits: array[TSuit] of string = ('clubs', 'diamonds', 'hearts', 'spades');
begin
  Result := ImageOf('card_' + Suits[C.Suit] + '_' + Format('%.2d', [C.Rank]));
end;

{ The vampire's portrait, darkened to Brightness (0..1). Each brightness is made
  once per size on a hidden canvas: only the picture's own pixels are darkened. }
function TWebView.Portrait(V, W, H: Integer; Brightness: Double): TJSObject;
var
  Lv, L: Integer;
  Cv: TJSHTMLCanvasElement;
  C2: TJSCanvasRenderingContext2D;
  PW, PH: Integer;
begin
  PW := Round(W * FDpr);
  PH := Round(H * FDpr);
  if (FShadedW[V] <> PW) or (FShadedH[V] <> PH) then
  begin
    for L := 0 to PortraitLevels do FShaded[V, L] := nil;
    FShadedW[V] := PW;
    FShadedH[V] := PH;
  end;
  Lv := Round(Brightness * PortraitLevels);
  if Lv < 0 then Lv := 0;
  if Lv > PortraitLevels then Lv := PortraitLevels;
  if FShaded[V, Lv] = nil then
  begin
    Cv := TJSHTMLCanvasElement(document.createElement('canvas'));
    Cv.width := PW;
    Cv.height := PH;
    C2 := Cv.getContextAs2DContext('2d');
    C2.imageSmoothingEnabled := True;
    C2.drawImage(ImageOf(PortraitName(V)), 0, 0, PW, PH);
    if Lv < PortraitLevels then
    begin
      C2.globalCompositeOperation := 'source-atop';
      C2.fillStyle := 'rgba(0,0,0,' + FloatToStr(1 - Lv / PortraitLevels) + ')';
      C2.fillRect(0, 0, PW, PH);
    end;
    FShaded[V, Lv] := Cv;
  end;
  Result := FShaded[V, Lv];
end;

procedure TWebView.DrawPortraitIn(V: Integer; X, Y, W, H: Double; Brightness: Double);
begin
  if (V < 0) or (V >= PortraitCount) or (W < 2) or (H < 2) then Exit;
  FCtx.drawImage(Portrait(V, Round(W), Round(H), Brightness), X, Y, W, H);
end;

{ The gothic card back, drawn once per size. }
function RgbStr(C: Integer): string;
begin
  Result := Format('rgb(%d,%d,%d)', [ColorR(C), ColorG(C), ColorB(C)]);
end;

function TWebView.BackCard(W, H: Integer): TJSObject;
begin
  Result := BackCardStyled(W, H, FCtl.StyleBack);
end;

function TWebView.BackCardStyled(W, H, AStyle: Integer): TJSObject;
var
  C2: TJSCanvasRenderingContext2D;
  PW, PH, Inset, L, T, Rt, B, K, Step, Lo, Hi, CX, CY, Rad, Sz: Integer;
  S: Double;
begin
  if (FBack <> nil) and (FBackW = W) and (FBackH = H) and (FBackStyle = AStyle) then
  begin
    Result := FBack;
    Exit;
  end;
  FBack := TJSHTMLCanvasElement(document.createElement('canvas'));
  FBackW := W;
  FBackH := H;
  FBackStyle := AStyle;
  PW := Round(W * FDpr);
  PH := Round(H * FDpr);
  FBack.width := PW;
  FBack.height := PH;
  C2 := FBack.getContextAs2DContext('2d');
  S := FDpr;
  C2.scale(S, S);
  { the same picture as the desktop's DrawCardBack, in the same proportions }
  C2.fillStyle := RgbStr(BackColor(AStyle, 0));
  C2.strokeStyle := RgbStr(BackColor(AStyle, 1));
  C2.lineWidth := 1;
  C2.beginPath;
  C2.moveTo(W / 16, 0);
  C2.arcTo(W, 0, W, H, W / 16);
  C2.arcTo(W, H, 0, H, W / 16);
  C2.arcTo(0, H, 0, 0, W / 16);
  C2.arcTo(0, 0, W, 0, W / 16);
  C2.closePath;
  C2.fill;
  C2.stroke;
  { lattice, clipped to the inner panel }
  Inset := W div 7;
  L := Inset; T := Inset; Rt := W - Inset; B := H - Inset;
  C2.save;
  C2.beginPath;
  C2.rect(L, T, Rt - L, B - T);
  C2.clip;
  C2.strokeStyle := RgbStr(BackColor(AStyle, 2));
  C2.lineWidth := 1;
  Step := W div 5;
  if Step < 4 then Step := 4;
  K := T - Rt;
  while K <= B - L do
  begin
    Lo := L; if T - K > Lo then Lo := T - K;
    Hi := Rt; if B - K < Hi then Hi := B - K;
    if Lo < Hi then
    begin
      C2.beginPath; C2.moveTo(Lo, Lo + K); C2.lineTo(Hi, Hi + K); C2.stroke;
    end;
    Inc(K, Step);
  end;
  K := T + L;
  while K <= B + Rt do
  begin
    Lo := L; if K - B > Lo then Lo := K - B;
    Hi := Rt; if K - T < Hi then Hi := K - T;
    if Lo < Hi then
    begin
      C2.beginPath; C2.moveTo(Lo, K - Lo); C2.lineTo(Hi, K - Hi); C2.stroke;
    end;
    Inc(K, Step);
  end;
  C2.restore;
  { frames }
  C2.strokeStyle := RgbStr(BackColor(AStyle, 3));
  C2.lineWidth := W div 40 + 1;
  C2.beginPath;
  C2.moveTo(W / 12 + W / 20, W / 12);
  C2.arcTo(W - W / 12, W / 12, W - W / 12, H - W / 12, W / 20);
  C2.arcTo(W - W / 12, H - W / 12, W / 12, H - W / 12, W / 20);
  C2.arcTo(W / 12, H - W / 12, W / 12, W / 12, W / 20);
  C2.arcTo(W / 12, W / 12, W - W / 12, W / 12, W / 20);
  C2.closePath;
  C2.stroke;
  C2.strokeStyle := RgbStr(BackColor(AStyle, 4));
  C2.lineWidth := 1;
  C2.beginPath;
  C2.moveTo(W / 8 + 1 + W / 24, W / 8 + 1);
  C2.arcTo(W - W / 8 - 1, W / 8 + 1, W - W / 8 - 1, H - W / 8 - 1, W / 24);
  C2.arcTo(W - W / 8 - 1, H - W / 8 - 1, W / 8 + 1, H - W / 8 - 1, W / 24);
  C2.arcTo(W / 8 + 1, H - W / 8 - 1, W / 8 + 1, W / 8 + 1, W / 24);
  C2.arcTo(W / 8 + 1, W / 8 + 1, W - W / 8 - 1, W / 8 + 1, W / 24);
  C2.closePath;
  C2.stroke;
  { medallion with a crescent moon }
  CX := W div 2;
  CY := H div 2;
  Rad := W * 28 div 100;
  C2.fillStyle := RgbStr(BackColor(AStyle, 1));
  C2.strokeStyle := RgbStr(BackColor(AStyle, 3));
  C2.lineWidth := W div 50 + 1;
  C2.beginPath; C2.arc(CX, CY, Rad, 0, 2 * Pi); C2.fill; C2.stroke;
  C2.fillStyle := RgbStr(BackColor(AStyle, 3));
  Rad := W * 17 div 100;
  C2.beginPath; C2.arc(CX, CY, Rad, 0, 2 * Pi); C2.fill;
  C2.fillStyle := RgbStr(BackColor(AStyle, 1));
  Rad := W * 15 div 100;
  C2.beginPath;
  C2.arc(CX + W * 7 div 100, CY - W * 3 div 100, Rad, 0, 2 * Pi);
  C2.fill;
  { small four-point star }
  C2.fillStyle := RgbStr(BackColor(AStyle, 3));
  Sz := W * 7 div 100;
  CX := CX + W * 12 div 100;
  CY := CY - W * 11 div 100;
  C2.beginPath;
  C2.moveTo(CX, CY - Sz);
  C2.lineTo(CX + Sz / 3, CY - Sz / 3);
  C2.lineTo(CX + Sz, CY);
  C2.lineTo(CX + Sz / 3, CY + Sz / 3);
  C2.lineTo(CX, CY + Sz);
  C2.lineTo(CX - Sz / 3, CY + Sz / 3);
  C2.lineTo(CX - Sz, CY);
  C2.lineTo(CX - Sz / 3, CY - Sz / 3);
  C2.closePath;
  C2.fill;
  Result := FBack;
end;

procedure TWebView.DrawCardBackAt(const R: TRect);
begin
  FCtx.drawImage(BackCard(R.Right - R.Left, R.Bottom - R.Top), R.Left, R.Top,
    R.Right - R.Left, R.Bottom - R.Top);
end;

procedure TWebView.DrawCard(const R: TRect; const C: TCard; FaceUp, Playable: Boolean);
var
  Rad: Double;
begin
  Rad := FCtl.Scaled(8);
  if FaceUp then
  begin
    FCtx.drawImage(Face(C), R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top);
    if Playable then
    begin
      StrokeColor(255, 215, 0);
      FCtx.lineWidth := Max(2, FCtl.Scaled(3));
      RRect(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top, Rad / 2 + 2);
      FCtx.stroke;
    end;
  end
  else
    DrawCardBackAt(R);
end;

{ ---- the table ---- }

procedure TWebView.DrawTableBackground;
var
  Gr: TJSCanvasGradient;
  I: Integer;
  D, T: Double;
  M, Th, Dm: Integer;

  procedure Diamond(CX, CY: Double);
  begin
    FCtx.beginPath;
    FCtx.moveTo(CX, CY - Dm);
    FCtx.lineTo(CX + Dm, CY);
    FCtx.lineTo(CX, CY + Dm);
    FCtx.lineTo(CX - Dm, CY);
    FCtx.closePath;
    FCtx.fill;
  end;

begin
  { a felt vignette: bright in the middle, dark in the corners }
  FCtx.save;
  FCtx.translate(FW / 2, FH / 2);
  FCtx.scale(FW / 2, FH / 2);
  Gr := FCtx.createRadialGradient(0, 0, 0, 0, 0, Sqrt(2));
  for I := 0 to 10 do
  begin
    D := I / 10;
    T := Power(Min(1, D * 1.15), 1.7);
    GradStop(Gr, D, Format('rgb(%d,%d,%d)', [Lerp(ColorR(ClothColor(FCtl.StyleCloth, 0)), ColorR(ClothColor(FCtl.StyleCloth, 1)), T),
      Lerp(ColorG(ClothColor(FCtl.StyleCloth, 0)), ColorG(ClothColor(FCtl.StyleCloth, 1)), T),
      Lerp(ColorB(ClothColor(FCtl.StyleCloth, 0)), ColorB(ClothColor(FCtl.StyleCloth, 1)), T)]));
  end;
  FCtx.fillStyle := Gr;
  FCtx.fillRect(-1, -1, 2, 2);
  FCtx.restore;

  { the thin gold frame with corner diamonds }
  M := Round(10 * FCtl.Scale) + 6;
  Th := Max(1, Round(FCtl.Scale * 1.5));
  Dm := Round(5 * FCtl.Scale) + 2;
  FCtx.strokeStyle := RgbStr(ClothColor(FCtl.StyleCloth, 2));
  FCtx.lineWidth := Th;
  FCtx.strokeRect(M, M, FW - 2 * M, FH - 2 * M);
  FCtx.strokeStyle := RgbStr(ClothColor(FCtl.StyleCloth, 3));
  FCtx.lineWidth := 1;
  FCtx.strokeRect(M + 4 * Th + 2, M + 4 * Th + 2, FW - 2 * (M + 4 * Th + 2), FH - 2 * (M + 4 * Th + 2));
  FCtx.fillStyle := RgbStr(ClothColor(FCtl.StyleCloth, 2));
  Diamond(M, M);
  Diamond(FW - M, M);
  Diamond(M, FH - M);
  Diamond(FW - M, FH - M);
end;

{ A vampire's mark on a face-up card, in the top half (the lower rows may cover the
  rest): a blood-red bat for a bitten card, a chain with a padlock for a chained one. }
procedure TWebView.DrawMark(const R: TRect; Kind: Integer);
const
  CrossShape: array[0..11, 0..1] of Double = ((-0.14, -0.5), (0.14, -0.5), (0.14, -0.2),
    (0.34, -0.2), (0.34, 0.02), (0.14, 0.02), (0.14, 0.5), (-0.14, 0.5), (-0.14, 0.02),
    (-0.34, 0.02), (-0.34, -0.2), (-0.14, -0.2));
  Bat: array[0..15, 0..1] of Double = ((0, 0.35), (0.12, 0.12), (0.3, 0.25), (0.4, 0.05),
    (0.5, 0.2), (0.6, 0.05), (0.7, 0.25), (0.88, 0.12), (1, 0.35), (0.82, 0.38), (0.75, 0.55),
    (0.62, 0.42), (0.5, 0.6), (0.38, 0.42), (0.25, 0.55), (0.18, 0.38));
var
  W, H, X0, Y0, PW, PH, CX, CY, LW, LH: Double;
  I, K: Integer;
begin
  if Kind = MarkNone then Exit;
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  if Kind = MarkBitten then
  begin
    PW := W * 0.72;
    X0 := R.Left + (W - PW) / 2;
    Y0 := R.Top + H * 0.09;
    FCtx.beginPath;
    for I := 0 to 15 do
      if I = 0 then FCtx.moveTo(X0 + Bat[I, 0] * PW, Y0 + Bat[I, 1] * PW)
      else FCtx.lineTo(X0 + Bat[I, 0] * PW, Y0 + Bat[I, 1] * PW);
    FCtx.closePath;
    FillColor(176, 12, 36);
    StrokeColor(255, 245, 235);
    FCtx.lineWidth := Max(2, W * 0.04);
    FCtx.fill;
    FCtx.stroke;
    FCtx.beginPath;                          { two drops of blood under it }
    FCtx.ellipse(X0 + PW * 0.42, Y0 + PW * 0.76, PW * 0.04, PW * 0.08, 0, 0, 6.2832);
    FCtx.ellipse(X0 + PW * 0.6, Y0 + PW * 0.76, PW * 0.04, PW * 0.08, 0, 0, 6.2832);
    FCtx.fill;
    FCtx.stroke;
  end
  else if Kind = MarkCross then
  begin
    { a silver cross in a golden glow, under a peak: only a Wild card claims it }
    CX := R.Left + W / 2;
    CY := R.Top + H * 0.30;
    PH := H * 0.34;                          { the cross's height }
    FCtx.beginPath;
    FCtx.ellipse(CX, CY, PH * 0.62, PH * 0.62, 0, 0, 6.2832);
    FillColor(240, 205, 110);
    StrokeColor(150, 112, 30);
    FCtx.lineWidth := Max(2, W * 0.03);
    FCtx.fill;
    FCtx.stroke;
    FCtx.beginPath;
    for I := 0 to 11 do
      if I = 0 then FCtx.moveTo(CX + CrossShape[I, 0] * PH, CY + CrossShape[I, 1] * PH)
      else FCtx.lineTo(CX + CrossShape[I, 0] * PH, CY + CrossShape[I, 1] * PH);
    FCtx.closePath;
    FillColor(226, 230, 244);
    StrokeColor(30, 34, 52);
    FCtx.lineWidth := Max(2, W * 0.04);
    FCtx.fill;
    FCtx.stroke;
  end
  else
  begin
    CY := R.Top + H * 0.30;
    LH := H * 0.14;
    StrokeColor(20, 20, 28);
    FCtx.lineWidth := Max(2, W * 0.03);
    FillColor(170, 172, 186);
    for K := 0 to 4 do                        { the links, wide and narrow in turn }
    begin
      CX := R.Left + (2 * K + 1) * W / 10;
      if K mod 2 = 0 then LW := W * 0.22 else LW := W * 0.12;
      FCtx.beginPath;
      FCtx.ellipse(CX, CY, LW / 2, LH / 2, 0, 0, 6.2832);
      FCtx.fill;
      FCtx.stroke;
    end;
    PW := W * 0.24;                          { the padlock in the middle }
    PH := H * 0.17;
    CX := R.Left + W / 2;
    FillColor(201, 162, 74);
    RRect(CX - PW / 2, CY - PH / 3, PW, PH, 3);
    FCtx.fill;
    FCtx.stroke;
    FillColor(20, 20, 28);
    FCtx.beginPath;
    FCtx.ellipse(CX, CY + PH * 0.1, PW / 8, PH / 8, 0, 0, 6.2832);
    FCtx.fill;
  end;
end;

{ A pile's place: empty, with a turn-over arrow when the waste can be turned over. }
procedure TWebView.DrawPile(const R: TRect; ACount: Integer; ARecycle: Boolean);
var
  CX, CY, Rad, A0: Double;
begin
  FillColor(0, 0, 0, 0.18);
  RRect(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top, FCtl.Scaled(7));
  FCtx.fill;
  StrokeColor(110, 92, 48);
  FCtx.lineWidth := 2;
  RRect(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top, FCtl.Scaled(7));
  FCtx.stroke;
  if ARecycle then
  begin
    CX := (R.Left + R.Right) / 2;
    CY := (R.Top + R.Bottom) / 2;
    Rad := (R.Right - R.Left) * 0.22;
    A0 := 2 * Pi - 0.9;
    StrokeColor(226, 195, 117);
    FCtx.lineWidth := Max(2, FCtl.Scaled(4));
    FCtx.beginPath;
    FCtx.arc(CX, CY, Rad, 0.4, A0);
    FCtx.stroke;
    FillColor(226, 195, 117);
    FCtx.beginPath;
    FCtx.moveTo(CX + Rad * Cos(A0) - Rad * 0.55, CY + Rad * Sin(A0) - Rad * 0.2);
    FCtx.lineTo(CX + Rad * Cos(A0) + Rad * 0.65, CY + Rad * Sin(A0) - Rad * 0.35);
    FCtx.lineTo(CX + Rad * Cos(A0) + Rad * 0.1, CY + Rad * Sin(A0) + Rad * 0.6);
    FCtx.closePath;
    FCtx.fill;
  end;
end;

{ A glowing outline: 0 = selected (gold), 1 = a hint or a card that can be picked (blue). }
procedure TWebView.DrawRing(const R: TRect; Kind: Integer);
begin
  FCtx.save;
  if Kind = 0 then
  begin
    FCtx.shadowColor := 'rgba(255,215,0,0.9)';
    StrokeColor(255, 215, 0);
  end
  else
  begin
    FCtx.shadowColor := 'rgba(110,220,255,0.9)';
    StrokeColor(110, 220, 255);
  end;
  FCtx.shadowBlur := FCtl.Scaled(14);
  FCtx.lineWidth := Max(2, FCtl.Scaled(4));
  RRect(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top, FCtl.Scaled(7));
  FCtx.stroke;
  FCtx.restore;
end;

procedure TWebView.DrawTableContents;
var
  I, N: Integer;
  G: TPyramidGame;
  R: TRect;
  C: TCard;
begin
  G := FCtl.Game;
  case FCtl.TableMode of
    tmDealing:
    begin
      DrawDealing;
      Exit;
    end;
    tmWon:
    begin
      DrawWinScreen(FCtl.WinMessage);
      Exit;
    end;
  end;
  for I := 0 to PyramidSize - 1 do        { lower rows on top }
    if not G.Removed(I) then
    begin
      R := FCtl.CardRect(I);
      DrawCard(R, G.CardAt(I), True, False);
      if not G.IsFree(I) and not G.IsUnder(I) then          { a card that cannot be taken yet is dimmed }
      begin
        FillColor(8, 4, 16, 0.38);
        RRect(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top, FCtl.Scaled(7));
        FCtx.fill;
      end;
      DrawMark(R, FCtl.CardMark(I));                         { a vampire's bite, chain or the silver cross }
    end;
  for I := 0 to PyramidSize - 1 do        { the outlines last, so that no card covers them }
    if not G.Removed(I) then
    begin
      if FCtl.CardSelected(I) then DrawRing(FCtl.CardRect(I), 0)
      else if FCtl.CardHighlighted(I) then DrawRing(FCtl.CardRect(I), 1);
    end;
  { the stock and the waste }
  R := FCtl.StockRect;
  if G.StockCount > 0 then
    DrawCard(R, G.CardAt(0), False, False)
  else
    DrawPile(R, 0, G.CanRecycle);
  if FCtl.StockHighlighted then DrawRing(R, 1);
  R := FCtl.WasteRect;
  if G.WasteTop(C) then DrawCard(R, C, True, False) else DrawPile(R, 0, False);
  if FCtl.WasteSelected then DrawRing(R, 0)
  else if FCtl.WasteHighlighted then DrawRing(R, 1);
  { Seer's eye: the next three cards of the stock, fanned beside the waste }
  if G.Revealed and (G.StockCount > 0) then
    for I := Min(2, G.StockCount - 1) downto 0 do
    begin
      R := FCtl.WasteRect;
      N := (R.Right - R.Left) * 6 div 10;
      OffsetRect(R, (R.Right - R.Left) + FCtl.Scaled(14) + (2 - I) * N div 2, 0);
      R.Right := R.Left + N;
      R.Bottom := R.Top + (R.Bottom - R.Top) * 6 div 10;
      FCtx.drawImage(Face(G.StockCard(I)), R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top);
    end;
end;

procedure TWebView.DrawDealing;
var
  Pass, Slot: Integer;
  Settled: Boolean;
begin
  DrawCard(FCtl.StockRect, FCtl.Game.CardAt(0), False, False);     { the pile the cards leave }
  for Pass := 0 to 1 do                    { cards in place first, flying ones on top }
    for Slot := 0 to PyramidSize - 1 do
    begin
      if FCtl.Stage.Move[Slot] <= 0 then Continue;
      Settled := FCtl.Stage.Move[Slot] >= 1;
      if (Pass = 0) = Settled then DrawStageCard(Slot);
    end;
end;

procedure TWebView.DrawStageCard(Slot: Integer);
var
  Src, Dst, R, Rs: TRect;
  P, F: Double;
  W, H, NewW, CX: Integer;
  FaceUp: Boolean;
begin
  Src := FCtl.StockRect;
  Dst := FCtl.CardRect(Slot);
  P := FCtl.Stage.Move[Slot];
  W := Src.Right - Src.Left;
  H := Src.Bottom - Src.Top;
  R.Left := Src.Left + Round((Dst.Left - Src.Left) * P);
  R.Top := Src.Top + Round((Dst.Top - Src.Top) * P);
  R.Right := R.Left + W;
  R.Bottom := R.Top + H;
  { a flip squeezes the card to an edge and widens it again }
  F := FCtl.Stage.Flip[Slot];
  if F < 0.5 then
  begin
    NewW := Round(W * (1 - 2 * F));
    FaceUp := False;
  end
  else
  begin
    NewW := Round(W * (2 * F - 1));
    FaceUp := True;
  end;
  if NewW < 2 then Exit;
  CX := (R.Left + R.Right) div 2;
  Rs := Rect(CX - NewW div 2, R.Top, CX - NewW div 2 + NewW, R.Bottom);
  if FaceUp then
    FCtx.drawImage(Face(FCtl.Game.CardAt(Slot)), Rs.Left, Rs.Top, Rs.Right - Rs.Left, Rs.Bottom - Rs.Top)
  else
    FCtx.drawImage(BackCard(W, H), Rs.Left, Rs.Top, Rs.Right - Rs.Left, Rs.Bottom - Rs.Top);
end;

procedure TWebView.DrawWinScreen(const Msg: string);
var
  AX, AY, AW, AH, W, H: Double;
  Img: TJSObject;
  IW, IH: Double;
begin
  Img := ImageOf('win_screen');
  IW := Double(Img['naturalWidth']);
  IH := Double(Img['naturalHeight']);
  AX := FCtl.Scaled(30);
  AY := FCtl.Scaled(24);
  AW := FW - 2 * FCtl.Scaled(30);
  AH := FH - AY - FCtl.Scaled(52);
  if (AW < 16) or (AH < 16) or (IW < 1) then Exit;
  W := AW;
  H := W * IH / IW;
  if H > AH then
  begin
    H := AH;
    W := H * IW / IH;
  end;
  FCtx.drawImage(Img, AX + (AW - W) / 2, AY + (AH - H) / 2, W, H);
  SetFont(Max(14, FCtl.Scaled(11) * PtToPx), False, False);
  FillColor(150, 125, 70);
  CenterText(0, FW, FH - FCtl.Scaled(40), Msg, 14);
end;

{ ---- the dialogue scenes ---- }

procedure TWebView.DrawTextBox(X, Y, W, H: Double; K: Double);
var
  Pad, Th, NameH, AreaTop, AreaBot, TextY, Fade, Pulse, Sz, XX: Double;
  Lines: TJSArray;
  I: Integer;
  St: TStage;
  Hint: string;
  CaptionPx: Double;
begin
  St := FCtl.Stage;
  Pad := Max(10, 16 * K);
  Th := Max(1, Round(2 * K));
  FillColor(22, 13, 28);
  StrokeColor(201, 162, 74);
  FCtx.lineWidth := Th;
  RRect(X, Y, W, H, Max(6, 7 * K));
  FCtx.fill;
  FCtx.stroke;
  StrokeColor(110, 90, 46);
  FCtx.lineWidth := 1;
  RRect(X + Th * 3, Y + Th * 3, W - Th * 6, H - Th * 6, Max(4, 5 * K));
  FCtx.stroke;

  AreaTop := Y + Pad;
  AreaBot := Y + H - Pad;
  NameH := 0;
  { name plate }
  if St.SpeakerName <> '' then
  begin
    SetFont(Max(16, 17 * K * PtToPx), True, True);
    FillColor(201, 162, 74);
    Text(St.SpeakerName, X + Pad, AreaTop);
    XX := X + Pad + TextW(St.SpeakerName) + 14 * K;
    NameH := Max(16, 17 * K * PtToPx) * 1.22;
    if St.SpeakerTitle <> '' then
    begin
      SetFont(Max(13, 12 * K * PtToPx), False, True);
      FillColor(150, 125, 70);
      Text(St.SpeakerTitle, XX, AreaTop + NameH - Max(13, 12 * K * PtToPx) * 1.22);
    end;
    AreaTop := AreaTop + NameH + 8 * K;
  end;
  { the line of text, faded by blending its colour into the box }
  if St.Caption <> '' then
  begin
    Fade := Max(0, Min(1, St.Scalar[ssTextFade]));
    CaptionPx := Max(17, 16 * K * PtToPx);
    SetFont(CaptionPx, False, False);
    FillColor(Lerp(22, 232, Fade), Lerp(13, 224, Fade), Lerp(28, 204, Fade));
    Lines := WrapLines(Self, St.Caption, W - 2 * Pad);
    TextY := AreaTop + (AreaBot - AreaTop - Lines.length * CaptionPx * 1.22) / 2;
    if TextY < AreaTop then TextY := AreaTop;
    for I := 0 to Lines.length - 1 do
    begin
      Text(string(Lines[I]), X + (W - TextW(string(Lines[I]))) / 2, TextY);
      TextY := TextY + CaptionPx * 1.22;
    end;
  end;
  { waiting for the player: a small gold arrow that pulses }
  if St.WaitingForClick and (St.Scalar[ssTextFade] >= 0.99) then
  begin
    Pulse := 0.5 + 0.5 * Sin(TJSDate.now / 260.0);
    FillColor(Lerp(110, 240, Pulse), Lerp(90, 205, Pulse), Lerp(46, 110, Pulse));
    Sz := Max(6, 7 * K);
    FCtx.beginPath;
    FCtx.moveTo(X + W / 2 - Sz, Y + H - Pad - Sz - Sz);
    FCtx.lineTo(X + W / 2 + Sz, Y + H - Pad - Sz - Sz);
    FCtx.lineTo(X + W / 2, Y + H - Pad);
    FCtx.closePath;
    FCtx.fill;
  end;
  { a quiet reminder }
  if FTouch then Hint := 'tap: next line' else Hint := 'click: next line     Esc: skip';
  SetFont(Max(12, 9 * K * PtToPx), False, False);
  FillColor(96, 80, 48);
  Text(Hint, X + W - Pad - TextW(Hint), Y + H - Pad - 12);
end;

{ The house picture, cropped to fill the whole area, darkened by Dark (0..1). }
procedure TWebView.DrawHouseCover(Dark: Double);
var
  Img: TJSObject;
  S, W, H: Double;
begin
  Img := ImageOf(HouseImageKey(FCtl.StyleMoon));
  S := Max(FW / 1600, FH / 1000);
  W := 1600 * S;
  H := 1000 * S;
  FCtx.drawImage(Img, (FW - W) / 2, (FH - H) / 2, W, H);
  DrawOverlay(4, 4, 10, Dark);
end;

{ The story's opening: the house on the hill with a box of text. }
procedure TWebView.DrawHouseScene;
var
  K: Double;
  St: TStage;
begin
  St := FCtl.Stage;
  K := Min(FW / 1240, FH / 584);
  if K < 0.55 then K := 0.55;
  DrawHouseCover(0.12);
  DrawTextBox(Round(FW * 0.06), Round(FH * 0.695), Round(FW * 0.88), Round(FH * 0.26), K);
  DrawOverlay(255, 255, 255, St.Scalar[ssFlashWhite]);
  DrawOverlay(190, 10, 20, St.Scalar[ssFlashRed]);
end;

{ The start menu: the house on the hill, the title and the buttons. }
procedure TWebView.DrawMenu;
var
  I: Integer;
  T, R: TRect;
  Px, Th: Double;
  S: string;
begin
  DrawHouseCover(0);
  FillColor(8, 5, 14, 0.55);                         { a darker band behind the buttons }
  FCtx.fillRect(0, FH * 0.44, FW, FH - FH * 0.44);
  T := FCtl.MenuTitleRect;
  Px := Max(30, (T.Bottom - T.Top) * 0.5);
  SetFont(Px, True, True);
  S := 'Tiepair';
  FillColor(0, 0, 0);
  CenterText(0, FW, T.Top + 3, S, Px);
  FillColor(232, 224, 204);
  Th := CenterText(0, FW, T.Top, S, Px);
  SetFont(Max(15, Px * 0.34), False, True);
  FillColor(201, 162, 74);
  CenterText(0, FW, T.Top + Th, FCtl.MenuSubtitle, Px * 0.34);
  for I := 0 to FCtl.MenuButtonCount - 1 do
  begin
    R := FCtl.MenuButtonRect(I);
    FillColor(22, 13, 28);
    StrokeColor(201, 162, 74);
    FCtx.lineWidth := 2;
    RRect(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top, 8);
    FCtx.fill;
    FCtx.stroke;
    StrokeColor(110, 90, 46);
    FCtx.lineWidth := 1;
    RRect(R.Left + 5, R.Top + 5, R.Right - R.Left - 10, R.Bottom - R.Top - 10, 5);
    FCtx.stroke;
    Px := Max(16, (R.Bottom - R.Top) * 0.42);
    SetFont(Px, True, False);
    if FCtl.MenuButtonEnabled(I) then FillColor(232, 224, 204) else FillColor(110, 100, 90);   { dimmed: nothing to save yet }
    S := FCtl.MenuButtonCaption(I);
    Text(S, R.Left + ((R.Right - R.Left) - TextW(S)) / 2, R.Top + ((R.Bottom - R.Top) - Px) / 2 - 1);
  end;
  SetFont(14, False, False);                                  { the version, small, in the corner }
  FillColor(190, 160, 90);
  S := FCtl.MenuVersion;
  Text(S, FW - TextW(S) - 10, FH - 24);
  if FCtl.MenuNote <> '' then
  begin
    R := FCtl.MenuButtonRect(FCtl.MenuButtonCount - 1);
    SetFont(15, False, True);
    FillColor(201, 162, 74);
    CenterWrapped(12, FW - 12, Min(R.Bottom + 12, FH - 26), FCtl.MenuNote, 15);
  end;
end;

procedure TWebView.DrawDialogue;
var
  K, Slide, PW, PH, PX, PY, Base: Double;
  St: TStage;
begin
  St := FCtl.Stage;
  K := Min(FW / 1240, FH / 584);
  if K < 0.55 then K := 0.55;
  { a darker room }
  DrawOverlay(4, 6, 8, 0.62);
  { the portrait: slides in from the left, shakes, fades to dark }
  if (St.PortraitId >= 0) and (St.PortraitId < PortraitCount) then
  begin
    PH := Round(FH * 0.62);
    PW := Round(PH * 596 / 878);
    if PW > FW * 0.9 then
    begin
      PW := Round(FW * 0.9);
      PH := Round(PW * 878 / 596);
    end;
    PY := Round(FH * 0.035);
    Base := (FW - PW) / 2;
    Slide := St.Scalar[ssPortraitSlide];
    PX := Base - (1 - Slide) * (Base + PW) + St.Scalar[ssPortraitDX] * PW;
    DrawPortraitIn(St.PortraitId, PX, PY, PW, PH, St.Scalar[ssPortraitFade]);
  end;
  DrawTextBox(Round(FW * 0.06), Round(FH * 0.695), Round(FW * 0.88), Round(FH * 0.26), K);
  { flashes: white for the blow, red for the vampire's free round }
  DrawOverlay(255, 255, 255, St.Scalar[ssFlashWhite]);
  DrawOverlay(190, 10, 20, St.Scalar[ssFlashRed]);
end;

{ ---- the duel panel ---- }

procedure TWebView.PanelFrame(const R: TRect; K: Double);
var
  Th: Double;
begin
  Th := Max(1, Round(2 * K));
  FillColor(22, 13, 28);
  StrokeColor(201, 162, 74);
  FCtx.lineWidth := Th;
  RRect(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top, 7 * K);
  FCtx.fill;
  FCtx.stroke;
  StrokeColor(110, 90, 46);
  FCtx.lineWidth := 1;
  RRect(R.Left + Th * 3, R.Top + Th * 3, R.Right - R.Left - Th * 6, R.Bottom - R.Top - Th * 6, 5 * K);
  FCtx.stroke;
end;

procedure TWebView.Pips(CX, Y: Double; const Info: TDuelInfo; K: Double);
var
  I: Integer;
  D, Gap, PX: Double;
begin
  D := Max(8, 11 * K);
  Gap := Max(5, 7 * K);
  PX := CX - (Info.WinsNeeded * D + (Info.WinsNeeded - 1) * Gap) / 2 + D / 2;
  StrokeColor(201, 162, 74);
  FCtx.lineWidth := Max(1, K);
  for I := 1 to Info.WinsNeeded do
  begin
    FCtx.beginPath;
    FCtx.arc(PX, Y + D / 2, D / 2, 0, 2 * Pi);
    if I <= Info.Wins then
    begin
      FillColor(201, 162, 74);
      FCtx.fill;
    end;
    FCtx.stroke;
    PX := PX + D + Gap;
  end;
end;

procedure TWebView.Row(Left, Right, Y: Double; const LabelText, Value: string; Px: Double;
  R, G, B: Integer);
begin
  FillColor(150, 125, 70);
  Text(LabelText, Left, Y);
  FillColor(R, G, B);
  Text(Value, Right - TextW(Value), Y);
end;

function PayText(const Info: TDuelInfo): string;
begin
  if Info.PayNow = 1 then Result := '1 coin' else Result := IntToStr(Info.PayNow) + ' coins';
end;

{ The tall panel in a column beside the table. }
{ The foot of the side panel: a divider, then cards left and stock, streak and
  best, and the coins. Its height at scale K is StatsHeight. }
function StatsHeight(K: Double): Double;
begin
  Result := 10 * K + 3 * Max(8, 11 * K) * PtToPx * 1.3;
end;

{ The trophy shelf: a small card for each trophy (an outlined tile for one not
  earned yet), or in a narrow strip one chip with the count. A tap on it opens
  the trophy page (the controller). }
procedure TWebView.DrawTrophyShelf(const L: TTrophyLayout; const St: TPanelStats);
var
  I: Integer;
  H, W, X, Px, Gap: Double;
begin
  if L.Shelf.Right <= L.Shelf.Left then Exit;
  StrokeColor(110, 90, 46);
  FCtx.lineWidth := 1;
  if L.Chip then
  begin
    H := L.Shelf.Bottom - L.Shelf.Top;
    FillColor(30, 19, 38);
    RRect(L.Shelf.Left, L.Shelf.Top, L.Shelf.Right - L.Shelf.Left, H, 6);
    FCtx.fill;
    FCtx.stroke;
    Px := Max(10, H * 0.46);
    SetFont(Px, True, False);
    FillColor(201, 162, 74);
    CenterText(L.Shelf.Left, L.Shelf.Right, L.Shelf.Top + (H - Px * 1.2) / 2,
      Format('Trophies %d/%d', [St.TrophyCount, TrophyCount]), Px);
    Exit;
  end;
  Gap := Max(2, (L.Reserved - (L.Shelf.Bottom - L.Shelf.Top)) / 2);
  FCtx.beginPath;
  FCtx.moveTo(L.Shelf.Left, L.Shelf.Top - Gap);
  FCtx.lineTo(L.Shelf.Right, L.Shelf.Top - Gap);
  FCtx.stroke;
  for I := 0 to TrophyCount - 1 do
  begin
    H := L.Slots[I].Bottom - L.Slots[I].Top;
    W := H * 164 / 232;
    X := L.Slots[I].Left + ((L.Slots[I].Right - L.Slots[I].Left) - W) / 2;
    if (St.Trophies shr I) and 1 = 1 then
      FCtx.drawImage(ImageOf('special_trophy_' + TrophyKeys[TTrophy(I)]), X, L.Slots[I].Top, W, H)
    else
    begin
      FillColor(30, 19, 38);
      RRect(X, L.Slots[I].Top, W, H, Max(3, H / 8));
      FCtx.fill;
      FCtx.stroke;
    end;
  end;
end;

{ A Style row's picture, drawn in code: a card back, a bit of the table cloth, or the moon. }
procedure TWebView.DrawStylePreview(const R: TRect; P: Integer);
var
  Kind, Item, Steps, I: Integer;
  W, H, CX, CY, Rad, F: Double;
  Cen, Edg: Integer;
  Gr: TJSCanvasGradient;
begin
  Kind := (P - 1) div 16;
  Item := (P - 1) mod 16;
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  case Kind of
    0: FCtx.drawImage(BackCardStyled(Round(W), Round(H), Item), R.Left, R.Top, W, H);
    1:
    begin
      Cen := ClothColor(Item, 0);
      Edg := ClothColor(Item, 1);
      { the felt is dark: show it a little lighter so the swatch reads in a small picture }
      Gr := FCtx.createRadialGradient(R.Left + W / 2, R.Top + H / 2, 0, R.Left + W / 2, R.Top + H / 2, Max(W, H) * 0.7);
      GradStop(Gr, 0, Format('rgb(%d,%d,%d)', [Min(255, ColorR(Cen) * 2), Min(255, ColorG(Cen) * 2), Min(255, ColorB(Cen) * 2)]));
      GradStop(Gr, 1, Format('rgb(%d,%d,%d)', [Min(255, ColorR(Edg) * 2 + 14), Min(255, ColorG(Edg) * 2 + 14), Min(255, ColorB(Edg) * 2 + 14)]));
      FCtx.fillStyle := Gr;
      RRect(R.Left, R.Top, W, H, 8);
      FCtx.fill;
      FCtx.strokeStyle := RgbStr(ClothColor(Item, 2));
      FCtx.lineWidth := 1;
      RRect(R.Left + 3, R.Top + 3, W - 6, H - 6, 6);
      FCtx.stroke;
    end;
  else
    begin
      FillColor(22, 14, 36);
      StrokeColor(80, 64, 40);
      FCtx.lineWidth := 1;
      RRect(R.Left, R.Top, W, H, 8);
      FCtx.fill;
      FCtx.stroke;
      CX := R.Left + W / 2;
      CY := R.Top + H / 2;
      Rad := Min(W, H) * 0.3;
      FCtx.fillStyle := RgbStr(MoonColor(Item, 0));
      FCtx.beginPath;
      FCtx.arc(CX, CY, Rad, 0, 2 * Pi);
      FCtx.fill;
      if MoonColor(Item, 1) >= 0 then
      begin
        FCtx.strokeStyle := RgbStr(MoonColor(Item, 1));
        FCtx.lineWidth := Max(1, Rad / 7);
        FCtx.beginPath;
        FCtx.arc(CX, CY, Rad + 1, 0, 2 * Pi);
        FCtx.stroke;
      end;
    end;
  end;
end;

procedure TWebView.DrawStatsBlock(X0, X1, Y, K: Double; const St: TPanelStats);
var
  Px, RowH, Mid, Gap: Double;
begin
  StrokeColor(110, 90, 46);
  FCtx.lineWidth := 1;
  FCtx.beginPath; FCtx.moveTo(X0, Y); FCtx.lineTo(X1, Y); FCtx.stroke;
  Y := Y + 6 * K;
  Px := Max(8, 11 * K) * PtToPx;
  SetFont(Px, False, False);
  RowH := Px * 1.3;
  Mid := (X0 + X1) / 2;
  Gap := Max(4, (X1 - X0) / 14);
  Row(X0, Mid - Gap, Y, 'Cards left', IntToStr(St.Remaining), Px, 232, 224, 204);
  Row(Mid + Gap, X1, Y, 'Stock', IntToStr(St.Stock), Px, 232, 224, 204);
  Y := Y + RowH;
  Row(X0, Mid - Gap, Y, 'Streak', IntToStr(St.Streak), Px, 232, 224, 204);
  Row(Mid + Gap, X1, Y, 'Best', IntToStr(St.BestStreak), Px, 232, 224, 204);
  Y := Y + RowH;
  Row(X0, Mid - Gap, Y, 'Turn-overs', IntToStr(St.Recycles), Px, 232, 224, 204);
  SetFont(Px, True, False);
  Row(Mid + Gap, X1, Y, 'Coins', IntToStr(St.Coins), Px, 201, 162, 74);
end;

{ Free Play: no vampire, just what the hand pays. }
procedure TWebView.DrawFreeColumn(X0, X1, Y, Bottom, K: Double; const St: TPanelStats);
var
  Px, RowH, PW, PH, A, CW, CH, SX, SY: Double;
  S: string;
  Img: TJSObject;
begin
  Px := Max(8, 10 * K) * PtToPx;
  SetFont(Px, True, False);
  FillColor(150, 125, 70);
  Y := Y + CenterText(X0, X1, Y, 'FREE PLAY', Px) + 10 * K;
  StrokeColor(110, 90, 46);
  FCtx.lineWidth := 1;
  FCtx.beginPath; FCtx.moveTo(X0, Y); FCtx.lineTo(X1, Y); FCtx.stroke;
  Y := Y + 8 * K;
  Px := Max(8, 9 * K) * PtToPx;
  SetFont(Px, True, False);
  Y := Y + CenterText(X0, X1, Y, 'THIS HAND PAYS', Px);
  Px := Max(8, 26 * K) * PtToPx;
  SetFont(Px, True, False);
  FillColor(232, 224, 204);
  if St.PayNow = 1 then S := '1 coin' else S := IntToStr(St.PayNow) + ' coins';
  Y := Y + CenterText(X0, X1, Y, S, Px) + 6 * K;
  Px := Max(8, 11 * K) * PtToPx;
  SetFont(Px, False, False);
  RowH := Px * 1.3;
  Row(X0, X1, Y, 'Each win', '+' + IntToStr(St.PerWin), Px, 232, 224, 204);
  Y := Y + RowH;
  if St.MissCut > 0 then
  begin
    Row(X0, X1, Y, Format('Missed moves (%d)', [St.Misses]), '-' + IntToStr(St.MissCut), Px, 214, 80, 92);
    Y := Y + RowH;
  end;
  { the house fills what is left of the panel: the middle of the picture }
  Y := Y + 8 * K;
  PW := X1 - X0;
  PH := Bottom - 8 * K - Y;
  if (PW > 8) and (PH >= 60 * K) then
  begin
    Img := ImageOf(HouseImageKey(FCtl.StyleMoon));
    A := PW / PH;
    CH := 1000;
    CW := CH * A;
    if CW > 1600 then
    begin
      CW := 1600;
      CH := CW / A;
    end;
    SX := (1600 - CW) / 2;
    SY := 1000 * 0.52 - CH / 2;
    if SY < 0 then SY := 0;
    if SY + CH > 1000 then SY := 1000 - CH;
    FCtx.drawImage(Img, SX, SY, CW, CH, X0, Y, PW, PH);
    StrokeColor(201, 162, 74);
    FCtx.lineWidth := 2;
    FCtx.strokeRect(X0, Y, PW, PH);
  end;
end;

{ Free Play in the strip under the table: the pay on the left, the numbers on the right. }
procedure TWebView.DrawFreeStrip(const R: TRect; const St: TPanelStats);
var
  W, H, K, Pad, Px, Y, Mid, RowH: Double;
  S: string;
begin
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  K := Min(W / 520, H / 170);
  if K < 0.6 then K := 0.6;
  Pad := Round(12 * K);
  PanelFrame(R, K);
  DrawTrophyShelf(TrophyLayoutFor(R, True), St);
  Mid := R.Left + W * 0.5;
  Y := R.Top + Pad;
  Px := Max(11, 9 * K) * PtToPx;
  SetFont(Px, True, False);
  FillColor(150, 125, 70);
  Y := Y + CenterText(R.Left + Pad, Mid - Pad, Y, 'THIS HAND PAYS', Px) + 4 * K;
  Px := Max(11, 22 * K) * PtToPx;
  SetFont(Px, True, False);
  FillColor(232, 224, 204);
  if St.PayNow = 1 then S := '1 coin' else S := IntToStr(St.PayNow) + ' coins';
  Y := Y + CenterText(R.Left + Pad, Mid - Pad, Y, S, Px) + 4 * K;
  Px := Max(11, 10 * K) * PtToPx;
  SetFont(Px, False, False);
  RowH := Px * 1.3;
  Row(R.Left + Pad, Mid - Pad, Y, 'Each win', '+' + IntToStr(St.PerWin), Px, 232, 224, 204);
  if St.MissCut > 0 then
    Row(R.Left + Pad, Mid - Pad, Y + RowH, Format('Missed moves (%d)', [St.Misses]), '-' + IntToStr(St.MissCut), Px, 214, 80, 92);
  { the numbers }
  Y := R.Top + Pad;
  Px := Max(11, 11 * K) * PtToPx;
  SetFont(Px, False, False);
  RowH := Px * 1.5;
  Row(Mid + Pad, R.Right - Pad, Y, 'Cards left', IntToStr(St.Remaining), Px, 232, 224, 204);
  Y := Y + RowH;
  Row(Mid + Pad, R.Right - Pad, Y, 'Stock (turn-overs ' + IntToStr(St.Recycles) + ')', IntToStr(St.Stock), Px, 232, 224, 204);
  Y := Y + RowH;
  Row(Mid + Pad, R.Right - Pad, Y, 'Streak (best ' + IntToStr(St.BestStreak) + ')', IntToStr(St.Streak), Px, 232, 224, 204);
  Y := Y + RowH;
  SetFont(Px, True, False);
  Row(Mid + Pad, R.Right - Pad, Y, 'Coins', IntToStr(St.Coins), Px, 201, 162, 74);
end;

procedure TWebView.DrawPanelColumn(const R: TRect; const Info: TDuelInfo; const St: TPanelStats);
var
  W, H, K, Pad, X0, X1, Y, PH, PW, RowH, Bottom, Px: Double;
  S: string;
  TL: TTrophyLayout;
  function F(Size: Double): Double;
  begin
    Result := Max(8, Size * K) * PtToPx;
  end;
begin
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  K := Min(W / 248, H / 524);
  if K < 0.55 then K := 0.55;
  Pad := Round(14 * K);
  X0 := R.Left + Pad;
  X1 := R.Right - Pad;
  TL := TrophyLayoutFor(R, False);
  Bottom := R.Bottom - Pad - TL.Reserved - StatsHeight(K);   { the stats block, and the trophy shelf under it, sit below }
  PanelFrame(R, K);
  Y := R.Top + Pad;
  DrawStatsBlock(X0, X1, R.Bottom - Pad - TL.Reserved - StatsHeight(K) + 2 * K, K, St);
  DrawTrophyShelf(TL, St);
  if not Info.Active then
  begin
    DrawFreeColumn(X0, X1, Y, Bottom, K, St);
    Exit;
  end;

  Px := F(10);
  SetFont(Px, True, False);
  FillColor(150, 125, 70);
  Y := Y + CenterText(X0, X1, Y, Format('DUEL %d OF %d', [Info.DuelNumber, Info.DuelCount]), Px) + 6 * K;

  if Info.StuckWaiting then PH := Round(H * 0.20) else PH := Round(H * 0.28);
  PH := PH - Round(TL.Reserved * 0.6);                { the shelf needs room too }
  PH := Min(Round((X1 - X0) * 878 / 596), PH);
  PW := Round(PH * 596 / 878);
  DrawPortraitIn(Info.Vampire, R.Left + (W - PW) / 2, Y, PW, PH, 1);
  Y := Y + PH + 8 * K;

  Px := F(15);
  SetFont(Px, True, True);
  FillColor(201, 162, 74);
  Y := Y + CenterWrapped(X0, X1, Y, Info.Name, Px);
  Px := F(11);
  SetFont(Px, False, True);
  FillColor(150, 125, 70);
  Y := Y + CenterWrapped(X0, X1, Y, Info.Title, Px) + 6 * K;

  Pips((X0 + X1) / 2, Y, Info, K);
  Y := Y + Max(8, 11 * K) + 3 * K;
  Px := F(10);
  SetFont(Px, True, False);
  FillColor(150, 125, 70);
  Y := Y + CenterText(X0, X1, Y, Format('WINS %d OF %d', [Info.Wins, Info.WinsNeeded]), Px) + 6 * K;

  StrokeColor(110, 90, 46);
  FCtx.lineWidth := 1;
  FCtx.beginPath; FCtx.moveTo(X0, Y); FCtx.lineTo(X1, Y); FCtx.stroke;
  Y := Y + 8 * K;

  Px := F(9);
  SetFont(Px, True, False);
  FillColor(150, 125, 70);
  if Info.KillBonus > 0 then S := 'THE KILL PAYS' else S := 'THIS WIN PAYS';
  Y := Y + CenterText(X0, X1, Y, S, Px);
  Px := F(26);
  SetFont(Px, True, False);
  FillColor(232, 224, 204);
  Y := Y + CenterText(X0, X1, Y, PayText(Info), Px);
  if Info.AtFloor then
  begin
    Px := F(9);
    SetFont(Px, False, True);
    FillColor(150, 125, 70);
    Y := Y + CenterText(X0, X1, Y, '(the minimum)', Px);
  end;
  Y := Y + 6 * K;

  Px := F(11);
  SetFont(Px, False, False);
  RowH := Px * 1.3;
  Row(X0, X1, Y, 'Each win', '+' + IntToStr(Info.PerWin), Px, 232, 224, 204);
  Y := Y + RowH;
  if Info.KillBonus > 0 then
  begin
    Row(X0, X1, Y, 'Kill bonus', '+' + IntToStr(Info.KillBonus), Px, 232, 224, 204);
    Y := Y + RowH;
  end;
  if Info.LostHandsCut > 0 then
  begin
    Row(X0, X1, Y, Format('Lost hands (%d)', [Info.LostHands]), '-' + IntToStr(Info.LostHandsCut), Px, 214, 80, 92);
    Y := Y + RowH;
  end;
  if Info.MissCut > 0 then
  begin
    Row(X0, X1, Y, Format('Missed moves (%d)', [Info.Misses]), '-' + IntToStr(Info.MissCut), Px, 214, 80, 92);
    Y := Y + RowH;
  end;
  if Info.BiteCut > 0 then
  begin
    Row(X0, X1, Y, Format('Bitten cards (%d)', [Info.Bites]), '-' + IntToStr(Info.BiteCut), Px, 214, 80, 92);
    Y := Y + RowH;
  end;

  Y := Y + 4 * K;
  Px := F(10);
  SetFont(Px, False, True);
  FillColor(150, 125, 70);
  if Info.Easy then S := 'the Easy rule' else S := 'plain Pyramid';
  Y := Y + CenterWrapped(X0, X1, Y, TurnOvers(Info.Recycles) + ' of the stock; ' + S, Px);
  if Info.HazardText <> '' then                       { and his trick }
  begin
    FillColor(214, 80, 92);
    Y := Y + CenterWrapped(X0, X1, Y, Info.HazardText, Px);
  end;
  if Info.CrossText <> '' then                        { the silver cross }
  begin
    FillColor(205, 208, 224);
    Y := Y + CenterWrapped(X0, X1, Y, Info.CrossText, Px);
  end;

  if Info.StuckWaiting then
  begin
    Y := Y + 6 * K;
    Px := F(11);
    SetFont(Px, True, False);
    FillColor(214, 80, 92);
    if Y + 3 * Px * 1.22 <= Bottom then
      CenterWrapped(X0, X1, Y, 'No moves left. Use an undo or special card, or press New Game to concede.', Px);
  end;
end;

{ The same panel laid out wide, for the strip under the table on a tall screen:
  portrait on the left, who and how far in the middle, the pay on the right. }
procedure TWebView.DrawPanelStrip(const R: TRect; const Info: TDuelInfo; const St: TPanelStats);
var
  W, H, K, Pad, PH, PW, X, Y, MidL, MidR, RightL, RightR, Px, RowH: Double;
  S: string;
  TL: TTrophyLayout;
  function F(Size: Double): Double;
  begin
    Result := Max(11, Size * K) * PtToPx;
  end;
begin
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  K := Min(W / 700, H / 220);
  if K < 0.6 then K := 0.6;
  Pad := Round(12 * K);
  PanelFrame(R, K);
  TL := TrophyLayoutFor(R, True);
  DrawTrophyShelf(TL, St);
  PH := H - 2 * Pad;
  if TL.Chip then PH := PH - TL.Reserved;            { the chip sits under the portrait }
  PW := Round(PH * 596 / 878);
  DrawPortraitIn(Info.Vampire, R.Left + Pad, R.Top + Pad, PW, PH, 1);
  MidL := R.Left + Pad + PW + Pad;
  RightL := R.Left + Pad + PW + Pad + (W - 3 * Pad - PW) * 0.47;
  MidR := RightL - Pad;
  RightR := R.Right - Pad;

  { who }
  Y := R.Top + Pad;
  Px := F(9);
  SetFont(Px, True, False);
  FillColor(150, 125, 70);
  Y := Y + CenterText(MidL, MidR, Y, Format('DUEL %d OF %d', [Info.DuelNumber, Info.DuelCount]), Px) + 2 * K;
  Px := F(13);
  SetFont(Px, True, True);
  FillColor(201, 162, 74);
  Y := Y + CenterWrapped(MidL, MidR, Y, Info.Name, Px);
  Px := F(10);
  SetFont(Px, False, True);
  FillColor(150, 125, 70);
  Y := Y + CenterWrapped(MidL, MidR, Y, Info.Title, Px) + 4 * K;
  Pips((MidL + MidR) / 2, Y, Info, K * 1.1);
  Y := Y + Max(8, 11 * K * 1.1) + 3 * K;
  Px := F(9);
  SetFont(Px, True, False);
  FillColor(150, 125, 70);
  Y := Y + CenterText(MidL, MidR, Y, Format('WINS %d OF %d', [Info.Wins, Info.WinsNeeded]), Px) + 4 * K;
  Px := F(9);
  SetFont(Px, False, True);
  if Info.Easy then S := 'the Easy rule' else S := 'plain Pyramid';
  Y := Y + CenterWrapped(MidL, MidR, Y, TurnOvers(Info.Recycles) + '; ' + S, Px) + 4 * K;
  { the numbers, two short lines }
  Px := F(10);
  SetFont(Px, False, False);
  FillColor(232, 224, 204);
  Y := Y + CenterText(MidL, MidR, Y, Format('Left %d   Stock %d', [St.Remaining, St.Stock]), Px);
  FillColor(201, 162, 74);
  CenterText(MidL, MidR, Y, Format('Streak %d (best %d)   Coins %d', [St.Streak, St.BestStreak, St.Coins]), Px);

  { the pay }
  X := RightL;
  Y := R.Top + Pad;
  Px := F(9);
  SetFont(Px, True, False);
  FillColor(150, 125, 70);
  if Info.KillBonus > 0 then S := 'THE KILL PAYS' else S := 'THIS WIN PAYS';
  Y := Y + CenterText(RightL, RightR, Y, S, Px);
  Px := F(22);
  SetFont(Px, True, False);
  FillColor(232, 224, 204);
  Y := Y + CenterText(RightL, RightR, Y, PayText(Info), Px) + 2 * K;
  Px := F(10);
  SetFont(Px, False, False);
  RowH := Px * 1.28;
  Row(RightL, RightR, Y, 'Each win', '+' + IntToStr(Info.PerWin), Px, 232, 224, 204);
  Y := Y + RowH;
  if Info.KillBonus > 0 then
  begin
    Row(RightL, RightR, Y, 'Kill bonus', '+' + IntToStr(Info.KillBonus), Px, 232, 224, 204);
    Y := Y + RowH;
  end;
  if Info.LostHandsCut > 0 then
  begin
    Row(RightL, RightR, Y, Format('Lost hands (%d)', [Info.LostHands]), '-' + IntToStr(Info.LostHandsCut), Px, 214, 80, 92);
    Y := Y + RowH;
  end;
  if Info.MissCut > 0 then
  begin
    Row(RightL, RightR, Y, Format('Missed moves (%d)', [Info.Misses]), '-' + IntToStr(Info.MissCut), Px, 214, 80, 92);
    Y := Y + RowH;
  end;
  if Info.BiteCut > 0 then
  begin
    Row(RightL, RightR, Y, Format('Bitten cards (%d)', [Info.Bites]), '-' + IntToStr(Info.BiteCut), Px, 214, 80, 92);
    Y := Y + RowH;
  end;
  if Info.HazardText <> '' then
  begin
    SetFont(Px, False, True);
    FillColor(214, 80, 92);
    Y := Y + CenterWrapped(RightL, RightR, Y + 2 * K, Info.HazardText, Px);
  end;
  if Info.CrossText <> '' then
  begin
    SetFont(Px, False, True);
    FillColor(205, 208, 224);
    Y := Y + CenterWrapped(RightL, RightR, Y + 2 * K, Info.CrossText, Px);
  end;
  if Info.StuckWaiting then
  begin
    SetFont(Px, True, False);
    FillColor(214, 80, 92);
    CenterWrapped(RightL, RightR, Y + 2 * K, 'No moves left. Use an undo or special card, or press New Game to concede.', Px);
  end;
end;

procedure TWebView.DrawPanel;
var
  R: TRect;
  Info: TDuelInfo;
begin
  R := FCtl.PanelRect;
  if R.Right <= R.Left then Exit;
  Info := FCtl.DuelInfo;
  if FCtl.PanelPlacement = ppBottom then
  begin
    if Info.Active then DrawPanelStrip(R, Info, FCtl.PanelStats) else DrawFreeStrip(R, FCtl.PanelStats);
  end
  else
    DrawPanelColumn(R, Info, FCtl.PanelStats);
end;

{ ---- the Store and the card tray ---- }

{ Text clipped to R. }
procedure TWebView.ClipText(const R: TRect; const S: string; X, Y: Double);
begin
  FCtx.save;
  FCtx.beginPath;
  FCtx.rect(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top);
  FCtx.clip;
  Text(S, X, Y);
  FCtx.restore;
end;

procedure TWebView.DrawOverlayUi;
const
  ArtKey: array[0..OverlayArtCount - 1] of string = ('extraturn', 'easyrule', 'dawn', 'wild', 'seer', 'stake', 'undo', 'hint',
    'trophy_firstwin', 'trophy_perfect', 'trophy_jack', 'trophy_queen', 'trophy_king', 'trophy_flawless',
    '', 'relic_garlic', 'relic_pick', 'relic_spoon', 'relic_locket', 'relic_moonstone');
var
  P, Pt, Sp, R, B, TextR: TRect;
  I: Integer;
  K, X, Y, Px, TW: Double;
  Row: TOverlayRow;
  Lines: TJSArray;
  S: string;
  IconH, IconW: Double;
begin
  if FCtl.Overlay = okNone then Exit;
  DrawOverlay(0, 0, 0, 0.72);
  P := FCtl.OverlayPanelRect;
  K := Min((P.Right - P.Left) / 1100, (P.Bottom - P.Top) / 560);
  if K < 0.9 then K := 0.9;
  if K > 1.5 then K := 1.5;

  { the panel }
  FillColor(22, 13, 28);
  StrokeColor(201, 162, 74);
  FCtx.lineWidth := Max(2, 2 * K);
  RRect(P.Left, P.Top, P.Right - P.Left, P.Bottom - P.Top, 14 * K);
  FCtx.fill;
  FCtx.stroke;
  StrokeColor(110, 90, 46);
  FCtx.lineWidth := 1;
  RRect(P.Left + 6, P.Top + 6, P.Right - P.Left - 12, P.Bottom - P.Top - 12, 10 * K);
  FCtx.stroke;

  { his portrait }
  Pt := FCtl.OverlayPortraitRect;
  if Pt.Right > Pt.Left then
    FCtx.drawImage(ImageOf('shopkeeper'), Pt.Left, Pt.Top, Pt.Right - Pt.Left, Pt.Bottom - Pt.Top);

  { his words, or the tray's help }
  Sp := FCtl.OverlaySpeechRect;
  FillColor(30, 19, 38);
  StrokeColor(110, 90, 46);
  FCtx.lineWidth := 1;
  RRect(Sp.Left, Sp.Top, Sp.Right - Sp.Left, Sp.Bottom - Sp.Top, 9 * K);
  FCtx.fill;
  FCtx.stroke;
  X := Sp.Left + 12 * K;
  Y := Sp.Top + 8 * K;
  if FCtl.Overlay = okStore then
  begin
    Px := Max(17, 16 * K);
    SetFont(Px, True, True);
    FillColor(201, 162, 74);
    Text(FCtl.ShopkeeperName, X, Y);
    TW := TextW(FCtl.ShopkeeperName);
    SetFont(Max(13, 11 * K), False, True);
    FillColor(150, 125, 70);
    Text(FCtl.ShopkeeperTitle, X + TW + 10 * K, Y + 4);
    Y := Y + Px * 1.25 + 4 * K;
  end
  else
  begin
    Px := Max(17, 15 * K);
    SetFont(Px, True, False);
    FillColor(201, 162, 74);
    Text(FCtl.OverlayTitle, X, Y);
    Y := Y + Px * 1.25 + 2 * K;
  end;
  Px := Max(15, 13 * K);
  SetFont(Px, False, False);
  FillColor(232, 224, 204);
  Lines := WrapLines(Self, FCtl.OverlayLine, Sp.Right - Sp.Left - 24 * K);
  for I := 0 to Lines.length - 1 do
  begin
    if Y + Px * 1.2 > Sp.Bottom - 4 then Break;
    Text(string(Lines[I]), X, Y);
    Y := Y + Px * 1.22;
  end;
  if FCtl.OverlayHint <> '' then
  begin
    SetFont(Max(13, 10 * K), False, True);
    FillColor(150, 125, 70);
    S := FCtl.OverlayHint;
    Text(S, Sp.Right - TextW(S) - 12 * K, Sp.Bottom - Max(13, 10 * K) * 1.3 - 6);
  end;

  { the rows }
  { the tabs above the rows (the Style page) }
  for I := 0 to FCtl.OverlayTabCount - 1 do
  begin
    R := FCtl.OverlayTabRect(I);
    if FCtl.OverlayTabSelected(I) then
    begin
      FillColor(201, 162, 74);
      StrokeColor(150, 118, 46);
    end
    else
    begin
      FillColor(30, 19, 38);
      StrokeColor(110, 90, 46);
    end;
    FCtx.lineWidth := 1;
    RRect(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top, 8 * K);
    FCtx.fill;
    FCtx.stroke;
    SetFont(Max(14, 13 * K), True, False);
    if FCtl.OverlayTabSelected(I) then FillColor(30, 19, 38) else FillColor(232, 224, 204);
    S := FCtl.OverlayTabCaption(I);
    Text(S, R.Left + ((R.Right - R.Left) - TextW(S)) / 2, R.Top + ((R.Bottom - R.Top) - Max(14, 13 * K)) / 2 - 2);
  end;
  for I := 0 to FCtl.OverlayRowCount - 1 do
  begin
    Row := FCtl.OverlayRow(I);
    R := FCtl.OverlayRowRect(I);
    B := FCtl.OverlayButtonRect(I);
    if Row.Header then
    begin
      { a heading: just gold text with a thin rule under it }
      SetFont(Min(Max(15, 13 * K), (R.Bottom - R.Top) * 0.8), True, False);
      FillColor(201, 162, 74);
      Text(Row.Title, R.Left + 4, R.Top + ((R.Bottom - R.Top) - Min(Max(15, 13 * K), (R.Bottom - R.Top) * 0.8)) / 2 - 1);
      StrokeColor(110, 90, 46);
      FCtx.lineWidth := 1;
      FCtx.beginPath;
      FCtx.moveTo(R.Left, R.Bottom - 0.5);
      FCtx.lineTo(R.Right, R.Bottom - 0.5);
      FCtx.stroke;
      Continue;
    end;
    if Row.Selected then FillColor(46, 30, 56) else FillColor(30, 19, 38);
    if Row.Selected then StrokeColor(201, 162, 74) else StrokeColor(80, 64, 40);
    FCtx.lineWidth := 1;
    RRect(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top, 8 * K);
    FCtx.fill;
    FCtx.stroke;
    { the little card picture (the records page has none) }
    X := R.Left + 10 * K;
    if Row.Preview > 0 then
    begin
      IconH := R.Bottom - R.Top - 8;
      IconW := IconH * 164 / 232;
      DrawStylePreview(Rect(Round(R.Left + 6), Round(R.Top + 4), Round(R.Left + 6 + IconW), Round(R.Top + 4 + IconH)), Row.Preview);
      X := R.Left + 6 + IconW + 10 * K;
    end
    else if Row.Art >= 0 then
    begin
      IconH := R.Bottom - R.Top - 8;
      IconW := IconH * 164 / 232;
      if Row.Art = ArtTrophyEmpty then
      begin
        { a trophy not earned yet: an empty tile, the same shape as the pictures }
        FillColor(22, 13, 28);
        StrokeColor(110, 90, 46);
        RRect(R.Left + 6, R.Top + 4, IconW, IconH, Max(4, IconH / 8));
        FCtx.fill;
        FCtx.stroke;
        SetFont(Max(10, IconH * 0.5), True, False);
        FillColor(110, 90, 46);
        CenterText(R.Left + 6, R.Left + 6 + IconW, R.Top + 4 + (IconH - Max(10, IconH * 0.5) * 1.2) / 2, '?', Max(10, IconH * 0.5));
      end
      else
        FCtx.drawImage(ImageOf('special_' + ArtKey[Row.Art]), R.Left + 6, R.Top + 4, IconW, IconH);
      X := R.Left + 6 + IconW + 10 * K;
    end;
    if Row.Button2Text <> '' then TextR := Rect(Round(X), R.Top, FCtl.OverlayButton2Rect(I).Left - 12, R.Bottom)
    else if Row.ButtonText <> '' then TextR := Rect(Round(X), R.Top, B.Left - 70, R.Bottom)
    else if Row.Aside = '' then TextR := Rect(Round(X), R.Top, R.Right - 12, R.Bottom)
    else TextR := Rect(Round(X), R.Top, R.Right - 150, R.Bottom);
    if R.Bottom - R.Top >= 28 then
    begin
      Px := Min(Max(15, 14 * K), (R.Bottom - R.Top - 4) * 0.5);          { both lines must fit the row }
      SetFont(Px, True, False);
      FillColor(232, 224, 204);
      ClipText(TextR, Row.Title, X, R.Top + 2);
      SetFont(Min(Max(12, 11 * K), (R.Bottom - R.Top - 4) * 0.36), False, False);
      FillColor(150, 125, 70);
      ClipText(TextR, Row.Detail, X, R.Top + 2 + Px * 1.1);
    end
    else
    begin
      Px := Min(Max(14, 14 * K), (R.Bottom - R.Top) * 0.75);              { short rows: one line }
      SetFont(Px, True, False);
      FillColor(232, 224, 204);
      ClipText(TextR, Row.Title, X, R.Top + ((R.Bottom - R.Top) - Px) / 2 - 1);
    end;
    { price, count or record }
    Px := Min(Max(14, 13 * K), (R.Bottom - R.Top) * 0.75);
    SetFont(Px, True, False);
    FillColor(201, 162, 74);
    S := Row.Aside;
    if Row.ButtonText <> '' then
      Text(S, B.Left - TextW(S) - 10 * K, R.Top + ((R.Bottom - R.Top) - Px) / 2 - 2)
    else
      Text(S, R.Right - TextW(S) - 12 * K, R.Top + ((R.Bottom - R.Top) - Px) / 2 - 2);
    { the button }
    if Row.ButtonText <> '' then
    begin
      if Row.ButtonEnabled then
      begin
        FillColor(201, 162, 74);
        StrokeColor(150, 118, 46);
      end
      else
      begin
        FillColor(46, 36, 54);
        StrokeColor(70, 58, 44);
      end;
      RRect(B.Left, B.Top, B.Right - B.Left, B.Bottom - B.Top, 8 * K);
      FCtx.fill;
      FCtx.stroke;
      SetFont(Max(14, 13 * K), True, False);
      if Row.ButtonEnabled then FillColor(30, 19, 38) else FillColor(110, 98, 84);
      S := Row.ButtonText;
      Text(S, B.Left + ((B.Right - B.Left) - TextW(S)) / 2, B.Top + ((B.Bottom - B.Top) - Max(14, 13 * K)) / 2 - 2);
    end;
    { the second, smaller button (Delete on a saved game) }
    if Row.Button2Text <> '' then
    begin
      B := FCtl.OverlayButton2Rect(I);
      FillColor(46, 30, 56);
      if Row.Button2Enabled then StrokeColor(196, 60, 76) else StrokeColor(70, 58, 44);
      RRect(B.Left, B.Top, B.Right - B.Left, B.Bottom - B.Top, 8 * K);
      FCtx.fill;
      FCtx.stroke;
      SetFont(Max(14, 13 * K), True, False);
      if Row.Button2Enabled then FillColor(232, 224, 204) else FillColor(110, 98, 84);
      S := Row.Button2Text;
      Text(S, B.Left + ((B.Right - B.Left) - TextW(S)) / 2, B.Top + ((B.Bottom - B.Top) - Max(14, 13 * K)) / 2 - 2);
    end;
  end;

  { coins, and the Leave / Close button }
  R := FCtl.OverlayFooterRect;
  SetFont(Max(16, 14 * K), True, False);
  FillColor(201, 162, 74);
  Text(FCtl.OverlayFooter, R.Left, R.Top + ((R.Bottom - R.Top) - Max(16, 14 * K)) / 2 - 2);
  for I := 0 to FCtl.OverlayExtraCount - 1 do         { buttons beside Leave: the Store's Relics and Style }
  begin
    R := FCtl.OverlayExtraRect(I);
    FillColor(42, 29, 54);
    StrokeColor(110, 90, 46);
    RRect(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top, 8 * K);
    FCtx.fill;
    FCtx.stroke;
    SetFont(Max(16, 14 * K), True, False);
    FillColor(232, 224, 204);
    S := FCtl.OverlayExtraCaption(I);
    Text(S, R.Left + ((R.Right - R.Left) - TextW(S)) / 2, R.Top + ((R.Bottom - R.Top) - Max(16, 14 * K)) / 2 - 2);
  end;
  R := FCtl.OverlayLeaveRect;
  FillColor(42, 29, 54);
  StrokeColor(201, 162, 74);
  RRect(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top, 8 * K);
  FCtx.fill;
  FCtx.stroke;
  SetFont(Max(16, 14 * K), True, False);
  FillColor(232, 224, 204);
  S := FCtl.OverlayLeaveCaption;
  Text(S, R.Left + ((R.Right - R.Left) - TextW(S)) / 2, R.Top + ((R.Bottom - R.Top) - Max(16, 14 * K)) / 2 - 2);
end;

{ ---- everything ---- }

procedure TWebView.Paint(W, H: Integer; Dpr: Double);
begin
  FCtx.save;
  FCtx.setTransform(Dpr, 0, 0, Dpr, 0, FOriginY * Dpr);
  FCtx.beginPath;
  FCtx.rect(0, 0, W, H);
  FCtx.clip;
  PaintInner(W, H, Dpr);
  FCtx.restore;
end;

procedure TWebView.PaintHud(W, H: Integer; Dpr: Double);
begin
  FW := W;
  FH := H;
  FDpr := Dpr;
  FCtx.save;
  FCtx.setTransform(Dpr, 0, 0, Dpr, 0, FOriginY * Dpr);
  FCtx.beginPath;
  FCtx.rect(0, 0, W, H);
  FCtx.clip;
  FCtx.clearRect(0, 0, W, H);
  FCtx.textBaseline := 'top';
  FCtx.textAlign := 'left';
  FCtx.imageSmoothingEnabled := True;
  FCtl.SetViewport(W, H);
  DrawPanel;
  FCtx.restore;
end;

procedure TWebView.DrawMarkAt(const R: TRect; Kind: Integer);
begin
  FDpr := 1;
  FCtx.textBaseline := 'top';
  DrawMark(R, Kind);
end;

function TWebView.BackCardCanvas(W, H: Integer): TJSObject;
begin
  Result := BackCard(W, H);
end;

procedure TWebView.PaintInner(W, H: Integer; Dpr: Double);
var
  St: TStage;
begin
  FW := W;
  FH := H;
  FDpr := Dpr;
  FCtx.setTransform(Dpr, 0, 0, Dpr, 0, FOriginY * Dpr);
  FCtx.textBaseline := 'top';
  FCtx.textAlign := 'left';
  FCtx.imageSmoothingEnabled := True;
  FCtl.SetViewport(W, H);
  St := FCtl.Stage;
  if FCtl.MenuOpen then
  begin
    DrawMenu;
    DrawOverlayUi;                                         { the save / load slots, if open }
    Exit;
  end;
  DrawTableBackground;
  case St.Backdrop of
    sbDialogue: DrawDialogue;
    sbHouse: DrawHouseScene;
    sbWinPicture: DrawWinScreen(FCtl.WinMessage);
  else
  begin
    DrawTableContents;
    DrawPanel;
    DrawOverlay(190, 10, 20, St.Scalar[ssFlashRed]);       { a missed move flashes red }
  end;
  end;
  DrawOverlayUi;                                           { the Store or the card tray, if open }
  DrawOverlay(0, 0, 0, St.Scalar[ssDim]);                  { fading to or from black }
end;

end.
