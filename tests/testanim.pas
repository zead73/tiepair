program TestAnim;

{$mode objfpc}{$H+}

uses SysUtils, Classes, Anim, Stage, NewGameAnim, Sound{$IFDEF PAS2JS}, JsCompat{$ENDIF};

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

type
  { Records everything the sequencer does to it. }
  TRecStep = class(TAnimStep)
  public
    Name: string;
    Dur: Integer;
    Log: TStringList;
    LastT: Integer;
    Starts, Finishes: Integer;
    constructor Create(const AName: string; ADur: Integer; ALog: TStringList);
    function Duration: Integer; override;
    procedure Start; override;
    procedure Update(T: Integer); override;
    procedure Finish; override;
  end;

  TCounter = class
  public
    N: Integer;
    procedure Bump;
  end;

constructor TRecStep.Create(const AName: string; ADur: Integer; ALog: TStringList);
begin
  inherited Create;
  Name := AName;
  Dur := ADur;
  Log := ALog;
  LastT := -1;
end;

function TRecStep.Duration: Integer;
begin
  Result := Dur;
end;

procedure TRecStep.Start;
begin
  Inc(Starts);
  Log.Add('start ' + Name);
end;

procedure TRecStep.Update(T: Integer);
begin
  LastT := T;
end;

procedure TRecStep.Finish;
begin
  Inc(Finishes);
  Log.Add('finish ' + Name + ' lastT=' + IntToStr(LastT));
end;

procedure TCounter.Bump;
begin
  Inc(N);
end;

procedure TestEasing;
var
  I: Integer;
  Prev, V: Double;
begin
  Check(EaseLinear(0) = 0, 'linear 0');
  Check(Abs(EaseLinear(1) - 1) < 1e-9, 'linear 1');
  Check(Abs(EaseOutCubic(0)) < 1e-9, 'out cubic 0');
  Check(Abs(EaseOutCubic(1) - 1) < 1e-9, 'out cubic 1');
  Check(Abs(EaseInOutQuad(0)) < 1e-9, 'in-out 0');
  Check(Abs(EaseInOutQuad(1) - 1) < 1e-9, 'in-out 1');
  Check(Abs(EaseInOutQuad(0.5) - 0.5) < 1e-9, 'in-out midpoint');
  Check(Abs(EaseOutCubic(0.5) - 0.875) < 1e-9, 'out cubic at 0.5 is 0.875 (starts fast)');
  Check(Abs(EaseOutCubic(0.25) - 0.578125) < 1e-9, 'out cubic at 0.25');
  Check(Abs(EaseInOutQuad(0.25) - 0.125) < 1e-9, 'in-out at 0.25 (slow start)');
  Check(Abs(EaseInOutQuad(0.75) - 0.875) < 1e-9, 'in-out at 0.75 (slow end)');
  Check(Abs(EaseLinear(0.3) - 0.3) < 1e-9, 'linear is the identity');
  Prev := -1;
  for I := 0 to 100 do
  begin
    V := EaseOutCubic(I / 100);
    Check(V >= Prev, 'out cubic never goes backwards');
    Prev := V;
  end;
  Prev := -1;
  for I := 0 to 100 do
  begin
    V := EaseInOutQuad(I / 100);
    Check((V >= Prev) and (V >= 0) and (V <= 1), 'in-out stays in range and never goes backwards');
    Prev := V;
  end;
end;

procedure TestSequenceOrder;
var
  Seq: TAnimSequence;
  Log: TStringList;
  A, B: TRecStep;
