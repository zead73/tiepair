program TestPyramid;

{$mode objfpc}{$H+}

uses SysUtils, Cards, Pyramid{$IFDEF PAS2JS}, JsCompat{$ENDIF};

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

function MakeCard(Rank: Integer): TCard;
begin
  Result.Suit := suSpades;
  Result.Rank := Rank;
  Result.FaceUp := False;
end;

{ Deal order: the 28 pyramid cards (index 0..27), then the 24 stock cards in the
  order they are dealt (the LAST one dealt is on top of the stock). Cards may repeat:
  these are rule tests, not saved hands. }
function BuildDeck(const Tab: array of Integer; const Stock: array of Integer): TDeck;
var
  A: TCardArray;
  I: Integer;
begin
  SetLength(A, 52);
  for I := 0 to 27 do A[I] := MakeCard(Tab[I]);
  for I := 0 to 23 do A[28 + I] := MakeCard(Stock[I]);
  Result := TDeck.CreateFromCards(A);
end;

procedure AllSame(var Tab: array of Integer; var Stock: array of Integer; TabRank, StockRank: Integer);
var
  I: Integer;
begin
  for I := 0 to 27 do Tab[I] := TabRank;
  for I := 0 to 23 do Stock[I] := StockRank;
end;

procedure TestLayout;
var
  I, R, C, N: Integer;
begin
  N := 0;
  for R := 0 to RowCount - 1 do
    for C := 0 to R do
    begin
      I := IndexOf(R, C);
      Check(I = N, 'cards are numbered along the rows from the top');
      Check((RowOf(I) = R) and (ColOf(I) = C), 'row and column of ' + IntToStr(I));
      if R < RowCount - 1 then
        Check((CoverLeft(I) = IndexOf(R + 1, C)) and (CoverRight(I) = IndexOf(R + 1, C + 1)),
          'the two cards that cover ' + IntToStr(I))
      else
        Check((CoverLeft(I) = -1) and (CoverRight(I) = -1), 'the bottom row is covered by nothing');
      Inc(N);
    end;
  Check(N = PyramidSize, 'twenty-eight cards');
  Check(IndexOf(RowCount, 0) = PyramidSize, 'row 7 would start where the pyramid ends');
end;

procedure TestPairs;
var
  G: TPyramidGame;
  Tab: array[0..27] of Integer;
  Stock: array[0..23] of Integer;
  A, B, S: Integer;
begin
  G := TPyramidGame.Create;
  try
    { every two ranks that add up to 13 go together; none other does }
    for A := 1 to 12 do
      for B := 1 to 12 do
      begin
        AllSame(Tab, Stock, 7, 7);
        Tab[21] := A;
        Tab[22] := B;
        G.Deal(BuildDeck(Tab, Stock));
        Check(G.CanRemove(21, 22) = (A + B = 13), Format('%d and %d: pair only if they add up to 13', [A, B]));
        Check(G.CanRemove(21, 22) = G.CanRemove(22, 21), 'order does not matter');
      end;
    { a King goes alone; nothing else does }
    for S := 1 to 13 do
    begin
      AllSame(Tab, Stock, 7, 7);
      Tab[24] := S;
      G.Deal(BuildDeck(Tab, Stock));
      Check(G.CanRemove(24, PosNone) = (S = 13), Format('rank %d alone: only a King', [S]));
    end;
    { a card cannot be paired with itself }
    AllSame(Tab, Stock, 13, 7);
    G.Deal(BuildDeck(Tab, Stock));
    Check(not G.CanRemove(21, 21), 'not with itself');
    Check(not G.CanRemove(21, 99) and not G.CanRemove(-7, PosNone), 'nonsense positions are refused');
  finally
    G.Free;
  end;
end;

procedure TestFree;
var
  G: TPyramidGame;
  Tab: array[0..27] of Integer;
  Stock: array[0..23] of Integer;
  I: Integer;
