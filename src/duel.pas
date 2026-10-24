unit Duel;

{ The rules of a duel against a vampire, as a small state machine. No window
  code and no card code: it only hears "the hand was won / lost" and "the scene
  has finished", and says what state the duel is in and what it pays.

  A scene is anything the window shows between hands (intro, a hit, the
  vampire's free round after a lost hand, the fatal blow, the defeat). Each
  state below except Playing and Complete is a scene; when the window has
  finished showing it, it calls SceneDone.

      Intro       -> Playing
      Playing     -> Hit         a won hand (wins 1-4)
      Playing     -> FatalBlow   the 5th won hand
      Playing     -> FreeRound   a lost hand
      Hit, FreeRound -> Playing
      FatalBlow   -> Defeated -> next vampire (Intro), or Complete

  Rules: it takes WinsToKill (5) won hands to kill a vampire; each win pays
  at once (the fifth adds a bonus). A lost hand (stuck, or you conceded) never
  ends the campaign or takes a win away: the vampire gets a free round, the
  next win pays a little less, and you deal again. The cut is forgotten once
  you win a hand. }

{$mode objfpc}{$H+}

interface

uses
  Vampires, Campaign, Inventory;

const
  SpoilsStep = 2;          { coins a win pays less for each lost hand since the last win }
  SpoilsFloor = RewardFloorCoins;   { ... but never less than this }

type
  TDuelState = (dsIntro, dsPlaying, dsHit, dsFreeRound, dsFatalBlow, dsDefeated,
    dsComplete);
  TLossReason = (lrStuck, lrConceded);

  TDuelReward = record
    Coins, UndoCards, HintCards: Integer;
  end;

  TDuel = class
  private
    FCampaign: TCampaign;
    FState: TDuelState;
    FLastLoss: TLossReason;
    FLastReward: TDuelReward;
    function GetVampire: Integer;
    function GetLostHands: Integer;
    function GetWins: Integer;
  public
    constructor Create(ACampaign: TCampaign);
    { Enters the current vampire's intro (or Complete if all are defeated). }
    procedure Start;
    { The window finished showing the scene for the current state. }
    function SceneDone: Boolean;
    { Pick up a saved hand: straight from the intro into play (the intro was
      already seen). False unless the duel is at its intro. }
    function ResumePlaying: Boolean;
    { The hand ended: each returns False if no hand was in progress. AMisses is
      how many moves the player missed in the hand, ABites how many bitten
      cards they played; each shaves a little more off the coins paid. }
    function HandWon(AMisses: Integer = 0; ABites: Integer = 0): Boolean;
    function HandLost(Reason: TLossReason): Boolean;
    { Coins the next win pays before missed moves: the vampire's per-win coins
      less the lost-hand cut, never below the floor. The kill bonus (see
      KillBonus) is not part of this and is never cut. }
    function Spoils: Integer;
    { True if the next win will kill the vampire (it is the fifth). }
    function NextWinKills: Boolean;
    { What the killing win adds on top of Spoils (0 unless NextWinKills). }
    function KillBonus: Integer;
    { True if this vampire has been fought already (a win or a lost hand), so
      his intro need not be shown again. }
    function InProgress: Boolean;
    { How badly the player is doing, for the vampire's taunts:
      0 = no lost hands, 1, 2, 3 = three or more. }
    function Tier: Integer;
    property State: TDuelState read FState;
    property Vampire: Integer read GetVampire;       { index into the campaign }
    property LostHands: Integer read GetLostHands;
    { Lost hands in the whole duel with this vampire (not forgotten by a win). }
    function TotalLost: Integer;
    property Wins: Integer read GetWins;             { against this vampire so far }
    property LastLoss: TLossReason read FLastLoss;
    property LastReward: TDuelReward read FLastReward;
  end;

implementation

constructor TDuel.Create(ACampaign: TCampaign);
begin
  inherited Create;
  FCampaign := ACampaign;
  Start;
end;

function TDuel.GetVampire: Integer;
begin
  Result := FCampaign.Current;
end;

function TDuel.TotalLost: Integer;
begin
  Result := FCampaign.TotalLost;
end;

function TDuel.GetLostHands: Integer;
begin
  Result := FCampaign.LostHands;
end;

procedure TDuel.Start;
begin
  if FCampaign.IsComplete then FState := dsComplete else FState := dsIntro;
end;

function TDuel.GetWins: Integer;
begin
  Result := FCampaign.Wins;
end;

function TDuel.Spoils: Integer;
begin
  if FCampaign.IsComplete then
  begin
    Result := 0;
    Exit;
  end;
  Result := VampireWinCoins[FCampaign.Current] - SpoilsStep * FCampaign.LostHands;
  if Result < SpoilsFloor then Result := SpoilsFloor;
  if Result > VampireWinCoins[FCampaign.Current] then      { a floor above the pay never raises it }
    Result := VampireWinCoins[FCampaign.Current];
end;

function TDuel.NextWinKills: Boolean;
begin
  Result := not FCampaign.IsComplete and (FCampaign.Wins = WinsToKill - 1);
end;

function TDuel.KillBonus: Integer;
begin
  if NextWinKills then Result := VampireKillBonus[FCampaign.Current] else Result := 0;
end;

function TDuel.InProgress: Boolean;
begin
  Result := not FCampaign.IsComplete and ((FCampaign.Wins > 0) or (FCampaign.LostHands > 0));
end;

function TDuel.Tier: Integer;
begin
  Result := FCampaign.LostHands;
  if Result > 3 then Result := 3;
end;

function TDuel.SceneDone: Boolean;
begin
  Result := True;
  case FState of
    dsIntro, dsHit, dsFreeRound: FState := dsPlaying;
    dsFatalBlow: FState := dsDefeated;
    dsDefeated:
    begin
      FCampaign.Advance;
      Start;                               { next intro, or Complete }
    end;
  else
    Result := False;                       { Playing / Complete: no scene to finish }
  end;
end;

function TDuel.ResumePlaying: Boolean;
begin
  Result := FState = dsIntro;
  if Result then FState := dsPlaying;
end;

function TDuel.HandWon(AMisses: Integer; ABites: Integer): Boolean;
begin
  Result := FState = dsPlaying;
  if not Result then Exit;
  { what this win pays, worked out before the win clears the lost-hand cut;
    the bonus is added after the cuts, so nothing can eat it }
  FLastReward.Coins := RewardAfterCuts(Spoils, AMisses, ABites) + KillBonus;
  if NextWinKills then
  begin
    FLastReward.UndoCards := WinUndoCards;
    FLastReward.HintCards := WinHintCards;
  end
  else
  begin
    FLastReward.UndoCards := 0;
    FLastReward.HintCards := HitHintCards;
  end;
  if FCampaign.RecordWin then            { saved now, not when the scenes end }
    FState := dsFatalBlow
  else
    FState := dsHit;
end;

function TDuel.HandLost(Reason: TLossReason): Boolean;
begin
  Result := FState = dsPlaying;
  if not Result then Exit;
  FLastLoss := Reason;
  FCampaign.AddLostHand;
  FState := dsFreeRound;
end;

end.
