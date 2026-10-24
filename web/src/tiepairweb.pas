program tiepairweb;

{ The web version of Perfect Pair: the same game (PairGame and everything under it)
  running in a browser. This file loads the pictures, draws the table on a canvas,
  turns taps and button presses into controller calls, and repaints when the
  controller says something changed. Saved data goes to the browser's local
  storage (see Storage). }

{$mode objfpc}{$H+}

uses
  JS, Web, SysUtils, Math, Types, Cards, Pyramid, PairGame, Version;

type
  TPairView = class
  private
    FCtx: TJSCanvasRenderingContext2D;
    FCtl: TPairController;
    FW, FH: Integer;
    FDpr: Double;
    FBack: TJSHTMLCanvasElement;
    FBackW, FBackH: Integer;
    procedure FillColor(R, G, B: Integer; A: Double = 1);
    procedure StrokeColor(R, G, B: Integer);
    procedure RRect(X, Y, W, H, R: Double);
    procedure SetFont(Px: Double; Bold, Italic: Boolean);
    function TextW(const S: string): Double;
    procedure Text(const S: string; X, Y: Double);
    function BackCard(W, H: Integer): TJSObject;
    procedure DrawBack(const R: TRect);
    procedure DrawFace(const R: TRect; const C: TCard);
    procedure Ring(const R: TRect; Cr, Cg, Cb: Integer; Width: Double);
    procedure Empty(const R: TRect; ARecycle: Boolean);
    procedure DrawTable;
    procedure DrawPanel;
    procedure DrawPiles;
    procedure DrawPyramid;
    procedure DrawBanner;
    function RectOf(APos: Integer): TRect;
  public
    constructor Create(ACtx: TJSCanvasRenderingContext2D; ACtl: TPairController);
    procedure Paint(W, H: Integer; Dpr: Double);
  end;

  TWebApp = class
  private
    FCtl: TPairController;
    FView: TPairView;
    FCanvas: TJSHTMLCanvasElement;
    FStageBox: TJSElement;
    FCtx: TJSCanvasRenderingContext2D;
    FScheduled: Boolean;
    FW, FH: Integer;
    FDpr: Double;
    FLastStatus: string;
    function El(const Id: string): TJSElement;
    procedure SetText(const Id, Value: string);
    procedure SetOn(const Id: string; AOn: Boolean);
    procedure Listen(const Id, Event: string; AHandler: TJSEventHandler);
    procedure ApplyUi;
    procedure FitCanvas;
    procedure DoPaint;
    procedure Invalidate;
    procedure Changed;
    procedure Frame(aTime: TJSDOMHighResTimeStamp);
    function OnPointerDown(Event: TEventListenerEvent): Boolean;
    function OnResize(Event: TEventListenerEvent): Boolean;
    function OnNew(Event: TEventListenerEvent): Boolean;
    function OnUndo(Event: TEventListenerEvent): Boolean;
    function OnHint(Event: TEventListenerEvent): Boolean;
    function OnMode(Event: TEventListenerEvent): Boolean;
    function OnKeyDown(Event: TEventListenerEvent): Boolean;
  public
    procedure Run;
    procedure Boot;
  end;

var
  App: TWebApp;

procedure GlueLoadImages(Pairs: TJSArray; Done: TProc); external name 'TCGlue.loadImages';
function ImageOf(const Key: string): TJSObject; external name 'TCGlue.getImage';

procedure GradStop(Gr: TJSCanvasGradient; Pos: Double; const Col: string);
begin
  asm
    Gr.addColorStop(Pos, Col);
  end;
end;

{ ---- drawing ---- }

constructor TPairView.Create(ACtx: TJSCanvasRenderingContext2D; ACtl: TPairController);
begin
  inherited Create;
  FCtx := ACtx;
  FCtl := ACtl;
  FDpr := 1;
end;

procedure TPairView.FillColor(R, G, B: Integer; A: Double);
begin
  if A >= 1 then FCtx.fillStyle := Format('rgb(%d,%d,%d)', [R, G, B])
  else FCtx.fillStyle := Format('rgba(%d,%d,%d,%s)', [R, G, B, FloatToStr(A)]);
end;

procedure TPairView.StrokeColor(R, G, B: Integer);
begin
  FCtx.strokeStyle := Format('rgb(%d,%d,%d)', [R, G, B]);
end;

procedure TPairView.RRect(X, Y, W, H, R: Double);
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

