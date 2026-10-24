program PairSolver;

{ Measures how often a hand of Perfect Pair can be won, for different numbers of
  turn-overs of the stock (MaxRecycles). Run it like this:

    fpc -Mobjfpc -O2 -Fusrc -FUbuild/lib/tools -FEbuild tools/pair-solver.pas
    build/pair-solver [deals] [under]     (under = 0: Normal mode; anything else or nothing: Easy mode)

  Two kinds of player are measured on the same deals:
    plain   what a careful person does with no foresight: take a King, else a
            pair between two pyramid cards, else a pair with the waste top, else
            draw. It never looks at the stock's order.
    skilled the best of many tries on the same deal (mostly the plain choice, now
            and then a different legal move). It knows the stock's order, so it
            is a LOWER bound on what perfect play could win. }

{$mode objfpc}{$H+}

uses SysUtils, Cards, Pyramid;

const
  Tries = 150;
  Chaos = 12;                    { one move in this many is a random legal one }

{ One step of the plain player (or a random move now and then). False: nothing to do. }
function Step(G: TPyramidGame; Random_: Boolean): Boolean;
var
  I, J, A, B, N: Integer;
  Spots: array[0..PyramidSize] of Integer;
begin
  Result := True;
  if Random_ and (G.RemovalCount > 0) and (Random(2) = 0) then
  begin
    G.FindRemoval(Random(G.RemovalCount), A, B);
    G.Remove(A, B);
    Exit;
  end;
  N := 0;
  for I := 0 to PyramidSize - 1 do
    if G.IsFree(I) or G.IsUnder(I) then begin Spots[N] := I; Inc(N); end;
  { a King in the pyramid }
  for I := 0 to N - 1 do
    if G.CanRemove(Spots[I], PosNone) then begin G.Remove(Spots[I], PosNone); Exit; end;
  { a pair inside the pyramid }
  for I := 0 to N - 1 do
    for J := I + 1 to N - 1 do
      if G.CanRemove(Spots[I], Spots[J]) then begin G.Remove(Spots[I], Spots[J]); Exit; end;
  { the waste }
  if G.CanRemove(PosWaste, PosNone) then begin G.Remove(PosWaste, PosNone); Exit; end;
  for I := 0 to N - 1 do
    if G.CanRemove(Spots[I], PosWaste) then begin G.Remove(Spots[I], PosWaste); Exit; end;
  if G.CanDraw then begin G.Draw; Exit; end;
  if G.CanRecycle then begin G.Recycle; Exit; end;
  Result := False;
end;

function Play(G: TPyramidGame; Skilled: Boolean): Boolean;
var
  Guard: Integer;
begin
  Guard := 0;
  while not G.IsWon and (Guard < 2000) do
  begin
    Inc(Guard);
    if Skilled and (Random(Chaos) = 0) then
    begin
      if not Step(G, True) then Break;
    end
    else if not Step(G, False) then Break;
  end;
  Result := G.IsWon;
end;

var
  Deals, Plain, Skilled, D, T, Recycles: Integer;
  G: TPyramidGame;
  Decks: array of TPairHand;
  Start: TPairHand;
  Won: Boolean;
begin
  Randomize;
  Deals := 600;
  if ParamCount >= 1 then Deals := StrToIntDef(ParamStr(1), Deals);
  G := TPyramidGame.Create;
  G.UnderPairs := not ((ParamCount >= 2) and (ParamStr(2) = '0'));
  SetLength(Decks, Deals);
  for D := 0 to Deals - 1 do
  begin
    G.NewShuffled;
    G.GetState(Decks[D]);
  end;
  if G.UnderPairs then Write('Easy mode') else Write('Normal mode');
  WriteLn(': ', Deals, ' deals, "skilled" = best of ', Tries, ' tries');
  WriteLn('turn-overs   plain    skilled');
  for Recycles in [0, 1, 2, 3, 99] do
  begin
    Plain := 0;
    Skilled := 0;
    for D := 0 to Deals - 1 do
    begin
      Start := Decks[D];
      Start.MaxRecycles := Recycles;
      G.SetState(Start);
      if Play(G, False) then Inc(Plain);
      Won := False;
      for T := 1 to Tries do
      begin
        G.SetState(Start);
        if Play(G, True) then begin Won := True; Break; end;
      end;
      if Won then Inc(Skilled);
    end;
    if Recycles = 99 then Write('unlimited   ') else Write(Recycles:6, '       ');
    WriteLn(100 * Plain / Deals:6:1, '%  ', 100 * Skilled / Deals:6:1, '%');
  end;
  G.Free;
end.
