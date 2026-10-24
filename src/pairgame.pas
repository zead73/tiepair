unit PairGame;

{ The flow of Perfect Pair that does not depend on a window: where everything is drawn,
  what a tap does, the one-line messages, the saved hand. The desktop program and the
  web page both draw what this says and pass taps back to it, so the two cannot
  disagree about the game. No window code. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Types, Math, Cards, Pyramid, PairHand, Storage;

type
  TChangeEvent = procedure of object;
  { Tests give their own deals; nil means a shuffled deck. }
  TDeckEvent = function: TDeck of object;

  TPairUi = record
    UndoEnabled: Boolean;
    HintEnabled: Boolean;
    Status: string;                 { one line for the status bar }
    CardsLeft: Integer;
    StockCount: Integer;
    WasteCount: Integer;
    RecyclesLeft: Integer;
    Won: Boolean;
    Stuck: Boolean;
    Easy: Boolean;                  { Easy mode: a card may go with the one covering it }
    ModeCaption: string;            { 'Mode: Normal' or 'Mode: Easy' }
  end;

  TPairController = class
  private
    FGame: TPyramidGame;
    FOnChange: TChangeEvent;
    FDeckProvider: TDeckEvent;
    FVW, FVH: Integer;
    FPanel, FTable: TRect;
    FCW, FCH, FGap, FStep, FOrgX, FOrgY: Integer;
    FStockR, FWasteR: TRect;
    FSel: Integer;                  { the selected card: a pyramid position, PosWaste, or PosNone }
    FHintA, FHintB: Integer;
    FHintStock: Boolean;
    FToast: string;
    FSaving: Boolean;
    FEasy: Boolean;
    procedure LoadSettings;
    procedure SaveSettings;
    procedure Recompute;
    procedure Changed;
    procedure AfterMove;
    procedure ClearHints;
    procedure SaveHand;
    procedure Pick(APos: Integer);
    function StatusLine: string;
  public
    constructor Create;
    destructor Destroy; override;
    { Open the program: pick up the saved hand if there is a believable one, else deal. }
    procedure Start;
    procedure SetViewport(W, H: Integer);
    procedure SetViewportQuiet(W, H: Integer);     { the same, without telling anyone (used while painting) }

    procedure ActionNew;
    { Easy or Normal: a different mode deals a new hand, since the rules of a hand do not change half way. }
    procedure SetEasy(AValue: Boolean);
    procedure ActionToggleEasy;
    procedure ActionUndo;
    procedure ActionHint;
    procedure Tap(X, Y: Integer);

    { Where things are (all in the same pixels as the viewport). }
    function PanelRect: TRect;                 { empty when the window is too narrow for a side panel }
    function TableRect: TRect;
    function CardRect(I: Integer): TRect;
    function StockRect: TRect;
    function WasteRect: TRect;
    property CardW: Integer read FCW;
    property CardH: Integer read FCH;
    function Scaled(N: Integer): Integer;      { a size that grows with the cards }

    function GetUi: TPairUi;
    property Game: TPyramidGame read FGame;
    property Easy: Boolean read FEasy;
    property Selected: Integer read FSel;
    property HintA: Integer read FHintA;
    property HintB: Integer read FHintB;
    property HintStock: Boolean read FHintStock;
    property DeckProvider: TDeckEvent read FDeckProvider write FDeckProvider;
    property OnChange: TChangeEvent read FOnChange write FOnChange;
  end;

implementation

const
  CardAspectW = 328;               { the card pictures are 328 x 465 }
  CardAspectH = 465;

function SettingsFile: string;
begin
  Result := StoreName('settings.ini');
end;

procedure TPairController.LoadSettings;
var
  Text: string;
begin
  FEasy := False;
  if StoreRead(SettingsFile, Text) then FEasy := Pos('easy=1', Text) > 0;
end;

procedure TPairController.SaveSettings;
begin
  if FEasy then StoreWrite(SettingsFile, 'easy=1' + #10)
  else StoreWrite(SettingsFile, 'easy=0' + #10);
end;

constructor TPairController.Create;
begin
  inherited Create;
  FGame := TPyramidGame.Create;
  FSel := PosNone;
  FHintA := PosNone;
  FHintB := PosNone;
  FVW := 1000;
  FVH := 600;
  Recompute;
end;

destructor TPairController.Destroy;
begin
  FGame.Free;
  inherited Destroy;
end;

procedure TPairController.Changed;
begin
  if Assigned(FOnChange) then FOnChange();
end;

{ ---- where things are ---- }

procedure TPairController.SetViewport(W, H: Integer);
begin
  if W < 100 then W := 100;
  if H < 100 then H := 100;
  FVW := W;
  FVH := H;
  Recompute;
  Changed;
end;

procedure TPairController.SetViewportQuiet(W, H: Integer);
begin
  if W < 100 then W := 100;
  if H < 100 then H := 100;
  if (W = FVW) and (H = FVH) then Exit;
  FVW := W;
  FVH := H;
  Recompute;
end;

procedure TPairController.Recompute;
var
  PanelW, M, TW, TH, CWw, CHh, Total, Lower, PyW, PyH: Integer;
begin
  { a side panel when the window is wide, none on a phone held upright }
  if FVW >= FVH * 115 div 100 then PanelW := Max(150, Min(260, FVW * 22 div 100))
  else PanelW := 0;
  FPanel := Rect(0, 0, PanelW, FVH);
  FTable := Rect(PanelW, 0, FVW, FVH);
  M := Max(8, Min(FVW, FVH) div 40);
  TW := FTable.Right - FTable.Left - 2 * M;
  TH := FVH - 2 * M;
  { seven cards across with a small gap; and 6 half-steps + 2 card heights + a gap down }
  CWw := TW * 100 div 752;
  CHh := TH * 100 div 530;
  FCW := Min(CWw, CHh * CardAspectW div CardAspectH);
  if FCW < 12 then FCW := 12;
  FCH := FCW * CardAspectH div CardAspectW;
  FGap := Max(2, FCW * 8 div 100);
  FStep := FCH div 2;
  Lower := FCH * 20 div 100;
  PyW := 7 * FCW + 6 * FGap;
  PyH := 6 * FStep + FCH + Lower + FCH;
  FOrgX := (FTable.Left + FTable.Right) div 2;
  Total := PyH;
  FOrgY := FTable.Top + M + Max(0, (TH - Total) div 2);
  FStockR := Rect(FOrgX - PyW div 2, FOrgY + 6 * FStep + FCH + Lower,
    FOrgX - PyW div 2 + FCW, FOrgY + 6 * FStep + FCH + Lower + FCH);
  FWasteR := Rect(FStockR.Right + FGap * 2, FStockR.Top, FStockR.Right + FGap * 2 + FCW, FStockR.Bottom);
end;

function TPairController.Scaled(N: Integer): Integer;
begin
  Result := Max(1, N * FCW div 100);
end;

function TPairController.PanelRect: TRect;
begin
  Result := FPanel;
end;

function TPairController.TableRect: TRect;
begin
  Result := FTable;
end;

function TPairController.CardRect(I: Integer): TRect;
var
  R, C, Left: Integer;
begin
  R := RowOf(I);
  C := ColOf(I);
  Left := FOrgX + (2 * C - R) * (FCW + FGap) div 2 - FCW div 2;
  Result := Rect(Left, FOrgY + R * FStep, Left + FCW, FOrgY + R * FStep + FCH);
end;

function TPairController.StockRect: TRect;
begin
  Result := FStockR;
end;

function TPairController.WasteRect: TRect;
begin
  Result := FWasteR;
end;

{ ---- the hand ---- }

procedure TPairController.ClearHints;
begin
  FHintA := PosNone;
  FHintB := PosNone;
  FHintStock := False;
end;

procedure TPairController.SaveHand;
var
  H: TPairHand;
begin
  if FSaving then Exit;
  if FGame.IsWon then
  begin
    DeleteHandFile(AutoSaveFile);            { a won hand is not kept: the next start deals a new one }
    Exit;
  end;
  FGame.GetState(H);
  WriteHandFile(AutoSaveFile, H);
end;

procedure TPairController.Start;
var
  H: TPairHand;
begin
  LoadSettings;
  if ReadHandFile(AutoSaveFile, H) and FGame.SetState(H) and not FGame.IsWon and not FGame.IsStuck then
  begin
    if FEasy <> FGame.UnderPairs then       { the hand in front of you decides the mode }
    begin
      FEasy := FGame.UnderPairs;
      SaveSettings;
    end;
    FSel := PosNone;
    ClearHints;
    FToast := 'Welcome back: your hand is as you left it.';
    Changed;
  end
  else
    ActionNew;
end;

procedure TPairController.ActionNew;
var
  D: TDeck;
begin
  FGame.UnderPairs := FEasy;
  if Assigned(FDeckProvider) then
  begin
    D := FDeckProvider();
    FGame.Deal(D);
    D.Free;
  end
  else
    FGame.NewShuffled;
  FSel := PosNone;
  ClearHints;
  FToast := '';
  SaveHand;
  Changed;
end;

procedure TPairController.SetEasy(AValue: Boolean);
begin
  if AValue = FEasy then Exit;
  FEasy := AValue;
  SaveSettings;
  ActionNew;
  if FEasy then
    FToast := 'Easy mode: a card can go with the one sitting on top of it. A new hand is dealt.'
  else
    FToast := 'Normal mode: cards must be uncovered first. A new hand is dealt.';
  Changed;
end;

procedure TPairController.ActionToggleEasy;
begin
  SetEasy(not FEasy);
end;

function TPairController.StatusLine: string;
begin
  if FToast <> '' then Exit(FToast);
  if FGame.IsWon then Exit('You cleared the pyramid! Tap anywhere for a new hand.');
  if FGame.IsStuck then Exit('No moves left. Undo, or start a new hand.');
  if FSel <> PosNone then Exit('Now tap a card that makes 13 with it. A King needs no partner.');
  if FEasy then Result := 'Take away Kings, and pairs that add up to 13. A card can go with the one on top of it.'
  else Result := 'Take away Kings, and pairs that add up to 13.';
end;

function TPairController.GetUi: TPairUi;
begin
  Result.Won := FGame.IsWon;
  Result.Stuck := FGame.IsStuck;
  Result.UndoEnabled := FGame.CanUndo and not FGame.IsWon;
  Result.HintEnabled := not FGame.IsWon and not FGame.IsStuck;
  Result.CardsLeft := FGame.CardsLeft;
  Result.StockCount := FGame.StockCount;
  Result.WasteCount := FGame.WasteCount;
  Result.RecyclesLeft := FGame.RecyclesLeft;
  Result.Easy := FEasy;
  if FEasy then Result.ModeCaption := 'Mode: Easy' else Result.ModeCaption := 'Mode: Normal';
  Result.Status := StatusLine;
end;

procedure TPairController.AfterMove;
begin
  FSel := PosNone;
  ClearHints;
  SaveHand;
  Changed;
end;

procedure TPairController.ActionUndo;
begin
  if FGame.IsWon then Exit;
  FToast := '';
  if FGame.Undo then AfterMove else Changed;
end;

procedure TPairController.ActionHint;
var
  A, B: Integer;
begin
  if FGame.IsWon or FGame.IsStuck then Exit;
  FToast := '';
  ClearHints;
  FSel := PosNone;
  if FGame.FindRemoval(0, A, B) then
  begin
    FHintA := A;
    FHintB := B;
    FToast := 'There is a move: look for the glowing cards.';
  end
  else if FGame.CanDraw then
  begin
    FHintStock := True;
    FToast := 'Nothing to take away: draw from the stock.';
  end
  else if FGame.CanRecycle then
  begin
    FHintStock := True;
    FToast := 'Turn the waste over to make a new stock.';
  end;
  Changed;
end;

{ A free pyramid card, or the waste top, was tapped. }
procedure TPairController.Pick(APos: Integer);
var
  C, S: TCard;
begin
  C := FGame.CardIn(APos);
  FToast := '';
  if C.Rank = KingRank then
  begin
    if FGame.Remove(APos, PosNone) then AfterMove
    else
    begin
      FToast := 'A King can only be taken when nothing covers it.';
      Changed;
    end;
    Exit;
  end;
  if FSel = PosNone then
    FSel := APos
  else if FSel = APos then
    FSel := PosNone
  else if FGame.CanRemove(FSel, APos) then
  begin
    FGame.Remove(FSel, APos);
    AfterMove;
    Exit;
  end
  else
  begin
    S := FGame.CardIn(FSel);
    if S.Rank + C.Rank = PairTotal then
      FToast := 'A card that is covered can only go with the card sitting on top of it.'
    else
      FToast := Format('%s and %s make %d, not 13.', [CardName(S), CardName(C), S.Rank + C.Rank]);
    FSel := APos;
  end;
  ClearHints;
  Changed;
end;

procedure TPairController.Tap(X, Y: Integer);
var
  P: TPoint;
  I: Integer;
  C: TCard;
begin
  P := Point(X, Y);
  if FGame.IsWon then
  begin
    ActionNew;
    Exit;
  end;
  if PtInRect(FStockR, P) then
  begin
    FToast := '';
    if FGame.CanDraw then
    begin
      FGame.Draw;
      AfterMove;
    end
    else if FGame.CanRecycle then
    begin
      FGame.Recycle;
      AfterMove;
    end
    else
    begin
      FToast := 'The stock is empty and cannot be turned over again.';
      Changed;
    end;
    Exit;
  end;
  if PtInRect(FWasteR, P) and FGame.WasteTop(C) then
  begin
    Pick(PosWaste);
    Exit;
  end;
  for I := PyramidSize - 1 downto 0 do      { the cards in front first }
    if not FGame.Removed(I) and PtInRect(CardRect(I), P) then
    begin
      if FGame.IsFree(I) or FGame.IsUnder(I) then Pick(I)
      else
      begin
        FToast := 'That card is covered. Take away the cards on top of it first.';
        Changed;
      end;
      Exit;
    end;
  if FSel <> PosNone then               { a tap on empty table lets go of the selection }
  begin
    FSel := PosNone;
    FToast := '';
    Changed;
  end;
end;

end.
