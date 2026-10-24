program PairPerfect;

{ Measures how often a hand of Tiepair can be won with PERFECT play (every card,
  including the stock's order, known), for each vampire's rules. A depth-first search
  over the real game with a table of positions already seen; a hand the search gives up
  on (too many positions) is counted as "unknown". Run it like this:

    fpc -Mobjfpc -O2 -Fusrc -FUbuild/lib/tools -FEbuild tools/pair-perfect.pas
    build/pair-perfect [deals] [node cap per deal]

  Shows: proven winnable / proven not / unknown, so the true share is between
  "winnable" and "winnable + unknown". }

{$mode objfpc}{$H+}

uses SysUtils, Generics.Collections, Cards, Pyramid;

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
  Seen: specialize TDictionary<QWord, Boolean>;
  Nodes, NodeCap: Int64;
  Capped: Boolean;

function Key(G: TPyramidGame): QWord;
var
  D: TPairHand;
  I: Integer;
  H: QWord;
  procedure Mix(V: QWord);
  begin
    H := (H xor V) * QWord(1099511628211);
  end;
begin
  G.GetState(D);
  H := QWord(14695981039346656037);
  for I := 0 to PyramidSize - 1 do
    if D.Removed[I] then Mix(1) else Mix(0);
  Mix(100 + Length(D.Stock));
  for I := 0 to High(D.Stock) do Mix(Ord(D.Stock[I].Suit) * 16 + D.Stock[I].Rank);
  Mix(200 + Length(D.Waste));
  for I := 0 to High(D.Waste) do Mix(Ord(D.Waste[I].Suit) * 16 + D.Waste[I].Rank);
  Mix(300 + D.Recycled);
  Mix(400 + D.Draws mod 4);
  Mix(500 + Ord(D.BreakUsed));
  Mix(600 + Length(D.Eaten));
  Result := H;
end;

{ A hand that can no longer be won: some pyramid card has no partner left anywhere
  (counting every pyramid card, stock and waste card; a rank r pairs only with 13-r). }
function Dead(G: TPyramidGame): Boolean;
var
  P, S: array[1..13] of Integer;
  I, R: Integer;
  D: TPairHand;
begin
  G.GetState(D);
  for R := 1 to 13 do begin P[R] := 0; S[R] := 0; end;
  for I := 0 to PyramidSize - 1 do
    if not D.Removed[I] then Inc(P[D.Tableau[I].Rank]);
  for I := 0 to High(D.Stock) do Inc(S[D.Stock[I].Rank]);
  for I := 0 to High(D.Waste) do Inc(S[D.Waste[I].Rank]);
  Result := False;
  for R := 1 to 12 do
    if P[R] > P[13 - R] + S[13 - R] then Exit(True);
end;

function Solve(G: TPyramidGame): Boolean;
var
  K, A, B, N: Integer;
  Moves: array of array[0..1] of Integer;
  Hit: Boolean;
  Kk: QWord;
begin
  Result := False;
  if G.IsWon then Exit(True);
  if Capped then Exit;
  Inc(Nodes);
  if Nodes > NodeCap then begin Capped := True; Exit; end;
  if Dead(G) then Exit;
  Kk := Key(G);
  if Seen.TryGetValue(Kk, Hit) then Exit(Hit);
  N := G.RemovalCount;
  SetLength(Moves, N);
  for K := 0 to N - 1 do G.FindRemoval(K, Moves[K][0], Moves[K][1]);
  { a King on its own is always safe to take }
  for K := 0 to N - 1 do
    if Moves[K][1] = PosNone then
    begin
      G.Remove(Moves[K][0], PosNone);
      Result := Solve(G);
      G.Undo;
      if not Capped then Seen.AddOrSetValue(Kk, Result);
      Exit;
    end;
  for K := 0 to N - 1 do
  begin
    A := Moves[K][0]; B := Moves[K][1];
    G.Remove(A, B);
    Result := Solve(G);
    G.Undo;
    if Result or Capped then Break;
  end;
  if not Result and not Capped then
    if G.CanDraw then
    begin
      G.Draw;
      Result := Solve(G);
      G.Undo;
    end
    else if G.CanRecycle then
    begin
      G.Recycle;
      Result := Solve(G);
      G.Undo;
    end;
  if Result or not Capped then Seen.AddOrSetValue(Kk, Result);
end;

var
  Deals, D, C, Win, Lose, Unknown: Integer;
  G: TPyramidGame;
  Start: TPairHand;
begin
  Randomize;
  Deals := 200;
  NodeCap := 400000;
  if ParamCount >= 1 then Deals := StrToIntDef(ParamStr(1), Deals);
  if ParamCount >= 2 then NodeCap := StrToIntDef(ParamStr(2), 400000);
  G := TPyramidGame.Create;
  Seen := specialize TDictionary<QWord, Boolean>.Create;
  WriteLn(Deals, ' deals each, search cap ', NodeCap, ' positions per deal');
  WriteLn('hand                              winnable  not   unknown');
  for C := 0 to High(Configs) do
  begin
    Win := 0; Lose := 0; Unknown := 0;
    for D := 0 to Deals - 1 do
    begin
      G.NewShuffled;
      G.UnderPairs := Configs[C].Easy;
      G.MaxRecycles := Configs[C].Recycles;
      G.SetHazard(Configs[C].Hazard);
      G.GetState(Start);
      G.SetState(Start);
      G.SetRelicRules(Configs[C].Spoon, Configs[C].Pick);
      Seen.Clear;
      Nodes := 0;
      Capped := False;
      if Solve(G) then Inc(Win)
      else if Capped then Inc(Unknown)
      else Inc(Lose);
    end;
    WriteLn(Configs[C].Name:32, '  ', 100 * Win / Deals:6:1, '%  ', 100 * Lose / Deals:6:1, '%  ', 100 * Unknown / Deals:6:1, '%');
  end;
  Seen.Free;
  G.Free;
end.
