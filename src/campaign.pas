unit Campaign;

{ Where the player is in the vampire campaign, saved between sessions. No
  window code. Stored next to the inventory in the per-user config folder. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, TextIni, Storage, Vampires;

var
  { The silver cross is only laid on the table when this is True. Tests switch
    it off, since where it lies is chosen at random. }
  CrossCardsOn: Boolean = True;

type
  TCampaign = class
  private
    FFile: string;
    FCurrent: Integer;
    FLostHands: Integer;
    FTotalLost: Integer;
    FLostAll: Integer;       { lost hands in the whole campaign so far (never reset by a kill) }
    FWins: Integer;
    FPremiseSeen: Boolean;
    FKillPending: Boolean;
    FCrossGame: Integer;     { which game of this duel (1..3) carries the silver cross; -1 = none or taken }
    FEase: Integer;          { hands still to be played at the lowest level: -1 until he falls, 0 none }
    FEaseLive: Boolean;      { the hand in progress was dealt at the lowest level }
    procedure PickCross;
    procedure EndEasedHand;
    procedure WriteFields(Ini: TTextIni);
  public
    { AFileName = '' means never load or save (used by tests). A missing or
      damaged file starts a fresh campaign. }
    constructor Create(const AFileName: string);
    procedure Reset;                 { start the campaign over }
    procedure Save;
    { The campaign's progress as text, and back (a save slot keeps it). }
    function ExportText: string;
    procedure ImportText(const Text: string);
    function IsComplete: Boolean;    { all vampires defeated }
    procedure AddLostHand;           { a hand was lost in the current duel }
    { A hand was won against the current vampire. Saved at once (before the
      reward is paid or any scene plays), so quitting cannot replay the win.
      Clears the lost-hand count: the cut only lasts until the next win.
      Returns True if this was the killing win (see RecordKill). }
    function RecordWin: Boolean;
    procedure Advance;               { the current vampire fell: on to the next }
    { The opening story has been shown (once per campaign, not per run). }
    procedure MarkPremiseSeen;
    { The current vampire was just killed (the fifth win). Saved at once, so
      quitting before the defeat scene ends cannot let you fight him again for a
      second reward: the next load moves on without it. RecordWin calls this. }
    procedure RecordKill;
    { ---- the silver cross (the Easy-Vampire card). Lying on one of the pyramid's cards in
      one of the first three games against the Queen and against the King, never
      in the fourth or fifth. Claimed with a Wild card, it drops the vampire to
      the lowest level from the next hand dealt: until the Queen falls, or for
      the next 2 hands against the King (won or lost). The game is chosen once,
      when the duel begins, and saved; a lost game's retry still carries it. ---- }
    function CrossOffered: Boolean;       { the hand about to be dealt carries the cross }
    function ClaimCross: Boolean;         { a Wild card took it: saved at once (False: not a duel that carries one) }
    procedure SetCrossGame(AGame: Integer);   { by hand, for tests (-1 = none) }
    { Called as a hand is dealt: True if it is played at the lowest level. }
    function BeginHand: Boolean;
    property CrossGame: Integer read FCrossGame;
    property Ease: Integer read FEase;
    property EaseLive: Boolean read FEaseLive;
    property Current: Integer read FCurrent;        { 0..VampireCount; = count when done }
    property LostHands: Integer read FLostHands;    { since the last win in the current duel }
    property LostAll: Integer read FLostAll;        { all duels together: 0 at the end earns the Flawless trophy }
    property TotalLost: Integer read FTotalLost;    { in the whole duel with this vampire (for Records) }
    property Wins: Integer read FWins;              { against the current vampire, 0..WinsToKill }
    property PremiseSeen: Boolean read FPremiseSeen;
  end;

{ Per-user save location (works on Linux and Windows). }
function DefaultCampaignFile: string;

implementation

constructor TCampaign.Create(const AFileName: string);
var
  Text: string;
begin
  inherited Create;
  FFile := AFileName;
  if (FFile <> '') and StoreRead(FFile, Text) then ImportText(Text);
end;

procedure TCampaign.ImportText(const Text: string);
var
  Ini: TTextIni;
begin
  begin
    Ini := TTextIni.Create;
    try
      Ini.LoadFromText(Text);
      FCurrent := Ini.ReadInteger('Campaign', 'Current', 0);
      FLostHands := Ini.ReadInteger('Campaign', 'LostHands', 0);
      FWins := Ini.ReadInteger('Campaign', 'Wins', 0);
      FTotalLost := Ini.ReadInteger('Campaign', 'TotalLost', 0);
      FLostAll := Ini.ReadInteger('Campaign', 'LostAll', -1);
      FPremiseSeen := Ini.ReadBool('Campaign', 'PremiseSeen', False);
      FKillPending := Ini.ReadBool('Campaign', 'KillPending', False);
      FCrossGame := Ini.ReadInteger('Campaign', 'CrossGame', -2);
      FEase := Ini.ReadInteger('Campaign', 'Ease', 0);
      FEaseLive := Ini.ReadBool('Campaign', 'EaseLive', False);
    finally
      Ini.Free;
    end;
    { guard against a damaged or hand-edited file }
    if FCurrent < 0 then FCurrent := 0;
    if FCurrent > VampireCount then FCurrent := VampireCount;
    if FLostHands < 0 then FLostHands := 0;
    if FWins < 0 then FWins := 0;
    if FTotalLost < 0 then FTotalLost := 0;
    if FLostAll < 0 then                      { a file from before this was counted }
    begin
      if (FCurrent > 0) or (FWins > 0) or (FTotalLost > 0) then
      begin
        FLostAll := FTotalLost;               { history unknown: it cannot prove a flawless run }
        if FLostAll < 1 then FLostAll := 1;
      end
      else
        FLostAll := 0;
    end;
    if (FEase < -1) or (FEase > 9) then FEase := 0;
    if (FCurrent < 1) or (FCurrent > 2) then
    begin
      FCrossGame := -1;
      FEase := 0;
      FEaseLive := False;
    end
    else if FCrossGame = -2 then PickCross                 { a file from before the cross }
    else if (FCrossGame < FWins + 1) or (FCrossGame > 3) then FCrossGame := -1;
    if FEase = 0 then FEaseLive := False;
    if FWins >= WinsToKill then FKillPending := True;   { a killing win is a pending kill }
    if FCurrent >= VampireCount then
    begin
      FLostHands := 0;
      FWins := 0;
      FTotalLost := 0;
    end;
    if FKillPending then Advance;       { he was killed last time: he stays dead }
  end;
end;

procedure TCampaign.Reset;
begin
  FCurrent := 0;
  FLostHands := 0;
  FTotalLost := 0;
  FLostAll := 0;
  FWins := 0;
  FPremiseSeen := False;
  FKillPending := False;
  FCrossGame := -1;
  FEase := 0;
  FEaseLive := False;
  Save;
end;

procedure TCampaign.WriteFields(Ini: TTextIni);
begin
  Ini.WriteInteger('Campaign', 'Current', FCurrent);
  Ini.WriteInteger('Campaign', 'LostHands', FLostHands);
  Ini.WriteInteger('Campaign', 'Wins', FWins);
  Ini.WriteInteger('Campaign', 'TotalLost', FTotalLost);
  Ini.WriteInteger('Campaign', 'LostAll', FLostAll);
  Ini.WriteBool('Campaign', 'PremiseSeen', FPremiseSeen);
  Ini.WriteBool('Campaign', 'KillPending', FKillPending);
  Ini.WriteInteger('Campaign', 'CrossGame', FCrossGame);
  Ini.WriteInteger('Campaign', 'Ease', FEase);
  Ini.WriteBool('Campaign', 'EaseLive', FEaseLive);
end;

function TCampaign.ExportText: string;
var
  Ini: TTextIni;
begin
  Ini := TTextIni.Create;
  try
    WriteFields(Ini);
    Result := Ini.ToText;
  finally
    Ini.Free;
  end;
end;

procedure TCampaign.Save;
var
  Ini: TTextIni;
  Text: string;
begin
  if FFile = '' then Exit;
  Ini := TTextIni.Create;
  try
    if StoreRead(FFile, Text) then Ini.LoadFromText(Text);    { keep entries we do not know }
    WriteFields(Ini);
    StoreWrite(FFile, Ini.ToText);
  finally
    Ini.Free;
  end;
end;

function TCampaign.IsComplete: Boolean;
begin
  Result := FCurrent >= VampireCount;
end;

procedure TCampaign.AddLostHand;
begin
  if IsComplete then Exit;
  EndEasedHand;
  Inc(FLostHands);
  Inc(FTotalLost);
  Inc(FLostAll);
  Save;
end;

function TCampaign.RecordWin: Boolean;
begin
  Result := False;
  if IsComplete then Exit;
  EndEasedHand;
  Inc(FWins);
  FLostHands := 0;
  if FWins >= WinsToKill then
  begin
    FWins := WinsToKill;
    Result := True;
    RecordKill;                          { saves too }
  end
  else
    Save;
end;

procedure TCampaign.RecordKill;
begin
  if IsComplete then Exit;
  FKillPending := True;
  Save;
end;

procedure TCampaign.Advance;
begin
  FKillPending := False;
  if IsComplete then
  begin
    Save;
    Exit;
  end;
  Inc(FCurrent);
  FLostHands := 0;
  FTotalLost := 0;
  FWins := 0;
  FEase := 0;                              { he is dead: the cross works no further }
  FEaseLive := False;
  PickCross;
  Save;
end;

{ The game (1..3) of this duel that carries the cross: chosen at random once, for
  the Queen and the King only. }
procedure TCampaign.PickCross;
begin
  FCrossGame := -1;
  if CrossCardsOn and (FCurrent >= 1) and (FCurrent <= 2) and (FWins < 3) then
    FCrossGame := FWins + 1 + Random(3 - FWins);
end;

procedure TCampaign.SetCrossGame(AGame: Integer);
begin
  FCrossGame := AGame;
end;

function TCampaign.CrossOffered: Boolean;
begin
  Result := CrossCardsOn and (FCurrent >= 1) and (FCurrent <= 2) and (FCrossGame >= 1)
    and (FWins + 1 = FCrossGame) and (FEase = 0);
end;

function TCampaign.ClaimCross: Boolean;
begin
  Result := (FCurrent >= 1) and (FCurrent <= 2);
  if not Result then Exit;
  FCrossGame := -1;
  FEase := VampireEaseHands[FCurrent];
  Save;
end;

function TCampaign.BeginHand: Boolean;
begin
  Result := FEase <> 0;
  if FEaseLive <> Result then
  begin
    FEaseLive := Result;
    Save;
  end;
end;

{ A hand ended (won, lost or given up): if it was dealt at the lowest level it
  uses up one of the hands the cross gave. }
procedure TCampaign.EndEasedHand;
begin
  if not FEaseLive then Exit;
  FEaseLive := False;
  if FEase > 0 then Dec(FEase);
end;

procedure TCampaign.MarkPremiseSeen;
begin
  if FPremiseSeen then Exit;
  FPremiseSeen := True;
  Save;
end;

function DefaultCampaignFile: string;
begin
  Result := StoreName('campaign.ini');
end;

end.
