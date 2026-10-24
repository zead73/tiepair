program TestSlots;

{ The campaign's save slots: what one holds (progress, coins and cards, the hand),
  reading it back, and refusing a damaged file. No window. }

{$mode objfpc}{$H+}

uses SysUtils, Classes, Cards, Pyramid, Inventory, Session, Specials, Campaign, Storage, HandFile,
  CampaignSlots{$IFDEF PAS2JS}, JsCompat{$ENDIF};

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

procedure TestSlotRoundTrip;
var
  S: TGameSession;
  C, C2: TCampaign;
  Inv2: TPlayerInventory;
  H: TSavedHand;
  Slot: TCampaignSlot;
  Info: TCampaignSlotInfo;
  Text: string;
  A, B: Integer;
begin
  S := TGameSession.Create('');
  C := TCampaign.Create('');
  C2 := TCampaign.Create('');
  Inv2 := TPlayerInventory.Create;
  try
    S.NewGame;
    S.DrawStock;
    if S.Game.FindRemoval(0, A, B) then S.Remove(A, B);
    S.Inventory.AddCoins(123);
    S.Inventory.AddUndoCards(4);
    S.Inventory.AddSpecial(skWild, 2);
    S.ExportHand(H);
    C.Advance;                                  { on to the second vampire }
    C.RecordWin;
    C.AddLostHand;
    C.MarkPremiseSeen;

    Check(not PeekCampaignSlot(1).Exists, 'an empty slot says so');
    Check(WriteCampaignSlot(1, C.ExportText, S.Inventory.ExportText, H), 'a slot is written');
    Info := PeekCampaignSlot(1);
    Check(Info.Exists and (Info.Vampire = 1) and (Info.Wins = 1), 'it shows which vampire and how many wins');
    Check(Info.CardsLeft = S.Game.CardsLeft, 'and how many cards were left');
    Check(Length(Info.Stamp) > 8, 'and when: ' + Info.Stamp);
    Check(not PeekCampaignSlot(2).Exists, 'the other slots are still empty');

    Check(ReadCampaignSlot(1, Slot), 'it reads back');
    C2.ImportText(Slot.CampaignText);
    Check((C2.Current = C.Current) and (C2.Wins = C.Wins) and (C2.LostHands = C.LostHands)
      and (C2.TotalLost = C.TotalLost) and C2.PremiseSeen, 'the campaign progress is the same');
    Inv2.ImportText(Slot.InventoryText);
    Check((Inv2.Coins = S.Inventory.Coins) and (Inv2.UndoCards = 4) and (Inv2.SpecialCards(skWild) = 2),
      'so are the coins and cards');
    Check(Slot.Hand.Game.Draws = H.Game.Draws, 'and the hand');

    { a second save replaces the first }
    S.Inventory.AddCoins(7);
    Check(WriteCampaignSlot(1, C.ExportText, S.Inventory.ExportText, H), 'saved again');
    Check(ReadCampaignSlot(1, Slot), 'read again');
    Inv2.ImportText(Slot.InventoryText);
    Check(Inv2.Coins = S.Inventory.Coins, 'the newer save wins');

    { text round trip, and what a damaged file does }
    Text := CampaignSlotToText(Slot);
    Check(TextToCampaignSlot(Text, Slot), 'the text reads');
    Check(not TextToCampaignSlot('', Slot), 'empty text is refused');
    Check(not TextToCampaignSlot('hello', Slot), 'text that is not a slot is refused');
    Check(not TextToCampaignSlot(StringReplace(Text, '@@hand', '@@hands', []), Slot), 'a slot with no hand is refused');
    Check(not TextToCampaignSlot(StringReplace(Text, '@@inventory', '@@stuff', []), Slot), 'or no inventory');
    Check(not TextToCampaignSlot(StringReplace(Text, 'tiepair-campaign-slot 1', 'tiepair-campaign-slot 9', []), Slot),
      'an unknown version is refused');
    Check(not TextToCampaignSlot(StringReplace(Text, 'tableau=', 'tabl=', []), Slot), 'a damaged hand is refused');

    DeleteCampaignSlot(1);
    Check(not PeekCampaignSlot(1).Exists, 'a deleted slot is empty');
  finally
    Inv2.Free;
    C2.Free;
    C.Free;
    S.Free;
  end;
end;

begin
  CrossCardsOn := False;                  { where the silver cross lies is random: it has its own tests }
  Randomize;
  SetStoreDir('tiepair_test_slots');
  TestSlotRoundTrip;
  DeleteCampaignSlot(1);
  if Failures = 0 then WriteLn('ALL SLOT TESTS PASSED') else
  begin
    WriteLn(Failures, ' FAILURES');
    Halt(1);
  end;
end.