procedure TPairView.SetFont(Px: Double; Bold, Italic: Boolean);
var
  S: string;
begin
  S := '';
  if Italic then S := 'italic ';
  if Bold then S := S + 'bold ';
  FCtx.font := S + IntToStr(Round(Px)) + 'px "Times New Roman", Georgia, "Liberation Serif", serif';
  FCtx.textBaseline := 'top';
end;

function TPairView.TextW(const S: string): Double;
begin
  Result := FCtx.measureText(S).width;
end;

procedure TPairView.Text(const S: string; X, Y: Double);
begin
  FCtx.fillText(S, X, Y);
end;

{ The card back, drawn once per size: the same gothic moon as Tiecards. }
function TPairView.BackCard(W, H: Integer): TJSObject;
var
  C2: TJSCanvasRenderingContext2D;
  PW, PH, Inset, L, T, Rt, B, K, Step, Lo, Hi, CX, CY, Rad, Sz: Integer;
const
  Base = 'rgb(42,13,26)'; Dark = 'rgb(13,6,8)'; Line = 'rgb(74,26,44)'; Gold = 'rgb(201,162,74)'; Dim = 'rgb(122,42,58)';
begin
  if (FBack <> nil) and (FBackW = W) and (FBackH = H) then
  begin
    Result := FBack;
    Exit;
  end;
  FBack := TJSHTMLCanvasElement(document.createElement('canvas'));
  FBackW := W;
  FBackH := H;
  PW := Round(W * FDpr);
  PH := Round(H * FDpr);
  FBack.width := PW;
  FBack.height := PH;
  C2 := FBack.getContextAs2DContext('2d');
  C2.scale(FDpr, FDpr);
  C2.fillStyle := Base;
  C2.strokeStyle := Dark;
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
  Inset := W div 7;
  L := Inset; T := Inset; Rt := W - Inset; B := H - Inset;
  C2.save;
  C2.beginPath;
  C2.rect(L, T, Rt - L, B - T);
  C2.clip;
  C2.strokeStyle := Line;
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
  C2.strokeStyle := Gold;
  C2.lineWidth := W div 40 + 1;
  C2.beginPath;
  C2.moveTo(W / 12 + W / 20, W / 12);
  C2.arcTo(W - W / 12, W / 12, W - W / 12, H - W / 12, W / 20);
  C2.arcTo(W - W / 12, H - W / 12, W / 12, H - W / 12, W / 20);
  C2.arcTo(W / 12, H - W / 12, W / 12, W / 12, W / 20);
  C2.arcTo(W / 12, W / 12, W - W / 12, W / 12, W / 20);
  C2.closePath;
  C2.stroke;
  C2.strokeStyle := Dim;
  C2.lineWidth := 1;
  C2.beginPath;
  C2.moveTo(W / 8 + 1 + W / 24, W / 8 + 1);
  C2.arcTo(W - W / 8 - 1, W / 8 + 1, W - W / 8 - 1, H - W / 8 - 1, W / 24);
  C2.arcTo(W - W / 8 - 1, H - W / 8 - 1, W / 8 + 1, H - W / 8 - 1, W / 24);
  C2.arcTo(W / 8 + 1, H - W / 8 - 1, W / 8 + 1, W / 8 + 1, W / 24);
  C2.arcTo(W / 8 + 1, W / 8 + 1, W - W / 8 - 1, W / 8 + 1, W / 24);
  C2.closePath;
  C2.stroke;
  CX := W div 2;
  CY := H div 2;
  Rad := W * 28 div 100;
  C2.fillStyle := Dark;
  C2.strokeStyle := Gold;
  C2.lineWidth := W div 50 + 1;
  C2.beginPath; C2.arc(CX, CY, Rad, 0, 2 * Pi); C2.fill; C2.stroke;
  C2.fillStyle := Gold;
  Rad := W * 17 div 100;
  C2.beginPath; C2.arc(CX, CY, Rad, 0, 2 * Pi); C2.fill;
  C2.fillStyle := Dark;
  Rad := W * 15 div 100;
  C2.beginPath;
  C2.arc(CX + W * 7 div 100, CY - W * 3 div 100, Rad, 0, 2 * Pi);
  C2.fill;
  C2.fillStyle := Gold;
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

procedure TPairView.DrawBack(const R: TRect);
begin
  FCtx.drawImage(BackCard(R.Right - R.Left, R.Bottom - R.Top), R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top);
end;

