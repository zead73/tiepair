unit Cosmetics;

{ Style: the cosmetic things Fenwick sells and the vampires' trophies unlock. No
  window code, and nothing here changes how a hand plays.

  Three kinds, four choices each. The first of every kind is the original look
  (free, and exactly the colours the game always had). The others are bought at
  a fixed list price (never discounted), or, for the last of each kind, earned
  with a trophy. Colours are plain 0xRRGGBB integers: each front end turns them
  into its own colour type. A choice is saved by its key (a word), not by its
  number, so the list can grow without breaking anyone's save. }

{$mode objfpc}{$H+}

interface

type
  TCosmeticKind = (ckBack, ckCloth, ckMoon);

const
  CosmeticKindCount = 3;
  CosmeticsPerKind = 4;
  NoTrophy = -1;
  { The price of the ones that are bought (list price: the campaign's cheaper Store
    prices do not apply). }
  BackPrice = 60;
  ClothPrice = 80;
  MoonPrice = 50;

function CosmeticKey(K: TCosmeticKind; I: Integer): string;
{ The word the story file uses for this one: 'back.blood', 'cloth.velvet', 'moon.harvest'. }
function CosmeticStoryKey(K: TCosmeticKind; I: Integer): string;
{ Coins it costs; 0 for the original look and for the ones a trophy unlocks. }
function CosmeticCost(K: TCosmeticKind; I: Integer): Integer;
{ Ord(TTrophy) of the trophy that unlocks it, or NoTrophy. }
function CosmeticTrophy(K: TCosmeticKind; I: Integer): Integer;
{ The original look: nothing to buy, nothing to earn. }
function CosmeticIsFree(K: TCosmeticKind; I: Integer): Boolean;
{ The index of a saved key (0, the original, if it is unknown). }
function CosmeticIndexOf(K: TCosmeticKind; const Key: string): Integer;
function CosmeticKindName(K: TCosmeticKind): string;

{ Card back colours. Part: 0 base, 1 dark, 2 lattice line, 3 gold, 4 inner frame. }
function BackColor(I, Part: Integer): Integer;
{ Table cloth colours. Part: 0 centre, 1 edge, 2 frame, 3 inner frame. }
function ClothColor(I, Part: Integer): Integer;
{ The moon as a small picture: Part 0 the disc, 1 the ring round it (-1 = none). The
  house pictures themselves are made by tools/make_house.py with the same colours. }
function MoonColor(I, Part: Integer): Integer;
{ The house picture to draw (the moon is part of it): 'house' or 'house_<moon>'. }
function HouseImageKey(I: Integer): string;

function ColorR(C: Integer): Integer;
function ColorG(C: Integer): Integer;
function ColorB(C: Integer): Integer;

implementation

const
  BackKeys: array[0..3] of string = ('moon', 'blood', 'bone', 'midnight');
  ClothKeys: array[0..3] of string = ('green', 'velvet', 'marble', 'mourning');
  MoonKeys: array[0..3] of string = ('pale', 'blood', 'harvest', 'eclipse');

  { Ord(TTrophy): trVampire0 = 2, trVampire1 = 3, trVampire2 = 4 }
  BackTrophy: array[0..3] of Integer = (NoTrophy, NoTrophy, NoTrophy, 2);
  ClothTrophy: array[0..3] of Integer = (NoTrophy, NoTrophy, NoTrophy, 3);
  MoonTrophy: array[0..3] of Integer = (NoTrophy, NoTrophy, NoTrophy, 4);

  BackBase: array[0..3] of Integer = ($2A0D1A, $600A1A, $36343C, $0E1838);
  BackDark: array[0..3] of Integer = ($0D0608, $1E0308, $100F14, $050816);
  BackLine: array[0..3] of Integer = ($4A1A2C, $961A2C, $5C5A64, $223668);
  BackGold: array[0..3] of Integer = ($C9A24A, $E2BA60, $DED6C2, $BEC8E6);
  BackDim: array[0..3] of Integer = ($7A2A3A, $A02C38, $7E7A72, $465C96);

  ClothCenter: array[0..3] of Integer = ($184A30, $5C1424, $2C2C34, $341E56);
  ClothEdge: array[0..3] of Integer = ($05100B, $18040A, $08080C, $0C0618);
  ClothFrame: array[0..3] of Integer = ($6E5A2E, $785C2E, $78788A, $9678AA);
  ClothFrame2: array[0..3] of Integer = ($3A301A, $3C2E1A, $3C3C46, $463854);

  MoonDisc: array[0..3] of Integer = ($F1E8CF, $CF3B33, $F4B64F, $1B1527);
  MoonRing: array[0..3] of Integer = (-1, -1, -1, $D4CDE8);

function Safe(I: Integer): Integer;
begin
  if (I < 0) or (I >= CosmeticsPerKind) then Result := 0 else Result := I;
end;

function CosmeticKey(K: TCosmeticKind; I: Integer): string;
begin
  case K of
    ckBack: Result := BackKeys[Safe(I)];
    ckCloth: Result := ClothKeys[Safe(I)];
  else
    Result := MoonKeys[Safe(I)];
  end;
end;

function CosmeticKindName(K: TCosmeticKind): string;
begin
  case K of
    ckBack: Result := 'back';
    ckCloth: Result := 'cloth';
  else
    Result := 'moon';
  end;
end;

function CosmeticStoryKey(K: TCosmeticKind; I: Integer): string;
begin
  Result := CosmeticKindName(K) + '.' + CosmeticKey(K, I);
end;

function CosmeticTrophy(K: TCosmeticKind; I: Integer): Integer;
begin
  case K of
    ckBack: Result := BackTrophy[Safe(I)];
    ckCloth: Result := ClothTrophy[Safe(I)];
  else
    Result := MoonTrophy[Safe(I)];
  end;
end;

function CosmeticCost(K: TCosmeticKind; I: Integer): Integer;
begin
  Result := 0;
  if (Safe(I) = 0) or (CosmeticTrophy(K, I) <> NoTrophy) then Exit;
  case K of
    ckBack: Result := BackPrice;
    ckCloth: Result := ClothPrice;
  else
    Result := MoonPrice;
  end;
end;

function CosmeticIsFree(K: TCosmeticKind; I: Integer): Boolean;
begin
  Result := Safe(I) = 0;
end;

function CosmeticIndexOf(K: TCosmeticKind; const Key: string): Integer;
var
  J: Integer;
begin
  Result := 0;
  for J := 0 to CosmeticsPerKind - 1 do
    if CosmeticKey(K, J) = Key then Exit(J);
end;

function BackColor(I, Part: Integer): Integer;
begin
  I := Safe(I);
  case Part of
    0: Result := BackBase[I];
    1: Result := BackDark[I];
    2: Result := BackLine[I];
    3: Result := BackGold[I];
  else
    Result := BackDim[I];
  end;
end;

function ClothColor(I, Part: Integer): Integer;
begin
  I := Safe(I);
  case Part of
    0: Result := ClothCenter[I];
    1: Result := ClothEdge[I];
    2: Result := ClothFrame[I];
  else
    Result := ClothFrame2[I];
  end;
end;

function MoonColor(I, Part: Integer): Integer;
begin
  I := Safe(I);
  if Part = 0 then Result := MoonDisc[I] else Result := MoonRing[I];
end;

function HouseImageKey(I: Integer): string;
begin
  I := Safe(I);
  if I = 0 then Result := 'house' else Result := 'house_' + MoonKeys[I];
end;

function ColorR(C: Integer): Integer;
begin
  Result := (C shr 16) and 255;
end;

function ColorG(C: Integer): Integer;
begin
  Result := (C shr 8) and 255;
end;

function ColorB(C: Integer): Integer;
begin
  Result := C and 255;
end;

end.