begin
  G := TPyramidGame.Create;
  try
    AllSame(Tab, Stock, 13, 7);
    G.Deal(BuildDeck(Tab, Stock));
    for I := 0 to 20 do Check(not G.IsFree(I), 'covered card ' + IntToStr(I) + ' is not free');
    for I := 21 to 27 do Check(G.IsFree(I), 'bottom card ' + IntToStr(I) + ' is free');
    Check(not G.CanRemove(0, PosNone), 'a covered King cannot be taken');
    { the two cards covering card 15 (row 5, column 0) are 21 and 22 }
    Check((CoverLeft(15) = 21) and (CoverRight(15) = 22), 'test set-up');
    Check(G.Remove(21, PosNone), 'take King 21');
    Check(not G.IsFree(15), 'one cover gone: still not free');
    Check(G.Remove(22, PosNone), 'take King 22');
    Check(G.IsFree(15) and G.CanRemove(15, PosNone), 'both covers gone: free');
    Check(G.Removed(21) and not G.IsFree(21) and not G.CanRemove(21, PosNone), 'a removed card cannot be taken again');
    Check(G.CardsLeft = 26, 'two cards gone');
  finally
    G.Free;
  end;
end;

procedure TestWaste;
var
  G: TPyramidGame;
  Tab: array[0..27] of Integer;
  Stock: array[0..23] of Integer;
  C: TCard;
  M: TPairMove;
begin
  G := TPyramidGame.Create;
  try
    AllSame(Tab, Stock, 7, 7);
    Tab[27] := 6;
    Stock[23] := 7;                            { the top of the stock: the 7 that pairs with the 6 }
    Stock[22] := 13;                           { under it: a King }
    G.Deal(BuildDeck(Tab, Stock));
    Check((G.StockCount = 24) and (G.WasteCount = 0), 'a fresh deal: 24 in the stock, nothing in the waste');
    Check(not G.WasteTop(C) and not G.InPlay(PosWaste), 'nothing in play on the waste yet');
    Check(not G.CanRemove(27, PosWaste), 'the waste is empty');
    Check(G.Draw, 'draw');
    Check(G.WasteTop(C) and (C.Rank = 7) and C.FaceUp, 'the top of the stock is now the waste top');
    Check((G.StockCount = 23) and (G.WasteCount = 1), 'counts');
    Check(G.CanRemove(27, PosWaste) and G.CanRemove(PosWaste, 27), '6 and the waste 7 pair');
    Check(G.Remove(27, PosWaste), 'take them');
    Check(G.Removed(27) and (G.WasteCount = 0), 'the pyramid card and the waste card are both gone');
    Check(G.LastMove(M) and (M.Kind = mkRemove) and (M.WasteCard.Rank = 7), 'the move remembers the waste card');
    Check(G.Undo, 'undo');
    Check(not G.Removed(27) and (G.WasteCount = 1) and G.WasteTop(C) and (C.Rank = 7), 'both are back');
    Check(G.Undo, 'undo the draw');
    Check((G.StockCount = 24) and (G.WasteCount = 0), 'the card is back on the stock');
    Check(G.Draw and G.Draw, 'draw the 7 and then the King');
    Check(G.CanRemove(PosWaste, PosNone), 'a King on the waste goes alone');
    Check(G.Remove(PosWaste, PosNone) and (G.WasteCount = 1), 'take it: the 7 under it is the waste top again');
    Check(G.WasteTop(C) and (C.Rank = 7), 'the card under it is in play now');
    { two waste cards cannot be paired with each other: only the top is in play }
    Check(not G.CanRemove(PosWaste, PosWaste), 'the waste top with itself');
  finally
    G.Free;
  end;
end;

procedure TestRecycle;
var
  G: TPyramidGame;
  Tab: array[0..27] of Integer;
  Stock: array[0..23] of Integer;
  I: Integer;
  C: TCard;
  First: array[0..23] of Integer;