procedure TPairView.DrawFace(const R: TRect; const C: TCard);
const
  Suits: array[TSuit] of string = ('clubs', 'diamonds', 'hearts', 'spades');
begin
  FCtx.drawImage(ImageOf('card_' + Suits[C.Suit] + '_' + Format('%.2d', [C.Rank])), R.Left, R.Top,
    R.Right - R.Left, R.Bottom - R.Top);
end;

procedure TPairView.Ring(const R: TRect; Cr, Cg, Cb: Integer; Width: Double);
begin
  FCtx.save;
  FCtx.shadowColor := Format('rgba(%d,%d,%d,0.9)', [Cr, Cg, Cb]);
  FCtx.shadowBlur := FCtl.Scaled(14);
  StrokeColor(Cr, Cg, Cb);
  FCtx.lineWidth := Width;
  RRect(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top, FCtl.Scaled(7));
  FCtx.stroke;
  FCtx.restore;
end;

{ An empty place for a pile; with a turn-over arrow when the waste can be turned over. }
procedure TPairView.Empty(const R: TRect; ARecycle: Boolean);
var
  CX, CY, Rad: Double;
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
    StrokeColor(226, 195, 117);
    FCtx.lineWidth := Max(2, FCtl.Scaled(4));
    FCtx.beginPath;
    FCtx.arc(CX, CY, Rad, 0.4, 2 * Pi - 0.9);
    FCtx.stroke;
    FillColor(226, 195, 117);
    FCtx.beginPath;
    FCtx.moveTo(CX + Rad * Cos(2 * Pi - 0.9) - Rad * 0.55, CY + Rad * Sin(2 * Pi - 0.9) - Rad * 0.2);
    FCtx.lineTo(CX + Rad * Cos(2 * Pi - 0.9) + Rad * 0.65, CY + Rad * Sin(2 * Pi - 0.9) - Rad * 0.35);
    FCtx.lineTo(CX + Rad * Cos(2 * Pi - 0.9) + Rad * 0.1, CY + Rad * Sin(2 * Pi - 0.9) + Rad * 0.6);
    FCtx.closePath;
    FCtx.fill;
  end;
end;

procedure TPairView.DrawTable;
var
  Gr: TJSCanvasGradient;
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
  FCtx.save;
  FCtx.translate(FW / 2, FH / 2);
  FCtx.scale(FW / 2, FH / 2);
  Gr := FCtx.createRadialGradient(0, 0, 0, 0, 0, Sqrt(2));
  GradStop(Gr, 0, 'rgb(24,74,48)');
  GradStop(Gr, 0.45, 'rgb(15,46,31)');
  GradStop(Gr, 1, 'rgb(5,16,11)');
  FCtx.fillStyle := Gr;
  FCtx.fillRect(-1, -1, 2, 2);
  FCtx.restore;
  M := Max(6, Min(FW, FH) div 55);
  Th := Max(1, Round(Min(FW, FH) / 500));
  Dm := Max(3, M div 2);
  FCtx.strokeStyle := 'rgb(110,90,46)';
  FCtx.lineWidth := Th;
  FCtx.strokeRect(M, M, FW - 2 * M, FH - 2 * M);
  FCtx.fillStyle := 'rgb(110,90,46)';
  Diamond(M, M);
  Diamond(FW - M, M);
  Diamond(M, FH - M);
  Diamond(FW - M, FH - M);
end;

procedure TPairView.DrawPanel;
var
  P: TRect;
  K, X0, X1, Y, W, ImgH: Double;
  Ui: TPairUi;

  procedure Row(const LabelText, Value: string);
  begin
    SetFont(15 * K, False, False);
    FillColor(150, 139, 70);
    Text(LabelText, X0, Y);
    FillColor(232, 224, 204);
    Text(Value, X1 - TextW(Value), Y);
    Y := Y + 22 * K;
  end;

