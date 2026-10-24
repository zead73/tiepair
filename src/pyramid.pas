unit Pyramid;

{ The rules of Pyramid solitaire, as played in Tiepair. No window code, so
  everything here can be tested without a screen.

  Twenty-eight cards are dealt face up in a pyramid of seven rows, and the other
  twenty-four make the stock. A pyramid card is FREE when both cards that cover it
  are gone (the bottom row is always free). The cards you can use are the free
  pyramid cards and the top card of the waste. Take away

    - a King, on its own, or
    - two cards whose ranks add up to 13 (Ace 1 ... Queen 12): A+Q, 2+J, 3+10,
      4+9, 5+8, 6+7.

  Turn the top card of the stock onto the waste to bring a new card into play.
  When the stock is empty the waste can be turned over to make a new stock, as
  often as MaxRecycles allows. Take away all 28 pyramid cards and you win.

  In EASY mode (UnderPairs) a card that is covered by exactly ONE card, when that card
  is free, is "under" it, and the two can be taken away together if they add up to 13
  (a Queen sitting on an Ace, say). In NORMAL mode (the default) a card has to be
  uncovered first, which is how Pyramid is usually played. The mode belongs to a hand.

  What a vampire does to a hand (the campaign only; Free Play has none):
    bitten   a few cards are marked; taking one costs coins and ends your streak
             (a pair with two bitten cards costs two bites)
    chained  a few cards are chained; a chained card cannot be taken while a card
             beside it in its row is still on the table (not even together with that
             neighbour)
    hunger   after every FeedEvery-th draw the bottom card of the stock is eaten
  Relics change these live, in the middle of a hand: the Locksmith's Pick lets one
  chained card go once a hand (BreakUsed), and the Iron Spoon limits his hunger to the
  first feeding (FeedOnce).

  Choices that other books make differently are named here, so they are easy to
  see and change:
    - only the TOP of the waste is in play, never the cards under it;
    - the stock's top card is face down and is not in play until it is drawn;
    - a pair is two different cards: a card is never paired with itself, and
      the waste top can be paired with a free pyramid card (not with an "under" one);
    - a King is only taken on its own when it is free;
    - turning the waste over keeps the cards in their old order, so a hand that
      is played through again comes out in the same order;
    - draws after a turn-over count towards the vampire's hunger;
    - a miss is a draw while some removal was possible (a turn-over is never a miss). }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Cards;

const
  RowCount = 7;
  PyramidSize = 28;            { 1 + 2 + ... + 7 }
  StockStart = 24;             { 52 - 28 }
  PairTotal = 13;              { two cards adding up to this go together }
  KingRank = 13;               { goes on its own }
  DefaultRecycles = 2;         { the stock can be turned over this many times: three trips through it }
  PosWaste = -1;               { "the top of the waste" in a move }
  PosNone = -2;                { "no second card": a King on its own }

  BittenCount = 3;             { marked cards per hand }
  ChainedCount = 3;
  FeedEvery = 4;               { the hungry vampire eats after every 4th draw }
  MarkNone = 0;
  MarkBitten = 1;
  MarkChained = 2;
  MarkCross = 3;               { the silver cross (see Campaign): only a Wild card can claim it }

