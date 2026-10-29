unit VrPanel;

{ What the game looks like on the flat panel that floats in front of you in VR.
  The game itself is drawn by a TWebView (the same drawing as the page) into the
  lower part of the panel's canvas. Everything the page has as HTML (the toolbar,
  the status line, the Skip and Cancel buttons and the five dialogs) cannot be seen
  in VR, so it is drawn here, on the same canvas, and a tap is sorted out here too:
  on a dialog, on a toolbar button, or on the game (which goes to the controller
  exactly as a tap on the page would). Coordinates are CSS pixels of the panel. }

{$mode objfpc}{$H+}

interface

uses
  JS, Web, SysUtils, Math, Types, Cards, Pyramid, Stage, Cosmetics, GameController, WebView;

const
  VrW = 1280;                { the panel, in CSS pixels }
  VrH = 640;
  VrDpr = 1.5;               { canvas pixels per CSS pixel }
  VrBarH = 84;               { the toolbar and the status line; the game is drawn below them }
  { the buttons: the toolbar, then the two that float over the game }
  vbNew = 0;
  vbUndo = 1;
  vbStore = 2;
  vbHint = 3;
  vbCards = 4;
  vbMenu = 5;
  vbStartOver = 6;
  vbRecords = 7;
  vbMode = 8;                { Normal / Easy in Free Play }
  vbExit = 9;
  vbSkip = 10;
  vbCancel = 11;
  vbCheat = 12;              { the testing button on the menu (only with ?vrdebug) }
  VrButtons = 13;

