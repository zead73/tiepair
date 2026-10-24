unit MainForm;

{ The desktop window: buttons, a status line and a paint box. All the game flow
  (what a click does, which scene plays, saving, the buttons' state, the layout)
  lives in GameController; this unit only draws what the controller describes
  and forwards clicks, keys and button presses to it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Forms, Controls, Graphics, ExtCtrls, StdCtrls, Menus, Dialogs,
  LCLType,
  Cards, Pyramid, Inventory, Session, Stage, DuelInfo, Story, Duel, Settings, Cosmetics,
  HandFile, GameController,
  CardImages, TableBg, WinScreen, SceneView, DuelPanel, StoreView;

type
  TfrmMain = class(TForm)
    pnlTop: TPanel;
    btnNew: TButton;
    btnUndo: TButton;
    btnStore: TButton;
    btnHint: TButton;
    btnCards: TButton;
    btnRecords: TButton;
    btnMode: TButton;
    btnMenu: TButton;
    btnStartOver: TButton;
    lblStatus: TLabel;
    pbTable: TPaintBox;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure btnNewClick(Sender: TObject);
    procedure btnUndoClick(Sender: TObject);
    procedure btnStoreClick(Sender: TObject);
    procedure btnHintClick(Sender: TObject);
    procedure btnCardsClick(Sender: TObject);
    procedure btnRecordsClick(Sender: TObject);
    procedure btnModeClick(Sender: TObject);
    procedure btnMenuClick(Sender: TObject);
    procedure FormKeyPress(Sender: TObject; var Key: Char);
    procedure btnStartOverClick(Sender: TObject);
    procedure pbTablePaint(Sender: TObject);
    procedure pbTableMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  private
    FCtl: TGameController;       { the game }
    FStory: TStory;
    FImages: TCardImages;
    FTable: TTableBackground;
    FWinImage: TWinScreenImage;
    FBuffer: TBitmap;            { everything is drawn here, then copied to the screen }
    FCv: TCanvas;                { = FBuffer.Canvas while painting }
    FAnimTimer: TTimer;
    FLastTick: QWord;
    FSceneView: TSceneView;
    FPanelView: TSceneView;      { its own portrait cache, at the panel's size }
    FStoreView: TStoreView;      { the Store and the card tray }
    FAskTimer: TTimer;           { shows the initials question once the screen has settled }
    FAsking: Boolean;
    procedure ControllerChanged;
    procedure AskTimer(Sender: TObject);
    procedure ShowRulesDialog;
    procedure AnimTimer(Sender: TObject);
    procedure DrawMenu(const Full: TRect);
    procedure QuitGame;
    procedure DrawPanel;
    procedure DrawWinScreen(const Msg: string);
    procedure PaintScene;
    procedure DrawTableContents;
    procedure DrawDealing;
    procedure DrawStageCard(Slot: Integer);
    procedure DrawCard(const R: TRect; const C: TCard; FaceUp, Playable: Boolean);
    procedure DrawMark(const R: TRect; Kind: Integer);
    procedure DimCard(const R: TRect);
    procedure DrawRing(const R: TRect; Kind: Integer);
    procedure DrawPile(const R: TRect; ARecycle: Boolean);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

procedure TfrmMain.FormCreate(Sender: TObject);
var
  RS: TResourceStream;
begin
  Randomize;
  FBuffer := TBitmap.Create;
  FAnimTimer := TTimer.Create(Self);
  FAnimTimer.Enabled := False;
  FAnimTimer.Interval := 16;                 { about 60 frames a second }
  FAnimTimer.OnTimer := @AnimTimer;
  FImages := TCardImages.Create;
  FTable := TTableBackground.Create;
  FWinImage := TWinScreenImage.Create;
  FSceneView := TSceneView.Create;
  FPanelView := TSceneView.Create;
  FStoreView := TStoreView.Create;
  FAskTimer := TTimer.Create(Self);
  FAskTimer.Enabled := False;
  FAskTimer.Interval := 50;
  FAskTimer.OnTimer := @AskTimer;
  FStory := TStory.Create;
  RS := TResourceStream.Create(HInstance, 'STORY', RT_RCDATA);
  try
    FStory.LoadFromStream(RS);
  finally
    RS.Free;
  end;
  { the program's own icon, for the title bar and the task bar (Windows also has
    it in the exe; Linux takes it from here) }
  try
    RS := TResourceStream.Create(HInstance, 'TIEPAIR_ICO', RT_RCDATA);
    try
      Application.Icon.LoadFromStream(RS);
    finally
      RS.Free;
    end;
    Icon.Assign(Application.Icon);
  except
    { no icon is better than no game }
  end;
  FCtl := TGameController.Create(FStory);
  FCtl.OnChange := @ControllerChanged;
  FCtl.SetViewport(pbTable.Width, pbTable.Height);
  FCtl.CanQuit := True;                      { a program can close itself }
  FCtl.OnQuit := @QuitGame;
  FCtl.StartWithMenu;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  FAnimTimer.Enabled := False;
  FCtl.Free;              { saves the inventory }
  FStory.Free;
  FBuffer.Free;
  FSceneView.Free;
  FPanelView.Free;
  FStoreView.Free;
  FImages.Free;
  FTable.Free;
  FWinImage.Free;
end;

procedure TfrmMain.FormResize(Sender: TObject);
begin
  FCtl.SetViewport(pbTable.Width, pbTable.Height);
  ControllerChanged;
end;

{ The controller says something changed: refresh the buttons and the status
  line, repaint, and keep the timer running while anything is animating. }
procedure TfrmMain.ControllerChanged;
var
  UI: TUiState;
begin
  UI := FCtl.GetUi;
  lblStatus.Caption := UI.StatusText;
  btnNew.Enabled := not FCtl.MenuOpen;
  btnStartOver.Enabled := not FCtl.MenuOpen;
  btnUndo.Caption := UI.UndoCaption;
  btnUndo.Enabled := UI.UndoEnabled;
  btnHint.Caption := UI.HintCaption;
  btnHint.Enabled := UI.HintEnabled;
  btnMenu.Caption := UI.MenuCaption;
  { the Store button always answers (Fenwick says why he is shut mid-hand) }
  btnStore.Caption := UI.StoreCaption;
  btnStore.Enabled := UI.CardsEnabled;
  btnCards.Caption := UI.CardsCaption;
  btnCards.Enabled := UI.CardsEnabled;
  btnRecords.Caption := UI.RecordsCaption;
  btnRecords.Enabled := UI.RecordsEnabled;
  btnMode.Caption := UI.EasyCaption;
  btnMode.Enabled := UI.EasyEnabled;
  { a record was broken: ask for initials, but not from inside a repaint }
  if (UI.AskInitials or UI.AskCross or UI.ShowRules or UI.AskDelete) and not FAsking then
  begin
    FAsking := True;
    FAskTimer.Enabled := True;
  end;
  if FCtl.NeedsTicks and not FAnimTimer.Enabled then
  begin
    FLastTick := GetTickCount64;
    FAnimTimer.Enabled := True;
  end;
  pbTable.Invalidate;
end;

procedure TfrmMain.AskTimer(Sender: TObject);
var
  UI: TUiState;
  S: string;
  R: Integer;
begin
  FAskTimer.Enabled := False;
  UI := FCtl.GetUi;
  if UI.ShowRules then
  begin
    ShowRulesDialog;
    FCtl.ActionRulesClosed;
  end
  else if UI.AskDelete then
  begin
    { Keep is the default (and Esc / closing the window): nothing is deleted by accident }
    R := QuestionDlg('Delete saved game', UI.DeletePrompt, mtWarning,
      [mrNo, 'Keep it', 'IsDefault', 'IsCancel', mrYes, 'Delete it'], 0);
    FCtl.ActionAnswerDelete(R = mrYes);
  end
  else if UI.AskCross then
  begin
    { Keep is the default (and Esc / closing the window): nothing is destroyed by accident }
    R := QuestionDlg('Silver cross', UI.CrossPrompt, mtConfirmation,
      [mrNo, 'Keep the cross', 'IsDefault', 'IsCancel', mrYes, 'Play it anyway'], 0);
    FCtl.ActionAnswerCross(R = mrYes);
  end
  else if UI.AskInitials then
  begin
    S := UI.InitialsDefault;
    if not InputQuery('New record!', UI.InitialsPrompt, S) then S := '';   { Cancel = skip }
    FCtl.ActionSubmitInitials(S);
  end;
  FAsking := False;
  { in case another record was broken meanwhile }
  if FCtl.GetUi.AskInitials or FCtl.GetUi.AskCross or FCtl.GetUi.ShowRules or FCtl.GetUi.AskDelete then
  begin
    FAsking := True;
    FAskTimer.Enabled := True;
  end;
end;

{ The rules: a modal window with the text in a scrolling box (Esc or Close ends it). }
procedure TfrmMain.ShowRulesDialog;
var
  F: TForm;
  M: TMemo;
  B: TButton;
begin
  F := TForm.CreateNew(Self);
  try
    F.Caption := 'Rules';
    F.Position := poOwnerFormCenter;
    F.Width := Min(760, Screen.Width - 80);
    F.Height := Min(680, Screen.Height - 120);
    F.Color := RGBToColor(22, 13, 28);
    B := TButton.Create(F);
    B.Parent := F;
    B.Align := alBottom;
    B.BorderSpacing.Around := 10;
    B.Caption := 'Close';
    B.Default := True;
    B.Cancel := True;                          { Esc }
    B.ModalResult := mrOk;
    M := TMemo.Create(F);
    M.Parent := F;
    M.Align := alClient;
    M.BorderSpacing.Around := 10;
    M.ReadOnly := True;
    M.WordWrap := True;
    M.ScrollBars := ssAutoVertical;
    M.Color := RGBToColor(30, 19, 38);
    M.Font.Color := RGBToColor(232, 224, 204);
    M.Font.Size := 12;
    M.Text := FCtl.RulesPlainText;
    M.SelStart := 0;
    F.ShowModal;
  finally
    F.Free;
  end;
end;

procedure TfrmMain.AnimTimer(Sender: TObject);
var
  Now: QWord;
begin
  Now := GetTickCount64;
  FCtl.Tick(Integer(Now - FLastTick));
  FLastTick := Now;
  if not FCtl.NeedsTicks then FAnimTimer.Enabled := False;
end;

procedure TfrmMain.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  FCtl.KeyPress(Key = VK_ESCAPE);
end;

procedure TfrmMain.btnNewClick(Sender: TObject);
begin
  FCtl.ActionNew;
end;

procedure TfrmMain.btnUndoClick(Sender: TObject);
begin
  FCtl.ActionUndo;
end;

procedure TfrmMain.btnStoreClick(Sender: TObject);
begin
  FCtl.ActionOpenStore;
end;

procedure TfrmMain.btnHintClick(Sender: TObject);
begin
  FCtl.ActionHint;
end;

procedure TfrmMain.btnCardsClick(Sender: TObject);
begin
  FCtl.ActionOpenCards;
end;

procedure TfrmMain.btnRecordsClick(Sender: TObject);
begin
  FCtl.ActionOpenRecords;
end;

procedure TfrmMain.btnModeClick(Sender: TObject);
begin
  FCtl.ActionToggleEasy;
end;

procedure TfrmMain.btnMenuClick(Sender: TObject);
begin
  FCtl.ActionOpenMenu;
end;

procedure TfrmMain.FormKeyPress(Sender: TObject; var Key: Char);
begin
  if Key >= ' ' then FCtl.TypeChar(Key);       { the menu's hidden cheat word }
end;

procedure TfrmMain.QuitGame;
begin
  Close;
end;

{ ---- Start over ---- }

procedure TfrmMain.btnStartOverClick(Sender: TObject);
var
  R: Integer;
begin
  { Cancel is the default (and Esc / closing the window), so nothing is erased by accident }
  R := QuestionDlg('Start over',
    'What would you like to start over?' + LineEnding + LineEnding +
    'Erase everything: your coins, undo and hint cards, campaign progress, ' +
    'personal records and all saved hands are deleted, and the game starts as ' +
    'if it were brand new.' +
    LineEnding + LineEnding +
    'Restart the campaign only: the story begins again from the first vampire. ' +
    'Your coins and cards are kept.' + LineEnding + LineEnding +
    'Neither can be undone.',
    mtWarning,
    [mrYes, 'Erase everything', mrNo, 'Restart the campaign only',
     mrCancel, 'Cancel', 'IsDefault', 'IsCancel'], 0);
  if R = mrYes then FCtl.ActionEraseEverything
  else if R = mrNo then FCtl.ActionRestartCampaign;
end;

{ ---- drawing ---- }

{ A vampire's mark on a face-up card, in the top half (the lower rows may cover the
  rest): a blood-red bat for a bitten card, a chain with a padlock for a chained one. }
procedure TfrmMain.DrawMark(const R: TRect; Kind: Integer);
const
  CrossShape: array[0..11, 0..1] of Double = ((-0.14, -0.5), (0.14, -0.5), (0.14, -0.2),
    (0.34, -0.2), (0.34, 0.02), (0.14, 0.02), (0.14, 0.5), (-0.14, 0.5), (-0.14, 0.02),
    (-0.34, 0.02), (-0.34, -0.2), (-0.14, -0.2));
  Bat: array[0..15, 0..1] of Double = ((0, 0.35), (0.12, 0.12), (0.3, 0.25), (0.4, 0.05),
    (0.5, 0.2), (0.6, 0.05), (0.7, 0.25), (0.88, 0.12), (1, 0.35), (0.82, 0.38), (0.75, 0.55),
    (0.62, 0.42), (0.5, 0.6), (0.38, 0.42), (0.25, 0.55), (0.18, 0.38));
var
  W, H, X0, Y0, I, K, LW, LH, CX, CY, PW, PH: Integer;
  Pts: array[0..15] of TPoint;
  CrossPts: array[0..11] of TPoint;
begin
  if Kind = MarkNone then Exit;
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  if Kind = MarkBitten then
  begin
    PW := W * 72 div 100;
    X0 := R.Left + (W - PW) div 2;
    Y0 := R.Top + H * 9 div 100;
    for I := 0 to 15 do
      Pts[I] := Point(X0 + Round(Bat[I, 0] * PW), Y0 + Round(Bat[I, 1] * PW));
    FCv.Pen.Style := psSolid;
    FCv.Pen.Width := Max(2, FCtl.Scaled(3));
    FCv.Pen.Color := RGBToColor(255, 245, 235);
    FCv.Brush.Style := bsSolid;
    FCv.Brush.Color := RGBToColor(176, 12, 36);
    FCv.Polygon(Pts);
    { two drops of blood under it }
    FCv.Pen.Color := RGBToColor(255, 245, 235);
    FCv.Ellipse(X0 + PW * 38 div 100, Y0 + PW * 68 div 100, X0 + PW * 46 div 100, Y0 + PW * 84 div 100);
    FCv.Ellipse(X0 + PW * 56 div 100, Y0 + PW * 68 div 100, X0 + PW * 64 div 100, Y0 + PW * 84 div 100);
  end
  else if Kind = MarkCross then
  begin
    { a silver cross in a golden glow, under a peak: only a Wild card claims it }
    CX := R.Left + W div 2;
    CY := R.Top + H * 30 div 100;
    PH := H * 34 div 100;                     { the cross's height }
    FCv.Pen.Style := psSolid;
    FCv.Pen.Width := Max(1, FCtl.Scaled(2));
    FCv.Pen.Color := RGBToColor(150, 112, 30);
    FCv.Brush.Style := bsSolid;
    FCv.Brush.Color := RGBToColor(240, 205, 110);
    FCv.Ellipse(CX - PH * 62 div 100, CY - PH * 62 div 100, CX + PH * 62 div 100, CY + PH * 62 div 100);
    for I := 0 to 11 do
      CrossPts[I] := Point(CX + Round(CrossShape[I, 0] * PH), CY + Round(CrossShape[I, 1] * PH));
    FCv.Pen.Width := Max(2, FCtl.Scaled(3));
    FCv.Pen.Color := RGBToColor(30, 34, 52);
    FCv.Brush.Color := RGBToColor(226, 230, 244);
    FCv.Polygon(CrossPts);
  end
  else
  begin
    CY := R.Top + H * 30 div 100;
    LH := H * 14 div 100;
    FCv.Pen.Style := psSolid;
    FCv.Pen.Width := Max(1, FCtl.Scaled(2));
    FCv.Pen.Color := RGBToColor(20, 20, 28);
    FCv.Brush.Style := bsSolid;
    FCv.Brush.Color := RGBToColor(170, 172, 186);
    for K := 0 to 4 do                        { the links, wide and narrow in turn }
    begin
      CX := R.Left + (2 * K + 1) * W div 10;
      if K mod 2 = 0 then LW := W * 22 div 100 else LW := W * 12 div 100;
      FCv.Ellipse(CX - LW div 2, CY - LH div 2, CX + LW div 2, CY + LH div 2);
    end;
    { the padlock in the middle }
    PW := W * 24 div 100;
    PH := H * 17 div 100;
    CX := R.Left + W div 2;
    FCv.Brush.Style := bsSolid;
    FCv.Brush.Color := RGBToColor(201, 162, 74);
    FCv.Pen.Color := RGBToColor(20, 20, 28);
    FCv.RoundRect(CX - PW div 2, CY - PH div 3, CX + PW div 2, CY + PH * 2 div 3, FCtl.Scaled(3), FCtl.Scaled(3));
    FCv.Brush.Color := RGBToColor(20, 20, 28);
    FCv.Ellipse(CX - PW div 8, CY - PH div 12, CX + PW div 8, CY + PH div 6);
  end;
  FCv.Pen.Width := 1;
end;

procedure TfrmMain.DrawCard(const R: TRect; const C: TCard;
  FaceUp, Playable: Boolean);
var
  Rad: Integer;
begin
  Rad := FCtl.Scaled(8);
  FImages.SetSize(R.Right - R.Left, R.Bottom - R.Top);
  if FaceUp then
  begin
    FCv.Draw(R.Left, R.Top, FImages.Face(C));
    if Playable then
      with FCv do
      begin
        Pen.Color := RGBToColor(255, 215, 0);
        Pen.Width := FCtl.Scaled(3);
        Brush.Style := bsClear;
        RoundRect(R, Rad, Rad);
        Brush.Style := bsSolid;
      end;
  end
  else
    DrawCardBack(FCv, R);
end;

{ A card that cannot be taken yet is dimmed a little. }
procedure TfrmMain.DimCard(const R: TRect);
var
  Inset: Integer;
begin
  Inset := FCtl.Scaled(4);
  FSceneView.DrawOverlay(FCv, Rect(R.Left + Inset, R.Top + Inset, R.Right - Inset, R.Bottom - Inset),
    RGBToColor(8, 4, 16), 0.38);
end;

{ A glowing outline: Kind 0 = selected (gold), 1 = a hint or a card that can be picked (blue). }
procedure TfrmMain.DrawRing(const R: TRect; Kind: Integer);
begin
  with FCv do
  begin
    Pen.Style := psSolid;
    if Kind = 0 then Pen.Color := RGBToColor(255, 215, 0)
    else Pen.Color := RGBToColor(110, 220, 255);
    Pen.Width := Max(2, FCtl.Scaled(4));
    Brush.Style := bsClear;
    RoundRect(R, FCtl.Scaled(8), FCtl.Scaled(8));
    Brush.Style := bsSolid;
    Pen.Width := 1;
  end;
end;

{ An empty stock or waste place; with a turn-over left it carries a circling arrow. }
procedure TfrmMain.DrawPile(const R: TRect; ARecycle: Boolean);
var
  CX, CY, Rad: Integer;
begin
  with FCv do
  begin
    Pen.Style := psSolid;
    Pen.Width := 2;
    Pen.Color := RGBToColor(110, 92, 48);
    Brush.Style := bsClear;
    RoundRect(R, FCtl.Scaled(7), FCtl.Scaled(7));
    if ARecycle then
    begin
      CX := (R.Left + R.Right) div 2;
      CY := (R.Top + R.Bottom) div 2;
      Rad := (R.Right - R.Left) * 22 div 100;
      Pen.Color := RGBToColor(226, 195, 117);
      Pen.Width := Max(2, FCtl.Scaled(4));
      Arc(CX - Rad, CY - Rad, CX + Rad, CY + Rad, CX + Rad, CY - Rad, CX + Rad, CY - Rad + Rad div 4);
      Brush.Style := bsSolid;
      Brush.Color := RGBToColor(226, 195, 117);
      Pen.Width := 1;
      Polygon([Point(CX + Rad - Rad div 2, CY - Rad - Rad div 4), Point(CX + Rad + Rad div 2, CY - Rad - Rad div 4),
        Point(CX + Rad, CY - Rad + Rad div 3)]);
    end;
    Brush.Style := bsSolid;
    Pen.Width := 1;
  end;
end;

procedure TfrmMain.DrawWinScreen(const Msg: string);
var
  Area: TRect;
begin
  { leave room for the frame and for a line of text at the bottom }
  Area := Rect(FCtl.Scaled(30), FCtl.Scaled(24), pbTable.Width - FCtl.Scaled(30),
    pbTable.Height - FCtl.Scaled(52));
  FWinImage.Draw(FCv, Area);
  with FCv do
  begin
    Brush.Style := bsClear;
    Font.Name := 'default';
    Font.Style := [];
    Font.Size := FCtl.Scaled(11);
    if Font.Size < 8 then Font.Size := 8;
    Font.Color := RGBToColor(150, 125, 70);
    TextOut((pbTable.Width - TextWidth(Msg)) div 2, pbTable.Height - FCtl.Scaled(40), Msg);
    Brush.Style := bsSolid;
  end;
end;

procedure TfrmMain.DrawPanel;
var
  R: TRect;
begin
  R := FCtl.PanelRect;
  if R.Right <= R.Left then Exit;
  DrawDuelPanel(FCv, R, FCtl.DuelInfo, FCtl.PanelStats, FPanelView);
end;

procedure TfrmMain.pbTablePaint(Sender: TObject);
begin
  { draw off screen and copy in one go: no flicker while animating }
  if (FBuffer.Width <> pbTable.Width) or (FBuffer.Height <> pbTable.Height) then
    FBuffer.SetSize(pbTable.Width, pbTable.Height);
  FCv := FBuffer.Canvas;
  FCtl.SetViewport(pbTable.Width, pbTable.Height);
  { the look the player chose: card backs, table cloth, the moon on the house }
  BackStyle := FCtl.StyleBack;
  FTable.SetCloth(FCtl.StyleCloth);
  FSceneView.SetHouse(HouseImageKey(FCtl.StyleMoon));
  FPanelView.SetHouse(HouseImageKey(FCtl.StyleMoon));
  PaintScene;
  pbTable.Canvas.Draw(0, 0, FBuffer);
end;

procedure TfrmMain.PaintScene;
var
  Full: TRect;
  St: TStage;
begin
  St := FCtl.Stage;
  Full := Rect(0, 0, pbTable.Width, pbTable.Height);
  if FCtl.MenuOpen then
  begin
    DrawMenu(Full);
    FStoreView.Draw(FCv, FCtl, FSceneView, Full);      { the save / load slots, if open }
    Exit;
  end;
  FTable.Draw(FCv, Full, FCtl.Scale);
  case St.Backdrop of
    sbDialogue: FSceneView.DrawDialogue(FCv, Full, St);
    sbHouse: FSceneView.DrawHouseScene(FCv, Full, St);
    sbWinPicture: DrawWinScreen(FCtl.WinMessage);
  else
  begin
    DrawTableContents;
    DrawPanel;                                   { nothing in Free Play }
    { a missed move flashes the table red }
    FSceneView.DrawOverlay(FCv, Full, RGBToColor(190, 10, 20), St.Scalar[ssFlashRed]);
  end;
  end;
  FStoreView.Draw(FCv, FCtl, FSceneView, Full);      { the Store or the card tray, if open }
  { fading to or from black }
  FSceneView.DrawOverlay(FCv, Full, clBlack, St.Scalar[ssDim]);
end;

{ The start menu: the house on the hill, the title and the buttons. }
procedure TfrmMain.DrawMenu(const Full: TRect);
const
  FontName = 'Times New Roman';
var
  I, K10, Th: Integer;
  R, T: TRect;
  Cap: string;
begin
  FSceneView.DrawHousePicture(FCv, Full, 0.0);
  { a darker band behind the buttons so they read against the picture }
  FSceneView.DrawOverlay(FCv, Rect(Full.Left, Full.Top + (Full.Bottom - Full.Top) * 44 div 100,
    Full.Right, Full.Bottom), RGBToColor(8, 5, 14), 0.55);
  T := FCtl.MenuTitleRect;
  K10 := T.Bottom - T.Top;
  FCv.Brush.Style := bsClear;
  FCv.Font.Name := FontName;
  FCv.Font.Style := [fsBold, fsItalic];
  FCv.Font.Size := Max(20, K10 * 52 div 100 * 72 div 96);
  Cap := 'Tiepair';
  FCv.Font.Color := RGBToColor(0, 0, 0);
  FCv.TextOut((T.Left + T.Right - FCv.TextWidth(Cap)) div 2 + 3, T.Top + 3, Cap);
  FCv.Font.Color := RGBToColor(232, 224, 204);
  FCv.TextOut((T.Left + T.Right - FCv.TextWidth(Cap)) div 2, T.Top, Cap);
  Th := FCv.TextHeight(Cap);
  Cap := FCtl.MenuSubtitle;
  FCv.Font.Style := [fsItalic];
  FCv.Font.Size := Max(10, K10 * 17 div 100 * 72 div 96);
  FCv.Font.Color := RGBToColor(201, 162, 74);
  FCv.TextOut((T.Left + T.Right - FCv.TextWidth(Cap)) div 2, T.Top + Th + 2, Cap);
  for I := 0 to FCtl.MenuButtonCount - 1 do
  begin
    R := FCtl.MenuButtonRect(I);
    FCv.Brush.Style := bsSolid;
    FCv.Brush.Color := RGBToColor(22, 13, 28);
    FCv.Pen.Style := psSolid;
    FCv.Pen.Width := 2;
    FCv.Pen.Color := RGBToColor(201, 162, 74);
    FCv.RoundRect(R.Left, R.Top, R.Right, R.Bottom, 14, 14);
    FCv.Pen.Width := 1;
    FCv.Pen.Color := RGBToColor(110, 90, 46);
    FCv.Brush.Style := bsClear;
    FCv.RoundRect(R.Left + 5, R.Top + 5, R.Right - 5, R.Bottom - 5, 10, 10);
    Cap := FCtl.MenuButtonCaption(I);
    FCv.Font.Style := [fsBold];
    FCv.Font.Size := Max(11, (R.Bottom - R.Top) * 36 div 100 * 72 div 96);
    if FCtl.MenuButtonEnabled(I) then
      FCv.Font.Color := RGBToColor(232, 224, 204)
    else
      FCv.Font.Color := RGBToColor(110, 100, 90);                 { dimmed: nothing to save yet }
    FCv.TextOut((R.Left + R.Right - FCv.TextWidth(Cap)) div 2,
      (R.Top + R.Bottom - FCv.TextHeight(Cap)) div 2, Cap);
  end;
  FCv.Font.Style := [];                                           { the version, small, in the corner }
  FCv.Font.Size := 10;
  FCv.Font.Color := RGBToColor(190, 160, 90);
  Cap := FCtl.MenuVersion;
  FCv.TextOut(Full.Right - FCv.TextWidth(Cap) - 10, Full.Bottom - FCv.TextHeight(Cap) - 6, Cap);
  if FCtl.MenuNote <> '' then
  begin
    R := FCtl.MenuButtonRect(FCtl.MenuButtonCount - 1);
    FCv.Font.Style := [fsItalic];
    FCv.Font.Size := 11;
    FCv.Font.Color := RGBToColor(201, 162, 74);
    FCv.TextOut((Full.Right + Full.Left - FCv.TextWidth(FCtl.MenuNote)) div 2, Min(R.Bottom + 10, Full.Bottom - FCv.TextHeight('A') - 4), FCtl.MenuNote);
  end;
end;

procedure TfrmMain.DrawTableContents;
var
  I, N: Integer;
  G: TPyramidGame;
  R: TRect;
  C: TCard;
begin
  G := FCtl.Game;
  case FCtl.TableMode of
    tmDealing:
    begin
      DrawDealing;
      Exit;
    end;
    tmWon:
    begin
      DrawWinScreen(FCtl.WinMessage);
      Exit;
    end;
  end;
  for I := 0 to PyramidSize - 1 do      { lower rows on top }
    if not G.Removed(I) then
    begin
      R := FCtl.CardRect(I);
      DrawCard(R, G.CardAt(I), True, False);
      if not G.IsFree(I) and not G.IsUnder(I) then DimCard(R);
      DrawMark(R, FCtl.CardMark(I));                      { a vampire's bite, chain or the silver cross }
    end;
  for I := 0 to PyramidSize - 1 do      { the outlines last, so that no card covers them }
    if not G.Removed(I) then
    begin
      if FCtl.CardSelected(I) then DrawRing(FCtl.CardRect(I), 0)
      else if FCtl.CardHighlighted(I) then DrawRing(FCtl.CardRect(I), 1);
    end;
  { the stock and the waste }
  R := FCtl.StockRect;
  if G.StockCount > 0 then
    DrawCard(R, G.CardAt(0), False, False)
  else
    DrawPile(R, G.CanRecycle);
  if FCtl.StockHighlighted then DrawRing(R, 1);
  R := FCtl.WasteRect;
  if G.WasteTop(C) then DrawCard(R, C, True, False) else DrawPile(R, False);
  if FCtl.WasteSelected then DrawRing(R, 0)
  else if FCtl.WasteHighlighted then DrawRing(R, 1);
  { Seer's eye: the next three cards of the stock, fanned beside the waste }
  if G.Revealed and (G.StockCount > 0) then
    for I := Min(2, G.StockCount - 1) downto 0 do
    begin
      R := FCtl.WasteRect;
      N := (R.Right - R.Left) * 6 div 10;
      OffsetRect(R, (R.Right - R.Left) + FCtl.Scaled(14) + (2 - I) * N div 2, 0);
      R.Right := R.Left + N;
      R.Bottom := R.Top + (R.Bottom - R.Top) * 6 div 10;
      FImages.SetSize(R.Right - R.Left, R.Bottom - R.Top);
      FCv.Draw(R.Left, R.Top, FImages.Face(G.StockCard(I)));
    end;
end;

procedure TfrmMain.DrawDealing;
var
  Pass, Slot: Integer;
  Settled: Boolean;
begin
  DrawCard(FCtl.StockRect, FCtl.Game.CardAt(0), False, False);     { the pile the cards leave }
  for Pass := 0 to 1 do                    { cards in place first, flying ones on top }
    for Slot := 0 to PyramidSize - 1 do
    begin
      if FCtl.Stage.Move[Slot] <= 0 then Continue;             { still in the stock }
      Settled := FCtl.Stage.Move[Slot] >= 1;
      if (Pass = 0) = Settled then DrawStageCard(Slot);
    end;
end;

procedure TfrmMain.DrawStageCard(Slot: Integer);
var
  Src, Dst, R, Rs: TRect;
  P, F: Double;
  W, H, NewW, CX: Integer;
  FaceUp: Boolean;
  C: TCard;
begin
  Src := FCtl.StockRect;
  Dst := FCtl.CardRect(Slot);
  P := FCtl.Stage.Move[Slot];
  W := Src.Right - Src.Left;
  H := Src.Bottom - Src.Top;
  R.Left := Src.Left + Round((Dst.Left - Src.Left) * P);
  R.Top := Src.Top + Round((Dst.Top - Src.Top) * P);
  R.Right := R.Left + W;
  R.Bottom := R.Top + H;

  { a flip squeezes the card to an edge and widens it again, face on the far side }
  F := FCtl.Stage.Flip[Slot];
  if F < 0.5 then
  begin
    NewW := Round(W * (1 - 2 * F));
    FaceUp := False;
  end
  else
  begin
    NewW := Round(W * (2 * F - 1));
    FaceUp := True;
  end;
  if NewW < 2 then Exit;                                   { edge-on: invisible }
  CX := (R.Left + R.Right) div 2;
  Rs := Rect(CX - NewW div 2, R.Top, CX - NewW div 2 + NewW, R.Bottom);

  if FaceUp then
  begin
    C := FCtl.Game.CardAt(Slot);
    FImages.SetSize(W, H);
    if NewW = W then
      FCv.Draw(R.Left, R.Top, FImages.Face(C))
    else
      FCv.StretchDraw(Rs, FImages.Face(C));
  end
  else
    DrawCardBack(FCv, Rs);
end;

procedure TfrmMain.pbTableMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button <> mbLeft then Exit;
  FCtl.SetViewport(pbTable.Width, pbTable.Height);
  FCtl.Tap(X, Y);
end;

end.
