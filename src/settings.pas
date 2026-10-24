unit Settings;

{ Small preferences that should be remembered between runs. No window code.
  Stored in the per-user config folder next to the inventory and campaign. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, TextIni, Storage, Campaign, Cosmetics;

type
  TGameMode = (gmFreePlay, gmCampaign);

  TSettings = class
  private
    FFile: string;
    FMode: TGameMode;
    FFenwickMet: Boolean;
    FEasyUnlocked: Boolean;
    FTurnsUnlocked: Boolean;
    FFreeEasy: Boolean;
    FBackKey, FClothKey, FMoonKey: string;
    FEquipped: string;
  public
    { AFileName = '' means never load or save (used by tests). A missing or
      unreadable file gives the defaults. }
    constructor Create(const AFileName: string);
    procedure Save;
    property Mode: TGameMode read FMode write FMode;    { the mode you were last in }
    { The player has had Fenwick's introduction in the Store (shown once). }
    property FenwickMet: Boolean read FFenwickMet write FFenwickMet;
    { The Store stocks the Easy rule card from the time the player first reaches
      a vampire without the Easy rule (and keeps it, even if the campaign is restarted). }
    property EasyUnlocked: Boolean read FEasyUnlocked write FEasyUnlocked;
    { Likewise the Extra turn card, from the first vampire with fewer turn-overs. }
    property TurnsUnlocked: Boolean read FTurnsUnlocked write FTurnsUnlocked;
    { Free Play: is the Easy rule (a card can go with the one card covering it) on? The campaign
      sets its own rules for each vampire. }
    property FreeEasy: Boolean read FFreeEasy write FFreeEasy;
    { The Style the player picked (a key from Cosmetics). Always check the player still
      has it: a loaded save or a hand-edited file may not. }
    property BackKey: string read FBackKey write FBackKey;
    property ClothKey: string read FClothKey write FClothKey;
    property MoonKey: string read FMoonKey write FMoonKey;
    procedure ResetStyle;             { back to the original look }
    { The relics equipped, as their keys with commas ('pick,locket'). Always check each is
      still owned and that they fit the slots: the game does, whenever it reads this. }
    property Equipped: string read FEquipped write FEquipped;
    procedure ResetRelics;
  end;

{ Per-user save location (works on Linux and Windows). }
function DefaultSettingsFile: string;

{ Should the game open straight into the campaign? Only if you were in it last
  time and it is not already finished (a finished campaign is never restarted
  for you: that is your choice, with the Campaign button). }
function ShouldResumeCampaign(ASettings: TSettings; ACampaign: TCampaign): Boolean;

implementation

constructor TSettings.Create(const AFileName: string);
var
  Ini: TTextIni;
  Text: string;
begin
  inherited Create;
  FFile := AFileName;
  FMode := gmFreePlay;
  ResetStyle;
  ResetRelics;
  if (FFile <> '') and StoreRead(FFile, Text) then
  begin
    Ini := TTextIni.Create;
    try
      Ini.LoadFromText(Text);
      if SameText(Ini.ReadString('Settings', 'Mode', 'FreePlay'), 'Campaign') then
        FMode := gmCampaign;                { anything else = Free Play }
      FFenwickMet := Ini.ReadBool('Settings', 'FenwickMet', False);
      FEasyUnlocked := Ini.ReadBool('Settings', 'EasyUnlocked', False);
      FTurnsUnlocked := Ini.ReadBool('Settings', 'TurnsUnlocked', False);
      FFreeEasy := Ini.ReadBool('Settings', 'FreeEasy', False);
      FBackKey := Ini.ReadString('Settings', 'Back', FBackKey);
      FClothKey := Ini.ReadString('Settings', 'Cloth', FClothKey);
      FMoonKey := Ini.ReadString('Settings', 'Moon', FMoonKey);
      FEquipped := Ini.ReadString('Settings', 'Relics', '');
    finally
      Ini.Free;
    end;
  end;
end;

procedure TSettings.Save;
var
  Ini: TTextIni;
  Text: string;
begin
  if FFile = '' then Exit;
  Ini := TTextIni.Create;
  try
    if StoreRead(FFile, Text) then Ini.LoadFromText(Text);
    if FMode = gmCampaign then
      Ini.WriteString('Settings', 'Mode', 'Campaign')
    else
      Ini.WriteString('Settings', 'Mode', 'FreePlay');
    Ini.WriteBool('Settings', 'FenwickMet', FFenwickMet);
    Ini.WriteBool('Settings', 'EasyUnlocked', FEasyUnlocked);
    Ini.WriteBool('Settings', 'TurnsUnlocked', FTurnsUnlocked);
    Ini.WriteBool('Settings', 'FreeEasy', FFreeEasy);
    Ini.WriteString('Settings', 'Back', FBackKey);
    Ini.WriteString('Settings', 'Cloth', FClothKey);
    Ini.WriteString('Settings', 'Moon', FMoonKey);
    Ini.WriteString('Settings', 'Relics', FEquipped);
    StoreWrite(FFile, Ini.ToText);
  finally
    Ini.Free;
  end;
end;

procedure TSettings.ResetRelics;
begin
  FEquipped := '';
end;

procedure TSettings.ResetStyle;
begin
  FBackKey := CosmeticKey(ckBack, 0);
  FClothKey := CosmeticKey(ckCloth, 0);
  FMoonKey := CosmeticKey(ckMoon, 0);
end;

function DefaultSettingsFile: string;
begin
  Result := StoreName('settings.ini');
end;

function ShouldResumeCampaign(ASettings: TSettings; ACampaign: TCampaign): Boolean;
begin
  Result := (ASettings.Mode = gmCampaign) and not ACampaign.IsComplete;
end;

end.
