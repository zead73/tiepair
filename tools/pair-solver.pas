program PairSolver;

{ Measures how often a hand of Tiepair can be won, for each vampire's hands (the Easy rule, the turn-overs of the stock,
  his trick) with and without the Pick and the Spoon. Run it like this:

    fpc -Mobjfpc -O2 -Fusrc -FUbuild/lib/tools -FEbuild tools/pair-solver.pas
    build/pair-solver [deals] [tries]

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
  DefaultTries = 150;
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

type
  TConfig = record
    Name: string;
    Easy: Boolean;
    Recycles: Integer;
    Hazard: THazard;
    Spoon, Pick: Boolean;
  end;

const
  { the campaign as it stands in vampires.pas, then the same hands with the Pick and the
    Spoon equipped, then a few what-ifs }
  Configs: array[0..11] of TConfig = (
    (Name: 'plain, Easy, 3 turns';        Easy: True;  Recycles: 3; Hazard: hzNone;    Spoon: False; Pick: False),
    (Name: 'plain, Normal, 3 turns';      Easy: False; Recycles: 3; Hazard: hzNone;    Spoon: False; Pick: False),
    (Name: 'plain, Normal, 2 turns';      Easy: False; Recycles: 2; Hazard: hzNone;    Spoon: False; Pick: False),
    (Name: 'plain, Normal, 1 turn';       Easy: False; Recycles: 1; Hazard: hzNone;    Spoon: False; Pick: False),
    (Name: 'Lucien (Easy, 3, bites)';     Easy: True;  Recycles: 3; Hazard: hzBitten;  Spoon: False; Pick: False),
    (Name: 'Carmilla (Normal, 2, chains)'; Easy: False; Recycles: 2; Hazard: hzChained; Spoon: False; Pick: False),
    (Name: 'Alaric (Normal, 2, hunger)';  Easy: False; Recycles: 2; Hazard: hzHunger;  Spoon: False; Pick: False),
    (Name: 'Carmilla + Pick';             Easy: False; Recycles: 2; Hazard: hzChained; Spoon: False; Pick: True),
    (Name: 'Alaric + Spoon';              Easy: False; Recycles: 2; Hazard: hzHunger;  Spoon: True;  Pick: False),
    (Name: 'Carmilla, Easy rule';         Easy: True;  Recycles: 2; Hazard: hzChained; Spoon: False; Pick: False),
    (Name: 'Alaric, Easy rule';           Easy: True;  Recycles: 1; Hazard: hzHunger;  Spoon: False; Pick: False),
    (Name: 'Alaric, Easy rule, +1 turn';  Easy: True;  Recycles: 2; Hazard: hzHunger;  Spoon: False; Pick: False));

var
  Tries, Deals, Plain, Skilled, D, T, C: Integer;
  G: TPyramidGame;
  Start: TPairHand;
  Won: Boolean;
begin
  Randomize;
  Deals := 600;
  Tries := DefaultTries;
  if ParamCount >= 2 then Tries := StrToIntDef(ParamStr(2), Tries);
  if ParamCount >= 1 then Deals := StrToIntDef(ParamStr(1), Deals);
  G := TPyramidGame.Create;
  WriteLn(Deals, ' deals each; "skilled" = best of ', Tries, ' tries (a lower bound on perfect play)');
  WriteLn('hand                              plain    skilled');
  for C := 0 to High(Configs) do
  begin
    Plain := 0;
    Skilled := 0;
    for D := 0 to Deals - 1 do
    begin
      G.NewShuffled;
      G.UnderPairs := Configs[C].Easy;
      G.MaxRecycles := Configs[C].Recycles;
      G.SetHazard(Configs[C].Hazard);
      G.GetState(Start);
      G.SetState(Start);
      G.SetRelicRules(Configs[C].Spoon, Configs[C].Pick);
      if Play(G, False) then Inc(Plain);
      Won := False;
      for T := 1 to Tries do
      begin
        G.SetState(Start);
        G.SetRelicRules(Configs[C].Spoon, Configs[C].Pick);
        if Play(G, True) then begin Won := True; Break; end;
      end;
      if Won then Inc(Skilled);
    end;
    WriteLn(Configs[C].Name:32, '  ', 100 * Plain / Deals:6:1, '%  ', 100 * Skilled / Deals:6:1, '%');
  end;
  G.Free;
end.
