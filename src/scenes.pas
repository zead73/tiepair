unit Scenes;

{ The duel's scenes, as animation sequences. No drawing, no window.

  Each builder returns a TAnimSequence that writes to a Stage (see Stage); the
  window draws the stage. The words come from the story file (see Story).

  Every dialogue line is a TMarkStep followed by "set the text, fade it in,
  hold while it is read, fade it out", so a click can jump to the next line
  (TAnimSequence.SkipToMark). Every scene fades from the picture it found to
  black first and ends faded to black, so scenes join up smoothly; the next
  thing (another scene, or the deal) fades back in from black.

  To add a scene: write a builder like these, and add it to BuildSceneForState. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, Anim, Stage, Story, Vampires, Duel;

type
  { Actions the scenes trigger (sounds); any may be nil. }
  TSceneHooks = record
    OnToll, OnNo, OnBlow, OnFanfare: TAnimAction;
  end;

const
  FadeMs = 450;              { to or from black }
  TextFadeInMs = 300;
  TextFadeOutMs = 250;
  HoldBaseMs = 900;          { how long a line stays, before counting letters }
  HoldPerCharMs = 38;
  HoldMaxMs = 7000;

{ How long a line stays on screen once it has faded in. }
function LineHoldMs(const Text: string): Integer;

{ Format that never raises: if the story text has the wrong number of %d, it
  is used as written. }
function SafeFormat(const Fmt: string; const Args: array of const): string;

function BuildIntroScene(AStage: TStage; AStory: TStory; V: Integer;
  WithPremise: Boolean; const Hooks: TSceneHooks): TAnimSequence;
{ Bleed = which picture of him drinking: 0 = blood on his fangs, 1 = the goblet. }
function BuildFreeRoundScene(AStage: TStage; AStory: TStory; V, Tier, Bleed: Integer;
  Reason: TLossReason; SpoilsNow: Integer; const Hooks: TSceneHooks): TAnimSequence;
{ Win number AWin (1..WinsToKill-1) landed on vampire V; AReward is what it paid. }
function BuildHitScene(AStage: TStage; AStory: TStory; V, AWin: Integer;
  const AReward: TDuelReward; const Hooks: TSceneHooks): TAnimSequence;
function BuildFatalBlowScene(AStage: TStage; AStory: TStory; V: Integer;
  const Hooks: TSceneHooks): TAnimSequence;
function BuildDefeatScene(AStage: TStage; AStory: TStory; V: Integer;
  const Reward: TDuelReward; const Hooks: TSceneHooks): TAnimSequence;
{ Ends on the victory picture and stays there (the window waits for a click). }
function BuildFinaleScene(AStage: TStage; AStory: TStory;
  const Hooks: TSceneHooks): TAnimSequence;

{ The scene for the duel's current state; nil while a hand is being played. }
function BuildSceneForState(AStage: TStage; AStory: TStory; ADuel: TDuel;
  WithPremise: Boolean; const Hooks: TSceneHooks): TAnimSequence;

implementation

function LineHoldMs(const Text: string): Integer;
begin
  Result := Min(HoldMaxMs, HoldBaseMs + HoldPerCharMs * Length(Text));
end;

function SafeFormat(const Fmt: string; const Args: array of const): string;
begin
  try
    Result := Format(Fmt, Args);
  except
    Result := Fmt;
  end;
end;

{ shakes that die away }
function SoftShake(T: Double): Double;
begin
  Result := 0.035 * Sin(T * 36) * (1 - T);
end;

function HardShake(T: Double): Double;
begin
  Result := 0.07 * Sin(T * 44) * (1 - T);
end;

{ ---- building blocks ---- }

{ Fade whatever is showing to black (nothing to do if already black). }
procedure ToBlack(Seq: TAnimSequence; AStage: TStage);
var
  D: Double;
begin
  D := AStage.Scalar[ssDim];
  if D < 1 then
    Seq.Add(TTweenStep.Create(AStage, ssDim, D, 1, Round(FadeMs * (1 - D)),
      @EaseLinear));
end;

procedure SetScalar(Seq: TAnimSequence; AStage: TStage; Which: TStageScalar;
  Value: Double);
begin
  Seq.Add(TTweenStep.Create(AStage, Which, Value, Value, 0, @EaseLinear));
end;

{ Switches to the dialogue room, or another backdrop (everything still black). PortraitId -1 = none. }
procedure SetUpRoom(Seq: TAnimSequence; AStage: TStage; Portrait: Integer;
  PortraitSlide, PortraitFade: Double; ABackdrop: TBackdrop = sbDialogue);
begin
  Seq.Add(TBackdropStep.Create(AStage, ABackdrop));
  Seq.Add(TPortraitStep.Create(AStage, Portrait));
  Seq.Add(TTextStep.Create(AStage, stCaption, ''));
  Seq.Add(TTextStep.Create(AStage, stSpeakerName, ''));
  Seq.Add(TTextStep.Create(AStage, stSpeakerTitle, ''));
  SetScalar(Seq, AStage, ssTextFade, 0);
  SetScalar(Seq, AStage, ssFlashWhite, 0);
  SetScalar(Seq, AStage, ssFlashRed, 0);
  SetScalar(Seq, AStage, ssPortraitDX, 0);
  SetScalar(Seq, AStage, ssPortraitSlide, PortraitSlide);
  SetScalar(Seq, AStage, ssPortraitFade, PortraitFade);
end;

{ One line of dialogue. Speaker/Title blank = the narrator. With WaitForClick the
  line stays until the player clicks (every scene does this); otherwise it stays
  long enough to read. }
procedure AddLine(Seq: TAnimSequence; AStage: TStage; const Text, Speaker, Title: string;
  WaitForClick: Boolean = False);
begin
  if Text = '' then Exit;
  Seq.Add(TMarkStep.Create);
  Seq.Add(TTextStep.Create(AStage, stSpeakerName, Speaker));
  Seq.Add(TTextStep.Create(AStage, stSpeakerTitle, Title));
  Seq.Add(TTextStep.Create(AStage, stCaption, Text));
  Seq.Add(TTweenStep.Create(AStage, ssTextFade, 0, 1, TextFadeInMs, @EaseLinear));
  if WaitForClick then
    Seq.Add(TClickWaitStep.Create(AStage))
  else
    Seq.Add(TWaitStep.Create(LineHoldMs(Text)));
  Seq.Add(TTweenStep.Create(AStage, ssTextFade, 1, 0, TextFadeOutMs, @EaseLinear));
end;

procedure AddLines(Seq: TAnimSequence; AStage: TStage; const Lines: TStringArray;
  const Speaker, Title: string; WaitForClick: Boolean = False);
var
  I: Integer;
begin
  for I := 0 to High(Lines) do AddLine(Seq, AStage, Lines[I], Speaker, Title, WaitForClick);
end;

{ Back to the plain table, left black: whatever follows fades in. }
procedure CloseScene(Seq: TAnimSequence; AStage: TStage);
begin
  Seq.Add(TTweenStep.Create(AStage, ssDim, 0, 1, FadeMs, @EaseLinear));
  Seq.Add(TBackdropStep.Create(AStage, sbTable));
  Seq.Add(TPortraitStep.Create(AStage, -1));
  Seq.Add(TTextStep.Create(AStage, stCaption, ''));
  Seq.Add(TTextStep.Create(AStage, stSpeakerName, ''));
  Seq.Add(TTextStep.Create(AStage, stSpeakerTitle, ''));
end;

function Reveal(AStage: TStage; Ms: Integer): TTweenStep;
begin
  Result := TTweenStep.Create(AStage, ssDim, 1, 0, Ms, @EaseLinear);
end;

{ ---- the scenes ---- }

function BuildIntroScene(AStage: TStage; AStory: TStory; V: Integer;
  WithPremise: Boolean; const Hooks: TSceneHooks): TAnimSequence;
var
  G: TAnimGroup;
begin
  Result := TAnimSequence.Create;
  ToBlack(Result, AStage);
  if WithPremise then
    SetUpRoom(Result, AStage, -1, 0, 0, sbHouse)       { the story opens on the house }
  else
    SetUpRoom(Result, AStage, -1, 0, 0);
  Result.Add(TCallStep.Create(Hooks.OnToll));
  Result.Add(Reveal(AStage, 700));
  if WithPremise then
  begin
    AddLines(Result, AStage, AStory.Premise, '', '', True);      { click to read on }
    { then the dark room, where the vampire waits }
    Result.Add(TTweenStep.Create(AStage, ssDim, 0, 1, FadeMs, @EaseLinear));
    Result.Add(TBackdropStep.Create(AStage, sbDialogue));
    Result.Add(TTextStep.Create(AStage, stCaption, ''));
    Result.Add(Reveal(AStage, 500));
  end;
  { the vampire steps out of the dark }
  Result.Add(TMarkStep.Create);
  Result.Add(TPortraitStep.Create(AStage, V));
  G := TAnimGroup.Create;
  G.Add(TTweenStep.Create(AStage, ssPortraitSlide, 0, 1, 900, @EaseOutCubic));
  G.Add(TTweenStep.Create(AStage, ssPortraitFade, 0, 1, 900, @EaseOutCubic));
  Result.Add(G);
  AddLines(Result, AStage, AStory.Intro(V), AStory.Name(V), AStory.Title(V), True);
  AddLines(Result, AStage, AStory.Trick(V), AStory.Name(V), AStory.Title(V), True);   { his trick }
  CloseScene(Result, AStage);
end;

function BuildFreeRoundScene(AStage: TStage; AStory: TStory; V, Tier, Bleed: Integer;
  Reason: TLossReason; SpoilsNow: Integer; const Hooks: TSceneHooks): TAnimSequence;
var
  G: TAnimGroup;
begin
  Result := TAnimSequence.Create;
  ToBlack(Result, AStage);
  SetUpRoom(Result, AStage, BleedPortrait(V, Bleed), 1, 1);
  Result.Add(TCallStep.Create(Hooks.OnNo));
  { the vampire's free round: a red flash and a lunge, then he drinks }
  G := TAnimGroup.Create;
  G.Add(TTweenStep.Create(AStage, ssDim, 1, 0, 250, @EaseLinear));
  G.Add(TTweenStep.Create(AStage, ssFlashRed, 0.6, 0, 500, @EaseOutCubic));
  G.Add(TCurveStep.Create(AStage, ssPortraitDX, 550, @SoftShake));
  Result.Add(G);
  if Reason = lrStuck then
    AddLine(Result, AStage, AStory.LostStuck, '', '', True)
  else
    AddLine(Result, AStage, AStory.LostConceded, '', '', True);
  AddLines(Result, AStage, AStory.Taunt(V, Tier), AStory.Name(V), AStory.Title(V), True);
  AddLine(Result, AStage, SafeFormat(AStory.SpoilsNowFormat, [SpoilsNow]), '', '', True);
  CloseScene(Result, AStage);
end;

{ How faded a vampire looks after AWins hits: he wears down a little each time. }
function WornFade(AWins: Integer): Double;
begin
  Result := 1 - 0.15 * AWins;
  if Result < 0.3 then Result := 0.3;
end;

function BuildHitScene(AStage: TStage; AStory: TStory; V, AWin: Integer;
  const AReward: TDuelReward; const Hooks: TSceneHooks): TAnimSequence;
var
  G: TAnimGroup;
begin
  Result := TAnimSequence.Create;
  ToBlack(Result, AStage);
  SetUpRoom(Result, AStage, V, 1, WornFade(AWin - 1));
  Result.Add(TCallStep.Create(Hooks.OnBlow));
  G := TAnimGroup.Create;
  G.Add(TTweenStep.Create(AStage, ssDim, 1, 0, 200, @EaseLinear));
  G.Add(TTweenStep.Create(AStage, ssFlashWhite, 0.6, 0, 450, @EaseOutCubic));
  G.Add(TCurveStep.Create(AStage, ssPortraitDX, 500, @SoftShake));
  Result.Add(G);
  Result.Add(TTweenStep.Create(AStage, ssPortraitFade, WornFade(AWin - 1), WornFade(AWin),
    700, @EaseInOutQuad));
  AddLines(Result, AStage, AStory.Hit(V, AWin), AStory.Name(V), AStory.Title(V), True);
  AddLine(Result, AStage,
    SafeFormat(AStory.HitPaidFormat, [AWin, WinsToKill, AReward.Coins, AReward.HintCards]),
    '', '', True);
  CloseScene(Result, AStage);
end;

function BuildFatalBlowScene(AStage: TStage; AStory: TStory; V: Integer;
  const Hooks: TSceneHooks): TAnimSequence;
var
  G: TAnimGroup;
begin
  Result := TAnimSequence.Create;
  ToBlack(Result, AStage);
  SetUpRoom(Result, AStage, V, 1, WornFade(WinsToKill - 1));
  Result.Add(TCallStep.Create(Hooks.OnBlow));
  G := TAnimGroup.Create;
  G.Add(TTweenStep.Create(AStage, ssDim, 1, 0, 180, @EaseLinear));
  G.Add(TTweenStep.Create(AStage, ssFlashWhite, 1, 0, 600, @EaseOutCubic));
  G.Add(TCurveStep.Create(AStage, ssPortraitDX, 650, @HardShake));
  Result.Add(G);
  { the vampire's light goes out }
  Result.Add(TTweenStep.Create(AStage, ssPortraitFade, WornFade(WinsToKill - 1), 0.3, 900,
    @EaseInOutQuad));
  AddLines(Result, AStage, AStory.Strike(V), '', '', True);
  CloseScene(Result, AStage);
end;

function BuildDefeatScene(AStage: TStage; AStory: TStory; V: Integer;
  const Reward: TDuelReward; const Hooks: TSceneHooks): TAnimSequence;
begin
  Result := TAnimSequence.Create;
  ToBlack(Result, AStage);
  SetUpRoom(Result, AStage, V, 1, 0.3);
  Result.Add(Reveal(AStage, 600));
  AddLines(Result, AStage, AStory.Defeat(V), AStory.Name(V), AStory.Title(V), True);
  AddLine(Result, AStage,
    SafeFormat(AStory.SpoilsPaidFormat, [Reward.Coins, Reward.UndoCards, Reward.HintCards]),
    '', '', True);
  CloseScene(Result, AStage);
end;

function BuildFinaleScene(AStage: TStage; AStory: TStory;
  const Hooks: TSceneHooks): TAnimSequence;
begin
  Result := TAnimSequence.Create;
  ToBlack(Result, AStage);
  SetUpRoom(Result, AStage, -1, 0, 0);
  Result.Add(Reveal(AStage, 700));
  AddLines(Result, AStage, AStory.Finale, '', '', True);
  { lights out, then the three vampires and the caption }
  Result.Add(TTweenStep.Create(AStage, ssDim, 0, 1, FadeMs, @EaseLinear));
  Result.Add(TBackdropStep.Create(AStage, sbWinPicture));
  Result.Add(TTextStep.Create(AStage, stCaption, ''));
  Result.Add(TCallStep.Create(Hooks.OnFanfare));
  Result.Add(Reveal(AStage, 1100));
end;

function BuildSceneForState(AStage: TStage; AStory: TStory; ADuel: TDuel;
  WithPremise: Boolean; const Hooks: TSceneHooks): TAnimSequence;
begin
  case ADuel.State of
    dsIntro: Result := BuildIntroScene(AStage, AStory, ADuel.Vampire, WithPremise, Hooks);
    dsHit: Result := BuildHitScene(AStage, AStory, ADuel.Vampire, ADuel.Wins,
      ADuel.LastReward, Hooks);
    dsFreeRound: Result := BuildFreeRoundScene(AStage, AStory, ADuel.Vampire,
      ADuel.Tier, (ADuel.TotalLost - 1) and 1, ADuel.LastLoss, ADuel.Spoils, Hooks);
    dsFatalBlow: Result := BuildFatalBlowScene(AStage, AStory, ADuel.Vampire, Hooks);
    dsDefeated: Result := BuildDefeatScene(AStage, AStory, ADuel.Vampire,
      ADuel.LastReward, Hooks);
    dsComplete: Result := BuildFinaleScene(AStage, AStory, Hooks);
  else
    Result := nil;                            { dsPlaying: no scene }
  end;
end;

end.