begin
  G := TPyramidGame.Create;
  try
    AllSame(Tab, Stock, 7, 7);
    for I := 0 to 23 do Stock[I] := 1 + (I mod 6);       { 1..6, no pair with a 7 }
    G.Deal(BuildDeck(Tab, Stock));
    G.MaxRecycles := 1;
    Check((G.RecyclesLeft = 1) and not G.CanRecycle, 'a turn-over left, but the stock is not empty');
    for I := 0 to 23 do
    begin
      Check(G.Draw, 'draw ' + IntToStr(I));
      G.WasteTop(C);
      First[I] := C.Rank;
    end;
    Check(not G.CanDraw and G.CanRecycle, 'stock empty: it can be turned over');
    Check(G.Recycle, 'turn it over');
    Check((G.StockCount = 24) and (G.WasteCount = 0) and (G.Recycled = 1) and (G.RecyclesLeft = 0), 'a new stock of 24');
    for I := 0 to 23 do
    begin
      G.Draw;
      G.WasteTop(C);
      Check(C.Rank = First[I], 'the cards come round in the same order (' + IntToStr(I) + ')');
    end;
    Check(not G.CanRecycle and not G.Recycle, 'no second turn-over');
    Check(G.IsStuck, 'nothing left to do: stuck');
    { undo the whole second pass and the turn-over }
    for I := 1 to 24 do Check(G.Undo, 'undo a draw');
    Check(G.Undo, 'undo the turn-over');
    Check((G.StockCount = 0) and (G.WasteCount = 24) and (G.Recycled = 0), 'back to the end of the first pass');
    G.WasteTop(C);
    Check(C.Rank = First[23], 'with the same card on top');
  finally
    G.Free;
  end;
end;

procedure TestWinAndStuck;
var
  G: TPyramidGame;
  Tab: array[0..27] of Integer;
  Stock: array[0..23] of Integer;
  Done, I, A, B: Integer;
begin
  G := TPyramidGame.Create;
  try
    { a pyramid of Kings is cleared one card at a time }
    AllSame(Tab, Stock, 13, 7);
    G.Deal(BuildDeck(Tab, Stock));
    Done := 0;
    while not G.IsWon do
    begin
      Check(G.FindRemoval(0, A, B), 'a King can always be taken');
      if not G.Remove(A, B) then Break;
      Inc(Done);
      if Done > 40 then Break;
    end;
    Check(G.IsWon and (Done = 28) and not G.IsStuck, 'twenty-eight Kings: won');
    { all sevens and no turn-over: stuck once the stock has been drawn }
    AllSame(Tab, Stock, 7, 7);
    G.Deal(BuildDeck(Tab, Stock));
    G.MaxRecycles := 0;
    Check(not G.IsStuck and G.HasMoves, 'a fresh hand can still draw');
    for I := 1 to 24 do G.Draw;
    Check(G.IsStuck and not G.HasMoves and (G.RemovalCount = 0), 'no pair, nothing to draw: stuck');
  finally
    G.Free;
  end;
end;

{ A card and the one card that still covers it can go together: a Queen sitting on an Ace. }
procedure TestUnderPairs;
var
  G, G2: TPyramidGame;
  Tab: array[0..27] of Integer;
  Stock: array[0..23] of Integer;
  C: TCard;
  Saved: TPairHand;
