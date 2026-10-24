program TestScenes;

{$mode objfpc}{$H+}

uses SysUtils, Classes, Anim, Stage, Story, Vampires, Campaign, Duel, Inventory, Scenes{$IFDEF PAS2JS}, JsCompat{$ENDIF};

var
  Failures: Integer = 0;
  TheStory: TStory;

procedure Check(Cond: Boolean; const Msg: string);
begin
  if not Cond then
  begin
    WriteLn('FAIL: ', Msg);
    Inc(Failures);
  end;
end;

type
  THookCounter = class
  public
    Tolls, Nos, Blows, Fanfares: Integer;
    procedure Toll;
    procedure No;
    procedure Blow;
    procedure Fanfare;
    function Hooks: TSceneHooks;
  end;

procedure THookCounter.Toll; begin Inc(Tolls); end;
procedure THookCounter.No; begin Inc(Nos); end;
procedure THookCounter.Blow; begin Inc(Blows); end;
procedure THookCounter.Fanfare; begin Inc(Fanfares); end;

function THookCounter.Hooks: TSceneHooks;
begin
  Result.OnToll := @Toll;
  Result.OnNo := @No;
  Result.OnBlow := @Blow;
  Result.OnFanfare := @Fanfare;
end;

{ Plays a scene out one millisecond at a time and records each line the moment
  it is fully visible, with who is speaking and which portrait is showing. }
type
  TShown = class
  public
    Lines, Speakers, Portraits, Backdrops: TStringList;
    MaxFlashRed, MaxFlashWhite, MaxDX: Double;
    PortraitFadeAtLine: TStringList;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TShown.Create;
begin
  Lines := TStringList.Create;
  Speakers := TStringList.Create;
  Portraits := TStringList.Create;
  Backdrops := TStringList.Create;
  PortraitFadeAtLine := TStringList.Create;
end;

destructor TShown.Destroy;
begin
  Lines.Free; Speakers.Free; Portraits.Free; Backdrops.Free; PortraitFadeAtLine.Free;
  inherited Destroy;
end;

procedure Observe(St: TStage; R: TShown);
begin
  if St.Scalar[ssFlashRed] > R.MaxFlashRed then R.MaxFlashRed := St.Scalar[ssFlashRed];
  if St.Scalar[ssFlashWhite] > R.MaxFlashWhite then R.MaxFlashWhite := St.Scalar[ssFlashWhite];
  if Abs(St.Scalar[ssPortraitDX]) > R.MaxDX then R.MaxDX := Abs(St.Scalar[ssPortraitDX]);
  if (St.Scalar[ssTextFade] >= 0.99) and (St.Caption <> '') then
    if (R.Lines.Count = 0) or (R.Lines[R.Lines.Count - 1] <> St.Caption) then
    begin
      R.Lines.Add(St.Caption);
      R.Speakers.Add(St.SpeakerName);
      R.Portraits.Add(IntToStr(St.PortraitId));
      R.Backdrops.Add(IntToStr(Ord(St.Backdrop)));
      R.PortraitFadeAtLine.Add(FloatToStrF(St.Scalar[ssPortraitFade], ffFixed, 6, 2));
    end;
end;

procedure PlayOut(Seq: TAnimSequence; St: TStage; R: TShown);
var
  I, Total, Clicks: Integer;
begin
  Total := Seq.TotalDuration;
  Clicks := 0;
  Seq.Advance(0);
  Observe(St, R);
  for I := 1 to Total + 5 do
  begin
    Seq.Advance(1);
    Observe(St, R);
    { a scene that waits for the player: click once the line has been read }
    while Seq.WaitingForClick do
    begin
      Seq.SkipToMark;
      Inc(Clicks);
      Seq.Advance(0);
      Observe(St, R);
      if Clicks > 1000 then Break;
    end;
  end;
end;

{ What a vampire says when he is introduced: his intro lines, then the trick line. }
function Spoken(V: Integer): TStringArray;
var
  A, B: TStringArray;
  I: Integer;
