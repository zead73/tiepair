unit StartOver;

{ Starting over, for a player who wants a fresh beginning (a second player on
  the same computer, say). No window code. Two levels:

    EraseEverything     a brand-new player: coins, undo and hint cards, which
                        hands have paid, campaign progress, the mode, and every
                        saved hand and slot (the campaign's too), the personal records and the trophies.
    RestartCampaignOnly the story starts again from the first vampire; your
                        coins and cards (and Free Play hands) and your trophies are kept.

  Only the game's own save data is touched. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Inventory, Session, Campaign, Settings, HandFile, Records, Trophies;

{ SaveDir is the folder holding the saved hands. The caller must start a new
  hand afterwards (the one in memory is not touched). }
procedure EraseEverything(ASession: TGameSession; ACampaign: TCampaign;
  ASettings: TSettings; ARecords: TRecords; ATrophies: TTrophies; const SaveDir: string);

procedure RestartCampaignOnly(ACampaign: TCampaign; const SaveDir: string);

implementation

procedure EraseEverything(ASession: TGameSession; ACampaign: TCampaign;
  ASettings: TSettings; ARecords: TRecords; ATrophies: TTrophies; const SaveDir: string);
begin
  ASession.Inventory.Reset;              { 50 coins, no cards, no paid hands }
  ASession.SaveNow;
  ACampaign.Reset;                       { saved by Reset }
  ASettings.Mode := gmFreePlay;
  ASettings.FenwickMet := False;         { he introduces himself again }
  ASettings.EasyUnlocked := False;       { and his Easy rule and Extra turn cards are not in stock yet }
  ASettings.TurnsUnlocked := False;
  ASettings.ResetStyle;                  { the original look (what was bought is cleared with the inventory) }
  ASettings.ResetRelics;                 { and no relics equipped }
  ASettings.Save;
  ARecords.Reset;                        { personal records too }
  ATrophies.Reset;                       { and the trophies (Restart campaign keeps them) }
  DeleteAllSavedHands(SaveDir);
end;

procedure RestartCampaignOnly(ACampaign: TCampaign; const SaveDir: string);
begin
  ACampaign.Reset;
  DeleteCampaignHand(SaveDir);           { a half-played duel hand goes too }
end;

end.
