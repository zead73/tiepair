program TestPairFlow;

{$mode objfpc}{$H+}

uses SysUtils, Types, Cards, Pyramid, PairHand, PairGame, Storage{$IFDEF PAS2JS}, JsCompat{$ENDIF};

var
  Failures: Integer = 0;

procedure Check(Cond: Boolean; const Msg: string);
begin
  if not Cond then
  begin
    WriteLn('FAIL: ', Msg);
    Inc(Failures);
  end;
end;

type
  { Hands to order: the next one dealt is Tab (28 pyramid ranks) and Stock (24, the last is on top). }
  TDeals = class
  public
    Tab: array[0..27] of Integer;
    Stock: array[0..23] of Integer;
    Changes: Integer;
    function Next: TDeck;
    procedure OnChange;
    procedure Fill(TabRank, StockRank: Integer);
  end;

function TDeals.Next: TDeck;
var
  A: TCardArray;
  I: Integer;
begin
  SetLength(A, 52);
  for I := 0 to 27 do
  begin
    A[I].Suit := suSpades; A[I].Rank := Tab[I]; A[I].FaceUp := False;
  end;
  for I := 0 to 23 do
  begin
    A[28 + I].Suit := suHearts; A[28 + I].Rank := Stock[I]; A[28 + I].FaceUp := False;
  end;
  Result := TDeck.CreateFromCards(A);
end;

procedure TDeals.OnChange;
begin
  Inc(Changes);
end;

procedure TDeals.Fill(TabRank, StockRank: Integer);
var
  I: Integer;
begin
  for I := 0 to 27 do Tab[I] := TabRank;
  for I := 0 to 23 do Stock[I] := StockRank;
end;

function NewCtl(D: TDeals): TPairController;
begin
  Result := TPairController.Create;
  Result.DeckProvider := @D.Next;
  Result.OnChange := @D.OnChange;
  Result.SetViewport(1100, 700);
end;

{ Taps the visible top part of a pyramid card. }
procedure TapCard(C: TPairController; I: Integer);
var
  R: TRect;
begin
  R := C.CardRect(I);
  C.Tap((R.Left + R.Right) div 2, R.Top + C.CardH div 8);
end;

