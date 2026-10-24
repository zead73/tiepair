unit Inventory;

{ The player's fake-currency wallet and item counts. No UI code in here.

  Coins and undo cards are earned or bought at fixed prices. Nothing in this
  game is random-reward or pay-to-roll; keep it that way. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, TextIni, Storage, Specials, Cosmetics, Relics;

const
  StartingCoins = 50;
  UndoPackCost = 30;      { coins }
  UndoPackSize = 3;       { undo cards per pack }
  HintPackCost = 20;      { coins }
  HintPackSize = 5;       { hint cards per pack }
  WinCoins = 25;          { placeholder reward for clearing a board }
  WinUndoCards = 1;       { placeholder reward for clearing a board }
  WinHintCards = 2;       { placeholder reward for clearing a board }
  MissPenaltyCoins = 2;   { each missed move takes this off the hand's reward }
  RewardFloorCoins = 5;   { ... but a reward is never cut below this }
  BitePenaltyCoins = 4;   { each bitten card played takes this off a duel hand's reward }
  RememberedHands = 200;  { how many paid-out hands are remembered }

type
  TPlayerInventory = class
  private
    FCoins: Integer;
    FUndoCards: Integer;
    FHintCards: Integer;
    FSpecials: array[TSpecialKind] of Integer;
    FBought: array[TCosmeticKind, 0..CosmeticsPerKind - 1] of Boolean;   { Style items bought with coins }
    FBoughtRelic: array[TRelic] of Boolean;
    FPaidHands: array of Integer;       { ids of hands whose reward was paid }
    FPricePercent: Integer;
    procedure ParseIds(const S: string);
    function IdsText: string;
  public
    constructor Create;
    procedure Reset;                                { new player defaults }
    procedure AddCoins(N: Integer);
    { What the Store charges, as a percentage of the list prices (100 = list
      price). Not saved: whoever runs the game sets it (the campaign sells
      cheaper at the earlier vampires). A discounted price is rounded up to a
      multiple of 5 coins. }
    property PricePercent: Integer read FPricePercent write FPricePercent;
    function UndoPackPrice: Integer;
    function HintPackPrice: Integer;
    function SpecialPrice(K: TSpecialKind): Integer;
    { Style (see Cosmetics): the original look is always yours; the others are bought
      at a fixed list price (never discounted), or unlocked by a trophy (the caller
      knows the trophies: this only knows what was bought). }
    function BoughtCosmetic(K: TCosmeticKind; I: Integer): Boolean;
    function CanBuyCosmetic(K: TCosmeticKind; I: Integer): Boolean;
    function BuyCosmetic(K: TCosmeticKind; I: Integer): Boolean;   { False if it cannot be bought }
    { Relics bought from Fenwick (the caller also counts the ones a trophy gives). }
    function BoughtRelic(R: TRelic): Boolean;
    function CanBuyRelic(R: TRelic): Boolean;
    function BuyRelic(R: TRelic): Boolean;
    function SpendCoins(N: Integer): Boolean;                      { False, taking nothing, if too few }
    procedure AddUndoCards(N: Integer);
    function CanBuyUndoPack: Boolean;
    function BuyUndoPack: Boolean;                  { False if too few coins }
    function UseUndoCard: Boolean;                  { False if none left }
    procedure AddHintCards(N: Integer);
    function CanBuyHintPack: Boolean;
    function BuyHintPack: Boolean;                  { False if too few coins }
    function UseHintCard: Boolean;                  { False if none left }
    { Special cards (see Specials): how many of each you own, bought one at a
      time at a fixed price. }
    function SpecialCards(K: TSpecialKind): Integer;
    function TotalSpecialCards: Integer;
    procedure AddSpecial(K: TSpecialKind; N: Integer);
    function CanBuySpecial(K: TSpecialKind): Boolean;
    function BuySpecial(K: TSpecialKind): Boolean;  { False if too few coins }
    function UseSpecialCard(K: TSpecialKind): Boolean;  { False if none left }
    { A saved hand can be loaded again, so each deal is named by an id and a
      hand pays its reward only once. }
    function HandPaid(Id: Integer): Boolean;
    procedure MarkHandPaid(Id: Integer);
    procedure LoadFromFile(const FileName: string); { missing file = defaults }
    { Everything owned, as text and back (a campaign save slot keeps it). }
    function ExportText: string;
    procedure ImportText(const Text: string);
    procedure SaveToFile(const FileName: string);
    property Coins: Integer read FCoins;
    property UndoCards: Integer read FUndoCards;
    property HintCards: Integer read FHintCards;
  end;

{ A list price at Percent of its full size: unchanged at 100 or more, otherwise
  rounded up to a multiple of 5 (never below 5). }
function DiscountedPrice(Base, Percent: Integer): Integer;

{ A hand's coin reward after Misses missed moves: Base less the penalty for
  each, never cut below the floor (and never raised above Base). }
function RewardAfterMisses(Base, Misses: Integer): Integer;
{ ... and after Bites played bitten cards as well (Lucien's trick). }
function RewardAfterCuts(Base, Misses, Bites: Integer): Integer;

{ Per-user save location (works on Linux and Windows). }
function DefaultInventoryFile: string;

implementation

constructor TPlayerInventory.Create;
begin
  inherited Create;
  FPricePercent := 100;
  Reset;
end;

function DiscountedPrice(Base, Percent: Integer): Integer;
begin
  if Percent >= 100 then Exit(Base);
  if Percent < 0 then Percent := 0;
  Result := (Base * Percent + 99) div 100;          { round up to a whole coin }
  Result := ((Result + 4) div 5) * 5;               { then up to a multiple of 5 }
  if Result < 5 then Result := 5;
end;

function TPlayerInventory.UndoPackPrice: Integer;
begin
  Result := DiscountedPrice(UndoPackCost, FPricePercent);
end;

function TPlayerInventory.HintPackPrice: Integer;
begin
  Result := DiscountedPrice(HintPackCost, FPricePercent);
end;

function TPlayerInventory.SpecialPrice(K: TSpecialKind): Integer;
begin
  Result := DiscountedPrice(Specials.SpecialPrice[K], FPricePercent);
end;

procedure TPlayerInventory.Reset;
var
  K: TSpecialKind;
  CK: TCosmeticKind;
  CI: Integer;
  RR: TRelic;
begin
  FCoins := StartingCoins;
  FUndoCards := 0;
  FHintCards := 0;
  for K := Low(TSpecialKind) to High(TSpecialKind) do FSpecials[K] := 0;
  FPaidHands := nil;
  for CK := Low(TCosmeticKind) to High(TCosmeticKind) do
    for CI := 0 to CosmeticsPerKind - 1 do FBought[CK, CI] := False;
  for RR := Low(TRelic) to High(TRelic) do FBoughtRelic[RR] := False;
end;

function TPlayerInventory.BoughtRelic(R: TRelic): Boolean;
begin
  Result := FBoughtRelic[R];
end;

function TPlayerInventory.CanBuyRelic(R: TRelic): Boolean;
begin
  Result := not FBoughtRelic[R] and (FCoins >= RelicPrice(R));
end;

function TPlayerInventory.BuyRelic(R: TRelic): Boolean;
begin
  Result := CanBuyRelic(R);
  if not Result then Exit;
  Dec(FCoins, RelicPrice(R));
  FBoughtRelic[R] := True;
end;

function TPlayerInventory.BoughtCosmetic(K: TCosmeticKind; I: Integer): Boolean;
begin
  Result := (I >= 0) and (I < CosmeticsPerKind) and FBought[K, I];
end;

function TPlayerInventory.CanBuyCosmetic(K: TCosmeticKind; I: Integer): Boolean;
begin
  Result := (I > 0) and (I < CosmeticsPerKind) and (CosmeticTrophy(K, I) = NoTrophy)
    and not FBought[K, I] and (FCoins >= CosmeticCost(K, I));
end;

function TPlayerInventory.BuyCosmetic(K: TCosmeticKind; I: Integer): Boolean;
begin
  Result := CanBuyCosmetic(K, I);
  if not Result then Exit;
  Dec(FCoins, CosmeticCost(K, I));
  FBought[K, I] := True;
end;

function TPlayerInventory.SpendCoins(N: Integer): Boolean;
begin
  Result := (N >= 0) and (FCoins >= N);
  if Result then Dec(FCoins, N);
end;

procedure TPlayerInventory.AddCoins(N: Integer);
begin
  if N > 0 then Inc(FCoins, N);
end;

procedure TPlayerInventory.AddUndoCards(N: Integer);
begin
  if N > 0 then Inc(FUndoCards, N);
end;

function TPlayerInventory.CanBuyUndoPack: Boolean;
begin
  Result := FCoins >= UndoPackPrice;
end;

function TPlayerInventory.BuyUndoPack: Boolean;
begin
  Result := CanBuyUndoPack;
  if not Result then Exit;
  Dec(FCoins, UndoPackPrice);
  Inc(FUndoCards, UndoPackSize);
end;

function TPlayerInventory.SpecialCards(K: TSpecialKind): Integer;
begin
  Result := FSpecials[K];
end;

function TPlayerInventory.TotalSpecialCards: Integer;
var
  K: TSpecialKind;
begin
  Result := 0;
  for K := Low(TSpecialKind) to High(TSpecialKind) do Inc(Result, FSpecials[K]);
end;

procedure TPlayerInventory.AddSpecial(K: TSpecialKind; N: Integer);
begin
  if N > 0 then Inc(FSpecials[K], N);
end;

function TPlayerInventory.CanBuySpecial(K: TSpecialKind): Boolean;
begin
  Result := FCoins >= SpecialPrice(K);
end;

function TPlayerInventory.BuySpecial(K: TSpecialKind): Boolean;
begin
  Result := CanBuySpecial(K);
  if not Result then Exit;
  Dec(FCoins, SpecialPrice(K));
  Inc(FSpecials[K]);
end;

function TPlayerInventory.UseSpecialCard(K: TSpecialKind): Boolean;
begin
  Result := FSpecials[K] > 0;
  if Result then Dec(FSpecials[K]);
end;

procedure TPlayerInventory.ParseIds(const S: string);
var
  P, Start, V: Integer;
  Part: string;
begin
  FPaidHands := nil;
  Start := 1;
  for P := 1 to Length(S) + 1 do
    if (P > Length(S)) or (S[P] = ',') then
    begin
      Part := Trim(Copy(S, Start, P - Start));
      Start := P + 1;
      if TryStrToInt(Part, V) and (V > 0) and not HandPaid(V) then
        MarkHandPaid(V);                      { also enforces the size limit }
    end;
end;

function TPlayerInventory.IdsText: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(FPaidHands) do
  begin
    if Result <> '' then Result := Result + ',';
    Result := Result + IntToStr(FPaidHands[I]);
  end;
end;

function TPlayerInventory.HandPaid(Id: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(FPaidHands) do
    if FPaidHands[I] = Id then Exit(True);
end;

procedure TPlayerInventory.MarkHandPaid(Id: Integer);
var
  I: Integer;
begin
  if HandPaid(Id) then Exit;
  if Length(FPaidHands) >= RememberedHands then      { forget the oldest }
  begin
    for I := 1 to High(FPaidHands) do FPaidHands[I - 1] := FPaidHands[I];
    SetLength(FPaidHands, Length(FPaidHands) - 1);
  end;
  SetLength(FPaidHands, Length(FPaidHands) + 1);
  FPaidHands[High(FPaidHands)] := Id;
end;

procedure TPlayerInventory.AddHintCards(N: Integer);
begin
  if N > 0 then Inc(FHintCards, N);
end;

function TPlayerInventory.CanBuyHintPack: Boolean;
begin
  Result := FCoins >= HintPackPrice;
end;

function TPlayerInventory.BuyHintPack: Boolean;
begin
  Result := CanBuyHintPack;
  if not Result then Exit;
  Dec(FCoins, HintPackPrice);
  Inc(FHintCards, HintPackSize);
end;

function TPlayerInventory.UseHintCard: Boolean;
begin
  Result := FHintCards > 0;
  if Result then Dec(FHintCards);
end;

function TPlayerInventory.UseUndoCard: Boolean;
begin
  Result := FUndoCards > 0;
  if Result then Dec(FUndoCards);
end;

procedure TPlayerInventory.LoadFromFile(const FileName: string);
var
  Text: string;
begin
  Reset;
  if StoreRead(FileName, Text) then ImportText(Text);
end;

procedure TPlayerInventory.ImportText(const Text: string);
var
  Ini: TTextIni;
  K: TSpecialKind;
  CK: TCosmeticKind;
  CI: Integer;
  RR: TRelic;
begin
  Reset;
  Ini := TTextIni.Create;
  try
    Ini.LoadFromText(Text);
    FCoins := Ini.ReadInteger('Inventory', 'Coins', StartingCoins);
    FUndoCards := Ini.ReadInteger('Inventory', 'UndoCards', 0);
    FHintCards := Ini.ReadInteger('Inventory', 'HintCards', 0);
    ParseIds(Ini.ReadString('Inventory', 'PaidHands', ''));
    if FHintCards < 0 then FHintCards := 0;
    if FCoins < 0 then FCoins := 0;          { guard against a damaged file }
    if FUndoCards < 0 then FUndoCards := 0;
    for K := Low(TSpecialKind) to High(TSpecialKind) do
    begin
      FSpecials[K] := Ini.ReadInteger('Inventory', 'Special.' + SpecialKey[K], 0);
      if FSpecials[K] < 0 then FSpecials[K] := 0;
    end;
    for CK := Low(TCosmeticKind) to High(TCosmeticKind) do
      for CI := 1 to CosmeticsPerKind - 1 do
        FBought[CK, CI] := Ini.ReadBool('Inventory', 'Style.' + CosmeticStoryKey(CK, CI), False)
          and (CosmeticTrophy(CK, CI) = NoTrophy);
    for RR := Low(TRelic) to High(TRelic) do
      FBoughtRelic[RR] := Ini.ReadBool('Inventory', 'Relic.' + RelicKey(RR), False);
  finally
    Ini.Free;
  end;
end;

function TPlayerInventory.ExportText: string;
var
  Ini: TTextIni;
  K: TSpecialKind;
  CK: TCosmeticKind;
  CI: Integer;
  RR: TRelic;
begin
  Ini := TTextIni.Create;
  try
    Ini.WriteInteger('Inventory', 'Coins', FCoins);
    Ini.WriteInteger('Inventory', 'UndoCards', FUndoCards);
    Ini.WriteInteger('Inventory', 'HintCards', FHintCards);
    Ini.WriteString('Inventory', 'PaidHands', IdsText);
    for K := Low(TSpecialKind) to High(TSpecialKind) do
      Ini.WriteInteger('Inventory', 'Special.' + SpecialKey[K], FSpecials[K]);
    for CK := Low(TCosmeticKind) to High(TCosmeticKind) do
      for CI := 1 to CosmeticsPerKind - 1 do
        Ini.WriteBool('Inventory', 'Style.' + CosmeticStoryKey(CK, CI), FBought[CK, CI]);
    for RR := Low(TRelic) to High(TRelic) do
      Ini.WriteBool('Inventory', 'Relic.' + RelicKey(RR), FBoughtRelic[RR]);
    Result := Ini.ToText;
  finally
    Ini.Free;
  end;
end;

procedure TPlayerInventory.SaveToFile(const FileName: string);
var
  Ini: TTextIni;
  Text: string;
  K: TSpecialKind;
  CK: TCosmeticKind;
  CI: Integer;
  RR: TRelic;
begin
  Ini := TTextIni.Create;
  try
    if StoreRead(FileName, Text) then Ini.LoadFromText(Text);   { keep entries we do not know }
    Ini.WriteInteger('Inventory', 'Coins', FCoins);
    Ini.WriteInteger('Inventory', 'UndoCards', FUndoCards);
    Ini.WriteInteger('Inventory', 'HintCards', FHintCards);
    Ini.WriteString('Inventory', 'PaidHands', IdsText);
    for K := Low(TSpecialKind) to High(TSpecialKind) do
      Ini.WriteInteger('Inventory', 'Special.' + SpecialKey[K], FSpecials[K]);
    for CK := Low(TCosmeticKind) to High(TCosmeticKind) do
      for CI := 1 to CosmeticsPerKind - 1 do
        Ini.WriteBool('Inventory', 'Style.' + CosmeticStoryKey(CK, CI), FBought[CK, CI]);
    for RR := Low(TRelic) to High(TRelic) do
      Ini.WriteBool('Inventory', 'Relic.' + RelicKey(RR), FBoughtRelic[RR]);
    StoreWrite(FileName, Ini.ToText);
  finally
    Ini.Free;
  end;
end;

function RewardAfterCuts(Base, Misses, Bites: Integer): Integer;
var
  Floor: Integer;
begin
  if Misses < 0 then Misses := 0;
  if Bites < 0 then Bites := 0;
  Result := Base - MissPenaltyCoins * Misses - BitePenaltyCoins * Bites;
  Floor := RewardFloorCoins;
  if Floor > Base then Floor := Base;      { a reward already below the floor stays }
  if Result < Floor then Result := Floor;
end;

function RewardAfterMisses(Base, Misses: Integer): Integer;
begin
  Result := RewardAfterCuts(Base, Misses, 0);
end;

function DefaultInventoryFile: string;
begin
  Result := StoreName('inventory.ini');
end;

end.
