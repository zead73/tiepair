program TestStartOver;

{$mode objfpc}{$H+}

uses SysUtils, Classes, Inventory, Session, Campaign, Settings, HandFile, StartOver, Records, Trophies{$IFDEF PAS2JS}, JsCompat{$ENDIF};

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

procedure Touch(const FileName, Text: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Text := Text;
    L.SaveToFile(FileName);
  finally
    L.Free;
  end;
end;

{ A folder shaped like a played-in config folder. }
function MakeDir: string;
var
  N: Integer;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir) + 'tiepair_test_startover' + PathDelim;
  ForceDirectories(Result);
  Touch(Result + 'freeplay.hand', 'x');
  Touch(Result + 'freeplay.hand.tmp', 'x');
  Touch(Result + 'campaign.hand', 'x');
  for N := 1 to SlotCount do Touch(Result + Format('slot%d.hand', [N]), 'x');
  for N := 1 to SlotCount do Touch(Result + Format('campaignslot%d.save', [N]), 'x');
  Touch(Result + 'deal.wav', 'sound');                 { not the game's save data }
  Touch(Result + 'notes.txt', 'someone else''s file');
  Touch(Result + 'slot4.hand', 'not one of ours');
end;

procedure CleanDir(const Dir: string);
{$IFDEF PAS2JS}
var
  N: Integer;
begin
  { no folder listing on the web: remove the names the tests make }
  DeleteFile(Dir + 'freeplay.hand');
  DeleteFile(Dir + 'campaign.hand');
  for N := 1 to SlotCount + 1 do DeleteFile(Dir + Format('slot%d.hand', [N]));
  for N := 1 to SlotCount do DeleteFile(Dir + Format('campaignslot%d.save', [N]));
  DeleteFile(Dir + 'deal.wav');
  DeleteFile(Dir + 'notes.txt');
  RemoveDir(Dir);
end;
{$ELSE}
var
  SR: TSearchRec;
begin
  if FindFirst(Dir + '*', faAnyFile, SR) = 0 then
  begin
    repeat
      if (SR.Attr and faDirectory) = 0 then DeleteFile(Dir + SR.Name);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  RemoveDir(Dir);
end;
{$ENDIF}

function Exists(const Dir, Name: string): Boolean;
begin
  Result := FileExists(Dir + Name);
end;

procedure TestEraseEverything;
var
  Dir, FI, FC, FS: string;
  S: TGameSession;
  C: TCampaign;
  St: TSettings;
  S2: TGameSession;
  C2: TCampaign;
  St2: TSettings;
  N: Integer;
  Rec: TRecords;
  Tro: TTrophies;
begin
  Dir := MakeDir;
  Rec := TRecords.Create(Dir + 'records.ini');
  Tro := TTrophies.Create(Dir + 'trophies.ini');
  FI := Dir + 'inventory.ini';
  FC := Dir + 'campaign.ini';
  FS := Dir + 'settings.ini';
  S := TGameSession.Create(FI);
  C := TCampaign.Create(FC);
  St := TSettings.Create(FS);
  try
    { a well-played game, with a record to its name }
    Rec.FreePlayWon(9, 0);
    Rec.SetHolders([rcFreeStreak], 'ABC');
    S.Inventory.AddCoins(500);
    S.Inventory.AddUndoCards(7);
    S.Inventory.AddHintCards(9);
    S.Inventory.MarkHandPaid(12345);
    S.SaveNow;
    C.Advance;
    C.RecordWin; C.RecordWin;
    C.AddLostHand;
    C.MarkPremiseSeen;
    St.Mode := gmCampaign;
    St.Save;

    Tro.Award(trFirstWin);
    Tro.Award(trVampire1);
    EraseEverything(S, C, St, Rec, Tro, Dir);
    Check(not Rec.IsSet(rcFreeStreak) and (Rec.FreeWins = 0), 'the personal records are erased too');
    Check((Tro.Count = 0) and not Tro.Has(trFirstWin), 'and the trophies');
    Check(TTrophies.Create(Dir + 'trophies.ini').Count = 0, 'saved: no trophies');

    Check(S.Inventory.Coins = StartingCoins, 'coins are back to the starting amount');
    Check((S.Inventory.UndoCards = 0) and (S.Inventory.HintCards = 0), 'no undo or hint cards');
    Check(not S.Inventory.HandPaid(12345), 'no hand is remembered as paid');
    Check((C.Current = 0) and (C.LostHands = 0) and (C.Wins = 0) and not C.PremiseSeen and not C.IsComplete,
      'the campaign is back at the start (no wins), with its opening to be shown again');
    Check(St.Mode = gmFreePlay, 'the mode is Free Play');
    for N := 1 to SlotCount do
      Check(not Exists(Dir, Format('slot%d.hand', [N])), 'slot ' + IntToStr(N) + ' is erased');
      Check(not Exists(Dir, Format('campaignslot%d.save', [N])), 'campaign slot ' + IntToStr(N) + ' is erased');
    Check(not Exists(Dir, 'freeplay.hand'), 'the Free Play autosave is erased');
    Check(not Exists(Dir, 'campaign.hand'), 'the duel autosave is erased');
    Check(not Exists(Dir, 'freeplay.hand.tmp'), 'leftover temporary files are erased');

    { nothing that is not the game's own is touched }
    Check(Exists(Dir, 'notes.txt'), 'an unrelated file in the folder survives');
    Check(Exists(Dir, 'deal.wav'), 'the sound cache survives');
    Check(Exists(Dir, 'slot4.hand'), 'a file that merely looks like a slot survives');

    { and it really is on disk: a fresh start would see a new player }
    S2 := TGameSession.Create(FI);
    C2 := TCampaign.Create(FC);
    St2 := TSettings.Create(FS);
    try
      Check(S2.Inventory.Coins = StartingCoins, 'saved: starting coins');
      Check((S2.Inventory.UndoCards = 0) and (S2.Inventory.HintCards = 0), 'saved: no cards');
      Check(not S2.Inventory.HandPaid(12345), 'saved: no paid hands');
      Check((C2.Current = 0) and not C2.PremiseSeen, 'saved: campaign at the start');
      Check(St2.Mode = gmFreePlay, 'saved: Free Play');
    finally
      St2.Free; C2.Free; S2.Free;
    end;

    { erasing when there is nothing to erase is fine }
    EraseEverything(S, C, St, Rec, Tro, Dir);
    Check(S.Inventory.Coins = StartingCoins, 'erasing twice is harmless');
  finally
    Tro.Free; Rec.Free; St.Free; C.Free; S.Free;
    CleanDir(Dir);
  end;
end;

procedure TestRestartCampaign;
var
  Dir, FI, FC: string;
  S: TGameSession;
  C: TCampaign;
  C2: TCampaign;
begin
  Dir := MakeDir;
  FI := Dir + 'inventory.ini';
  FC := Dir + 'campaign.ini';
  S := TGameSession.Create(FI);
  C := TCampaign.Create(FC);
  try
    S.Inventory.AddCoins(500);
    S.Inventory.AddUndoCards(4);
    S.SaveNow;
    C.Advance;
    C.RecordWin; C.RecordWin; C.RecordWin;
    C.AddLostHand;
    C.MarkPremiseSeen;

    RestartCampaignOnly(C, Dir);

    Check((C.Current = 0) and (C.LostHands = 0) and (C.Wins = 0) and not C.PremiseSeen, 'the campaign starts over, wins and all');
    C2 := TCampaign.Create(FC);
    try
      Check((C2.Current = 0) and (C2.Wins = 0) and not C2.PremiseSeen, 'and that is saved');
    finally
      C2.Free;
    end;
    Check(S.Inventory.Coins = StartingCoins + 500, 'coins are kept');
    Check(S.Inventory.UndoCards = 4, 'cards are kept');
    Check(not Exists(Dir, 'campaign.hand'), 'a half-played duel hand is discarded');
    Check(Exists(Dir, 'freeplay.hand'), 'the Free Play hand is kept');
    Check(Exists(Dir, 'slot1.hand') and Exists(Dir, 'slot3.hand'), 'the manual slots are kept');
    Check(Exists(Dir, 'campaignslot1.save') and Exists(Dir, 'campaignslot3.save'), 'and so are the campaign slots (they hold their own progress)');
    Check(Exists(Dir, 'notes.txt'), 'unrelated files are untouched');
  finally
    C.Free; S.Free;
    CleanDir(Dir);
  end;
end;

procedure TestOnlyTheGivenFolder;
var
  A, B: string;
begin
  A := MakeDir;
  B := IncludeTrailingPathDelimiter(GetTempDir) + 'tiepair_test_startover_other' + PathDelim;
  ForceDirectories(B);
  Touch(B + 'freeplay.hand', 'other folder');
  Touch(B + 'slot1.hand', 'other folder');
  try
    DeleteAllSavedHands(A);
    Check(not Exists(A, 'freeplay.hand') and not Exists(A, 'slot2.hand'), 'the named folder is cleared');
    Check(Exists(B, 'freeplay.hand') and Exists(B, 'slot1.hand'), 'another folder is not touched');
    DeleteAllSavedHands(A + 'does_not_exist' + PathDelim);   { a missing folder is fine too }
    Check(True, 'a missing folder does not raise');
  finally
    CleanDir(A);
    CleanDir(B);
  end;
end;

begin
  CrossCardsOn := False;                  { where the silver cross lies is random: it has its own tests }
  TestEraseEverything;
  TestRestartCampaign;
  TestOnlyTheGivenFolder;
  if Failures = 0 then WriteLn('ALL START-OVER TESTS PASSED') else
  begin
    WriteLn(Failures, ' FAILURES');
    Halt(1);
  end;
end.
