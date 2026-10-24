program testrelics;

{ Relics: what each one does to a hand, how it is paid for and saved, and the
  rules that keep it fair (one break, one feeding at most, one free hint, one
  forgiven bite or miss, all undone and saved with the hand). }

{$mode objfpc}{$H+}

uses SysUtils, Classes, Cards, Pyramid, Storage, Inventory, Session, Settings, Story, Trophies,
  Relics, HandFile, Campaign
  {$IFDEF PAS2JS}, JsCompat{$ENDIF};

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

function StoryPath: string;
begin
{$IFDEF PAS2JS}
  Result := 'assets/story/story.ini';          { run from the project folder }
{$ELSE}
  Result := ExtractFilePath(ParamStr(0)) + '../assets/story/story.ini';
{$ENDIF}
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

procedure TestTable;
var
  R: TRelic;
begin
  for R := Low(TRelic) to High(TRelic) do
  begin
    Check(RelicIndexOf(RelicKey(R)) = Ord(R), 'a key finds its relic: ' + RelicKey(R));
    Check(RelicPrice(R) > 0, RelicKey(R) + ' has a price');
    Check(HasRelic(RelicBit(R), R) and not HasRelic(0, R), 'its bit');
  end;
  Check(RelicIndexOf('nonsense') = -1, 'an unknown key is -1');
  Check((RelicSlots(0) = 1) and (RelicSlots(1) = 2) and (RelicSlots(3) = 4) and (RelicSlots(9) = MaxRelicSlots) and (RelicSlots(-2) = 1),
    'one slot, and one more for each vampire trophy, up to the cap');
  Check((RelicTrophy(rlLocket) = Ord(trPerfect)) and (RelicTrophy(rlMoonstone) = Ord(trVampire1)), 'the Locket and the Moonstone can also be earned');
  Check((RelicTrophy(rlGarlic) = NoRelicTrophy) and (RelicTrophy(rlPick) = NoRelicTrophy) and (RelicTrophy(rlSpoon) = NoRelicTrophy),
    'the first three are only bought');
  Check(ValidRelicMask(0) and ValidRelicMask(31) and not ValidRelicMask(32) and not ValidRelicMask(-1), 'a mask has five bits');
end;

procedure TestBuying;
var
  Inv, Inv2: TPlayerInventory;
  F, Text: string;
begin
  F := GetTempDir + 'tiepair_test_relic_inv.ini';
  StoreDelete(F);
  Inv := TPlayerInventory.Create;
  try
    Check(not Inv.BoughtRelic(rlPick) and not Inv.CanBuyRelic(rlPick), 'nothing bought; 50 coins do not reach 160');
    Check(not Inv.BuyRelic(rlPick) and (Inv.Coins = StartingCoins), 'a refused purchase takes nothing');
    Inv.AddCoins(1000);
    Check(Inv.BuyRelic(rlPick) and (Inv.Coins = StartingCoins + 1000 - RelicPrice(rlPick)), 'buy one at its price');
    Check(not Inv.BuyRelic(rlPick), 'not twice');
    Check(Inv.BoughtRelic(rlPick) and not Inv.BoughtRelic(rlSpoon), 'only that one');
    Inv.SaveToFile(F);
    Text := Inv.ExportText;
  finally
    Inv.Free;
  end;
  Inv2 := TPlayerInventory.Create;
  Inv2.LoadFromFile(F);
  try
    Check(Inv2.BoughtRelic(rlPick), 'saved on disk');
    Inv2.Reset;
    Check(not Inv2.BoughtRelic(rlPick), 'a reset takes it away');
    Inv2.ImportText(Text);
    Check(Inv2.BoughtRelic(rlPick), 'a save slot keeps it');
  finally
    Inv2.Free;
  end;
  StoreDelete(F);
end;

procedure TestSettings;
var
  F: string;
  S: TSettings;
begin
  F := GetTempDir + 'tiepair_test_relic_set.ini';
  StoreDelete(F);
  S := TSettings.Create(F);
  try
    Check(S.Equipped = '', 'nothing equipped to begin with');
    S.Equipped := 'pick,locket';
    S.Save;
  finally
    S.Free;
  end;
  S := TSettings.Create(F);
  try
    Check(S.Equipped = 'pick,locket', 'saved');
    S.ResetRelics;
    Check(S.Equipped = '', 'and reset');
  finally
    S.Free;
  end;
  StoreDelete(F);
