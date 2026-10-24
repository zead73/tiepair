program TestHands;

{ Saving a hand to disk and reading it back, and what a saved hand means to the game. }

{$mode objfpc}{$H+}

uses SysUtils, Classes, Cards, Pyramid, Inventory, Session, Vampires, Campaign, Duel,
  DuelSession, Settings, HandFile{$IFDEF PAS2JS}, JsCompat{$ENDIF};

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

function CardsEq(const A, B: TCard): Boolean;
begin
  Result := (A.Suit = B.Suit) and (A.Rank = B.Rank);
end;

function PilesEqual(const A, B: TCardArray): Boolean;
var
  I: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then Exit;
  for I := 0 to High(A) do
    if not CardsEq(A[I], B[I]) then Result := False;
end;

function HistoriesEqual(const A, B: TMoveArray): Boolean;
var
  I: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then Exit;
  for I := 0 to High(A) do
    if (A[I].Kind <> B[I].Kind) or (A[I].A <> B[I].A) or (A[I].B <> B[I].B) or (A[I].Missed <> B[I].Missed)
      or (A[I].Bites <> B[I].Bites) or (A[I].Ate <> B[I].Ate) or (A[I].Broke <> B[I].Broke)
      or (A[I].PrevStreak <> B[I].PrevStreak) or ((A[I].Kind = mkRemove) and not CardsEq(A[I].WasteCard, B[I].WasteCard)) then
      Result := False;
end;

function HandsEqual(const A, B: TSavedHand): Boolean;
var
  I: Integer;
begin
  Result := (A.Misses = B.Misses) and (A.Bites = B.Bites) and (A.ForgivenBite = B.ForgivenBite)
    and (A.ForgivenMiss = B.ForgivenMiss) and (A.FreeHintUsed = B.FreeHintUsed)
    and (A.Game.Hazard = B.Game.Hazard) and (A.Game.HandId = B.Game.HandId)
    and (A.Game.MaxRecycles = B.Game.MaxRecycles) and (A.Game.Recycled = B.Game.Recycled)
    and (A.Game.UnderPairs = B.Game.UnderPairs) and (A.Game.Revealed = B.Game.Revealed)
    and (A.Game.Stakes = B.Game.Stakes) and (A.Game.Draws = B.Game.Draws)
    and (A.Game.Streak = B.Game.Streak) and (A.Game.BestStreak = B.Game.BestStreak)
    and (A.Game.WasteGone = B.Game.WasteGone) and (A.Game.BreakUsed = B.Game.BreakUsed)
    and PilesEqual(A.Game.Stock, B.Game.Stock) and PilesEqual(A.Game.Waste, B.Game.Waste)
    and PilesEqual(A.Game.Eaten, B.Game.Eaten) and HistoriesEqual(A.Game.History, B.Game.History);
  if not Result then Exit;
  for I := 0 to PyramidSize - 1 do
    if not CardsEq(A.Game.Tableau[I], B.Game.Tableau[I]) or (A.Game.Removed[I] <> B.Game.Removed[I])
      or (A.Game.Marks[I] <> B.Game.Marks[I]) then
      Result := False;
end;

{ Plays a few moves of a shuffled hand so the state is interesting. }
procedure PlaySome(S: TGameSession; Moves: Integer);
var
  K, A, B: Integer;
begin
  for K := 1 to Moves do
  begin
    if S.Game.IsWon or S.Game.IsStuck then Break;
    if S.Game.FindRemoval(Random(S.Game.RemovalCount + 1), A, B) then
      S.Remove(A, B)
    else if S.Game.CanDraw then
      S.DrawStock
    else if S.Game.CanRecycle then
      S.Recycle;
  end;
end;

procedure TestTextRoundTrip;
var
  N, Moves: Integer;
  S, S2: TGameSession;
  A, B: TSavedHand;
  Text, Stamp: string;
  Undos: Integer;
  Kind: THazard;
