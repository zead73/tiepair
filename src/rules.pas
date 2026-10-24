unit Rules;

{ The player's rules, in plain words, for the Rules button on the menu. No
  window code: both front ends show the same sections (the desktop as one
  scrolling text, the web page as a dialog).

  Every number is built from the constants the game really uses, so a balance
  change cannot leave this text wrong. Names come from the story file. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pyramid, Specials, Inventory, Vampires, Duel, Story, HandFile, Trophies, Cosmetics, Relics;

function RulesSectionCount: Integer;
function RulesHeading(I: Integer; AStory: TStory): string;
{ The paragraphs of a section, one per line (separated by LineBreak). }
function RulesBody(I: Integer; AStory: TStory): string;
{ Everything as one text: each heading, then its paragraphs. }
function RulesPlainText(AStory: TStory): string;

const
  RulesBreak = #10;       { between paragraphs, in the same way on every platform }

implementation

const
  Sections = 14;
  RankNames: array[0..VampireCount - 1] of string = ('Jack', 'Queen', 'King');

function RulesSectionCount: Integer;
begin
  Result := Sections;
end;

function RulesHeading(I: Integer; AStory: TStory): string;
begin
  case I of
    0: Result := 'The goal';
    1: Result := 'Taking cards away';
    2: Result := 'The stock, missed moves and streaks';
    3: Result := 'Winning and losing a hand';
    4: Result := 'Undo and hint cards';
    5: Result := 'The Store and special cards';
    6: Result := 'The Campaign';
    7: Result := 'The vampires and their tricks';
    8: Result := 'The silver cross';
    9: Result := 'Saving your game';
    10: Result := 'Trophies';
    11: Result := 'Style';
    12: Result := 'Relics';
  else
    Result := 'Free Play and Records';
  end;
end;

{ "Lucien Vale (the Jack)" }
function VampireLabel(V: Integer; AStory: TStory): string;
begin
  Result := Format('%s (the %s)', [AStory.Name(V), RankNames[V]]);
end;

function BodyPlaying(AStory: TStory): string;
begin
  Result :=
    'A card can be taken away when it is free: no card is lying on top of it. The bottom row is free from the start. ' +
    'Each card above it is covered by the two cards below it, one to its left and one to its right, and becomes free when both are gone.' + RulesBreak +
    'Take away a King on its own, with one tap. Take away any other card together with a second card, when their ranks add up to 13: ' +
    'Ace (1) and Queen (12), 2 and Jack, 3 and 10, 4 and 9, 5 and 8, 6 and 7. Tap one card, then the other. Tap a card again to let it go. Suits do not matter.' + RulesBreak +
    'Two cards can come from the pyramid, or one from the pyramid and one from the top of the waste pile. Only the top card of the waste pile can be used.' + RulesBreak +
    'In Easy mode (and in the first vampire''s duel) a card that only one card still covers can go together with that card: a Queen lying on an Ace, say. ' +
    'In Normal mode a card has to be uncovered first.';
end;

function BodyDrawing(AStory: TStory): string;
begin
  Result :=
    'When nothing can be taken away, tap the stock to turn its top card onto the waste pile. ' +
    'A hand has ' + IntToStr(StockStart) + ' cards in the stock. When it is empty, tap its place to turn the waste pile over and go through it again. The panel says how many times that is allowed (it differs from vampire to vampire).' + RulesBreak +
    Format('If you draw while something on the table could have been taken away, that is a missed move. Each missed move takes %d coins off what the hand pays (it never pays less than %d). Turning the waste over is never a missed move.',
      [MissPenaltyCoins, RewardFloorCoins]) + RulesBreak +
    'Every pair you take away in a row builds your streak. Drawing from the stock ends it. Your longest streak goes in your Records.';
end;

function BodyWinLose(AStory: TStory): string;
begin
  Result :=
    'You win a hand by taking away all 28 cards of the pyramid.' + RulesBreak +
    'You lose a hand when the stock is empty (and cannot be turned over again) and nothing on the table can be taken away. ' +
    'If you still have an undo card or a special card that could help, the game waits so that you can use one. ' +
    'In the Campaign, pressing New Game gives up the hand you are playing, and it counts as a lost hand.';
end;

function BodyUndoHint(AStory: TStory): string;
begin
  Result :=
    'An undo card takes back your last move. You can use as many as you have cards for, one card for each move, all the way back to the deal. ' +
    'Taking back a missed move or a bitten card gives its coins back. ' +
    'Using a special card clears the history, so you cannot undo past it.' + RulesBreak +
    'A hint card (the Show move button) points out two cards you could take away, or tells you to draw. ' +
    'The card is used up even when there is no move to show.' + RulesBreak +
    Format('You start with %d coins, and clearing hands earns more coins and cards. Packs are sold in the Store: %d undo cards for %d coins, %d hint cards for %d coins (list prices).',
      [StartingCoins, UndoPackSize, UndoPackCost, HintPackSize, HintPackCost]);
end;

function SpecialLine(K: TSpecialKind; const Text: string): string;
begin
  Result := Format('%s (%d coins): %s', [SpecialName[K], SpecialPrice[K], Text]);
end;

{ When the Extra turn and the Easy rule go on the shelf. }
function SellingText(AStory: TStory): string;
begin
  if FirstFewerTurnsVampire = FirstNormalVampire then
    Result := Format('Fenwick starts selling the Extra turn and the Easy rule once you reach %s.',
      [VampireLabel(FirstFewerTurnsVampire, AStory)])
  else
    Result := Format('Fenwick starts selling the Extra turn once you reach %s, and the Easy rule once you reach %s.',
      [VampireLabel(FirstFewerTurnsVampire, AStory), VampireLabel(FirstNormalVampire, AStory)]);
end;

function BodyStore(AStory: TStory): string;
begin
  Result :=
    'The Store is run by Fenwick Grimm. It is open between hands, and on a fresh hand until you make your first move. It is also open at the start of a hand you have loaded. ' +
    'Prices are fixed and nothing in the Store is random: you always get what you pay for.' + RulesBreak +
    'Your special cards are kept in My cards. A special card can be used in any hand, as many as you like:' + RulesBreak +
    SpecialLine(skExtraTurn, 'the stock can be turned over one more time this hand.') + RulesBreak +
    SpecialLine(skEasyRule, 'a card that only one card covers can go together with that card for this hand.') + RulesBreak +
    SpecialLine(skDawn, 'both of the above in one card.') + RulesBreak +
    SpecialLine(skWild, 'tap two cards in play (in the pyramid, or the top of the waste) and they are taken away as a pair, whatever their ranks.') + RulesBreak +
    SpecialLine(skSeer, 'shows the next three cards of the stock for this hand.') + RulesBreak +
    SpecialLine(skStake, 'tap a free card to destroy it. It counts towards clearing the pyramid; your streak and the waste pile stay as they were.') + RulesBreak +
    SellingText(AStory);
end;

function BodyCampaign(AStory: TStory): string;
var
  V: Integer;
  Pays: string;
begin
  Pays := '';
  for V := 0 to VampireCount - 1 do
  begin
    if Pays <> '' then Pays := Pays + ', ';
    Pays := Pays + Format('%d', [VampireWinCoins[V]]);
  end;
  Result :=
    Format('In the Campaign you duel %d vampires in turn. To kill one you must win %d hands against that vampire.', [VampireCount, WinsToKill]) + RulesBreak +
    Format('Each won hand pays coins at once (%s coins for the %s, %s and %s). The last hand, the one that kills the vampire, pays a bonus on top: ',
      [Pays, RankNames[0], RankNames[1], RankNames[2]]) +
    Format('%d, %d and %d coins.', [VampireKillBonus[0], VampireKillBonus[1], VampireKillBonus[2]]) + RulesBreak +
    Format('Winning also earns cards: %d hint card for each of the first %d wins, and %d undo card and %d hint cards for the kill.',
      [HitHintCards, WinsToKill - 1, WinUndoCards, WinHintCards]) + RulesBreak +
    Format('Losing a hand never costs you a win. The vampire drinks your blood, you deal again, and the next win pays %d coins less for each hand you have lost since your last win (never less than %d).',
      [SpoilsStep, RewardFloorCoins]) + RulesBreak +
    Format('Missed moves still take %d coins each off a hand''s pay.', [MissPenaltyCoins]) + RulesBreak +
    Format('The Store is cheaper at the earlier vampires: %d%% of list price against %s, %d%% against %s and %d%% against %s.',
      [VampirePricePercent[0], AStory.Name(0), VampirePricePercent[1], AStory.Name(1), VampirePricePercent[2], AStory.Name(2)]) + RulesBreak +
    'After the last vampire falls, the Campaign is over and you can play it again from the Start over button.';
end;

function StockText(V: Integer): string;
begin
  Result := TurnOvers(VampireRecycles[V]) + ' of the stock';
  if VampireEasy[V] then Result := Result + ', the Easy rule'
  else Result := Result + ', plain Pyramid';
end;

function BodyVampires(AStory: TStory): string;
begin
  Result :=
    'Each vampire changes the rules a little, and each has a trick. The panel beside the table always reminds you.' + RulesBreak +
    Format('%s: %s. Bitten cards: %d cards carry a bat. Taking one costs %d coins off the hand''s pay and ends your streak; a pair of two bitten cards costs two bites.',
      [VampireLabel(0, AStory), StockText(0), BittenCount, BitePenaltyCoins]) + RulesBreak +
    Format('%s: %s. Chained cards: %d cards are chained. A chained card cannot be taken away while a card beside it in its row is still on the table (not even together with that card). A Wood Stake or a Wild card still reaches it.',
      [VampireLabel(1, AStory), StockText(1), ChainedCount]) + RulesBreak +
    Format('%s: %s. Hunger: after every %dth draw he eats the bottom card of the stock. An Extra turn gives you back some of what he costs you.',
      [VampireLabel(2, AStory), StockText(2), FeedEvery]) + RulesBreak +
    'Special cards are the answer to the tricks: Wild card or Wood Stake for chains, Wood Stake for a bite, Seer''s eye to plan ahead, Extra turn for hunger.';
end;

function BodyCross(AStory: TStory): string;
begin
  Result :=
    Format('In the duel against %s, and again in the duel against %s, a silver cross lies on the table once, in one of the first three games of that duel. It is never in the last two games.',
      [AStory.Name(1), AStory.Name(2)]) + RulesBreak +
    'It is drawn on one card of the pyramid, and the Store is open until your first move, so you can buy a Wild card first.' + RulesBreak +
    'Only a Wild card claims it: use the Wild card with the cross card as one of the two. Taking that card away in an ordinary move, or using a Wood Stake on it, destroys the cross. The game asks before it lets you take it as an ordinary card.' + RulesBreak +
    Format('Once claimed, from the next hand on the vampire plays like %s: the Easy rule, the most turn-overs, and no trick. The pay stays the same. For %s it lasts until the duel ends. For %s it lasts %d hands, won or lost (the hand you claim it in does not count).',
      [AStory.Name(0), AStory.Name(1), AStory.Name(2), VampireEaseHands[2]]) + RulesBreak +
    'If you lose the game that carries the cross, the next deal still has it, in a new place.';
end;

function BodySaving(AStory: TStory): string;
begin
  Result :=
    'The game saves your hand after every move, and your coins and cards as soon as they change. Close it at any time: next time it opens where you left off.' + RulesBreak +
    Format('The Menu button opens the start menu. From there you can Save game or Load game into one of %d slots for each mode. ', [SlotCount]) +
    'Loading a Campaign slot takes your campaign back to that moment, including your coins and cards.' + RulesBreak +
    'To clear out a saved game, press the Delete button beside it on the Save or Load page. The game asks first, because a deleted save cannot be brought back.' + RulesBreak +
    'Start over lets you restart the Campaign only, or erase everything.';
end;

function BodyTrophies(AStory: TStory): string;
var
  T: TTrophy;
  List: string;
begin
  List := '';
  for T := Low(TTrophy) to High(TTrophy) do
  begin
    if List <> '' then List := List + RulesBreak;
    List := List + AStory.TrophyName(TrophyKeys[T]) + ': ' + AStory.TrophyHow(TrophyKeys[T]);
  end;
  Result :=
    'Trophies are keepsakes you earn by playing, and they are always earned the same way: nothing about them is random.' + RulesBreak +
    List + RulesBreak +
    'They sit on a shelf at the foot of the side panel: a small picture for each one you have, and an empty tile for the rest. Tap the shelf to see their names and what each one says. On a narrow screen the shelf is a single Trophies button.' + RulesBreak +
    'Starting the Campaign again keeps your trophies. Only Erase everything clears them.' + RulesBreak +
    'Trophies you already deserved from your earlier wins and kills were put on the shelf the first time the game started with trophies. The flawless trophy is only earned in a run that is played from the start.';
end;

function BodyStyle(AStory: TStory): string;
begin
  Result :=
    'Style changes how the game looks and never how it plays: the backs of the cards, the table cloth, and the colour of the moon over the house.' + RulesBreak +
    'Open it from the Style button on the start menu, or from the Store. Each kind has its own tab. Every kind starts with the original look, which is always yours.' + RulesBreak +
    Format('The others are bought from Fenwick at fixed prices: %d coins for a card back, %d for a table cloth, %d for a moon. They never go on sale, and the campaign''s cheaper Store prices do not apply to them.',
      [BackPrice, ClothPrice, MoonPrice]) + RulesBreak +
    'The last one of each kind cannot be bought. It is unlocked by the trophy of a vampire you kill, and the page says which.' + RulesBreak +
    'Pick what you own with Use. You can change your style at any time, even in the middle of a hand. What you bought goes with your coins: loading a Campaign save takes it back to what you had then, and Erase everything clears it.';
end;

function BodyRelics(AStory: TStory): string;
var
  R: TRelic;
  List: string;
begin
  List := '';
  for R := Low(TRelic) to High(TRelic) do
  begin
    if List <> '' then List := List + RulesBreak;
    List := List + Format('%s (%d coins): %s', [AStory.RelicName(RelicKey(R)), RelicPrice(R), AStory.RelicLine(RelicKey(R))]);
  end;
  Result :=
    'Relics are small helps you keep, to take the edge off the hard vampires. Buy them from Fenwick (the Relics button in the Store). Prices are fixed and nothing about them is random.' + RulesBreak +
    List + RulesBreak +
    'You start with one slot, and every vampire you kill (the trophy on the shelf) gives you another. Equip a relic to put it in a slot; remove one to make room. You keep what you buy.' + RulesBreak +
    'The Steady Locket is also given to you by The Steady Hand trophy, and the Moonstone by Carmilla''s trophy, so you can earn them instead of buying them.' + RulesBreak +
    'Buying is only between hands, but you can equip and remove relics at any time: use the Relics button in the Store, or on the start menu in the middle of a hand. A relic works the moment it is equipped, in the hand you are playing too. What a hand has already used stays used, however you change your relics: the Pick''s one chained card, the Moonstone''s free hint, and the bite and the missed move that the Wreath and the Locket forgave (they forgive the first one that happens while they are equipped). The Pick, the Spoon and the Wreath only matter against a vampire''s trick, so in Free Play they do nothing.';
end;

function BodyFree(AStory: TStory): string;
begin
  Result :=
    Format('Free Play is Pyramid with no vampires, in Normal or Easy mode as you choose. Clearing a hand pays %d coins, %d undo card and %d hint cards, less %d coins for every missed move.',
      [WinCoins, WinUndoCards, WinHintCards, MissPenaltyCoins]) + RulesBreak +
    'The Store charges list prices in Free Play.' + RulesBreak +
    'The Records button keeps your personal bests: longest streaks, wins in a row, perfect hands and, in the Campaign, your fewest lost hands against each vampire. ' +
    'When you break a record you can type your initials.';
end;

function RulesBody(I: Integer; AStory: TStory): string;
begin
  case I of
    0: Result := 'Pyramid is played with one deck. Take away all 28 cards of the pyramid to win the hand.' + RulesBreak +
         'Seven rows of cards stand on the table, one more card in each row. Below them is a stock pile you draw from, and a waste pile.';
    1: Result := BodyPlaying(AStory);
    2: Result := BodyDrawing(AStory);
    3: Result := BodyWinLose(AStory);
    4: Result := BodyUndoHint(AStory);
    5: Result := BodyStore(AStory);
    6: Result := BodyCampaign(AStory);
    7: Result := BodyVampires(AStory);
    8: Result := BodyCross(AStory);
    9: Result := BodySaving(AStory);
    10: Result := BodyTrophies(AStory);
    11: Result := BodyStyle(AStory);
    12: Result := BodyRelics(AStory);
  else
    Result := BodyFree(AStory);
  end;
end;

function RulesPlainText(AStory: TStory): string;
var
  I, P: Integer;
  B, Para: string;
begin
  Result := '';
  for I := 0 to Sections - 1 do
  begin
    if Result <> '' then Result := Result + LineEnding + LineEnding;
    Result := Result + UpperCase(RulesHeading(I, AStory)) + LineEnding;
    B := RulesBody(I, AStory);
    while B <> '' do
    begin
      P := Pos(RulesBreak, B);
      if P = 0 then
      begin
        Para := B;
        B := '';
      end
      else
      begin
        Para := Copy(B, 1, P - 1);
        B := Copy(B, P + 1, Length(B));
      end;
      Result := Result + LineEnding + Para + LineEnding;
    end;
  end;
end;

end.
