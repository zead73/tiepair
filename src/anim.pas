unit Anim;

{ A tiny cutscene sequencer. No drawing, no game rules, no window: just time.

  A TAnimSequence runs TAnimSteps one after another. A TAnimGroup is a step
  that runs several steps at the same time. Steps do not draw anything: they
  write values somewhere (see Stage) and the window draws those values, so the
  whole thing can be tested without a screen.

  To add a new kind of animation, derive from TAnimStep and override:
    Duration - length in milliseconds (0 = instant, like a one-shot action)
    Start    - called once, just before the first Update
    Update(T) - T is the time into the step, 0..Duration. It must set its
               output purely from T (not from the previous call), so a step can
               be jumped to its end by Skip.
    Finish   - called once when the step has completed (or was skipped)
    Blocks   - True for a step that waits for the player (a click) instead of
               for time. The sequence stops there, no matter how much time
               passes, until it is released (see TAnimSequence.SkipToMark). }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Contnrs, Math;

type
  TEasing = function(T: Double): Double;      { maps 0..1 to 0..1 }
  TAnimAction = procedure of object;

function EaseLinear(T: Double): Double;
function EaseOutCubic(T: Double): Double;      { fast start, gentle landing }
function EaseInOutQuad(T: Double): Double;

type
  TAnimStep = class
  public
    function Duration: Integer; virtual; abstract;
    function Blocks: Boolean; virtual;
    procedure Start; virtual;
    procedure Update(T: Integer); virtual;
    procedure Finish; virtual;
  end;

  { Does nothing for a while. }
  TWaitStep = class(TAnimStep)
  private
    FMs: Integer;
  public
    constructor Create(AMs: Integer);
    function Duration: Integer; override;
  end;

  { Runs an action once, instantly (start a sound, switch a flag, ...). }
  TCallStep = class(TAnimStep)
  private
    FAction: TAnimAction;
  public
    constructor Create(AAction: TAnimAction);
    function Duration: Integer; override;
    procedure Start; override;
  end;

  { Marks a point the sequence can jump to (the start of a line of dialogue,
    say). Takes no time and does nothing by itself; see SkipToMark. }
  TMarkStep = class(TAnimStep)
  public
    function Duration: Integer; override;
  end;

  { Runs its children at the same time; lasts as long as the longest. }
  TAnimGroup = class(TAnimStep)
  private
    FChildren: TObjectList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(Step: TAnimStep);            { takes ownership }
    function Duration: Integer; override;
    procedure Start; override;
    procedure Update(T: Integer); override;
    procedure Finish; override;
  end;

  TAnimSequence = class
  private
    FSteps: TObjectList;
    FIndex: Integer;
    FStepTime: Integer;
    FStarted: Boolean;
    FReleased: Boolean;          { the waiting (blocking) step has been let go }
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(Step: TAnimStep);            { takes ownership }
    function Running: Boolean;                 { steps remain }
    function TotalDuration: Integer;
    { Moves time forward; steps are started, updated and finished as needed. }
    procedure Advance(DeltaMs: Integer);
    { Jumps to the end: every remaining step is started (if needed), brought to
      its final state and finished, in order. }
    procedure Skip;
    { A click on a scene. If the sequence is waiting for a click, it is let go
      (and carries on normally, so a fade-out still plays). Otherwise the
      current step is finished and everything after it up to the next mark
      or the next waiting step, which is left to start normally (so the next
      line of dialogue begins fresh). With nothing of the kind ahead, this is
      the same as Skip. }
    procedure SkipToMark;
    { True while the sequence is stopped at a step that waits for a click. }
    function WaitingForClick: Boolean;
  end;

implementation

function EaseLinear(T: Double): Double;
begin
  Result := T;
end;

function EaseOutCubic(T: Double): Double;
begin
  Result := 1 - Power(1 - T, 3);
end;

function EaseInOutQuad(T: Double): Double;
begin
  if T < 0.5 then Result := 2 * T * T
  else Result := 1 - Power(-2 * T + 2, 2) / 2;
end;

{ TAnimStep }

function TAnimStep.Blocks: Boolean;
begin
  Result := False;
end;

procedure TAnimStep.Start;
begin
end;

procedure TAnimStep.Update(T: Integer);
begin
end;

procedure TAnimStep.Finish;
begin
end;

{ TWaitStep }

constructor TWaitStep.Create(AMs: Integer);
begin
  inherited Create;
  FMs := AMs;
end;

function TWaitStep.Duration: Integer;
begin
  Result := FMs;
end;

{ TCallStep }

