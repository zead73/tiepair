program TestRecords;

{ The personal records: what breaks a record, the counts, the holders' initials,
  and saving and loading. }

{$mode objfpc}{$H+}

uses SysUtils, Classes, Vampires, Records{$IFDEF PAS2JS}, JsCompat{$ENDIF};

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

procedure TestFreePlay;
var
  R: TRecords;
  B: TRecordSet;
begin
  R := TRecords.Create('');
  try
    Check(not R.IsSet(rcFreeStreak) and not R.IsSet(rcFreeRun) and not R.IsSet(rcCampStreak), 'nothing is set at the start');
    Check((R.FreeWins = 0) and (R.FreePerfect = 0) and (R.FreeRun = 0), 'and the counts are zero');
    Check(R.ValueText(rcFreeStreak) = '-', 'an unset record shows a dash');

    B := R.FreePlayWon(5, 2);
    Check(B = [rcFreeStreak, rcFreeRun], 'the first win sets both records');
    Check((R.Value(rcFreeStreak) = 5) and (R.Value(rcFreeRun) = 1), 'with their values');
    Check((R.FreeWins = 1) and (R.FreePerfect = 0) and (R.FreeRun = 1), 'one win, not perfect');

    B := R.FreePlayWon(4, 0);
    Check(B = [rcFreeRun], 'a lower streak breaks nothing, but the run of two does');
    Check((R.Value(rcFreeStreak) = 5) and (R.Value(rcFreeRun) = 2), 'the streak record stays');
    Check((R.FreePerfect = 1) and (R.FreeWins = 2), 'no missed moves is a perfect hand');

    B := R.FreePlayWon(5, 3);
    Check(B = [rcFreeRun], 'an equal streak is not a new record');
    B := R.FreePlayWon(9, 1);
    Check(B = [rcFreeStreak, rcFreeRun], 'a longer streak and a longer run');
    Check((R.Value(rcFreeStreak) = 9) and (R.Value(rcFreeRun) = 4), 'values updated');

    R.FreePlayAbandoned;
    Check(R.FreeRun = 0, 'dropping a hand ends the run');
    B := R.FreePlayWon(0, 0);
    Check(not (rcFreeStreak in B) and (R.Value(rcFreeStreak) = 9), 'a streak of nothing (won with special cards alone) is no record');
    R.FreePlayAbandoned;
    Check(R.Value(rcFreeRun) = 4, 'but the record stays');
    R.FreePlayAbandoned;
    Check(R.FreeRun = 0, 'dropping again is harmless');
    B := R.FreePlayWon(2, 0);
    Check(B = [], 'a new run of one beats nothing');
    Check((R.FreeRun = 1) and (R.FreeWins = 6), 'it starts again from one');
  finally
    R.Free;
  end;
end;

procedure TestCampaign;
var
  R: TRecords;
  B: TRecordSet;
begin
  R := TRecords.Create('');
  try
    B := R.CampaignHandWon(6);
    Check(B = [rcCampStreak], 'the first duel win sets the streak record');
    Check(R.CampaignHandWon(3) = [], 'a shorter streak does not');
    Check(R.CampaignHandWon(8) = [rcCampStreak], 'a longer one does');
    Check(R.CampaignWins = 3, 'hands won are counted');
    Check(R.FreeWins = 0, 'and Free Play is separate');

    Check(R.CampaignKill(0, 3) = [rcFewestLost0], 'beating Jack sets his record');
    Check(R.Value(FewestLostId(0)) = 3, 'at three lost hands');
    Check(R.CampaignKill(0, 5) = [], 'more lost hands is not better');
    Check(R.CampaignKill(0, 3) = [], 'the same is not a record');
    Check(R.CampaignKill(0, 0) = [rcFewestLost0], 'none lost is the best');
    Check(R.Value(FewestLostId(0)) = 0, 'zero is a real value, not "unset"');
    Check(R.IsSet(FewestLostId(0)) and not R.IsSet(FewestLostId(1)), 'each vampire has his own');
    Check(R.CampaignKill(2, 1) = [rcFewestLost2], 'the King too');
    Check(R.CampaignKill(7, 0) = [], 'a vampire that does not exist is ignored');
    Check(R.CampaignKill(-1, 0) = [], 'so is a negative one');
    R.CampaignCompleted;
    R.CampaignCompleted;
    Check(R.CampaignsDone = 2, 'completed campaigns are counted');
  finally
    R.Free;
  end;
end;

