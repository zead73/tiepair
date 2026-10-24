program testcosmetics;

{ Style: the original look is exactly what the game always had, what is bought is
  paid for and saved with the coins, what a trophy unlocks cannot be bought, and
  the text for every item is in the story file. }

{$mode objfpc}{$H+}

uses SysUtils, Classes, Storage, Inventory, Settings, Story, Trophies, Cosmetics, Campaign
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

function Rgb(R, G, B: Integer): Integer;
begin
  Result := (R shl 16) or (G shl 8) or B;
end;

{ Anyone who never opens Style must see no change at all: item 0 is the old look, number for number. }
procedure TestOriginalLook;
begin
  Check(BackColor(0, 0) = Rgb(42, 13, 26), 'back: the wine base');
  Check(BackColor(0, 1) = Rgb(13, 6, 8), 'back: the dark centre');
  Check(BackColor(0, 2) = Rgb(74, 26, 44), 'back: the lattice');
  Check(BackColor(0, 3) = Rgb(201, 162, 74), 'back: the gold');
  Check(BackColor(0, 4) = Rgb(122, 42, 58), 'back: the inner frame');
  Check(ClothColor(0, 0) = Rgb(24, 74, 48), 'cloth: the felt centre');
  Check(ClothColor(0, 1) = Rgb(5, 16, 11), 'cloth: the felt edge');
  Check(ClothColor(0, 2) = Rgb(110, 90, 46), 'cloth: the frame');
  Check(ClothColor(0, 3) = Rgb(58, 48, 26), 'cloth: the inner frame');
  Check(HouseImageKey(0) = 'house', 'moon: the house picture as it was');
  Check((MoonColor(0, 0) = Rgb(241, 232, 207)) and (MoonColor(0, 1) = -1), 'moon: the original disc, no ring');
  Check(MoonColor(3, 1) <> -1, 'the eclipse has a ring');
  Check((ColorR(Rgb(1, 2, 3)) = 1) and (ColorG(Rgb(1, 2, 3)) = 2) and (ColorB(Rgb(1, 2, 3)) = 3), 'colours split back into parts');
end;

procedure TestTable;
var
  K: TCosmeticKind;
  I, J: Integer;
begin
  for K := Low(TCosmeticKind) to High(TCosmeticKind) do
  begin
    Check(CosmeticIsFree(K, 0) and (CosmeticCost(K, 0) = 0) and (CosmeticTrophy(K, 0) = NoTrophy), 'the first of each kind is free');
    for I := 0 to CosmeticsPerKind - 1 do
    begin
      Check(CosmeticIndexOf(K, CosmeticKey(K, I)) = I, 'a key finds its item (' + CosmeticStoryKey(K, I) + ')');
      for J := I + 1 to CosmeticsPerKind - 1 do
        Check(CosmeticKey(K, I) <> CosmeticKey(K, J), 'keys are unique');
      if I > 0 then
        Check((CosmeticCost(K, I) > 0) <> (CosmeticTrophy(K, I) <> NoTrophy), 'every other one is bought or earned, never both or neither');
    end;
    Check(CosmeticIndexOf(K, 'nonsense') = 0, 'an unknown key means the original');
    Check(CosmeticTrophy(K, CosmeticsPerKind - 1) <> NoTrophy, 'the last of each kind is earned');
  end;
  Check((CosmeticCost(ckBack, 1) = BackPrice) and (CosmeticCost(ckCloth, 1) = ClothPrice) and (CosmeticCost(ckMoon, 1) = MoonPrice), 'the list prices');
  Check((CosmeticTrophy(ckBack, 3) = Ord(trVampire0)) and (CosmeticTrophy(ckCloth, 3) = Ord(trVampire1))
    and (CosmeticTrophy(ckMoon, 3) = Ord(trVampire2)), 'one vampire''s trophy for each kind');
  Check(HouseImageKey(2) = 'house_harvest', 'a moon has its own picture');
end;

procedure TestBuying;
var
  Inv, Inv2: TPlayerInventory;
  F, Text: string;
