unit CampaignSlots;

{ Manual save slots for the campaign. A slot keeps three things in one file: the
  campaign's progress (which vampire, wins, lost hands), the coins and cards you
  own, and the hand being played. Loading one puts all three back, so it is a
  true rewind: nothing earned after the save is kept (which also means a slot
  cannot be used to collect a win's pay twice). No window code.

  The file is plain text: a header line, a "saved=" line, then three parts, each
  introduced by a line "@@campaign", "@@inventory" or "@@hand". Reading is
  defensive: anything missing or damaged is simply "no usable save". }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Storage, Session, HandFile;

type
  TCampaignSlotInfo = record
    Exists: Boolean;
    Stamp: string;          { when it was saved }
    Vampire: Integer;       { which vampire he was fighting (0-based) }
    Wins: Integer;          { won hands against him }
    CardsLeft: Integer;
  end;

  TCampaignSlot = record
    CampaignText, InventoryText: string;
    Hand: TSavedHand;
    Stamp: string;
  end;

function CampaignSlotFile(N: Integer): string;      { N = 1..SlotCount }

{ The text of a slot (exposed so it can be tested without files). }
function CampaignSlotToText(const S: TCampaignSlot): string;
function TextToCampaignSlot(const Text: string; out S: TCampaignSlot): Boolean;

function WriteCampaignSlot(N: Integer; const ACampaignText, AInventoryText: string;
  const H: TSavedHand): Boolean;
function ReadCampaignSlot(N: Integer; out S: TCampaignSlot): Boolean;
function PeekCampaignSlot(N: Integer): TCampaignSlotInfo;
procedure DeleteCampaignSlot(N: Integer);

implementation

uses
  TextIni;

const
  Magic = 'tiepair-campaign-slot 1';

function CampaignSlotFile(N: Integer): string;
begin
  Result := StoreName(Format('campaignslot%d.save', [N]));
end;

function CampaignSlotToText(const S: TCampaignSlot): string;
begin
  Result := Magic + LineEnding + 'saved=' + S.Stamp + LineEnding
    + '@@campaign' + LineEnding + S.CampaignText + LineEnding
    + '@@inventory' + LineEnding + S.InventoryText + LineEnding
    + '@@hand' + LineEnding + HandToText(S.Hand, S.Stamp);
end;

function TextToCampaignSlot(const Text: string; out S: TCampaignSlot): Boolean;
var
  L: TStringList;
  I, Part: Integer;
  Camp, Inv, Hand: string;
  Stamp: string;
begin
  Result := False;
  S := Default(TCampaignSlot);
  L := TStringList.Create;
  try
    L.Text := Text;
    if (L.Count < 4) or (Trim(L[0]) <> Magic) then Exit;
    Part := 0;                                 { 1 campaign, 2 inventory, 3 hand }
    Camp := '';
    Inv := '';
    Hand := '';
    for I := 1 to L.Count - 1 do
    begin
      if Trim(L[I]) = '@@campaign' then Part := 1
      else if Trim(L[I]) = '@@inventory' then Part := 2
      else if Trim(L[I]) = '@@hand' then Part := 3
      else
        case Part of
          1: Camp := Camp + L[I] + LineEnding;
          2: Inv := Inv + L[I] + LineEnding;
          3: Hand := Hand + L[I] + LineEnding;
        end;
    end;
    if (Camp = '') or (Inv = '') or (Hand = '') then Exit;
    if not TextToHand(Hand, S.Hand, Stamp) then Exit;
    S.Stamp := Stamp;
    S.CampaignText := Camp;
    S.InventoryText := Inv;
    Result := True;
  finally
    L.Free;
  end;
end;

function WriteCampaignSlot(N: Integer; const ACampaignText, AInventoryText: string;
  const H: TSavedHand): Boolean;
var
  S: TCampaignSlot;
begin
  S.CampaignText := ACampaignText;
  S.InventoryText := AInventoryText;
  S.Hand := H;
  S.Stamp := FormatDateTime('yyyy-mm-dd hh:nn', Now);
  Result := StoreWrite(CampaignSlotFile(N), CampaignSlotToText(S));
end;

function ReadCampaignSlot(N: Integer; out S: TCampaignSlot): Boolean;
var
  Text: string;
begin
  Result := StoreRead(CampaignSlotFile(N), Text) and TextToCampaignSlot(Text, S);
end;

function PeekCampaignSlot(N: Integer): TCampaignSlotInfo;
var
  S: TCampaignSlot;
  Ini: TTextIni;
  I, Left: Integer;
begin
  Result.Exists := False;
  Result.Stamp := '';
  Result.Vampire := 0;
  Result.Wins := 0;
  Result.CardsLeft := 0;
  if not ReadCampaignSlot(N, S) then Exit;
  Result.Exists := True;
  Result.Stamp := S.Stamp;
  Left := 0;
  for I := 0 to High(S.Hand.Game.Removed) do
    if not S.Hand.Game.Removed[I] then Inc(Left);
  Result.CardsLeft := Left;
  Ini := TTextIni.Create;
  try
    Ini.LoadFromText(S.CampaignText);
    Result.Vampire := Ini.ReadInteger('Campaign', 'Current', 0);
    Result.Wins := Ini.ReadInteger('Campaign', 'Wins', 0);
  finally
    Ini.Free;
  end;
end;

procedure DeleteCampaignSlot(N: Integer);
begin
  StoreDelete(CampaignSlotFile(N));
end;

end.
