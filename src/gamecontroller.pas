unit GameController;

{ The game's flow, with no window code: what a tap does, which scene plays
  when, what is saved and when, which buttons are on, what the status line
  says, and where everything sits on the table. The desktop window and the web
  page are both thin: they draw what the controller describes, and forward
  taps, key presses and button presses to it.

  How a front end uses it:
    * create it with the story, call SetViewport with the drawing area's size
      (again on every resize), then Start;
    * draw from Stage / Game / Session / DuelInfo and the rectangles
      (CardRect, StockRect, WasteRect, PanelRect), using TableMode to know
      whether to draw the dealing cards, the "you won" picture or the table;
    * call Tick(ms) while NeedsTicks is True (about 60 times a second);
    * redraw and refresh its buttons and status line from GetUi whenever
      OnChange is called. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Types, Math, Cards, Pyramid, Inventory, Session, Sound, Anim, Stage,
  NewGameAnim, Vampires, Story, Campaign, Duel, DuelSession, DuelInfo, Scenes,
  Settings, HandFile, CampaignSlots, StartOver, Storage, Specials, Records, Rules, Trophies, Cosmetics, Relics, Version;

const
  { The table is laid out on a fixed design grid and scaled to fit. The pyramid is
    seven cards wide at the bottom; a card sits half a step (HalfStep) further in for
    each row up, and rows overlap by half a card. }
  CardW = 64;
  CardH = 91;
  CardGap = 8;
  MarginX = 40;
  MarginY = 20;
  HalfStep = (CardW + CardGap) div 2;       { pixels per half-card step }
  RowStep = CardH div 2;
  DesignW = 2 * MarginX + 12 * HalfStep + CardW;
  DesignH = MarginY + 6 * RowStep + CardH + 40 + CardH + MarginY;

type
  { Where the side panel (the duel, or in Free Play your stats) goes: not shown
    (a small window), in a column on the left, or in a strip under the table
    (tall, narrow screens such as a tablet held upright). }
  TPanelPlacement = (ppNone, ppLeft, ppBottom);

  { What the table area is showing. }
  TTableMode = (tmNormal, tmDealing, tmWon);

  TUiState = record
    StatusText: string;
    UndoCaption, HintCaption: string;
    EasyCaption: string;            { 'Mode: Normal' or 'Mode: Easy' (Free Play's choice) }
    EasyEnabled: Boolean;
    MenuCaption: string;            { the button that goes back to the start menu }
    StoreCaption, CardsCaption: string;
    UndoEnabled, HintEnabled: Boolean;
    SaveEnabled, LoadEnabled: Boolean;
    StoreEnabled: Boolean;          { the shop is open (between hands) }
    CardsEnabled: Boolean;
    ShopOpen: Boolean;
    ShopClosedReason: string;       { why the Store is shut mid-hand }
    CanSkip: Boolean;               { a scene or the deal is playing and can be skipped }
    InScene: Boolean;
    Targeting: Boolean;             { waiting for a tap on a card (Wild card, Wood Stake) }
    CancelCaption: string;
    RecordsCaption: string;
    RecordsEnabled: Boolean;
    { A record was just broken: the front end should ask for the player's
      initials (pre-filled with InitialsDefault) and call ActionSubmitInitials. }
    AskInitials: Boolean;
    InitialsPrompt, InitialsDefault: string;
    { A tap would play the silver cross as an ordinary card, which destroys it
      (only a Wild card claims it): the front end should ask, and call
      ActionAnswerCross(True) to play it anyway or (False) to keep it. }
    AskCross: Boolean;
    CrossPrompt: string;
    { The Rules button was pressed: the front end shows the rules (RulesSectionCount,
      RulesHeading, RulesBody) and calls ActionRulesClosed when they are dismissed. }
    ShowRules: Boolean;
    { Delete was pressed on a saved game: the front end should ask (DeletePrompt) and
      call ActionAnswerDelete(True) to delete it or (False) to keep it. }
    AskDelete: Boolean;
    DeletePrompt: string;
  end;

  { The Store (Fenwick's goods) and the tray of your own special cards are two
    overlays drawn over the table; both are a list of rows with a button. }
  TOverlayKind = (okNone, okStore, okCards, okRecords, okSlots, okTrophies, okStyle, okRelics);

  TOverlayRow = record
    Title, Detail: string;
    Aside: string;                  { the price, or how many you own }
    ButtonText: string;
    ButtonEnabled: Boolean;
    Art: Integer;                   { 0..5 = Ord(TSpecialKind), 6 = undo cards, 7 = hint cards, -1 = none }
    Selected: Boolean;
    Header: Boolean;                { a section heading, not a row }
    Button2Text: string;            { a second, smaller button to the left of the first (a saved game's Delete) }
    Button2Enabled: Boolean;
    Preview: Integer;               { 0 none; else Ord(kind) * 16 + item + 1: a small picture drawn in code (Style page) }
  end;

const
  StoreGoodCount = SpecialCount + 2;       { the six cards, undo cards and hint cards }
  ArtUndo = SpecialCount;
  ArtHint = SpecialCount + 1;
  { The trophy page reuses the picture slots after the Store's goods: ArtTrophy0 + the
    trophy's number, or ArtTrophyEmpty for a trophy not earned yet (an empty tile). }
  ArtTrophy0 = StoreGoodCount;
  ArtTrophyEmpty = StoreGoodCount + TrophyCount;
  StyleTabHeight = 34;                       { the tabs on the Style page }
  ArtRelic0 = ArtTrophyEmpty + 1;            { the relics' pictures follow (ArtTrophyEmpty itself has none) }
  OverlayArtCount = ArtRelic0 + RelicCount;  { pictures to load: the goods, the trophies and the relics }

type
  TChangeEvent = procedure of object;

  TOverlayLayout = record
    Panel, Portrait, Speech, Leave, Footer: TRect;
    X0, X1, RowsTop, RowH: Integer;
  end;

  TGameController = class
  private
    FStory: TStory;                 { borrowed }
    FSession: TGameSession;
    FGame: TPyramidGame;
    FCampaign: TCampaign;
    FDuel: TDuelSession;
    FSettings: TSettings;
    FStage: TStage;
    FSeq: TAnimSequence;            { the running animation, if any }
    FFx: TAnimSequence;             { a short effect alongside play (never blocks input) }
    FHooks: TSceneHooks;
    FDealWav: string;
    FCampaignMode: Boolean;
    FInScene: Boolean;
    FAllowBottomPanel: Boolean;
    FToast: string;
    FTrophies: TTrophies;
    FStyleTab: Integer;        { which kind the Style page shows: 0 backs, 1 cloths, 2 moons }
    FNews: string;             { 'Trophy earned: ...' until the next tap on the table }
    FDeleteAsk: Integer;       { the slot row whose Delete is waiting for an answer (-1 = none) }
    FRulesShow: Boolean;       { the rules are being shown (by the front end) }
    FCrossAsk: Integer;        { 0 = a pair that takes the silver cross card is waiting for the player's answer (-1 = none) }
    FCrossA, FCrossB: Integer; { ... and the pair }
    FPick: Integer;            { the card selected for a pair: a pyramid position, PosWaste, or PosNone }
    FTargetA: Integer;         { Wild card: the first of its two cards (PosNone = none yet) }
    FOnChange: TChangeEvent;
    FDeckProvider: TDeckProvider;
    FOverlay: TOverlayKind;
    FSelected: Integer;             { the Store row Fenwick is talking about (-1 = none) }
    FStoreLine: string;             { what Fenwick is saying }
    FIntro: TStringArray;           { his first-visit lines, one per tap }
    FIntroAt: Integer;              { the line showing; = Length(FIntro) when done }
    FVisits, FSales, FRefusals: Integer;
    FTargeting: Boolean;            { a Wild card or Wood Stake waits for a card to be tapped }
    FTargetKind: TSpecialKind;
    FRecords: TRecords;
    FPending: TRecordSet;           { records just broken, waiting for the player's initials }
    FMenuOpen: Boolean;             { the start menu is up (nothing else can be done)  }
    FStarted: Boolean;              { a mode has been entered since the program began }
    FMenuTyped, FMenuNote: string;  { the hidden cheat word being typed, and its answer }
    FSlotsSave: Boolean;            { the slot screen is for saving (else loading) }
    FCanQuit: Boolean;
    FOnQuit: TChangeEvent;
    FVW, FVH: Integer;              { the drawing area }
    FScale: Double;
    FOffX, FOffY: Integer;
    procedure Changed;
    procedure EarnTrophy(T: TTrophy);
    function RelicOwned(R: TRelic): Boolean;
    function RelicsEquippedMask: Integer;
    function RelicRow(I: Integer): TOverlayRow;
    procedure RelicAction(I: Integer);
    function StyleAvailable(K: TCosmeticKind; I: Integer): Boolean;
    function StyleChoice(K: TCosmeticKind): Integer;
    function StyleRow(I: Integer): TOverlayRow;
    procedure StyleAction(I: Integer);
    function DeleteText: string;
    procedure SessionWon(BestStreak, Misses: Integer);
    procedure DuelWon(V, TotalLost, BestStreak, Misses: Integer; Kill: Boolean);
    function NeedInitials: Boolean;
    function PendingText: string;
    function RecordRow(I: Integer): TOverlayRow;
    procedure CloseModes;           { close the overlay and stop targeting }
    procedure RowAction(I: Integer);
    procedure SelectRow(I: Integer);
    procedure TapOverlay(X, Y: Integer);
    procedure TapTarget(X, Y: Integer);
    procedure TapTable(X, Y: Integer);
    procedure TapStock;
    procedure PickCard(APos: Integer);
    procedure TryRemove(A, B: Integer);
    function HitPyramid(X, Y: Integer): Integer;
    procedure AfterTableMove;
    procedure ApplyFreeRules;
    procedure AfterSpecial(Used: Boolean);
    function GoodArt(I: Integer): Integer;
    function IntroActive: Boolean;
    function Stocked(I: Integer): Boolean;
    procedure SyncPrices;                      { the Store price level for the vampire you face }
    function CanSaveNow: Boolean;
    function SlotRowInfo(I: Integer; out Camp: Boolean; out N: Integer): Boolean;
    function SlotRow(I: Integer): TOverlayRow;
    procedure SlotAction(I: Integer);
    procedure SaveFreeSlot(N: Integer);
    procedure SaveCampaignSlot(N: Integer);
    procedure LoadFreeSlot(N: Integer);
    procedure LoadCampaignSlot(N: Integer);
    procedure OpenSlots(ForSave: Boolean);
    procedure TapMenu(X, Y: Integer);
    procedure MenuChoose(I: Integer);
    procedure AdvanceIntro;
    function Layout: TOverlayLayout;
    procedure SetDeckProvider(AProvider: TDeckProvider);
    procedure UpdateScale;
    function Sc(V: Integer): Integer;
    function TableAreaHeight: Integer;
    procedure DealHand;
    procedure DoNewGame;
    function Animating: Boolean;
    procedure StartNewGameAnim;
    procedure PlayDealSound;
    procedure RunFx(Seq: TAnimSequence);
    procedure StartMissFx;
    procedure StartFadeIn(Ms: Integer);
    procedure DropFx;
    procedure StopSeq;
    procedure AutoSave;
    function ResumeFreePlayHand: Boolean;
    function ResumeCampaignHand: Boolean;
    procedure EnterCampaign;
    procedure ExitCampaign;
    procedure StartScene;
    procedure SceneFinished;
    procedure SequenceFinished;
    procedure SkipScene;
    procedure SkipDeal;
    procedure ResolveDuel;
    function HandIsLive: Boolean;
    function ShopOpen: Boolean;
    procedure HookToll;
    procedure HookNo;
    procedure HookBlow;
    procedure HookFanfare;
  public
    constructor Create(AStory: TStory);
    destructor Destroy; override;
    { Opens the game where the player left off (or deals a first hand). }
    procedure Start;
    { Opens on the start menu instead: nothing is dealt or resumed until the
      player picks Campaign or Free Play (see MenuChoose). }
    procedure StartWithMenu;

    { ---- the start menu (a picture of the house and three buttons) ---- }
    property MenuOpen: Boolean read FMenuOpen;
    function MenuButtonCount: Integer;
    function MenuButtonCaption(I: Integer): string;   { Campaign, Free Play, Save game, Load game, Rules, Quit }
    function MenuButtonRect(I: Integer): TRect;
    function MenuButtonEnabled(I: Integer): Boolean;  { Save needs a hand that can be saved }
    function MenuTitleRect: TRect;
    function MenuSubtitle: string;                   { under the title: the campaign's name }
    function MenuVersion: string;                    { 'v0.9.1': drawn small in a corner of the menu }
    property MenuNote: string read FMenuNote;         { e.g. the cheat's answer }
    { Typing on the menu: a hidden word gives 900 coins (cheat mode, for testing). }
    procedure TypeChar(C: Char);
    procedure ActionOpenMenu;
    { The front end says whether it can close the program (the web page cannot);
      choosing Quit then calls OnQuit. }
    property CanQuit: Boolean read FCanQuit write FCanQuit;
    property OnQuit: TChangeEvent read FOnQuit write FOnQuit;

    { ---- the drawing area and the layout ---- }
    procedure SetViewport(W, H: Integer);
    function PanelPlacement: TPanelPlacement;
    function PanelRect: TRect;                 { empty when there is no panel }
    function CardRect(I: Integer): TRect;
    function StockRect: TRect;
    function WasteRect: TRect;
    property Scale: Double read FScale;
    function Scaled(V: Integer): Integer;      { design units -> pixels }
    { Web only: allow the panel under the table on tall screens. }
    property AllowBottomPanel: Boolean read FAllowBottomPanel write FAllowBottomPanel;

    { ---- what to draw ---- }
    property Stage: TStage read FStage;
    property Game: TPyramidGame read FGame;
    property Session: TGameSession read FSession;
    property Duel: TDuelSession read FDuel;
    property Campaign: TCampaign read FCampaign;
    property CampaignMode: Boolean read FCampaignMode;
    property InScene: Boolean read FInScene;
    function TableMode: TTableMode;
    { The line shown under the "you won" picture. }
    function WinMessage: string;
    function DuelInfo: TDuelInfo;
    { The numbers for the side panel: cards left, stock, streak, coins, and in
      Free Play what this hand pays. }
    function PanelStats: TPanelStats;
    function GetUi: TUiState;
    function SlotInfo(N: Integer): TSlotInfo;

    { ---- time ---- }
    function NeedsTicks: Boolean;
    procedure Tick(DeltaMs: Integer);

    { ---- what the player does ---- }
    procedure Tap(X, Y: Integer);              { a click or a finger on the table }
    procedure KeyPress(IsEscape: Boolean);     { any key; Escape skips a whole scene }
    procedure SkipPressed;                     { an on-screen "skip" control }
    procedure ActionNew;
    procedure ActionUndo;
    procedure ActionHint;
    procedure ActionBuyUndo;
    procedure ActionBuyHint;
    procedure ActionToggleMode;
    procedure ActionSaveSlot(N: Integer);
    procedure ActionLoadSlot(N: Integer);
    procedure ActionEraseEverything;
    procedure ActionRestartCampaign;
    { ---- the Store, the card tray and special cards ---- }
    procedure ActionOpenStore;
    procedure ActionOpenCards;
    procedure ActionOpenRecords;
    procedure ActionSubmitInitials(const S: string);     { '' = skip }
    procedure ActionAnswerCross(APlayIt: Boolean);       { the question in UiState.AskCross }
    { ---- trophies: the shelf in the side panel and the page it opens ---- }
    property Trophies: TTrophies read FTrophies;
    function TrophyLayout: TTrophyLayout;      { the shelf's rectangles (empty with no panel) }
    function TrophyArt(I: Integer): Integer;   { the picture slot to draw for shelf slot I }
    procedure ActionOpenTrophies;
    { ---- Style: card backs, table cloths and the colour of the moon ---- }
    procedure ActionOpenStyle;
    { ---- relics: small permanent helps from Fenwick, carried in a few slots ---- }
    procedure ActionOpenRelics;
    function RelicSlotCount: Integer;          { one, and one more for each vampire trophy }
    function RelicEquipped(R: TRelic): Boolean;
    function StyleBack: Integer;               { the choice in use (0 = the original look) }
    function StyleCloth: Integer;
    function StyleMoon: Integer;
    procedure ActionAnswerDelete(ADelete: Boolean);      { the question in UiState.AskDelete }
    procedure ActionRulesClosed;                         { the rules shown for UiState.ShowRules were dismissed }
    function RulesSectionCount: Integer;
    function RulesHeading(I: Integer): string;
    function RulesBody(I: Integer): string;               { paragraphs separated by Rules.RulesBreak }
    function RulesPlainText: string;                      { all of it, as one text }
    property Records: TRecords read FRecords;
    procedure ActionCloseOverlay;
    procedure ActionCancel;                    { stop choosing a card for a special card }
    function Overlay: TOverlayKind;
    function OverlayRowCount: Integer;
    function OverlayRow(I: Integer): TOverlayRow;
    function OverlayTitle: string;
    function OverlayLine: string;              { Fenwick's words, or the tray's help }
    function OverlayHint: string;              { a quiet line, e.g. "tap to go on" }
    function OverlayFooter: string;            { your coins }
    function OverlayLeaveCaption: string;
    function ShopkeeperName: string;
    function ShopkeeperTitle: string;
    { The overlay's layout in the drawing area (the portrait rectangle is empty
      for the tray). }
    function OverlayPanelRect: TRect;
    function OverlayPortraitRect: TRect;
    function OverlaySpeechRect: TRect;
    function OverlayRowRect(I: Integer): TRect;
    function OverlayButtonRect(I: Integer): TRect;
    function OverlayButton2Rect(I: Integer): TRect;   { the second button, left of the first }
    { Tabs above the rows (the Style page: card backs, table cloths, the moon) and a
      button beside Close (the Store: Style). }
    function OverlayTabCount: Integer;
    function OverlayTabRect(I: Integer): TRect;
    function OverlayTabCaption(I: Integer): string;
    function OverlayTabSelected(I: Integer): Boolean;
    function OverlayExtraCount: Integer;              { buttons beside Close: the Store has Style and Relics }
    function OverlayExtraCaption(I: Integer): string;
    function OverlayExtraRect(I: Integer): TRect;
    function OverlayLeaveRect: TRect;
    function OverlayFooterRect: TRect;
    { Drawing the table: is this card shown face up (free, or Seer's eye)? is it
      outlined (a move was hinted, or it can be picked as a target)? }
    function CardFaceUp(I: Integer): Boolean;
    { The card selected for a pair (a pyramid position, PosWaste, or PosNone), and the
      cards a hint points at. }
    property Pick: Integer read FPick;
    function CardSelected(I: Integer): Boolean;
    function WasteSelected: Boolean;
    function WasteHighlighted: Boolean;
    function StockHighlighted: Boolean;          { the hint says: draw }
    { Free Play: the Easy rule on or off (a different mode deals a new hand). }
    function FreeEasy: Boolean;
    procedure ActionToggleEasy;
    { The vampire's mark on card I that should be drawn on it (MarkBitten, MarkChained,
      or MarkNone): only on a card that is face up (or revealed), never on its back. }
    function CardMark(I: Integer): Integer;
    function CardHighlighted(I: Integer): Boolean;
    { A message to show in the status line until the next action. }
    procedure SetToast(const Msg: string);

    property OnChange: TChangeEvent read FOnChange write FOnChange;
    { Tests rig the deals with this (nil = ordinary shuffles). }
    property DeckProvider: TDeckProvider read FDeckProvider write SetDeckProvider;
  end;

implementation

const
  PanelMargin = 30;          { from the window edge, inside the table's gold frame }
  PanelGap = 14;             { between the panel and the table }
  PanelMinWindow = 720;      { too narrow for a left panel below this }

constructor TGameController.Create(AStory: TStory);
begin
  inherited Create;
  FStory := AStory;
  FCrossAsk := -1;
  FCrossA := PosNone;
  FCrossB := PosNone;
  FPick := PosNone;
  FTargetA := PosNone;
  FDeleteAsk := -1;
  FStage := TStage.Create;
  FSession := TGameSession.Create(DefaultInventoryFile);
  FGame := FSession.Game;
  FCampaign := TCampaign.Create(DefaultCampaignFile);
  FDuel := TDuelSession.Create(FSession, FCampaign);
  FSettings := TSettings.Create(DefaultSettingsFile);
  FRecords := TRecords.Create(DefaultRecordsFile);
  FTrophies := TTrophies.Create(DefaultTrophiesFile);
  if FTrophies.IsNew then FTrophies.SeedFrom(FRecords, FCampaign.Current);   { what the records already prove }
  FSession.RelicProvider := @RelicsEquippedMask;                              { every deal asks what is equipped }
  FSession.OnWon := @SessionWon;
  FDuel.OnHandWon := @DuelWon;
  FHooks.OnToll := @HookToll;
  FHooks.OnNo := @HookNo;
  FHooks.OnBlow := @HookBlow;
  FHooks.OnFanfare := @HookFanfare;
  FScale := 1;
end;

destructor TGameController.Destroy;
begin
  FSeq.Free;
  FFx.Free;
  FStage.Free;
  FDuel.Free;
  FSettings.Free;
  FTrophies.Free;
  FRecords.Free;
  FCampaign.Free;
  FSession.Free;          { saves the inventory }
  inherited Destroy;
end;

procedure TGameController.Changed;
begin
  if Assigned(FOnChange) then FOnChange();
end;

procedure TGameController.SetDeckProvider(AProvider: TDeckProvider);
begin
  FDeckProvider := AProvider;
  FDuel.OnNeedDeck := AProvider;               { duel hands use it too }
end;

procedure TGameController.StartWithMenu;
begin
  FStarted := False;
  FMenuOpen := True;
  FMenuTyped := '';
  FMenuNote := '';
  Changed;
end;

procedure TGameController.Start;
begin
  FStarted := True;
  if ShouldResumeCampaign(FSettings, FCampaign) then
  begin
    DealHand;                       { a hand must exist before anything is drawn }
    FStage.Scalar[ssDim] := 1;      { start from black; the scene fades in }
    EnterCampaign;
  end
  else if not ResumeFreePlayHand then
    DoNewGame;
end;

{ ---- the start menu ---- }

const
  CheatWord = 'coffeeisnotblood';       { typed on the menu (any capitals): +900 coins }
  CheatCoins = 900;

function TGameController.MenuButtonCount: Integer;
begin
  if FCanQuit then Result := 8 else Result := 7;
end;

{ 0 Campaign, 1 Free Play, 2 Save game, 3 Load game (those two share a row),
  4 Rules, 5 Style (those two share a row), then 6 Relics, and Quit (7) beside it
  where the program can quit. Relics are here because the Store is shut in the middle
  of a hand, and a relic should be equipped whenever it is needed. }
function TGameController.MenuButtonCaption(I: Integer): string;
begin
  case I of
    0: Result := 'Campaign';
    1: Result := 'Free Play';
    2: Result := 'Save game';
    3: Result := 'Load game';
    4: Result := 'Rules';
    5: Result := 'Style';
    6: Result := 'Relics';
    7: Result := 'Quit';
  else
    Result := '';
  end;
end;

function TGameController.MenuButtonEnabled(I: Integer): Boolean;
begin
  if I = 2 then Result := FStarted and CanSaveNow else Result := True;
end;

function TGameController.MenuSubtitle: string;
begin
  Result := FStory.CampaignTitle;
end;

function TGameController.MenuVersion: string;
begin
  Result := 'v' + AppVersion;
end;

function TGameController.MenuTitleRect: TRect;
begin
  Result := Rect(0, FVH * 4 div 100, FVW, FVH * 25 div 100);
end;

function TGameController.MenuButtonRect(I: Integer): TRect;
var
  BW, BH, Gap, Top, X, Row, Rows, HalfW: Integer;
begin
  Rows := 5;
  BW := Min(380, FVW * 62 div 100);
  BH := Max(34, Min(56, FVH * 7 div 100));
  Gap := BH div 4;
  Top := FVH * 44 div 100;
  if Top + Rows * BH + (Rows - 1) * Gap > FVH - 10 then
    Top := FVH - 10 - Rows * BH - (Rows - 1) * Gap;
  X := (FVW - BW) div 2;
  HalfW := (BW - Gap) div 2;
  case I of
    0, 1: Row := I;
    2, 3: Row := 2;
    4, 5: Row := 3;
  else
    Row := 4;                                  { Relics, with Quit beside it }
  end;
  if I = 4 then
    Result := Rect(X, Top + Row * (BH + Gap), X + HalfW, Top + Row * (BH + Gap) + BH)
  else if I = 5 then
    Result := Rect(X + BW - HalfW, Top + Row * (BH + Gap), X + BW, Top + Row * (BH + Gap) + BH)
  else if I = 2 then
    Result := Rect(X, Top + Row * (BH + Gap), X + HalfW, Top + Row * (BH + Gap) + BH)
  else if I = 3 then
    Result := Rect(X + BW - HalfW, Top + Row * (BH + Gap), X + BW, Top + Row * (BH + Gap) + BH)
  else if (I = 6) and FCanQuit then
    Result := Rect(X, Top + Row * (BH + Gap), X + HalfW, Top + Row * (BH + Gap) + BH)
  else if I = 7 then
    Result := Rect(X + BW - HalfW, Top + Row * (BH + Gap), X + BW, Top + Row * (BH + Gap) + BH)
  else
    Result := Rect(X, Top + Row * (BH + Gap), X + BW, Top + Row * (BH + Gap) + BH);
end;

procedure TGameController.ActionOpenMenu;
begin
  if FMenuOpen then Exit;
  if Animating and not FInScene then SkipDeal;       { a deal being shown is finished first }
  CloseModes;
  FMenuOpen := True;
  FMenuTyped := '';
  FMenuNote := '';
  Changed;
end;

{ Campaign (I = 0), Free Play (1), Save game (2), Load game (3), Rules (4), Style (5), Relics (6) or Quit (7).
  Choosing the mode already being played just goes back to the table. }
procedure TGameController.MenuChoose(I: Integer);
begin
  case I of
    0, 1:
    begin
      FMenuOpen := False;
      FMenuTyped := '';
      FMenuNote := '';
      if not FStarted then
      begin
        FStarted := True;
        if I = 0 then
        begin
          DealHand;                   { a hand must exist before anything is drawn }
          FStage.Scalar[ssDim] := 1;  { start from black; the scene fades in }
          EnterCampaign;
        end
        else
        begin
          FSettings.Mode := gmFreePlay;
          FSettings.Save;
          if not ResumeFreePlayHand then DoNewGame;
        end;
      end
      else if (I = 0) and not FCampaignMode then
        EnterCampaign
      else if (I = 1) and FCampaignMode then
        ExitCampaign;
      Changed;
    end;
    2: if MenuButtonEnabled(2) then OpenSlots(True);
    3: OpenSlots(False);
    4:
    begin
      FRulesShow := True;               { the front end shows them }
      Changed;
    end;
    5: ActionOpenStyle;
    6: ActionOpenRelics;
    7:
      if FCanQuit and Assigned(FOnQuit) then FOnQuit();
  end;
end;

procedure TGameController.TapMenu(X, Y: Integer);
var
  I: Integer;
begin
  for I := 0 to MenuButtonCount - 1 do
    if PtInRect(MenuButtonRect(I), Point(X, Y)) then
    begin
      if MenuButtonEnabled(I) then MenuChoose(I);
      Exit;
    end;
end;

procedure TGameController.TypeChar(C: Char);
begin
  if not FMenuOpen then Exit;
  FMenuTyped := FMenuTyped + LowerCase(string(C));
  if Length(FMenuTyped) > Length(CheatWord) then
    Delete(FMenuTyped, 1, Length(FMenuTyped) - Length(CheatWord));
  if FMenuTyped = CheatWord then
  begin
    FMenuTyped := '';
    FSession.Inventory.AddCoins(CheatCoins);
    FSession.SaveNow;
    FMenuNote := Format('Cheat mode: %d coins added (you have %d).',
      [CheatCoins, FSession.Inventory.Coins]);
    Changed;
  end;
end;

{ ---- save slots (reached from the start menu) ---- }

{ Is there a hand that can be saved right now? }
function TGameController.CanSaveNow: Boolean;
begin
  if FCampaignMode then
    Result := (FDuel.Duel.State = dsPlaying) and not FInScene and not FGame.IsWon
  else
    Result := not FInScene and not Animating and not FGame.IsWon;
end;

procedure TGameController.OpenSlots(ForSave: Boolean);
begin
  FSlotsSave := ForSave;
  FOverlay := okSlots;
  Changed;
end;

{ Which slot row I is (Camp, N), False for a heading. Saving lists the mode
  being played; loading lists both. }
function TGameController.SlotRowInfo(I: Integer; out Camp: Boolean; out N: Integer): Boolean;
begin
  Result := False;
  Camp := False;
  N := 0;
  if FSlotsSave then
  begin
    Camp := FCampaignMode;
    if I >= 1 then
    begin
      N := I;
      Result := True;
    end;
  end
  else if (I >= 1) and (I <= 3) then
  begin
    N := I;
    Result := True;
  end
  else if I >= 5 then
  begin
    Camp := True;
    N := I - 4;
    Result := True;
  end;
end;

function TGameController.SlotRow(I: Integer): TOverlayRow;
var
  Camp: Boolean;
  N, V: Integer;
  FI: TSlotInfo;
  CI: TCampaignSlotInfo;
  Name: string;
begin
  Result.Title := '';
  Result.Detail := '';
  Result.Aside := '';
  Result.ButtonText := '';
  Result.ButtonEnabled := False;
  Result.Button2Text := '';
  Result.Button2Enabled := False;
  Result.Preview := 0;
  Result.Art := -1;
  Result.Selected := False;
  Result.Header := False;
  if not SlotRowInfo(I, Camp, N) then
  begin
    Result.Header := True;
    if FSlotsSave then
    begin
      if FCampaignMode then Result.Title := 'CAMPAIGN' else Result.Title := 'FREE PLAY';
    end
    else if I = 0 then
      Result.Title := 'FREE PLAY'
    else
      Result.Title := 'CAMPAIGN';
    Exit;
  end;
  Result.Title := Format('Slot %d', [N]);
  if Camp then
  begin
    CI := PeekCampaignSlot(N);
    if CI.Exists then
    begin
      V := CI.Vampire;
      if V < VampireCount then Name := FStory.Name(V) else Name := 'Campaign complete';
      Result.Detail := Format('%s, %d of %d wins   %d cards left   saved %s',
        [Name, CI.Wins, WinsToKill, CI.CardsLeft, CI.Stamp]);
      Result.Button2Text := 'Delete';
      Result.Button2Enabled := True;
    end
    else
      Result.Detail := 'Empty';
    Result.Aside := '';
    if FSlotsSave then
    begin
      if CI.Exists then Result.ButtonText := 'Replace' else Result.ButtonText := 'Save';
      Result.ButtonEnabled := CanSaveNow;
    end
    else
    begin
      Result.ButtonText := 'Load';
      Result.ButtonEnabled := CI.Exists;
    end;
  end
  else
  begin
    FI := PeekHandFile(SlotFile(N));
    if FI.Exists then
    begin
      Result.Detail := Format('%d cards left   saved %s', [FI.CardsLeft, FI.Stamp]);
      Result.Button2Text := 'Delete';
      Result.Button2Enabled := True;
    end
    else
      Result.Detail := 'Empty';
    if FSlotsSave then
    begin
      if FI.Exists then Result.ButtonText := 'Replace' else Result.ButtonText := 'Save';
      Result.ButtonEnabled := CanSaveNow;
    end
    else
    begin
      Result.ButtonText := 'Load';
      Result.ButtonEnabled := FI.Exists;
    end;
  end;
end;

procedure TGameController.SlotAction(I: Integer);
var
  Camp: Boolean;
  N: Integer;
begin
  if not SlotRowInfo(I, Camp, N) then Exit;
  if FSlotsSave then
  begin
    if not CanSaveNow then Exit;
    if Camp then SaveCampaignSlot(N) else SaveFreeSlot(N);
  end
  else if Camp then
    LoadCampaignSlot(N)
  else
    LoadFreeSlot(N);
end;

procedure TGameController.SaveFreeSlot(N: Integer);
var
  H: TSavedHand;
begin
  FSession.ExportHand(H);
  if WriteHandFile(SlotFile(N), H) then
    FToast := Format('Free Play hand saved to slot %d.', [N])
  else
    FToast := 'Sorry, that save could not be written.';
  Changed;
end;

procedure TGameController.SaveCampaignSlot(N: Integer);
var
  H: TSavedHand;
begin
  FSession.ExportHand(H);
  if WriteCampaignSlot(N, FCampaign.ExportText, FSession.Inventory.ExportText, H) then
    FToast := Format('Campaign saved to slot %d.', [N])
  else
    FToast := 'Sorry, that save could not be written.';
  Changed;
end;

{ Is H a believable hand? (Checked on a scratch game, so nothing changes if not.) }
function HandIsBelievable(const H: TSavedHand): Boolean;
var
  G: TPyramidGame;
begin
  G := TPyramidGame.Create;
  try
    Result := (H.Misses >= 0) and G.SetState(H.Game);
  finally
    G.Free;
  end;
end;

{ Back at the table in whichever mode a loaded slot belongs to. }
procedure TGameController.LoadFreeSlot(N: Integer);
var
  H: TSavedHand;
begin
  if not (ReadHandFile(SlotFile(N), H) and HandIsBelievable(H)) then
  begin
    FToast := Format('Slot %d could not be read, so nothing changed.', [N]);
    Changed;
    Exit;
  end;
  if FStarted and not FCampaignMode and FSession.HandStarted and not FGame.IsWon then
    FRecords.FreePlayAbandoned;
  if FCampaignMode then
  begin
    FDuel.Deactivate;                    { out of the duel: its autosave stays as it was }
    FCampaignMode := False;
  end;
  FSettings.Mode := gmFreePlay;
  FSettings.Save;
  FSession.ImportHand(H);
  CloseModes;
  FInScene := False;
  StopSeq;
  DropFx;
  FStage.ResetScene;
  FStage.Settle;
  FStarted := True;
  FMenuOpen := False;
  FMenuTyped := '';
  FMenuNote := '';
  AutoSave;
  FToast := Format('Loaded Free Play slot %d.', [N]);
  Changed;
end;

procedure TGameController.LoadCampaignSlot(N: Integer);
var
  S: TCampaignSlot;
begin
  if not (ReadCampaignSlot(N, S) and HandIsBelievable(S.Hand)) then
  begin
    FToast := Format('Campaign slot %d could not be read, so nothing changed.', [N]);
    Changed;
    Exit;
  end;
  if FStarted and not FCampaignMode and FSession.HandStarted and not FGame.IsWon then
    FRecords.FreePlayAbandoned;
  FCampaign.ImportText(S.CampaignText);                { progress, coins and cards: a true rewind }
  FCampaign.Save;
  FSession.Inventory.ImportText(S.InventoryText);
  FSession.SaveNow;
  if FCampaignMode then FDuel.Duel.Start else FDuel.Activate;
  FDuel.ResumeHand(S.Hand);
  FCampaignMode := True;
  FSettings.Mode := gmCampaign;
  FSettings.Save;
  CloseModes;
  FInScene := False;
  StopSeq;
  DropFx;
  FStage.ResetScene;
  FStage.Settle;
  FStarted := True;
  FMenuOpen := False;
  FMenuTyped := '';
  FMenuNote := '';
  AutoSave;
  FToast := Format('Loaded campaign slot %d.', [N]);
  Changed;
end;

{ ---- layout ---- }

procedure TGameController.SetViewport(W, H: Integer);
begin
  FVW := W;
  FVH := H;
  UpdateScale;
end;

function TGameController.PanelPlacement: TPanelPlacement;
begin
  Result := ppNone;
  if FAllowBottomPanel and (FVH * 10 > FVW * 11) then
    Result := ppBottom                         { taller than wide }
  else if FVW >= PanelMinWindow then
    Result := ppLeft;
end;

{ Height of the strip under the table (0 unless the panel goes there). }
function TGameController.TableAreaHeight: Integer;
var
  PH: Integer;
begin
  Result := FVH;
  if PanelPlacement = ppBottom then
  begin
    PH := FVH * 32 div 100;
    if PH < 170 then PH := 170;
    Result := FVH - PH - PanelGap;
  end;
end;

procedure TGameController.UpdateScale;
var
  SX, SY: Double;
  Reserve, AW, AH: Integer;
begin
  Reserve := 0;
  if PanelPlacement = ppLeft then
  begin
    Reserve := FVW * 20 div 100;
    if Reserve < 170 then Reserve := 170;
    if Reserve > 300 then Reserve := 300;
    Reserve := PanelMargin + Reserve + PanelGap;
  end;
  AW := FVW - Reserve;
  AH := TableAreaHeight;
  SX := AW / DesignW;
  SY := AH / DesignH;
  if SX < SY then FScale := SX else FScale := SY;
  if FScale < 0.2 then FScale := 0.2;
  FOffX := Reserve + (AW - Round(DesignW * FScale)) div 2;
  FOffY := (AH - Round(DesignH * FScale)) div 2;
end;

function TGameController.PanelRect: TRect;
var
  Reserve, PW, PH: Integer;
begin
  case PanelPlacement of
    ppLeft:
    begin
      PW := FVW * 20 div 100;
      if PW < 170 then PW := 170;
      if PW > 300 then PW := 300;
      Reserve := PanelMargin + PW + PanelGap;
      Result := Rect(PanelMargin, PanelMargin, Reserve - PanelGap, FVH - PanelMargin);
    end;
    ppBottom:
    begin
      PH := FVH - TableAreaHeight - PanelGap;
      Result := Rect(PanelMargin div 2, FVH - PH - PanelMargin div 2,
        FVW - PanelMargin div 2, FVH - PanelMargin div 2);
    end;
  else
    Result := Rect(0, 0, 0, 0);
  end;
end;

function TGameController.Sc(V: Integer): Integer;
begin
  Result := Round(V * FScale);
end;

function TGameController.Scaled(V: Integer): Integer;
begin
  Result := Sc(V);
end;

{ Half-steps from the left edge of the bottom row: the apex sits in the middle (step 6). }
function HalfX(I: Integer): Integer;
begin
  Result := (RowCount - 1 - RowOf(I)) + 2 * ColOf(I);
end;

function TGameController.CardRect(I: Integer): TRect;
begin
  Result.Left := FOffX + Sc(MarginX + HalfX(I) * HalfStep);
  Result.Top := FOffY + Sc(MarginY + RowOf(I) * RowStep);
  Result.Right := Result.Left + Sc(CardW);
  Result.Bottom := Result.Top + Sc(CardH);
end;

function TGameController.StockRect: TRect;
begin
  Result.Left := FOffX + Sc(MarginX);
  Result.Top := FOffY + Sc(MarginY + 6 * RowStep + CardH + 40);
  Result.Right := Result.Left + Sc(CardW);
  Result.Bottom := Result.Top + Sc(CardH);
end;

function TGameController.WasteRect: TRect;
begin
  Result := StockRect;
  OffsetRect(Result, Sc(CardW + 24), 0);
end;

{ ---- what to draw ---- }

function TGameController.Animating: Boolean;
begin
  Result := (FSeq <> nil) and FSeq.Running;
end;

function TGameController.TableMode: TTableMode;
begin
  if Animating and not FInScene then
    Result := tmDealing
  else if FGame.IsWon and not FCampaignMode then
    Result := tmWon
  else
    Result := tmNormal;
end;

function TGameController.WinMessage: string;
begin
  if FStage.Backdrop = sbWinPicture then
    Result := 'Click anywhere to return to Free Play'
  else
    Result := 'Click anywhere, or press New Game, to play again';
end;

function TGameController.PanelStats: TPanelStats;
var
  I: Integer;
begin
  Result.Remaining := FGame.CardsLeft;
  Result.Stock := FGame.StockCount;
  Result.Recycles := FGame.RecyclesLeft;
  Result.Streak := FGame.Streak;
  Result.BestStreak := FGame.BestStreak;
  Result.Coins := FSession.Inventory.Coins;
  Result.FreePlay := not FCampaignMode;
  Result.PerWin := WinCoins;
  Result.Misses := FSession.Misses;
  Result.PayNow := FSession.PayoutNow;
  Result.MissCut := WinCoins - Result.PayNow;
  Result.Trophies := 0;
  for I := 0 to TrophyCount - 1 do
    if FTrophies.Has(TTrophy(I)) then Result.Trophies := Result.Trophies or (1 shl I);
  Result.TrophyCount := FTrophies.Count;
end;

function TGameController.DuelInfo: TDuelInfo;
begin
  Result := GetDuelInfo(FDuel, FStory);
  if not FCampaignMode then Result.Active := False;    { Free Play: no duel to show }
end;

function TGameController.SlotInfo(N: Integer): TSlotInfo;
begin
  Result := PeekHandFile(SlotFile(N));
end;

{ Cards and buttons only work during a hand (not during a scene or animation). }
function TGameController.HandIsLive: Boolean;
begin
  Result := not Animating and (not FCampaignMode or (FDuel.Duel.State = dsPlaying));
end;

function TGameController.ShopOpen: Boolean;
begin
  { cards are only sold between hands (see TGameSession.CanShop) }
  Result := not Animating and FSession.CanShop;
end;

function TGameController.GetUi: TUiState;
var
  S, Stats: string;
  Inv: TPlayerInventory;
  V: Integer;
begin
  Inv := FSession.Inventory;
  { the numbers live in the side panel; with no room for it the status line
    carries them }
  Stats := Format('Left: %d   Stock: %d   Streak: %d (best %d)   Coins: %d',
    [FGame.CardsLeft, FGame.StockCount, FGame.Streak, FGame.BestStreak,
     Inv.Coins]);
  if not FCampaignMode and not FGame.IsWon then
    Stats := Stats + Format('   This hand pays: %d', [FSession.PayoutNow]);
  if PanelPlacement = ppNone then S := Stats else S := '';
  if FCampaignMode then
  begin
    V := FDuel.Duel.Vampire;
    if FDuel.Duel.State = dsComplete then
      S := 'Campaign complete.   ' + S
    else if (V < VampireCount) and (PanelPlacement = ppNone) then
    begin
      { with no room for the panel, the status line carries the duel details }
      S := Format('Duel: %s -- wins %d of %d, this win pays %d coins   ',
        [FStory.Name(V), FDuel.Duel.Wins, WinsToKill, FDuel.PayoutNow]) + S;
      if FDuel.StuckWaiting then
        S := 'No moves left -- use an undo or special card, or press New Game to concede.   ' + S;
    end;
  end
  else if FSession.Note <> '' then
    S := FSession.Note + '   ' + S
  else if FGame.IsStuck then
    S := 'No moves left.   ' + S;
  if FCampaignMode and (FSession.Note <> '') and (FDuel.Duel.State = dsPlaying) then
    S := FSession.Note + '   ' + S;          { a bite, or the Count feeding }
  if FTargeting then
    if (FTargetKind = skWild) and (FTargetA = PosNone) then
      S := SpecialName[FTargetKind] + ': tap two cards in play, and they go as a pair (any other tap cancels).   ' + S
    else if FTargetKind = skWild then
      S := SpecialName[FTargetKind] + ': now tap the second card.   ' + S
    else
      S := SpecialName[FTargetKind] + ': tap a free card (any other tap cancels).   ' + S;
  if FToast <> '' then S := FToast + '   ' + S;
  if FNews <> '' then S := FNews + '   ' + S;
  S := Trim(S);
  Result.StatusText := S;
  Result.UndoCaption := Format('Undo (%d)', [Inv.UndoCards]);
  Result.UndoEnabled := FSession.CanUseUndo and HandIsLive;
  Result.HintCaption := Format('Show move (%d)', [Inv.HintCards]);
  if FSession.FreeHintAvailable then Result.HintCaption := 'Show move (free)';      { the Moonstone }
  Result.HintEnabled := ((Inv.HintCards > 0) or FSession.FreeHintAvailable) and HandIsLive;
  if FSettings.FreeEasy then Result.EasyCaption := 'Mode: Easy' else Result.EasyCaption := 'Mode: Normal';
  if FCampaignMode then Result.EasyCaption := 'Mode: Duel';          { each vampire sets his own rules }
  Result.EasyEnabled := not FCampaignMode and not FMenuOpen and not Animating;
  Result.MenuCaption := 'Menu';
  Result.StoreCaption := 'Store';
  Result.CardsCaption := Format('My cards (%d)', [Inv.TotalSpecialCards]);
  Result.CardsEnabled := not (Animating and FInScene);
  Result.Targeting := FTargeting;
  Result.CancelCaption := 'Cancel';
  Result.RecordsCaption := 'Records';
  Result.RecordsEnabled := not (Animating and FInScene);
  Result.AskInitials := NeedInitials;
  Result.InitialsPrompt := PendingText;
  Result.InitialsDefault := FRecords.LastInitials;
  Result.ShowRules := FRulesShow;
  Result.AskDelete := FDeleteAsk >= 0;
  Result.DeletePrompt := DeleteText;
  Result.AskCross := FCrossAsk >= 0;
  Result.CrossPrompt := 'One of these cards carries the silver cross. Taking it away as an ordinary move destroys the cross: only a Wild card can claim it. Take them away anyway?';
  Result.SaveEnabled := not FCampaignMode and not Animating and not FGame.IsWon;
  Result.LoadEnabled := not FCampaignMode and not Animating;
  Result.ShopOpen := ShopOpen;
  Result.StoreEnabled := FSession.CanShop and not (Animating and FInScene);
  if Result.ShopOpen then
    Result.ShopClosedReason := ''
  else
  begin
    Result.ShopClosedReason := FStory.FenwickClosed;
    if Result.ShopClosedReason = '' then
      Result.ShopClosedReason := 'The Store is only open after a hand, or before your first move.';
  end;
  Result.CanSkip := Animating;
  Result.InScene := FInScene and Animating;
  if FMenuOpen then                            { the menu is on top of everything }
  begin
    Result.StatusText := Format('Coins: %d', [Inv.Coins]);
    if FMenuNote <> '' then Result.StatusText := FMenuNote + '   ' + Result.StatusText;
    if FToast <> '' then Result.StatusText := FToast + '   ' + Result.StatusText;
    Result.UndoEnabled := False;
    Result.HintEnabled := False;
    Result.SaveEnabled := False;
    Result.LoadEnabled := False;
    Result.StoreEnabled := False;
    Result.CardsEnabled := False;
    Result.RecordsEnabled := False;
    Result.CanSkip := False;
    Result.InScene := False;
    Result.Targeting := False;
    Result.AskInitials := False;
    Result.AskCross := False;
  end;
end;

{ ---- time ---- }

function TGameController.NeedsTicks: Boolean;
begin
  Result := (Animating or (FFx <> nil)) and not FMenuOpen;
end;

procedure TGameController.Tick(DeltaMs: Integer);
begin
  if DeltaMs > 100 then DeltaMs := 100;        { after a stall, do not jump ahead }
  if DeltaMs < 0 then DeltaMs := 0;
  if FMenuOpen then Exit;                      { everything waits behind the menu }
  if FFx <> nil then
  begin
    FFx.Advance(DeltaMs);
    if not FFx.Running then FreeAndNil(FFx);
  end;
  if Animating then
  begin
    FSeq.Advance(DeltaMs);
    if not FSeq.Running then SequenceFinished;   { may start another sequence }
  end;
  Changed;
end;

{ ---- sounds ---- }

procedure TGameController.HookToll;
begin
  PlayToll;
end;

procedure TGameController.HookNo;
begin
  PlayNo;
end;

procedure TGameController.HookBlow;
begin
  PlayBlow;
end;

procedure TGameController.HookFanfare;
begin
  PlayWin;
end;

procedure TGameController.PlayDealSound;
begin
  if FDealWav = '' then FDealWav := MakeTicksWav(NewGameTickTimes);
  PlayWav('deal.wav', FDealWav);
end;

{ ---- animations and effects ---- }

procedure TGameController.StopSeq;
begin
  FreeAndNil(FSeq);
end;

{ Deals a hand into the session (no show). }
{ Free Play: the rules for the next hand are the player's choice. }
procedure TGameController.ApplyFreeRules;
begin
  FSession.SetRules(FSettings.FreeEasy, DefaultRecycles, hzNone);
end;

function TGameController.FreeEasy: Boolean;
begin
  Result := FSettings.FreeEasy;
end;

{ Normal or Easy: a different mode deals a new hand, since the rules of a hand do not change half way. }
procedure TGameController.ActionToggleEasy;
begin
  if FMenuOpen or FCampaignMode or Animating then Exit;
  CloseModes;
  FSettings.FreeEasy := not FSettings.FreeEasy;
  FSettings.Save;
  DoNewGame;
  if FSettings.FreeEasy then
    FToast := 'Easy mode: a card can go with the one card sitting on top of it. A new hand is dealt.'
  else
    FToast := 'Normal mode: cards must be uncovered first. A new hand is dealt.';
  Changed;
end;

procedure TGameController.DealHand;
var
  D: TDeck;
begin
  if not FCampaignMode then ApplyFreeRules;
  if Assigned(FDeckProvider) then
  begin
    D := FDeckProvider();
    if D <> nil then
    begin
      FSession.NewGameFrom(D);
      D.Free;
      Exit;
    end;
  end;
  FSession.NewGame;
end;

procedure TGameController.DoNewGame;
begin
  { dropping a hand that was under way (and not won) ends a run of wins }
  if not FCampaignMode and FSession.HandStarted and not FGame.IsWon then
    FRecords.FreePlayAbandoned;
  DealHand;
  StartNewGameAnim;           { the hand is already dealt; this is only the show }
  Changed;
end;

procedure TGameController.StartNewGameAnim;
begin
  CloseModes;
  UpdateScale;
  DropFx;
  StopSeq;
  FInScene := False;
  { if a scene just ended, the table fades in from black as the cards deal }
  FSeq := BuildNewGameSequence(FStage, @PlayDealSound, 450);
  FSeq.Advance(0);                { runs the start action (the sound) right away }
  AutoSave;                       { the new hand is saved straight away }
end;

procedure TGameController.RunFx(Seq: TAnimSequence);
begin
  FreeAndNil(FFx);
  FFx := Seq;
  FFx.Advance(0);
end;

{ A missed move: a red flash and a sting, over the table, without blocking play. }
procedure TGameController.StartMissFx;
var
  Seq: TAnimSequence;
begin
  PlaySting;
  Seq := TAnimSequence.Create;
  Seq.Add(TTweenStep.Create(FStage, ssFlashRed, 0.45, 0, 450, @EaseOutCubic));
  RunFx(Seq);
  FToast := 'You missed a move!';
end;

{ Fade up from black (a hand was just put back). }
procedure TGameController.StartFadeIn(Ms: Integer);
var
  Seq: TAnimSequence;
begin
  Seq := TAnimSequence.Create;
  Seq.Add(TTweenStep.Create(FStage, ssDim, FStage.Scalar[ssDim], 0, Ms, @EaseLinear));
  RunFx(Seq);
end;

procedure TGameController.DropFx;
begin
  FreeAndNil(FFx);
  FStage.Scalar[ssFlashRed] := 0;
  FToast := '';
end;

procedure TGameController.SkipDeal;
begin
  if FSeq <> nil then FSeq.Skip;
  Changed;
end;

procedure TGameController.SkipScene;
begin
  FSeq.Skip;
  SequenceFinished;
end;

{ A sequence has run to its end. }
procedure TGameController.SequenceFinished;
begin
  if FInScene then SceneFinished;
  Changed;
end;

{ ---- saving and resuming ---- }

{ Saves the hand in progress (or removes the save when the hand is over), so
  closing the game at any moment loses nothing. Each mode has its own file. }
procedure TGameController.AutoSave;
var
  H: TSavedHand;
  F: string;
begin
  if FCampaignMode then
  begin
    F := AutoSaveFile(gmCampaign);
    if FDuel.Duel.State = dsPlaying then
    begin
      FSession.ExportHand(H);
      WriteHandFile(F, H);
    end
    else
      DeleteHandFile(F);              { the hand is over: kill or lost }
  end
  else
  begin
    F := AutoSaveFile(gmFreePlay);
    if FGame.IsWon then
      DeleteHandFile(F)
    else
    begin
      FSession.ExportHand(H);
      WriteHandFile(F, H);
    end;
  end;
end;

{ Puts back the Free Play hand that was saved, if there is a usable one. }
function TGameController.ResumeFreePlayHand: Boolean;
var
  H: TSavedHand;
begin
  Result := ReadHandFile(AutoSaveFile(gmFreePlay), H) and FSession.ImportHand(H);
  if not Result then Exit;
  FStage.ResetScene;
  FStage.Settle;
  FToast := 'Welcome back: your hand was restored.';
  Changed;
end;

{ Puts back a saved duel hand, straight into play (the intro was already seen). }
function TGameController.ResumeCampaignHand: Boolean;
var
  H: TSavedHand;
begin
  Result := (FDuel.Duel.State = dsIntro)
    and ReadHandFile(AutoSaveFile(gmCampaign), H) and FDuel.ResumeHand(H);
  if not Result then Exit;
  UpdateScale;
  FStage.Settle;
  FStage.Scalar[ssDim] := 1;            { cut to black, then fade the hand in }
  StartFadeIn(450);
  FToast := 'Welcome back: your duel hand was restored.';
  Changed;
end;

procedure TGameController.ActionSaveSlot(N: Integer);
var
  H: TSavedHand;
begin
  if FMenuOpen then Exit;
  CloseModes;
  if FCampaignMode or Animating or FGame.IsWon then Exit;
  FSession.ExportHand(H);
  if WriteHandFile(SlotFile(N), H) then
    FToast := Format('Hand saved to slot %d.', [N])
  else
    FToast := 'Sorry, that save could not be written.';
  Changed;
end;

procedure TGameController.ActionLoadSlot(N: Integer);
var
  H: TSavedHand;
begin
  if FMenuOpen then Exit;
  CloseModes;
  if FCampaignMode or Animating then Exit;
  if FSession.HandStarted and not FGame.IsWon then FRecords.FreePlayAbandoned;
  if ReadHandFile(SlotFile(N), H) and FSession.ImportHand(H) then
  begin
    FStage.ResetScene;
    FStage.Settle;
    AutoSave;
    FToast := Format('Loaded slot %d.', [N]);
  end
  else
    FToast := Format('Slot %d could not be read, so nothing changed.', [N]);
  Changed;
end;

{ A brand-new player: back to Free Play with a fresh hand. }
procedure TGameController.ActionEraseEverything;
begin
  if FMenuOpen then Exit;
  CloseModes;
  FVisits := 0;
  FSales := 0;
  FRefusals := 0;
  FDuel.Deactivate;
  FCampaignMode := False;
  UpdateScale;
  FInScene := False;
  StopSeq;
  DropFx;
  FStage.ResetScene;
  FPending := [];
  EraseEverything(FSession, FCampaign, FSettings, FRecords, FTrophies, ExtractFilePath(DefaultInventoryFile));
  FNews := '';
  FDuel.Duel.Start;                      { the campaign is at the first vampire again }
  DoNewGame;
  FToast := 'Everything was erased: a fresh start.';
  Changed;
end;

{ The story begins again; coins, cards and Free Play hands are kept. }
procedure TGameController.ActionRestartCampaign;
begin
  if FMenuOpen then Exit;
  RestartCampaignOnly(FCampaign, ExtractFilePath(DefaultInventoryFile));
  FDuel.Duel.Start;
  if FCampaignMode then
    StartScene                           { the opening, then Lucien Vale }
  else
  begin
    FToast := 'The campaign was reset. Press Campaign to begin again from the start.';
    Changed;
  end;
end;

{ ---- the campaign ---- }

procedure TGameController.EnterCampaign;
begin
  CloseModes;
  FCampaignMode := True;
  if FCampaign.IsComplete then FDuel.Restart;     { a finished campaign starts over }
  FDuel.Activate;
  FSettings.Mode := gmCampaign;                   { remembered for next time }
  FSettings.Save;
  if not ResumeCampaignHand then
    StartScene;                                   { otherwise: the intro, then a new hand }
end;

procedure TGameController.ExitCampaign;
begin
  CloseModes;
  FDuel.Deactivate;
  FCampaignMode := False;
  UpdateScale;
  FSettings.Mode := gmFreePlay;
  FSettings.Save;
  FInScene := False;
  StopSeq;
  FStage.ResetScene;
  if not ResumeFreePlayHand then
    DoNewGame;
end;

procedure TGameController.ActionToggleMode;
begin
  if FMenuOpen then Exit;
  if FCampaignMode then ExitCampaign else EnterCampaign;
end;

{ Plays the scene for the duel's current state (nothing while a hand is on). }
procedure TGameController.StartScene;
var
  Seq: TAnimSequence;
  WithPremise: Boolean;
begin
  CloseModes;
  { a vampire already being fought (some wins or lost hands, saved earlier) is
    not introduced again: straight to the next hand }
  if (FDuel.Duel.State = dsIntro) and FDuel.Duel.InProgress then
  begin
    DropFx;
    StopSeq;
    FStage.Scalar[ssDim] := 1;
    FInScene := True;
    SceneFinished;
    Exit;
  end;
  WithPremise := (FDuel.Duel.State = dsIntro) and (FCampaign.Current = 0)
    and (FCampaign.LostHands = 0) and not FCampaign.PremiseSeen;
  Seq := BuildSceneForState(FStage, FStory, FDuel.Duel, WithPremise, FHooks);
  if Seq = nil then Exit;
  if WithPremise then FCampaign.MarkPremiseSeen;
  DropFx;
  StopSeq;
  FSeq := Seq;
  FInScene := True;
  FSeq.Advance(0);
  Changed;
end;

{ A duel scene has ended: tell the duel, then show what comes next. }
procedure TGameController.SceneFinished;
begin
  FInScene := False;
  if not FCampaignMode then Exit;
  if FDuel.Duel.State = dsComplete then        { the finale stays up until a click }
  begin
    Changed;
    Exit;
  end;
  if FDuel.SceneDone then
  begin
    if FDuel.Duel.State = dsPlaying then
      StartNewGameAnim                         { the next hand has been dealt }
    else
      StartScene;
  end;
  Changed;
end;

{ After a move or a concession: if the hand is over, play its scene. }
procedure TGameController.ResolveDuel;
begin
  if FCampaignMode and (FDuel.Duel.State <> dsPlaying) and not FInScene then
    StartScene;
  AutoSave;
  Changed;
end;

{ ---- what the player does ---- }

procedure TGameController.SetToast(const Msg: string);
begin
  FToast := Msg;
  Changed;
end;

procedure TGameController.KeyPress(IsEscape: Boolean);
begin
  if FRulesShow or (FDeleteAsk >= 0) then Exit;
  if FMenuOpen and (FOverlay in [okSlots, okStyle, okRelics]) then
  begin
    if IsEscape then ActionCloseOverlay;     { back to the menu }
    Exit;
  end;
  if FMenuOpen then
  begin
    if IsEscape and FStarted then          { back to the table }
    begin
      FMenuOpen := False;
      FMenuTyped := '';
      FMenuNote := '';
      Changed;
    end;
    Exit;
  end;
  if FOverlay <> okNone then
  begin
    if IsEscape then ActionCloseOverlay
    else if IntroActive then AdvanceIntro;
    Exit;
  end;
  if FTargeting then
  begin
    if IsEscape then ActionCancel;
    Exit;
  end;
  if not Animating then Exit;
  if FInScene then
  begin
    if IsEscape then SkipScene             { Esc: skip the whole scene }
    else
    begin
      FSeq.SkipToMark;                     { any other key: the next line }
      if FSeq.Running then Changed else SequenceFinished;
    end;
  end
  else
    SkipDeal;                              { any key skips the deal }
end;

procedure TGameController.SkipPressed;
begin
  if FMenuOpen or not Animating then Exit;
  if FInScene then SkipScene else SkipDeal;
end;

procedure TGameController.Tap(X, Y: Integer);
var
  I: Integer;
  P: TPoint;
begin
  if (FCrossAsk >= 0) or (FDeleteAsk >= 0) or FRulesShow then Exit;   { a question or the rules have to be dealt with first }
  if FOverlay <> okNone then                 { the slot screen sits over the menu too }
  begin
    TapOverlay(X, Y);
    Exit;
  end;
  if FMenuOpen then
  begin
    TapMenu(X, Y);
    Exit;
  end;
  if Animating then
  begin
    if FInScene then
    begin
      FSeq.SkipToMark;          { a click on a scene: the next line }
      if FSeq.Running then Changed else SequenceFinished;
    end
    else
      SkipDeal;                 { a click skips the deal }
    Exit;
  end;
  { the trophy shelf in the side panel opens the trophy page (also on the win screen) }
  if (PanelPlacement <> ppNone) and not FTargeting
    and PtInRect(TrophyLayout.Shelf, Point(X, Y)) then
  begin
    ActionOpenTrophies;
    Exit;
  end;
  if FCampaignMode then
  begin
    if FDuel.Duel.State = dsComplete then
    begin
      ExitCampaign;             { the victory picture: click to go back to Free Play }
      Exit;
    end;
    if FDuel.Duel.State <> dsPlaying then Exit;
  end
  else if FGame.IsWon then
  begin
    DoNewGame;                  { the win screen: click anywhere to play again }
    Exit;
  end;
  if FTargeting then
  begin
    TapTarget(X, Y);
    Exit;
  end;
  FToast := '';
  FNews := '';
  TapTable(X, Y);
end;

{ ---- the table: tap a card, then its partner ---- }

{ The pyramid card under the point, front-most first (-1 = none). }
function TGameController.HitPyramid(X, Y: Integer): Integer;
var
  I: Integer;
  P: TPoint;
begin
  Result := -1;
  P := Point(X, Y);
  for I := PyramidSize - 1 downto 0 do
    if not FGame.Removed(I) and PtInRect(CardRect(I), P) then Exit(I);
end;

procedure TGameController.TapTable(X, Y: Integer);
var
  P: TPoint;
  I: Integer;
  C: TCard;
begin
  P := Point(X, Y);
  if PtInRect(StockRect, P) then
  begin
    FPick := PosNone;
    TapStock;
    Exit;
  end;
  if PtInRect(WasteRect, P) and FGame.WasteTop(C) then
  begin
    PickCard(PosWaste);
    Exit;
  end;
  I := HitPyramid(X, Y);
  if I >= 0 then
  begin
    PickCard(I);
    Exit;
  end;
  if FPick <> PosNone then               { a tap on bare table lets go of the selection }
  begin
    FPick := PosNone;
    Changed;
  end;
end;

{ What a move on the table needs doing afterwards. }
procedure TGameController.AfterTableMove;
begin
  FPick := PosNone;
  if FCampaignMode then
  begin
    ResolveDuel;                { the hand may be over: kill, or stuck }
    Exit;
  end;
  if FGame.IsWon then PlayWin;
  AutoSave;
  Changed;
end;

procedure TGameController.TapStock;
var
  Moved: Boolean;
begin
  if FGame.CanDraw then
  begin
    if FCampaignMode then Moved := FDuel.DrawStock else Moved := FSession.DrawStock;
    if Moved and FSession.MissedLast then StartMissFx;
  end
  else if FGame.CanRecycle then
  begin
    if FCampaignMode then Moved := FDuel.Recycle else Moved := FSession.Recycle;
  end
  else
  begin
    FToast := 'The stock is empty and cannot be turned over again.';
    Changed;
    Exit;
  end;
  AfterTableMove;
end;

{ A pair (or a King, B = PosNone) is complete: take it away, asking first if it takes the silver cross. }
procedure TGameController.TryRemove(A, B: Integer);
begin
  if FCampaignMode and ((FGame.Mark(A) = MarkCross) or (FGame.Mark(B) = MarkCross)) then
  begin
    FCrossAsk := 0;                      { ask first: taking it as an ordinary move destroys the cross }
    FCrossA := A;
    FCrossB := B;
    FPick := PosNone;
    Changed;
    Exit;
  end;
  if FCampaignMode then FDuel.Remove(A, B) else FSession.Remove(A, B);
  AfterTableMove;
end;

{ A card in play (or an "under" card) was tapped. }
procedure TGameController.PickCard(APos: Integer);
var
  C, S: TCard;
begin
  if not FGame.CanSelect(APos) then
  begin
    if FGame.IsLocked(APos) then
      FToast := 'That card is chained: clear the cards beside it in its row, or use a Wood Stake or a Wild card.'
    else
      FToast := 'That card is covered. Take away the cards on top of it first.';
    Changed;
    Exit;
  end;
  C := FGame.CardIn(APos);
  if C.Rank = KingRank then
  begin
    TryRemove(APos, PosNone);            { a King goes on one tap }
    Exit;
  end;
  if FPick = PosNone then
    FPick := APos
  else if FPick = APos then
    FPick := PosNone
  else if FGame.CanRemove(FPick, APos) then
  begin
    TryRemove(FPick, APos);
    Exit;
  end
  else
  begin
    S := FGame.CardIn(FPick);
    if S.Rank + C.Rank <> PairTotal then
      FToast := Format('%s and %s make %d, not 13.', [CardName(S), CardName(C), S.Rank + C.Rank])
    else if FGame.IsLocked(FPick) or FGame.IsLocked(APos) then
      FToast := 'A chained card has to wait until the cards beside it are gone.'
    else
      FToast := 'A covered card can only go with the card sitting on top of it (in Easy mode).';
    FPick := APos;
  end;
  Changed;
end;

procedure TGameController.ActionNew;
begin
  if FMenuOpen then Exit;
  CloseModes;
  if FCampaignMode then
  begin
    { in a duel, New Game means giving up this hand }
    if FDuel.Concede then ResolveDuel;
    Exit;
  end;
  DoNewGame;
end;

procedure TGameController.ActionUndo;
begin
  if FMenuOpen then Exit;
  CloseModes;
  if FCampaignMode then FDuel.UseUndo else FSession.UseUndo;
  FToast := '';
  AutoSave;
  Changed;
end;

procedure TGameController.ActionHint;
var
  R: THintResult;
begin
  if FMenuOpen then Exit;
  CloseModes;
  if FCampaignMode then R := FDuel.UseHint else R := FSession.UseHint;
  if R = hrNoMoves then PlayNo;   { nothing to show; the hint card is still spent }
  Changed;
end;

procedure TGameController.ActionBuyUndo;
begin
  if FMenuOpen then Exit;
  SyncPrices;
  FSession.BuyUndoPack;
  Changed;
end;

procedure TGameController.ActionBuyHint;
begin
  if FMenuOpen then Exit;
  SyncPrices;
  FSession.BuyHintPack;
  Changed;
end;


{ ---- the Store, the card tray and special cards ---- }

procedure TGameController.CloseModes;
begin
  FOverlay := okNone;
  FTargeting := False;
  FTargetA := PosNone;
  FSelected := -1;
  FCrossAsk := -1;
  FDeleteAsk := -1;
end;

function TGameController.IntroActive: Boolean;
begin
  Result := (FOverlay = okStore) and (FIntroAt < Length(FIntro));
end;

function TGameController.GoodArt(I: Integer): Integer;
begin
  Result := I;
end;

function TGameController.Overlay: TOverlayKind;
begin
  Result := FOverlay;
end;

function TGameController.ShopkeeperName: string;
begin
  Result := FStory.FenwickName;
end;

function TGameController.ShopkeeperTitle: string;
begin
  Result := FStory.FenwickTitle;
end;


{ The Store is cheaper at the first vampires (see VampirePricePercent); Free
  Play, and a won campaign, pay the list price. }
procedure TGameController.SyncPrices;
begin
  if FCampaignMode and not FCampaign.IsComplete then
    FSession.Inventory.PricePercent := VampirePricePercent[FCampaign.Current]
  else
    FSession.Inventory.PricePercent := 100;
end;

{ Fenwick only stocks a card once it can be of use: the Easy rule once the player
  has met a vampire without it, the Extra turn once one allows fewer turn-overs.
  Reached once, it stays on the shelf for good. }
function TGameController.Stocked(I: Integer): Boolean;
begin
  Result := True;
  if I = Ord(skEasyRule) then
  begin
    if not FSettings.EasyUnlocked and (FCampaign.Current >= FirstNormalVampire) then
    begin
      FSettings.EasyUnlocked := True;
      FSettings.Save;
    end;
    Result := FSettings.EasyUnlocked;
  end
  else if I = Ord(skExtraTurn) then
  begin
    if not FSettings.TurnsUnlocked and (FCampaign.Current >= FirstFewerTurnsVampire) then
    begin
      FSettings.TurnsUnlocked := True;
      FSettings.Save;
    end;
    Result := FSettings.TurnsUnlocked;
  end;
end;

procedure TGameController.ActionOpenStore;
begin
  if FMenuOpen then Exit;
  if Animating and FInScene then Exit;       { not in the middle of a story scene }
  if Animating then SkipDeal;                { a fresh deal is still being shown: finish it }
  if not ShopOpen then
  begin
    SetToast(GetUi.ShopClosedReason);
    Exit;
  end;
  CloseModes;
  FOverlay := okStore;
  Inc(FVisits);
  FIntro := nil;
  FIntroAt := 0;
  if not FSettings.FenwickMet then FIntro := FStory.FenwickIntro;
  if IntroActive then
    FStoreLine := FIntro[0]
  else
  begin
    FStoreLine := FStory.FenwickGreet(FVisits - 1);
    if not FSettings.FenwickMet then
    begin
      FSettings.FenwickMet := True;
      FSettings.Save;
    end;
  end;
  Changed;
end;

procedure TGameController.ActionOpenCards;
begin
  if FMenuOpen then Exit;
  if Animating and FInScene then Exit;
  if Animating then SkipDeal;
  CloseModes;
  FOverlay := okCards;
  Changed;
end;

procedure TGameController.ActionCloseOverlay;
begin
  if FMenuOpen and not (FOverlay in [okSlots, okStyle, okRelics]) then Exit;
  if FOverlay = okNone then Exit;
  if (FOverlay = okStore) then
  begin
    if IntroActive and not FSettings.FenwickMet then
    begin
      FSettings.FenwickMet := True;            { leaving early still counts as met }
      FSettings.Save;
    end;
    FToast := FStory.FenwickLeave;
  end;
  FOverlay := okNone;
  FSelected := -1;
  Changed;
end;

procedure TGameController.ActionCancel;
begin
  if FMenuOpen then Exit;
  if not FTargeting then Exit;
  FTargeting := False;
  FToast := 'Cancelled.';
  Changed;
end;

procedure TGameController.AdvanceIntro;
begin
  if not IntroActive then Exit;
  Inc(FIntroAt);
  if FIntroAt >= Length(FIntro) then
  begin
    FSettings.FenwickMet := True;
    FSettings.Save;
    FStoreLine := FStory.FenwickGreet(FVisits - 1);
  end
  else
    FStoreLine := FIntro[FIntroAt];
  Changed;
end;

function TGameController.OverlayRowCount: Integer;
begin
  case FOverlay of
    okStore: Result := StoreGoodCount;
    okCards: Result := SpecialCount;
    okRecords: Result := 10 + 2;             { two headings, ten records }
    okSlots: if FSlotsSave then Result := 4 else Result := 8;   { headings and three slots a mode }
    okTrophies: Result := TrophyCount;
    okStyle: Result := CosmeticsPerKind;
    okRelics: Result := RelicCount;
  else
    Result := 0;
  end;
end;

function TGameController.OverlayRow(I: Integer): TOverlayRow;
var
  K: TSpecialKind;
  Inv: TPlayerInventory;
  Owned: Integer;
begin
  SyncPrices;
  Inv := FSession.Inventory;
  Result.Title := '';
  Result.Detail := '';
  Result.Aside := '';
  Result.ButtonText := '';
  Result.ButtonEnabled := False;
  Result.Button2Text := '';
  Result.Button2Enabled := False;
  Result.Preview := 0;
  Result.Art := I;
  Result.Selected := (FOverlay = okStore) and (I = FSelected);
  Result.Header := False;
  if (I < 0) or (I >= OverlayRowCount) then Exit;
  if FOverlay = okRecords then
  begin
    Result := RecordRow(I);
    Exit;
  end;
  if FOverlay = okSlots then
  begin
    Result := SlotRow(I);
    Exit;
  end;
  if FOverlay = okStyle then
  begin
    Result := StyleRow(I);
    Exit;
  end;
  if FOverlay = okRelics then
  begin
    Result := RelicRow(I);
    Exit;
  end;
  if FOverlay = okTrophies then
  begin
    Result.Art := TrophyArt(I);
    Result.Selected := False;
    if FTrophies.Has(TTrophy(I)) then
    begin
      Result.Title := FStory.TrophyName(TrophyKeys[TTrophy(I)]);
      Result.Detail := FStory.TrophyLine(TrophyKeys[TTrophy(I)]);
      Result.Aside := '';                    { the picture says it; the text gets the room }
    end
    else
    begin
      Result.Title := FStory.TrophyName(TrophyKeys[TTrophy(I)]);
      Result.Detail := FStory.TrophyHow(TrophyKeys[TTrophy(I)]);
      Result.Aside := '';
    end;
    Exit;
  end;
  if I < SpecialCount then
  begin
    K := TSpecialKind(I);
    Owned := Inv.SpecialCards(K);
    Result.Title := SpecialName[K];
    Result.Detail := SpecialInfo[K];
    if FOverlay = okStore then
    begin
      if Owned > 0 then Result.Detail := Result.Detail + Format('  (You have %d.)', [Owned]);
      Result.Aside := Format('%d coins', [Inv.SpecialPrice(K)]);
      Result.ButtonText := 'Buy';
      Result.ButtonEnabled := not IntroActive and Inv.CanBuySpecial(K) and Stocked(I);
      if not Stocked(I) then
      begin
        Result.Detail := 'Not in stock yet. Come back after Lucien.';
        Result.Aside := 'soon';
      end;
    end
    else
    begin
      Result.Aside := Format('x %d', [Owned]);
      if NeedsTarget(K) then Result.ButtonText := 'Use...' else Result.ButtonText := 'Use';
      Result.ButtonEnabled := HandIsLive and FSession.CanUseSpecial(K);
    end;
  end
  else if I = ArtUndo then
  begin
    Result.Title := Format('Undo cards (%d)', [UndoPackSize]);
    Result.Detail := 'Take back your last move.';
    if Inv.UndoCards > 0 then Result.Detail := Result.Detail + Format('  (You have %d.)', [Inv.UndoCards]);
    Result.Aside := Format('%d coins', [Inv.UndoPackPrice]);
    Result.ButtonText := 'Buy';
    Result.ButtonEnabled := not IntroActive and Inv.CanBuyUndoPack;
  end
  else
  begin
    Result.Title := Format('Hint cards (%d)', [HintPackSize]);
    Result.Detail := 'Show which cards can be played.';
    if Inv.HintCards > 0 then Result.Detail := Result.Detail + Format('  (You have %d.)', [Inv.HintCards]);
    Result.Aside := Format('%d coins', [Inv.HintPackPrice]);
    Result.ButtonText := 'Buy';
    Result.ButtonEnabled := not IntroActive and Inv.CanBuyHintPack;
  end;
end;

function TGameController.OverlayTitle: string;
begin
  case FOverlay of
    okStore: Result := FStory.FenwickName;
    okCards: Result := 'Your special cards';
    okRecords: Result := 'Your records';
    okSlots: if FSlotsSave then Result := 'Save game' else Result := 'Load game';
    okTrophies: Result := 'Your trophies';
    okStyle: Result := 'Style';
    okRelics: Result := 'Relics';
  else
    Result := '';
  end;
end;

function TGameController.OverlayLine: string;
begin
  case FOverlay of
    okStore: Result := FStoreLine;
    okCards:
      Result := 'Pick a card to use it. The Wild card asks you to tap two cards in play, the Wood Stake one free card. Dimmed cards would do nothing now.';
    okRecords:
      Result := 'Your best results on this device. Only won hands count.';
    okRelics:
    begin
      Result := Format('Small helps against the vampires. Slots used: %d of %d. A relic works the moment you equip it, even in the hand you are playing.',
        [RelicsInMask(RelicsEquippedMask), RelicSlotCount]);
      if not ShopOpen then Result := Result + ' Fenwick sells between hands.';
    end;
    okStyle:
      Result := 'How the cards, the table and the moon look. It never changes how a hand plays.';
    okTrophies:
      Result := 'Keepsakes from the vampires, and from how you play. They stay with you, even if you start the campaign again.';
    okSlots:
      if FSlotsSave then
      begin
        if FCampaignMode then
          Result := 'A campaign save keeps your progress, this hand, and your coins and cards.'
        else
          Result := 'A Free Play save keeps this hand (not your coins or cards).';
      end
      else
        Result := 'Puts the game back as saved (a campaign save restores your coins and cards too).';
  else
    Result := '';
  end;
end;

function TGameController.OverlayHint: string;
begin
  if IntroActive then Result := 'tap to go on' else Result := '';
end;

function TGameController.OverlayFooter: string;
begin
  if (FOverlay = okStore) and (FVW < 520) and (OverlayExtraCount > 0) then
    Result := ''                                 { no room: the coins are in the status line anyway }
  else if FOverlay = okStore then
    Result := Format('Coins: %d', [FSession.Inventory.Coins])
  else if (FOverlay = okStyle) or (FOverlay = okRelics) then
    Result := Format('Coins: %d', [FSession.Inventory.Coins])
  else if FOverlay = okTrophies then
    Result := Format('%d of %d earned', [FTrophies.Count, TrophyCount])
  else
    Result := '';
end;

function TGameController.OverlayLeaveCaption: string;
begin
  if FOverlay = okStore then Result := 'Leave' else Result := 'Close';
end;

{ Where everything goes. A wide area: the portrait on the left and the list on
  the right. A tall area (a tablet held upright): the portrait and his words
  across the top and the list underneath. }
function TGameController.Layout: TOverlayLayout;
const
  M = 12;
  Pad = 14;
  LeaveH = 44;
var
  L: TOverlayLayout;
  PW, PH, SpeechH, N, InnerH, Bottom: Integer;
  Tall: Boolean;
begin
  L.Panel := Rect(M, M, FVW - M, FVH - M);
  Tall := FVH * 10 > FVW * 11;
  L.Portrait := Rect(0, 0, 0, 0);
  L.X0 := L.Panel.Left + Pad;
  L.X1 := L.Panel.Right - Pad;
  InnerH := L.Panel.Bottom - L.Panel.Top - 2 * Pad;
  if FOverlay = okStore then
  begin
    if Tall then
    begin
      PH := Round(FVH * 0.26);
      if PH < 140 then PH := 140;
      if PH > 300 then PH := 300;
      PW := Round(PH * 596 / 878);
      L.Portrait := Rect(L.X0, L.Panel.Top + Pad, L.X0 + PW, L.Panel.Top + Pad + PH);
      L.Speech := Rect(L.Portrait.Right + Pad, L.Portrait.Top, L.X1, L.Portrait.Bottom);
      L.RowsTop := L.Portrait.Bottom + Pad;
    end
    else
    begin
      PW := Round((L.Panel.Right - L.Panel.Left) * 0.28);
      if PW < 170 then PW := 170;
      if PW > 340 then PW := 340;
      PH := Round(PW * 878 / 596);
      if PH > InnerH then
      begin
        PH := InnerH;
        PW := Round(PH * 596 / 878);
      end;
      L.Portrait := Rect(L.X0, L.Panel.Top + Pad, L.X0 + PW, L.Panel.Top + Pad + PH);
      L.X0 := L.Portrait.Right + Pad;
      SpeechH := Round((L.Panel.Bottom - L.Panel.Top) * 0.2);
      if SpeechH < 70 then SpeechH := 70;
      if SpeechH > 130 then SpeechH := 130;
      L.Speech := Rect(L.X0, L.Panel.Top + Pad, L.X1, L.Panel.Top + Pad + SpeechH);
      L.RowsTop := L.Speech.Bottom + Pad;
    end;
  end
  else
  begin
    SpeechH := 72;
    if (FVH < 420) or (FVW < 520) then SpeechH := 90;
    if FOverlay in [okRecords, okSlots, okTrophies, okStyle] then SpeechH := 62;
    if FOverlay = okRelics then SpeechH := 80;
    if (FOverlay = okStyle) and ((FVH < 420) or (FVW < 520)) then SpeechH := 90;
    L.Speech := Rect(L.X0, L.Panel.Top + Pad, L.X1, L.Panel.Top + Pad + SpeechH);
    L.RowsTop := L.Speech.Bottom + Pad;
    if FOverlay = okStyle then L.RowsTop := L.RowsTop + StyleTabHeight + 6;     { the tabs sit between }
  end;
  L.Leave := Rect(L.X1 - 130, L.Panel.Bottom - Pad - LeaveH, L.X1, L.Panel.Bottom - Pad);
  L.Footer := Rect(L.X0, L.Leave.Top, L.Leave.Left - Pad, L.Leave.Bottom);
  Bottom := L.Leave.Top - Pad;
  N := OverlayRowCount;
  if N < 1 then N := 1;
  L.RowH := (Bottom - L.RowsTop) div N;
  if L.RowH > 64 then L.RowH := 64;
  if (FOverlay = okRecords) and (L.RowH < 24) then L.RowH := 24
  else if (FOverlay <> okRecords) and (L.RowH < 30) then L.RowH := 30;
  Result := L;
end;

function TGameController.OverlayPanelRect: TRect;
begin
  Result := Layout.Panel;
end;

function TGameController.OverlayPortraitRect: TRect;
begin
  Result := Layout.Portrait;
end;

function TGameController.OverlaySpeechRect: TRect;
begin
  Result := Layout.Speech;
end;

function TGameController.OverlayLeaveRect: TRect;
begin
  Result := Layout.Leave;
end;

function TGameController.OverlayFooterRect: TRect;
begin
  Result := Layout.Footer;
end;

function TGameController.OverlayRowRect(I: Integer): TRect;
var
  L: TOverlayLayout;
begin
  L := Layout;
  Result := Rect(L.X0, L.RowsTop + I * L.RowH, L.X1, L.RowsTop + (I + 1) * L.RowH - 4);
end;

function TGameController.OverlayTabCount: Integer;
begin
  if FOverlay = okStyle then Result := CosmeticKindCount else Result := 0;
end;

function TGameController.OverlayTabRect(I: Integer): TRect;
var
  L: TOverlayLayout;
  W: Integer;
begin
  L := Layout;
  W := (L.X1 - L.X0 - 2 * 8) div CosmeticKindCount;
  Result := Rect(L.X0 + I * (W + 8), L.Speech.Bottom + 6, L.X0 + I * (W + 8) + W,
    L.Speech.Bottom + 6 + StyleTabHeight);
end;

function TGameController.OverlayTabCaption(I: Integer): string;
begin
  case I of
    0: Result := 'Card backs';
    1: Result := 'Table cloths';
  else
    Result := 'The moon';
  end;
end;

function TGameController.OverlayTabSelected(I: Integer): Boolean;
begin
  Result := (FOverlay = okStyle) and (I = FStyleTab);
end;

function TGameController.OverlayExtraCount: Integer;
begin
  if (FOverlay = okStore) and not IntroActive then Result := 2 else Result := 0;
end;

function TGameController.OverlayExtraCaption(I: Integer): string;
begin
  case I of
    0: Result := 'Relics';
    1: Result := 'Style';
  else
    Result := '';
  end;
  if I >= OverlayExtraCount then Result := '';
end;

function TGameController.OverlayExtraRect(I: Integer): TRect;
var
  L: TOverlayLayout;
  BW: Integer;
begin
  L := Layout;
  BW := 110;
  if FVW < 520 then BW := 80;                  { a phone held upright: three buttons have to fit the row }
  { Relics sits beside Close, Style beside Relics }
  Result := Rect(L.Leave.Left - (I + 1) * (BW + 8), L.Leave.Top, L.Leave.Left - (I + 1) * (BW + 8) + BW, L.Leave.Bottom);
end;

function TGameController.OverlayButton2Rect(I: Integer): TRect;
var
  B: TRect;
begin
  B := OverlayButtonRect(I);
  Result := B;
  OffsetRect(Result, -((B.Right - B.Left) + 8), 0);
end;

function TGameController.OverlayButtonRect(I: Integer): TRect;
var
  R: TRect;
  BH: Integer;
begin
  R := OverlayRowRect(I);
  BH := R.Bottom - R.Top - 6;
  if BH > 44 then BH := 44;
  Result := Rect(R.Right - 100, R.Top + ((R.Bottom - R.Top) - BH) div 2, R.Right - 4,
    R.Top + ((R.Bottom - R.Top) - BH) div 2 + BH);
end;

procedure TGameController.SelectRow(I: Integer);
begin
  if FOverlay <> okStore then Exit;
  FSelected := I;
  if not Stocked(I) then
    FStoreLine := FStory.FenwickLocked(SpecialKey[TSpecialKind(I)])
  else if I < SpecialCount then
    FStoreLine := FStory.FenwickPitch(SpecialKey[TSpecialKind(I)])
  else if I = ArtUndo then
    FStoreLine := FStory.FenwickPitch('undo')
  else
    FStoreLine := FStory.FenwickPitch('hint');
  Changed;
end;

procedure TGameController.AfterSpecial(Used: Boolean);
begin
  if not Used then
  begin
    Changed;
    Exit;
  end;
  if not FCampaignMode and FGame.IsWon then PlayWin;
  if FCampaignMode then
    ResolveDuel                              { the hand may be won, or lost, by it }
  else
  begin
    AutoSave;
    Changed;
  end;
end;

procedure TGameController.RowAction(I: Integer);
var
  K: TSpecialKind;
  Bought: Boolean;
  Used: Boolean;
begin
  if (I < 0) or (I >= OverlayRowCount) then Exit;
  if FOverlay = okSlots then
  begin
    SlotAction(I);
    Exit;
  end;
  if FOverlay = okStyle then
  begin
    StyleAction(I);
    Exit;
  end;
  if FOverlay = okRelics then
  begin
    RelicAction(I);
    Exit;
  end;
  if FOverlay = okStore then
  begin
    if not Stocked(I) then
    begin
      SelectRow(I);                          { he says it is not in yet }
      Exit;
    end;
    SyncPrices;
    if I < SpecialCount then Bought := FSession.BuySpecial(TSpecialKind(I))
    else if I = ArtUndo then Bought := FSession.BuyUndoPack
    else Bought := FSession.BuyHintPack;
    if Bought then
    begin
      Inc(FSales);
      FStoreLine := FStory.FenwickBought(FSales - 1);
    end
    else
    begin
      Inc(FRefusals);
      FStoreLine := FStory.FenwickBroke(FRefusals - 1);
    end;
    FSelected := I;
    Changed;
    Exit;
  end;
  { the tray: use a card }
  K := TSpecialKind(I);
  if NeedsTarget(K) then
  begin
    FTargetKind := K;
    FTargeting := True;
    FOverlay := okNone;
    Changed;
    Exit;
  end;
  if FCampaignMode then Used := FDuel.UseSpecial(K) else Used := FSession.UseSpecial(K);
  FOverlay := okNone;
  AfterSpecial(Used);
end;

procedure TGameController.TapOverlay(X, Y: Integer);
var
  P: TPoint;
  I: Integer;
begin
  P := Point(X, Y);
  if PtInRect(Layout.Leave, P) then
  begin
    ActionCloseOverlay;
    Exit;
  end;
  for I := 0 to OverlayExtraCount - 1 do
    if PtInRect(OverlayExtraRect(I), P) then
    begin
      if I = 0 then ActionOpenRelics else ActionOpenStyle;     { Fenwick's other pages }
      Exit;
    end;
  for I := 0 to OverlayTabCount - 1 do
    if PtInRect(OverlayTabRect(I), P) then
    begin
      FStyleTab := I;
      Changed;
      Exit;
    end;
  if IntroActive then
  begin
    AdvanceIntro;
    Exit;
  end;
  if FOverlay = okSlots then
    for I := 0 to OverlayRowCount - 1 do
      if PtInRect(OverlayButton2Rect(I), P) and (OverlayRow(I).Button2Text <> '') then
      begin
        if OverlayRow(I).Button2Enabled then
        begin
          FDeleteAsk := I;                 { ask first: a deleted save cannot be brought back }
          Changed;
        end;
        Exit;
      end;
  for I := 0 to OverlayRowCount - 1 do
    if PtInRect(OverlayButtonRect(I), P) then
    begin
      if OverlayRow(I).ButtonEnabled then RowAction(I)
      else if FOverlay = okStore then SelectRow(I);
      Exit;
    end;
  for I := 0 to OverlayRowCount - 1 do
    if PtInRect(OverlayRowRect(I), P) then
    begin
      SelectRow(I);
      Exit;
    end;
  if not PtInRect(Layout.Panel, P) then ActionCloseOverlay;     { a tap outside closes it }
end;

procedure TGameController.TapTarget(X, Y: Integer);
var
  P: TPoint;
  Hit: Integer;
  C: TCard;
  Used: Boolean;
begin
  P := Point(X, Y);
  Hit := HitPyramid(X, Y);
  if (Hit < 0) and (FTargetKind = skWild) and PtInRect(WasteRect, P) and FGame.WasteTop(C) then
    Hit := PosWaste;                                   { the waste top is in play for a Wild card }
  if Hit = PosNone - 1 then Hit := -1;
  if (Hit < 0) and (Hit <> PosWaste) then
  begin
    ActionCancel;                                      { a tap anywhere else cancels }
    Exit;
  end;
  if (Hit >= 0) and not FGame.IsFree(Hit) then
  begin
    FToast := 'That card has cards on top of it: pick one with nothing covering it.';
    Changed;
    Exit;
  end;
  if FTargetKind = skWild then
  begin
    if FTargetA = PosNone then
    begin
      FTargetA := Hit;                                 { the first of the two }
      FToast := '';
      Changed;
      Exit;
    end;
    if Hit = FTargetA then
    begin
      FTargetA := PosNone;                             { the same card again lets it go }
      Changed;
      Exit;
    end;
    FTargeting := False;
    if FCampaignMode then Used := FDuel.UseSpecialOn(FTargetKind, FTargetA, Hit)
    else Used := FSession.UseSpecialOn(FTargetKind, FTargetA, Hit);
    FTargetA := PosNone;
  end
  else
  begin
    FTargeting := False;
    if FCampaignMode then Used := FDuel.UseSpecialOn(FTargetKind, Hit, PosNone)
    else Used := FSession.UseSpecialOn(FTargetKind, Hit, PosNone);
  end;
  FToast := '';
  AfterSpecial(Used);
end;

function TGameController.CardFaceUp(I: Integer): Boolean;
begin
  Result := True;                           { the pyramid is dealt face up }
end;

function TGameController.CardMark(I: Integer): Integer;
begin
  if FGame.Removed(I) then Result := MarkNone
  else Result := FGame.Mark(I);
end;

function TGameController.CardSelected(I: Integer): Boolean;
begin
  Result := (FPick = I) or (FTargeting and (FTargetKind = skWild) and (FTargetA = I));
end;

function TGameController.WasteSelected: Boolean;
begin
  Result := (FPick = PosWaste) or (FTargeting and (FTargetKind = skWild) and (FTargetA = PosWaste));
end;

{ The cards a hint points at: the first removal there is. }
function HintCards(AGame: TPyramidGame; out A, B: Integer): Boolean;
begin
  Result := AGame.FindRemoval(0, A, B);
end;

function TGameController.CardHighlighted(I: Integer): Boolean;
var
  A, B: Integer;
begin
  Result := FTargeting and FGame.IsFree(I) and not CardSelected(I);
  if (not Result) and FSession.HintActive and HintCards(FGame, A, B) then
    Result := (A = I) or (B = I);
end;

function TGameController.WasteHighlighted: Boolean;
var
  A, B: Integer;
  C: TCard;
begin
  Result := FTargeting and (FTargetKind = skWild) and FGame.WasteTop(C) and not WasteSelected;
  if (not Result) and FSession.HintActive and HintCards(FGame, A, B) then
    Result := (A = PosWaste) or (B = PosWaste);
end;

function TGameController.StockHighlighted: Boolean;
var
  A, B: Integer;
begin
  Result := FSession.HintActive and not HintCards(FGame, A, B) and (FGame.CanDraw or FGame.CanRecycle);
end;

{ ---- personal records ---- }

{ A trophy earned: say so (the status line keeps the news until the next tap on the table). }
procedure TGameController.EarnTrophy(T: TTrophy);
var
  Name: string;
begin
  if not FTrophies.Award(T) then Exit;
  Name := FStory.TrophyName(TrophyKeys[T]);
  if FNews = '' then FNews := 'Trophy earned: ' + Name
  else FNews := FNews + ', ' + Name;
end;

procedure TGameController.SessionWon(BestStreak, Misses: Integer);
begin
  if FCampaignMode then Exit;
  FPending := FPending + FRecords.FreePlayWon(BestStreak, Misses);
  EarnTrophy(trFirstWin);
  if Misses = 0 then EarnTrophy(trPerfect);
end;

procedure TGameController.DuelWon(V, TotalLost, BestStreak, Misses: Integer; Kill: Boolean);
begin
  FPending := FPending + FRecords.CampaignHandWon(BestStreak);
  EarnTrophy(trFirstWin);
  if Misses = 0 then EarnTrophy(trPerfect);
  if Kill then
  begin
    FPending := FPending + FRecords.CampaignKill(V, TotalLost);
    EarnTrophy(TrophyForVampire(V));
    if V = VampireCount - 1 then
    begin
      FRecords.CampaignCompleted;
      if FCampaign.LostAll = 0 then EarnTrophy(trFlawless);
    end;
  end;
end;

{ Ask for initials once the table is quiet (not during a scene, a deal, a
  Store visit or a card pick). }
function TGameController.NeedInitials: Boolean;
begin
  Result := (FPending <> []) and not FMenuOpen and not Animating and (FOverlay = okNone) and not FTargeting;
end;

function TGameController.PendingText: string;
var
  Id: TRecordId;
  V: Integer;
begin
  Result := '';
  for Id := Low(TRecordId) to High(TRecordId) do
    if Id in FPending then
    begin
      if Result <> '' then Result := Result + ', ';
      case Id of
        rcFreeStreak: Result := Result + 'Free Play longest streak';
        rcFreeRun: Result := Result + 'Free Play most wins in a row';
        rcCampStreak: Result := Result + 'Campaign longest streak';
      else
        begin
          V := Ord(Id) - Ord(rcFewestLost0);
          Result := Result + 'fewest lost hands against ' + FStory.Name(V);
        end;
      end;
    end;
  if Result <> '' then
    Result := 'New personal best: ' + Result + '. Enter your initials (up to 3 letters or digits):';
end;

procedure TGameController.ActionSubmitInitials(const S: string);
begin
  if FPending = [] then Exit;
  FRecords.SetHolders(FPending, S);
  FPending := [];
  Changed;
end;

procedure TGameController.ActionAnswerCross(APlayIt: Boolean);
begin
  if FCrossAsk < 0 then Exit;
  FCrossAsk := -1;
  FToast := '';
  if APlayIt and FCampaignMode and (FDuel.Duel.State = dsPlaying)
    and ((FGame.Mark(FCrossA) = MarkCross) or (FGame.Mark(FCrossB) = MarkCross))
    and FGame.CanRemove(FCrossA, FCrossB) then
  begin
    FDuel.Remove(FCrossA, FCrossB);
    ResolveDuel;
    AutoSave;
  end;
  Changed;
end;

{ What the delete question says: which saved game and what is in it. }
function TGameController.DeleteText: string;
var
  Camp: Boolean;
  N: Integer;
begin
  Result := '';
  if (FDeleteAsk < 0) or not SlotRowInfo(FDeleteAsk, Camp, N) then Exit;
  if Camp then Result := 'Delete the saved Campaign in slot ' + IntToStr(N)
  else Result := 'Delete the saved Free Play hand in slot ' + IntToStr(N);
  Result := Result + ' (' + OverlayRow(FDeleteAsk).Detail + ')? It cannot be brought back.';
end;

procedure TGameController.ActionAnswerDelete(ADelete: Boolean);
var
  I, N: Integer;
  Camp: Boolean;
begin
  I := FDeleteAsk;
  if I < 0 then Exit;
  FDeleteAsk := -1;
  if ADelete and (FOverlay = okSlots) and SlotRowInfo(I, Camp, N) then
  begin
    if Camp then DeleteCampaignSlot(N) else StoreDelete(SlotFile(N));
    FToast := Format('Deleted slot %d.', [N]);
  end;
  Changed;
end;

procedure TGameController.ActionRulesClosed;
begin
  FRulesShow := False;
  Changed;
end;

function TGameController.RulesSectionCount: Integer;
begin
  Result := Rules.RulesSectionCount;
end;

function TGameController.RulesHeading(I: Integer): string;
begin
  Result := Rules.RulesHeading(I, FStory);
end;

function TGameController.RulesBody(I: Integer): string;
begin
  Result := Rules.RulesBody(I, FStory);
end;

function TGameController.RulesPlainText: string;
begin
  Result := Rules.RulesPlainText(FStory);
end;

function TGameController.TrophyLayout: TTrophyLayout;
begin
  Result := TrophyLayoutFor(PanelRect, PanelPlacement = ppBottom);
end;

function TGameController.TrophyArt(I: Integer): Integer;
begin
  if (I >= 0) and (I < TrophyCount) and FTrophies.Has(TTrophy(I)) then Result := ArtTrophy0 + I
  else Result := ArtTrophyEmpty;
end;

{ ---- relics ---- }

{ Bought, or given by a trophy. }
function TGameController.RelicOwned(R: TRelic): Boolean;
var
  T: Integer;
begin
  Result := FSession.Inventory.BoughtRelic(R);
  T := RelicTrophy(R);
  if (T <> NoRelicTrophy) and FTrophies.Has(TTrophy(T)) then Result := True;
end;

function TGameController.RelicSlotCount: Integer;
var
  V, N: Integer;
begin
  N := 0;
  for V := 0 to VampireCount - 1 do
    if FTrophies.Has(TrophyForVampire(V)) then Inc(N);
  Result := RelicSlots(N);
end;

{ The relics in use, as bits: what the player chose, in order, if they still own it and
  it fits the slots (a loaded save or an edited file may break either). }
function TGameController.RelicsEquippedMask: Integer;
var
  S, Key: string;
  P, Idx, N: Integer;
begin
  Result := 0;
  N := 0;
  S := FSettings.Equipped;
  while S <> '' do
  begin
    P := Pos(',', S);
    if P = 0 then
    begin
      Key := S;
      S := '';
    end
    else
    begin
      Key := Copy(S, 1, P - 1);
      S := Copy(S, P + 1, Length(S));
    end;
    Idx := RelicIndexOf(Key);
    if (Idx >= 0) and RelicOwned(TRelic(Idx)) and not HasRelic(Result, TRelic(Idx)) and (N < RelicSlotCount) then
    begin
      Result := Result or RelicBit(TRelic(Idx));
      Inc(N);
    end;
  end;
end;

function TGameController.RelicEquipped(R: TRelic): Boolean;
begin
  Result := HasRelic(RelicsEquippedMask, R);
end;

procedure TGameController.ActionOpenRelics;
begin
  if Animating and FInScene then Exit;
  if Animating then SkipDeal;
  if not FMenuOpen then CloseModes;
  FOverlay := okRelics;
  Changed;
end;

function TGameController.RelicRow(I: Integer): TOverlayRow;
var
  R: TRelic;
  T: Integer;
  Used: Integer;
  B: Integer;
begin
  R := TRelic(I);
  Result.Title := FStory.RelicName(RelicKey(R));
  Result.Detail := FStory.RelicLine(RelicKey(R));
  Result.Aside := '';
  Result.ButtonText := '';
  Result.ButtonEnabled := False;
  Result.Button2Text := '';
  Result.Button2Enabled := False;
  Result.Art := ArtRelic0 + I;
  Result.Selected := False;
  Result.Header := False;
  Result.Preview := 0;
  T := RelicTrophy(R);
  Used := 0;
  for B := 0 to RelicCount - 1 do
    if RelicEquipped(TRelic(B)) then Inc(Used);
  if RelicEquipped(R) then
  begin
    Result.Selected := True;
    Result.Aside := 'equipped';
    Result.ButtonText := 'Remove';
    Result.ButtonEnabled := True;
  end
  else if RelicOwned(R) then
  begin
    Result.ButtonText := 'Equip';
    Result.ButtonEnabled := Used < RelicSlotCount;
  end
  else
  begin
    Result.Aside := Format('%d coins', [RelicPrice(R)]);
    Result.ButtonText := 'Buy';
    Result.ButtonEnabled := ShopOpen and FSession.Inventory.CanBuyRelic(R);     { Fenwick sells between hands only }
    if T <> NoRelicTrophy then
      Result.Detail := Result.Detail + ' Also earned with ' + FStory.TrophyName(TrophyKeys[TTrophy(T)]) + '.';
  end;
end;

{ Buy, equip or remove relic I. }
procedure TGameController.RelicAction(I: Integer);
var
  R: TRelic;
  Name, Key, S: string;
  Used, B: Integer;
begin
  R := TRelic(I);
  Name := FStory.RelicName(RelicKey(R));
  Key := RelicKey(R);
  Used := 0;
  for B := 0 to RelicCount - 1 do
    if RelicEquipped(TRelic(B)) then Inc(Used);
  if RelicEquipped(R) then
  begin
    { take it out: rebuild the list without it }
    S := '';
    for B := 0 to RelicCount - 1 do
      if (B <> I) and RelicEquipped(TRelic(B)) then
      begin
        if S <> '' then S := S + ',';
        S := S + RelicKey(TRelic(B));
      end;
    FSettings.Equipped := S;
    FToast := Name + ' removed.';
  end
  else
  begin
    if not RelicOwned(R) then
    begin
      if not ShopOpen then
      begin
        SetToast('Fenwick sells between hands. You can equip what you own now.');
        Exit;
      end;
      if not FSession.Inventory.BuyRelic(R) then Exit;
      FSession.SaveNow;
      FToast := 'Bought ' + Name + '.';
    end
    else
      FToast := '';
    if Used < RelicSlotCount then
    begin
      S := FSettings.Equipped;
      { keep only what is really in use, then add this one }
      S := '';
      for B := 0 to RelicCount - 1 do
        if RelicEquipped(TRelic(B)) then
        begin
          if S <> '' then S := S + ',';
          S := S + RelicKey(TRelic(B));
        end;
      if S <> '' then S := S + ',';
      FSettings.Equipped := S + Key;
      FToast := FToast + ' ' + Name + ' equipped.';
    end
    else
      FToast := FToast + ' No free slot: remove a relic first.';
    FToast := Trim(FToast);
  end;
  FSettings.Save;
  FSession.Relics := RelicsEquippedMask;      { a relic works at once, in the hand on the table too }
  if FCampaignMode and FStarted and (FDuel.Duel.State = dsPlaying) then
  begin
    FDuel.RelicsChanged;                      { no move left without the Pick: the hand is lost }
    ResolveDuel;
  end
  else
    Changed;
end;

{ ---- Style ---- }

{ Is it the player's? The original look always is; a trophy unlocks one; the rest are bought. }
function TGameController.StyleAvailable(K: TCosmeticKind; I: Integer): Boolean;
var
  T: Integer;
begin
  if I <= 0 then Exit(True);
  T := CosmeticTrophy(K, I);
  if T <> NoTrophy then Result := FTrophies.Has(TTrophy(T))
  else Result := FSession.Inventory.BoughtCosmetic(K, I);
end;

{ The choice in use: what was picked, if the player still has it (a loaded save or an
  edited file may not), else the original. }
function TGameController.StyleChoice(K: TCosmeticKind): Integer;
begin
  case K of
    ckBack: Result := CosmeticIndexOf(K, FSettings.BackKey);
    ckCloth: Result := CosmeticIndexOf(K, FSettings.ClothKey);
  else
    Result := CosmeticIndexOf(K, FSettings.MoonKey);
  end;
  if not StyleAvailable(K, Result) then Result := 0;
end;

function TGameController.StyleBack: Integer;
begin
  Result := StyleChoice(ckBack);
end;

function TGameController.StyleCloth: Integer;
begin
  Result := StyleChoice(ckCloth);
end;

function TGameController.StyleMoon: Integer;
begin
  Result := StyleChoice(ckMoon);
end;

procedure TGameController.ActionOpenStyle;
begin
  if Animating and FInScene then Exit;
  if Animating then SkipDeal;
  if not FMenuOpen then CloseModes;
  FOverlay := okStyle;
  Changed;
end;

function TGameController.StyleRow(I: Integer): TOverlayRow;
var
  K: TCosmeticKind;
  Key: string;
  T: Integer;
begin
  Result.Title := '';
  Result.Detail := '';
  Result.Aside := '';
  Result.ButtonText := '';
  Result.ButtonEnabled := False;
  Result.Button2Text := '';
  Result.Button2Enabled := False;
  Result.Art := -1;
  Result.Selected := False;
  Result.Header := False;
  K := TCosmeticKind(FStyleTab);
  Result.Preview := Ord(K) * 16 + I + 1;
  Key := CosmeticStoryKey(K, I);
  Result.Title := FStory.StyleName(Key);
  Result.Detail := FStory.StyleLine(Key);
  T := CosmeticTrophy(K, I);
  if StyleChoice(K) = I then
  begin
    Result.Selected := True;
    Result.Aside := '';
    Result.ButtonText := 'In use';
    Result.ButtonEnabled := False;
  end
  else if StyleAvailable(K, I) then
  begin
    Result.ButtonText := 'Use';
    Result.ButtonEnabled := True;
  end
  else if T <> NoTrophy then
  begin
    Result.Detail := 'Earned with ' + FStory.TrophyName(TrophyKeys[TTrophy(T)]) + '.';
    Result.Aside := 'locked';
  end
  else
  begin
    Result.Aside := Format('%d coins', [CosmeticCost(K, I)]);
    Result.ButtonText := 'Buy';
    Result.ButtonEnabled := FSession.Inventory.CanBuyCosmetic(K, I);
  end;
end;

{ Buy or use item I of the page's kind. Buying takes the price and uses it at once. }
procedure TGameController.StyleAction(I: Integer);
var
  K: TCosmeticKind;
  Name: string;
begin
  K := TCosmeticKind(FStyleTab);
  Name := FStory.StyleName(CosmeticStoryKey(K, I));
  if not StyleAvailable(K, I) then
  begin
    if not FSession.Inventory.BuyCosmetic(K, I) then Exit;
    FSession.SaveNow;
    FToast := 'Bought ' + Name + '.';
  end
  else
    FToast := Name + ' is now in use.';
  case K of
    ckBack: FSettings.BackKey := CosmeticKey(K, I);
    ckCloth: FSettings.ClothKey := CosmeticKey(K, I);
  else
    FSettings.MoonKey := CosmeticKey(K, I);
  end;
  FSettings.Save;
  Changed;
end;

procedure TGameController.ActionOpenTrophies;
begin
  if FMenuOpen then Exit;
  if Animating and FInScene then Exit;
  if Animating then SkipDeal;
  CloseModes;
  FOverlay := okTrophies;
  Changed;
end;

procedure TGameController.ActionOpenRecords;
begin
  if FMenuOpen then Exit;
  if Animating and FInScene then Exit;
  if Animating then SkipDeal;
  CloseModes;
  FOverlay := okRecords;
  Changed;
end;

{ The records page: a heading, four Free Play lines, a heading, six campaign
  lines. }
function TGameController.RecordRow(I: Integer): TOverlayRow;
var
  V: Integer;
begin
  Result.Title := '';
  Result.Detail := '';
  Result.Aside := '';
  Result.ButtonText := '';
  Result.ButtonEnabled := False;
  Result.Button2Text := '';
  Result.Button2Enabled := False;
  Result.Preview := 0;
  Result.Art := -1;
  Result.Selected := False;
  Result.Header := False;
  case I of
    0:
    begin
      Result.Header := True;
      Result.Title := 'FREE PLAY';
    end;
    1, 2:
    begin
      Result.Title := FRecords.Title(TRecordId(I - 1));      { rcFreeStreak, rcFreeRun }
      Result.Detail := FRecords.Detail(TRecordId(I - 1));
      Result.Aside := FRecords.ValueText(TRecordId(I - 1));
    end;
    3:
    begin
      Result.Title := 'Perfect hands';
      Result.Detail := 'Hands won without a single missed move.';
      Result.Aside := IntToStr(FRecords.FreePerfect);
    end;
    4:
    begin
      Result.Title := 'Hands won';
      Result.Detail := 'Every Free Play hand you have won.';
      Result.Aside := IntToStr(FRecords.FreeWins);
    end;
    5:
    begin
      Result.Header := True;
      Result.Title := 'CAMPAIGN';
    end;
    6:
    begin
      Result.Title := FRecords.Title(rcCampStreak);
      Result.Detail := FRecords.Detail(rcCampStreak);
      Result.Aside := FRecords.ValueText(rcCampStreak);
    end;
    7, 8, 9:
    begin
      V := I - 7;
      Result.Title := 'Fewest lost hands: ' + FStory.Name(V);
      Result.Detail := FRecords.Detail(FewestLostId(V));
      Result.Aside := FRecords.ValueText(FewestLostId(V));
    end;
    10:
    begin
      Result.Title := 'Campaigns completed';
      Result.Detail := 'Every vampire beaten, start to finish.';
      Result.Aside := IntToStr(FRecords.CampaignsDone);
    end;
    11:
    begin
      Result.Title := 'Hands won';
      Result.Detail := 'Every duel hand you have won.';
      Result.Aside := IntToStr(FRecords.CampaignWins);
    end;
  end;
end;

end.
