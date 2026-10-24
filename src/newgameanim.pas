unit NewGameAnim;

{ The "new game" animation: the 28 pyramid cards fly out of the stock into their
  places (top row first), then flip face-up (bottom row first).

  Pure data and timing; the window draws the Stage. To make a different
  animation (a longer one, a story intro, a duel opening) build another
  TAnimSequence the same way: compose steps, and return it. }

{$mode objfpc}{$H+}

interface

uses
  Anim, Stage;

const
  DealStaggerMs = 30;      { gap between cards leaving the stock }
  DealFlightMs = 240;      { time a card spends flying }
  FlipStaggerMs = 35;
  FlipMs = 220;

type
  TIntArray = array of Integer;

{ Resets the cards on AStage and returns the sequence that animates them.
  AOnStart (may be nil) is called the moment the sequence starts, e.g. to begin
  a sound. If AFadeInMs > 0 and the picture is currently dimmed (a scene just
  ended), the dim fades away over that time while the cards start to deal. }
function BuildNewGameSequence(AStage: TStage; AOnStart: TAnimAction;
  AFadeInMs: Integer): TAnimSequence;

{ Times (ms from the start) of the card "flicks" the sound should match. }
function NewGameTickTimes: TIntArray;

implementation

function BuildNewGameSequence(AStage: TStage; AOnStart: TAnimAction;
  AFadeInMs: Integer): TAnimSequence;
var
  Deal: array[0..27] of Integer;
  Flips: array[0..27] of Integer;
  I: Integer;
  G: TAnimGroup;
begin
  for I := 0 to 27 do Deal[I] := I;              { top row first }
  for I := 0 to 27 do Flips[I] := 27 - I;        { the bottom row first }

  AStage.FinalFaceUp := [];
  for I := 0 to 27 do Include(AStage.FinalFaceUp, I);
  AStage.Reset;

  Result := TAnimSequence.Create;
  Result.Add(TCallStep.Create(AOnStart));
  if (AFadeInMs > 0) and (AStage.Scalar[ssDim] > 0) then
  begin
    G := TAnimGroup.Create;                      { fade in while the deal begins }
    G.Add(TTweenStep.Create(AStage, ssDim, AStage.Scalar[ssDim], 0, AFadeInMs,
      @EaseLinear));
    G.Add(TStaggerStep.Create(AStage, sfMove, Deal, DealStaggerMs,
      DealFlightMs, @EaseOutCubic));
    Result.Add(G);
  end
  else
    Result.Add(TStaggerStep.Create(AStage, sfMove, Deal, DealStaggerMs,
      DealFlightMs, @EaseOutCubic));
  Result.Add(TStaggerStep.Create(AStage, sfFlip, Flips, FlipStaggerMs,
    FlipMs, @EaseInOutQuad));
end;

function NewGameTickTimes: TIntArray;
var
  I, N, T: Integer;
begin
  Result := nil;
  SetLength(Result, 28 + 28);
  N := 0;
  for I := 0 to 27 do                            { each card leaving the stock }
  begin
    Result[N] := I * DealStaggerMs;
    Inc(N);
  end;
  T := 27 * DealStaggerMs + DealFlightMs;        { then the flips }
  for I := 0 to 27 do
  begin
    Result[N] := T + I * FlipStaggerMs;
    Inc(N);
  end;
end;

end.
