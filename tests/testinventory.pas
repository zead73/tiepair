program TestInventory;

{$mode objfpc}{$H+}

uses SysUtils, Inventory, Specials{$IFDEF PAS2JS}, JsCompat{$ENDIF};

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

var
  Inv, Inv2: TPlayerInventory;
  F: string;
  I: Integer;
procedure TestRewardAfterMisses;
begin
  Check(RewardAfterMisses(25, 0) = 25, 'no misses: full reward');
  Check(RewardAfterMisses(25, 1) = 25 - MissPenaltyCoins, 'one miss');
  Check(RewardAfterMisses(25, 3) = 25 - 3 * MissPenaltyCoins, 'three misses');
  Check(RewardAfterMisses(25, 100) = RewardFloorCoins, 'never below the floor');
  Check(RewardAfterMisses(25, -4) = 25, 'a negative count is treated as none');
  Check(RewardAfterMisses(3, 0) = 3, 'a reward already under the floor is not raised');
  Check(RewardAfterMisses(3, 5) = 3, 'nor cut further');
  Check(RewardAfterMisses(RewardFloorCoins, 7) = RewardFloorCoins, 'a reward at the floor stays there');
  Check(RewardAfterMisses(0, 2) = 0, 'zero stays zero');
end;

procedure TestDiscounts;
var
  Inv: TPlayerInventory;
  K: TSpecialKind;
begin
  Check(DiscountedPrice(25, 100) = 25, 'list price at 100 percent');
  Check(DiscountedPrice(45, 150) = 45, 'never raised above the list price');
  Check(DiscountedPrice(25, 50) = 15, 'half of 25 rounds up to a multiple of 5');
  Check(DiscountedPrice(45, 75) = 35, 'three quarters of 45 rounds up to 35');
  Check(DiscountedPrice(20, 50) = 10, 'an exact half stays exact');
  Check(DiscountedPrice(5, 1) = 5, 'a price is never below 5');
  Inv := TPlayerInventory.Create;
  try
    Check(Inv.PricePercent = 100, 'list price by default');
    Check((Inv.UndoPackPrice = UndoPackCost) and (Inv.HintPackPrice = HintPackCost), 'packs at list price');
    Inv.PricePercent := 50;
    Check(Inv.UndoPackPrice = 15, 'half-price undo pack');
    Check(Inv.HintPackPrice = 10, 'half-price hint pack');
    for K := Low(TSpecialKind) to High(TSpecialKind) do
      Check((Inv.SpecialPrice(K) < SpecialPrice[K]) and (Inv.SpecialPrice(K) mod 5 = 0),
        'every special card is cheaper: ' + SpecialKey[K]);
    { buying charges the discounted price, and affordability follows it }
    Inv.AddCoins(0);
    Check(Inv.Coins = StartingCoins, 'start with the starting coins');
    Check(Inv.BuyUndoPack and (Inv.Coins = StartingCoins - 15) and (Inv.UndoCards = UndoPackSize),
      'an undo pack is bought for the discounted price');
    Check(Inv.BuySpecial(skExtraTurn) and (Inv.Coins = StartingCoins - 15 - 15),
      'a Full deck is bought for the discounted price');
    Inv.PricePercent := 100;
    Check(Inv.Coins = StartingCoins - 30, 'changing the level changes no coins');
    Check(not Inv.CanBuySpecial(skDawn) = (Inv.Coins < SpecialPrice[skDawn]), 'affordability follows the list price again');
  finally
    Inv.Free;
  end;
end;

begin
  TestRewardAfterMisses;
  TestDiscounts;
  F := GetTempDir + 'tiepair_test_inventory.ini';
  if FileExists(F) then DeleteFile(F);
  Inv := TPlayerInventory.Create;
  Inv2 := TPlayerInventory.Create;
  try
    Check(Inv.Coins = StartingCoins, 'starts with starting coins');
    Check(Inv.UndoCards = 0, 'starts with no undo cards');
    Check(not Inv.UseUndoCard, 'cannot use an undo you do not have');
    Check(Inv.UndoCards = 0, 'count unchanged after failed use');

    Check(Inv.BuyUndoPack, 'buy a pack');
    Check(Inv.Coins = StartingCoins - UndoPackCost, 'coins spent');
    Check(Inv.UndoCards = UndoPackSize, 'cards received');

    for I := 1 to UndoPackSize do
      Check(Inv.UseUndoCard, 'use card ' + IntToStr(I));
    Check(not Inv.UseUndoCard, 'cannot overspend cards');
    Check(Inv.UndoCards = 0, 'cards at zero, never negative');

    { run out of coins }
    while Inv.CanBuyUndoPack do Inv.BuyUndoPack;
    Check(Inv.Coins < UndoPackCost, 'cannot afford another pack');
    I := Inv.Coins;
    Check(not Inv.BuyUndoPack, 'purchase refused when too poor');
    Check(Inv.Coins = I, 'coins unchanged after refused purchase');

    { hint cards }
    Inv.AddCoins(HintPackCost);
    Check(Inv.BuyHintPack, 'buy hint pack');
    Check(Inv.HintCards = HintPackSize, 'hint cards received');
    for I := 1 to HintPackSize do Check(Inv.UseHintCard, 'use hint ' + IntToStr(I));
    Check(not Inv.UseHintCard, 'cannot overspend hints');
    Check(Inv.HintCards = 0, 'hints never negative');
    Inv.AddHintCards(2);
    Inv.AddHintCards(-9);
    Check(Inv.HintCards = 2, 'negative hint grant ignored');
    while Inv.CanBuyUndoPack do Inv.BuyUndoPack;
    I := Inv.Coins;

    { earning, and ignoring nonsense amounts }
    Inv.AddCoins(WinCoins);
    Inv.AddUndoCards(WinUndoCards);
    Inv.AddCoins(-1000);
    Inv.AddUndoCards(-5);
    Check(Inv.Coins = I + WinCoins, 'negative coin grant ignored');

    { save and load round trip }
    Inv.SaveToFile(F);
    Inv2.LoadFromFile(F);
    Check(Inv2.Coins = Inv.Coins, 'coins survive save/load');
    Check(Inv2.UndoCards = Inv.UndoCards, 'undo cards survive save/load');
    Check(Inv2.HintCards = Inv.HintCards, 'hint cards survive save/load');

    { missing file = defaults }
    DeleteFile(F);
    Inv2.LoadFromFile(F);
    Check(Inv2.Coins = StartingCoins, 'missing file gives defaults');
    Check(Inv2.UndoCards = 0, 'missing file gives no cards');
  finally
    Inv.Free;
    Inv2.Free;
    if FileExists(F) then DeleteFile(F);
  end;
  if Failures = 0 then WriteLn('ALL INVENTORY TESTS PASSED') else
  begin
    WriteLn(Failures, ' FAILURES');
    Halt(1);
  end;
end.