begin
  P := FCtl.PanelRect;
  if P.Right - P.Left < 20 then Exit;
  Ui := FCtl.GetUi;
  K := (P.Right - P.Left) / 248;
  FillColor(18, 10, 26, 0.94);
  RRect(P.Left + 8, 8, P.Right - P.Left - 16, FH - 16, 12);
  FCtx.fill;
  StrokeColor(201, 162, 74);
  FCtx.lineWidth := 2;
  RRect(P.Left + 8, 8, P.Right - P.Left - 16, FH - 16, 12);
  FCtx.stroke;
  X0 := P.Left + 24;
  X1 := P.Right - 24;
  W := X1 - X0;
  Y := 26;
  SetFont(30 * K, True, True);
  FillColor(232, 224, 204);
  Text('Perfect Pair', P.Left + ((P.Right - P.Left) - TextW('Perfect Pair')) / 2, Y);
  Y := Y + 40 * K;
  SetFont(14 * K, False, True);
  FillColor(201, 162, 74);
  Text('Pyramid solitaire', P.Left + ((P.Right - P.Left) - TextW('Pyramid solitaire')) / 2, Y);
  Y := Y + 28 * K;
  ImgH := W * 1000 / 1600;
  FCtx.save;
  RRect(X0, Y, W, ImgH, 8);
  FCtx.clip;
  FCtx.drawImage(ImageOf('house'), X0, Y, W, ImgH);
  FCtx.restore;
  StrokeColor(201, 162, 74);
  FCtx.lineWidth := 1.5;
  RRect(X0, Y, W, ImgH, 8);
  FCtx.stroke;
  Y := Y + ImgH + 22 * K;
  Row('Cards left', IntToStr(Ui.CardsLeft));
  Row('Stock', IntToStr(Ui.StockCount));
  Row('Waste', IntToStr(Ui.WasteCount));
  Row('Turn-overs left', IntToStr(Ui.RecyclesLeft));
  Row('Mode', Copy(Ui.ModeCaption, 7, 20));
  Y := Y + 10 * K;
  SetFont(14 * K, False, True);
  FillColor(176, 164, 189);
  Text('Take away Kings,', X0, Y);
  Text('and pairs that add up to 13.', X0, Y + 18 * K);
  if Ui.Easy then
  begin
    Text('A card may go with the', X0, Y + 40 * K);
    Text('one sitting on top of it.', X0, Y + 58 * K);
    Text('A 1  Q 12  K 13', X0, Y + 84 * K);
  end
  else
    Text('A 1  Q 12  K 13', X0, Y + 44 * K);
  SetFont(12 * K, False, False);
  FillColor(120, 110, 70);
  Text('v' + AppVersion, X1 - TextW('v' + AppVersion), FH - 34 * K);
end;

function TPairView.RectOf(APos: Integer): TRect;
begin
  if APos = PosWaste then Result := FCtl.WasteRect else Result := FCtl.CardRect(APos);
end;

procedure TPairView.DrawPiles;
var
  S, W: TRect;
  C: TCard;
  Ui: TPairUi;
  Cap: string;
begin
  S := FCtl.StockRect;
  W := FCtl.WasteRect;
  Ui := FCtl.GetUi;
  if FCtl.Game.StockCount > 0 then
  begin
    DrawBack(S);
    if FCtl.HintStock then Ring(S, 110, 220, 255, Max(2, FCtl.Scaled(4)));
  end
  else
  begin
    Empty(S, FCtl.Game.CanRecycle);
    if FCtl.HintStock then Ring(S, 110, 220, 255, Max(2, FCtl.Scaled(4)));
  end;
  if FCtl.Game.WasteTop(C) then
  begin
    DrawFace(W, C);
    if FCtl.Selected = PosWaste then Ring(W, 255, 215, 0, Max(3, FCtl.Scaled(5)));
    if (FCtl.HintA = PosWaste) or (FCtl.HintB = PosWaste) then Ring(W, 110, 220, 255, Max(2, FCtl.Scaled(4)));
  end
  else
    Empty(W, False);
  SetFont(Max(12, FCtl.Scaled(16)), False, True);
  FillColor(176, 164, 189);
  Text('Stock ' + IntToStr(Ui.StockCount), S.Left, S.Bottom + FCtl.Scaled(4));
  Text('Waste ' + IntToStr(Ui.WasteCount), W.Left, W.Bottom + FCtl.Scaled(4));
  if FCtl.PanelRect.Right - FCtl.PanelRect.Left < 20 then      { no side panel: the numbers go here }
  begin
    Cap := Format('Cards left %d   Turn-overs left %d', [Ui.CardsLeft, Ui.RecyclesLeft]);
    SetFont(Max(12, FCtl.Scaled(16)), False, True);
    FillColor(226, 195, 117);
    Text(Cap, FCtl.TableRect.Right - TextW(Cap) - FCtl.Scaled(14), W.Top + FCtl.Scaled(10));
  end;
end;

procedure TPairView.DrawPyramid;
var
  I: Integer;
  R: TRect;
  Hint: Boolean;