begin
  A := TheStory.Intro(V);
  B := TheStory.Trick(V);
  SetLength(Result, Length(A) + Length(B));
  for I := 0 to High(A) do Result[I] := A[I];
  for I := 0 to High(B) do Result[Length(A) + I] := B[I];
end;

function Joined(const A: TStringArray): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(A) do Result := Result + A[I] + '|';
end;

function JoinedList(L: TStringList): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to L.Count - 1 do Result := Result + L[I] + '|';
end;

procedure TestHelpers;
begin
  Check(SafeFormat('Pay %d coins', [5]) = 'Pay 5 coins', 'SafeFormat formats');
  Check(SafeFormat('%d and %d', [1]) = '%d and %d', 'SafeFormat returns the text as written when the numbers do not match');
  Check(SafeFormat('no numbers here', [5]) = 'no numbers here', 'SafeFormat tolerates a text with no placeholders');
  Check(LineHoldMs('') = HoldBaseMs, 'an empty line holds the base time');
  Check(LineHoldMs('a longer line of text') > LineHoldMs('short'), 'longer lines are held longer');
  Check(LineHoldMs(StringOfChar('x', 5000)) = HoldMaxMs, 'holding time is capped');
end;

procedure TestIntro;
var
  V, I: Integer;
  St: TStage;
  Seq: TAnimSequence;
  R: TShown;
  H: THookCounter;
  Expect: TStringArray;
begin
  for V := 0 to VampireCount - 1 do
  begin
    St := TStage.Create;
    H := THookCounter.Create;
    R := TShown.Create;
    Seq := BuildIntroScene(St, TheStory, V, False, H.Hooks);
    try
      { no timer to read by: only the fades take time; the player supplies the rest }
      Check((Seq.TotalDuration > 1000) and (Seq.TotalDuration < 10000),
        'intro ' + IntToStr(V) + ' has only its fades as timed length (' + IntToStr(Seq.TotalDuration) + ' ms)');
      PlayOut(Seq, St, R);
      Expect := Spoken(V);
      Check(JoinedList(R.Lines) = Joined(Expect), 'intro ' + IntToStr(V) + ' shows the intro lines in order: ' + JoinedList(R.Lines));
      for I := 0 to R.Speakers.Count - 1 do
      begin
        Check(R.Speakers[I] = TheStory.Name(V), 'the vampire speaks his intro');
        Check(R.Portraits[I] = IntToStr(V), 'his portrait is showing');
      end;
      Check(H.Tolls = 1, 'the bell tolls once');
      Check(not Seq.Running, 'the scene ends');
      Check(St.Backdrop = sbTable, 'back to the table');
      Check(St.Scalar[ssDim] = 1, 'and left black for the next thing to fade in');
      Check(St.Scalar[ssTextFade] = 0, 'with no text left showing');
      Check(St.Caption = '', 'caption cleared');
    finally
      Seq.Free; R.Free; H.Free; St.Free;
    end;
  end;

  { with the opening premise first }
  St := TStage.Create;
  H := THookCounter.Create;
  R := TShown.Create;
  Seq := BuildIntroScene(St, TheStory, 0, True, H.Hooks);
  try
    PlayOut(Seq, St, R);
    Expect := TheStory.Premise;
    Check(R.Lines.Count = Length(Expect) + Length(Spoken(0)), 'premise lines come before the intro lines');
    for I := 0 to High(Expect) do
    begin
      Check(R.Lines[I] = Expect[I], 'premise line ' + IntToStr(I) + ' in order');
      Check(R.Speakers[I] = '', 'the premise is narration (no speaker)');
      Check(R.Portraits[I] = '-1', 'no portrait during the premise');
      Check(R.Backdrops[I] = IntToStr(Ord(sbHouse)), 'the premise is told over the picture of the house');
    end;
    Check(R.Lines[Length(Expect)] = Spoken(0)[0], 'the first intro line follows');
    Check(R.Portraits[Length(Expect)] = '0', 'the vampire has appeared by then');
    Check(R.Backdrops[Length(Expect)] = IntToStr(Ord(sbDialogue)), 'in the dark room, not in front of the house');
    Check(St.Backdrop = sbTable, 'and the scene ends back on the table');
  finally
    Seq.Free; R.Free; H.Free; St.Free;
  end;
