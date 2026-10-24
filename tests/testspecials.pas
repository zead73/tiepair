program TestSpecials;

{ The special cards: the table of them, the inventory, what each does to a Pyramid
  hand, and how the session lets the player use them. }

{$mode objfpc}{$H+}

uses SysUtils, Classes, Cards, Pyramid, Inventory, Session, Specials, Campaign{$IFDEF PAS2JS}, JsCompat{$ENDIF};

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

{ A rigged deal (not a real 52-card deck: for tests that never save). }
function BuildDeck(const TabRanks: array of Integer; StockRank: Integer): TDeck;
var
  A: TCardArray;
  I: Integer;
begin
  SetLength(A, 52);
  for I := 0 to 27 do A[I] := MakeCard(TabRanks[I]);
  for I := 28 to 51 do A[I] := MakeCard(StockRank);
  Result := TDeck.CreateFromCards(A);
end;

procedure DealRanks(G: TPyramidGame; Rank, StockRank: Integer);
var
  R: array[0..27] of Integer;
  I: Integer;
  D: TDeck;
begin
  for I := 0 to 27 do R[I] := Rank;
  D := BuildDeck(R, StockRank);
  G.Deal(D);
  D.Free;
end;

procedure TestTable;
var
  K, J: TSpecialKind;
begin
  for K := Low(TSpecialKind) to High(TSpecialKind) do
  begin
    Check(SpecialPrice[K] > 0, SpecialName[K] + ' has a price');
    Check((SpecialName[K] <> '') and (SpecialInfo[K] <> '') and (SpecialKey[K] <> ''), SpecialName[K] + ' has its words');
    for J := Low(TSpecialKind) to High(TSpecialKind) do
      if J <> K then Check(SpecialKey[J] <> SpecialKey[K], 'keys are distinct');
    Check(NeedsTarget(K) = (K in [skWild, skStake]), SpecialName[K] + ': only Wild and Stake need a target');
  end;
  Check(SpecialPrice[skDawn] > SpecialPrice[skExtraTurn], 'Dawn costs more than half of it');
  Check(SpecialPrice[skDawn] > SpecialPrice[skEasyRule], 'and the other half');
end;

procedure TestInventory;
var
  Inv, Inv2: TPlayerInventory;
  F: string;
  K: TSpecialKind;
  C: Integer;
begin
  Inv := TPlayerInventory.Create;
  Inv2 := TPlayerInventory.Create;
  F := GetTempDir + 'tiepair_test_specialinv.ini';
  if FileExists(F) then DeleteFile(F);
  try
    for K := Low(TSpecialKind) to High(TSpecialKind) do
      Check(Inv.SpecialCards(K) = 0, 'a new player has no ' + SpecialName[K]);
    Check(Inv.TotalSpecialCards = 0, 'and none in total');
    C := Inv.Coins;
    Check(Inv.BuySpecial(skWild), 'buy a Wild card');
    Check((Inv.Coins = C - SpecialPrice[skWild]) and (Inv.SpecialCards(skWild) = 1), 'it costs its price and arrives');
    Check(Inv.UseSpecialCard(skWild) and (Inv.SpecialCards(skWild) = 0), 'using spends it');
    Check(not Inv.UseSpecialCard(skWild), 'none left to use');
    Check(Inv.SpecialCards(skWild) = 0, 'and never negative');
    while Inv.CanBuySpecial(skDawn) do Inv.BuySpecial(skDawn);
    C := Inv.Coins;
    Check(not Inv.BuySpecial(skDawn) and (Inv.Coins = C), 'too poor: refused, nothing taken');
    Inv.AddSpecial(skSeer, 2);
    Inv.AddSpecial(skSeer, -5);
    Check(Inv.SpecialCards(skSeer) = 2, 'adding a negative number does nothing');
    Check(Inv.TotalSpecialCards = Inv.SpecialCards(skDawn) + 2, 'the total adds up');

    Inv.SaveToFile(F);
    Inv2.LoadFromFile(F);
    for K := Low(TSpecialKind) to High(TSpecialKind) do
      Check(Inv2.SpecialCards(K) = Inv.SpecialCards(K), SpecialName[K] + ' survives save and load');
    Inv.Reset;
    Check(Inv.TotalSpecialCards = 0, 'resetting clears them');
    { an old file with no special-card lines loads with none; a damaged one is made safe }
    DeleteFile(F);
    with TStringList.Create do
    try
      Text := '[Inventory]'#10'Coins=40'#10'UndoCards=1'#10'HintCards=2'#10'Special.wild=-4'#10;
      SaveToFile(F);
    finally
      Free;
    end;
    Inv2.LoadFromFile(F);
    Check((Inv2.Coins = 40) and (Inv2.TotalSpecialCards = 0), 'an old or damaged file gives none');
  finally
    Inv.Free; Inv2.Free;
    DeleteFile(F);
  end;
end;

procedure TestExtraTurn;
var
  G: TPyramidGame;
  I: Integer;
