unit HandFile;

{ Saving a hand to disk and reading it back. No window code.

  The file is plain text, one "key=value" per line. Reading is defensive: any
  missing, malformed or out-of-range entry means "no usable hand" (False), never
  a crash. Whether the cards add up to a believable hand is then checked by the
  game itself when the hand is loaded (see TPyramidGame.SetState).

  Writing is done by Storage, which on the desktop goes to a temporary file
  first and swaps it in afterwards, so a crash part-way through a save cannot
  destroy the previous save. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Storage, Cards, Pyramid, Session, Settings;

const
  SlotCount = 3;                  { manual save slots (Free Play) }

type
  TSlotInfo = record
    Exists: Boolean;
    CardsLeft: Integer;
    Stamp: string;                { when it was saved }
  end;

{ The text of a saved hand (exposed so it can be tested without files). }
function HandToText(const H: TSavedHand; const Stamp: string): string;
function TextToHand(const Text: string; out H: TSavedHand; out Stamp: string): Boolean;

function WriteHandFile(const FileName: string; const H: TSavedHand): Boolean;
function ReadHandFile(const FileName: string; out H: TSavedHand): Boolean;
{ A quick look at a save (for the slot menu) without loading it. }
function PeekHandFile(const FileName: string): TSlotInfo;
procedure DeleteHandFile(const FileName: string);
{ Deletes the game's own saved hands in Dir: the two autosaves and the manual
  slots (Free Play's and the campaign's) (and any leftover temporary files). Only those exact names: never
  anything else that happens to be in the folder. }
procedure DeleteAllSavedHands(const Dir: string);
{ Only the duel's autosave. }
procedure DeleteCampaignHand(const Dir: string);

{ Where hands live (per-user config folder). }
function AutoSaveFile(AMode: TGameMode): string;
function SlotFile(N: Integer): string;      { N = 1..SlotCount }

implementation

const
  Magic = 'tiepair-hand 2';

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

{ Splits S at Sep into Parts (as many as fit); N is how many there were. }
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

function BitsToStr(const B: TRemovedArray): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to PyramidSize - 1 do
    if B[I] then Result := Result + '1' else Result := Result + '0';
end;

function StrToBits(const S: string; out B: TRemovedArray): Boolean;
var
  I: Integer;
begin
  Result := Length(S) = PyramidSize;
  if not Result then Exit;
  for I := 0 to PyramidSize - 1 do
  begin
    if (S[I + 1] <> '0') and (S[I + 1] <> '1') then Exit(False);
    B[I] := S[I + 1] = '1';
  end;
end;

function MarksToStr(const M: TMarkArray): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to PyramidSize - 1 do Result := Result + IntToStr(M[I]);
end;

function StrToMarks(const S: string; out M: TMarkArray): Boolean;
var
  I: Integer;
begin
  Result := Length(S) = PyramidSize;
  if not Result then Exit;
  for I := 0 to PyramidSize - 1 do
  begin
    if (S[I + 1] < '0') or (S[I + 1] > '3') then Exit(False);
    M[I] := Ord(S[I + 1]) - Ord('0');
  end;
end;

function Flag(B: Boolean): string;
begin
  if B then Result := '1' else Result := '0';
end;

{ Moves, oldest first, one word each: "d:<missed>:<ate>:<prev streak>" a draw,
  "r:<prev streak>" a turn-over and "x:<a+2>:<b+2>:<card>:<bites>:<broke>:<prev streak>"
  a removal (positions are written plus 2, so that "the waste" and "nothing", -1 and
  -2, are not negative). }
function MovesToStr(const M: TMoveArray): string;
var
  I: Integer;
  S: string;
begin
  Result := '';
  for I := 0 to High(M) do
  begin
    case M[I].Kind of
      mkDraw: S := 'd:' + Flag(M[I].Missed) + ':' + Flag(M[I].Ate) + ':' + IntToStr(M[I].PrevStreak);
      mkRecycle: S := 'r:' + IntToStr(M[I].PrevStreak);
    else
      S := 'x:' + IntToStr(M[I].A + 2) + ':' + IntToStr(M[I].B + 2) + ':' + CardToStr(M[I].WasteCard) + ':' +
        IntToStr(M[I].Bites) + ':' + Flag(M[I].Broke) + ':' + IntToStr(M[I].PrevStreak);
    end;
    if Result <> '' then Result := Result + ' ';
    Result := Result + S;
  end;
end;

function StrToMoves(const S: string; out M: TMoveArray): Boolean;
var
  Parts: array[0..1999] of string;
  Bits: array[0..7] of string;
  N, NB, I, A, B, Bt, Pv: Integer;
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
    M[I].Missed := False;
    M[I].Bites := 0;
    M[I].Ate := False;
    M[I].Broke := False;
    M[I].PrevStreak := 0;
    Split(Parts[I], ':', Bits, NB);
    if NB < 1 then Exit;
    if Bits[0] = 'd' then
    begin
      if (NB <> 4) or not TryStrToInt(Bits[3], Pv) then Exit;
      if ((Bits[1] <> '0') and (Bits[1] <> '1')) or ((Bits[2] <> '0') and (Bits[2] <> '1')) then Exit;
      M[I].Kind := mkDraw;
      M[I].Missed := Bits[1] = '1';
      M[I].Ate := Bits[2] = '1';
      M[I].PrevStreak := Pv;
    end
    else if Bits[0] = 'r' then
    begin
      if (NB <> 2) or not TryStrToInt(Bits[1], Pv) then Exit;
      M[I].Kind := mkRecycle;
      M[I].PrevStreak := Pv;
    end
    else if Bits[0] = 'x' then
    begin
      if NB <> 7 then Exit;
      if not TryStrToInt(Bits[1], A) or not TryStrToInt(Bits[2], B) then Exit;
      if not StrToCard(Bits[3], C) then Exit;
      if not TryStrToInt(Bits[4], Bt) or (Bt < 0) or (Bt > 2) then Exit;
      if (Bits[5] <> '0') and (Bits[5] <> '1') then Exit;
      if not TryStrToInt(Bits[6], Pv) then Exit;
      M[I].Kind := mkRemove;
      M[I].A := A - 2;
      M[I].B := B - 2;
      M[I].WasteCard := C;
      M[I].Bites := Bt;
      M[I].Broke := Bits[5] = '1';
      M[I].PrevStreak := Pv;
    end
    else Exit;
  end;
  Result := True;
end;

function HandToText(const H: TSavedHand; const Stamp: string): string;
var
  L: TStringList;
  I, Left: Integer;
  Tab: TCardArray;
begin
  L := TStringList.Create;
  try
    Left := 0;
    SetLength(Tab, PyramidSize);
    for I := 0 to PyramidSize - 1 do
    begin
      Tab[I] := H.Game.Tableau[I];
      if not H.Game.Removed[I] then Inc(Left);
    end;
    L.Add(Magic);
    L.Add('saved=' + Stamp);
    L.Add('left=' + IntToStr(Left));
    L.Add('id=' + IntToStr(H.Game.HandId));
    L.Add('max=' + IntToStr(H.Game.MaxRecycles));
    L.Add('recycled=' + IntToStr(H.Game.Recycled));
    L.Add('easy=' + Flag(H.Game.UnderPairs));
    L.Add('hazard=' + IntToStr(H.Game.Hazard));
    L.Add('revealed=' + Flag(H.Game.Revealed));
    L.Add('stakes=' + IntToStr(H.Game.Stakes));
    L.Add('draws=' + IntToStr(H.Game.Draws));
    L.Add(Format('streak=%d %d', [H.Game.Streak, H.Game.BestStreak]));
    L.Add('wastegone=' + IntToStr(H.Game.WasteGone));
    L.Add('breakused=' + Flag(H.Game.BreakUsed));
    L.Add('tableau=' + CardsToStr(Tab));
    L.Add('removed=' + BitsToStr(H.Game.Removed));
    L.Add('marks=' + MarksToStr(H.Game.Marks));
    L.Add('stock=' + CardsToStr(H.Game.Stock));
    L.Add('waste=' + CardsToStr(H.Game.Waste));
    L.Add('eaten=' + CardsToStr(H.Game.Eaten));
    L.Add('misses=' + IntToStr(H.Misses));
    L.Add('bites=' + IntToStr(H.Bites));
    L.Add(Format('forgiven=%d %d', [H.ForgivenBite, H.ForgivenMiss]));
    L.Add('freehint=' + Flag(H.FreeHintUsed));
    L.Add('undo=' + MovesToStr(H.Game.History));
    Result := L.Text;
  finally
    L.Free;
  end;
end;

{ Reads N whitespace-separated integers. }
function ParseInts(const S: string; N: Integer; out V: array of Integer): Boolean;
var
  Parts: array[0..9] of string;
  NP, I: Integer;
begin
  Result := False;
  Split(S, ' ', Parts, NP);
  if NP <> N then Exit;
  for I := 0 to N - 1 do
    if not TryStrToInt(Parts[I], V[I]) then Exit;
  Result := True;
end;

function TextToHand(const Text: string; out H: TSavedHand; out Stamp: string): Boolean;
var
  L: TStringList;
  Tab: TCardArray;
  Nums: array[0..3] of Integer;
  I, Id: Integer;

  function Flag01(const Key: string; out V: Boolean): Boolean;
  var
    T: string;
  begin
    T := L.Values[Key];
    Result := (T = '0') or (T = '1');
    if Result then V := T = '1';
  end;

begin
  Result := False;
  Stamp := '';
  H := Default(TSavedHand);
  H.Game.Stock := nil;
  H.Game.Waste := nil;
  H.Game.Eaten := nil;
  H.Game.History := nil;
  L := TStringList.Create;
  try
    L.Text := Text;
    if (L.Count = 0) or (Trim(L[0]) <> Magic) then Exit;
    Stamp := L.Values['saved'];
    if not TryStrToInt(L.Values['id'], Id) then Exit;
    if Id <= 0 then Exit;
    H.Game.HandId := Id;
    if not TryStrToInt(L.Values['max'], H.Game.MaxRecycles) then Exit;
    if not TryStrToInt(L.Values['recycled'], H.Game.Recycled) then Exit;
    if not Flag01('easy', H.Game.UnderPairs) then Exit;
    if not TryStrToInt(L.Values['hazard'], H.Game.Hazard) then Exit;
    if not Flag01('revealed', H.Game.Revealed) then Exit;
    if not TryStrToInt(L.Values['stakes'], H.Game.Stakes) then Exit;
    if not TryStrToInt(L.Values['draws'], H.Game.Draws) then Exit;
    if not ParseInts(L.Values['streak'], 2, Nums) then Exit;
    H.Game.Streak := Nums[0];
    H.Game.BestStreak := Nums[1];
    if not TryStrToInt(L.Values['wastegone'], H.Game.WasteGone) then Exit;
    if not Flag01('breakused', H.Game.BreakUsed) then Exit;
    if not StrToCards(L.Values['tableau'], Tab) then Exit;
    if Length(Tab) <> PyramidSize then Exit;
    for I := 0 to PyramidSize - 1 do H.Game.Tableau[I] := Tab[I];
    if not StrToBits(L.Values['removed'], H.Game.Removed) then Exit;
    if not StrToMarks(L.Values['marks'], H.Game.Marks) then Exit;
    if L.IndexOfName('stock') < 0 then Exit;         { an empty pile is legal; a missing line is not }
    if not StrToCards(L.Values['stock'], H.Game.Stock) then Exit;
    if L.IndexOfName('waste') < 0 then Exit;
    if not StrToCards(L.Values['waste'], H.Game.Waste) then Exit;
    if L.IndexOfName('eaten') < 0 then Exit;
    if not StrToCards(L.Values['eaten'], H.Game.Eaten) then Exit;
    if not TryStrToInt(L.Values['misses'], H.Misses) then Exit;
    if not TryStrToInt(L.Values['bites'], H.Bites) then Exit;
    if (H.Misses < 0) or (H.Bites < 0) then Exit;
    if not ParseInts(L.Values['forgiven'], 2, Nums) then Exit;
    H.ForgivenBite := Nums[0];
    H.ForgivenMiss := Nums[1];
    if not Flag01('freehint', H.FreeHintUsed) then Exit;
    if L.IndexOfName('undo') < 0 then Exit;
    if not StrToMoves(L.Values['undo'], H.Game.History) then Exit;
    Result := True;
  finally
    L.Free;
  end;
end;

function WriteHandFile(const FileName: string; const H: TSavedHand): Boolean;
begin
  Result := StoreWrite(FileName, HandToText(H, FormatDateTime('yyyy-mm-dd hh:nn', Now)));
end;

function ReadHandFile(const FileName: string; out H: TSavedHand): Boolean;
var
  Text, Stamp: string;
begin
  Result := False;
  H := Default(TSavedHand);
  if not StoreRead(FileName, Text) then Exit;
  Result := TextToHand(Text, H, Stamp);
end;

function PeekHandFile(const FileName: string): TSlotInfo;
var
  H: TSavedHand;
  L: TStringList;
  Text, Stamp: string;
begin
  Result.Exists := False;
  Result.CardsLeft := 0;
  Result.Stamp := '';
  if not StoreRead(FileName, Text) then Exit;
  L := TStringList.Create;
  try
    L.Text := Text;
    if TextToHand(Text, H, Stamp) then      { only a readable file counts as a save }
    begin
      Result.Exists := True;
      Result.Stamp := Stamp;
      Result.CardsLeft := StrToIntDef(L.Values['left'], 0);
    end;
  finally
    L.Free;
  end;
end;

procedure DeleteHandFile(const FileName: string);
begin
  StoreDelete(FileName);
end;

procedure DeleteInDir(const Dir, Name: string);
begin
  StoreDelete(IncludeTrailingPathDelimiter(Dir) + Name);      { and its temporary copy }
end;

procedure DeleteAllSavedHands(const Dir: string);
var
  N: Integer;
begin
  DeleteInDir(Dir, ExtractFileName(AutoSaveFile(gmFreePlay)));
  DeleteInDir(Dir, ExtractFileName(AutoSaveFile(gmCampaign)));
  for N := 1 to SlotCount do
  begin
    DeleteInDir(Dir, ExtractFileName(SlotFile(N)));
    DeleteInDir(Dir, Format('campaignslot%d.save', [N]));     { the campaign's slots (see CampaignSlots) }
  end;
end;

procedure DeleteCampaignHand(const Dir: string);
begin
  DeleteInDir(Dir, ExtractFileName(AutoSaveFile(gmCampaign)));
end;

function AutoSaveFile(AMode: TGameMode): string;
begin
  if AMode = gmCampaign then
    Result := StoreName('campaign.hand')
  else
    Result := StoreName('freeplay.hand');
end;

function SlotFile(N: Integer): string;
begin
  Result := StoreName(Format('slot%d.hand', [N]));
end;

end.