end;

procedure TestIntroWaitsForClicks;
var
  St: TStage;
  Seq: TAnimSequence;
  H: THookCounter;
  Intro: TStringArray;
  Hold, I, K: Integer;
begin
  Intro := Spoken(0);
  St := TStage.Create;
  H := THookCounter.Create;
  Seq := BuildIntroScene(St, TheStory, 0, False, H.Hooks);
  try
    { run a very long time without any click: it must still be on the first line }
    Seq.Advance(0);
    for I := 1 to 60 do Seq.Advance(1000);                { a whole minute }
    Check(Seq.Running, 'a minute with no click: the scene is still going');
    Check(St.Caption = Intro[0], 'and still on the first line');
    Check(St.Scalar[ssTextFade] > 0.99, 'fully visible, not fading out by itself');
    Check(St.WaitingForClick, 'the stage says it is waiting for a click');
    Check(Seq.WaitingForClick, 'and so does the sequence');
    { even a very long line is not timed out }
    Hold := LineHoldMs(Intro[0]);
    Check(Hold < 60000, 'the old timer would have moved on long before this');

    { a click lets it go, with the fade-out playing }
    Seq.SkipToMark;
    Check(not Seq.WaitingForClick, 'a click releases the wait');
    Seq.Advance(TextFadeOutMs div 2);
    Check((St.Scalar[ssTextFade] > 0.0) and (St.Scalar[ssTextFade] < 1.0), 'the line fades out rather than vanishing');
    Check(not St.WaitingForClick, 'and the click cue is gone');
    Seq.Advance(TextFadeOutMs + TextFadeInMs + 20);
    Check(St.Caption = Intro[1], 'then the next line comes');
    Check(Seq.Running, 'still going');

    { clicking while a line is still fading in shows it in full but does not skip it }
    Seq.Advance(20000);
    K := 0;
    while (St.Caption <> Intro[High(Intro)]) and (K < 10) do     { click on to the last line }
    begin
      Seq.SkipToMark;
      Seq.Advance(20000);
      Inc(K);
    end;
    Check(St.Caption = Intro[Length(Intro) - 1], 'the last line is up again after waiting');
    Check(St.WaitingForClick, 'and it waits too');
    { the last click ends the scene by itself: no extra click needed for the closing fade }
    Seq.SkipToMark;
    for K := 1 to 40 do Seq.Advance(100);
    Check(not Seq.Running, 'after the last line is clicked the scene finishes on its own');
    Check(St.Backdrop = sbTable, 'back on the table');
    Check(not St.WaitingForClick, 'no longer waiting');
  finally
    Seq.Free; H.Free; St.Free;
  end;

  { a click during the fade-in shows the line in full and stops there: it does not skip it }
  St := TStage.Create;
  H := THookCounter.Create;
  Seq := BuildIntroScene(St, TheStory, 0, False, H.Hooks);
  try
    Seq.Advance(0);
    I := 0;
    while St.Caption <> Intro[0] do
    begin
      Seq.Advance(1);
      Inc(I);
      if I > 20000 then Break;
    end;
    Check(St.Caption = Intro[0], 'the first line has begun to appear');
    Check(St.Scalar[ssTextFade] < 0.99, 'and is still fading in');
    Seq.SkipToMark;                                       { an impatient click }
    Check(St.Scalar[ssTextFade] >= 0.99, 'a click during the fade-in shows the line in full');
    Check(St.Caption = Intro[0], 'but stays on the same line');
    Seq.Advance(0);
    Check(Seq.WaitingForClick, 'and then waits for the next click to move on');
  finally
    Seq.Free; H.Free; St.Free;
  end;
