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
  (a Queen sitting on an Ace, say). This is Tiepair's own rule. In NORMAL mode
  (the default) a card has to be uncovered first, which is how Pyramid is usually
  played. The mode belongs to a hand: it is saved with it.

  Choices that other books make differently are named here, so they are easy to
  see and change:
    - only the TOP of the waste is in play, never the cards under it;
    - the stock's top card is face down and is not in play until it is drawn;
    - a pair is two different cards: a card is never paired with itself, and
      the waste top can be paired with a free pyramid card (not with an "under" one);
    - a King is only taken on its own when it is free;
    - turning the waste over keeps the cards in their old order, so a hand that
      is played through again comes out in the same order;
    - DefaultRecycles is how many times the stock can be turned over. }

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
  DefaultRecycles = 2;         { the stock can be turned over this many times: three trips through it (measured with tools/pair-solver.pas) }
  PosWaste = -1;               { "the top of the waste" in a move }
  PosNone = -2;                { "no second card": a King on its own }

type
  TRemovedArray = array[0..PyramidSize - 1] of Boolean;
  TTableauArray = array[0..PyramidSize - 1] of TCard;

  TMoveKind = (mkDraw, mkRecycle, mkRemove);

  { One move that undo can take back. For a removal, A and B are pyramid
    positions (0..27), PosWaste or PosNone; WasteCard is the card that was taken
    from the top of the waste, if one was. }
  TPairMove = record
    Kind: TMoveKind;
    A, B: Integer;
    WasteCard: TCard;
  end;
  TMoveArray = array of TPairMove;

  { Everything needed to put a hand back exactly as it was, with its undo. }
  TPairHand = record
    HandId: Integer;
    MaxRecycles: Integer;
    Recycled: Integer;
    UnderPairs: Boolean;         { the hand is being played in Easy mode }
    Tableau: TTableauArray;
    Removed: TRemovedArray;
    Stock: TCardArray;           { the top of the stock is the last card }
    Waste: TCardArray;           { the top of the waste is the last card }
    History: TMoveArray;         { every move since the deal, oldest first }
  end;

  TPyramidGame = class
  private
    FTableau: TTableauArray;
    FRemoved: TRemovedArray;
    FStock, FWaste: TCardArray;
    FRecycled, FMaxRecycles, FHandId: Integer;
    FUnderPairs: Boolean;
    FHistory: TMoveArray;
    function UndoMove(const M: TPairMove): Boolean;
    function RemovedOk(const R: TRemovedArray): Boolean;
    function CardFor(APos: Integer; out C: TCard): Boolean;
    function CoversWithin(X, Y: Integer): Boolean;
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
    function CanSelect(APos: Integer): Boolean;      { InPlay, or an "under" card }
    function CardsLeft: Integer;                     { pyramid cards still on the table }

    { Which cards are in play, and what can be done with them }
    function WasteTop(out C: TCard): Boolean;
    function StockCount: Integer;
    function WasteCount: Integer;
    function InPlay(APos: Integer): Boolean;         { a free pyramid card, or the waste top (PosWaste) }
    function CardIn(APos: Integer): TCard;           { the card there (InPlay must be true) }
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

    property MaxRecycles: Integer read FMaxRecycles write FMaxRecycles;
    { May a card be taken away together with the one card still covering it (Easy
      mode)? Set it before dealing: a saved hand carries its own. }
    property UnderPairs: Boolean read FUnderPairs write FUnderPairs;
    property Recycled: Integer read FRecycled;
    function RecyclesLeft: Integer;
    property HandId: Integer read FHandId;

    procedure GetState(out D: TPairHand);
    { False (and nothing changed) unless the hand is a believable one: the cards
      are all different, and undoing every move in its history, one at a time,
      leads back to a fresh deal without ever breaking a rule. }
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
  end;
  SetLength(FStock, 0);
  SetLength(FStock, StockStart);
  for I := 0 to StockStart - 1 do
  begin
    FStock[I] := ADeck.Draw;
    FStock[I].FaceUp := False;
  end;
  SetLength(FWaste, 0);
  SetLength(FHistory, 0);
  FRecycled := 0;
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
end;

