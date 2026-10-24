unit Relics;

{ Relics: small permanent helps, bought from Fenwick (or earned with a trophy) and
  carried in a few slots. No window code. They exist to take the edge off the two
  hard vampires and the cost of mistakes; each is small on purpose, so nothing
  snowballs.

    Garlic Wreath      the first bitten card you play in a hand costs no coins
    Locksmith's Pick   one chained card in a hand can be played even with its
                       neighbour still on the table
    Iron Spoon         the Count feeds at most once in a hand
    Steady Locket      your first missed move in a hand costs no coins
    Moonstone          the first Show move in a hand uses no hint card

  A relic works in the hands dealt while it is equipped (before the first move,
  also the hand on the table), and a hand keeps the relics it was dealt with. The
  Locksmith's Pick and the Iron Spoon only matter against a vampire's trick, so in
  Free Play they do nothing. }

{$mode objfpc}{$H+}

interface

uses
  Trophies;

type
  TRelic = (rlGarlic, rlPick, rlSpoon, rlLocket, rlMoonstone);

const
  RelicCount = 5;
  MaxRelicSlots = 4;
  NoRelicTrophy = -1;

{ The word a relic is saved and written about under. }
function RelicKey(R: TRelic): string;
function RelicIndexOf(const Key: string): Integer;     { -1 if unknown }
{ List price in coins (never discounted). }
function RelicPrice(R: TRelic): Integer;
{ Ord(TTrophy) of the trophy that also gives it, or NoRelicTrophy. }
function RelicTrophy(R: TRelic): Integer;
{ Slots: one to begin with, one more for each vampire trophy held. }
function RelicSlots(VampireTrophies: Integer): Integer;

{ A set of relics as bits (bit I = the relic with number I). }
function RelicBit(R: TRelic): Integer;
function HasRelic(Mask: Integer; R: TRelic): Boolean;
function ValidRelicMask(Mask: Integer): Boolean;
function RelicsInMask(Mask: Integer): Integer;       { how many relics are in the set }

implementation

const
  Keys: array[TRelic] of string = ('garlic', 'pick', 'spoon', 'locket', 'moonstone');
  Prices: array[TRelic] of Integer = (80, 160, 160, 120, 100);
  { Ord(TTrophy): trPerfect = 1, trVampire1 = 3 }
  Trophies_: array[TRelic] of Integer = (NoRelicTrophy, NoRelicTrophy, NoRelicTrophy, 1, 3);

function RelicKey(R: TRelic): string;
begin
  Result := Keys[R];
end;

function RelicIndexOf(const Key: string): Integer;
var
  R: TRelic;
begin
  Result := -1;
  for R := Low(TRelic) to High(TRelic) do
    if Keys[R] = Key then Exit(Ord(R));
end;

function RelicPrice(R: TRelic): Integer;
begin
  Result := Prices[R];
end;

function RelicTrophy(R: TRelic): Integer;
begin
  Result := Trophies_[R];
end;

function RelicSlots(VampireTrophies: Integer): Integer;
begin
  if VampireTrophies < 0 then VampireTrophies := 0;
  Result := 1 + VampireTrophies;
  if Result > MaxRelicSlots then Result := MaxRelicSlots;
end;

function RelicBit(R: TRelic): Integer;
begin
  Result := 1 shl Ord(R);
end;

function HasRelic(Mask: Integer; R: TRelic): Boolean;
begin
  Result := (Mask and RelicBit(R)) <> 0;
end;

function RelicsInMask(Mask: Integer): Integer;
var
  R: TRelic;
begin
  Result := 0;
  for R := Low(TRelic) to High(TRelic) do
    if HasRelic(Mask, R) then Inc(Result);
end;

function ValidRelicMask(Mask: Integer): Boolean;
begin
  Result := (Mask >= 0) and (Mask < (1 shl RelicCount));
end;

end.
