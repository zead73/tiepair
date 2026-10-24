unit PairHand;

{ Saving a hand to disk (or the browser's storage) and reading it back. No window
  code. The file is plain text, one "key=value" per line. Reading is defensive: any
  missing or malformed entry means "no usable hand" (False). Whether the cards add
  up to a believable hand is then checked by the game itself (TPyramidGame.SetState). }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Storage, Cards, Pyramid;

function HandToText(const H: TPairHand): string;
function TextToHand(const Text: string; out H: TPairHand): Boolean;

function AutoSaveFile: string;
function WriteHandFile(const FileName: string; const H: TPairHand): Boolean;
function ReadHandFile(const FileName: string; out H: TPairHand): Boolean;
procedure DeleteHandFile(const FileName: string);

implementation

const
  Magic = 'tiepair-hand 1';

function AutoSaveFile: string;
begin
  Result := StoreName('freeplay.hand');
end;

function CardToStr(const C: TCard): string;
begin
  Result := IntToStr(Ord(C.Suit)) + '-' + IntToStr(C.Rank);
end;

function StrToCard(const S: string; out C: TCard): Boolean;
var
  P, Su, Ra: Integer;
begin
  Result := False;
  P := Pos('-', S);
  if P < 2 then Exit;
  if not TryStrToInt(Copy(S, 1, P - 1), Su) then Exit;
  if not TryStrToInt(Copy(S, P + 1, MaxInt), Ra) then Exit;
  if (Su < 0) or (Su > Ord(High(TSuit))) then Exit;
  if (Ra < Low(TRank)) or (Ra > High(TRank)) then Exit;
  C.Suit := TSuit(Su);
  C.Rank := Ra;
  C.FaceUp := False;
  Result := True;
end;

{ Splits S at Sep. }
procedure Split(const S: string; Sep: Char; out Parts: array of string; out N: Integer);
var
  P, Start: Integer;
begin
  N := 0;
  Start := 1;
  for P := 1 to Length(S) + 1 do
    if (P > Length(S)) or (S[P] = Sep) then
    begin
      if (P > Start) and (N <= High(Parts)) then
      begin
        Parts[N] := Copy(S, Start, P - Start);
        Inc(N);
      end;
      Start := P + 1;
    end;
end;

function CardsToStr(const A: TCardArray): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(A) do
  begin
    if Result <> '' then Result := Result + ' ';
    Result := Result + CardToStr(A[I]);
  end;
end;

function StrToCards(const S: string; out A: TCardArray): Boolean;
var
  Parts: array[0..52] of string;
  N, I: Integer;
begin
  Result := False;
  A := nil;
  Split(S, ' ', Parts, N);
  if N > 52 then Exit;
  SetLength(A, N);
  for I := 0 to N - 1 do
    if not StrToCard(Parts[I], A[I]) then Exit;
  Result := True;
end;

{ Positions are written plus 2, so that "the waste" and "nothing" (-1, -2) are not negative. }
function MovesToStr(const M: TMoveArray): string;
var
  I: Integer;
  S: string;
begin
  Result := '';
  for I := 0 to High(M) do
  begin
    case M[I].Kind of
      mkDraw: S := 'd';
      mkRecycle: S := 'r';
    else
      S := 'x:' + IntToStr(M[I].A + 2) + ':' + IntToStr(M[I].B + 2) + ':' + CardToStr(M[I].WasteCard);
    end;
    if Result <> '' then Result := Result + ' ';
    Result := Result + S;
  end;
end;

function StrToMoves(const S: string; out M: TMoveArray): Boolean;
var
  Parts: array[0..1999] of string;
  Bits: array[0..3] of string;
  N, NB, I, A, B: Integer;
  C: TCard;
begin
  Result := False;
  M := nil;
  Split(S, ' ', Parts, N);
  if N > 2000 then Exit;
  SetLength(M, N);
  for I := 0 to N - 1 do
  begin
    M[I].A := PosNone;
    M[I].B := PosNone;
    M[I].WasteCard.Suit := suSpades;
    M[I].WasteCard.Rank := 1;
    M[I].WasteCard.FaceUp := False;
    if Parts[I] = 'd' then M[I].Kind := mkDraw
    else if Parts[I] = 'r' then M[I].Kind := mkRecycle
    else
    begin
      Split(Parts[I], ':', Bits, NB);
      if (NB <> 4) or (Bits[0] <> 'x') then Exit;
      if not TryStrToInt(Bits[1], A) or not TryStrToInt(Bits[2], B) then Exit;
      if not StrToCard(Bits[3], C) then Exit;
      M[I].Kind := mkRemove;
      M[I].A := A - 2;
      M[I].B := B - 2;
      M[I].WasteCard := C;
    end;
  end;
  Result := True;
end;

function HandToText(const H: TPairHand): string;
var
  I: Integer;
  Tab: TCardArray;
  Rem, EasyStr: string;
begin
  if H.UnderPairs then EasyStr := '1' else EasyStr := '0';
  SetLength(Tab, PyramidSize);
  Rem := '';
  for I := 0 to PyramidSize - 1 do
  begin
    Tab[I] := H.Tableau[I];
    if H.Removed[I] then Rem := Rem + '1' else Rem := Rem + '0';
  end;
  Result := Magic + #10 +
    'id=' + IntToStr(H.HandId) + #10 +
    'max=' + IntToStr(H.MaxRecycles) + #10 +
    'recycled=' + IntToStr(H.Recycled) + #10 +
    'easy=' + EasyStr + #10 +
    'tableau=' + CardsToStr(Tab) + #10 +
    'removed=' + Rem + #10 +
    'stock=' + CardsToStr(H.Stock) + #10 +
    'waste=' + CardsToStr(H.Waste) + #10 +
    'undo=' + MovesToStr(H.History) + #10;
end;

{ The text after "Key=" on its own line, or '' (found = False). }
function ValueOf(const Text, Key: string; out Found: Boolean): string;
var
  P, Q: Integer;
  Needle: string;
begin
  Found := False;
  Result := '';
  Needle := #10 + Key + '=';
  P := Pos(Needle, #10 + Text);
  if P = 0 then Exit;
  P := P + Length(Needle) - 1;                       { in Text, just after the "=" }
  Q := P;
  while (Q <= Length(Text)) and (Text[Q] <> #10) and (Text[Q] <> #13) do Inc(Q);
  Result := Copy(Text, P, Q - P);
  Found := True;
end;

function TextToHand(const Text: string; out H: TPairHand): Boolean;
var
  Found: Boolean;
  S: string;
  Tab: TCardArray;
  I: Integer;
begin
  Result := False;
  H.HandId := 0;
  H.MaxRecycles := 0;
  H.Recycled := 0;
  H.UnderPairs := True;                 { version 0.2.0 wrote no "easy=" line, and its hands were all Easy }
  H.Stock := nil;
  H.Waste := nil;
  H.History := nil;
  for I := 0 to PyramidSize - 1 do
  begin
    H.Removed[I] := False;
    H.Tableau[I].Suit := suSpades;
    H.Tableau[I].Rank := 1;
    H.Tableau[I].FaceUp := True;
  end;
  if Copy(Text, 1, Length(Magic)) <> Magic then Exit;
  if not TryStrToInt(ValueOf(Text, 'id', Found), H.HandId) or not Found then Exit;
  if not TryStrToInt(ValueOf(Text, 'max', Found), H.MaxRecycles) or not Found then Exit;
  if not TryStrToInt(ValueOf(Text, 'recycled', Found), H.Recycled) or not Found then Exit;
  S := ValueOf(Text, 'easy', Found);
  if Found then
  begin
    if (S <> '0') and (S <> '1') then Exit;
    H.UnderPairs := S = '1';
  end;
  S := ValueOf(Text, 'tableau', Found);
  if not Found or not StrToCards(S, Tab) or (Length(Tab) <> PyramidSize) then Exit;
  for I := 0 to PyramidSize - 1 do H.Tableau[I] := Tab[I];
  S := ValueOf(Text, 'removed', Found);
  if not Found or (Length(S) <> PyramidSize) then Exit;
  for I := 0 to PyramidSize - 1 do
  begin
    if (S[I + 1] <> '0') and (S[I + 1] <> '1') then Exit;
    H.Removed[I] := S[I + 1] = '1';
  end;
  if not StrToCards(ValueOf(Text, 'stock', Found), H.Stock) or not Found then Exit;
  if not StrToCards(ValueOf(Text, 'waste', Found), H.Waste) or not Found then Exit;
  if not StrToMoves(ValueOf(Text, 'undo', Found), H.History) or not Found then Exit;
  Result := True;
end;

function WriteHandFile(const FileName: string; const H: TPairHand): Boolean;
begin
  Result := StoreWrite(FileName, HandToText(H));
end;

function ReadHandFile(const FileName: string; out H: TPairHand): Boolean;
var
  Text: string;
begin
  Result := StoreRead(FileName, Text) and TextToHand(Text, H);
end;

procedure DeleteHandFile(const FileName: string);
begin
  StoreDelete(FileName);
end;

end.