begin
  G := TPyramidGame.Create;
  try
    DealRanks(G, 12, 7);                       { nothing ever goes }
    G.MaxRecycles := 1;
    Check(G.CanExtraTurn, 'an Extra turn can be used');
    G.Draw;
    Check(G.CanUndo, 'test set-up: there is something to undo');
    Check(G.ExtraTurn and (G.MaxRecycles = 2) and (G.RecyclesLeft = 2), 'one more turn-over');
    Check(not G.CanUndo, 'using a card forgets the undo');
    for I := 2 to StockStart do G.Draw;
    Check(G.Recycle and G.Draw, 'the first turn-over');
    while G.Draw do ;
    Check(G.CanRecycle and G.Recycle, 'and the second, which the card paid for');
    while G.Draw do ;
    Check(not G.CanRecycle, 'and no third');
  finally
    G.Free;
  end;
end;

procedure TestEasyRule;
var
  G: TPyramidGame;
  R: array[0..27] of Integer;
  I: Integer;
  D: TDeck;
begin
  G := TPyramidGame.Create;
  try
    for I := 0 to 27 do R[I] := 7;
    R[15] := 1;
    R[21] := 12;
    R[22] := 13;
    D := BuildDeck(R, 7);
    G.Deal(D);
    D.Free;
    G.Remove(22, PosNone);
    Check(not G.CanRemove(21, 15), 'Normal: the Ace under the Queen has to wait');
    Check(G.CanEasyRule, 'the Easy rule can be used');
    Check(G.EasyRule and G.UnderPairs, 'used');
    Check(not G.CanEasyRule, 'and not twice');
    Check(not G.CanUndo, 'it forgets the undo');
    Check(G.CanRemove(21, 15), 'now the Queen takes the Ace with her');
    Check(G.Remove(21, 15) and G.Removed(15), 'and does');
  finally
    G.Free;
  end;
end;

procedure TestSeer;
var
  G: TPyramidGame;
  A: TCard;
begin
  G := TPyramidGame.Create;
  try
    G.NewShuffled;
    A := G.StockCard(0);
    Check(G.CanReveal and not G.Revealed, 'the Seer''s eye can be used');
    Check(G.Reveal and G.Revealed, 'used');
    Check(not G.CanReveal, 'and not twice');
    Check(G.Draw, 'draw');
    Check(G.WasteTop(A) and (A.Rank >= 1), 'the card that was on top is the waste top now');
    { the stock cards named by StockCard are the ones that come next }
    A := G.StockCard(1);
    Check(G.Draw, 'draw again');
    Check(G.WasteTop(A) = True, 'the waste has a top');
  finally
    G.Free;
  end;
end;

procedure TestWildAndStake;
var
  G: TPyramidGame;
  C: TCard;
  Streak: Integer;
begin
  G := TPyramidGame.Create;
  try
    DealRanks(G, 5, 5);                        { fives: no two make 13 }
    Check(not G.CanRemove(27, 26), 'test set-up: two fives are no pair');
    Check(G.CanWild(27, 26), 'but a Wild card takes any two free cards');
    Check(not G.CanWild(27, 27), 'not one card twice');
    Check(not G.CanWild(0, 1), 'not covered cards');
    Check(not G.CanWild(27, PosWaste), 'and not a waste that is empty');
    Streak := G.Streak;
    Check(G.Wild(27, 26) and G.Removed(27) and G.Removed(26), 'it takes them');
    Check(G.Streak = Streak + 1, 'as a pair: the streak grows');
    Check(not G.CanUndo, 'and the undo is forgotten');
    { with the waste }
    G.Draw;
    Check(G.WasteTop(C) and G.CanWild(25, PosWaste), 'a free card and the waste top');
    Check(G.Wild(25, PosWaste) and (G.WasteCount = 0), 'the waste card goes too');
    { the Wood Stake: one free card, nothing else changes }
    Check(G.CanStake(24) and not G.CanStake(3), 'a Stake takes a free card only');
    Streak := G.Streak;
    Check(G.Stake(24) and G.Removed(24) and (G.Streak = Streak) and (G.Stakes = 1), 'it destroys it and is not a move');
    Check(not G.CanStake(24), 'a card that is gone cannot be staked');
  finally
    G.Free;
  end;
end;

{ A hand that went through special cards (which forget the undo) still saves and loads. }
procedure TestStateAfterSpecials;
var
  G, G2: TPyramidGame;
  H, H2: TPairHand;
  N, Step, A, B, K: Integer;
  Rejected: Integer;