begin
  G := TPyramidGame.Create;
  G2 := TPyramidGame.Create;
  try
    Check(not G.UnderPairs, 'a new game is in Normal mode');
    G.UnderPairs := True;
    { card 15 (row 5, column 0) is covered by 21 and 22 }
    Check((CoverLeft(15) = 21) and (CoverRight(15) = 22), 'test set-up');
    AllSame(Tab, Stock, 7, 7);
    Tab[15] := 1;                  { an Ace }
    Tab[21] := 12;                 { a Queen on it }
    Tab[22] := 13;                 { and a King on its other side }
    G.Deal(BuildDeck(Tab, Stock));
    Check(G.IsUnder(15) = False, 'covered by two cards: not under anything yet');
    Check(not G.CanRemove(21, 15) and not G.CanRemove(15, 21), 'so the Queen and the Ace cannot go yet');
    Check(G.Remove(22, PosNone), 'take the King');
    Check(G.IsUnder(15) and (G.SoleCover(15) = 21) and not G.IsFree(15), 'now only the Queen covers the Ace');
    Check(G.CanSelect(15) and not G.InPlay(15), 'the Ace can be picked, but is not free');
    Check(G.CanRemove(21, 15) and G.CanRemove(15, 21), 'the Queen and the Ace go together, either way round');
    Check(not G.CanRemove(15, PosNone), 'a covered card is not taken on its own');
    G.Remove(15, 21);
    Check(G.Removed(15) and G.Removed(21), 'both gone');
    G.GetState(Saved);
    Check(Saved.UnderPairs, 'the hand knows it is an Easy one');
    Check(G.CardsLeft = 25, 'three cards gone in all');
    Check(G.Undo, 'undo');
    Check(not G.Removed(15) and not G.Removed(21) and G.Removed(22), 'the pair is back, the King is still gone');
    { it needs the right sum, and the card on top of it }
    Check(G.Undo, 'undo the King');
    AllSame(Tab, Stock, 7, 7);
    Tab[15] := 2;
    Tab[21] := 12;
    Tab[22] := 13;
    G.Deal(BuildDeck(Tab, Stock));
    G.Remove(22, PosNone);
    Check(not G.CanRemove(21, 15), '12 and 2 make 14: not a pair');
    AllSame(Tab, Stock, 7, 7);
    Tab[15] := 1;
    Tab[21] := 13;
    Tab[22] := 13;
    Tab[23] := 12;                 { a free Queen elsewhere }
    G.Deal(BuildDeck(Tab, Stock));
    G.Remove(22, PosNone);
    Check(G.IsUnder(15) and not G.CanRemove(23, 15), 'the Ace goes with the card on it, not with any other Queen');
    { a card cannot go with a card on top of the one that covers it }
    AllSame(Tab, Stock, 7, 7);
    Tab[8] := 1;                   { row 3 }
    Tab[14] := 12;                 { row 4 }
    G.Deal(BuildDeck(Tab, Stock));
    Check(not G.IsUnder(8) and not G.CanRemove(14, 8), 'cards that are themselves covered do not pair with what is under them');
    { with the rule off, only free cards pair }
    AllSame(Tab, Stock, 7, 7);
    Tab[15] := 1;
    Tab[21] := 12;
    Tab[22] := 13;
    G.Deal(BuildDeck(Tab, Stock));
    G.UnderPairs := False;
    G.Remove(22, PosNone);
    Check(not G.IsUnder(15) and not G.CanRemove(21, 15) and not G.CanSelect(15), 'with UnderPairs off the Ace must be uncovered first');
    G.UnderPairs := True;
    { a card under a card that is itself free is also found by FindRemoval }
    Check(G.RemovalCount >= 1, 'the removal is listed');
    Check(G.WasteTop(C) = False, 'test set-up');
  finally
    G.Free;
    G2.Free;
  end;
end;

{ A real hand in which a card went together with the card covering it: it loads as an
  Easy hand and is refused as a Normal one. }
procedure TestUnderHistory;
var
  G, G2: TPyramidGame;
  H: TPairHand;
  N, Step, A, B, K: Integer;
  Found: Boolean;