procedure TestInitials;
var
  R: TRecords;
begin
  R := TRecords.Create('');
  try
    Check(TRecords.CleanInitials('a1b2c') = 'A1B', 'letters and digits, upper case, at most three');
    Check(TRecords.CleanInitials(' s-h ') = 'SH', 'spaces and symbols are dropped');
    Check(TRecords.CleanInitials('!!!') = '', 'nothing usable gives nothing');
    R.FreePlayWon(7, 0);
    Check(R.Holder(rcFreeStreak) = '', 'a new record has no holder yet');
    R.SetHolders([rcFreeStreak], 'sh');
    Check(R.Holder(rcFreeStreak) = 'SH', 'the initials are set');
    Check(R.Holder(rcFreeRun) = '', 'only for the records named');
    Check(R.LastInitials = 'SH', 'and remembered for next time');
    Check(R.ValueText(rcFreeStreak) = '7  SH', 'the value shows with the holder');
    R.FreePlayWon(9, 0);
    R.SetHolders([rcFreeStreak, rcFreeRun], '');
    Check(R.Holder(rcFreeStreak) = '---', 'skipping the question gives dashes');
    Check(R.LastInitials = 'SH', 'and does not replace the remembered initials');
    R.FreePlayWon(12, 0);
    Check(R.Holder(rcFreeStreak) = '', 'breaking a record clears the old holder until the new one is given');
  finally
    R.Free;
  end;
end;

procedure TestSaving;
var
  F: string;
  R, R2: TRecords;
  L: TStringList;
begin
  F := GetTempDir + 'tiepair_test_records.ini';
  if FileExists(F) then DeleteFile(F);
  R := TRecords.Create(F);
  try
    R.FreePlayWon(8, 0);
    R.SetHolders([rcFreeStreak, rcFreeRun], 'ab');
    R.CampaignHandWon(5);
    R.CampaignKill(1, 2);
    R.SetHolders([rcCampStreak, rcFewestLost1], 'cd');
    R.CampaignCompleted;
  finally
    R.Free;
  end;
  R2 := TRecords.Create(F);
  try
    Check((R2.Value(rcFreeStreak) = 8) and (R2.Holder(rcFreeStreak) = 'AB'), 'a record and its holder survive');
    Check((R2.Value(FewestLostId(1)) = 2) and (R2.Holder(FewestLostId(1)) = 'CD'), 'also a fewest-lost one');
    Check((R2.FreeWins = 1) and (R2.FreePerfect = 1) and (R2.FreeRun = 1) and (R2.CampaignWins = 1) and (R2.CampaignsDone = 1),
      'and the counts, including the current run');
    Check(R2.LastInitials = 'CD', 'and the last initials');
    R2.SetHolders([rcFreeRun], '');
    R2.Free;
    R2 := TRecords.Create(F);
    Check(R2.Holder(rcFreeRun) = '---', 'skipped initials (dashes) survive a restart');
    R2.Reset;
    Check(not R2.IsSet(rcFreeStreak) and (R2.FreeWins = 0) and (R2.LastInitials = ''), 'resetting clears everything');
  finally
    R2.Free;
  end;
  R2 := TRecords.Create(F);
  try
    Check(not R2.IsSet(rcFreeStreak) and (R2.FreeWins = 0), 'and that is saved');
  finally
    R2.Free;
  end;
  { a damaged file is made safe }
  L := TStringList.Create;
  try
    L.Text := '[Records]'#10'free.streak=-9'#10'free.streak.by=XY'#10'free.wins=-4'#10'camp.lost0=2'#10'camp.lost0.by=@@@'#10;
    L.SaveToFile(F);
  finally
    L.Free;
  end;
  R2 := TRecords.Create(F);
  try
    Check(not R2.IsSet(rcFreeStreak) and (R2.Holder(rcFreeStreak) = ''), 'a negative value is "unset" and has no holder');
    Check(R2.FreeWins = 0, 'a negative count is zero');
    Check((R2.Value(FewestLostId(0)) = 2) and (R2.Holder(FewestLostId(0)) = ''), 'unusable initials are dropped');
  finally
    R2.Free;
  end;
  DeleteFile(F);
end;

begin
  TestFreePlay;
  TestCampaign;
  TestInitials;
  TestSaving;
  if Failures = 0 then WriteLn('ALL RECORD TESTS PASSED') else
  begin
    WriteLn(Failures, ' FAILURES');
    Halt(1);
  end;
end.