end;

procedure TestCharges;
var
  S: TGameSession;
  R: array[0..27] of Integer;
  I: Integer;
begin
  for I := 0 to 27 do R[I] := 12;
  S := TGameSession.Create('');
  S.HazardsOn := False;
  try
    { every draw misses a move: a King can always be taken away }
    for I := 0 to 27 do R[I] := 13;
    S.NewGameFrom(BuildDeck(R, 7, 7));
    S.DrawStock;
    S.DrawStock;
    Check((S.Misses = 2) and (S.ChargedMisses = 2), 'no relic: two misses charged');
    Check(S.PayoutNow = RewardAfterCuts(WinCoins, 2, 0), 'and paid for');
    { the Steady Locket forgives the first }
    S.Relics := RelicBit(rlLocket);
    S.NewGameFrom(BuildDeck(R, 7, 7));
    S.DrawStock;
    Check((S.Misses = 1) and (S.ChargedMisses = 0), 'the Locket: the first miss costs nothing');
    Check(S.PayoutNow = WinCoins, 'so the hand pays in full');
    S.DrawStock;
    Check((S.Misses = 2) and (S.ChargedMisses = 1) and (S.PayoutNow = RewardAfterCuts(WinCoins, 1, 0)), 'the second is charged');
    S.Inventory.AddUndoCards(2);
    S.UseUndo;
    Check((S.Misses = 1) and (S.ChargedMisses = 0), 'undo takes the miss back, and the forgiveness stays right');
    S.UseUndo;
    Check((S.Misses = 0) and (S.ChargedMisses = 0), 'and back to none');
    { the Garlic Wreath forgives the first bite }
    S.Relics := RelicBit(rlGarlic);
    S.NewGameFrom(BuildDeck(R, 7, 7));
    S.Game.SetHazard(hzBitten);
    for I := 0 to 27 do S.Game.SetMark(I, MarkNone);
    S.Game.SetMark(27, MarkBitten);
    S.Game.SetMark(26, MarkBitten);
    Check(S.Remove(27, PosNone), 'play a bitten card');
    Check((S.Bites = 1) and (S.ChargedBites = 0), 'the Garlic: the first bite is free');
    Check(S.PayoutNow = WinCoins, 'and costs the hand nothing');
    Check(S.Remove(26, PosNone), 'a second bitten card');
    Check((S.Bites = 2) and (S.ChargedBites = 1) and (S.PayoutNow = RewardAfterCuts(WinCoins, 0, 1)), 'costs its coins');
    { with both, each forgives its own }
    S.Relics := RelicBit(rlGarlic) or RelicBit(rlLocket);
    S.NewGameFrom(BuildDeck(R, 7, 7));
    Check(S.Relics = (RelicBit(rlGarlic) or RelicBit(rlLocket)), 'both equipped');
    { a Locket put on in the middle of the hand forgives only what happens from then on }
    S.Relics := 0;
    S.NewGameFrom(BuildDeck(R, 7, 7));
    S.DrawStock;
    S.Relics := RelicBit(rlLocket);
    Check((S.Misses = 1) and (S.ChargedMisses = 1), 'a Locket put on after a miss does not forgive it');
    S.DrawStock;
    Check((S.Misses = 2) and (S.ChargedMisses = 1), 'the next miss is the one it forgives');
    S.DrawStock;
    Check((S.Misses = 3) and (S.ChargedMisses = 2), 'and only that one');
    S.Relics := 0;
    S.Relics := RelicBit(rlLocket);
    S.DrawStock;
    Check((S.Misses = 4) and (S.ChargedMisses = 3), 'taken out and put back, it forgives no second miss');
    S.Relics := 0;
    Check(S.ChargedMisses = 3, 'taken out, the miss it forgave stays forgiven');
    S.Inventory.AddUndoCards(5);
    S.UseUndo;
    S.UseUndo;
    S.UseUndo;
    Check((S.Misses = 1) and (S.ChargedMisses = 1), 'undone past the forgiven miss: it is charged again');
    S.Relics := RelicBit(rlLocket);
    S.DrawStock;
    Check((S.Misses = 2) and (S.ChargedMisses = 1), 'and forgiven again when it comes round once more');
    { the same for a Garlic Wreath and the bites }
    S.Relics := 0;
    S.NewGameFrom(BuildDeck(R, 7, 7));
    S.Game.SetHazard(hzBitten);
    for I := 0 to 27 do S.Game.SetMark(I, MarkNone);
    S.Game.SetMark(27, MarkBitten);
    S.Game.SetMark(26, MarkBitten);
    S.Game.SetMark(25, MarkBitten);
    Check(S.Remove(27, PosNone) and (S.Bites = 1) and (S.ChargedBites = 1), 'a bite with no Garlic is charged');
    S.Relics := RelicBit(rlGarlic);
    Check(S.Remove(26, PosNone) and (S.Bites = 2) and (S.ChargedBites = 1), 'a Garlic put on after it forgives the next');
    Check(S.Remove(25, PosNone) and (S.Bites = 3) and (S.ChargedBites = 2), 'and only that one');
  finally
    S.Free;
  end;
