program testtrophies;

{ The trophies: what is earned, what is saved, who gets what from old records,
  where the shelf sits in each kind of panel, and the lost-hand count that the
  flawless trophy depends on. }

{$mode objfpc}{$H+}

uses SysUtils, Classes, Types, Storage, Records, Vampires, Campaign, Story, Trophies
  {$IFDEF PAS2JS}, JsCompat{$ENDIF};

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

function StoryPath: string;
begin
{$IFDEF PAS2JS}
  Result := 'assets/story/story.ini';          { run from the project folder }
{$ELSE}
  Result := ExtractFilePath(ParamStr(0)) + '../assets/story/story.ini';
{$ENDIF}
end;

function Inside(const R, Outer: TRect): Boolean;
begin
  Result := (R.Left >= Outer.Left) and (R.Right <= Outer.Right)
    and (R.Top >= Outer.Top) and (R.Bottom <= Outer.Bottom);
end;

procedure TestTrophySet;
var
  F: string;
  T, T2: TTrophies;
  K: TTrophy;
begin
  F := GetTempDir + 'tiepair_test_trophies.ini';
  StoreDelete(F);
  T := TTrophies.Create(F);
  try
    Check(T.IsNew and (T.Count = 0), 'no file: new, nothing earned');
    Check(not T.Has(trFirstWin), 'nothing yet');
    Check(T.Award(trFirstWin), 'the first time it is earned');
    Check(not T.Award(trFirstWin), 'and not again');
    Check(T.Has(trFirstWin) and (T.Count = 1), 'one trophy');
    Check(not T.IsNew, 'saving makes it a file');
    T.Award(trVampire2);
  finally
    T.Free;
  end;
  T2 := TTrophies.Create(F);
  try
    Check(not T2.IsNew and (T2.Count = 2), 'both are on disk');
    Check(T2.Has(trFirstWin) and T2.Has(trVampire2) and not T2.Has(trPerfect), 'the right two');
    T2.Reset;
    Check(T2.Count = 0, 'reset: all gone');
  finally
    T2.Free;
  end;
  T2 := TTrophies.Create(F);
  try
    Check((T2.Count = 0) and not T2.IsNew, 'reset is saved too (a file with nothing in it)');
  finally
    T2.Free;
  end;
  StoreDelete(F);
  Check(TrophyForVampire(0) = trVampire0, 'the first vampire''s');
  Check(TrophyForVampire(VampireCount - 1) = trVampire2, 'and the last');
  for K := Low(TTrophy) to High(TTrophy) do
    Check(TrophyKeys[K] <> '', 'every trophy has a key');
end;

{ A player who already won before trophies existed is given what the records prove. }
procedure TestSeeding;
var
  F: string;
  R: TRecords;
  T: TTrophies;