begin
  for I := 0 to PyramidSize - 1 do
    if not FCtl.Game.Removed(I) then
    begin
      R := FCtl.CardRect(I);
      DrawFace(R, FCtl.Game.CardAt(I));
      if not FCtl.Game.IsFree(I) and not FCtl.Game.IsUnder(I) then      { a covered card is dimmed }
      begin
        FillColor(8, 4, 16, 0.38);
        RRect(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top, FCtl.Scaled(7));
        FCtx.fill;
      end;
    end;
  { the rings go on afterwards, so that no card covers them }
  for I := 0 to PyramidSize - 1 do
    if not FCtl.Game.Removed(I) then
    begin
      R := FCtl.CardRect(I);
      Hint := (FCtl.HintA = I) or (FCtl.HintB = I);
      if FCtl.Selected = I then Ring(R, 255, 215, 0, Max(3, FCtl.Scaled(5)))
      else if Hint then Ring(R, 110, 220, 255, Max(2, FCtl.Scaled(4)));
    end;
end;

procedure TPairView.DrawBanner;
var
  Ui: TPairUi;
  T: TRect;
  Msg, Sub: string;
  CX, CY, Px: Double;
begin
  Ui := FCtl.GetUi;
  if not Ui.Won then Exit;
  T := FCtl.TableRect;
  FillColor(8, 4, 16, 0.72);
  FCtx.fillRect(T.Left, T.Top, T.Right - T.Left, T.Bottom - T.Top);
  Msg := 'You cleared the pyramid!';
  Sub := 'Tap anywhere for a new hand';
  CX := (T.Left + T.Right) / 2;
  CY := (T.Top + T.Bottom) / 2;
  Px := Max(24, Min(T.Right - T.Left, T.Bottom - T.Top) / 11);
  SetFont(Px, True, True);
  FillColor(0, 0, 0);
  Text(Msg, CX - TextW(Msg) / 2 + 2, CY - Px + 2);
  FillColor(232, 224, 204);
  Text(Msg, CX - TextW(Msg) / 2, CY - Px);
  SetFont(Px * 0.45, False, True);
  FillColor(201, 162, 74);
  Text(Sub, CX - TextW(Sub) / 2, CY + Px * 0.2);
end;

procedure TPairView.Paint(W, H: Integer; Dpr: Double);
begin
  FW := W;
  FH := H;
  if Dpr <> FDpr then
  begin
    FDpr := Dpr;
    FBack := nil;
  end;
  FCtx.setTransform(Dpr, 0, 0, Dpr, 0, 0);
  FCtx.clearRect(0, 0, W, H);
  FCtl.SetViewportQuiet(W, H);
  DrawTable;
  DrawPanel;
  DrawPyramid;
  DrawPiles;
  DrawBanner;
end;

{ ---- the page ---- }

function TWebApp.El(const Id: string): TJSElement;
begin
  Result := document.getElementById(Id);
end;

procedure TWebApp.SetText(const Id, Value: string);
var
  E: TJSElement;
begin
  E := El(Id);
  if E <> nil then E.textContent := Value;
end;

procedure TWebApp.SetOn(const Id: string; AOn: Boolean);
var
  E: TJSElement;
begin
  E := El(Id);
  if E = nil then Exit;
  asm
    if (AOn) { E.classList.remove('off'); E.setAttribute('aria-disabled', 'false'); }
    else { E.classList.add('off'); E.setAttribute('aria-disabled', 'true'); }
  end;
end;

procedure TWebApp.Listen(const Id, Event: string; AHandler: TJSEventHandler);
var
  E: TJSElement;
begin
  E := El(Id);
  if E <> nil then E.addEventListener(Event, AHandler);
end;

procedure TWebApp.ApplyUi;
var
  U: TPairUi;
begin
  U := FCtl.GetUi;
  if U.Status <> FLastStatus then
  begin
    SetText('status', U.Status);
    FLastStatus := U.Status;
  end;
  SetText('btnMode', U.ModeCaption);
  SetOn('btnUndo', U.UndoEnabled);
  SetOn('btnHint', U.HintEnabled);
end;

procedure TWebApp.Changed;
begin
  ApplyUi;
  Invalidate;
end;

procedure TWebApp.FitCanvas;
var
  W, H: Integer;
  D: Double;