begin
  Rejected := 0;
  G := TPyramidGame.Create;
  G2 := TPyramidGame.Create;
  try
    for N := 1 to 200 do
    begin
      G.NewShuffled;
      G.MaxRecycles := 1 + Random(3);
      G.UnderPairs := Random(2) = 0;
      G.SetHazard(THazard(Random(4)));
      G.SetRelicRules(Random(2) = 0, Random(2) = 0);
      for Step := 1 to 120 do
      begin
        if G.IsWon or G.IsStuck then Break;
        K := Random(14);
        case K of
          0: G.ExtraTurn;
          1: G.EasyRule;
          2: G.Reveal;
          3: if G.FindRemoval(Random(G.RemovalCount + 1), A, B) and G.CanStake(A) then G.Stake(A);
          4: if G.FindRemoval(0, A, B) and (B <> PosNone) then G.Wild(A, B);
          5: if G.CanUndo then G.Undo;
          6, 7, 8, 9:
            if G.FindRemoval(Random(G.RemovalCount + 1), A, B) then G.Remove(A, B);
        else
          if G.CanDraw then G.Draw
          else if G.CanRecycle then G.Recycle;
        end;
        G.GetState(H);
        if not G2.SetState(H) then
        begin
          Inc(Rejected);
          Continue;
        end;
        G2.GetState(H2);
        if (H2.Draws <> H.Draws) or (H2.Stakes <> H.Stakes) or (Length(H2.History) <> Length(H.History))
          or (H2.UnderPairs <> H.UnderPairs) or (H2.Revealed <> H.Revealed) or (H2.MaxRecycles <> H.MaxRecycles) then
          Check(False, 'a hand changed on its way through SetState');
      end;
    end;
  finally
    G.Free; G2.Free;
  end;
  Check(Rejected = 0, 'every real hand was accepted (' + IntToStr(Rejected) + ' refused)');
end;

procedure TestSession;
var
  S: TGameSession;
  R: array[0..27] of Integer;
  I, Coins: Integer;
  D: TDeck;
begin
  S := TGameSession.Create('');
  S.HazardsOn := False;
  try
    for I := 0 to 27 do R[I] := 12;
    D := BuildDeck(R, 7);
    S.NewGameFrom(D);
    D.Free;
    Check(not S.CanUseSpecial(skWild), 'you cannot use a card you do not own');
    Coins := S.Inventory.Coins;
    Check(S.BuySpecial(skWild) and (S.Inventory.Coins = Coins - SpecialPrice[skWild]), 'buy a Wild card');
    Check(S.CanUseSpecial(skWild), 'now it can be used');
    Check(not S.UseSpecial(skWild), 'but it needs two cards chosen: UseSpecial refuses it');
    Check(S.UseSpecialOn(skWild, 27, 26), 'a Wild card on two free cards');
    Check(S.Inventory.SpecialCards(skWild) = 0, 'the card is spent');
    Check(not S.CanShop, 'and the hand has started: the shop is shut');
    Check(not S.UseSpecialOn(skWild, 25, 24), 'none left');
    S.Inventory.AddSpecial(skWild, 1);
    Check(not S.UseSpecialOn(skWild, 3, 25), 'a covered card is refused, and the card is kept');
    Check(S.Inventory.SpecialCards(skWild) = 1, 'it is not spent');
    { the others }
    S.Inventory.AddSpecial(skStake, 1);
    Check(S.UseSpecialOn(skStake, 25, PosNone) and S.Game.Removed(25), 'a Wood Stake');
    S.Inventory.AddSpecial(skSeer, 1);
    Check(S.UseSpecial(skSeer) and S.Game.Revealed, 'a Seer''s eye');
    S.Inventory.AddSpecial(skSeer, 1);
    Check(not S.CanUseSpecial(skSeer), 'greyed out when it would do nothing');
    S.Inventory.AddSpecial(skDawn, 1);
    Check(S.UseSpecial(skDawn) and S.Game.UnderPairs and (S.Game.MaxRecycles = DefaultRecycles + 1), 'Dawn does both');
    S.Inventory.AddSpecial(skDawn, 1);
    Check(S.CanUseSpecial(skDawn), 'Dawn can still be used for its Extra turn');
  finally
    S.Free;
  end;
end;

{ A stuck hand is not lost while a special card could help. }
procedure TestRescue;
var
  S: TGameSession;
  R: array[0..27] of Integer;
  I: Integer;
  D: TDeck;
begin
  S := TGameSession.Create('');
  S.HazardsOn := False;
  try
    S.SetRules(False, 0);
    for I := 0 to 27 do R[I] := 12;
    D := BuildDeck(R, 7);
    S.NewGameFrom(D);
    D.Free;
    for I := 1 to StockStart do S.DrawStock;
    Check(S.HandOver, 'stuck with nothing to help: the hand is over');
    S.NewGameFrom(BuildDeck(R, 7));
    S.Inventory.AddSpecial(skExtraTurn, 1);
    for I := 1 to StockStart do S.DrawStock;
    Check(not S.HandOver and S.Game.IsStuck and S.HasRescue, 'with an Extra turn the hand waits');
    Check(S.UseSpecial(skExtraTurn) and S.Game.CanRecycle and not S.Game.IsStuck, 'and the card gives it a move');
  finally
    S.Free;
  end;
end;

begin
  Randomize;
  TestTable;
  TestInventory;
  TestExtraTurn;
  TestEasyRule;
  TestSeer;
  TestWildAndStake;
  TestStateAfterSpecials;
  TestSession;
  TestRescue;
  if Failures = 0 then WriteLn('ALL SPECIAL CARD TESTS PASSED') else
  begin
    WriteLn(Failures, ' FAILURES');
    Halt(1);
  end;
end.
