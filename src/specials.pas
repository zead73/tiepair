unit Specials;

{ The special cards sold in the Store. No window code. A special card changes
  the hand you are playing (never the deal: nothing here gives a new shuffle),
  is bought one at a time at a fixed price, and any number may be used in a hand.
  What each one does to the cards is in Pyramid (ExtraTurn, EasyRule, ...);
  who owns how many is in Inventory; the rules for using one are in Session. }

{$mode objfpc}{$H+}

interface

type
  TSpecialKind = (
    skExtraTurn,    { the stock can be turned over one more time }
    skEasyRule,     { a card may go with the one card covering it }
    skDawn,         { both of the above: the "lowest level" card }
    skWild,         { take away any two cards in play as a pair, whatever their ranks }
    skSeer,         { show the next three stock cards }
    skStake);       { destroy any free card }

const
  SpecialCount = 6;

  { Fixed prices in coins, the same as in Tiecards for the card of the same place in
    the list (Tiepair's sibling): the Extra turn and the Easy rule are the cheapest (they help where the
    hands are hard and nowhere else), Wild card and Wood Stake help anywhere, Dawn does
    both softenings in one card for less than the two, and the Seer's eye changes no
    cards, it only lets you plan. }
  SpecialPrice: array[TSpecialKind] of Integer = (25, 25, 45, 35, 30, 35);

  { Names used in the save file and the story file (lower case, no spaces). }
  SpecialKey: array[TSpecialKind] of string =
    ('extraturn', 'easyrule', 'dawn', 'wild', 'seer', 'stake');

  SpecialName: array[TSpecialKind] of string =
    ('Extra turn', 'Easy rule', 'Dawn', 'Wild card', 'Seer''s eye', 'Wood Stake');

  { One line for the Store and the card tray. }
  SpecialInfo: array[TSpecialKind] of string = (
    'The stock can be turned over one more time this hand.',
    'A card can go with the one card covering it this hand.',
    'Extra turn and Easy rule in one: the gentlest rules.',
    'Take away any two cards in play as a pair, whatever their ranks.',
    'Shows the next three cards of the stock this hand.',
    'Destroy any free card. Nothing else changes.');

{ Wild card (two cards) and Wood Stake (one) need the player to pick cards on the table. }
function NeedsTarget(K: TSpecialKind): Boolean;

implementation

function NeedsTarget(K: TSpecialKind): Boolean;
begin
  Result := K in [skWild, skStake];
end;

end.