begin
  W := FStageBox.clientWidth;
  H := FStageBox.clientHeight;
  if W < 50 then W := 50;
  if H < 50 then H := 50;
  D := window.devicePixelRatio;
  if D < 1 then D := 1;
  if D > 3 then D := 3;
  if (W = FW) and (H = FH) and (D = FDpr) then Exit;
  FW := W;
  FH := H;
  FDpr := D;
  FCanvas.width := Round(W * D);
  FCanvas.height := Round(H * D);
  FCanvas.style.setProperty('width', IntToStr(W) + 'px');
  FCanvas.style.setProperty('height', IntToStr(H) + 'px');
end;

procedure TWebApp.DoPaint;
begin
  FitCanvas;
  FView.Paint(FW, FH, FDpr);
end;

procedure TWebApp.Invalidate;
begin
  if FScheduled then Exit;
  FScheduled := True;
  window.requestAnimationFrame(@Frame);
end;

procedure TWebApp.Frame(aTime: TJSDOMHighResTimeStamp);
begin
  FScheduled := False;
  DoPaint;
end;

function TWebApp.OnPointerDown(Event: TEventListenerEvent): Boolean;
var
  Rect: TJSDOMRect;
begin
  Event.preventDefault;
  Rect := FCanvas.getBoundingClientRect;
  FCtl.Tap(Round(TJSMouseEvent(Event).clientX - Rect.left), Round(TJSMouseEvent(Event).clientY - Rect.top));
  Result := False;
end;

function TWebApp.OnResize(Event: TEventListenerEvent): Boolean;
begin
  FitCanvas;
  FCtl.SetViewport(FW, FH);
  Result := True;
end;

function TWebApp.OnNew(Event: TEventListenerEvent): Boolean;
begin
  FCtl.ActionNew;
  Result := True;
end;

function TWebApp.OnUndo(Event: TEventListenerEvent): Boolean;
begin
  FCtl.ActionUndo;
  Result := True;
end;

function TWebApp.OnHint(Event: TEventListenerEvent): Boolean;
begin
  FCtl.ActionHint;
  Result := True;
end;

function TWebApp.OnMode(Event: TEventListenerEvent): Boolean;
begin
  FCtl.ActionToggleEasy;
  Result := True;
end;

function TWebApp.OnKeyDown(Event: TEventListenerEvent): Boolean;
var
  K: string;
begin
  K := LowerCase(string(TJSObject(Event)['key']));
  Result := True;
  if K = 'n' then FCtl.ActionNew
  else if (K = 'u') or (K = 'z') then FCtl.ActionUndo
  else if K = 'h' then FCtl.ActionHint
  else if K = 'm' then FCtl.ActionToggleEasy
  else Result := False;
end;

procedure TWebApp.Boot;
var
  E: TJSElement;
begin
  FCanvas := TJSHTMLCanvasElement(El('table'));
  FStageBox := El('stage');
  FCtx := FCanvas.getContextAs2DContext('2d');
  FCtl := TPairController.Create;
  FCtl.OnChange := @Changed;
  FView := TPairView.Create(FCtx, FCtl);
  FitCanvas;
  FCtl.SetViewport(FW, FH);
  FCanvas.addEventListener('pointerdown', @OnPointerDown);
  window.addEventListener('keydown', @OnKeyDown);
  window.addEventListener('resize', @OnResize);
  window.addEventListener('orientationchange', @OnResize);
  Listen('btnNew', 'click', @OnNew);
  Listen('btnUndo', 'click', @OnUndo);
  Listen('btnHint', 'click', @OnHint);
  Listen('btnMode', 'click', @OnMode);
  FCtl.Start;
  E := El('loading');
  if E <> nil then E.parentNode.removeChild(E);
  DoPaint;
  ApplyUi;
end;

procedure TWebApp.Run;
var
  Pairs: TJSArray;
  Su, R: Integer;
const
  Suits: array[0..3] of string = ('clubs', 'diamonds', 'hearts', 'spades');
begin
  Pairs := TJSArray.new;
  for Su := 0 to 3 do
    for R := 1 to 13 do
    begin
      Pairs.push('card_' + Suits[Su] + '_' + Format('%.2d', [R]));
      Pairs.push('assets/cards/card_' + Suits[Su] + '_' + Format('%.2d', [R]) + '.png');
    end;
  Pairs.push('house');
  Pairs.push('assets/house/house.png');
  GlueLoadImages(Pairs, @Boot);
end;

begin
  App := TWebApp.Create;
  App.Run;
end.