begin
  G := TPyramidGame.Create;
  G2 := TPyramidGame.Create;
  try
    Found := False;
    for N := 1 to 3000 do
    begin
      G.NewShuffled;
      G.UnderPairs := True;
      for Step := 1 to 80 do
      begin
        if G.IsWon or G.IsStuck then Break;
        if G.HasRemoval and (Random(5) > 0) then
        begin
          G.FindRemoval(Random(G.RemovalCount), A, B);
          if (A >= 0) and (B >= 0) and (not G.IsFree(A) or not G.IsFree(B)) then
          begin
            G.Remove(A, B);
            Found := True;
            Break;
          end;
          G.Remove(A, B);
        end
        else if G.CanDraw then G.Draw
        else if G.CanRecycle then G.Recycle;
      end;
      if Found then Break;
    end;
    Check(Found, 'test set-up: a hand with an under pair in it');
    if not Found then Exit;
    G.GetState(H);
    G2.UnderPairs := False;
    Check(G2.SetState(H) and G2.UnderPairs, 'it loads as an Easy hand, and takes the mode');
    H.UnderPairs := False;
    G2.UnderPairs := True;
    Check(not G2.SetState(H), 'as a Normal hand it is refused');
    Check(G2.UnderPairs, 'and nothing changes');
    K := 0;
    while G.CanUndo and G.Undo do Inc(K);
    Check(K > 0, 'and it can be undone');
  finally
    G.Free;
    G2.Free;
  end;
end;

procedure TestFindRemoval;
var
  G: TPyramidGame;
  Tab: array[0..27] of Integer;
  Stock: array[0..23] of Integer;
  A, B: Integer;
begin
  G := TPyramidGame.Create;
  try
    AllSame(Tab, Stock, 7, 7);
    Tab[21] := 6;
    Tab[22] := 7;
    Tab[23] := 13;
    G.Deal(BuildDeck(Tab, Stock));
    { 6 and 7 pair (6 with 7 at 22, and with every other free 7); the King goes alone }
    Check(G.RemovalCount = 1 + 5, 'one King, and the 6 with each of the five 7s');
    Check(G.FindRemoval(0, A, B), 'the first one');
    Check(not G.FindRemoval(G.RemovalCount, A, B), 'and no more after them');
  finally
    G.Free;
  end;
end;

function SameHand(const A, B: TPairHand): Boolean;
var
  I: Integer;
begin
  Result := (A.HandId = B.HandId) and (A.MaxRecycles = B.MaxRecycles) and (A.Recycled = B.Recycled)
    and (A.UnderPairs = B.UnderPairs)
    and (Length(A.Stock) = Length(B.Stock)) and (Length(A.Waste) = Length(B.Waste))
    and (Length(A.History) = Length(B.History));
  if not Result then Exit;
  for I := 0 to PyramidSize - 1 do
    if (A.Removed[I] <> B.Removed[I]) or (A.Tableau[I].Suit <> B.Tableau[I].Suit) or (A.Tableau[I].Rank <> B.Tableau[I].Rank) then Result := False;
  for I := 0 to High(A.Stock) do
    if (A.Stock[I].Suit <> B.Stock[I].Suit) or (A.Stock[I].Rank <> B.Stock[I].Rank) then Result := False;
  for I := 0 to High(A.Waste) do
    if (A.Waste[I].Suit <> B.Waste[I].Suit) or (A.Waste[I].Rank <> B.Waste[I].Rank) then Result := False;
  for I := 0 to High(A.History) do
    if (A.History[I].Kind <> B.History[I].Kind) or (A.History[I].A <> B.History[I].A) or (A.History[I].B <> B.History[I].B) then Result := False;
end;

{ Plays random legal moves, saves and reloads the hand after every move, and finally
  undoes everything: back at the deal. }
procedure TestRandomHands;
var
  G, G2: TPyramidGame;
  Start, Mid, Back: TPairHand;
  N, Step, K, A, B, Rejected, Moves, Wins, Recycles: Integer;