type
  THazard = (hzNone, hzBitten, hzChained, hzHunger);

  TRemovedArray = array[0..PyramidSize - 1] of Boolean;
  TTableauArray = array[0..PyramidSize - 1] of TCard;
  TMarkArray = array[0..PyramidSize - 1] of Integer;

  TMoveKind = (mkDraw, mkRecycle, mkRemove);

  { One move that undo can take back. For a removal, A and B are pyramid
    positions (0..27), PosWaste or PosNone; WasteCard is the card that was taken
    from the top of the waste, if one was. }
  TPairMove = record
    Kind: TMoveKind;
    A, B: Integer;
    WasteCard: TCard;
    Missed: Boolean;             { a draw made while a removal was possible }
    Bites: Integer;              { bitten cards taken in this removal (0..2) }
    Ate: Boolean;                { a draw after which the vampire ate a stock card }
    Broke: Boolean;              { a removal of a chained card that the Locksmith's Pick let through }
    PrevStreak: Integer;
  end;
  TMoveArray = array of TPairMove;

  { Everything needed to put a hand back exactly as it was, with the moves undo can
    still take back (since the deal, or since the last special card, which forgets
    them). The relics are not part of a hand: they are the player's, equipped now. }
  TPairHand = record
    HandId: Integer;
    MaxRecycles: Integer;
    Recycled: Integer;
    UnderPairs: Boolean;         { the hand is being played in Easy mode }
    Hazard: Integer;             { Ord(THazard) }
    Revealed: Boolean;           { Seer's eye: the top three stock cards are shown }
    Stakes: Integer;             { free cards destroyed with a Wood Stake }
    Draws: Integer;              { cards drawn from the stock so far (the vampire's hunger counts them) }
    Streak, BestStreak: Integer;
    WasteGone: Integer;          { cards taken off the top of the waste so far }
    BreakUsed: Boolean;          { the Pick's one break has been spent }
    Tableau: TTableauArray;
    Removed: TRemovedArray;
    Marks: TMarkArray;
    Stock: TCardArray;           { the top of the stock is the last card }
    Waste: TCardArray;           { the top of the waste is the last card }
    Eaten: TCardArray;           { what the vampire has eaten, the latest last }
    History: TMoveArray;         { oldest first }
  end;

  TPyramidGame = class
  private
    FTableau: TTableauArray;
    FRemoved: TRemovedArray;
    FMarks: TMarkArray;
    FStock, FWaste, FEaten: TCardArray;
    FRecycled, FMaxRecycles, FHandId: Integer;
    FUnderPairs: Boolean;
    FHazard: THazard;
    FRevealed: Boolean;
    FStakes, FDraws, FStreak, FBestStreak, FWasteGone: Integer;
    FBreakUsed: Boolean;
    FFeedOnce, FPickOn: Boolean;
    FHistory: TMoveArray;
    function UndoMove(const M: TPairMove): Boolean;
    function RemovedOk(const R: TRemovedArray): Boolean;
    function CardFor(APos: Integer; out C: TCard): Boolean;
    function CoversWithin(X, Y: Integer): Boolean;
    function LockCount(A, B: Integer): Integer;
    function BitesOf(A, B: Integer): Integer;
    procedure Push(const M: TPairMove);
    procedure ForgetUndo;
    procedure EatCard;
    procedure UneatCard;
  public
    constructor Create;
    { Lay out a hand: the first 28 cards of the deck are the pyramid, the next 24 the stock. }
    procedure Deal(ADeck: TDeck);
    procedure NewShuffled;

    { The pyramid }
    function CardAt(I: Integer): TCard;
    function Removed(I: Integer): Boolean;
    function IsFree(I: Integer): Boolean;            { on the table and nothing covers it }
    function CoverCount(I: Integer): Integer;        { how many cards still cover it (0..2) }
    function SoleCover(I: Integer): Integer;         { the one card covering it, or -1 }
    function IsUnder(I: Integer): Boolean;           { covered by just one card, and that one is free (see UnderPairs) }
    function CardsLeft: Integer;                     { pyramid cards still on the table }

    { Which cards are in play, and what can be done with them }
    function WasteTop(out C: TCard): Boolean;
    function StockCount: Integer;
    function WasteCount: Integer;
    function InPlay(APos: Integer): Boolean;         { a free pyramid card, or the waste top (PosWaste) }
    function CanSelect(APos: Integer): Boolean;      { InPlay and not locked, or an "under" card }
    function CardIn(APos: Integer): TCard;           { the card there }
    { A removal: B = PosNone for a King on its own, else a second card. }
    function CanRemove(A, B: Integer): Boolean;
    function Remove(A, B: Integer): Boolean;
    function FindRemoval(Skip: Integer; out A, B: Integer): Boolean;   { the Skip-th possible removal }
    function RemovalCount: Integer;
    function HasRemoval: Boolean;
    function CanDraw: Boolean;
    function Draw: Boolean;
    function CanRecycle: Boolean;                    { stock empty, waste not, a turn-over left }
    function Recycle: Boolean;
    function HasMoves: Boolean;                      { a removal, a draw or a turn-over }
    function IsWon: Boolean;
    function IsStuck: Boolean;                       { not won and nothing can be done }

    function CanUndo: Boolean;
    function Undo: Boolean;
    function LastMove(out M: TPairMove): Boolean;
    function LastMoveMissed: Boolean;
    function LastMoveBites: Integer;
    function LastMoveAte: Boolean;

    { ---- a vampire's trick. SetHazard chooses where the marks go for the hand just dealt. ---- }
    procedure SetHazard(AKind: THazard);
    procedure SetMark(I, Kind: Integer);          { by hand, for tests }
    function Mark(I: Integer): Integer;
    function HasMark(Kind: Integer): Boolean;     { a card of this mark is still on the table }
    { Lay the silver cross on a random pyramid card that has no mark yet. Returns its index, or -1. }
    function PlaceCross: Integer;
    function IsLocked(I: Integer): Boolean;       { chained, with a neighbour on the table, and no break left to spend }
    function IsLockedStrict(I: Integer): Boolean; { chained, with a neighbour on the table (the plain rule) }
    function NeighborLeft(I: Integer): Integer;   { the card beside it in its row, or -1 }
    function NeighborRight(I: Integer): Integer;
    { The relics that change the rules, as equipped right now (they may change in the
      middle of a hand). }
    procedure SetRelicRules(AFeedOnce, APick: Boolean);
    property FeedsOnce: Boolean read FFeedOnce;
    property PickOn: Boolean read FPickOn;
    property BreakUsed: Boolean read FBreakUsed;
    function BreakAvailable: Boolean;             { the Pick is equipped and the hand's break is still unspent }
    property Hazard: THazard read FHazard;

    { ---- special cards (see Specials). Each changes this hand only, and none can be
      taken back with undo (using one forgets the undo). Each Can... says whether it
      would do anything now. ---- }
    function CanStake(I: Integer): Boolean;
    function Stake(I: Integer): Boolean;          { destroy a free card: nothing else changes }
    function CanWild(A, B: Integer): Boolean;
    function Wild(A, B: Integer): Boolean;        { take away two cards in play as a pair, whatever their ranks }
    function CanExtraTurn: Boolean;
    function ExtraTurn: Boolean;                  { the stock can be turned over once more }
    function CanEasyRule: Boolean;
    function EasyRule: Boolean;                   { the card-under-a-card rule, for the rest of the hand }
    function CanReveal: Boolean;
    function Reveal: Boolean;                     { show the top three stock cards }
    function HasFreeCard: Boolean;
    function InPlayCount: Integer;                { free pyramid cards plus the waste top }
    { The stock card n places down from the top (0 = the next to be drawn). }
    function StockCard(N: Integer): TCard;

    property MaxRecycles: Integer read FMaxRecycles write FMaxRecycles;
    property Recycled: Integer read FRecycled;
    function RecyclesLeft: Integer;
    { May a card be taken away together with the one card still covering it (Easy
      mode)? Set it before dealing: a saved hand carries its own. }
    property UnderPairs: Boolean read FUnderPairs write FUnderPairs;
    property HandId: Integer read FHandId;
    property Streak: Integer read FStreak;
    property BestStreak: Integer read FBestStreak;
    property Revealed: Boolean read FRevealed;
    property Stakes: Integer read FStakes;
    property Draws: Integer read FDraws;

    procedure GetState(out D: TPairHand);
    { False (and nothing changed) unless the hand is a believable one: the cards are
      all different and add up, and undoing every move in its history, one at a time,
      never breaks a rule. }
    function SetState(const D: TPairHand): Boolean;
  end;

function RowOf(I: Integer): Integer;                 { 0..6 }
function ColOf(I: Integer): Integer;                 { 0..Row }
function IndexOf(ARow, ACol: Integer): Integer;
{ The two pyramid cards that sit on top of card I (-1 = none: the bottom row). }
function CoverLeft(I: Integer): Integer;
function CoverRight(I: Integer): Integer;
function MakesPair(RankA, RankB: Integer): Boolean;  { they add up to 13 }

implementation

function RowOf(I: Integer): Integer;
var
  R: Integer;
begin
  R := 0;
  while (R + 1) * (R + 2) div 2 <= I do Inc(R);
  Result := R;
end;

function IndexOf(ARow, ACol: Integer): Integer;
begin
  Result := ARow * (ARow + 1) div 2 + ACol;
end;

function ColOf(I: Integer): Integer;
begin
  Result := I - IndexOf(RowOf(I), 0);
end;

function CoverLeft(I: Integer): Integer;
begin
  if RowOf(I) >= RowCount - 1 then Result := -1
  else Result := IndexOf(RowOf(I) + 1, ColOf(I));
end;

function CoverRight(I: Integer): Integer;
begin
  if RowOf(I) >= RowCount - 1 then Result := -1
  else Result := IndexOf(RowOf(I) + 1, ColOf(I) + 1);
end;

function MakesPair(RankA, RankB: Integer): Boolean;
begin
  Result := RankA + RankB = PairTotal;
end;

constructor TPyramidGame.Create;
begin
  inherited Create;
  FMaxRecycles := DefaultRecycles;
  FUnderPairs := False;
  FHazard := hzNone;
end;

procedure TPyramidGame.Deal(ADeck: TDeck);
var
  I: Integer;
begin
  for I := 0 to PyramidSize - 1 do
  begin
    FTableau[I] := ADeck.Draw;
    FTableau[I].FaceUp := True;
    FRemoved[I] := False;
    FMarks[I] := MarkNone;
  end;
  SetLength(FStock, 0);
  SetLength(FStock, StockStart);
  for I := 0 to StockStart - 1 do
  begin
    FStock[I] := ADeck.Draw;
    FStock[I].FaceUp := False;
  end;
  SetLength(FWaste, 0);
  SetLength(FEaten, 0);
  SetLength(FHistory, 0);
  FRecycled := 0;
  FHazard := hzNone;
  FRevealed := False;
  FStakes := 0;
  FDraws := 0;
  FStreak := 0;
  FBestStreak := 0;
  FWasteGone := 0;
  FBreakUsed := False;                  { the equipped relics (FFeedOnce, FPickOn) are the player's, not the deal's }
  FHandId := 1 + Random(MaxInt - 1);
end;

procedure TPyramidGame.NewShuffled;
var
  D: TDeck;
begin
  D := TDeck.Create;
  try
    D.Shuffle;
    Deal(D);
  finally
    D.Free;
  end;
end;

procedure TPyramidGame.Push(const M: TPairMove);
var
  N: Integer;
begin
  N := Length(FHistory);
  SetLength(FHistory, N + 1);
  FHistory[N] := M;
end;

procedure TPyramidGame.ForgetUndo;
begin
  SetLength(FHistory, 0);
end;

{ ---- the pyramid ---- }

function TPyramidGame.CardAt(I: Integer): TCard;
begin
  Result := FTableau[I];
end;

function TPyramidGame.Removed(I: Integer): Boolean;
begin
  Result := (I < 0) or (I >= PyramidSize) or FRemoved[I];
end;

function TPyramidGame.IsFree(I: Integer): Boolean;
var
  L, R: Integer;
begin
  Result := False;
  if (I < 0) or (I >= PyramidSize) or FRemoved[I] then Exit;
  L := CoverLeft(I);
  R := CoverRight(I);
  Result := ((L < 0) or FRemoved[L]) and ((R < 0) or FRemoved[R]);
end;

function TPyramidGame.CoverCount(I: Integer): Integer;
var
  L, R: Integer;
begin
  Result := 0;
  if (I < 0) or (I >= PyramidSize) or FRemoved[I] then Exit;
  L := CoverLeft(I);
  R := CoverRight(I);
  if (L >= 0) and not FRemoved[L] then Inc(Result);
  if (R >= 0) and not FRemoved[R] then Inc(Result);
end;

function TPyramidGame.SoleCover(I: Integer): Integer;
var
  L, R: Integer;
begin
  Result := -1;
  if CoverCount(I) <> 1 then Exit;
  L := CoverLeft(I);
  R := CoverRight(I);
  if (L >= 0) and not FRemoved[L] then Result := L else Result := R;
end;

function TPyramidGame.IsUnder(I: Integer): Boolean;
begin
  Result := FUnderPairs and (CoverCount(I) = 1) and IsFree(SoleCover(I));
end;

{ All the cards still covering X are Y (Y may be a waste or "nothing" position: then none). }
function TPyramidGame.CoversWithin(X, Y: Integer): Boolean;
var
  L, R: Integer;
begin
  L := CoverLeft(X);
  R := CoverRight(X);
  Result := ((L < 0) or FRemoved[L] or (L = Y)) and ((R < 0) or FRemoved[R] or (R = Y));
end;

function TPyramidGame.CardsLeft: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to PyramidSize - 1 do
    if not FRemoved[I] then Inc(Result);
end;

{ ---- marks, locks and the silver cross ---- }

function TPyramidGame.NeighborLeft(I: Integer): Integer;
begin
  if (I < 0) or (I >= PyramidSize) or (ColOf(I) = 0) then Result := -1 else Result := I - 1;
end;

function TPyramidGame.NeighborRight(I: Integer): Integer;
begin
  if (I < 0) or (I >= PyramidSize) or (ColOf(I) = RowOf(I)) then Result := -1 else Result := I + 1;
end;

function TPyramidGame.Mark(I: Integer): Integer;
begin
  if (I < 0) or (I >= PyramidSize) then Result := MarkNone else Result := FMarks[I];
end;

procedure TPyramidGame.SetMark(I, Kind: Integer);
begin
  if (I >= 0) and (I < PyramidSize) then FMarks[I] := Kind;
end;

function TPyramidGame.HasMark(Kind: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to PyramidSize - 1 do
    if (FMarks[I] = Kind) and not FRemoved[I] then Exit(True);
end;

function TPyramidGame.PlaceCross: Integer;
var
  I, N: Integer;
begin
  Result := -1;
  N := 0;
  for I := 0 to PyramidSize - 1 do
    if (FMarks[I] = MarkNone) and not FRemoved[I] then Inc(N);
  if N = 0 then Exit;
  N := Random(N);
  for I := 0 to PyramidSize - 1 do
    if (FMarks[I] = MarkNone) and not FRemoved[I] then
    begin
      if N = 0 then
      begin
        FMarks[I] := MarkCross;
        Exit(I);
      end;
      Dec(N);
    end;
end;

procedure TPyramidGame.SetHazard(AKind: THazard);
var
  I, K, N, Tries: Integer;
  Ok: Boolean;
begin
  FHazard := AKind;
  for I := 0 to PyramidSize - 1 do FMarks[I] := MarkNone;
  case AKind of
    hzBitten:
      begin
        N := 0;
        while N < BittenCount do
        begin
          K := Random(PyramidSize);
          if FMarks[K] = MarkNone then
          begin
            FMarks[K] := MarkBitten;
            Inc(N);
          end;
        end;
      end;
    hzChained:
      begin
        { never in the top row (nothing beside it), and never two beside each other
          (they would lock each other for ever) }
        N := 0;
        Tries := 0;
        while (N < ChainedCount) and (Tries < 1000) do
        begin
          Inc(Tries);
          K := 1 + Random(PyramidSize - 1);
          if FMarks[K] <> MarkNone then Continue;
          Ok := True;
          if (NeighborLeft(K) >= 0) and (FMarks[NeighborLeft(K)] = MarkChained) then Ok := False;
          if (NeighborRight(K) >= 0) and (FMarks[NeighborRight(K)] = MarkChained) then Ok := False;
          if Ok then
          begin
            FMarks[K] := MarkChained;
            Inc(N);
          end;
        end;
      end;
  end;
end;

function TPyramidGame.IsLockedStrict(I: Integer): Boolean;
var
  L, R: Integer;
begin
  Result := False;
  if (I < 0) or (I >= PyramidSize) or (FMarks[I] <> MarkChained) or FRemoved[I] then Exit;
  L := NeighborLeft(I);
  R := NeighborRight(I);
  Result := ((L >= 0) and not FRemoved[L]) or ((R >= 0) and not FRemoved[R]);
end;

procedure TPyramidGame.SetRelicRules(AFeedOnce, APick: Boolean);
begin
  FFeedOnce := AFeedOnce;
  FPickOn := APick;
end;

function TPyramidGame.BreakAvailable: Boolean;
begin
  Result := FPickOn and not FBreakUsed;
end;

function TPyramidGame.IsLocked(I: Integer): Boolean;
begin
  Result := not BreakAvailable and IsLockedStrict(I);
end;

{ How many of the two cards are chained down (pyramid positions only). }
function TPyramidGame.LockCount(A, B: Integer): Integer;
begin
  Result := 0;
  if IsLockedStrict(A) then Inc(Result);
  if IsLockedStrict(B) then Inc(Result);
end;

function TPyramidGame.BitesOf(A, B: Integer): Integer;
begin
  Result := 0;
  if (A >= 0) and (A < PyramidSize) and (FMarks[A] = MarkBitten) then Inc(Result);
  if (B >= 0) and (B < PyramidSize) and (FMarks[B] = MarkBitten) then Inc(Result);
end;

{ ---- the cards in play ---- }

function TPyramidGame.WasteTop(out C: TCard): Boolean;
begin
  Result := Length(FWaste) > 0;
  if Result then C := FWaste[High(FWaste)];
end;

function TPyramidGame.StockCount: Integer;
begin
  Result := Length(FStock);
end;

function TPyramidGame.WasteCount: Integer;
begin
  Result := Length(FWaste);
end;

function TPyramidGame.StockCard(N: Integer): TCard;
begin
  if (N >= 0) and (N < Length(FStock)) then Result := FStock[High(FStock) - N] else Result := FTableau[0];
end;

function TPyramidGame.CardFor(APos: Integer; out C: TCard): Boolean;
begin
  Result := False;
  if APos = PosWaste then
    Result := WasteTop(C)
  else if IsFree(APos) then
  begin
    C := FTableau[APos];
    Result := True;
  end;
end;

function TPyramidGame.InPlay(APos: Integer): Boolean;
var
  C: TCard;
begin
  Result := CardFor(APos, C);
end;

function TPyramidGame.CardIn(APos: Integer): TCard;
begin
  if APos = PosWaste then
  begin
    if not WasteTop(Result) then Result := FTableau[0];
  end
  else if (APos >= 0) and (APos < PyramidSize) then
    Result := FTableau[APos]
  else
    Result := FTableau[0];
end;

function TPyramidGame.CanSelect(APos: Integer): Boolean;
begin
  Result := InPlay(APos) or ((APos >= 0) and IsUnder(APos));
  if Result and (APos >= 0) and IsLocked(APos) then Result := False;     { a chained card waits }
end;

function TPyramidGame.CanRemove(A, B: Integer): Boolean;
var
  CA, CB: TCard;
  Locks: Integer;
begin
  Result := False;
  if B = PosNone then
    Result := CardFor(A, CA) and (CA.Rank = KingRank)
  else if A = B then
    Exit
  else if CardFor(A, CA) and CardFor(B, CB) then
    Result := MakesPair(CA.Rank, CB.Rank)
  else if FUnderPairs and (A >= 0) and (B >= 0) and (A < PyramidSize) and (B < PyramidSize)
    and not FRemoved[A] and not FRemoved[B] then
    { a card and the one card that covers it }
    Result := MakesPair(FTableau[A].Rank, FTableau[B].Rank)
      and ((IsUnder(A) and (SoleCover(A) = B)) or (IsUnder(B) and (SoleCover(B) = A)));
  if not Result then Exit;
  { a chained card needs the Pick (one chained card a hand) }
  Locks := LockCount(A, B);
  Result := (Locks = 0) or ((Locks = 1) and BreakAvailable);
end;

function TPyramidGame.Remove(A, B: Integer): Boolean;
var
  M: TPairMove;
  C: TCard;
begin
  Result := CanRemove(A, B);
  if not Result then Exit;
  M.Kind := mkRemove;
  M.A := A;
  M.B := B;
  M.WasteCard := FTableau[0];
  M.Missed := False;
  M.Ate := False;
  M.PrevStreak := FStreak;
  M.Bites := BitesOf(A, B);
  M.Broke := LockCount(A, B) = 1;
  if (A = PosWaste) or (B = PosWaste) then
  begin
    WasteTop(C);
    M.WasteCard := C;
    SetLength(FWaste, Length(FWaste) - 1);
    Inc(FWasteGone);
  end;
  if A >= 0 then FRemoved[A] := True;
  if B >= 0 then FRemoved[B] := True;
  if M.Broke then FBreakUsed := True;
  if M.Bites > 0 then
    FStreak := 0                          { a bite ends the streak }
  else
  begin
    Inc(FStreak);
    if FStreak > FBestStreak then FBestStreak := FStreak;
  end;
  Push(M);
end;

{ The Skip-th removal that is possible now (0 = the first), in a fixed order: the
  pyramid cards from the top down, then the waste top. }
function TPyramidGame.FindRemoval(Skip: Integer; out A, B: Integer): Boolean;
var
  Spots: array[0..PyramidSize] of Integer;
  N, I, J: Integer;
begin
  Result := False;
  A := PosNone;
  B := PosNone;
  N := 0;
  for I := 0 to PyramidSize - 1 do
    if not FRemoved[I] and (IsFree(I) or IsUnder(I)) then
    begin
      Spots[N] := I;
      Inc(N);
    end;
  if Length(FWaste) > 0 then
  begin
    Spots[N] := PosWaste;
    Inc(N);
  end;
  for I := 0 to N - 1 do
  begin
    if CanRemove(Spots[I], PosNone) then
    begin
      if Skip = 0 then
      begin
        A := Spots[I];
        B := PosNone;
        Exit(True);
      end;
      Dec(Skip);
    end;
    for J := I + 1 to N - 1 do
      if CanRemove(Spots[I], Spots[J]) then
      begin
        if Skip = 0 then
        begin
          A := Spots[I];
          B := Spots[J];
          Exit(True);
        end;
        Dec(Skip);
      end;
  end;
end;

function TPyramidGame.RemovalCount: Integer;
var
  A, B: Integer;
begin
  Result := 0;
  while FindRemoval(Result, A, B) do Inc(Result);
end;

function TPyramidGame.HasRemoval: Boolean;
var
  A, B: Integer;
begin
  Result := FindRemoval(0, A, B);
end;

{ ---- the stock ---- }

function TPyramidGame.CanDraw: Boolean;
begin
  Result := Length(FStock) > 0;
end;

{ The vampire eats the bottom card of the stock. }
procedure TPyramidGame.EatCard;
var
  I: Integer;
begin
  SetLength(FEaten, Length(FEaten) + 1);
  FEaten[High(FEaten)] := FStock[0];
  for I := 1 to High(FStock) do FStock[I - 1] := FStock[I];
  SetLength(FStock, Length(FStock) - 1);
end;

{ ... and an undone feast puts it back under the stock. }
procedure TPyramidGame.UneatCard;
var
  I: Integer;
begin
  SetLength(FStock, Length(FStock) + 1);
  for I := High(FStock) downto 1 do FStock[I] := FStock[I - 1];
  FStock[0] := FEaten[High(FEaten)];
  SetLength(FEaten, Length(FEaten) - 1);
end;

function TPyramidGame.Draw: Boolean;
var
  M: TPairMove;
  N: Integer;
begin
  Result := CanDraw;
  if not Result then Exit;
  M.Kind := mkDraw;
  M.A := PosNone;
  M.B := PosNone;
  M.WasteCard := FTableau[0];
  M.Missed := HasRemoval;                 { a miss if something could have been taken away }
  M.Bites := 0;
  M.Ate := False;
  M.Broke := False;
  M.PrevStreak := FStreak;
  N := Length(FWaste);
  SetLength(FWaste, N + 1);
  FWaste[N] := FStock[High(FStock)];
  FWaste[N].FaceUp := True;
  SetLength(FStock, Length(FStock) - 1);
  Inc(FDraws);
  FStreak := 0;
  { hunger: after every FeedEvery-th draw he eats the bottom card of the stock }
  if (FHazard = hzHunger) and (Length(FStock) > 0) and (FDraws mod FeedEvery = 0)
    and not (FFeedOnce and (FDraws > FeedEvery)) then      { the Spoon: only the first feeding }
  begin
    EatCard;
    M.Ate := True;
  end;
  Push(M);
end;

function TPyramidGame.RecyclesLeft: Integer;
begin
  Result := FMaxRecycles - FRecycled;
  if Result < 0 then Result := 0;
end;

function TPyramidGame.CanRecycle: Boolean;
begin
  Result := (Length(FStock) = 0) and (Length(FWaste) > 0) and (FRecycled < FMaxRecycles);
end;

{ The waste is turned over: its bottom card becomes the top of the new stock, so
  the cards come round again in the order they came the first time. }
function TPyramidGame.Recycle: Boolean;
var
  M: TPairMove;
  I, N: Integer;
begin
  Result := CanRecycle;
  if not Result then Exit;
  M.Kind := mkRecycle;
  M.A := PosNone;
  M.B := PosNone;
  M.WasteCard := FTableau[0];
  M.Missed := False;
  M.Bites := 0;
  M.Ate := False;
  M.Broke := False;
  M.PrevStreak := FStreak;
  N := Length(FWaste);
  SetLength(FStock, N);
  for I := 0 to N - 1 do
  begin
    FStock[I] := FWaste[N - 1 - I];
    FStock[I].FaceUp := False;
  end;
  SetLength(FWaste, 0);
  Inc(FRecycled);
  Push(M);
end;

function TPyramidGame.HasMoves: Boolean;
begin
  Result := HasRemoval or CanDraw or CanRecycle;
end;

function TPyramidGame.IsWon: Boolean;
begin
  Result := CardsLeft = 0;
end;

function TPyramidGame.IsStuck: Boolean;
begin
  Result := not IsWon and not HasMoves;
end;

{ ---- undo ---- }

function TPyramidGame.CanUndo: Boolean;
begin
  Result := (Length(FHistory) > 0) and not IsWon;
end;

function TPyramidGame.LastMove(out M: TPairMove): Boolean;
begin
  Result := Length(FHistory) > 0;
  if Result then M := FHistory[High(FHistory)];
end;

function TPyramidGame.LastMoveMissed: Boolean;
begin
  Result := (Length(FHistory) > 0) and FHistory[High(FHistory)].Missed;
end;

function TPyramidGame.LastMoveBites: Integer;
begin
  if Length(FHistory) > 0 then Result := FHistory[High(FHistory)].Bites else Result := 0;
end;

function TPyramidGame.LastMoveAte: Boolean;
begin
  Result := (Length(FHistory) > 0) and FHistory[High(FHistory)].Ate;
end;

{ Take one move back, checking as it goes that it could really have been made (so
  that a hand loaded from a file cannot hold an impossible history). }
function TPyramidGame.UndoMove(const M: TPairMove): Boolean;
var
  I, N, RA, RB: Integer;
  C: TCard;
begin
  Result := False;
  if M.PrevStreak < 0 then Exit;
  case M.Kind of
    mkDraw:
      begin
        N := Length(FWaste);
        if (N = 0) or (FDraws <= 0) or (FStreak <> 0) then Exit;
        if M.Ate then
        begin
          if (FHazard <> hzHunger) or (Length(FEaten) = 0) then Exit;
          UneatCard;
        end;
        C := FWaste[N - 1];
        SetLength(FWaste, N - 1);
        C.FaceUp := False;
        SetLength(FStock, Length(FStock) + 1);
        FStock[High(FStock)] := C;
        Dec(FDraws);
      end;
    mkRecycle:
      begin
        if (Length(FStock) = 0) or (Length(FWaste) <> 0) or (FRecycled <= 0) then Exit;
        N := Length(FStock);
        SetLength(FWaste, N);
        for I := 0 to N - 1 do
        begin
          FWaste[I] := FStock[N - 1 - I];
          FWaste[I].FaceUp := True;
        end;
        SetLength(FStock, 0);
        Dec(FRecycled);
      end;
    mkRemove:
      begin
        if (M.A < PosWaste) or (M.A >= PyramidSize) then Exit;
        if (M.B < PosNone) or (M.B >= PyramidSize) or (M.A = M.B) then Exit;
        if (M.A = PosWaste) and (M.B = PosWaste) then Exit;
        { what they were: a King alone, or two cards adding up to 13 }
        if M.B = PosNone then
        begin
          if M.A = PosWaste then
          begin
            if M.WasteCard.Rank <> KingRank then Exit;
          end
          else if FTableau[M.A].Rank <> KingRank then Exit;
        end
        else
        begin
          if M.A = PosWaste then RA := M.WasteCard.Rank else RA := FTableau[M.A].Rank;
          if M.B = PosWaste then RB := M.WasteCard.Rank else RB := FTableau[M.B].Rank;
          if not MakesPair(RA, RB) then Exit;
        end;
        if (M.A >= 0) and not FRemoved[M.A] then Exit;
        if (M.B >= 0) and not FRemoved[M.B] then Exit;
        if M.Bites <> BitesOf(M.A, M.B) then Exit;
        { the streak: a bite ended it, anything else added one }
        if M.Bites > 0 then
        begin
          if FStreak <> 0 then Exit;
        end
        else if FStreak <> M.PrevStreak + 1 then Exit;
        if (M.A = PosWaste) or (M.B = PosWaste) then
        begin
          if FWasteGone <= 0 then Exit;
          C := M.WasteCard;
          C.FaceUp := True;
          SetLength(FWaste, Length(FWaste) + 1);
          FWaste[High(FWaste)] := C;
          Dec(FWasteGone);
        end;
        if M.A >= 0 then FRemoved[M.A] := False;
        if M.B >= 0 then FRemoved[M.B] := False;
        { both were free when they were taken (or one was under the other) }
        if M.A >= 0 then
        begin
          if FUnderPairs then begin if not CoversWithin(M.A, M.B) then Exit; end
          else if not IsFree(M.A) then Exit;
        end;
        if M.B >= 0 then
        begin
          if FUnderPairs then begin if not CoversWithin(M.B, M.A) then Exit; end
          else if not IsFree(M.B) then Exit;
        end;
        { a chained card needed the Pick }
        N := 0;
        if (M.A >= 0) and IsLockedStrict(M.A) then Inc(N);
        if (M.B >= 0) and IsLockedStrict(M.B) then Inc(N);
        if M.Broke then
        begin
          if (N <> 1) or not FBreakUsed then Exit;
          FBreakUsed := False;
        end
        else if N <> 0 then Exit;
      end;
  end;
  FStreak := M.PrevStreak;
  Result := RemovedOk(FRemoved);
end;

function TPyramidGame.Undo: Boolean;
var
  M: TPairMove;
begin
  Result := CanUndo and LastMove(M);
  if not Result then Exit;
  Result := UndoMove(M);
  if Result then SetLength(FHistory, Length(FHistory) - 1);
end;

{ A card can only be gone if both cards covering it are gone. }
function TPyramidGame.RemovedOk(const R: TRemovedArray): Boolean;
var
  I, L, Rt: Integer;
begin
  Result := True;
  for I := 0 to PyramidSize - 1 do
    if R[I] then
    begin
      L := CoverLeft(I);
      Rt := CoverRight(I);
      if ((L >= 0) and not R[L]) or ((Rt >= 0) and not R[Rt]) then Result := False;
    end;
end;

{ ---- special cards ---- }

function TPyramidGame.HasFreeCard: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to PyramidSize - 1 do
    if IsFree(I) then Exit(True);
end;

function TPyramidGame.CanStake(I: Integer): Boolean;
begin
  Result := IsFree(I) and not IsWon;
end;

function TPyramidGame.Stake(I: Integer): Boolean;
begin
  Result := CanStake(I);
  if not Result then Exit;
  FRemoved[I] := True;
  Inc(FStakes);                            { not a move: the streak stays }
  ForgetUndo;
end;

function TPyramidGame.CanWild(A, B: Integer): Boolean;
var
  CA, CB: TCard;
begin
  Result := (A <> B) and CardFor(A, CA) and CardFor(B, CB) and not IsWon;
end;

function TPyramidGame.Wild(A, B: Integer): Boolean;
begin
  Result := CanWild(A, B);
  if not Result then Exit;
  if A = PosWaste then
  begin
    SetLength(FWaste, Length(FWaste) - 1);
    Inc(FWasteGone);
  end
  else FRemoved[A] := True;
  if B = PosWaste then
  begin
    SetLength(FWaste, Length(FWaste) - 1);
    Inc(FWasteGone);
  end
  else FRemoved[B] := True;
  Inc(FStreak);                            { it counts as a pair }
  if FStreak > FBestStreak then FBestStreak := FStreak;
  ForgetUndo;
end;

function TPyramidGame.CanExtraTurn: Boolean;
begin
  Result := not IsWon;
end;

function TPyramidGame.ExtraTurn: Boolean;
begin
  Result := CanExtraTurn;
  if not Result then Exit;
  Inc(FMaxRecycles);
  ForgetUndo;
end;

function TPyramidGame.CanEasyRule: Boolean;
begin
  Result := not FUnderPairs and not IsWon;
end;

function TPyramidGame.EasyRule: Boolean;
begin
  Result := CanEasyRule;
  if not Result then Exit;
  FUnderPairs := True;
  ForgetUndo;
end;

function TPyramidGame.CanReveal: Boolean;
begin
  Result := not FRevealed and not IsWon and (Length(FStock) > 0);
end;

function TPyramidGame.Reveal: Boolean;
begin
  Result := CanReveal;
  if not Result then Exit;
  FRevealed := True;
  ForgetUndo;
end;

function TPyramidGame.InPlayCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to PyramidSize - 1 do
    if IsFree(I) then Inc(Result);
  if Length(FWaste) > 0 then Inc(Result);
end;

{ ---- saving ---- }

procedure TPyramidGame.GetState(out D: TPairHand);
var
  I: Integer;
begin
  D.HandId := FHandId;
  D.MaxRecycles := FMaxRecycles;
  D.Recycled := FRecycled;
  D.UnderPairs := FUnderPairs;
  D.Hazard := Ord(FHazard);
  D.Revealed := FRevealed;
  D.Stakes := FStakes;
  D.Draws := FDraws;
  D.Streak := FStreak;
  D.BestStreak := FBestStreak;
  D.WasteGone := FWasteGone;
  D.BreakUsed := FBreakUsed;
  for I := 0 to PyramidSize - 1 do      { element by element: in JavaScript a whole-array assignment shares the array }
  begin
    D.Tableau[I] := FTableau[I];
    D.Removed[I] := FRemoved[I];
    D.Marks[I] := FMarks[I];
  end;
  D.Stock := Copy(FStock);
  D.Waste := Copy(FWaste);
  D.Eaten := Copy(FEaten);
  D.History := Copy(FHistory);
end;

function TPyramidGame.SetState(const D: TPairHand): Boolean;
var
  T: TPyramidGame;
  I, J, Gone, Cards, NRecycles, NDraws: Integer;
  All: array of TCard;
  M: TPairMove;
begin
  Result := False;
  if (D.MaxRecycles < 0) or (D.MaxRecycles > 99) or (D.Recycled < 0) or (D.Recycled > D.MaxRecycles) then Exit;
  if (D.Hazard < Ord(Low(THazard))) or (D.Hazard > Ord(High(THazard))) then Exit;
  if (D.Stakes < 0) or (D.Draws < 0) or (D.Streak < 0) or (D.BestStreak < D.Streak) or (D.WasteGone < 0) then Exit;
  for I := 0 to PyramidSize - 1 do
    if (D.Marks[I] < MarkNone) or (D.Marks[I] > MarkCross) then Exit;
  { what the history says: waste cards taken, draws, turn-overs }
  Gone := 0;
  NDraws := 0;
  NRecycles := 0;
  for I := 0 to High(D.History) do
  begin
    M := D.History[I];
    if (M.Kind = mkRemove) and ((M.A = PosWaste) or (M.B = PosWaste)) then Inc(Gone);
    if M.Kind = mkDraw then Inc(NDraws);
    if M.Kind = mkRecycle then Inc(NRecycles);
  end;
  if (D.WasteGone < Gone) or (D.Draws < NDraws) or (D.Recycled < NRecycles) then Exit;
  { every card is different, and they add up to a pack }
  Cards := PyramidSize + Length(D.Stock) + Length(D.Waste) + Length(D.Eaten) + D.WasteGone;
  if Cards <> 52 then Exit;
  SetLength(All, PyramidSize + Length(D.Stock) + Length(D.Waste) + Length(D.Eaten) + Gone);
  J := 0;
  for I := 0 to PyramidSize - 1 do begin All[J] := D.Tableau[I]; Inc(J); end;
  for I := 0 to High(D.Stock) do begin All[J] := D.Stock[I]; Inc(J); end;
  for I := 0 to High(D.Waste) do begin All[J] := D.Waste[I]; Inc(J); end;
  for I := 0 to High(D.Eaten) do begin All[J] := D.Eaten[I]; Inc(J); end;
  for I := 0 to High(D.History) do
    if (D.History[I].Kind = mkRemove) and ((D.History[I].A = PosWaste) or (D.History[I].B = PosWaste)) then
    begin
      All[J] := D.History[I].WasteCard;
      Inc(J);
    end;
  for I := 0 to High(All) do
    for J := I + 1 to High(All) do
      if (All[I].Suit = All[J].Suit) and (All[I].Rank = All[J].Rank) then Exit;
  { undo every move on a copy: each must be a move that could have been made }
  T := TPyramidGame.Create;
  try
    T.FMaxRecycles := D.MaxRecycles;
    T.FUnderPairs := D.UnderPairs;
    T.FHazard := THazard(D.Hazard);
    T.FRecycled := D.Recycled;
    T.FDraws := D.Draws;
    T.FStreak := D.Streak;
    T.FWasteGone := D.WasteGone;
    T.FBreakUsed := D.BreakUsed;
    for I := 0 to PyramidSize - 1 do
    begin
      T.FTableau[I] := D.Tableau[I];
      T.FRemoved[I] := D.Removed[I];
      T.FMarks[I] := D.Marks[I];
    end;
    T.FStock := Copy(D.Stock);
    T.FWaste := Copy(D.Waste);
    T.FEaten := Copy(D.Eaten);
    T.FHistory := Copy(D.History);
    if not T.RemovedOk(T.FRemoved) then Exit;
    while Length(T.FHistory) > 0 do
    begin
      if not T.UndoMove(T.FHistory[High(T.FHistory)]) then Exit;
      SetLength(T.FHistory, Length(T.FHistory) - 1);
    end;
  finally
    T.Free;
  end;
  FHandId := D.HandId;
  FMaxRecycles := D.MaxRecycles;
  FRecycled := D.Recycled;
  FUnderPairs := D.UnderPairs;
  FHazard := THazard(D.Hazard);
  FRevealed := D.Revealed;
  FStakes := D.Stakes;
  FDraws := D.Draws;
  FStreak := D.Streak;
  FBestStreak := D.BestStreak;
  FWasteGone := D.WasteGone;
  FBreakUsed := D.BreakUsed;
  for I := 0 to PyramidSize - 1 do
  begin
    FTableau[I] := D.Tableau[I];
    FTableau[I].FaceUp := True;
    FRemoved[I] := D.Removed[I];
    FMarks[I] := D.Marks[I];
  end;
  FStock := Copy(D.Stock);
  FWaste := Copy(D.Waste);
  FEaten := Copy(D.Eaten);
  FHistory := Copy(D.History);
  Result := True;
end;

end.
