program TestSession;

{ The session: what the player may do with a Pyramid hand (undo and hints cost
  cards, wins pay rewards, the shop is open between hands). }

{$mode objfpc}{$H+}

uses SysUtils, DateUtils, Cards, Pyramid, Inventory, Session, Specials, Sound{$IFDEF PAS2JS}, JsCompat{$ENDIF};

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

{ 28 pyramid cards, then 24 stock cards (the waste rank is not used in Pyramid). }
function BuildDeck(const TabRanks: array of Integer; StockRank, WasteRank: Integer): TDeck;
var
  A: TCardArray;
  I: Integer;
begin
  SetLength(A, 52);
  for I := 0 to 27 do A[I] := MakeCard(TabRanks[I]);
  for I := 28 to 51 do A[I] := MakeCard(StockRank);
  Result := TDeck.CreateFromCards(A);
end;

{ A pyramid of Queens with one 6 at the bottom, and a stock of 7s: the 6 goes with the first card drawn. }
procedure DealSixAndSevens(S: TGameSession);
var
  R: array[0..27] of Integer;
  I: Integer;
begin
  for I := 0 to 27 do R[I] := 12;
  R[27] := 6;
  S.NewGameFrom(BuildDeck(R, 7, 7));
end;

{ A pyramid of Kings: every card goes on one tap. }
procedure DealKings(S: TGameSession);
var
  R: array[0..27] of Integer;
  I: Integer;
begin
  for I := 0 to 27 do R[I] := 13;
  S.NewGameFrom(BuildDeck(R, 7, 7));
end;

procedure ClearKings(S: TGameSession);
var
  A, B, Guard: Integer;
begin
  Guard := 0;
  while not S.Game.IsWon and S.Game.FindRemoval(0, A, B) and (Guard < 100) do
  begin
    Inc(Guard);
    S.Remove(A, B);
  end;
end;

procedure TestHint;
var
  S: TGameSession;
begin
  S := TGameSession.Create('');
  S.HazardsOn := False;
  try
    DealSixAndSevens(S);
    Check(S.UseHint = hrNoHintCards, 'no hint cards -> refused');
    Check(not S.HintActive, 'still not showing');
    S.Inventory.AddHintCards(3);
    Check(S.UseHint = hrNoMoves, 'at the start nothing can be taken away: the answer is to draw');
    Check(S.Inventory.HintCards = 2, 'and the card is spent');
    S.DrawStock;                                  { a 7: it goes with the 6 }
    Check(S.UseHint = hrShown, 'now there is a pair to show');
    Check(S.Inventory.HintCards = 1, 'one more hint card spent');
    Check(S.HintActive, 'the hint is showing');
    Check(S.UseHint = hrAlreadyShown, 'a second press while showing');
    Check(S.Inventory.HintCards = 1, 'costs nothing');
    Check(S.Remove(27, PosWaste), 'the pair is taken away');
    Check(not S.HintActive, 'the hint is gone after a move');
  finally
    S.Free;
  end;
end;

procedure TestUndoGate;
var
  S: TGameSession;
begin
  S := TGameSession.Create('');
  S.HazardsOn := False;
  try
    DealSixAndSevens(S);
    Check(not S.CanUseUndo, 'nothing to undo at the start');
    S.DrawStock;
    Check(not S.UseUndo, 'no undo cards -> refused');
    S.Inventory.AddUndoCards(2);
    Check(S.CanUseUndo, 'now it can');
    Check(S.UseUndo, 'undo the draw');
    Check((S.Game.StockCount = StockStart) and (S.Inventory.UndoCards = 1), 'the card went back, one undo card spent');
    Check(not S.UseUndo, 'nothing left to undo, and no card wasted');
    Check(S.Inventory.UndoCards = 1, 'the undo card is kept');
  finally
    S.Free;
  end;
end;

procedure TestUndoMany;
var
  S: TGameSession;
  I: Integer;