function TPyramidGame.CanRemove(A, B: Integer): Boolean;
var
  CA, CB: TCard;
begin
  Result := False;
  if B = PosNone then
  begin
    Result := CardFor(A, CA) and (CA.Rank = KingRank);
    Exit;
  end;
  if A = B then Exit;
  if CardFor(A, CA) and CardFor(B, CB) then
    Result := MakesPair(CA.Rank, CB.Rank)
  else if FUnderPairs and (A >= 0) and (B >= 0) and (A < PyramidSize) and (B < PyramidSize)
    and not FRemoved[A] and not FRemoved[B] then
    { a card and the one card that covers it }
    Result := MakesPair(FTableau[A].Rank, FTableau[B].Rank)
      and ((IsUnder(A) and (SoleCover(A) = B)) or (IsUnder(B) and (SoleCover(B) = A)));
end;

function TPyramidGame.Remove(A, B: Integer): Boolean;
var
  M: TPairMove;
  C: TCard;
  N: Integer;
begin
  Result := CanRemove(A, B);
  if not Result then Exit;
  M.Kind := mkRemove;
  M.A := A;
  M.B := B;
  M.WasteCard := FTableau[0];
  if (A = PosWaste) or (B = PosWaste) then
  begin
    WasteTop(C);
    M.WasteCard := C;
    SetLength(FWaste, Length(FWaste) - 1);
  end;
  if A >= 0 then FRemoved[A] := True;
  if B >= 0 then FRemoved[B] := True;
  N := Length(FHistory);
  SetLength(FHistory, N + 1);
  FHistory[N] := M;
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
  N := Length(FWaste);
  SetLength(FWaste, N + 1);
  FWaste[N] := FStock[High(FStock)];
  FWaste[N].FaceUp := True;
  SetLength(FStock, Length(FStock) - 1);
  N := Length(FHistory);
  SetLength(FHistory, N + 1);
  FHistory[N] := M;
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
  N := Length(FWaste);
  SetLength(FStock, N);
  for I := 0 to N - 1 do
  begin
    FStock[I] := FWaste[N - 1 - I];
    FStock[I].FaceUp := False;
  end;
  SetLength(FWaste, 0);
  Inc(FRecycled);
  N := Length(FHistory);
  SetLength(FHistory, N + 1);
  FHistory[N] := M;
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
  Result := Length(FHistory) > 0;
end;

function TPyramidGame.LastMove(out M: TPairMove): Boolean;
begin
  Result := Length(FHistory) > 0;
  if Result then M := FHistory[High(FHistory)];
end;

{ Take one move back, checking as it goes that it could really have been made (so
  that a hand loaded from a file cannot hold an impossible history). }
function TPyramidGame.UndoMove(const M: TPairMove): Boolean;
var
  I, N: Integer;
  C: TCard;
begin
  Result := False;
  case M.Kind of
    mkDraw:
      begin
        N := Length(FWaste);
        if N = 0 then Exit;
        C := FWaste[N - 1];
        SetLength(FWaste, N - 1);
        C.FaceUp := False;
        SetLength(FStock, Length(FStock) + 1);
        FStock[High(FStock)] := C;
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
        if M.A = PosNone then Exit;
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
          if M.A = PosWaste then I := M.WasteCard.Rank else I := FTableau[M.A].Rank;
          if M.B = PosWaste then N := M.WasteCard.Rank else N := FTableau[M.B].Rank;
          if not MakesPair(I, N) then Exit;
        end;
        if (M.A >= 0) and not FRemoved[M.A] then Exit;
        if (M.B >= 0) and not FRemoved[M.B] then Exit;
        if (M.A = PosWaste) or (M.B = PosWaste) then
        begin
          C := M.WasteCard;
          C.FaceUp := True;
          SetLength(FWaste, Length(FWaste) + 1);
          FWaste[High(FWaste)] := C;
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
      end;
  end;
  Result := RemovedOk(FRemoved);
end;

function TPyramidGame.Undo: Boolean;
var
  M: TPairMove;
begin
  Result := LastMove(M);
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

{ ---- saving ---- }