begin
  Undos := 0;
  for N := 1 to 300 do
  begin
    S := TGameSession.Create('');
    S2 := TGameSession.Create('');
    try
      Kind := THazard(N mod 4);
      S.SetRules(N mod 2 = 0, 1 + N mod 3, Kind);
      S.NewGame;
      S.Inventory.AddUndoCards(2);
      Moves := Random(40);
      PlaySome(S, Moves);
      if (Random(3) = 0) and S.CanUseUndo then
      begin
        S.UseUndo;
        Inc(Undos);
      end;
      if not S.Game.IsWon then
      begin
        S.ExportHand(A);
        Text := HandToText(A, '2026-01-01 12:00');
        if not TextToHand(Text, B, Stamp) then
        begin
          Check(False, 'a real hand did not survive text: ' + Text);
          Break;
        end;
        if not HandsEqual(A, B) then
        begin
          Check(False, 'a hand changed on its way through text');
          Break;
        end;
        if not S2.ImportHand(B) then
        begin
          Check(False, 'a hand read back from text was refused');
          Break;
        end;
        S2.ExportHand(B);
        if not HandsEqual(A, B) then
        begin
          Check(False, 'the session did not restore the hand exactly');
          Break;
        end;
        if (S2.Misses <> S.Misses) or (S2.Bites <> S.Bites) then
        begin
          Check(False, 'the counters were not restored');
          Break;
        end;
      end;
    finally
      S.Free;
      S2.Free;
    end;
  end;
  Check(Undos > 5, 'enough hands had an undo in them (' + IntToStr(Undos) + ')');
end;

{ The hand carries its own rules: Easy or not, how many turn-overs, which trick. }
procedure TestHandRules;
var
  S, S2: TGameSession;
  H: TSavedHand;