constructor TCallStep.Create(AAction: TAnimAction);
begin
  inherited Create;
  FAction := AAction;
end;

function TCallStep.Duration: Integer;
begin
  Result := 0;
end;

procedure TCallStep.Start;
begin
  if Assigned(FAction) then FAction();
end;

{ TMarkStep }

function TMarkStep.Duration: Integer;
begin
  Result := 0;
end;

{ TAnimGroup }

constructor TAnimGroup.Create;
begin
  inherited Create;
  FChildren := TObjectList.Create(True);
end;

destructor TAnimGroup.Destroy;
begin
  FChildren.Free;
  inherited Destroy;
end;

procedure TAnimGroup.Add(Step: TAnimStep);
begin
  FChildren.Add(Step);
end;

function TAnimGroup.Duration: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FChildren.Count - 1 do
    Result := Max(Result, TAnimStep(FChildren[I]).Duration);
end;

procedure TAnimGroup.Start;
var
  I: Integer;
begin
  for I := 0 to FChildren.Count - 1 do TAnimStep(FChildren[I]).Start;
end;

procedure TAnimGroup.Update(T: Integer);
var
  I: Integer;
  C: TAnimStep;
begin
  for I := 0 to FChildren.Count - 1 do
  begin
    C := TAnimStep(FChildren[I]);
    C.Update(Min(T, C.Duration));
  end;
end;

procedure TAnimGroup.Finish;
var
  I: Integer;
begin
  for I := 0 to FChildren.Count - 1 do TAnimStep(FChildren[I]).Finish;
end;

{ TAnimSequence }

constructor TAnimSequence.Create;
begin
  inherited Create;
  FSteps := TObjectList.Create(True);
end;

destructor TAnimSequence.Destroy;
begin
  FSteps.Free;
  inherited Destroy;
end;

procedure TAnimSequence.Add(Step: TAnimStep);
begin
  FSteps.Add(Step);
end;

function TAnimSequence.Running: Boolean;
begin
  Result := FIndex < FSteps.Count;
end;

function TAnimSequence.TotalDuration: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FSteps.Count - 1 do
    Inc(Result, TAnimStep(FSteps[I]).Duration);
end;

procedure TAnimSequence.Advance(DeltaMs: Integer);
var
  Left, Dur: Integer;
  Step: TAnimStep;
begin
  Left := DeltaMs;
  while FIndex < FSteps.Count do
  begin
    Step := TAnimStep(FSteps[FIndex]);
    if not FStarted then
    begin
      Step.Start;
      FStarted := True;
    end;
    if Step.Blocks and not FReleased then Break;   { waiting for a click: time does not pass }
    Dur := Step.Duration;
    if FStepTime + Left >= Dur then
    begin
      Left := Left - (Dur - FStepTime);       { time left over for the next step }
      Step.Update(Dur);
      Step.Finish;
      Inc(FIndex);
      FStepTime := 0;
      FStarted := False;
      FReleased := False;
    end
    else
    begin
      Inc(FStepTime, Left);
      Step.Update(FStepTime);
      Break;
    end;
  end;
end;

procedure TAnimSequence.Skip;
var
  Step: TAnimStep;
begin
  while FIndex < FSteps.Count do
  begin
    Step := TAnimStep(FSteps[FIndex]);
    if not FStarted then Step.Start;
    Step.Update(Step.Duration);
    Step.Finish;
    Inc(FIndex);
    FStepTime := 0;
    FStarted := False;
    FReleased := False;
  end;
end;

procedure TAnimSequence.SkipToMark;
var
  Step: TAnimStep;
  First: Boolean;
begin
  { waiting for a click: let it go, and play on normally from there }
  if (FIndex < FSteps.Count) and TAnimStep(FSteps[FIndex]).Blocks then
  begin
    FReleased := True;
    Exit;
  end;
  First := True;
  while FIndex < FSteps.Count do
  begin
    Step := TAnimStep(FSteps[FIndex]);
    { stop in front of the next mark or waiting step (but never on the step we
      are leaving) }
    if (not First) and not FStarted and ((Step is TMarkStep) or Step.Blocks) then Break;
    First := False;
    if not FStarted then Step.Start;
    Step.Update(Step.Duration);
    Step.Finish;
    Inc(FIndex);
    FStepTime := 0;
    FStarted := False;
    FReleased := False;
  end;
end;

function TAnimSequence.WaitingForClick: Boolean;
begin
  Result := (FIndex < FSteps.Count) and TAnimStep(FSteps[FIndex]).Blocks
    and not FReleased;
end;

end.