begin
  Log := TStringList.Create;
  Seq := TAnimSequence.Create;
  try
    A := TRecStep.Create('A', 100, Log);
    B := TRecStep.Create('B', 50, Log);
    Seq.Add(A);
    Seq.Add(B);
    Check(Seq.TotalDuration = 150, 'total duration 150');
    Check(Seq.Running, 'running before any time passes');
    Seq.Advance(0);
    Check(A.Starts = 1, 'A starts at time 0');
    Seq.Advance(60);
    Check(A.LastT = 60, 'A at 60 ms');
    Check(A.Finishes = 0, 'A not finished yet');
    Seq.Advance(60);                       { 120 total: A done, B at 20 }
    Check(A.Finishes = 1, 'A finished');
    Check(A.LastT = 100, 'A got its final update at exactly its duration');
    Check(B.Starts = 1, 'B started');
    Check(B.LastT = 20, 'B carries the leftover time (20 ms)');
    Seq.Advance(1000);                     { way past the end }
    Check(B.Finishes = 1, 'B finished');
    Check(B.LastT = 50, 'B ends at its duration, never beyond');
    Check(not Seq.Running, 'sequence ended');
    Check((A.Starts = 1) and (A.Finishes = 1) and (B.Starts = 1) and (B.Finishes = 1),
      'every step started and finished exactly once');
    Check(Log.Text = 'start A'#10'finish A lastT=100'#10'start B'#10'finish B lastT=50'#10,
      'events happen in order: ' + StringReplace(Log.Text, #10, ' | ', [rfReplaceAll]));
    Seq.Advance(500);                      { advancing a finished sequence is harmless }
    Check(A.Finishes = 1, 'no double finish');
  finally
    Seq.Free;                               { owns the steps }
    Log.Free;
  end;
end;

procedure TestChunksEqualJump;
var
  S1, S2: TAnimSequence;
  L1, L2: TStringList;
  I: Integer;
begin
  L1 := TStringList.Create;
  L2 := TStringList.Create;
  S1 := TAnimSequence.Create;
  S2 := TAnimSequence.Create;
  try
    S1.Add(TRecStep.Create('A', 130, L1));
    S1.Add(TRecStep.Create('B', 0, L1));
    S1.Add(TRecStep.Create('C', 77, L1));
    S2.Add(TRecStep.Create('A', 130, L2));
    S2.Add(TRecStep.Create('B', 0, L2));
    S2.Add(TRecStep.Create('C', 77, L2));
    for I := 1 to 400 do S1.Advance(1);    { 1 ms at a time }
    S2.Advance(400);                        { one big jump }
    Check(L1.Text = L2.Text, 'tiny steps and one jump give identical events');
    Check(not S1.Running and not S2.Running, 'both finished');
  finally
    S1.Free; S2.Free; L1.Free; L2.Free;
  end;
end;

procedure TestSkip;
var
  Seq: TAnimSequence;
  Log: TStringList;
  A, B, C: TRecStep;
begin
  Log := TStringList.Create;
  Seq := TAnimSequence.Create;
  try
    A := TRecStep.Create('A', 100, Log);
    B := TRecStep.Create('B', 100, Log);
    C := TRecStep.Create('C', 100, Log);
    Seq.Add(A); Seq.Add(B); Seq.Add(C);
    Seq.Advance(150);                       { A done, B halfway }
    Seq.Skip;
    Check(not Seq.Running, 'skip ends the sequence');
    Check(B.LastT = 100, 'skipped step reaches its final state');
    Check(C.Starts = 1, 'a step skipped before it began is still started');
    Check(C.LastT = 100, 'and brought to its final state');
    Check((A.Finishes = 1) and (B.Finishes = 1) and (C.Finishes = 1),
      'every step finished exactly once');
    Check(B.Starts = 1, 'the half-run step is not started twice');
    Seq.Skip;
    Check(C.Finishes = 1, 'a second skip does nothing');
  finally
    Seq.Free;
    Log.Free;
  end;
end;

procedure TestCallAndWait;
var
  Seq: TAnimSequence;
  C: TCounter;
begin
  C := TCounter.Create;
  Seq := TAnimSequence.Create;
  try
    Seq.Add(TCallStep.Create(@C.Bump));
    Seq.Add(TWaitStep.Create(50));
    Seq.Add(TCallStep.Create(@C.Bump));
    Seq.Advance(0);
    Check(C.N = 1, 'first action runs at time 0');
    Seq.Advance(49);
    Check(C.N = 1, 'second action waits for the wait step');
    Seq.Advance(1);
    Check(C.N = 2, 'second action runs when the wait ends');
    Check(not Seq.Running, 'done');
    Seq.Advance(100);
    Check(C.N = 2, 'actions never run twice');
  finally
    Seq.Free;
    C.Free;
  end;
  { a nil action is allowed (the new-game sequence passes one when no sound) }
  Seq := TAnimSequence.Create;
  try
    Seq.Add(TCallStep.Create(nil));
    Seq.Advance(1);
    Check(not Seq.Running, 'nil action is harmless');
  finally
    Seq.Free;
  end;
end;

procedure TestGroup;
var
  Seq: TAnimSequence;
  G: TAnimGroup;
  Log: TStringList;
  A, B: TRecStep;
begin
  Log := TStringList.Create;
  Seq := TAnimSequence.Create;
  try
    G := TAnimGroup.Create;
    A := TRecStep.Create('A', 100, Log);
    B := TRecStep.Create('B', 40, Log);
    G.Add(A); G.Add(B);
    Seq.Add(G);
    Check(G.Duration = 100, 'group lasts as long as its longest child');
    Seq.Advance(70);
    Check(A.LastT = 70, 'long child at 70');
    Check(B.LastT = 40, 'short child clamps at its own end');
    Check((A.Starts = 1) and (B.Starts = 1), 'both children started together');
    Seq.Advance(100);
    Check((A.Finishes = 1) and (B.Finishes = 1), 'both children finish once');
    Check(A.LastT = 100, 'long child ends at 100');
  finally
    Seq.Free;
    Log.Free;
  end;
end;

procedure TestStagger;
var
  St: TStage;
  Step: TStaggerStep;
begin
  St := TStage.Create;
  try
    Step := TStaggerStep.Create(St, sfMove, [5, 6, 7], 100, 200, @EaseLinear);
    try
      Check(Step.Duration = 2 * 100 + 200, 'stagger duration = (n-1)*stagger + dur');
      Step.Update(0);
      Check((St.Move[5] = 0) and (St.Move[6] = 0) and (St.Move[7] = 0), 'all at 0 at t=0');
      Step.Update(100);
      Check(Abs(St.Move[5] - 0.5) < 1e-9, 'first item half way at t=100');
      Check(St.Move[6] = 0, 'second item only just starting');
      Step.Update(250);
      Check(Abs(St.Move[5] - 1) < 1e-9, 'first item done');
      Check(Abs(St.Move[6] - 0.75) < 1e-9, 'second item 75%');
      Check(Abs(St.Move[7] - 0.25) < 1e-9, 'third item 25%');
      Step.Update(400);
      Check((St.Move[5] = 1) and (St.Move[6] = 1) and (St.Move[7] = 1), 'all at 1 at the end');
      Step.Update(250);                       { going back in time is allowed }
      Check(Abs(St.Move[6] - 0.75) < 1e-9, 'output depends only on T, not on history');
      Check(St.Move[0] = 0, 'slots not listed are untouched');
    finally
      Step.Free;
    end;
    Step := TStaggerStep.Create(St, sfFlip, [3], 0, 100, @EaseInOutQuad);
    try
      Step.Update(50);
      Check(Abs(St.Flip[3] - 0.5) < 1e-9, 'flip field is written too');
      Check(St.Move[3] = 0, 'and the move field is not');
    finally
      Step.Free;
    end;
  finally
    St.Free;
  end;
end;

procedure TestStage;
var
  St: TStage;
begin
  St := TStage.Create;
  try
    St.FinalFaceUp := [3, 28];
    St.Settle;
    Check((St.Move[0] = 1) and (St.Move[28] = 1), 'settle puts everything in place');
    Check((St.Flip[3] = 1) and (St.Flip[28] = 1), 'face-up slots flipped');
    Check((St.Flip[0] = 0) and (St.Flip[27] = 0), 'others stay face down');
    St.Reset;
    Check((St.Move[3] = 0) and (St.Flip[3] = 0), 'reset empties the stage');
  finally
    St.Free;
  end;
end;

procedure TestNewGameSequence;
var
  St: TStage;
  Seq: TAnimSequence;
  C: TCounter;
  I, Total: Integer;
  PrevSum, Sum: Double;
  Ticks: TIntArray;
begin
  St := TStage.Create;
  C := TCounter.Create;
  try
    St.Move[3] := 1;                             { stale values must be cleared }
    Seq := BuildNewGameSequence(St, @C.Bump, 0);
    try
      Check(St.Move[3] = 0, 'building the sequence resets the stage');
      Total := 27 * DealStaggerMs + DealFlightMs
        + 27 * FlipStaggerMs + FlipMs;
      Check(Seq.TotalDuration = Total, 'total duration matches the constants');
      Check((Total > 1000) and (Total < 3000), 'new-game animation is 1-3 s');
      Seq.Advance(0);
      Check(C.N = 1, 'start action called once at the start');
      Check(St.Move[0] = 0, 'nothing has left the stock at t=0');

      PrevSum := 0;
      for I := 1 to Total do
      begin
        Seq.Advance(1);
        Sum := St.Move[0] + St.Move[10] + St.Move[27] + St.Flip[20];
        Check(Sum >= PrevSum - 1e-9, 'progress never goes backwards at ' + IntToStr(I) + ' ms');
        PrevSum := Sum;
        if I = 200 then
          Check((St.Move[0] > 0.5) and (St.Move[27] = 0), 'at 200 ms the top is flying, the last card has not left');
      end;
      Check(not Seq.Running, 'finished after its total duration');
      Check(C.N = 1, 'start action still only once');
      for I := 0 to 27 do
        Check(St.Move[I] = 1, 'card ' + IntToStr(I) + ' arrived');
      for I := 0 to 27 do
        Check(St.Flip[I] = 1, 'card ' + IntToStr(I) + ' is face up (the pyramid is dealt face up)');
    finally
      Seq.Free;
    end;

    { skipping lands in exactly the same final state }
    Seq := BuildNewGameSequence(St, nil, 0);
    try
      Seq.Advance(300);
      Seq.Skip;
      Check(not Seq.Running, 'skip finishes it');
      Check((St.Move[27] = 1) and (St.Flip[19] = 1) and (St.Flip[3] = 1),
        'skip reaches the same final state as playing it out');
    finally
      Seq.Free;
    end;

    Ticks := NewGameTickTimes;
    Check(Length(Ticks) = 56, '56 sound ticks (28 deals + 28 flips)');
    for I := 1 to High(Ticks) do
      Check(Ticks[I] >= Ticks[I - 1], 'tick times are in order');
    Check(Ticks[0] = 0, 'first tick at the start');
    Check(Ticks[High(Ticks)] < Total, 'last tick is before the end');
  finally
    St.Free;
    C.Free;
  end;
end;

procedure TestTicksWav;
var
  W: string;
  DataLen: LongWord;
  N, I, Peak, V: Integer;
  Ticks: TIntArray;

  function Sample(K: Integer): Integer;
  begin
    Result := SmallInt(Word(Ord(W[45 + 2 * K])) or (Word(Ord(W[46 + 2 * K])) shl 8));
  end;

begin
  Ticks := NewGameTickTimes;
  W := MakeTicksWav(Ticks);
  Check(Copy(W, 1, 4) = 'RIFF', 'ticks: RIFF header');
  Check(Copy(W, 37, 4) = 'data', 'ticks: data chunk');
  DataLen := Ord(W[41]) or (Ord(W[42]) shl 8) or (Ord(W[43]) shl 16) or (LongWord(Ord(W[44])) shl 24);
  Check(Length(W) = 44 + Integer(DataLen), 'ticks: length matches header');
  N := Integer(DataLen) div 2;
  Check(N > (Ticks[High(Ticks)] * 22050) div 1000, 'ticks: long enough to hold the last tick');
  Check(N < (Ticks[High(Ticks)] * 22050) div 1000 + 22050, 'ticks: not much longer than needed');
  Peak := 0;
  for I := 0 to N - 1 do
  begin
    V := Abs(Sample(I));
    if V > Peak then Peak := V;
  end;
  Check((Peak > 8000) and (Peak < 25000), 'ticks: audible but gentle (peak ' + IntToStr(Peak) + ')');
  Check(Abs(Sample(0)) < 300, 'ticks: starts without a click');
  Check(Abs(Sample(N - 1)) < 300, 'ticks: ends quietly');
  { silence between ticks: an empty list must still be valid }
  W := MakeTicksWav([]);
  Check(Copy(W, 1, 4) = 'RIFF', 'ticks: empty list still gives a valid file');
end;

function ShakeCurve(T: Double): Double;
begin
  Result := 10 * T;
end;

procedure TestSkipToMark;
var
  Seq: TAnimSequence;
  Log: TStringList;
  A, B, C: TRecStep;
begin
  Log := TStringList.Create;
  Seq := TAnimSequence.Create;
  try
    A := TRecStep.Create('A', 100, Log);
    B := TRecStep.Create('B', 100, Log);
    C := TRecStep.Create('C', 100, Log);
    Seq.Add(TMarkStep.Create);
    Seq.Add(A);
    Seq.Add(TMarkStep.Create);
    Seq.Add(B);
    Seq.Add(TMarkStep.Create);
    Seq.Add(C);
    Check(Seq.TotalDuration = 300, 'marks take no time');
    Seq.Advance(40);                              { part way through A }
    Seq.SkipToMark;
    Check(A.Finishes = 1, 'the current step is finished');
    Check(A.LastT = 100, 'brought to its end');
    Check(B.Starts = 0, 'the next section has not started yet: it starts normally');
    Seq.Advance(30);
    Check(B.Starts = 1, 'it starts on the next advance');
    Check(B.LastT = 30, 'with the new time counted from its start');
    Seq.SkipToMark;
    Check(B.Finishes = 1, 'a second jump finishes B');
    Check(C.Starts = 0, 'and stops before C');
    Seq.SkipToMark;                               { standing in front of a mark }
    Check(C.Finishes = 1, 'jumping while in front of a mark passes it, and C finishes');
    Check(not Seq.Running, 'no marks left: that was the end');
    Seq.SkipToMark;                               { harmless when finished }
    Check(C.Finishes = 1, 'nothing happens twice');
  finally
    Seq.Free;
    Log.Free;
  end;
end;

type
  { a step that waits for a click, like TClickWaitStep but without a stage }
  TGate = class(TAnimStep)
  public
    function Duration: Integer; override;
    function Blocks: Boolean; override;
  end;

function TGate.Duration: Integer;
begin
  Result := 0;
end;

function TGate.Blocks: Boolean;
begin
  Result := True;
end;

procedure TestClickWait;
var
  Seq: TAnimSequence;
  Log: TStringList;
  A, B, C: TRecStep;
begin
  Log := TStringList.Create;
  Seq := TAnimSequence.Create;
  try
    A := TRecStep.Create('A', 100, Log);
    B := TRecStep.Create('B', 100, Log);
    C := TRecStep.Create('C', 100, Log);
    Seq.Add(TMarkStep.Create);
    Seq.Add(A);
    Seq.Add(TGate.Create);
    Seq.Add(B);
    Seq.Add(TMarkStep.Create);
    Seq.Add(C);
    Seq.Advance(150);                            { A is done, then the gate }
    Check(A.Finishes = 1, 'the step before the gate completes');
    Check(Seq.WaitingForClick, 'the sequence waits at the gate');
    Check(B.Starts = 0, 'and the next step has not begun');
    Seq.Advance(1000000);
    Check(Seq.WaitingForClick and (B.Starts = 0), 'no amount of time gets past the gate');
    Check(Seq.Running, 'it is still running');

    Seq.SkipToMark;                              { a click }
    Check(not Seq.WaitingForClick, 'a click lets it go');
    Check(B.Starts = 0, 'but the next step starts only as time passes (so a fade-out can play)');
    Seq.Advance(30);
    Check((B.Starts = 1) and (B.LastT = 30), 'and then it plays on normally');
    Seq.Advance(500);
    Check(B.Finishes = 1, 'B finishes');
    Check(C.Starts = 1, 'and the next section is reached');
  finally
    Seq.Free;
    Log.Free;
  end;

  { clicking before the gate is reached finishes the lead-up but stops in front of the gate }
  Log := TStringList.Create;
  Seq := TAnimSequence.Create;
  try
    A := TRecStep.Create('A', 100, Log);
    B := TRecStep.Create('B', 100, Log);
    Seq.Add(TMarkStep.Create);
    Seq.Add(A);
    Seq.Add(TGate.Create);
    Seq.Add(B);
    Seq.Advance(40);
    Seq.SkipToMark;
    Check(A.Finishes = 1, 'the lead-up is finished');
    Check(B.Starts = 0, 'but the gate was not skipped');
    Seq.Advance(10);
    Check(Seq.WaitingForClick, 'it waits for the next click');
    Seq.SkipToMark;
    Seq.Advance(10);
    Check(B.Starts = 1, 'which moves it on');
  finally
    Seq.Free;
    Log.Free;
  end;

  { Skip (Esc) goes straight through a gate }
  Log := TStringList.Create;
  Seq := TAnimSequence.Create;
  try
    B := TRecStep.Create('B', 100, Log);
    Seq.Add(TGate.Create);
    Seq.Add(B);
    Seq.Advance(10);
    Check(Seq.WaitingForClick, 'waiting');
    Seq.Skip;
    Check(not Seq.Running and (B.Finishes = 1), 'skip does not wait for a click');
    Check(not Seq.WaitingForClick, 'and nothing is left waiting');
  finally
    Seq.Free;
    Log.Free;
  end;

  { an ordinary sequence never waits }
  Seq := TAnimSequence.Create;
  try
    Seq.Add(TWaitStep.Create(50));
    Check(not Seq.WaitingForClick, 'a timed step is not a gate');
    Seq.Advance(100);
    Check(not Seq.Running and not Seq.WaitingForClick, 'and finishes on time');
  finally
    Seq.Free;
  end;
end;

procedure TestSceneSteps;
var
  St: TStage;
  Tw: TTweenStep;
  Cv: TCurveStep;
begin
  St := TStage.Create;
  try
    Check((St.Scalar[ssPortraitSlide] = 1) and (St.Scalar[ssPortraitFade] = 1), 'a fresh stage shows a lit portrait in place');
    Check((St.Scalar[ssDim] = 0) and (St.Scalar[ssTextFade] = 0), 'and no dimming or text');
    Check((St.Backdrop = sbTable) and (St.PortraitId = -1) and (St.Caption = ''), 'on the plain table');

    Tw := TTweenStep.Create(St, ssDim, 0.2, 0.8, 100, @EaseLinear);
    try
      Check(Tw.Duration = 100, 'tween lasts as long as asked');
      Tw.Update(0);
      Check(Abs(St.Scalar[ssDim] - 0.2) < 1e-9, 'tween starts at From');
      Tw.Update(50);
      Check(Abs(St.Scalar[ssDim] - 0.5) < 1e-9, 'half way is half way');
      Tw.Update(100);
      Check(Abs(St.Scalar[ssDim] - 0.8) < 1e-9, 'ends at To');
      Tw.Update(900);
      Check(Abs(St.Scalar[ssDim] - 0.8) < 1e-9, 'and never overshoots');
      Tw.Update(30);
      Check(Abs(St.Scalar[ssDim] - 0.38) < 1e-9, 'it can go back in time (output depends on T only)');
    finally
      Tw.Free;
    end;
    Tw := TTweenStep.Create(St, ssFlashRed, 5, 0.7, 0, @EaseLinear);
    try
      Check(Tw.Duration = 0, 'a zero-length tween is instant');
      Tw.Update(0);
      Check(Abs(St.Scalar[ssFlashRed] - 0.7) < 1e-9, 'and simply sets the value');
    finally
      Tw.Free;
    end;

    Cv := TCurveStep.Create(St, ssPortraitDX, 200, @ShakeCurve);
    try
      Cv.Update(100);
      Check(Abs(St.Scalar[ssPortraitDX] - 5) < 1e-9, 'a curve step writes the curve at the right moment');
      Cv.Update(200);
      Check(Abs(St.Scalar[ssPortraitDX] - 10) < 1e-9, 'and at the end');
    finally
      Cv.Free;
    end;

    with TBackdropStep.Create(St, sbDialogue) do
    try
      Check(Duration = 0, 'a backdrop change is instant');
      Start;
    finally
      Free;
    end;
    Check(St.Backdrop = sbDialogue, 'backdrop changed');
    with TPortraitStep.Create(St, 2) do
    try
      Start;
    finally
      Free;
    end;
    Check(St.PortraitId = 2, 'portrait changed');
    with TTextStep.Create(St, stCaption, 'hello') do
    try
      Start;
    finally
      Free;
    end;
    Check(St.Caption = 'hello', 'caption changed');
    with TTextStep.Create(St, stSpeakerName, 'Vale') do
    try
      Start;
    finally
      Free;
    end;
    Check((St.SpeakerName = 'Vale') and (St.Caption = 'hello'), 'only the chosen text changed');
    St.ResetScene;
    Check((St.Backdrop = sbTable) and (St.PortraitId = -1) and (St.Caption = '') and (St.SpeakerName = ''),
      'ResetScene clears the scene');
    Check((St.Scalar[ssDim] = 0) and (St.Scalar[ssPortraitSlide] = 1), 'and restores the values');
    St.Move[3] := 0.5;
    St.ResetScene;
    Check(St.Move[3] = 0.5, 'but leaves the cards alone');
  finally
    St.Free;
  end;
end;

procedure TestSceneSounds;
var
  W: string;
  DataLen: LongWord;
  N, I, Peak, V, Which: Integer;

  function Sample(K: Integer): Integer;
  begin
    Result := SmallInt(Word(Ord(W[45 + 2 * K])) or (Word(Ord(W[46 + 2 * K])) shl 8));
  end;

begin
  for Which := 0 to 2 do
  begin
    case Which of
      0: W := MakeTollWav;
      1: W := MakeBlowWav;
    else
      W := MakeStingWav;
    end;
    Check(Copy(W, 1, 4) = 'RIFF', 'sound ' + IntToStr(Which) + ': RIFF header');
    Check(Copy(W, 37, 4) = 'data', 'sound ' + IntToStr(Which) + ': data chunk');
    DataLen := Ord(W[41]) or (Ord(W[42]) shl 8) or (Ord(W[43]) shl 16) or (LongWord(Ord(W[44])) shl 24);
    Check(Length(W) = 44 + Integer(DataLen), 'sound ' + IntToStr(Which) + ': length matches header');
    N := Integer(DataLen) div 2;
    Check((N > 22050 div 4) and (N < 22050 * 4), 'sound ' + IntToStr(Which) + ': a sensible length');
    Peak := 0;
    for I := 0 to N - 1 do
    begin
      V := Abs(Sample(I));
      if V > Peak then Peak := V;
    end;
    Check((Peak > 12000) and (Peak < 30000), 'sound ' + IntToStr(Which) + ': audible, not clipping (peak ' + IntToStr(Peak) + ')');
    Check(Abs(Sample(0)) < 600, 'sound ' + IntToStr(Which) + ': starts without a click');
    Check(Abs(Sample(N - 1)) < 600, 'sound ' + IntToStr(Which) + ': ends quietly');
  end;
end;

begin
  TestEasing;
  TestSequenceOrder;
  TestChunksEqualJump;
  TestSkip;
  TestCallAndWait;
  TestGroup;
  TestStagger;
  TestStage;
  TestNewGameSequence;
  TestTicksWav;
  TestSkipToMark;
  TestClickWait;
  TestSceneSteps;
  TestSceneSounds;
  if Failures = 0 then WriteLn('ALL ANIMATION TESTS PASSED') else
  begin
    WriteLn(Failures, ' FAILURES');
    Halt(1);
  end;
end.