begin
  S := TGameSession.Create('');
  S.HazardsOn := False;
  try
    DealKings(S);
    S.Inventory.AddUndoCards(5);
    for I := 27 downto 24 do S.Remove(I, PosNone);
    S.DrawStock;
    for I := 1 to 5 do Check(S.UseUndo, 'undo ' + IntToStr(I));
    Check(S.Game.CardsLeft = PyramidSize, 'all the way back to the deal');
    Check(S.Inventory.UndoCards = 0, 'five cards for five moves');
    Check(not S.UseUndo, 'then it stops');
  finally
    S.Free;
  end;
end;

procedure TestWinReward;
var
  S: TGameSession;
  C0: Integer;
begin
  S := TGameSession.Create('');
  S.HazardsOn := False;
  try
    DealKings(S);
    C0 := S.Inventory.Coins;
    ClearKings(S);
    Check(S.Game.IsWon, 'won');
    Check(S.Inventory.Coins = C0 + WinCoins, 'coins rewarded');
    Check(S.Inventory.UndoCards = WinUndoCards, 'undo card rewarded');
    Check(S.Inventory.HintCards = WinHintCards, 'hint cards rewarded');
    Check(S.Note <> '', 'win note set');
    Check(not S.UseUndo, 'cannot undo after the win (no reward farming)');
    Check(S.Inventory.Coins = C0 + WinCoins, 'reward paid once');
  finally
    S.Free;
  end;
end;

{ Cards can only be bought between hands. }
procedure TestShopRule;
var
  S, S2: TGameSession;
  H: TSavedHand;
  C: Integer;
begin
  S := TGameSession.Create('');
  S2 := TGameSession.Create('');
  S.HazardsOn := False;
  S2.HazardsOn := False;
  try
    S.NewGame;
    Check(S.CanShop, 'a fresh deal: the shop is open');
    Check(S.BuyUndoPack, 'and sells');
    S.Inventory.AddCoins(500);
    S.DrawStock;
    Check(not S.CanShop, 'once a card is drawn the shop is shut');
    C := S.Inventory.Coins;
    Check(not S.BuyUndoPack and not S.BuyHintPack and not S.BuySpecial(skWild), 'and sells nothing');
    Check(S.Inventory.Coins = C, 'and takes no coins');
    { a hand put back opens the shop until the first move }
    S.ExportHand(H);
    Check(S2.ImportHand(H), 'a saved hand loads');
    Check(S2.CanShop, 'a loaded hand: the shop is open until the first move');
    S2.DrawStock;
    Check(not S2.CanShop, 'and shuts at the first move');
    { won: open }
    DealKings(S);
    ClearKings(S);
    Check(S.CanShop, 'a won hand: the shop is open');
    { ended: open }
    S.NewGame;
    S.DrawStock;
    S.EndHand;
    Check(S.CanShop, 'a given-up hand: the shop is open');
  finally
    S.Free;
    S2.Free;
  end;
end;

procedure TestRules;
var
  S, S2: TGameSession;
  H: TSavedHand;