end;

procedure TestMoonstone;
var
  S, S2: TGameSession;
  H: TSavedHand;
begin
  S := TGameSession.Create('');
  S2 := TGameSession.Create('');
  S.HazardsOn := False;
  S2.HazardsOn := False;
  try
    Check(S.Inventory.HintCards = 0, 'test set-up: no hint cards');
    S.NewGame;
    Check((S.UseHint = hrNoHintCards) and not S.FreeHintAvailable, 'no relic and no cards: no hint');
    S.Relics := RelicBit(rlMoonstone);                 { a hand not yet started takes it at once }
    Check(S.FreeHintAvailable, 'equipped before the first move: this hand has the free hint');
    Check(S.UseHint <> hrNoHintCards, 'the free hint works');
    Check((S.Inventory.HintCards = 0) and not S.FreeHintAvailable, 'and used no card; it is spent');
    S.DrawStock;
    Check(S.UseHint = hrNoHintCards, 'a second hint needs a card');
    { saved and loaded: the free hint is not given back }
    S.ExportHand(H);
    Check(H.FreeHintUsed, 'the saved hand remembers');
    Check(S2.ImportHand(H), 'it loads');
    Check(not S2.FreeHintAvailable and (S2.UseHint = hrNoHintCards), 'a resumed hand does not give the hint back');
    { taking it out and putting it back gives nothing; a new hand starts afresh }
    S.Relics := 0;
    Check(not S.FreeHintAvailable, 'taken out: no free hint');
    S.Relics := RelicBit(rlMoonstone);
    Check(not S.FreeHintAvailable, 'put back: the hint it gave stays used');
    S.NewGame;
    Check(S.FreeHintAvailable, 'the next hand has its free hint');
    { put on in the middle of a hand, it works at once }
    S.Relics := 0;
    S.NewGame;
    S.DrawStock;
    Check(not S.FreeHintAvailable, 'no relic: no free hint');
    S.Relics := RelicBit(rlMoonstone);
    Check(S.FreeHintAvailable and (S.UseHint <> hrNoHintCards), 'equipped after a move: the free hint is there');
    Check(not S.FreeHintAvailable, 'and used');
  finally
    S.Free;
    S2.Free;
  end;
end;

procedure TestRulesRelics;
var
  S, S2: TGameSession;
  H: TSavedHand;
begin
  S := TGameSession.Create('');
  S2 := TGameSession.Create('');
  try
    S.Relics := RelicBit(rlPick) or RelicBit(rlSpoon);
    S.NewGame;
    Check(S.Game.PickOn and S.Game.FeedsOnce, 'the Pick and the Spoon reach the game''s rules');
    S.ExportHand(H);
    S2.Relics := 0;
    Check(S2.ImportHand(H) and not S2.Game.PickOn and not S2.Game.FeedsOnce,
      'a loaded hand takes the relics equipped now, not the ones it was saved with');
    S2.Relics := RelicBit(rlPick);
    Check(S2.Game.PickOn and not S2.Game.FeedsOnce, 'and equipping in the middle of it changes the rules at once');
    S.Relics := 0;
    Check(not S.Game.PickOn and not S.Game.FeedsOnce, 'so does taking them out');
    H.ForgivenBite := 1;
    Check(not S2.ImportHand(H), 'a forgiven bite that never happened is refused');
    H.ForgivenBite := 0;
    H.ForgivenMiss := 2;
    Check(not S2.ImportHand(H), 'and so is a forgiven miss that never happened');
    S.Relics := 0;
    S.NewGame;
    Check(not S.Game.PickOn and not S.Game.FeedsOnce, 'no relics: the plain rules');
  finally
    S.Free;
    S2.Free;
  end;