begin
  F := GetTempDir + 'tiepair_test_style_inv.ini';
  StoreDelete(F);
  Inv := TPlayerInventory.Create;
  try
    Check(not Inv.BoughtCosmetic(ckBack, 1), 'nothing bought yet');
    Check(not Inv.CanBuyCosmetic(ckBack, 1), '50 coins do not buy a 60-coin card back');
    Check(not Inv.BuyCosmetic(ckBack, 1) and (Inv.Coins = StartingCoins), 'a refused purchase takes nothing');
    Inv.AddCoins(500);
    Check(not Inv.CanBuyCosmetic(ckBack, 0), 'the original is not for sale');
    Check(not Inv.CanBuyCosmetic(ckBack, 3), 'what a trophy unlocks is not for sale');
    Check(not Inv.CanBuyCosmetic(ckBack, 9), 'and there is no number 9');
    Check(Inv.BuyCosmetic(ckBack, 1), 'buy a card back');
    Check(Inv.Coins = StartingCoins + 500 - BackPrice, 'for its list price');
    Check(Inv.BoughtCosmetic(ckBack, 1) and not Inv.BoughtCosmetic(ckBack, 2) and not Inv.BoughtCosmetic(ckCloth, 1), 'only that one');
    Check(not Inv.BuyCosmetic(ckBack, 1), 'not twice');
    Check(Inv.BuyCosmetic(ckCloth, 2) and Inv.BuyCosmetic(ckMoon, 1), 'a cloth and a moon');
    Check(Inv.Coins = StartingCoins + 500 - BackPrice - ClothPrice - MoonPrice, 'at their prices');
    Check(Inv.SpendCoins(10) and not Inv.SpendCoins(100000), 'SpendCoins takes what there is, or nothing');
    Inv.SaveToFile(F);
    Text := Inv.ExportText;
  finally
    Inv.Free;
  end;
  Inv2 := TPlayerInventory.Create;
  Inv2.LoadFromFile(F);
  try
    Check(Inv2.BoughtCosmetic(ckBack, 1) and Inv2.BoughtCosmetic(ckCloth, 2) and Inv2.BoughtCosmetic(ckMoon, 1), 'saved on disk');
    Check(not Inv2.BoughtCosmetic(ckBack, 2), 'and nothing more');
    Inv2.Reset;
    Check(not Inv2.BoughtCosmetic(ckBack, 1) and (Inv2.Coins = StartingCoins), 'a reset clears them with the coins');
    Inv2.ImportText(Text);
    Check(Inv2.BoughtCosmetic(ckCloth, 2), 'a save slot (export and import) keeps them');
    { a hand-edited file cannot give away what a trophy unlocks }
    Inv2.ImportText('[Inventory]' + LineEnding + 'Coins=5' + LineEnding + 'Style.back.midnight=1' + LineEnding + 'Style.back.blood=1' + LineEnding);
    Check(not Inv2.BoughtCosmetic(ckBack, 3) and Inv2.BoughtCosmetic(ckBack, 1), 'a trophy item is never counted as bought');
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
  F := GetTempDir + 'tiepair_test_style_set.ini';
  StoreDelete(F);
  S := TSettings.Create(F);
  try
    Check((S.BackKey = 'moon') and (S.ClothKey = 'green') and (S.MoonKey = 'pale'), 'the original look to begin with');
    S.BackKey := 'blood';
    S.MoonKey := 'harvest';
    S.Save;
  finally
    S.Free;
  end;
  S := TSettings.Create(F);
  try
    Check((S.BackKey = 'blood') and (S.ClothKey = 'green') and (S.MoonKey = 'harvest'), 'saved by key');
    S.ResetStyle;
    Check((S.BackKey = 'moon') and (S.MoonKey = 'pale'), 'ResetStyle goes back');
  finally
    S.Free;
  end;
  StoreDelete(F);
end;

procedure TestText;
var
  St: TStory;
  K: TCosmeticKind;
  I: Integer;
begin
  St := TStory.Create;
  try
    St.LoadFromFile(StoryPath);
    Check(Length(St.Validate) = 0, 'the story file has everything, the style text included');
    for K := Low(TCosmeticKind) to High(TCosmeticKind) do
      for I := 0 to CosmeticsPerKind - 1 do
      begin
        Check(St.StyleName(CosmeticStoryKey(K, I)) <> '', CosmeticStoryKey(K, I) + ' has a name');
        Check(St.StyleLine(CosmeticStoryKey(K, I)) <> '', CosmeticStoryKey(K, I) + ' has a line');
        Check(Pos('%', St.StyleLine(CosmeticStoryKey(K, I))) = 0, CosmeticStoryKey(K, I) + ' has no format marks');
      end;
  finally
    St.Free;
  end;
end;

begin
  CrossCardsOn := False;
  TestOriginalLook;
  TestTable;
  TestBuying;
  TestSettings;
  TestText;
  if Failures = 0 then WriteLn('ALL STYLE TESTS PASSED')
  else
  begin
    WriteLn(Failures, ' FAILURES');
    Halt(1);
  end;
end.