end;

procedure TestFreeRound;
var
  St: TStage;
  Seq: TAnimSequence;
  R: TShown;
  H: THookCounter;
  Taunt: TStringArray;
  I: Integer;
begin
  St := TStage.Create;
  H := THookCounter.Create;
  R := TShown.Create;
  Seq := BuildFreeRoundScene(St, TheStory, 1, 2, 0, lrStuck, 30, H.Hooks);
  try
    PlayOut(Seq, St, R);
    Taunt := TheStory.Taunt(1, 2);
    Check(R.Lines.Count = Length(Taunt) + 2, 'narration, taunt, then the spoils line');
    Check(R.Lines[0] = TheStory.LostStuck, 'a stuck hand is narrated first');
    Check(R.Speakers[0] = '', 'the narration has no speaker');
    for I := 0 to High(Taunt) do
    begin
      Check(R.Lines[1 + I] = Taunt[I], 'the tier-2 taunt is spoken');
      Check(R.Speakers[1 + I] = TheStory.Name(1), 'by the Queen');
    end;
    Check(Pos('30', R.Lines[R.Lines.Count - 1]) > 0, 'the spoils line shows the coins: ' + R.Lines[R.Lines.Count - 1]);
    Check(R.Portraits[0] = IntToStr(BleedPortrait(1, 0)), 'her portrait is showing, blood on her fangs');
    Check(R.Backdrops[0] = IntToStr(Ord(sbDialogue)), 'in the dark room');
    Check(H.Nos = 1, 'the "no" sound plays once');
    Check(R.MaxFlashRed > 0.4, 'there is a red flash');
    Check(R.MaxDX > 0.01, 'the portrait shakes');
    Check(St.Backdrop = sbTable, 'ends back on the table');
    Check(St.Scalar[ssDim] = 1, 'ends black');
    Check(St.Scalar[ssFlashRed] < 0.01, 'the flash has died away');
  finally
    Seq.Free; R.Free; H.Free; St.Free;
  end;

  { conceding reads differently from being stuck }
  St := TStage.Create;
  H := THookCounter.Create;
  R := TShown.Create;
  Seq := BuildFreeRoundScene(St, TheStory, 0, 1, 1, lrConceded, 20, H.Hooks);
  try
    PlayOut(Seq, St, R);
    Check(R.Lines[0] = TheStory.LostConceded, 'a conceded hand is narrated as conceded');
    Check(R.Lines[1] = TheStory.Taunt(0, 1)[0], 'tier 1 taunt for the first lost hand');
    Check(R.Portraits[0] = IntToStr(BleedPortrait(0, 1)), 'and the other picture: the goblet of your blood');
  finally
    Seq.Free; R.Free; H.Free; St.Free;
  end;
end;

procedure TestHit;
var
  St: TStage;
  Seq: TAnimSequence;
  R: TShown;
  H: THookCounter;
  Rew: TDuelReward;
  N: Integer;
  Fade: string;