end;

{ Taking the Pick out when a chained card is the only move left loses the hand. }
procedure TestPickTakenOutStuck;
var
  S: TGameSession;
  R: array[0..27] of Integer;
  I: Integer;
begin
  for I := 0 to 27 do R[I] := 12;
  R[25] := 6;                                      { goes with the 7 on the waste, and it is chained }
  S := TGameSession.Create('');
  S.HazardsOn := False;
  try
    S.SetRules(False, 0);
    S.Relics := RelicBit(rlPick);
    S.NewGameFrom(BuildDeck(R, 7, 7));
    S.Game.SetHazard(hzChained);
    for I := 0 to 27 do S.Game.SetMark(I, MarkNone);
    S.Game.SetMark(25, MarkChained);
    for I := 1 to StockStart do S.DrawStock;
    Check((S.Game.StockCount = 0) and not S.Game.CanRecycle, 'test set-up: the stock is used up');
    Check(not S.Game.IsStuck and S.Game.HasMoves and not S.HandOver, 'with the Pick the chained card is a move');
    S.Relics := 0;
    Check(S.Game.IsStuck and S.HandOver, 'taken out: no move is left, and the hand is over');
  finally
    S.Free;
  end;
end;

procedure DeleteLine(var Text: string; const Key: string);
var
  P, Q: Integer;
begin
  P := Pos(Key + '=', Text);
  if P = 0 then Exit;
  Q := P + Pos(#10, Copy(Text, P, MaxInt)) - 1;
  Delete(Text, P, Q - P + 1);
end;

procedure TestHandText;
var
  S: TGameSession;
  H, H2: TSavedHand;
  Text, Stamp: string;
begin
  S := TGameSession.Create('');
  S.HazardsOn := False;
  try
    S.Relics := RelicBit(rlPick) or RelicBit(rlMoonstone);
    S.NewGame;
    S.UseHint;
    S.ExportHand(H);
    Text := HandToText(H, 'x');
    H.Bites := 3;
    H.ForgivenBite := 2;
    H.Misses := 4;
    H.ForgivenMiss := 3;
    H.Game.BreakUsed := True;
    Text := HandToText(H, 'x');
    Check((Pos('forgiven=2 3', Text) > 0) and (Pos('freehint=1', Text) > 0) and (Pos('breakused=1', Text) > 0), 'the new lines are written');
    Check((Pos('relics=', Text) = 0) and (Pos('feedonce=', Text) = 0), 'and a hand does not carry the relics: they are the player''s');
    Check(TextToHand(Text, H2, Stamp) and (H2.ForgivenBite = 2) and (H2.ForgivenMiss = 3) and H2.FreeHintUsed and H2.Game.BreakUsed,
      'and read back');
    { the lines are not optional: a save that lacks them is not a save of this game }
    DeleteLine(Text, 'forgiven');
    Check(Pos('forgiven=', Text) = 0, 'test set-up: the line is gone');
    Check(not TextToHand(Text, H2, Stamp), 'a save without the forgiven counters is refused');
  finally
    S.Free;
  end;
end;

procedure TestText;
var
  St: TStory;
  R: TRelic;
begin
  St := TStory.Create;
  try
    St.LoadFromFile(StoryPath);
    Check(Length(St.Validate) = 0, 'the story file has everything, the relic text included');
    for R := Low(TRelic) to High(TRelic) do
    begin
      Check(St.RelicName(RelicKey(R)) <> '', RelicKey(R) + ' has a name');
      Check(St.RelicLine(RelicKey(R)) <> '', RelicKey(R) + ' says what it does');
      Check(Pos('%', St.RelicLine(RelicKey(R))) = 0, RelicKey(R) + ' has no format marks');
    end;
  finally
    St.Free;
  end;
end;

begin
  CrossCardsOn := False;
  TestTable;
  TestBuying;
  TestSettings;
  TestCharges;
  TestMoonstone;
  TestRulesRelics;
  TestPickTakenOutStuck;
  TestHandText;
  TestText;
  if Failures = 0 then WriteLn('ALL RELIC TESTS PASSED')
  else
  begin
    WriteLn(Failures, ' FAILURES');
    Halt(1);
  end;
end.
