unit Stage;

{ What an animation is "showing" right now. No drawing, no window.

  Steps (see Anim) write these values; the window reads them and draws. Keeping
  the numbers separate from the drawing is what makes animations testable and
  lets new ones (a duel intro, a story scene) be built from the same parts.

  Two kinds of thing live here:
    * Card slots (0..27 tableau, 28 waste): where each card is and how far it
      has flipped. Used by the deal.
    * A scene: a backdrop, a vampire portrait, a name plate, a line of text,
      and a few overlay values (fade to black, flashes, shake). Used by the
      duel scenes (see Scenes).

  To show something new, add a field here, a step that animates it, and a bit
  of drawing for it in the window. }

{$mode objfpc}{$H+}

interface

uses
  Anim;

const
  StageSlots = 29;
  WasteSlot = 28;

type
  TStageField = (
    sfMove,      { 0 = still in the stock, 1 = in its place; in between = flying }
    sfFlip);     { 0 = back showing, 1 = face showing; the middle is edge-on }

  TSlotSet = set of 0..StageSlots - 1;

  { Single numbers, all 0..1 unless noted. }
  TStageScalar = (
    ssPortraitSlide,   { 0 = off to the left, 1 = in place }
    ssPortraitFade,    { 0 = lost in the dark, 1 = fully lit }
    ssPortraitDX,      { sideways shake, in portrait widths (can be negative) }
    ssTextFade,        { the line of text: 0 = invisible, 1 = fully shown }
    ssDim,             { black over the whole picture: 1 = completely black }
    ssFlashWhite,      { a white flash over the picture }
    ssFlashRed);       { a red flash over the picture }

  { What fills the window. }
  TBackdrop = (
    sbTable,           { the table and cards (the normal game) }
    sbDialogue,        { a dark room: portrait, name plate, text }
    sbHouse,           { the house on the hill, with a box of text (the story's opening) }
    sbWinPicture);     { the three vampires and the victory caption }

  TStageText = (stSpeakerName, stSpeakerTitle, stCaption);

  TCurve = function(T: Double): Double;      { T = 0..1 through a step }

  TStage = class
  public
    { cards }
    Move: array[0..StageSlots - 1] of Double;
    Flip: array[0..StageSlots - 1] of Double;
    FinalFaceUp: TSlotSet;        { slots that end face-up once everything settles }
    { scene }
    Scalar: array[TStageScalar] of Double;
    Backdrop: TBackdrop;
    PortraitId: Integer;          { the picture shown (see PortraitCount in Vampires), -1 = none }
    SpeakerName, SpeakerTitle, Caption: string;
    WaitingForClick: Boolean;     { the scene is waiting for the player: show a cue }
    constructor Create;
    procedure Reset;              { cards: everything in the stock, face down }
    procedure Settle;             { cards: everything where it ends up }
    procedure ResetScene;         { scene: back to the plain table, nothing showing }
    procedure SetField(Field: TStageField; Slot: Integer; Value: Double);
    procedure SetText(Which: TStageText; const Value: string);
  end;

  { Animates one field of several slots, each starting a little after the
    previous one (a "wave"). One step covers dealing, flipping, or any other
    per-card effect: choose the field, the slots, the stagger and the easing. }
  TStaggerStep = class(TAnimStep)
  private
    FStage: TStage;
    FField: TStageField;
    FItems: array of Integer;
    FStagger, FDur: Integer;
    FEase: TEasing;
  public
    constructor Create(AStage: TStage; AField: TStageField;
      const AItems: array of Integer; AStaggerMs, ADurationMs: Integer;
      AEase: TEasing);
    function Duration: Integer; override;
    procedure Update(T: Integer); override;
  end;

  { Moves a scene value smoothly from one number to another. With a duration of
    0 it simply sets the value. }
  TTweenStep = class(TAnimStep)
  private
    FStage: TStage;
    FWhich: TStageScalar;
    FFrom, FTo: Double;
    FDur: Integer;
    FEase: TEasing;
  public
    constructor Create(AStage: TStage; AWhich: TStageScalar; AFrom, ATo: Double;
      ADurationMs: Integer; AEase: TEasing);
    function Duration: Integer; override;
    procedure Update(T: Integer); override;
  end;

  { Drives a scene value along any curve (a shake that dies away, say). }
  TCurveStep = class(TAnimStep)
  private
    FStage: TStage;
    FWhich: TStageScalar;
    FDur: Integer;
    FCurve: TCurve;
  public
    constructor Create(AStage: TStage; AWhich: TStageScalar; ADurationMs: Integer;
      ACurve: TCurve);
    function Duration: Integer; override;
    procedure Update(T: Integer); override;
  end;

  { Instant changes to what is on the stage. }
  TBackdropStep = class(TAnimStep)
  private
    FStage: TStage;
    FBackdrop: TBackdrop;
  public
    constructor Create(AStage: TStage; ABackdrop: TBackdrop);
    function Duration: Integer; override;
    procedure Start; override;
  end;

  TPortraitStep = class(TAnimStep)
  private
    FStage: TStage;
    FId: Integer;
  public
    constructor Create(AStage: TStage; AId: Integer);
    function Duration: Integer; override;
    procedure Start; override;
  end;

  { Holds the scene until the player clicks (or presses a key). Takes no time of
    its own; the sequence stops here and the stage shows a "click" cue. }
  TClickWaitStep = class(TAnimStep)
  private
    FStage: TStage;
  public
    constructor Create(AStage: TStage);
    function Duration: Integer; override;
    function Blocks: Boolean; override;
    procedure Start; override;
    procedure Finish; override;
  end;

  TTextStep = class(TAnimStep)
  private
    FStage: TStage;
    FWhich: TStageText;
    FText: string;
  public
    constructor Create(AStage: TStage; AWhich: TStageText; const AText: string);
    function Duration: Integer; override;
    procedure Start; override;
  end;

implementation

constructor TStage.Create;
begin
  inherited Create;
  FinalFaceUp := [];
  Reset;
  ResetScene;
end;

procedure TStage.Reset;
var
  I: Integer;
begin
  for I := 0 to StageSlots - 1 do
  begin
    Move[I] := 0;
    Flip[I] := 0;
  end;
end;

procedure TStage.Settle;
var
  I: Integer;
begin
  for I := 0 to StageSlots - 1 do
  begin
    Move[I] := 1;
    if I in FinalFaceUp then Flip[I] := 1 else Flip[I] := 0;
  end;
end;

procedure TStage.ResetScene;
var
  S: TStageScalar;
begin
  for S := Low(TStageScalar) to High(TStageScalar) do Scalar[S] := 0;
  Scalar[ssPortraitSlide] := 1;
  Scalar[ssPortraitFade] := 1;
  Backdrop := sbTable;
  PortraitId := -1;
  SpeakerName := '';
  SpeakerTitle := '';
  Caption := '';
  WaitingForClick := False;
end;

procedure TStage.SetField(Field: TStageField; Slot: Integer; Value: Double);
begin
  case Field of
    sfMove: Move[Slot] := Value;
    sfFlip: Flip[Slot] := Value;
  end;
end;

procedure TStage.SetText(Which: TStageText; const Value: string);
begin
  case Which of
    stSpeakerName: SpeakerName := Value;
    stSpeakerTitle: SpeakerTitle := Value;
    stCaption: Caption := Value;
  end;
end;

{ TStaggerStep }

constructor TStaggerStep.Create(AStage: TStage; AField: TStageField;
  const AItems: array of Integer; AStaggerMs, ADurationMs: Integer;
  AEase: TEasing);
var
  I: Integer;
begin
  inherited Create;
  FStage := AStage;
  FField := AField;
  SetLength(FItems, Length(AItems));
  for I := 0 to High(AItems) do FItems[I] := AItems[I];
  FStagger := AStaggerMs;
  FDur := ADurationMs;
  FEase := AEase;
end;

function TStaggerStep.Duration: Integer;
begin
  if Length(FItems) = 0 then Result := 0
  else Result := (Length(FItems) - 1) * FStagger + FDur;
end;

procedure TStaggerStep.Update(T: Integer);
var
  K: Integer;
  Raw: Double;
begin
  for K := 0 to High(FItems) do
  begin
    if FDur <= 0 then Raw := 1
    else Raw := (T - K * FStagger) / FDur;
    if Raw < 0 then Raw := 0;
    if Raw > 1 then Raw := 1;
    FStage.SetField(FField, FItems[K], FEase(Raw));
  end;
end;

{ TTweenStep }

constructor TTweenStep.Create(AStage: TStage; AWhich: TStageScalar;
  AFrom, ATo: Double; ADurationMs: Integer; AEase: TEasing);
begin
  inherited Create;
  FStage := AStage;
  FWhich := AWhich;
  FFrom := AFrom;
  FTo := ATo;
  FDur := ADurationMs;
  FEase := AEase;
end;

function TTweenStep.Duration: Integer;
begin
  if FDur < 0 then Result := 0 else Result := FDur;
end;

procedure TTweenStep.Update(T: Integer);
var
  Raw: Double;
begin
  if FDur <= 0 then
    FStage.Scalar[FWhich] := FTo
  else
  begin
    Raw := T / FDur;
    if Raw < 0 then Raw := 0;
    if Raw > 1 then Raw := 1;
    FStage.Scalar[FWhich] := FFrom + (FTo - FFrom) * FEase(Raw);
  end;
end;

{ TCurveStep }

constructor TCurveStep.Create(AStage: TStage; AWhich: TStageScalar;
  ADurationMs: Integer; ACurve: TCurve);
begin
  inherited Create;
  FStage := AStage;
  FWhich := AWhich;
  FDur := ADurationMs;
  FCurve := ACurve;
end;

function TCurveStep.Duration: Integer;
begin
  Result := FDur;
end;

procedure TCurveStep.Update(T: Integer);
var
  Raw: Double;
begin
  if FDur <= 0 then Raw := 1 else Raw := T / FDur;
  if Raw < 0 then Raw := 0;
  if Raw > 1 then Raw := 1;
  FStage.Scalar[FWhich] := FCurve(Raw);
end;

{ instant steps }

constructor TBackdropStep.Create(AStage: TStage; ABackdrop: TBackdrop);
begin
  inherited Create;
  FStage := AStage;
  FBackdrop := ABackdrop;
end;

function TBackdropStep.Duration: Integer;
begin
  Result := 0;
end;

procedure TBackdropStep.Start;
begin
  FStage.Backdrop := FBackdrop;
end;

constructor TPortraitStep.Create(AStage: TStage; AId: Integer);
begin
  inherited Create;
  FStage := AStage;
  FId := AId;
end;

function TPortraitStep.Duration: Integer;
begin
  Result := 0;
end;

procedure TPortraitStep.Start;
begin
  FStage.PortraitId := FId;
end;

constructor TClickWaitStep.Create(AStage: TStage);
begin
  inherited Create;
  FStage := AStage;
end;

function TClickWaitStep.Duration: Integer;
begin
  Result := 0;
end;

function TClickWaitStep.Blocks: Boolean;
begin
  Result := True;
end;

procedure TClickWaitStep.Start;
begin
  FStage.WaitingForClick := True;
end;

procedure TClickWaitStep.Finish;
begin
  FStage.WaitingForClick := False;
end;

constructor TTextStep.Create(AStage: TStage; AWhich: TStageText; const AText: string);
begin
  inherited Create;
  FStage := AStage;
  FWhich := AWhich;
  FText := AText;
end;

function TTextStep.Duration: Integer;
begin
  Result := 0;
end;

procedure TTextStep.Start;
begin
  FStage.SetText(FWhich, FText);
end;

end.