begin
  Rew.Coins := 12;
  Rew.UndoCards := 0;
  Rew.HintCards := HitHintCards;
  for N := 1 to WinsToKill - 1 do
  begin
    St := TStage.Create;
    H := THookCounter.Create;
    R := TShown.Create;
    Seq := BuildHitScene(St, TheStory, 1, N, Rew, H.Hooks);
    try
      PlayOut(Seq, St, R);
      Check(R.Lines.Count = Length(TheStory.Hit(1, N)) + 1, 'hit ' + IntToStr(N) + ': the reaction plus the pay line');
      Check(R.Lines[0] = TheStory.Hit(1, N)[0], 'hit ' + IntToStr(N) + ': the vampire''s own line for this win');
      Check(R.Speakers[0] = TheStory.Name(1), 'hit ' + IntToStr(N) + ': the vampire speaks');
      Check(R.Speakers[R.Speakers.Count - 1] = '', 'hit ' + IntToStr(N) + ': the pay is narrated');
      Check(R.Lines[R.Lines.Count - 1] = SafeFormat(TheStory.HitPaidFormat,
        [N, WinsToKill, 12, HitHintCards]), 'hit ' + IntToStr(N) + ': the pay line names the win and the pay');
      Check(H.Blows = 1, 'hit ' + IntToStr(N) + ': one blow sound');
      Check(R.MaxFlashWhite > 0.5, 'hit ' + IntToStr(N) + ': a flash');
      Check(R.MaxDX > 0.01, 'hit ' + IntToStr(N) + ': the portrait is hit');
      Fade := FloatToStrF(1 - 0.15 * N, ffFixed, 6, 2);
      Check(R.PortraitFadeAtLine[0] = Fade, 'hit ' + IntToStr(N) + ': he looks more worn (' + R.PortraitFadeAtLine[0] + ' vs ' + Fade + ')');
      Check(St.Backdrop = sbTable, 'hit ' + IntToStr(N) + ': back on the table');
      Check(St.Scalar[ssDim] = 1, 'hit ' + IntToStr(N) + ': ends black, ready for the next hand');
    finally
      Seq.Free; R.Free; H.Free; St.Free;
    end;
  end;
end;

procedure TestFatalBlowAndDefeat;
var
  St: TStage;
  Seq: TAnimSequence;
  R: TShown;
  H: THookCounter;
  Rew: TDuelReward;
  I: Integer;
begin
  St := TStage.Create;
  H := THookCounter.Create;
  R := TShown.Create;
  Seq := BuildFatalBlowScene(St, TheStory, 2, H.Hooks);
  try
    PlayOut(Seq, St, R);
    Check(JoinedList(R.Lines) = Joined(TheStory.Strike(2)), 'the strike lines are shown');
    Check(R.Speakers[0] = '', 'narrated');
    Check(H.Blows = 1, 'the blow lands once');
    Check(R.MaxFlashWhite > 0.9, 'a white flash');
    Check(R.MaxDX > 0.02, 'the portrait is hit hard');
    Check(R.PortraitFadeAtLine[0] = '0.30', 'the vampire''s light has gone down while the line shows (' + R.PortraitFadeAtLine[0] + ')');
    Check(St.Backdrop = sbTable, 'back on the table');
  finally
    Seq.Free; R.Free; H.Free; St.Free;
  end;

  Rew.Coins := 35;
  Rew.UndoCards := 1;
  Rew.HintCards := 2;
  St := TStage.Create;
  H := THookCounter.Create;
  R := TShown.Create;
  Seq := BuildDefeatScene(St, TheStory, 1, Rew, H.Hooks);
  try
    PlayOut(Seq, St, R);
    Check(R.Lines.Count = Length(TheStory.Defeat(1)) + 1, 'defeat lines plus the spoils line');
    for I := 0 to High(TheStory.Defeat(1)) do
    begin
      Check(R.Lines[I] = TheStory.Defeat(1)[I], 'defeat line ' + IntToStr(I));
      Check(R.Speakers[I] = TheStory.Name(1), 'the vampire speaks her last words');
      Check(R.PortraitFadeAtLine[I] = '0.30', 'her portrait is dim');
    end;
    Check((Pos('35', R.Lines[R.Lines.Count - 1]) > 0) and (Pos('2', R.Lines[R.Lines.Count - 1]) > 0),
      'the spoils line lists the reward: ' + R.Lines[R.Lines.Count - 1]);
    Check(R.Speakers[R.Speakers.Count - 1] = '', 'the spoils are narrated');
  finally
    Seq.Free; R.Free; H.Free; St.Free;
  end;
end;

procedure TestFinale;
var
  St: TStage;
  Seq: TAnimSequence;
  R: TShown;
  H: THookCounter;