begin
  F := GetTempDir + 'tiepair_test_trophies_seed.ini';
  StoreDelete(F);
  R := TRecords.Create('');
  try
    T := TTrophies.Create(F);
    try
      Check(T.SeedFrom(R, 0) = 0, 'a brand-new player gets nothing');
      Check(not T.IsNew, 'but it is now saved: never seeded again');
    finally
      T.Free;
    end;
    StoreDelete(F);

    R.FreePlayWon(9, 0);                      { a perfect Free Play win }
    R.FreePlayWon(9, 3);
    R.CampaignKill(0, 1);                     { the first vampire killed after one lost hand }
    T := TTrophies.Create(F);
    try
      Check(T.SeedFrom(R, 1) = 3, 'a win, a perfect hand and a vampire: three');
      Check(T.Has(trFirstWin) and T.Has(trPerfect) and T.Has(trVampire0), 'those three');
      Check(not T.Has(trVampire1) and not T.Has(trFlawless), 'not the rest');
      Check(T.SeedFrom(R, 1) = 0, 'and only once');
    finally
      T.Free;
    end;
    StoreDelete(F);

    { the campaign's own count counts too (records may have been erased), and flawless never comes from history }
    R.Reset;
    T := TTrophies.Create(F);
    try
      T.SeedFrom(R, 3);
      Check(T.Has(trVampire0) and T.Has(trVampire1) and T.Has(trVampire2), 'three vampires past: all three trophies');
      Check(not T.Has(trFlawless), 'but history cannot prove a flawless run');
      Check(not T.Has(trFirstWin), 'and no records means no first win');
    finally
      T.Free;
    end;
    StoreDelete(F);

    { an existing file is left alone }
    T := TTrophies.Create(F);
    T.Award(trPerfect);
    T.Free;
    R.FreePlayWon(9, 0);
    T := TTrophies.Create(F);
    try
      Check(T.SeedFrom(R, 3) = 0, 'a player who already has a trophies file is not seeded');
      Check(T.Count = 1, 'and keeps just what they had');
    finally
      T.Free;
    end;
  finally
    R.Free;
    StoreDelete(F);
  end;
end;

procedure CheckShelf(const Name: string; const Panel: TRect; Strip, WantChip: Boolean);
var
  L: TTrophyLayout;
  I: Integer;
begin
  L := TrophyLayoutFor(Panel, Strip);
  Check(L.Shelf.Right > L.Shelf.Left, Name + ': there is a shelf');
  Check(Inside(L.Shelf, Panel), Name + ': it is inside the panel');
  Check(L.Reserved > 0, Name + ': it reserves some height');
  Check(L.Chip = WantChip, Name + ': ' + IntToStr(Ord(L.Chip)) + ' chip');
  if not L.Chip then
    for I := 0 to TrophyCount - 1 do
    begin
      Check(Inside(L.Slots[I], L.Shelf), Name + ': slot ' + IntToStr(I) + ' is on the shelf');
      Check(L.Slots[I].Right - L.Slots[I].Left >= 16, Name + ': slot ' + IntToStr(I) + ' is big enough to read');
      Check(L.Slots[I].Bottom - L.Slots[I].Top = L.Slots[I].Right - L.Slots[I].Left, Name + ': slot ' + IntToStr(I) + ' is square');
      if I > 0 then
        Check(L.Slots[I].Left >= L.Slots[I - 1].Right, Name + ': slot ' + IntToStr(I) + ' is beside the one before');
    end;
end;

procedure TestShelf;
var
  L: TTrophyLayout;
begin
  CheckShelf('desktop column', Rect(12, 12, 312, 590), False, False);
  CheckShelf('narrow column', Rect(8, 8, 178, 400), False, False);
  CheckShelf('a short tall column', Rect(8, 8, 220, 700), False, False);
  CheckShelf('iPad strip', Rect(6, 600, 762, 920), True, False);
  CheckShelf('phone strip', Rect(4, 560, 371, 800), True, True);
  L := TrophyLayoutFor(Rect(0, 0, 0, 0), False);
  Check(L.Reserved = 0, 'no panel, no shelf');
  { the column's shelf is at the foot of the panel, and its reserved height covers it }
  L := TrophyLayoutFor(Rect(12, 12, 312, 590), False);
  Check(L.Shelf.Bottom < 590, 'there is padding under the shelf');
  Check(L.Reserved >= 590 - L.Shelf.Top - 30, 'the reserved height covers the shelf');
end;

procedure TestLostAll;
var
  C, C2: TCampaign;
  Old: string;
begin
  C := TCampaign.Create('');
  C2 := TCampaign.Create('');
  try
    Check(C.LostAll = 0, 'a new campaign has lost nothing');
    C.AddLostHand;
    C.AddLostHand;
    Check((C.LostAll = 2) and (C.TotalLost = 2), 'two lost hands');
    C.Advance;
    Check((C.TotalLost = 0) and (C.LostAll = 2), 'the next vampire starts at zero but the campaign remembers');
    C.AddLostHand;
    Check(C.LostAll = 3, 'and goes on counting');
    C2.ImportText(C.ExportText);
    Check(C2.LostAll = 3, 'a save slot keeps it');
    C.Reset;
    Check(C.LostAll = 0, 'a new campaign starts again');
    { a campaign file from before this was counted: it cannot prove a flawless run }
    Old := '[Campaign]' + LineEnding + 'Current=1' + LineEnding + 'Wins=2' + LineEnding;
    C2.ImportText(Old);
    Check(C2.LostAll >= 1, 'an old file part-way through is not flawless');
    C2.ImportText('[Campaign]' + LineEnding + 'Current=0' + LineEnding);
    Check(C2.LostAll = 0, 'but an old file at the very start is');
  finally
    C.Free;
    C2.Free;
  end;
end;

procedure TestTrophyText;
var
  St: TStory;
  K: TTrophy;
  Bad: TStringArray;
  Line: string;
begin
  St := TStory.Create;
  try
    St.LoadFromFile(StoryPath);
    Bad := St.Validate;
    Check(Length(Bad) = 0, 'the story file has everything it needs, including the trophies');
    for K := Low(TTrophy) to High(TTrophy) do
    begin
      Check(St.TrophyName(TrophyKeys[K]) <> '', TrophyKeys[K] + ' has a name');
      Check(St.TrophyHow(TrophyKeys[K]) <> '', TrophyKeys[K] + ' says how to earn it');
      Check(St.TrophyLine(TrophyKeys[K]) <> '', TrophyKeys[K] + ' has its words');
    end;
    { the three for any player stay free of he and she }
    for K in [trFirstWin, trPerfect, trFlawless] do
    begin
      Line := ' ' + LowerCase(St.TrophyLine(TrophyKeys[K]) + ' ' + St.TrophyHow(TrophyKeys[K])) + ' ';
      Check((Pos(' he ', Line) = 0) and (Pos(' she ', Line) = 0) and (Pos(' his ', Line) = 0)
        and (Pos(' her ', Line) = 0), TrophyKeys[K] + ' is neutral');
    end;
  finally
    St.Free;
  end;
end;

begin
  CrossCardsOn := False;
  TestTrophySet;
  TestSeeding;
  TestShelf;
  TestLostAll;
  TestTrophyText;
  if Failures = 0 then WriteLn('ALL TROPHY TESTS PASSED')
  else
  begin
    WriteLn(Failures, ' FAILURES');
    Halt(1);
  end;
end.