procedure TPyramidGame.GetState(out D: TPairHand);
var
  I: Integer;
begin
  D.HandId := FHandId;
  D.MaxRecycles := FMaxRecycles;
  D.Recycled := FRecycled;
  D.UnderPairs := FUnderPairs;
  for I := 0 to PyramidSize - 1 do      { element by element: in JavaScript a whole-array assignment shares the array }
  begin
    D.Tableau[I] := FTableau[I];
    D.Removed[I] := FRemoved[I];
  end;
  D.Stock := Copy(FStock);
  D.Waste := Copy(FWaste);
  D.History := Copy(FHistory);
end;

function TPyramidGame.SetState(const D: TPairHand): Boolean;
var
  T: TPyramidGame;
  I, J, Gone, Cards: Integer;
  All: array of TCard;
  M: TPairMove;
  Draws, Recycles: Integer;
begin
  Result := False;
  if (D.MaxRecycles < 0) or (D.MaxRecycles > 99) or (D.Recycled < 0) or (D.Recycled > D.MaxRecycles) then Exit;
  { every card is different }
  Gone := 0;
  for I := 0 to High(D.History) do
    if (D.History[I].Kind = mkRemove) and ((D.History[I].A = PosWaste) or (D.History[I].B = PosWaste)) then Inc(Gone);
  Cards := PyramidSize + Length(D.Stock) + Length(D.Waste) + Gone;
  if Cards <> 52 then Exit;
  SetLength(All, Cards);
  J := 0;
  for I := 0 to PyramidSize - 1 do begin All[J] := D.Tableau[I]; Inc(J); end;
  for I := 0 to High(D.Stock) do begin All[J] := D.Stock[I]; Inc(J); end;
  for I := 0 to High(D.Waste) do begin All[J] := D.Waste[I]; Inc(J); end;
  for I := 0 to High(D.History) do
    if (D.History[I].Kind = mkRemove) and ((D.History[I].A = PosWaste) or (D.History[I].B = PosWaste)) then
    begin
      All[J] := D.History[I].WasteCard;
      Inc(J);
    end;
  for I := 0 to Cards - 1 do
    for J := I + 1 to Cards - 1 do
      if (All[I].Suit = All[J].Suit) and (All[I].Rank = All[J].Rank) then Exit;
  { the history adds up to the hand }
  Draws := 0;
  Recycles := 0;
  for I := 0 to High(D.History) do
  begin
    M := D.History[I];
    if M.Kind = mkDraw then Inc(Draws);
    if M.Kind = mkRecycle then Inc(Recycles);
  end;
  if Recycles <> D.Recycled then Exit;
  { undo every move on a copy: it must end at a fresh deal }
  T := TPyramidGame.Create;
  try
    T.FMaxRecycles := D.MaxRecycles;
    T.FUnderPairs := D.UnderPairs;
    T.FRecycled := D.Recycled;
    for I := 0 to PyramidSize - 1 do
    begin
      T.FTableau[I] := D.Tableau[I];
      T.FRemoved[I] := D.Removed[I];
    end;
    T.FStock := Copy(D.Stock);
    T.FWaste := Copy(D.Waste);
    T.FHistory := Copy(D.History);
    if not T.RemovedOk(T.FRemoved) then Exit;
    while T.CanUndo do
      if not T.Undo then Exit;
    if (Length(T.FWaste) <> 0) or (Length(T.FStock) <> StockStart) or (T.FRecycled <> 0) then Exit;
    for I := 0 to PyramidSize - 1 do
      if T.FRemoved[I] then Exit;
  finally
    T.Free;
  end;
  FHandId := D.HandId;
  FMaxRecycles := D.MaxRecycles;
  FRecycled := D.Recycled;
  FUnderPairs := D.UnderPairs;
  for I := 0 to PyramidSize - 1 do
  begin
    FTableau[I] := D.Tableau[I];
    FTableau[I].FaceUp := True;
    FRemoved[I] := D.Removed[I];
  end;
  FStock := Copy(D.Stock);
  FWaste := Copy(D.Waste);
  FHistory := Copy(D.History);
  Result := True;
end;

end.