begin
  S := TGameSession.Create('');
  S2 := TGameSession.Create('');
  try
    Check(not S.Easy and (S.Recycles = DefaultRecycles), 'a new session has the ordinary rules');
    S.NewGame;
    Check(not S.Game.UnderPairs and (S.Game.MaxRecycles = DefaultRecycles) and (S.Game.StockCount = StockStart),
      'and so does its first hand');
    S.SetRules(True, 1);
    Check(S.Easy and (S.Recycles = 1), 'the rules can be changed');
    Check(not S.Game.UnderPairs and (S.Game.MaxRecycles = DefaultRecycles), 'but the hand already dealt keeps its own');
    S.NewGame;
    Check(S.Game.UnderPairs and (S.Game.MaxRecycles = 1), 'the next hand has the new rules');
    DealKings(S);
    Check(S.Game.UnderPairs and (S.Game.MaxRecycles = 1), 'a rigged deal gets the rules too');
    { a loaded hand brings its own rules; the next deal uses the session's }
    S.SetRules(False, 3);
    S.NewGame;
    S.ExportHand(H);
    S2.SetRules(True, 1);
    Check(S2.ImportHand(H), 'load a Normal hand into a session set for Easy');
    Check(not S2.Game.UnderPairs and (S2.Game.MaxRecycles = 3), 'it keeps the rules it was dealt with');
    S2.NewGame;
    Check(S2.Game.UnderPairs and (S2.Game.MaxRecycles = 1), 'the next deal uses the session rules');
  finally
    S.Free; S2.Free;
  end;
end;

procedure TestBitesAndMisses;
var
  S: TGameSession;
  R: array[0..27] of Integer;
  I: Integer;
begin
  S := TGameSession.Create('');
  S.HazardsOn := False;
  try
    for I := 0 to 27 do R[I] := 13;
    S.NewGameFrom(BuildDeck(R, 7, 7));
    S.Game.SetHazard(hzBitten);
    for I := 0 to 27 do S.Game.SetMark(I, MarkNone);
    S.Game.SetMark(27, MarkBitten);
    S.Game.SetMark(26, MarkBitten);
    Check(S.Remove(27, PosNone) and (S.Bites = 1), 'a bitten King: one bite');
    Check(Pos('Bitten', S.Note) > 0, 'the note says so: ' + S.Note);
    Check(S.Game.Streak = 0, 'and the streak is gone');
    Check(S.Remove(25, PosNone) and (S.Game.Streak = 1), 'an ordinary one starts it again');
    S.Inventory.AddUndoCards(2);
    S.UseUndo;
    Check(S.Bites = 1, 'undoing an ordinary move keeps the bite');
    S.UseUndo;
    Check(S.Bites = 0, 'undoing the bitten one gives it back');
    S.DrawStock;
    Check((S.Misses = 1) and S.MissedLast, 'a draw while a King could be taken is a missed move');
    Check(S.PayoutNow = WinCoins - MissPenaltyCoins, 'and costs its coins');
    S.Inventory.AddUndoCards(1);
    S.UseUndo;
    Check(S.Misses = 0, 'undo takes it back');
  finally
    S.Free;
  end;
end;

{ Two bitten cards in one pair are two bites. }
procedure TestTwoBites;
var
  S: TGameSession;
  R: array[0..27] of Integer;
  I: Integer;
begin
  S := TGameSession.Create('');
  S.HazardsOn := False;
  try
    for I := 0 to 27 do R[I] := 12;
    R[26] := 1;
    R[27] := 12;
    S.NewGameFrom(BuildDeck(R, 7, 7));
    S.Game.SetHazard(hzBitten);
    for I := 0 to 27 do S.Game.SetMark(I, MarkNone);
    S.Game.SetMark(26, MarkBitten);
    S.Game.SetMark(27, MarkBitten);
    Check(S.Remove(26, 27) and (S.Bites = 2), 'an Ace and a Queen, both bitten: two bites');
    Check(S.PayoutNow = RewardAfterCuts(WinCoins, 0, 2), 'and both cost');
    S.Inventory.AddUndoCards(1);
    Check(S.UseUndo and (S.Bites = 0), 'undo gives both back');
  finally
    S.Free;
  end;
end;

procedure TestFeeding;
var
  S: TGameSession;
  I: Integer;
begin
  S := TGameSession.Create('');
  try
    S.SetRules(False, 3, hzHunger);
    S.NewGame;
    for I := 1 to FeedEvery - 1 do S.DrawStock;
    Check(Pos('feeds', S.Note) = 0, 'three draws: no feast');
    S.DrawStock;
    Check(Pos('feeds', S.Note) > 0, 'the fourth: he feeds: ' + S.Note);
    Check(S.Game.StockCount = StockStart - FeedEvery - 1, 'a stock card is gone');
    S.Inventory.AddUndoCards(1);
    S.UseUndo;
    Check(S.Game.StockCount = StockStart - FeedEvery + 1, 'undo brings it back');
  finally
    S.Free;
  end;
end;

procedure TestShop;
var
  S: TGameSession;
  C: Integer;
begin
  S := TGameSession.Create('');
  try
    C := S.Inventory.Coins;
    Check(S.BuyHintPack, 'buy hint pack');
    Check(S.Inventory.Coins = C - HintPackCost, 'hint pack price');
    Check(S.Inventory.HintCards = HintPackSize, 'hint pack size');
    while S.BuyHintPack do ;
    Check(S.Inventory.Coins < HintPackCost, 'ran out of coins');
    C := S.Inventory.Coins;
    Check(not S.BuyHintPack, 'cannot afford');
    Check(not S.BuyUndoPack or (C >= UndoPackCost), 'consistent affordability');
  finally
    S.Free;
  end;
end;

procedure TestPersistence;
var
  F: string;
  S: TGameSession;
begin
  F := GetTempDir + 'tiepair_test_session.ini';
  if FileExists(F) then DeleteFile(F);
  S := TGameSession.Create(F);
  try
    S.BuyHintPack;
    S.BuyUndoPack;
  finally
    S.Free;
  end;
  S := TGameSession.Create(F);
  try
    Check(S.Inventory.HintCards = HintPackSize, 'hint cards persisted');
    Check(S.Inventory.UndoCards = UndoPackSize, 'undo cards persisted');
    Check(S.Inventory.Coins = StartingCoins - HintPackCost - UndoPackCost,
      'coins persisted');
  finally
    S.Free;
  end;
  DeleteFile(F);
end;

procedure TestWav;
var
  W: string;
  DataLen: LongWord;
begin
  W := MakeNoWav;
  Check(Copy(W, 1, 4) = 'RIFF', 'wav RIFF header');
  Check(Copy(W, 9, 4) = 'WAVE', 'wav WAVE tag');
  Check(Copy(W, 37, 4) = 'data', 'wav data chunk');
  DataLen := Ord(W[41]) or (Ord(W[42]) shl 8) or (Ord(W[43]) shl 16) or (LongWord(Ord(W[44])) shl 24);
  Check(Length(W) = 44 + Integer(DataLen), 'wav length matches header');
  Check(DataLen > 1000, 'wav has audio data');
end;

procedure TestWinWav;
var
  W: string;
  DataLen: LongWord;
  N, I, Peak, V: Integer;
  T0: TDateTime;
  Ms: Int64;

  function Sample(K: Integer): Integer;
  begin
    Result := SmallInt(Word(Ord(W[45 + 2 * K])) or (Word(Ord(W[46 + 2 * K])) shl 8));
  end;

begin
  T0 := Now;
  W := MakeWinWav;
  Ms := MilliSecondsBetween(Now, T0);
  Check(Ms < 1500, 'win jingle builds quickly (took ' + IntToStr(Ms) + ' ms)');
  Check(Copy(W, 1, 4) = 'RIFF', 'win wav RIFF header');
  Check(Copy(W, 9, 4) = 'WAVE', 'win wav WAVE tag');
  Check(Copy(W, 37, 4) = 'data', 'win wav data chunk');
  DataLen := Ord(W[41]) or (Ord(W[42]) shl 8) or (Ord(W[43]) shl 16) or (LongWord(Ord(W[44])) shl 24);
  Check(Length(W) = 44 + Integer(DataLen), 'win wav length matches header');
  N := Integer(DataLen) div 2;
  Check((N > 22050 * 3) and (N < 22050 * 5), 'win jingle is 3-5 seconds');
  Peak := 0;
  for I := 0 to N - 1 do
  begin
    V := Abs(Sample(I));
    if V > Peak then Peak := V;
  end;
  Check(Peak > 20000, 'win jingle is loud enough (peak ' + IntToStr(Peak) + ')');
  Check(Peak < 30000, 'win jingle does not clip (peak ' + IntToStr(Peak) + ')');
  Check(Abs(Sample(0)) < 500, 'starts near silence (no click)');
  Check(Abs(Sample(N - 1)) < 500, 'ends near silence (no click)');
end;

begin
  Randomize;
  TestHint;
  TestUndoGate;
  TestUndoMany;
  TestWinReward;
  TestShop;
  TestShopRule;
  TestRules;
  TestBitesAndMisses;
  TestTwoBites;
  TestFeeding;
  TestPersistence;
  TestWav;
  TestWinWav;
  if Failures = 0 then WriteLn('ALL SESSION TESTS PASSED') else
  begin
    WriteLn(Failures, ' FAILURES');
    Halt(1);
  end;
end.
