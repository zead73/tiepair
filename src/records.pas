unit Records;

{ The player's personal bests, kept in the per-user records file (on the web, in
  the browser's local storage). No window code. Only won hands count.

  Free Play:   longest streak in one hand, most wins in a row (a hand that is
               dropped or ends stuck breaks the run), perfect hands (no missed
               moves) and total wins as plain counts.
  Campaign:    longest streak in one hand, the fewest lost hands it took to beat
               each vampire, and counts of hands won and campaigns completed.

  A record has a holder: the initials the player gave when they broke it, so
  two people sharing a device can tell their bests apart. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, TextIni, Storage, Vampires;

type
  TRecordId = (rcFreeStreak, rcFreeRun, rcCampStreak,
    rcFewestLost0, rcFewestLost1, rcFewestLost2);   { one per vampire: see FewestLostId }

  TRecordSet = set of TRecordId;

const
  RecordCount = 6;

type
  TRecords = class
  private
    FFile: string;
    FValue: array[TRecordId] of Integer;            { -1 = not set yet }
    FHolder: array[TRecordId] of string;
    FFreeRun, FFreeWins, FFreePerfect: Integer;
    FCampWins, FCampaignsDone: Integer;
    FLastInitials: string;
    procedure ClearAll;
    function Better(Id: TRecordId; NewValue: Integer): Boolean;
    function Try_(Id: TRecordId; NewValue: Integer): TRecordSet;
  public
    { AFileName = '' means never load or save (used by tests). }
    constructor Create(const AFileName: string);
    procedure Reset;
    procedure Save;

    { A Free Play hand was won: BestStreak is its longest run of plays, Misses
      its missed moves. Returns the records it broke (or set for the first time). }
    function FreePlayWon(BestStreak, Misses: Integer): TRecordSet;
    { A Free Play hand was dropped (New Game, or stuck): the run of wins ends. }
    procedure FreePlayAbandoned;
    function CampaignHandWon(BestStreak: Integer): TRecordSet;
    { Vampire V was beaten after Lost hands lost against him. }
    function CampaignKill(V, Lost: Integer): TRecordSet;
    procedure CampaignCompleted;

    { Give the records just broken to a holder (initials; blank = '---'). Also
      remembers them as the default for next time. }
    procedure SetHolders(Ids: TRecordSet; const Initials: string);
    { What to offer as the initials next time. }
    property LastInitials: string read FLastInitials;
    { Letters and digits only, upper case, at most three; '' if nothing usable. }
    class function CleanInitials(const S: string): string;

    function IsSet(Id: TRecordId): Boolean;
    function Value(Id: TRecordId): Integer;
    function Holder(Id: TRecordId): string;
    function Title(Id: TRecordId): string;
    function Detail(Id: TRecordId): string;
    function ValueText(Id: TRecordId): string;       { "14 (SH)" or "-" }
    property FreeRun: Integer read FFreeRun;         { the current run of wins }
    property FreeWins: Integer read FFreeWins;
    property FreePerfect: Integer read FFreePerfect;
    property CampaignWins: Integer read FCampWins;
    property CampaignsDone: Integer read FCampaignsDone;
  end;

function FewestLostId(V: Integer): TRecordId;
function DefaultRecordsFile: string;

implementation

const
  Keys: array[TRecordId] of string =
    ('free.streak', 'free.run', 'camp.streak', 'camp.lost0', 'camp.lost1', 'camp.lost2');

function FewestLostId(V: Integer): TRecordId;
begin
  Result := TRecordId(Ord(rcFewestLost0) + V);
end;

function DefaultRecordsFile: string;
begin
  Result := StoreName('records.ini');
end;

constructor TRecords.Create(const AFileName: string);
var
  Ini: TTextIni;
  Text: string;
  Id: TRecordId;
begin
  inherited Create;
  FFile := AFileName;
  ClearAll;                                   { not Reset: that would save over the file }
  if (FFile <> '') and StoreRead(FFile, Text) then
  begin
    Ini := TTextIni.Create;
    try
      Ini.LoadFromText(Text);
      for Id := Low(TRecordId) to High(TRecordId) do
      begin
        FValue[Id] := Ini.ReadInteger('Records', Keys[Id], -1);
        if FValue[Id] < -1 then FValue[Id] := -1;
        FHolder[Id] := Ini.ReadString('Records', Keys[Id] + '.by', '');
        if FHolder[Id] <> '---' then FHolder[Id] := CleanInitials(FHolder[Id]);   { '---' = skipped }
        if FValue[Id] < 0 then FHolder[Id] := '';
      end;
      FFreeRun := Ini.ReadInteger('Records', 'free.currentrun', 0);
      FFreeWins := Ini.ReadInteger('Records', 'free.wins', 0);
      FFreePerfect := Ini.ReadInteger('Records', 'free.perfect', 0);
      FCampWins := Ini.ReadInteger('Records', 'camp.wins', 0);
      FCampaignsDone := Ini.ReadInteger('Records', 'camp.completed', 0);
      FLastInitials := CleanInitials(Ini.ReadString('Records', 'initials', ''));
      if FFreeRun < 0 then FFreeRun := 0;
      if FFreeWins < 0 then FFreeWins := 0;
      if FFreePerfect < 0 then FFreePerfect := 0;
      if FCampWins < 0 then FCampWins := 0;
      if FCampaignsDone < 0 then FCampaignsDone := 0;
    finally
      Ini.Free;
    end;
  end;
end;

procedure TRecords.Reset;
begin
  ClearAll;
  Save;
end;

procedure TRecords.ClearAll;
var
  Id: TRecordId;
begin
  for Id := Low(TRecordId) to High(TRecordId) do
  begin
    FValue[Id] := -1;
    FHolder[Id] := '';
  end;
  FFreeRun := 0;
  FFreeWins := 0;
  FFreePerfect := 0;
  FCampWins := 0;
  FCampaignsDone := 0;
  FLastInitials := '';
end;

procedure TRecords.Save;
var
  Ini: TTextIni;
  Id: TRecordId;
begin
  if FFile = '' then Exit;
  Ini := TTextIni.Create;
  try
    for Id := Low(TRecordId) to High(TRecordId) do
    begin
      Ini.WriteInteger('Records', Keys[Id], FValue[Id]);
      Ini.WriteString('Records', Keys[Id] + '.by', FHolder[Id]);
    end;
    Ini.WriteInteger('Records', 'free.currentrun', FFreeRun);
    Ini.WriteInteger('Records', 'free.wins', FFreeWins);
    Ini.WriteInteger('Records', 'free.perfect', FFreePerfect);
    Ini.WriteInteger('Records', 'camp.wins', FCampWins);
    Ini.WriteInteger('Records', 'camp.completed', FCampaignsDone);
    Ini.WriteString('Records', 'initials', FLastInitials);
    StoreWrite(FFile, Ini.ToText);
  finally
    Ini.Free;
  end;
end;

class function TRecords.CleanInitials(const S: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := UpCase(S[I]);
    if ((C >= 'A') and (C <= 'Z')) or ((C >= '0') and (C <= '9')) then
    begin
      Result := Result + C;
      if Length(Result) = 3 then Break;
    end;
  end;
end;

function TRecords.Better(Id: TRecordId; NewValue: Integer): Boolean;
begin
  if NewValue < 0 then
    Result := False
  else if FValue[Id] < 0 then
    Result := True                              { the first time is a record }
  else if Id >= rcFewestLost0 then
    Result := NewValue < FValue[Id]             { fewer lost hands is better }
  else
    Result := NewValue > FValue[Id];
end;

function TRecords.Try_(Id: TRecordId; NewValue: Integer): TRecordSet;
begin
  Result := [];
  if Better(Id, NewValue) then
  begin
    FValue[Id] := NewValue;
    FHolder[Id] := '';                           { until the player gives initials }
    Result := [Id];
  end;
end;

function TRecords.FreePlayWon(BestStreak, Misses: Integer): TRecordSet;
begin
  Inc(FFreeWins);
  if Misses = 0 then Inc(FFreePerfect);
  Inc(FFreeRun);
  Result := Try_(rcFreeRun, FFreeRun);
  if BestStreak > 0 then Result := Result + Try_(rcFreeStreak, BestStreak);   { a hand won with special cards alone has none }
  Save;
end;

procedure TRecords.FreePlayAbandoned;
begin
  if FFreeRun = 0 then Exit;
  FFreeRun := 0;
  Save;
end;

function TRecords.CampaignHandWon(BestStreak: Integer): TRecordSet;
begin
  Inc(FCampWins);
  Result := [];
  if BestStreak > 0 then Result := Try_(rcCampStreak, BestStreak);
  Save;
end;

function TRecords.CampaignKill(V, Lost: Integer): TRecordSet;
begin
  Result := [];
  if (V < 0) or (V >= VampireCount) then Exit;
  Result := Try_(FewestLostId(V), Lost);
  Save;
end;

procedure TRecords.CampaignCompleted;
begin
  Inc(FCampaignsDone);
  Save;
end;

procedure TRecords.SetHolders(Ids: TRecordSet; const Initials: string);
var
  Id: TRecordId;
  S: string;
begin
  S := CleanInitials(Initials);
  if S = '' then S := '---';
  for Id := Low(TRecordId) to High(TRecordId) do
    if Id in Ids then FHolder[Id] := S;
  if S <> '---' then FLastInitials := S;
  Save;
end;

function TRecords.IsSet(Id: TRecordId): Boolean;
begin
  Result := FValue[Id] >= 0;
end;

function TRecords.Value(Id: TRecordId): Integer;
begin
  Result := FValue[Id];
end;

function TRecords.Holder(Id: TRecordId): string;
begin
  Result := FHolder[Id];
end;

function TRecords.Title(Id: TRecordId): string;
begin
  case Id of
    rcFreeStreak: Result := 'Longest streak';
    rcFreeRun: Result := 'Most wins in a row';
    rcCampStreak: Result := 'Longest streak';
  else
    Result := 'Fewest lost hands';
  end;
end;

function TRecords.Detail(Id: TRecordId): string;
begin
  case Id of
    rcFreeStreak, rcCampStreak: Result := 'Cards played in a row in one hand, without drawing.';
    rcFreeRun: Result := 'Hands won one after another (dropping a hand ends the run).';
  else
    Result := 'Hands lost before the vampire fell, for the best duel.';
  end;
end;

function TRecords.ValueText(Id: TRecordId): string;
begin
  if FValue[Id] < 0 then
    Result := '-'
  else
  begin
    Result := IntToStr(FValue[Id]);
    if FHolder[Id] <> '' then Result := Result + '  ' + FHolder[Id];
  end;
end;

end.