begin
  St := TStage.Create;
  H := THookCounter.Create;
  R := TShown.Create;
  Seq := BuildFinaleScene(St, TheStory, H.Hooks);
  try
    PlayOut(Seq, St, R);
    Check(JoinedList(R.Lines) = Joined(TheStory.Finale), 'the finale lines are shown');
    Check(H.Fanfares = 1, 'the fanfare plays once');
    Check(not Seq.Running, 'finished');
    Check(St.Backdrop = sbWinPicture, 'it ends on the victory picture and stays there');
    Check(St.Scalar[ssDim] = 0, 'fully revealed');
    Check(St.Caption = '', 'no caption over the picture (it is baked in)');
  finally
    Seq.Free; R.Free; H.Free; St.Free;
  end;
end;

procedure TestDispatch;
var
  C: TCampaign;
  D: TDuel;
  St: TStage;
  H: THookCounter;
  Seq: TAnimSequence;
  R: TShown;

  procedure Run(const What: string; ExpectNil: Boolean);
  begin
    Seq := BuildSceneForState(St, TheStory, D, False, H.Hooks);
    try
      if ExpectNil then
        Check(Seq = nil, What + ': no scene while a hand is being played')
      else
      begin
        Check(Seq <> nil, What + ': has a scene');
        if Seq <> nil then
        begin
          R.Lines.Clear; R.Speakers.Clear; R.Portraits.Clear; R.Backdrops.Clear; R.PortraitFadeAtLine.Clear;
          PlayOut(Seq, St, R);
          Check(R.Lines.Count > 0, What + ': shows some text');
        end;
      end;
    finally
      Seq.Free;
    end;
  end;

begin
  C := TCampaign.Create('');
  D := TDuel.Create(C);
  St := TStage.Create;
  H := THookCounter.Create;
  R := TShown.Create;
  try
    Run('intro', False);
    D.SceneDone;
    Run('playing', True);
    D.HandLost(lrStuck);
    Run('free round', False);
    Check(R.Lines[1] = TheStory.Taunt(0, 1)[0], 'the free round uses the duel''s taunt tier');
    Check(R.Portraits[0] = IntToStr(BleedPortrait(0, 0)), 'the first lost hand: blood on his fangs');
    Check(R.Lines[R.Lines.Count - 1] = SafeFormat(TheStory.SpoilsNowFormat, [VampireWinCoins[0] - SpoilsStep]),
      'and what the next win pays now, after the lost hand');
    D.SceneDone;
    D.HandLost(lrConceded);
    Run('second free round', False);
    Check(R.Portraits[0] = IntToStr(BleedPortrait(0, 1)), 'the second: the goblet of your blood');
    D.SceneDone;
    D.HandLost(lrStuck);
    Run('third free round', False);
    Check(R.Portraits[0] = IntToStr(BleedPortrait(0, 0)), 'the third: back to the fangs');
    D.SceneDone;
    D.HandWon;
    Run('hit', False);
    Check(R.Lines[0] = TheStory.Hit(0, 1)[0], 'the hit scene shows the vampire''s reaction to the first win');
    Check(R.Lines[R.Lines.Count - 1] = SafeFormat(TheStory.HitPaidFormat,
      [1, WinsToKill, VampireWinCoins[0] - 3 * SpoilsStep, HitHintCards]), 'and what the win paid (the lost hands cut it)');
    D.SceneDone;
    D.HandWon; D.SceneDone; D.HandWon; D.SceneDone; D.HandWon; D.SceneDone;
    D.HandWon;
    Run('fatal blow', False);
    D.SceneDone;
    Run('defeat', False);
    Check(R.Lines[R.Lines.Count - 1] = SafeFormat(TheStory.SpoilsPaidFormat,
      [VampireWinCoins[0] + VampireKillBonus[0], WinUndoCards, WinHintCards]),
      'the defeat scene lists what the kill paid');
    D.SceneDone;
    Check(D.State = dsIntro, 'next vampire');
    Check(St.Scalar[ssDim] = 1, 'the stage is black between scenes');
    C.Advance; C.Advance;                  { jump to the end of the campaign }
    D.Start;
    Run('finale', False);
    Check(St.Backdrop = sbWinPicture, 'the finale ends on the victory picture');
  finally
    R.Free; H.Free; St.Free; D.Free; C.Free;
  end;