begin
  S := TGameSession.Create('');
  S2 := TGameSession.Create('');
  try
    S.SetRules(True, 3, hzChained);
    S.NewGame;
    S.ExportHand(H);
    Check(H.Game.UnderPairs and (H.Game.MaxRecycles = 3) and (H.Game.Hazard = Ord(hzChained)), 'the hand holds its rules');
    S2.SetRules(False, 1, hzNone);                { the session's own rules for the next deal are different }
    Check(S2.ImportHand(H), 'a hand loads whatever the session''s own rules');
    Check(S2.Game.UnderPairs and (S2.Game.MaxRecycles = 3) and (S2.Game.Hazard = hzChained), 'and keeps its own');
    S2.NewGame;
    Check(not S2.Game.UnderPairs and (S2.Game.MaxRecycles = 1), 'the next deal uses the session''s rules again');
  finally
    S.Free; S2.Free;
  end;
end;

{ Marks, bites, forgiveness and the hunger's eaten cards all survive. }
procedure TestTrickHands;
var
  S, S2: TGameSession;
  H, H2: TSavedHand;
  Text, Stamp: string;
  I, Marked, N, A, B: Integer;
begin
  S := TGameSession.Create('');
  S2 := TGameSession.Create('');
  try
    S.SetRules(False, 2, hzBitten);
    S.NewGame;
    Marked := 0;
    for I := 0 to PyramidSize - 1 do
      if S.Game.Mark(I) = MarkBitten then Inc(Marked);
    Check(Marked = BittenCount, 'a bitten hand has its bitten cards');
    S.ExportHand(H);
    Check(TextToHand(HandToText(H, 'x'), H2, Stamp) and HandsEqual(H, H2), 'the marks survive text');
    { hunger: draw until he has eaten }
    S.SetRules(False, 3, hzHunger);
    S.NewGame;
    for N := 1 to FeedEvery do S.DrawStock;
    Check(S.Game.LastMoveAte, 'test set-up: he fed');
    S.ExportHand(H);
    Check(Length(H.Game.Eaten) = 1, 'the eaten card is in the saved hand');
    Text := HandToText(H, 'x');
    Check(TextToHand(Text, H2, Stamp) and HandsEqual(H, H2), 'and survives text');
    Check(S2.ImportHand(H2) and (S2.Game.StockCount = StockStart - FeedEvery - 1), 'and the game takes it back');
    S2.Inventory.AddUndoCards(1);
    Check(S2.UseUndo and (S2.Game.StockCount = StockStart - FeedEvery + 1), 'undoing the feast puts the card back (stock +1 +1)');
    { chained hand }
    S.SetRules(False, 2, hzChained);
    S.NewGame;
    S.ExportHand(H);
    Marked := 0;
    for I := 0 to PyramidSize - 1 do
      if H.Game.Marks[I] = MarkChained then Inc(Marked);
    Check(Marked = ChainedCount, 'a chained hand has its chains');
    Check(TextToHand(HandToText(H, 'x'), H2, Stamp) and HandsEqual(H, H2), 'the chains survive text');
    if S.Game.FindRemoval(0, A, B) then S.Remove(A, B);
  finally
    S.Free; S2.Free;
  end;
end;

procedure TestBadText;
var
  S: TGameSession;
  L: TStringList;
  A, B: TSavedHand;
  Good, Bad, Stamp: string;
  I: Integer;

  function Without(const Key: string): string;
  begin
    L.Text := Good;
    L.Values[Key] := '';
    L.Delete(L.IndexOfName(Key));
    Result := L.Text;
  end;

  function Replace(const Key, Value: string): string;
  begin
    L.Text := Good;
    L.Values[Key] := Value;
    Result := L.Text;
  end;

begin
  S := TGameSession.Create('');
  L := TStringList.Create;
  try
    S.NewGame;
    S.Inventory.AddUndoCards(1);
    PlaySome(S, 6);
    S.ExportHand(A);
    Good := HandToText(A, 'x');
    Check(TextToHand(Good, B, Stamp), 'the good text reads');

    Check(not TextToHand('', B, Stamp), 'empty text is refused');
    Check(not TextToHand('hello world', B, Stamp), 'text that is not a save is refused');
    Check(not TextToHand(StringReplace(Good, 'tiepair-hand 2', 'tiepair-hand 9', []), B, Stamp),
      'an unknown version is refused');
    Check(not TextToHand(StringReplace(Good, 'tiepair-hand 2', 'tiecards-hand 1', []), B, Stamp),
      'another game''s save is refused');
    for I := 0 to 13 do
    begin
      case I of
        0: Bad := Without('tableau');
        1: Bad := Without('removed');
        2: Bad := Without('stock');
        3: Bad := Without('waste');
        4: Bad := Without('eaten');
        5: Bad := Without('misses');
        6: Bad := Without('id');
        7: Bad := Replace('tableau', '0-1 0-2');
        8: Bad := Replace('removed', '0101');
        9: Bad := Replace('waste', '9-99');
        10: Bad := Replace('streak', '1 two');
        11: Bad := Replace('misses', 'x');
        12: Bad := Replace('marks', '9999999999999999999999999999');
        13: Bad := Replace('easy', '7');
      end;
      Check(not TextToHand(Bad, B, Stamp), 'damaged entry #' + IntToStr(I) + ' is refused');
    end;
    Check(not TextToHand(Replace('id', '0'), B, Stamp), 'an id of zero is refused');
    Check(not TextToHand(Replace('undo', 'q'), B, Stamp), 'an unknown undo move is refused');
    Check(not TextToHand(Replace('undo', 'd:1:0'), B, Stamp), 'a draw missing its streak is refused');
    Check(not TextToHand(Replace('undo', 'x:3:4:9-99:0:0:0'), B, Stamp), 'a removal with a bad card is refused');
    Check(not TextToHand(Replace('forgiven', '1'), B, Stamp), 'too few forgiven counters are refused');
    { text that reads fine but is not a believable hand is refused by the game }
    Bad := Replace('draws', '99');
    Check(TextToHand(Bad, B, Stamp), 'syntactically fine text reads');
    Check(S.ImportHand(B) or not S.ImportHand(B), 'test set-up');
    Bad := Replace('wastegone', '5');
    Check(TextToHand(Bad, B, Stamp) and not S.ImportHand(B), 'but the game refuses counters that do not add up');
    Check(S.Game.CardsLeft <= PyramidSize, 'and the current hand is untouched');
  finally
    L.Free;
    S.Free;
  end;
end;

procedure TestFiles;
var
  S: TGameSession;
  A, B: TSavedHand;
  F, Dir: string;
  Info: TSlotInfo;
  L: TStringList;
begin
  Dir := GetTempDir + 'tiepair_test_hands' + PathDelim;
  F := Dir + 'one.hand';
  if FileExists(F) then DeleteFile(F);
  S := TGameSession.Create('');
  L := TStringList.Create;
  try
    S.NewGame;
    PlaySome(S, 8);
    S.ExportHand(A);
    Check(not ReadHandFile(F, B), 'a missing file reads as no hand');
    Check(not PeekHandFile(F).Exists, 'and does not count as a save');
    Check(WriteHandFile(F, A), 'writing works (and makes the folder)');
    Check(not FileExists(F + '.tmp'), 'no temporary file is left behind');
    Check(ReadHandFile(F, B) and HandsEqual(A, B), 'the file reads back exactly');
    Info := PeekHandFile(F);
    Check(Info.Exists and (Info.CardsLeft = S.Game.CardsLeft), 'peeking reports the cards left');
    Check(Info.Stamp <> '', 'and when it was saved');

    { overwriting replaces it }
    PlaySome(S, 3);
    S.ExportHand(A);
    Check(WriteHandFile(F, A) and ReadHandFile(F, B) and HandsEqual(A, B), 'saving again replaces the old save');

    { a leftover temp file from a crash is harmless }
    L.Text := 'garbage';
    L.SaveToFile(F + '.tmp');
    Check(ReadHandFile(F, B) and HandsEqual(A, B), 'a stale temp file does not matter');
    Check(WriteHandFile(F, A), 'and is overwritten by the next save');
    Check(not FileExists(F + '.tmp'), 'cleanly');

    { a damaged file is simply "no save" }
    L.Text := 'tiepair-hand 2'#10'id=5'#10;
    L.SaveToFile(F);
    Check(not ReadHandFile(F, B), 'a truncated file reads as no hand');
    Check(not PeekHandFile(F).Exists, 'and is not offered as a save');
    L.Text := '';
    L.SaveToFile(F);
    Check(not ReadHandFile(F, B), 'an empty file reads as no hand');
    DeleteHandFile(F);
    Check(not FileExists(F), 'deleting removes it');
    DeleteHandFile(F);                           { and deleting nothing is fine }
  finally
    L.Free;
    S.Free;
    DeleteFile(F + '.tmp');
    RemoveDir(Dir);
  end;
  Check(AutoSaveFile(gmFreePlay) <> AutoSaveFile(gmCampaign), 'each mode has its own autosave');
  Check(SlotFile(1) <> SlotFile(2), 'each slot has its own file');
  Check(SlotFile(SlotCount) <> '', 'the last slot has a file too');
end;

{$IFNDEF PAS2JS}     { these replay a deal from a random seed, which JavaScript cannot do }
type
  TReplayMove = record
    Kind: Integer;          { 0 = a removal, 1 = a draw, 2 = a turn-over }
    A, B: Integer;
  end;
  TReplay = array of TReplayMove;

procedure AddMove(var R: TReplay; AKind, A, B: Integer);
begin
  SetLength(R, Length(R) + 1);
  R[High(R)].Kind := AKind;
  R[High(R)].A := A;
  R[High(R)].B := B;
end;

{ Finds a shuffled deal that the greedy bot wins (Easy rules, three turn-overs), and the moves it made. }
procedure FindWinningDeal(out Seed: LongInt; out Moves: TReplay);
var
  S: TGameSession;
  D: TDeck;
  A, B, Guard: Integer;
  Won: Boolean;
begin
  Seed := 0;
  repeat
    Inc(Seed);
    Moves := nil;
    RandSeed := Seed;
    S := TGameSession.Create('');
    D := TDeck.Create;
    try
      S.SetRules(True, 3, hzNone);
      D.Shuffle;
      S.NewGameFrom(D);
      Guard := 0;
      while not S.Game.IsWon and (Guard < 600) do
      begin
        Inc(Guard);
        if S.Game.FindRemoval(0, A, B) then
        begin
          S.Remove(A, B);
          AddMove(Moves, 0, A, B);
        end
        else if S.DrawStock then
          AddMove(Moves, 1, 0, 0)
        else if S.Recycle then
          AddMove(Moves, 2, 0, 0)
        else
          Break;
      end;
      Won := S.Game.IsWon;
    finally
      D.Free;
      S.Free;
    end;
  until Won;
end;

procedure Replay(S: TGameSession; const Moves: TReplay);
var
  K: Integer;
begin
  for K := 0 to High(Moves) do
    case Moves[K].Kind of
      0: S.Remove(Moves[K].A, Moves[K].B);
      1: S.DrawStock;
    else
      S.Recycle;
    end;
end;

{ A hand loaded from a save before it was won pays only once. }
procedure TestRewardOnce;
var
  Seed: LongInt;
  Moves: TReplay;
  S: TGameSession;
  D: TDeck;
  Start: TSavedHand;
  F: string;
  Coins0: Integer;
begin
  FindWinningDeal(Seed, Moves);
  F := GetTempDir + 'tiepair_test_paid.ini';
  if FileExists(F) then DeleteFile(F);
  S := TGameSession.Create(F);
  try
    S.SetRules(True, 3, hzNone);
    RandSeed := Seed;
    D := TDeck.Create;
    D.Shuffle;
    S.NewGameFrom(D);
    D.Free;
    S.ExportHand(Start);                       { "save at the start of the hand" }
    Coins0 := S.Inventory.Coins;
    Replay(S, Moves);
    Check(S.Game.IsWon, 'the hand is won');
    Check(S.Inventory.Coins > Coins0, 'the first win pays');
    Coins0 := S.Inventory.Coins;
    Check(Pos('already', S.Note) = 0, 'with no complaint');

    { load the save from before the win and win it again }
    Check(S.ImportHand(Start), 'the saved hand loads');
    Check(not S.Game.IsWon, 'it is a fresh hand again');
    Replay(S, Moves);
    Check(S.Game.IsWon, 'and can be won again');
    Check(S.Inventory.Coins = Coins0, 'but pays nothing the second time');
    Check(Pos('already', S.Note) > 0, 'and says why: ' + S.Note);

    { a different deal pays normally }
    D := TDeck.Create;
    D.Shuffle;
    S.NewGameFrom(D);
    D.Free;
    Check(not S.Inventory.HandPaid(S.Game.HandId), 'a new deal has not paid yet');
  finally
    S.Free;
  end;
  { the memory of paid hands survives a restart, so quitting does not reopen the loophole }
  S := TGameSession.Create(F);
  try
    Check(S.Inventory.HandPaid(Start.Game.HandId), 'paid hands are remembered across runs');
    Check(S.ImportHand(Start), 'the old save still loads');
    Coins0 := S.Inventory.Coins;
    Replay(S, Moves);
    Check(S.Game.IsWon and (S.Inventory.Coins = Coins0), 'and still pays nothing after a restart');
  finally
    S.Free;
    DeleteFile(F);
  end;
end;
{$ENDIF}

procedure TestPaidList;
var
  Inv, Inv2: TPlayerInventory;
  F: string;
  I: Integer;
begin
  F := GetTempDir + 'tiepair_test_paidlist.ini';
  if FileExists(F) then DeleteFile(F);
  Inv := TPlayerInventory.Create;
  Inv2 := TPlayerInventory.Create;
  try
    Check(not Inv.HandPaid(7), 'nothing is paid at first');
    Inv.MarkHandPaid(7);
    Check(Inv.HandPaid(7) and not Inv.HandPaid(8), 'a marked hand is remembered');
    Inv.MarkHandPaid(7);                         { twice is fine }
    for I := 1 to RememberedHands + 50 do Inv.MarkHandPaid(1000 + I);
    Check(not Inv.HandPaid(7), 'the oldest are forgotten past the limit');
    Check(Inv.HandPaid(1000 + RememberedHands + 50), 'the newest are kept');
    Inv.SaveToFile(F);
    Inv2.LoadFromFile(F);
    Check(Inv2.HandPaid(1000 + RememberedHands + 50), 'the list survives saving');
    Check(not Inv2.HandPaid(7), 'and so does the limit');
    { junk in the file is ignored, not a crash }
    with TStringList.Create do
    try
      Text := '[Inventory]'#10'Coins=10'#10'PaidHands=5,abc,,-4,0,6,5'#10;
      SaveToFile(F);
    finally
      Free;
    end;
    Inv2.LoadFromFile(F);
    Check(Inv2.HandPaid(5) and Inv2.HandPaid(6), 'good ids are read');
    Check(not Inv2.HandPaid(0) and not Inv2.HandPaid(-4), 'bad ids are ignored');
    Check(Inv2.Coins = 10, 'and the rest of the file still loads');
  finally
    Inv.Free; Inv2.Free;
    DeleteFile(F);
  end;
end;

procedure TestKillPending;
var
  F: string;
  C, C2: TCampaign;
begin
  F := GetTempDir + 'tiepair_test_kill.ini';
  if FileExists(F) then DeleteFile(F);
  C := TCampaign.Create(F);
  try
    C.AddLostHand;
    C.RecordKill;                                { the kill, then a crash }
  finally
    C.Free;
  end;
  C2 := TCampaign.Create(F);
  try
    Check(C2.Current = 1, 'a recorded kill moves the campaign on when it is loaded');
    Check(C2.LostHands = 0, 'and clears the lost hands');
  finally
    C2.Free;
  end;
  C2 := TCampaign.Create(F);
  try
    Check(C2.Current = 1, 'loading again does not move it on twice');
    C2.RecordKill;
    C2.Advance;                                  { the normal path: the scenes finish }
    Check(C2.Current = 2, 'the normal path moves on exactly once');
  finally
    C2.Free;
  end;
  C2 := TCampaign.Create(F);
  try
    Check(C2.Current = 2, 'and loading afterwards does not move on again');
    C2.Reset;
    C2.RecordKill;
    C2.Reset;
    Check(C2.Current = 0, 'resetting clears a pending kill');
  finally
    C2.Free;
  end;
  C2 := TCampaign.Create(F);
  try
    Check(C2.Current = 0, 'and that is saved');
  finally
    C2.Free;
  end;
  DeleteFile(F);
end;

procedure TestResumeHand;
var
  S, Src: TGameSession;
  C: TCampaign;
  DS: TDuelSession;
  H, H2: TSavedHand;
  Bad: TSavedHand;
begin
  S := TGameSession.Create('');
  Src := TGameSession.Create('');
  C := TCampaign.Create('');
  DS := TDuelSession.Create(S, C);
  try
    Src.SetRules(True, 3, hzNone);
    Src.NewGame;
    PlaySome(Src, 7);
    Src.ExportHand(H);

    DS.Activate;
    Check(DS.Duel.State = dsIntro, 'at the intro');
    Bad := H;
    Bad.Game.WasteGone := Bad.Game.WasteGone + 5;
    Check(not DS.ResumeHand(Bad), 'a hand that is not believable is not resumed');
    Check(DS.Duel.State = dsIntro, 'the duel stays at its intro');
    Check(DS.ResumeHand(H), 'a believable hand is resumed');
    Check(DS.Duel.State = dsPlaying, 'straight into play, skipping the intro');
    S.ExportHand(H2);
    Check(HandsEqual(H, H2), 'with exactly the saved cards');
    Check(not DS.ResumeHand(H), 'a hand cannot be resumed over a hand in progress');
    Check(DS.DrawStock or DS.Session.Game.HasMoves, 'play goes on');

    { restored misses count towards the pay }
    Src.NewGame;
    Src.ExportHand(H);
    H.Misses := 2;
    DS.Restart;
    Check(DS.ResumeHand(H), 'a hand with misses resumes');
    Check(DS.PayoutNow = VampireWinCoins[0] - 2 * MissPenaltyCoins, 'and its misses still cost');
  finally
    DS.Free; C.Free; Src.Free; S.Free;
  end;
end;

begin
  CrossCardsOn := False;                  { where the silver cross lies is random: it has its own tests }
  Randomize;
  TestTextRoundTrip;
  TestHandRules;
  TestTrickHands;
  TestBadText;
  TestFiles;
{$IFNDEF PAS2JS}
  TestRewardOnce;
{$ENDIF}
  TestPaidList;
  TestKillPending;
  TestResumeHand;
  if Failures = 0 then WriteLn('ALL HAND TESTS PASSED') else
  begin
    WriteLn(Failures, ' FAILURES');
    Halt(1);
  end;
end.
