unit DuelSession;

{ Ties a vampire duel to a hand of Pyramid. No window code.

  It sits on top of TGameSession (the cards, the inventory, undo and hints):
  every action the player takes goes through here, so the duel hears about it,
  and the duel decides what the result means:

    * the board is cleared            -> a hit (the fifth is the fatal blow); the win
                                         is paid at once
    * stuck, and no undo card to use  -> a lost hand (the vampire's free round)
    * stuck, but an undo card is left -> wait: the player may undo or concede
    * the player gives up (New Game)  -> conceded: a lost hand too

  While a scene is showing (any state but Playing) the board is locked. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Cards, Pyramid, Inventory, Session, Campaign, Duel, Vampires, Specials;

type
  { Returns the deck for the next hand (the caller frees nothing: the session
    does). Nil means a normal shuffled deck. Used by tests to rig the deal. }
  TDeckProvider = function: TDeck of object;

  { A hand was won against vampire V (index). Kill = it was the fifth win. }
  TDuelWonEvent = procedure(V, TotalLost, BestStreak, Misses: Integer; Kill: Boolean) of object;

  TDuelSession = class
  private
    FSession: TGameSession;
    FCampaign: TCampaign;
    FDuel: TDuel;
    FActive: Boolean;
    FOnNeedDeck: TDeckProvider;
    FLastPaid: TDuelReward;
    FOnHandWon: TDuelWonEvent;
    procedure Evaluate;
    procedure Pay(const R: TDuelReward);
    procedure Deal;
  public
    constructor Create(ASession: TGameSession; ACampaign: TCampaign);
    destructor Destroy; override;
    { Campaign mode on/off. Turning it on stops the flat win reward (the duel
      pays spoils instead) and enters the current vampire's intro; no hand is
      dealt until that scene is done. }
    procedure Activate;
    procedure Deactivate;
    { Start the whole campaign again. }
    procedure Restart;
    { The window finished the scene for the current state. Deals a new hand
      if the duel is now in Playing. }
    function SceneDone: Boolean;
    { Pick up a saved hand mid-duel, skipping the intro. False (changing
      nothing) if the duel is not at its intro or the hand is not believable. }
    function ResumeHand(const H: TSavedHand): Boolean;

    { The usual actions; each returns False (doing nothing) when no hand is in
      progress. }
    function Remove(A, B: Integer): Boolean;
    function DrawStock: Boolean;
    function Recycle: Boolean;
    function UseUndo: Boolean;
    function UseHint: THintResult;
    { Special cards in a duel hand (only while playing); the hand may be won or
      lost by them just as by a card tap. }
    function UseSpecial(K: TSpecialKind): Boolean;
    function UseSpecialOn(K: TSpecialKind; A, B: Integer): Boolean;
    { The equipped relics changed in the middle of the hand: taking the Pick out can leave
      a hand with no move, which loses it just as a played card would. }
    procedure RelicsChanged;
    { The player gave up this hand (New Game during a duel). }
    function Concede: Boolean;
    { Stuck, but an undo card or a special card could still save the hand: the
      window should wait for the player's choice (use one, or New Game to concede). }
    function StuckWaiting: Boolean;
    { Coins the next win pays right now: the per-win coins less lost hands and
      missed moves, plus the kill bonus if it would be the fifth win. }
    function PayoutNow: Integer;

    property Active: Boolean read FActive;
    property Duel: TDuel read FDuel;
    property Campaign: TCampaign read FCampaign;
    property Session: TGameSession read FSession;
    property LastPaid: TDuelReward read FLastPaid;       { what the last win paid }
    property OnNeedDeck: TDeckProvider read FOnNeedDeck write FOnNeedDeck;
    property OnHandWon: TDuelWonEvent read FOnHandWon write FOnHandWon;
  end;

implementation

function CrossClaimedText(V: Integer): string;
begin
  if VampireEaseHands[V] < 0 then
    Result := 'The silver cross is yours! From the next hand the vampire plays at the lowest level, until the duel ends.'
  else
    Result := Format('The silver cross is yours! The vampire plays at the lowest level for the next %d hands.',
      [VampireEaseHands[V]]);
end;

constructor TDuelSession.Create(ASession: TGameSession; ACampaign: TCampaign);
begin
  inherited Create;
  FSession := ASession;
  FCampaign := ACampaign;
  FDuel := TDuel.Create(ACampaign);
end;

destructor TDuelSession.Destroy;
begin
  if FActive then Deactivate;
  FDuel.Free;
  inherited Destroy;
end;

procedure TDuelSession.Activate;
begin
  FActive := True;
  FSession.PayWinRewards := False;
  FDuel.Start;
end;

procedure TDuelSession.Deactivate;
begin
  FActive := False;
  FSession.PayWinRewards := True;
  FSession.SetRules(False, DefaultRecycles);   { Free Play: the ordinary rules (the controller sets the player's mode) }
end;

procedure TDuelSession.Restart;
begin
  FCampaign.Reset;
  FDuel.Start;
end;

procedure TDuelSession.Deal;
var
  D: TDeck;
begin
  { this vampire's level: the rules for the hand about to be dealt (the silver
    cross, once claimed, drops him to the lowest: the Easy rule, the most turn-overs, no trick) }
  if not FCampaign.IsComplete then
  begin
    if FCampaign.BeginHand then
      FSession.SetRules(VampireEasy[0], VampireRecycles[0], hzNone)
    else
      FSession.SetRules(VampireEasy[FCampaign.Current],
        VampireRecycles[FCampaign.Current], VampireHazard[FCampaign.Current]);
  end;
  D := nil;
  if Assigned(FOnNeedDeck) then D := FOnNeedDeck();
  if D <> nil then
  begin
    FSession.NewGameFrom(D);
    D.Free;
  end
  else
    FSession.NewGame;
  { the cross goes under one of the cards before anything saves the hand }
  if FCampaign.CrossOffered then FSession.PlaceCross;
end;

function TDuelSession.SceneDone: Boolean;
begin
  Result := FDuel.SceneDone;
  if Result and (FDuel.State = dsPlaying) then Deal;
end;

function TDuelSession.ResumeHand(const H: TSavedHand): Boolean;
begin
  Result := (FDuel.State = dsIntro) and FSession.ImportHand(H);
  if Result then FDuel.ResumePlaying;
end;

procedure TDuelSession.Pay(const R: TDuelReward);
begin
  FSession.Inventory.AddCoins(R.Coins);
  FSession.Inventory.AddUndoCards(R.UndoCards);
  FSession.Inventory.AddHintCards(R.HintCards);
  FSession.SaveNow;
  FLastPaid := R;
end;

procedure TDuelSession.Evaluate;
begin
  if FDuel.State <> dsPlaying then Exit;
  if FSession.Game.IsWon then
  begin
    if FDuel.HandWon(FSession.ChargedMisses, FSession.ChargedBites) then
    begin
      Pay(FDuel.LastReward);
      if Assigned(FOnHandWon) then
        FOnHandWon(FCampaign.Current, FCampaign.TotalLost, FSession.Game.BestStreak,
          FSession.Misses, FDuel.State = dsFatalBlow);
    end;
  end
  else if FSession.Game.IsStuck and not FSession.HasRescue then
    FDuel.HandLost(lrStuck);
end;

function TDuelSession.Remove(A, B: Integer): Boolean;
begin
  Result := (FDuel.State = dsPlaying) and FSession.Remove(A, B);
  if Result then Evaluate;
end;

function TDuelSession.Recycle: Boolean;
begin
  Result := (FDuel.State = dsPlaying) and FSession.Recycle;
  if Result then Evaluate;
end;

function TDuelSession.DrawStock: Boolean;
begin
  Result := (FDuel.State = dsPlaying) and FSession.DrawStock;
  if Result then Evaluate;
end;

function TDuelSession.UseUndo: Boolean;
begin
  Result := (FDuel.State = dsPlaying) and FSession.UseUndo;
end;

function TDuelSession.UseHint: THintResult;
begin
  if FDuel.State <> dsPlaying then Result := hrNoMoves
  else Result := FSession.UseHint;
end;

procedure TDuelSession.RelicsChanged;
begin
  Evaluate;
end;

function TDuelSession.Concede: Boolean;
begin
  Result := FDuel.HandLost(lrConceded);
  if Result then FSession.EndHand;
end;

function TDuelSession.PayoutNow: Integer;
begin
  Result := RewardAfterCuts(FDuel.Spoils, FSession.ChargedMisses, FSession.ChargedBites) + FDuel.KillBonus;
  if FCampaign.IsComplete then Result := 0;
end;

function TDuelSession.StuckWaiting: Boolean;
begin
  Result := (FDuel.State = dsPlaying) and FSession.Game.IsStuck
    and FSession.HasRescue;
end;

function TDuelSession.UseSpecial(K: TSpecialKind): Boolean;
begin
  Result := (FDuel.State = dsPlaying) and FSession.UseSpecial(K);
  if Result then Evaluate;
end;

function TDuelSession.UseSpecialOn(K: TSpecialKind; A, B: Integer): Boolean;
begin
  Result := (FDuel.State = dsPlaying) and FSession.UseSpecialOn(K, A, B);
  if Result and FSession.TakeCrossClaim then
  begin
    if FCampaign.ClaimCross and not FSession.Game.IsWon then   { saved at once }
      FSession.SetNote(CrossClaimedText(FCampaign.Current));
  end;
  if Result then Evaluate;                 { a Wild card or Stake can win the hand }
end;

end.