end;

procedure TestSkipping;
var
  St, St2: TStage;
  Seq, Seq2: TAnimSequence;
  H, H2: THookCounter;
  R: TShown;
  Intro: TStringArray;
  I, K: Integer;
begin
  Intro := Spoken(0);
  Check(Length(Intro) >= 2, 'the first intro has at least two lines to click through');
  St := TStage.Create;
  H := THookCounter.Create;
  Seq := BuildIntroScene(St, TheStory, 0, False, H.Hooks);
  try
    Seq.Advance(0);
    I := 0;
    while not Seq.WaitingForClick do                  { until the first line is up and waiting }
    begin
      Seq.Advance(1);
      Inc(I);
      if I > 20000 then Break;
    end;
    Check(St.Caption = Intro[0], 'the first line is up');
    { click through every remaining line }
    for K := 2 to Length(Intro) do
    begin
      Seq.SkipToMark;
      Seq.Advance(TextFadeOutMs + TextFadeInMs + 20);
      Check(St.Caption = Intro[K - 1], 'a click brings line ' + IntToStr(K));
    end;
    Seq.SkipToMark;                                    { the click on the last line }
    for K := 1 to 40 do Seq.Advance(100);
    Check(not Seq.Running, 'clicking past the last line ends the scene');
    Check(St.Backdrop = sbTable, 'which leaves the stage tidy');
    Check(St.Scalar[ssDim] = 1, 'and black');
  finally
    Seq.Free; H.Free; St.Free;
  end;

  { Esc skips the whole intro, waiting steps included, to the same end state as clicking through }
  St := TStage.Create; St2 := TStage.Create;
  H := THookCounter.Create; H2 := THookCounter.Create;
  Seq := BuildIntroScene(St, TheStory, 1, False, H.Hooks);
  Seq2 := BuildIntroScene(St2, TheStory, 1, False, H2.Hooks);
  R := TShown.Create;
  try
    Seq.Advance(0);
    Seq.Skip;
    PlayOut(Seq2, St2, R);
    Check(not Seq.Running, 'skip finishes the intro even though it waits for clicks');
    Check((St.Backdrop = St2.Backdrop) and (St.Scalar[ssDim] = St2.Scalar[ssDim])
      and (St.Caption = St2.Caption) and (St.WaitingForClick = St2.WaitingForClick),
      'skipping ends in exactly the state clicking through does');
    Check(not St.WaitingForClick, 'with no click cue left showing');
    Check(H.Tolls = 1, 'the bell still tolls once when skipped');
  finally
    Seq.Free; Seq2.Free; R.Free; H.Free; H2.Free; St.Free; St2.Free;
  end;

  { the free round waits for clicks too, and skips as before }
  St := TStage.Create; St2 := TStage.Create;
  H := THookCounter.Create; H2 := THookCounter.Create;
  Seq := BuildFreeRoundScene(St, TheStory, 2, 3, 1, lrConceded, 15, H.Hooks);
  Seq2 := BuildFreeRoundScene(St2, TheStory, 2, 3, 1, lrConceded, 15, H2.Hooks);
  R := TShown.Create;
  try
    Seq.Advance(0);
    Seq.Skip;
    PlayOut(Seq2, St2, R);
    Check(not Seq.Running, 'skip finishes the scene');
    Check((St.Backdrop = St2.Backdrop) and (St.Scalar[ssDim] = St2.Scalar[ssDim])
      and (St.Scalar[ssFlashRed] = St2.Scalar[ssFlashRed]) and (St.Caption = St2.Caption)
      and (St.Scalar[ssPortraitDX] = St2.Scalar[ssPortraitDX]),
      'skipping ends in exactly the state playing it out does');
    Check(H.Nos = 1, 'the sound still plays once when skipped');
  finally
    Seq.Free; Seq2.Free; R.Free; H.Free; H2.Free; St.Free; St2.Free;
  end;