procedure TapRect(C: TPairController; const R: TRect);
begin
  C.Tap((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
end;

function Inside(const R, Outer: TRect): Boolean;
begin
  Result := (R.Left >= Outer.Left) and (R.Top >= Outer.Top) and (R.Right <= Outer.Right) and (R.Bottom <= Outer.Bottom);
end;

procedure TestLayout;
const
  Sizes: array[0..5, 0..1] of Integer = ((1520, 584), (1100, 700), (800, 600), (375, 560), (360, 740), (1920, 1080));
var
  D: TDeals;
  C: TPairController;
  S, I: Integer;
  V, R: TRect;
  Z: TRect;
begin
  D := TDeals.Create;
  D.Fill(7, 7);
  C := NewCtl(D);
  try
    C.ActionNew;
    for S := 0 to High(Sizes) do
    begin
      C.SetViewport(Sizes[S, 0], Sizes[S, 1]);
      V := Rect(0, 0, Sizes[S, 0], Sizes[S, 1]);
      for I := 0 to PyramidSize - 1 do
        Check(Inside(C.CardRect(I), C.TableRect) and Inside(C.CardRect(I), V),
          Format('%dx%d: card %d is on the table', [Sizes[S, 0], Sizes[S, 1], I]));
      Check(Inside(C.StockRect, V) and Inside(C.WasteRect, V), 'the piles are on screen');
      Check(Inside(C.StockRect, C.TableRect) and Inside(C.WasteRect, C.TableRect), 'and on the table');
      { the piles sit below the pyramid, and do not overlap one another }
      Check(C.StockRect.Top >= C.CardRect(27).Bottom, 'the stock is under the bottom row');
      Check(C.WasteRect.Left >= C.StockRect.Right, 'the waste is beside the stock');
      { a card is covered half way by the row below, and by nothing else }
      Check(C.CardRect(0).Bottom > C.CardRect(1).Top, 'rows overlap');
      Check(C.CardRect(21).Right <= C.CardRect(22).Left, 'cards in a row do not overlap');
      Check(C.CardW >= 20, 'cards are big enough to tap');
      if Sizes[S, 0] >= Sizes[S, 1] * 115 div 100 then
        Check(C.PanelRect.Right > C.PanelRect.Left, 'a wide window has a side panel')
      else
        Check(C.PanelRect.Right = C.PanelRect.Left, 'a narrow window has none');
    end;
    Z := C.CardRect(0);
    Check(Z.Right - Z.Left = C.CardW, 'a card is CardW wide');
  finally
    C.Free;
    D.Free;
  end;
end;

procedure TestTaps;
var
  D: TDeals;
  C: TPairController;
  U: TPairUi;
begin
  D := TDeals.Create;
  D.Fill(7, 7);
  { bottom row 21..27: 6 7 K 5 8 2 10 }
  D.Tab[21] := 6; D.Tab[22] := 7; D.Tab[23] := 13; D.Tab[24] := 5; D.Tab[25] := 8; D.Tab[26] := 2; D.Tab[27] := 10;
  D.Stock[23] := 9;                 { the top of the stock }
  D.Stock[22] := 4;
  C := NewCtl(D);
  try
    C.ActionNew;
    U := C.GetUi;
    Check((U.CardsLeft = 28) and (U.StockCount = 24) and (U.WasteCount = 0) and not U.Won and not U.UndoEnabled, 'a fresh hand');
    { select, then pair }
    TapCard(C, 21);
    Check(C.Selected = 21, 'the first tap selects');
    TapCard(C, 21);
    Check(C.Selected = PosNone, 'a second tap on the same card lets it go');
    TapCard(C, 21);
    TapCard(C, 22);
    Check(C.Game.Removed(21) and C.Game.Removed(22) and (C.Selected = PosNone), '6 then 7: both go');
    Check(C.GetUi.UndoEnabled, 'and there is something to undo');
    { a King needs one tap }
    TapCard(C, 23);
    Check(C.Game.Removed(23) and (C.Selected = PosNone), 'a King goes on one tap');
    { the order does not matter }
    TapCard(C, 25);
    TapCard(C, 24);
    Check(C.Game.Removed(24) and C.Game.Removed(25), '8 then 5: both go');
    { a wrong pair: the message says why, and the second card is now the selected one }
    TapCard(C, 26);
    TapCard(C, 27);
    Check(not C.Game.Removed(26) and not C.Game.Removed(27), '2 and 10: they stay');
    Check(C.Selected = 27, 'the 10 is selected now');
    Check(Pos('not 13', C.GetUi.Status) > 0, 'and the line says what they make: ' + C.GetUi.Status);
    { a tap on bare table lets go }
    C.Tap(C.TableRect.Left + 3, C.TableRect.Top + 3);
    Check(C.Selected = PosNone, 'a tap on the table lets go of the selection');
    { a covered card cannot be picked }
    TapCard(C, 9);
    Check((C.Selected = PosNone) and (Pos('covered', C.GetUi.Status) > 0), 'a covered card says so: ' + C.GetUi.Status);
    { undo }
    Check(C.GetUi.UndoEnabled, 'undo is on');
    C.ActionUndo;
    Check(not C.Game.Removed(24) and not C.Game.Removed(25), 'undo brings the last pair back');
    C.ActionUndo;
    C.ActionUndo;
    Check(not C.GetUi.UndoEnabled and (C.Game.CardsLeft = 28), 'undone to the start');
  finally
    C.Free;
    D.Free;
  end;
end;

procedure TestUnderPair;
var
  D: TDeals;
  C: TPairController;
  R: TRect;
begin
  D := TDeals.Create;
  D.Fill(7, 7);
  D.Tab[15] := 1;                   { an Ace, under ... }
  D.Tab[21] := 12;                  { ... a Queen, and a King beside it }
  D.Tab[22] := 13;
  C := NewCtl(D);
  try
    C.SetEasy(True);
    Check(C.Easy and C.Game.UnderPairs, 'test set-up: Easy mode');
    { covered by two cards: still just covered }
    R := C.CardRect(15);
    C.Tap(R.Left + 4, R.Top + C.CardH div 8);
    Check((C.Selected = PosNone) and (Pos('covered', C.GetUi.Status) > 0), 'an Ace under two cards cannot be picked: ' + C.GetUi.Status);
    TapCard(C, 22);
    Check(C.Game.Removed(22), 'a King goes');
    { now only the Queen covers the Ace: the Ace is tapped where the Queen does not hide it }
    R := C.CardRect(15);
    C.Tap(R.Left + 4, R.Top + C.CardH div 8);
    Check(C.Selected = 15, 'the Ace can be picked now');
    TapCard(C, 21);
    Check(C.Game.Removed(15) and C.Game.Removed(21), 'and the Queen takes it with her');
    C.ActionUndo;
    Check(not C.Game.Removed(15) and not C.Game.Removed(21), 'undo brings both back');
    { the other way round: the Queen first }
    TapCard(C, 21);
    Check(C.Selected = 21, 'the Queen is selected');
    R := C.CardRect(15);
    C.Tap(R.Left + 4, R.Top + C.CardH div 8);
    Check(C.Game.Removed(15) and C.Game.Removed(21), 'and then the Ace');
    { the hint points at such a pair too }
    C.ActionUndo;
    C.ActionHint;
    Check(((C.HintA = 15) and (C.HintB = 21)) or ((C.HintA = 21) and (C.HintB = 15)) or C.Game.CanRemove(C.HintA, C.HintB), 'the hint finds a real removal');
  finally
    C.Free;
    D.Free;
  end;
end;

procedure TestMode;
var
  A, B: TPairController;
  Id, I: Integer;
begin
  StoreDelete(StoreName('settings.ini'));
  StoreDelete(AutoSaveFile);
  A := TPairController.Create;       { real shuffled deals: a saved hand must be believable }
  B := TPairController.Create;
  try
    A.SetViewport(1100, 700);
    B.SetViewport(1100, 700);
    A.Start;
    Check(not A.Easy and not A.Game.UnderPairs and (A.GetUi.ModeCaption = 'Mode: Normal'), 'the game starts in Normal mode');
    Id := A.Game.HandId;
    A.ActionToggleEasy;
    Check(A.Easy and A.Game.UnderPairs and (A.GetUi.ModeCaption = 'Mode: Easy'), 'a tap on Mode switches to Easy');
    Check((A.Game.HandId <> Id) and (A.Game.CardsLeft = 28), 'and deals a new hand: rules do not change half way');
    Check(Pos('Easy', A.GetUi.Status) > 0, 'and says so: ' + A.GetUi.Status);
    TapRect(A, A.StockRect);
    B.Start;
    Check(B.Easy and B.Game.UnderPairs and (B.Game.HandId = A.Game.HandId), 'a new start picks up the saved hand, an Easy one');
    A.ActionToggleEasy;
    Check(not A.Easy and not A.Game.UnderPairs, 'back to Normal');
    for I := 1 to 3 do TapRect(A, A.StockRect);
    B.Free;
    B := TPairController.Create;
    B.SetViewport(1100, 700);
    B.Start;
    Check(not B.Easy and not B.Game.UnderPairs and (B.Game.WasteCount = 3), 'and a Normal hand comes back Normal');
    Check(not B.Game.IsUnder(15), 'in Normal mode no card is under another');
  finally
    A.Free; B.Free;
    StoreDelete(StoreName('settings.ini'));
    StoreDelete(AutoSaveFile);
  end;
end;

procedure TestStock;
var
  D: TDeals;
  C: TPairController;
  T: TCard;
  I: Integer;
begin
  D := TDeals.Create;
  D.Fill(7, 1);                     { no pair among 7s; the stock is all Aces }
  D.Tab[27] := 12;                  { a Queen: pairs with an Ace }
  C := NewCtl(D);
  C.Game.MaxRecycles := 1;
  try
    C.ActionNew;
    C.Game.MaxRecycles := 1;
    TapRect(C, C.StockRect);
    Check((C.Game.WasteCount = 1) and (C.Game.StockCount = 23), 'a tap on the stock draws');
    Check(C.Game.WasteTop(T) and (T.Rank = 1), 'an Ace on the waste');
    TapRect(C, C.WasteRect);
    Check(C.Selected = PosWaste, 'a tap on the waste selects its top card');
    TapCard(C, 27);
    Check(C.Game.Removed(27) and (C.Game.WasteCount = 0), 'the Ace and the Queen go together');
    { a King on the waste goes on one tap }
    C.ActionUndo;
    Check(not C.Game.Removed(27) and (C.Game.WasteCount = 1), 'undo puts both back');
    { draw the rest and turn the stock over by tapping its place }
    for I := 1 to 23 do TapRect(C, C.StockRect);
    Check((C.Game.StockCount = 0) and (C.Game.WasteCount = 24), 'the stock is used up');
    TapRect(C, C.StockRect);
    Check((C.Game.StockCount = 24) and (C.Game.Recycled = 1), 'a tap on the empty stock turns the waste over');
    for I := 1 to 24 do TapRect(C, C.StockRect);
    TapRect(C, C.StockRect);
    Check(Pos('turned over', C.GetUi.Status) > 0, 'a second turn-over is refused with a line: ' + C.GetUi.Status);
  finally
    C.Free;
    D.Free;
  end;
end;

procedure TestHint;
var
  D: TDeals;
  C: TPairController;
begin
  D := TDeals.Create;
  D.Fill(7, 1);
  D.Tab[21] := 6;                   { 6 and 7 pair }
  C := NewCtl(D);
  try
    C.ActionNew;
    C.ActionHint;
    Check((C.HintA >= 21) and (C.HintB >= 21) and not C.HintStock, 'the hint points at two cards');
    Check(C.Game.CanRemove(C.HintA, C.HintB), 'which really go together');
    TapCard(C, C.HintA);
    Check(C.HintA = PosNone, 'a tap on a card clears the hint');
    { with nothing to take away it points at the stock }
    D.Fill(7, 1);
    C.ActionNew;
    C.ActionHint;
    Check(C.HintStock and (C.HintA = PosNone), 'no removal: it points at the stock');
  finally
    C.Free;
    D.Free;
  end;
end;

procedure TestWinAndStuck;
var
  D: TDeals;
  C: TPairController;
  I, N: Integer;
begin
  D := TDeals.Create;
  D.Fill(13, 7);                    { a pyramid of Kings }
  C := NewCtl(D);
  try
    C.ActionNew;
    for N := 1 to 28 do
      for I := PyramidSize - 1 downto 0 do
        if C.Game.IsFree(I) then
        begin
          TapCard(C, I);
          Break;
        end;
    Check(C.GetUi.Won and (C.Game.CardsLeft = 0), 'twenty-eight taps clear a pyramid of Kings');
    Check(not C.GetUi.UndoEnabled and not C.GetUi.HintEnabled, 'after the win: no undo, no hint');
    C.Tap(10, 10);
    Check(not C.GetUi.Won and (C.Game.CardsLeft = 28), 'a tap anywhere deals a new hand');
    { stuck }
    D.Fill(7, 7);
    C.ActionNew;
    C.Game.MaxRecycles := 0;
    for I := 1 to 24 do TapRect(C, C.StockRect);
    Check(C.GetUi.Stuck and not C.GetUi.HintEnabled, 'no moves left: stuck');
    Check(Pos('No moves', C.GetUi.Status) > 0, 'and it says so: ' + C.GetUi.Status);
  finally
    C.Free;
    D.Free;
  end;
end;

procedure TapPos(C: TPairController; APos: Integer);
begin
  if APos = PosWaste then TapRect(C, C.WasteRect) else TapCard(C, APos);
end;

procedure TestResume;
var
  D: TDeals;
  A, B, K: TPairController;
  H: TPairHand;
  I, X, Y, N: Integer;
begin
  StoreDelete(AutoSaveFile);
  StoreDelete(StoreName('settings.ini'));
  D := TDeals.Create;
  A := TPairController.Create;       { real shuffled deals: a saved hand must be believable }
  B := TPairController.Create;
  K := NewCtl(D);
  try
    A.SetViewport(1100, 700);
    B.SetViewport(1100, 700);
    A.Start;
    Check(A.Game.CardsLeft = 28, 'with no saved hand a new one is dealt');
    for I := 1 to 6 do TapRect(A, A.StockRect);
    A.ActionHint;
    X := A.HintA;
    Y := A.HintB;
    if X <> PosNone then
    begin
      TapPos(A, X);
      if Y <> PosNone then TapPos(A, Y);
    end;
    Check(A.Game.CanUndo, 'test set-up: moves were made');
    B.Start;
    Check(B.Game.CardsLeft = A.Game.CardsLeft, 'a new start picks the saved hand up (cards left)');
    Check((B.Game.StockCount = A.Game.StockCount) and (B.Game.WasteCount = A.Game.WasteCount), 'and the piles');
    Check(B.Game.HandId = A.Game.HandId, 'and it is the same hand');
    Check(B.Game.CanUndo, 'with its undo');
    B.ActionUndo;
    Check(B.Game.CardsLeft >= A.Game.CardsLeft, 'and undo works on it');
    { a won hand is not kept }
    D.Fill(13, 7);
    K.ActionNew;
    for N := 1 to 28 do
      for I := PyramidSize - 1 downto 0 do
        if K.Game.IsFree(I) then
        begin
          TapCard(K, I);
          Break;
        end;
    Check(K.GetUi.Won, 'test set-up: a won hand');
    Check(not ReadHandFile(AutoSaveFile, H), 'a won hand is not saved');
    { a damaged file is not picked up }
    StoreWrite(AutoSaveFile, 'tiepair-hand 1' + #10 + 'id=5' + #10);
    A.Start;
    Check(A.Game.CardsLeft = 28, 'a damaged file means a new hand');
  finally
    A.Free; B.Free; K.Free; D.Free;
    StoreDelete(AutoSaveFile);
  end;
end;

begin
  Randomize;
  SetStoreDir('tiepair_test_flow');
  TestLayout;
  TestTaps;
  TestUnderPair;
  TestMode;
  TestStock;
  TestHint;
  TestWinAndStuck;
  TestResume;
  if Failures = 0 then WriteLn('ALL FLOW TESTS PASSED')
  else
  begin
    WriteLn(Failures, ' FAILURES');
    Halt(1);
  end;
end.