begin
  Rejected := 0;
  Moves := 0;
  Wins := 0;
  Recycles := 0;
  G := TPyramidGame.Create;
  G2 := TPyramidGame.Create;
  try
    for N := 1 to 400 do
    begin
      G.NewShuffled;
      G.MaxRecycles := Random(4);
      G.UnderPairs := Random(2) = 0;
      G2.UnderPairs := not G.UnderPairs;       { a loaded hand brings its own mode }
      G.GetState(Start);
      for Step := 1 to 400 do
      begin
        if G.IsWon or G.IsStuck then Break;
        K := Random(10);
        if (K = 0) and G.CanUndo then
          G.Undo
        else if (K < 6) and G.HasRemoval then
        begin
          G.FindRemoval(Random(G.RemovalCount), A, B);
          if not G.Remove(A, B) then Check(False, 'a removal found by FindRemoval must be allowed');
        end
        else if G.CanDraw then
          G.Draw
        else if G.CanRecycle then
        begin
          G.Recycle;
          Inc(Recycles);
        end
        else if G.HasRemoval then
        begin
          G.FindRemoval(0, A, B);
          G.Remove(A, B);
        end;
        Inc(Moves);
        G.GetState(Mid);
        if not G2.SetState(Mid) then
        begin
          Inc(Rejected);
          Continue;
        end;
        G2.GetState(Back);
        if not SameHand(Mid, Back) then Check(False, 'a saved hand reloads exactly');
      end;
      if G.IsWon then Inc(Wins);
      while G.CanUndo do
        if not G.Undo then
        begin
          Check(False, 'undo must always work');
          Break;
        end;
      G.GetState(Mid);
      Check((Mid.Recycled = 0) and (Length(Mid.Stock) = StockStart) and (Length(Mid.Waste) = 0) and (G.CardsLeft = PyramidSize),
        'undone all the way: the deal again');
    end;
  finally
    G.Free;
    G2.Free;
  end;
  Check(Rejected = 0, 'every real hand was accepted (' + IntToStr(Rejected) + ' of ' + IntToStr(Moves) + ' refused)');
  Check(Recycles > 100, 'enough hands turned the stock over (' + IntToStr(Recycles) + ')');
  WriteLn('random hands: ', Moves, ' moves checked, ', Wins, ' of 400 won by random play');
end;

procedure TestBadStates;
var
  G, G2: TPyramidGame;
  A, Bad: TPairHand;
  X, Y: Integer;
begin
  G := TPyramidGame.Create;
  G2 := TPyramidGame.Create;
  try
    G.NewShuffled;
    while G.CanDraw and (G.WasteCount < 5) do G.Draw;
    G.GetState(A);
    Check(G2.SetState(A), 'a real hand is accepted');
    Bad := A; Bad.Tableau[3] := Bad.Tableau[4];
    Check(not G2.SetState(Bad), 'two equal cards are refused');
    Bad := A; SetLength(Bad.Stock, Length(Bad.Stock) - 1);
    Check(not G2.SetState(Bad), 'a missing card is refused');
    Bad := A; Bad.Recycled := 1;
    Check(not G2.SetState(Bad), 'a turn-over that never happened is refused');
    Bad := A; Bad.MaxRecycles := -1;
    Check(not G2.SetState(Bad), 'a negative limit is refused');
    Bad := A; Bad.Removed[0] := True;
    Check(not G2.SetState(Bad), 'a covered card taken is refused');
    Bad := A; SetLength(Bad.History, 0);
    Check(not G2.SetState(Bad), 'a waste with no draws behind it is refused');
    { a removal that is not a pair }
    G.NewShuffled;
    X := 0;
    for Y := 21 to 27 do
      if G.CardAt(Y).Rank <> 13 then X := Y;
    Check(X > 0, 'test set-up');
    G.GetState(A);
    Bad := A;
    SetLength(Bad.History, 1);
    Bad.History[0].Kind := mkRemove;
    Bad.History[0].A := X;
    Bad.History[0].B := PosNone;
    Bad.Removed[X] := True;
    Check(not G2.SetState(Bad), 'taking a card that is not a King on its own is refused');
  finally
    G.Free; G2.Free;
  end;
end;

begin
  Randomize;
  TestLayout;
  TestPairs;
  TestFree;
  TestWaste;
  TestRecycle;
  TestWinAndStuck;
  TestFindRemoval;
  TestUnderPairs;
  TestUnderHistory;
  TestRandomHands;
  TestBadStates;
  if Failures = 0 then WriteLn('ALL PYRAMID TESTS PASSED')
  else
  begin
    WriteLn(Failures, ' FAILURES');
    Halt(1);
  end;
end.