end;

{ Plays a scene the way a patient player does, clicking whenever it waits;
  returns how many clicks it took. Fails the test if the scene never ends. }
function ClicksToFinish(Seq: TAnimSequence): Integer;
var
  I: Integer;
begin
  Result := 0;
  Seq.Advance(0);
  for I := 1 to 20000 do
  begin
    Seq.Advance(100);
    if Seq.WaitingForClick then
    begin
      Inc(Result);
      Seq.SkipToMark;
    end;
    if not Seq.Running then Break;
  end;
end;

procedure TestEveryLineWaits;
var
  St: TStage;
  H: THookCounter;
  Seq: TAnimSequence;
  Reward: TDuelReward;
  N: Integer;

  procedure Expect(const What: string; AExpected: Integer);
  begin
    N := ClicksToFinish(Seq);
    Check(not Seq.Running, What + ' ends once clicked through');
    Check(N = AExpected, What + ': one click per line (' + IntToStr(N) + ' vs '
      + IntToStr(AExpected) + ')');
    Seq.Free;
  end;

begin
  St := TStage.Create;
  H := THookCounter.Create;
  try
    Reward.Coins := 25; Reward.UndoCards := 1; Reward.HintCards := 2;
    Seq := BuildFreeRoundScene(St, TheStory, 2, 3, 1, lrConceded, 15, H.Hooks);
    Expect('the free round (conceded)', 1 + Length(TheStory.Taunt(2, 3)) + 1);
    St.Scalar[ssDim] := 1;
    Seq := BuildFreeRoundScene(St, TheStory, 2, 3, 1, lrStuck, 15, H.Hooks);
    Expect('the free round (stuck)', 1 + Length(TheStory.Taunt(2, 3)) + 1);
    St.Scalar[ssDim] := 1;
    Seq := BuildHitScene(St, TheStory, 1, 3, Reward, H.Hooks);
    Expect('a hit', Length(TheStory.Hit(1, 3)) + 1);
    St.Scalar[ssDim] := 1;
    Seq := BuildFatalBlowScene(St, TheStory, 1, H.Hooks);
    Expect('the fatal blow', Length(TheStory.Strike(1)));
    St.Scalar[ssDim] := 1;
    Seq := BuildDefeatScene(St, TheStory, 1, Reward, H.Hooks);
    Expect('the defeat', Length(TheStory.Defeat(1)) + 1);
    St.Scalar[ssDim] := 1;
    Seq := BuildFinaleScene(St, TheStory, H.Hooks);
    Expect('the finale', Length(TheStory.Finale));
  finally
    H.Free; St.Free;
  end;
end;

begin
  CrossCardsOn := False;                  { where the silver cross lies is random: it has its own tests }
  TheStory := TStory.Create;
{$IFDEF PAS2JS}
  TheStory.LoadFromFile('assets/story/story.ini');           { run from the project folder }
{$ELSE}
  TheStory.LoadFromFile(ExtractFilePath(ParamStr(0)) + '../assets/story/story.ini');
{$ENDIF}
  try
    if Length(TheStory.Validate) > 0 then
    begin
      WriteLn('FAIL: story file incomplete: ', TheStory.Validate[0]);
      Halt(1);
    end;
    TestHelpers;
    TestIntro;
    TestIntroWaitsForClicks;
    TestFreeRound;
    TestHit;
    TestFatalBlowAndDefeat;
    TestFinale;
    TestDispatch;
    TestSkipping;
    TestEveryLineWaits;
  finally
    TheStory.Free;
  end;
  if Failures = 0 then WriteLn('ALL SCENE TESTS PASSED') else
  begin
    WriteLn(Failures, ' FAILURES');
    Halt(1);
  end;
end.
