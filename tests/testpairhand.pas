program TestPairHand;

{$mode objfpc}{$H+}

uses SysUtils, Cards, Pyramid, PairHand, Storage{$IFDEF PAS2JS}, JsCompat{$ENDIF};

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

function SameCards(const A, B: TCardArray): Boolean;
var
  I: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then Exit;
  for I := 0 to High(A) do
    if (A[I].Suit <> B[I].Suit) or (A[I].Rank <> B[I].Rank) then Result := False;
end;

procedure TestRoundTrip;
var
  G, G2: TPyramidGame;
  A, B, C: TPairHand;
  Text: string;
  N, Step, I, X, Y: Integer;
begin
  G := TPyramidGame.Create;
  G2 := TPyramidGame.Create;
  try
    for N := 1 to 60 do
    begin
      G.NewShuffled;
      G.MaxRecycles := Random(4);
      G.UnderPairs := Random(2) = 0;
      for Step := 1 to 120 do
      begin
        if G.IsWon or G.IsStuck then Break;
        if (Random(3) > 0) and G.HasRemoval then
        begin
          G.FindRemoval(Random(G.RemovalCount), X, Y);
          G.Remove(X, Y);
        end
        else if G.CanDraw then G.Draw
        else if G.CanRecycle then G.Recycle;
      end;
      G.GetState(A);
      Text := HandToText(A);
      Check(TextToHand(Text, B), 'the text reads back (hand ' + IntToStr(N) + ')');
      Check((B.HandId = A.HandId) and (B.MaxRecycles = A.MaxRecycles) and (B.Recycled = A.Recycled), 'the numbers');
      Check(B.UnderPairs = A.UnderPairs, 'the mode');
      Check(SameCards(A.Stock, B.Stock) and SameCards(A.Waste, B.Waste), 'the piles');
      Check(Length(A.History) = Length(B.History), 'the history');
      for I := 0 to PyramidSize - 1 do
        Check((A.Removed[I] = B.Removed[I]) and (A.Tableau[I].Suit = B.Tableau[I].Suit) and (A.Tableau[I].Rank = B.Tableau[I].Rank), 'pyramid card ' + IntToStr(I));
      G2.UnderPairs := not G.UnderPairs;
      Check(G2.SetState(B) and (G2.UnderPairs = G.UnderPairs), 'and the game accepts it, and takes its mode');
      G2.GetState(C);
      Check(HandToText(C) = Text, 'which writes the same text again');
      Step := 0;
      while G2.CanUndo and (Step < 1000) do
      begin
        if not G2.Undo then Break;
        Inc(Step);
      end;
      Check(G2.CardsLeft = PyramidSize, 'and can be undone to the deal');
    end;
  finally
    G.Free;
    G2.Free;
  end;
end;

procedure TestBadText;
var
  G: TPyramidGame;
  A, B: TPairHand;
  Text, Bad: string;
begin
  G := TPyramidGame.Create;
  try
    G.NewShuffled;
    G.Draw;
    G.GetState(A);
    Text := HandToText(A);
    Check(TextToHand(Text, B), 'test set-up');
    Check(not TextToHand('', B), 'empty text');
    Check(not TextToHand('hello', B), 'not a hand');
    Check(not TextToHand('tiecards-hand 1' + #10 + 'id=1' + #10, B), 'another game''s hand');
    Bad := Copy(Text, 1, Length(Text) div 2);
    Check(not TextToHand(Bad, B), 'cut short');
    Bad := StringReplace(Text, 'removed=', 'removed=2', []);
    Check(not TextToHand(Bad, B), 'a removed list of the wrong length');
    Bad := StringReplace(Text, 'tableau=', 'tableau=9-99 ', []);
    Check(not TextToHand(Bad, B), 'a card that does not exist');
    Bad := StringReplace(Text, 'undo=d', 'undo=q', []);
    Check(not TextToHand(Bad, B), 'a move that does not exist');
    Bad := StringReplace(Text, 'easy=0', 'easy=2', []);
    Check(not TextToHand(Bad, B), 'a mode that is neither');
    Bad := StringReplace(Text, 'easy=0' + #10, '', []);
    Bad := StringReplace(Bad, 'easy=1' + #10, '', []);
    Check(TextToHand(Bad, B) and B.UnderPairs, 'a hand with no mode line (version 0.2.0) was an Easy one');
  finally
    G.Free;
  end;
end;

procedure TestFile;
var
  G, G2: TPyramidGame;
  A, B: TPairHand;
begin
  SetStoreDir('tiepair_test_hand');
  G := TPyramidGame.Create;
  G2 := TPyramidGame.Create;
  try
    DeleteHandFile(AutoSaveFile);
    Check(not ReadHandFile(AutoSaveFile, B), 'nothing saved yet');
    G.NewShuffled;
    G.Draw;
    G.GetState(A);
    Check(WriteHandFile(AutoSaveFile, A), 'write');
    Check(ReadHandFile(AutoSaveFile, B) and G2.SetState(B) and (G2.HandId = G.HandId), 'read it back into a game');
    DeleteHandFile(AutoSaveFile);
    Check(not ReadHandFile(AutoSaveFile, B), 'and delete it');
  finally
    G.Free;
    G2.Free;
  end;
end;

begin
  Randomize;
  TestRoundTrip;
  TestBadText;
  TestFile;
  if Failures = 0 then WriteLn('ALL HAND FILE TESTS PASSED')
  else
  begin
    WriteLn(Failures, ' FAILURES');
    Halt(1);
  end;
end.
