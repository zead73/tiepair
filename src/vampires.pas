unit Vampires;

{ The fixed facts about the three vampires of the campaign. The words they say
  live in assets/story/story.ini (see Story); the numbers that affect play live
  here. Order = the order you fight them. }

{$mode objfpc}{$H+}

interface

uses
  Pyramid;

const
  VampireCount = 3;
  { Section name in the story file for each vampire. }
  VampireKey: array[0..VampireCount - 1] of string = ('jack', 'queen', 'king');
  { The court card each one wears (11 = Jack, 12 = Queen, 13 = King). }
  VampireCardRank: array[0..VampireCount - 1] of Integer = (11, 12, 13);
  { The pictures of the vampires shown in the scenes: 0..2 are the three of them,
    3..5 the same with blood on his fangs, 6..8 with a goblet of your blood (what
    he does after a lost hand). }
  PortraitCount = VampireCount * 3;
  { Won hands it takes to kill a vampire. }
  WinsToKill = 5;
  { Coins each won hand pays when you did not lose a hand first. Jack plays the
    ordinary rules, so he pays close to a Free Play win (25); each later
    vampire pays more because his hands are harder to win. }
  VampireWinCoins: array[0..VampireCount - 1] of Integer = (20, 30, 40);
  { What the killing (fifth) win adds on top; never cut by lost hands or
    missed moves. }
  VampireKillBonus: array[0..VampireCount - 1] of Integer = (30, 45, 60);
  { How hard each vampire's hands are (difficulty levels 1..3, Lucien to Alaric).
    Two things change: whether the Easy rule is on (a card that only one card
    still covers can go with that card) and how many times the stock can be
    turned over. Lucien's hands are the friendly ones: Easy, and three turn-overs.
    Carmilla plays plain Pyramid with two, Alaric with one. These are first
    numbers: tools/pair-solver.pas measures what they mean for the player.
    Each vampire's trick in the middle of a hand (see THazard in Pyramid):
    Lucien bites, Carmilla chains, Alaric starves you of cards. The special
    cards are the answers: Wood Stake or Wild card for a chained card, Wood Stake
    for a bitten one, Extra turn against his hunger. }
  VampireEasy: array[0..VampireCount - 1] of Boolean = (True, False, False);
  VampireRecycles: array[0..VampireCount - 1] of Integer = (3, 2, 1);
  VampireHazard: array[0..VampireCount - 1] of THazard = (hzBitten, hzChained, hzHunger);
  { What the Store charges while you face each vampire, as a percentage of the
    list prices: the early levels are cheaper. Free Play, and the campaign once
    it is won, pay the list price. }
  VampirePricePercent: array[0..VampireCount - 1] of Integer = (50, 60, 75);
  { How long the silver cross (the Easy-Vampire card) weakens each vampire once a
    Wild card has claimed it: -1 = until he falls, otherwise that many hands (won
    or lost). Jack never carries one. A weakened vampire plays Jack's hands:
    the Easy rule, three turn-overs and no trick. }
  VampireEaseHands: array[0..VampireCount - 1] of Integer = (0, -1, 2);
  { Hint cards each of the first four wins gives (the kill gives the full
    set: WinUndoCards and WinHintCards in Inventory). }
  HitHintCards = 1;

{ The picture of vampire V drinking: Variant 0 = blood on his fangs, 1 = the goblet. }
function BleedPortrait(V, Variant: Integer): Integer;
{ The image's name (as in assets/vampires and the embedded resources). }
function PortraitName(P: Integer): string;

{ '1 turn-over', '3 turn-overs'. }
function TurnOvers(N: Integer): string;

{ The first vampire whose hands are plain Pyramid, without the Easy rule
  (VampireCount if none). The Easy rule card is only worth buying from there on. }
function FirstNormalVampire: Integer;
{ The first vampire who allows fewer turn-overs than the first: from there on the
  Extra turn card is worth buying. }
function FirstFewerTurnsVampire: Integer;

implementation

uses
  SysUtils;

function BleedPortrait(V, Variant: Integer): Integer;
begin
  Result := V + VampireCount * (1 + (Variant and 1));
end;

function PortraitName(P: Integer): string;
begin
  Result := 'vampire_' + VampireKey[P mod VampireCount];
  case P div VampireCount of
    1: Result := Result + '_fangs';
    2: Result := Result + '_cup';
  end;
end;

function TurnOvers(N: Integer): string;
begin
  if N = 1 then Result := '1 turn-over'
  else Result := IntToStr(N) + ' turn-overs';
end;

function FirstNormalVampire: Integer;
var
  V: Integer;
begin
  Result := VampireCount;
  for V := VampireCount - 1 downto 0 do
    if not VampireEasy[V] then Result := V;
end;

function FirstFewerTurnsVampire: Integer;
var
  V: Integer;
begin
  Result := VampireCount;
  for V := VampireCount - 1 downto 0 do
    if VampireRecycles[V] < VampireRecycles[0] then Result := V;
end;

end.