type
  TVrDialog = (vdNone, vdOver, vdCross, vdDelete, vdInitials, vdRules);

  { A toolbar button was tapped (vb...). }
  TVrButtonEvent = procedure(Id: Integer) of object;
  { A dialog button was tapped: Choice is its position from the left (0, 1, ...); for the
    initials Text is the three letters. }
  TVrAnswerEvent = procedure(K: TVrDialog; Choice: Integer; const Text: string) of object;
  TVrNotify = procedure of object;

  TVrLine = record
    Text: string;
    Kind: Integer;           { 0 body, 1 heading, 2 blank }
  end;

  TVrPanel = class
  private
    FCtl: TGameController;
    FView: TWebView;
    FCtx: TJSCanvasRenderingContext2D;
    FDialog: TVrDialog;
    FPrompt: string;
    FLetters: array[0..2] of Integer;
    FLines: array of TVrLine;            { the rules, wrapped }
    FPage, FPerPage: Integer;
    FBtn: array[0..VrButtons - 1] of TRect;
    FBtnShown: array[0..VrButtons - 1] of Boolean;
    FChoice: array[0..3] of TRect;       { the dialog's buttons }
    FChoiceCount: Integer;
    FPrev, FNext: TRect;                 { the rules' page buttons }
    FArrow: array[0..5] of TRect;        { the initials: three up arrows, then three down }
    FOnButton: TVrButtonEvent;
    FOnAnswer: TVrAnswerEvent;
    FOnInvalidate: TVrNotify;
    FDebug: string;
    FCheats: Boolean;
    FMarkCv: array[1..3] of TJSHTMLCanvasElement;
    procedure RRect(X, Y, W, H, R: Double);
    procedure SetFont(Px: Double; Bold, Italic: Boolean);
    function TextW(const S: string): Double;
    procedure Fill(R, G, B: Integer; A: Double = 1);
    procedure Stroke(R, G, B: Integer);
    procedure DrawButton(const R: TRect; const Cap: string; AOn, Danger: Boolean; Px: Double);
    procedure WrapPlain(const S: string; MaxW: Double; Dest: TJSArray);
    procedure DrawToolbar;
    procedure DrawDialog;
    procedure BuildRules;
    procedure Changed;
    procedure ChooseDialog(Choice: Integer);
  public
    constructor Create(ACtl: TGameController; AView: TWebView; ACtx: TJSCanvasRenderingContext2D);
    procedure Paint;
    { Same toolbar and status line, but the game itself is left to the 3D table: only the
      duel panel is drawn under them. }
    procedure PaintHud;
    { True when the cards can be shown as a 3D table: they are on the table, and nothing
      else (a scene, the menu, the Store, a dialog, the win picture) is in front of them. }
    function TableActive: Boolean;
    { What the 3D table needs to know, as a flat list of numbers (see the layout in the
      body), or nil when TableActive is false. }
    function TableSnapshot: TJSArray;
    { A tap on card Slot (0..27 the peaks, 29 the stock) of the 3D table. }
    procedure TapSlot(Slot: Integer);
    function MarkCanvas(Kind: Integer): TJSObject;
    { The player's Style choices: the moon, then the cloth's four colours (packed like the
      table's), then the card back, then the key of the house picture with his moon. Always answers (the room is there on every screen). }
    function StyleList: TJSArray;
    procedure Tap(X, Y: Double);
    property DebugText: string read FDebug write FDebug;
    { Testing aid for a headset, where the menu's hidden cheat word cannot be typed: with this
      on, the menu shows a "+900 coins" button that types the word for you. }
    property Cheats: Boolean read FCheats write FCheats;
    procedure TypeCheat;
    procedure OpenDialog(K: TVrDialog; const APrompt: string; const ADefault: string = '');
    procedure CloseDialog;
    property Dialog: TVrDialog read FDialog;
    property OnButton: TVrButtonEvent read FOnButton write FOnButton;
    property OnAnswer: TVrAnswerEvent read FOnAnswer write FOnAnswer;
    property OnInvalidate: TVrNotify read FOnInvalidate write FOnInvalidate;
  end;

implementation

const
  FontStack = '"Times New Roman", Georgia, "Liberation Serif", serif';

constructor TVrPanel.Create(ACtl: TGameController; AView: TWebView; ACtx: TJSCanvasRenderingContext2D);
begin
  inherited Create;
  FCtl := ACtl;
  FView := AView;
  FCtx := ACtx;
  FDialog := vdNone;
end;

procedure TVrPanel.Changed;
begin
  if Assigned(FOnInvalidate) then FOnInvalidate();
end;

{ ---- small drawing helpers ---- }

procedure TVrPanel.RRect(X, Y, W, H, R: Double);
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

procedure TVrPanel.SetFont(Px: Double; Bold, Italic: Boolean);
var
  S: string;
begin
  S := '';
  if Italic then S := 'italic ';
  if Bold then S := S + 'bold ';
  FCtx.font := S + IntToStr(Round(Px)) + 'px ' + FontStack;
end;

function TVrPanel.TextW(const S: string): Double;
begin
  Result := FCtx.measureText(S).width;
end;

procedure TVrPanel.Fill(R, G, B: Integer; A: Double);
begin
  if A >= 1 then
    FCtx.fillStyle := Format('rgb(%d,%d,%d)', [R, G, B])
  else
    FCtx.fillStyle := Format('rgba(%d,%d,%d,%s)', [R, G, B, FloatToStr(A)]);
end;

procedure TVrPanel.Stroke(R, G, B: Integer);
begin
  FCtx.strokeStyle := Format('rgb(%d,%d,%d)', [R, G, B]);
end;

{ A button like the page's: dark plum with a gold edge, dim when it is "off". }
procedure TVrPanel.DrawButton(const R: TRect; const Cap: string; AOn, Danger: Boolean; Px: Double);
begin
  RRect(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top, 8);
  if AOn then Fill(42, 29, 54) else Fill(30, 22, 40);
  FCtx.fill;
  FCtx.lineWidth := 2;
  if Danger then Stroke(214, 80, 92) else Stroke(201, 162, 74);
  if not AOn then FCtx.globalAlpha := 0.45;
  FCtx.stroke;
  SetFont(Px, False, False);
  if AOn then Fill(232, 224, 204) else Fill(190, 180, 170);
  FCtx.textAlign := 'center';
  FCtx.textBaseline := 'middle';
  FCtx.fillText(Cap, (R.Left + R.Right) / 2, (R.Top + R.Bottom) / 2 + 1);
  FCtx.globalAlpha := 1;
end;

{ Cuts S into lines no wider than MaxW (at the font already set), appended to Lines. }
procedure TVrPanel.WrapPlain(const S: string; MaxW: Double; Dest: TJSArray);
var
  Words: TJSArray;
  I: Integer;
  Cur, Attempt: string;
begin
  Words := TJSArray(TJSString(S).split(' '));
  Cur := '';
  for I := 0 to Words.length - 1 do
  begin
    if Cur = '' then Attempt := string(Words[I]) else Attempt := Cur + ' ' + string(Words[I]);
    if (Cur <> '') and (TextW(Attempt) > MaxW) then
    begin
      Dest.push(Cur);
      Cur := string(Words[I]);
    end
    else
      Cur := Attempt;
  end;
  if Cur <> '' then Dest.push(Cur);
end;

{ ---- the toolbar ---- }

procedure TVrPanel.DrawToolbar;
const
  Gap = 8;
  Pad = 26;
var
  U: TUiState;
  Caps: array[0..9] of string;
  Ons: array[0..9] of Boolean;
  W: array[0..9] of Double;
  I: Integer;
  Total, K, X: Double;
  R: TRect;
begin
  U := FCtl.GetUi;
  Caps[vbNew] := 'New Game';       Ons[vbNew] := not FCtl.MenuOpen;
  Caps[vbUndo] := U.UndoCaption;   Ons[vbUndo] := U.UndoEnabled;
  Caps[vbStore] := U.StoreCaption; Ons[vbStore] := U.StoreEnabled;
  Caps[vbHint] := U.HintCaption;   Ons[vbHint] := U.HintEnabled;
  Caps[vbCards] := U.CardsCaption; Ons[vbCards] := U.CardsEnabled;
  Caps[vbMenu] := U.MenuCaption;   Ons[vbMenu] := True;
  Caps[vbStartOver] := 'Start over'; Ons[vbStartOver] := not FCtl.MenuOpen;
  Caps[vbRecords] := U.RecordsCaption; Ons[vbRecords] := U.RecordsEnabled;
  Caps[vbMode] := U.EasyCaption;   Ons[vbMode] := U.EasyEnabled;
  Caps[vbExit] := 'Exit VR';       Ons[vbExit] := True;
  Fill(20, 16, 28);
  FCtx.fillRect(0, 0, VrW, VrBarH);
  Fill(58, 48, 32);
  FCtx.fillRect(0, VrBarH - 1, VrW, 1);
  SetFont(17, False, False);
  Total := 0;
  for I := 0 to 9 do
  begin
    W[I] := TextW(Caps[I]) + Pad;
    Total := Total + W[I];
  end;
  Total := Total + 9 * Gap;
  K := 1;
  if Total > VrW - 16 then K := (VrW - 16 - 9 * Gap) / (Total - 9 * Gap);
  X := 8;
  for I := 0 to 9 do
  begin
    R := Rect(Round(X), 8, Round(X + W[I] * K), 52);
    FBtn[I] := R;
    FBtnShown[I] := True;
    DrawButton(R, Caps[I], Ons[I], False, 17);
    X := X + W[I] * K + Gap;
  end;
  { the status line }
  SetFont(18, False, True);
  Fill(150, 139, 70);
  FCtx.textAlign := 'left';
  FCtx.textBaseline := 'middle';
  FCtx.fillText(U.StatusText, 12, 70);
  if FDebug <> '' then
  begin
    SetFont(15, False, False);
    Fill(120, 110, 90);
    FCtx.textAlign := 'right';
    FCtx.fillText(FDebug, VrW - 12, 70);
    FCtx.textAlign := 'left';
  end;
  FBtnShown[vbCheat] := FCheats and FCtl.MenuOpen and (FCtl.Overlay = okNone) and (FDialog = vdNone);
  if FBtnShown[vbCheat] then
  begin
    FBtn[vbCheat] := Rect(12, VrH - 52, 232, VrH - 12);
    DrawButton(FBtn[vbCheat], '+900 coins (test)', True, False, 16);
  end;
  { Skip and Cancel float over the game }
  FBtnShown[vbSkip] := U.CanSkip;
  FBtnShown[vbCancel] := U.Targeting;
  if U.CanSkip then
  begin
    FBtn[vbSkip] := Rect(VrW - 130, VrBarH + 10, VrW - 12, VrBarH + 54);
    DrawButton(FBtn[vbSkip], 'Skip', True, False, 19);
  end;
  if U.Targeting then
  begin
    FBtn[vbCancel] := Rect(VrW - 130, VrBarH + 10, VrW - 12, VrBarH + 54);
    DrawButton(FBtn[vbCancel], 'Cancel', True, False, 19);
  end;
end;

{ ---- the dialogs ---- }

procedure TVrPanel.OpenDialog(K: TVrDialog; const APrompt: string; const ADefault: string);
var
  I, C: Integer;
  D: string;
begin
  FDialog := K;
  FPrompt := APrompt;
  FChoiceCount := 0;
  if K = vdInitials then
  begin
    D := UpperCase(ADefault);
    for I := 0 to 2 do
    begin
      C := 0;
      if I < Length(D) then C := Ord(D[I + 1]) - 65;
      if (C < 0) or (C > 25) then C := 0;
      FLetters[I] := C;
    end;
  end;
  if K = vdRules then
  begin
    FPage := 0;
    BuildRules;
  end;
  Changed;
end;

procedure TVrPanel.CloseDialog;
begin
  FDialog := vdNone;
  FChoiceCount := 0;
  Changed;
end;

{ The rules, one heading and some paragraphs per section, cut into lines that fit the box. }
procedure TVrPanel.BuildRules;
var
  I, J, N, K: Integer;
  Arr, Paras: TJSArray;
  L: TVrLine;
begin
  SetFont(21, False, False);
  SetLength(FLines, 0);
  N := FCtl.RulesSectionCount;
  for I := 0 to N - 1 do
  begin
    L.Text := FCtl.RulesHeading(I);
    L.Kind := 1;
    SetLength(FLines, Length(FLines) + 1);
    FLines[High(FLines)] := L;
    Paras := TJSArray(TJSString(FCtl.RulesBody(I)).split(#10));
    for J := 0 to Paras.length - 1 do
    begin
      if string(Paras[J]) = '' then Continue;
      Arr := TJSArray.new;
      SetFont(21, False, False);
      WrapPlain(string(Paras[J]), 960, Arr);
      for K := 0 to Arr.length - 1 do
      begin
        L.Text := string(Arr[K]);
        L.Kind := 0;
        SetLength(FLines, Length(FLines) + 1);
        FLines[High(FLines)] := L;
      end;
      L.Text := '';
      L.Kind := 2;
      SetLength(FLines, Length(FLines) + 1);
      FLines[High(FLines)] := L;
    end;
  end;
end;

procedure TVrPanel.DrawDialog;
const
  BoxW = 1040;
var
  BoxH, BoxX, BoxY, I, Y, Total, First, Last, BW, BX, BY: Integer;
  Title: string;
  Lines: TJSArray;
  Labels: array[0..3] of string;
  Danger: array[0..3] of Boolean;
  L: TVrLine;
  S: string;
begin
  Fill(0, 0, 0, 0.62);
  FCtx.fillRect(0, 0, VrW, VrH);
  FChoiceCount := 0;
  Lines := TJSArray.new;
  Title := '';
  for I := 0 to 3 do Danger[I] := False;
  case FDialog of
    vdCross: begin Title := 'Silver cross'; Labels[0] := 'Keep the cross'; Labels[1] := 'Play it anyway'; Danger[1] := True; FChoiceCount := 2; end;
    vdDelete: begin Title := 'Delete saved game'; Labels[0] := 'Keep it'; Labels[1] := 'Delete it'; Danger[1] := True; FChoiceCount := 2; end;
    vdOver:
    begin
      Title := 'Start over';
      Labels[0] := 'Cancel'; Labels[1] := 'Restart the campaign only'; Labels[2] := 'Erase everything';
      Danger[1] := True; Danger[2] := True; FChoiceCount := 3;
    end;
    vdInitials: begin Title := 'New record!'; Labels[0] := 'OK'; Labels[1] := 'Skip'; FChoiceCount := 2; end;
    vdRules: begin Title := 'Rules'; Labels[0] := 'Close'; FChoiceCount := 1; end;
  end;
  SetFont(22, False, False);
  case FDialog of
    vdCross, vdDelete, vdInitials: WrapPlain(FPrompt, BoxW - 80, Lines);
    vdOver:
    begin
      WrapPlain('What would you like to start over?', BoxW - 80, Lines);
      Lines.push('');
      WrapPlain('Erase everything: your coins, undo and hint cards, campaign progress, personal records and all saved hands are deleted, and the game starts as if it were brand new.', BoxW - 80, Lines);
      Lines.push('');
      WrapPlain('Restart the campaign only: the story begins again from the first vampire. Your coins and cards are kept.', BoxW - 80, Lines);
      Lines.push('');
      WrapPlain('Neither can be undone.', BoxW - 80, Lines);
    end;
  end;
  if FDialog = vdRules then
  begin
    BoxH := 570;
    FPerPage := 13;
  end
  else if FDialog = vdInitials then
    BoxH := 130 + Lines.length * 30 + 190
  else
    BoxH := 130 + Lines.length * 30 + 90;
  BoxX := (VrW - BoxW) div 2;
  BoxY := (VrH - BoxH) div 2;
  RRect(BoxX, BoxY, BoxW, BoxH, 16);
  Fill(18, 10, 26);
  FCtx.fill;
  FCtx.lineWidth := 3;
  Stroke(201, 162, 74);
  FCtx.stroke;
  SetFont(30, True, True);
  Fill(201, 162, 74);
  FCtx.textAlign := 'left';
  FCtx.textBaseline := 'top';
  FCtx.fillText(Title, BoxX + 40, BoxY + 26);
  Y := BoxY + 80;
  if FDialog = vdRules then
  begin
    First := FPage * FPerPage;
    Total := Length(FLines);
    Last := Min(First + FPerPage, Total) - 1;
    for I := First to Last do
    begin
      L := FLines[I];
      if L.Kind = 1 then
      begin
        SetFont(22, True, False);
        Fill(201, 162, 74);
      end
      else
      begin
        SetFont(21, False, False);
        Fill(232, 224, 204);
      end;
      FCtx.fillText(L.Text, BoxX + 40, Y);
      Y := Y + 29;
    end;
    SetFont(19, False, True);
    Fill(150, 139, 70);
    FCtx.textAlign := 'center';
    FCtx.fillText(Format('Page %d of %d', [FPage + 1, Max(1, (Total + FPerPage - 1) div FPerPage)]), VrW / 2, BoxY + BoxH - 78);
    FPrev := Rect(BoxX + 40, BoxY + BoxH - 90, BoxX + 40 + 150, BoxY + BoxH - 90 + 50);
    FNext := Rect(BoxX + 40 + 170, BoxY + BoxH - 90, BoxX + 40 + 320, BoxY + BoxH - 90 + 50);
    DrawButton(FPrev, '< Back', FPage > 0, False, 20);
    DrawButton(FNext, 'Next >', Last < Total - 1, False, 20);
  end
  else
  begin
    SetFont(22, False, False);
    Fill(232, 224, 204);
    FCtx.textAlign := 'left';
    FCtx.textBaseline := 'top';
    for I := 0 to Lines.length - 1 do
    begin
      S := string(Lines[I]);
      FCtx.fillText(S, BoxX + 40, Y);
      Y := Y + 30;
    end;
  end;
  if FDialog = vdInitials then
  begin
    { three letters, each with an arrow above and below to change it }
    Y := Y + 16;
    for I := 0 to 2 do
    begin
      BX := VrW div 2 - 150 + I * 110;
      FArrow[I] := Rect(BX, Y, BX + 90, Y + 40);
      FArrow[3 + I] := Rect(BX, Y + 100, BX + 90, Y + 140);
      DrawButton(FArrow[I], '+', True, False, 26);
      DrawButton(FArrow[3 + I], '-', True, False, 26);
      RRect(BX, Y + 46, 90, 48, 8);
      Fill(11, 7, 16);
      FCtx.fill;
      FCtx.lineWidth := 2;
      Stroke(201, 162, 74);
      FCtx.stroke;
      SetFont(36, True, False);
      Fill(232, 224, 204);
      FCtx.textAlign := 'center';
      FCtx.textBaseline := 'middle';
      FCtx.fillText(Chr(65 + FLetters[I]), BX + 45, Y + 71);
    end;
  end;
  { the answer buttons, along the bottom edge on the right }
  BW := 230;
  if FDialog = vdOver then BW := 300;
  if FDialog = vdRules then BW := 160;
  BY := BoxY + BoxH - 74;
  for I := 0 to FChoiceCount - 1 do
  begin
    BX := BoxX + BoxW - 40 - (FChoiceCount - I) * BW - (FChoiceCount - 1 - I) * 14;
    FChoice[I] := Rect(BX, BY, BX + BW, BY + 50);
    DrawButton(FChoice[I], Labels[I], True, Danger[I], 20);
  end;
end;

procedure TVrPanel.Paint;
begin
  FView.OriginY := VrBarH;
  FView.Paint(VrW, VrH - VrBarH, VrDpr);
  FCtx.save;
  FCtx.setTransform(VrDpr, 0, 0, VrDpr, 0, 0);
  DrawToolbar;
  if FDialog <> vdNone then DrawDialog;
  FCtx.restore;
end;

{ Types the menu's hidden cheat word, as the keyboard would on the page. }
procedure TVrPanel.TypeCheat;
const
  Word = 'coffeeisnotblood';
var
  I: Integer;
begin
  for I := 1 to Length(Word) do FCtl.TypeChar(Word[I]);
end;

procedure TVrPanel.PaintHud;
begin
  FCtx.clearRect(0, 0, VrW * VrDpr, VrH * VrDpr);
  FView.OriginY := VrBarH;
  FView.PaintHud(VrW, VrH - VrBarH, VrDpr);
  FCtx.save;
  FCtx.setTransform(VrDpr, 0, 0, VrDpr, 0, 0);
  DrawToolbar;
  FCtx.restore;
end;

{ ---- the 3D table ---- }

function TVrPanel.TableActive: Boolean;
begin
  Result := (not FCtl.MenuOpen) and (FCtl.Overlay = okNone) and (FDialog = vdNone)
    and (FCtl.Stage.Backdrop = sbTable) and (FCtl.TableMode <> tmWon);
end;

function TVrPanel.StyleList: TJSArray;
var
  A: TJSArray;
  I: Integer;
begin
  A := TJSArray.new;
  A.push(FCtl.StyleMoon);
  for I := 0 to 3 do
    A.push(ColorR(ClothColor(FCtl.StyleCloth, I)) * 65536 + ColorG(ClothColor(FCtl.StyleCloth, I)) * 256
      + ColorB(ClothColor(FCtl.StyleCloth, I)));
  A.push(FCtl.StyleBack);
  A.push(HouseImageKey(FCtl.StyleMoon));
  Result := A;
end;

function TVrPanel.MarkCanvas(Kind: Integer): TJSObject;
var
  Ctx: TJSCanvasRenderingContext2D;
  V: TWebView;
begin
  if (Kind < 1) or (Kind > 3) then Exit(nil);
  if FMarkCv[Kind] = nil then
  begin
    FMarkCv[Kind] := TJSHTMLCanvasElement(document.createElement('canvas'));
    FMarkCv[Kind].width := 328;
    FMarkCv[Kind].height := 464;
    Ctx := FMarkCv[Kind].getContextAs2DContext('2d');
    V := TWebView.Create(Ctx, FCtl);
    V.DrawMarkAt(Rect(0, 0, 328, 464), Kind);
    V.Free;
  end;
  Result := FMarkCv[Kind];
end;

{ The layout of the list: 0 the table is shown (1); 1..4 the table area (left, top, right,
  bottom, in the game's own pixels); 5 red flash, 6 fade to black (0..1); 7 the card back
  style; 8..11 the cloth (centre, edge, frame, inner frame: each packed r*65536+g*256+b);
  12 a Wild card or Wood Stake is waiting for a card, or the deal can be skipped (the Cancel or
  Skip button is shown); 16 the moon; 17 the stock: 0 nothing, 1 cards, 2 empty but it can be
  turned over again; 18..21 the stock's rectangle; then from 22 eleven numbers for each of 29
  slots (0..27 the pyramid's cards, 28 the waste): visible, left, top, right, bottom, card key
  (suit*13+rank-1), face up, glow (0 none, 1 a hint, 2 the card picked), mark (0 none, 1 bite,
  2 chain, 3 silver cross), width squeeze (a card turning over), dimmed (a card that cannot be
  taken yet); after them (from 22 + 29 * 11) six numbers for each of the three stock cards
  Seer's eye shows: visible, left, top, right, bottom, card key. }
function TVrPanel.TableSnapshot: TJSArray;
const
  Base = 22;
  PerSlot = 11;
  PeekBase = Base + 29 * PerSlot;
var
  A: TJSArray;
  G: TPyramidGame;
  St: TStage;
  I, K, N: Integer;
  R, Src, Dst, P: TRect;
  Slot: Integer;
  Prog, F, Sq: Double;
  Vis, Up, Hi, Mk, Dm: Integer;
  C: TCard;

  function PackCloth(Part: Integer): Integer;
  begin
    Result := ColorR(ClothColor(FCtl.StyleCloth, Part)) * 65536 + ColorG(ClothColor(FCtl.StyleCloth, Part)) * 256
      + ColorB(ClothColor(FCtl.StyleCloth, Part));
  end;

begin
  Result := nil;
  if not TableActive then Exit;
  FCtl.SetViewport(VrW, VrH - VrBarH);
  G := FCtl.Game;
  St := FCtl.Stage;
  A := TJSArray.new;
  for I := 0 to PeekBase + 3 * 6 - 1 do A.push(0);
  A[0] := 1;
  P := FCtl.PanelRect;
  if P.Right > P.Left then A[1] := P.Right + 6 else A[1] := 0;
  A[2] := 0;
  A[3] := VrW;
  A[4] := VrH - VrBarH;
  A[5] := St.Scalar[ssFlashRed];
  A[6] := St.Scalar[ssDim];
  A[7] := FCtl.StyleBack;
  A[8] := PackCloth(0);
  A[9] := PackCloth(1);
  A[10] := PackCloth(2);
  A[11] := PackCloth(3);
  if FCtl.GetUi.Targeting or FCtl.GetUi.CanSkip then A[12] := 1;
  A[16] := FCtl.StyleMoon;
  R := FCtl.StockRect;
  if (G.StockCount > 0) or (FCtl.TableMode = tmDealing) then A[17] := 1
  else if G.CanRecycle then A[17] := 2;
  A[18] := R.Left;
  A[19] := R.Top;
  A[20] := R.Right;
  A[21] := R.Bottom;
  for Slot := 0 to 28 do
  begin
    Vis := 0;
    Up := 1;
    Hi := 0;
    Mk := 0;
    Dm := 0;
    Sq := 1;
    C := G.CardAt(0);
    if Slot < PyramidSize then
    begin
      R := FCtl.CardRect(Slot);
      C := G.CardAt(Slot);
    end
    else
    begin
      R := FCtl.WasteRect;
      if G.WasteTop(C) then Vis := 1;
    end;
    if FCtl.TableMode = tmDealing then
    begin
      Vis := 0;
      if Slot < PyramidSize then
      begin
        Prog := St.Move[Slot];
        if Prog > 0 then
        begin
          Vis := 1;
          Src := FCtl.StockRect;
          Dst := R;
          R.Left := Src.Left + Round((Dst.Left - Src.Left) * Prog);
          R.Top := Src.Top + Round((Dst.Top - Src.Top) * Prog);
          R.Right := R.Left + (Src.Right - Src.Left);
          R.Bottom := R.Top + (Src.Bottom - Src.Top);
          F := St.Flip[Slot];
          if F < 0.5 then
          begin
            Sq := 1 - 2 * F;
            Up := 0;
          end
          else
          begin
            Sq := 2 * F - 1;
            Up := 1;
          end;
        end;
      end;
    end
    else if Slot < PyramidSize then
    begin
      if not G.Removed(Slot) then
      begin
        Vis := 1;
        if FCtl.CardSelected(Slot) then Hi := 2
        else if FCtl.CardHighlighted(Slot) then Hi := 1;
        Mk := FCtl.CardMark(Slot);
        if not G.IsFree(Slot) and not G.IsUnder(Slot) then Dm := 1;
      end;
    end
    else if Vis = 1 then
    begin
      if FCtl.WasteSelected then Hi := 2
      else if FCtl.WasteHighlighted then Hi := 1;
    end;
    I := Base + Slot * PerSlot;
    A[I] := Vis;
    A[I + 1] := R.Left;
    A[I + 2] := R.Top;
    A[I + 3] := R.Right;
    A[I + 4] := R.Bottom;
    A[I + 5] := Ord(C.Suit) * 13 + C.Rank - 1;
    A[I + 6] := Up;
    A[I + 7] := Hi;
    A[I + 8] := Mk;
    A[I + 9] := Sq;
    A[I + 10] := Dm;
  end;
  { the stock gets the hint ring too: its glow rides on the slot-29 stand-in (index 12 of the stock) }
  if FCtl.StockHighlighted then A[13] := 1;
  { Seer's eye: the next three cards of the stock, fanned beside the waste }
  if G.Revealed and (G.StockCount > 0) and (FCtl.TableMode <> tmDealing) then
  begin
    N := Min(3, G.StockCount);
    for K := 0 to N - 1 do
    begin
      R := FCtl.WasteRect;
      Dst := R;
      Dst.Left := R.Right + FCtl.Scaled(14) + K * (R.Right - R.Left) * 5 div 10;
      Dst.Right := Dst.Left + (R.Right - R.Left) * 8 div 10;
      Dst.Top := R.Top;
      Dst.Bottom := R.Top + (R.Bottom - R.Top) * 8 div 10;
      C := G.StockCard(K);
      I := PeekBase + K * 6;
      A[I] := 1;
      A[I + 1] := Dst.Left;
      A[I + 2] := Dst.Top;
      A[I + 3] := Dst.Right;
      A[I + 4] := Dst.Bottom;
      A[I + 5] := Ord(C.Suit) * 13 + C.Rank - 1;
    end;
  end;
  Result := A;
end;

{ Taps card Slot of the 3D table the way a tap on the flat table would: at a point of the card
  that no card lying on it covers (the controller picks the front-most card at the point).
  Slot 28 is the waste and 29 the stock. }
procedure TVrPanel.TapSlot(Slot: Integer);
var
  R: TRect;
  P: TPoint;
  Y, J, H: Integer;
  Clear: Boolean;
begin
  FCtl.SetViewport(VrW, VrH - VrBarH);
  if Slot = 29 then
  begin
    R := FCtl.StockRect;
    FCtl.Tap((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
    Exit;
  end;
  if Slot = 28 then
  begin
    R := FCtl.WasteRect;
    FCtl.Tap((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
    Exit;
  end;
  if (Slot < 0) or (Slot >= PyramidSize) then Exit;
  R := FCtl.CardRect(Slot);
  H := R.Bottom - R.Top;
  P := Point((R.Left + R.Right) div 2, R.Top + H div 2);
  for Y := R.Top + FCtl.Scaled(10) to R.Bottom - 2 do
  begin
    Clear := True;
    for J := Slot + 1 to PyramidSize - 1 do
      if (not FCtl.Game.Removed(J)) and PtInRect(FCtl.CardRect(J), Point(P.X, Y)) then
      begin
        Clear := False;
        Break;
      end;
    if Clear then
    begin
      P.Y := Y;
      Break;
    end;
  end;
  FCtl.Tap(P.X, P.Y);
end;

{ ---- taps ---- }

procedure TVrPanel.ChooseDialog(Choice: Integer);
var
  K: TVrDialog;
  S: string;
begin
  K := FDialog;
  S := '';
  if K = vdInitials then S := Chr(65 + FLetters[0]) + Chr(65 + FLetters[1]) + Chr(65 + FLetters[2]);
  FDialog := vdNone;
  FChoiceCount := 0;
  if Assigned(FOnAnswer) then FOnAnswer(K, Choice, S);
  Changed;
end;

procedure TVrPanel.Tap(X, Y: Double);
var
  I: Integer;
  P: TPoint;
begin
  P := Point(Round(X), Round(Y));
  if FDialog <> vdNone then
  begin
    for I := 0 to FChoiceCount - 1 do
      if PtInRect(FChoice[I], P) then
      begin
        ChooseDialog(I);
        Exit;
      end;
    if FDialog = vdRules then
    begin
      if PtInRect(FPrev, P) and (FPage > 0) then
      begin
        Dec(FPage);
        Changed;
      end
      else if PtInRect(FNext, P) and ((FPage + 1) * FPerPage < Length(FLines)) then
      begin
        Inc(FPage);
        Changed;
      end;
    end
    else if FDialog = vdInitials then
      for I := 0 to 5 do
        if PtInRect(FArrow[I], P) then
        begin
          if I < 3 then FLetters[I] := (FLetters[I] + 1) mod 26
          else FLetters[I - 3] := (FLetters[I - 3] + 25) mod 26;
          Changed;
          Exit;
        end;
    Exit;
  end;
  for I := 0 to VrButtons - 1 do
    if FBtnShown[I] and PtInRect(FBtn[I], P) then
    begin
      if Assigned(FOnButton) then FOnButton(I);
      Exit;
    end;
  if P.Y >= VrBarH then
  begin
    FCtl.SetViewport(VrW, VrH - VrBarH);
    FCtl.Tap(P.X, P.Y - VrBarH);
  end;
end;

end.
