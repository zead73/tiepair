program TestController;

{ The game's flow through GameController, the way both front ends use it: taps,
  buttons, scenes and saving. No window. }

{$mode objfpc}{$H+}

uses SysUtils, Types, Classes, Cards, Pyramid, Inventory, Session, Stage, Story, Vampires, Specials,
  Campaign, Duel, DuelSession, DuelInfo, Settings, HandFile, CampaignSlots, Storage, Records, Trophies, Cosmetics, Relics, GameController
  {$IFDEF PAS2JS}, JsCompat{$ENDIF};

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

{ A rigged deal that is a real, believable hand (52 different cards, so it survives
  saving and loading) and clears by tapping cards 27 down to 0: pairs one after the other
  (27 and 26, 25 and 24, ...) and a King on its own where a row has an odd card out
  (21, 10, 3 and 0). Twelve pairs (two suits of each of the six sums) and four Kings
  make the pyramid; the other 24 cards are the stock. }
type
  TDecks = class
  public
    function Next: TDeck;
  end;

function TDecks.Next: TDeck;
const
  PairIdx: array[0..11, 0..1] of Integer = ((27, 26), (25, 24), (23, 22), (20, 19), (18, 17), (16, 15),
    (14, 13), (12, 11), (9, 8), (7, 6), (5, 4), (2, 1));
  KingIdx: array[0..3] of Integer = (21, 10, 3, 0);
var
  A: TCardArray;
  Used: array[0..3, 1..13] of Boolean;
  K, R, Su, Rk: Integer;
begin
  SetLength(A, 52);
  for Su := 0 to 3 do
    for R := 1 to 13 do Used[Su, R] := False;
  for K := 0 to 11 do
  begin
    Rk := 1 + K mod 6;
    Su := K div 6;
    A[PairIdx[K, 0]].Suit := TSuit(Su); A[PairIdx[K, 0]].Rank := Rk; A[PairIdx[K, 0]].FaceUp := False;
    A[PairIdx[K, 1]].Suit := TSuit(Su); A[PairIdx[K, 1]].Rank := 13 - Rk; A[PairIdx[K, 1]].FaceUp := False;
    Used[Su, Rk] := True;
    Used[Su, 13 - Rk] := True;
  end;
  for K := 0 to 3 do
  begin
    A[KingIdx[K]].Suit := TSuit(K);
    A[KingIdx[K]].Rank := 13;
    A[KingIdx[K]].FaceUp := False;
    Used[K, 13] := True;
  end;
  K := 28;
  for Su := 0 to 3 do
    for R := 1 to 13 do
      if not Used[Su, R] then
      begin
        A[K].Suit := TSuit(Su);
        A[K].Rank := R;
        A[K].FaceUp := False;
        Inc(K);
      end;
  Result := TDeck.CreateFromCards(A);
end;

type
  TWatcher = class
  public
    Changes, Quits: Integer;
    procedure OnChange;
    procedure OnQuit;
  end;

procedure TWatcher.OnChange;
begin
  Inc(Changes);
end;

procedure TWatcher.OnQuit;
begin
  Inc(Quits);
end;

function StoryPath: string;
begin
{$IFDEF PAS2JS}
  Result := 'assets/story/story.ini';
{$ELSE}
  Result := ExtractFilePath(ParamStr(0)) + '../assets/story/story.ini';
{$ENDIF}
end;

procedure WipeStore;
var
  N: Integer;
begin
  StoreDelete(DefaultInventoryFile);
  StoreDelete(DefaultCampaignFile);
  StoreDelete(DefaultSettingsFile);
  StoreDelete(DefaultTrophiesFile);
  StoreDelete(DefaultRecordsFile);
  StoreDelete(AutoSaveFile(gmFreePlay));
  StoreDelete(AutoSaveFile(gmCampaign));
  for N := 1 to SlotCount do StoreDelete(SlotFile(N));
  for N := 1 to SlotCount do StoreDelete(CampaignSlotFile(N));
end;

function NewCtl(St: TStory; D: TDecks; W: TWatcher): TGameController;
begin
  Result := TGameController.Create(St);
  Result.OnChange := @W.OnChange;
  Result.DeckProvider := @D.Next;
  Result.Session.HazardsOn := False;       { the vampires' tricks have their own tests }
  Result.SetViewport(1520, 584);
end;

{ Lets any running deal, fade or effect finish by itself (a scene that is
  waiting for a click stays as it is). }
procedure RunOut(C: TGameController);
var
  I: Integer;
begin
  for I := 1 to 2000 do
  begin
    if not C.NeedsTicks then Exit;
    if C.InScene and C.Stage.WaitingForClick then Exit;
    C.Tick(50);
  end;
end;

{ Taps the visible top-centre of a card. }
procedure TapCard(C: TGameController; I: Integer);
var
  R: TRect;
begin
  R := C.CardRect(I);
  C.Tap((R.Left + R.Right) div 2, R.Top + C.Scaled(10));
end;

procedure ClearBoard(C: TGameController);
var
  I: Integer;
begin
  for I := 27 downto 0 do TapCard(C, I);
end;

{ In a scene: let each line fade in, then click, until the scene is over. }
procedure ClickThrough(C: TGameController);
var
  N: Integer;
begin
  for N := 1 to 200 do
  begin
    RunOut(C);
    if not C.InScene then Exit;
    C.Tap(10, 10);
    C.Tick(50);                            { the click lets the line fade out }
  end;
end;

procedure TestLayout;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  I: Integer;
  R: TRect;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    for I := 0 to PyramidSize - 1 do
    begin
      R := C.CardRect(I);
      Check((R.Left >= 0) and (R.Top >= 0) and (R.Right <= 1520) and (R.Bottom <= 584),
        'card ' + IntToStr(I) + ' is inside the drawing area');
    end;
    R := C.StockRect;
    Check((R.Left >= 0) and (R.Bottom <= 584) and (R.Right > R.Left), 'the stock is on the table');
    Check(C.WasteRect.Left > C.StockRect.Right - 1, 'the waste is beside the stock');
    Check(C.PanelPlacement = ppLeft, 'Free Play has the side panel too (your stats)');
    Check((C.PanelRect.Right - C.PanelRect.Left) >= 170, 'with a panel rectangle');
    Check(C.CardRect(0).Left > C.PanelRect.Right, 'and the table is to the right of it');
    Check(not C.DuelInfo.Active, 'but there is no duel to show in Free Play');
    { the scale follows the area }
    C.SetViewport(760, 292);
    Check(C.Scale < 1.2, 'a smaller area gives a smaller scale');
    C.SetViewport(1520, 584);
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

procedure TestFreePlay;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  U: TUiState;
  PS: TPanelStats;
  Coins0: Integer;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    Check(W.Changes > 0, 'the front end is told about changes');
    Check(C.NeedsTicks and (C.TableMode = tmDealing), 'a new hand deals with an animation');
    U := C.GetUi;
    Check(U.CanSkip and not U.InScene, 'the deal can be skipped');
    Check(not U.UndoEnabled and not U.HintEnabled, 'no undo or hint while dealing');
    Check(U.StoreEnabled, 'a fresh deal being shown can still go to the Store');
    C.ActionOpenStore;
    Check((C.Overlay = okStore) and not C.NeedsTicks, 'asking for the Store during the deal finishes the deal and opens it');
    C.ActionCloseOverlay;
    C.KeyPress(False);
    Check(not C.NeedsTicks, 'any key skips the deal');
    Check(C.TableMode = tmNormal, 'then the table shows');
    U := C.GetUi;
    Check(Pos('Coins', U.StatusText) = 0, 'the stats are in the side panel, not the status line');
    Check(Pos('Stock', U.StatusText) = 0, 'none of them');
    PS := C.PanelStats;
    Check((PS.Coins = StartingCoins) and (PS.Remaining = 28) and (PS.Stock = StockStart), 'the panel has the coins, the cards left and the stock');
    Check(PS.FreePlay and (PS.PayNow = WinCoins), 'and what the hand pays in Free Play');
    C.SetViewport(500, 584);                { no room for a panel: the status line carries them }
    Check(C.PanelPlacement = ppNone, 'a narrow window has no panel');
    U := C.GetUi;
    Check((Pos('Coins: 50', U.StatusText) > 0) and (Pos('This hand pays', U.StatusText) > 0),
      'then the status line shows the stats again');
    C.SetViewport(1520, 584);
    U := C.GetUi;
    Check(U.ShopOpen and U.StoreEnabled, 'a fresh hand: the shop is open');
    Check(U.MenuCaption = 'Menu', 'the toolbar has a Menu button');

    { a tap on the stock is a miss when a card could have been played }
    C.Tap(C.StockRect.Left + 5, C.StockRect.Top + 5);
    U := C.GetUi;
    Check(Pos('You missed a move', U.StatusText) > 0, 'drawing with a move available is a miss');
    Check(C.NeedsTicks, 'the red flash runs');
    RunOut(C);
    Check(not C.NeedsTicks, 'and ends by itself');
    Check(not U.ShopOpen and not U.StoreEnabled, 'mid-hand: the shop is shut');
    Check(Length(U.ShopClosedReason) > 0, 'with a reason to show');
    C.ActionOpenStore;
    Check(C.Overlay = okNone, 'the Store will not open mid-hand');
    Check(Pos('taken a card', C.GetUi.StatusText) > 0, 'Fenwick says why');

    { win by tapping every card }
    C.ActionNew;
    C.KeyPress(False);
    Coins0 := C.Session.Inventory.Coins;
    ClearBoard(C);
    Check(C.Game.IsWon and (C.TableMode = tmWon), 'tapping the cards wins the hand');
    Check(C.Session.Inventory.Coins = Coins0 + WinCoins, 'and pays the reward');
    Check(Pos('YOU WIN', C.GetUi.StatusText) > 0, 'the status line says so');
    Check(C.GetUi.ShopOpen, 'after a win the shop is open');
    Check(Length(C.WinMessage) > 0, 'there is a line for the win picture');
    C.Tap(5, 5);
    Check(not C.Game.IsWon, 'a click on the win screen starts a new hand');
    Check(C.NeedsTicks, 'with the deal animation');
    RunOut(C);
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

procedure TestResume;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  Left: Integer;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    TapCard(C, 27);
    TapCard(C, 26);
    Left := C.Game.CardsLeft;
    Check(Left < 28, 'some cards were played');
  finally
    C.Free;
  end;
  C := NewCtl(St, D, W);
  try
    C.Start;
    Check(C.Game.CardsLeft = Left, 'the next run puts the hand back');
    Check(Pos('Welcome back', C.GetUi.StatusText) > 0, 'and says so');
    Check(not C.NeedsTicks, 'with no deal animation');
    Check(C.GetUi.ShopOpen and C.GetUi.StoreEnabled, 'the Store is open at the start of a restored hand');
    C.ActionOpenStore;
    Check(C.Overlay = okStore, 'and opens');
    C.ActionCloseOverlay;
    TapCard(C, 25);
    TapCard(C, 24);
    Check(not C.GetUi.ShopOpen, 'but the first move shuts it again');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

{ A row's button, tapped by its centre. }
procedure TapButton(C: TGameController; I: Integer);
var
  R: TRect;
begin
  R := C.OverlayButtonRect(I);
  C.Tap((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
end;

procedure TapRowText(C: TGameController; I: Integer);
var
  R: TRect;
begin
  R := C.OverlayRowRect(I);
  C.Tap(R.Left + 10, (R.Top + R.Bottom) div 2);
end;

procedure TapLeave(C: TGameController);
var
  R: TRect;
begin
  R := C.OverlayLeaveRect;
  C.Tap((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
end;

function Inside(const R, Outer: TRect): Boolean;
begin
  Result := (R.Left >= Outer.Left) and (R.Top >= Outer.Top) and (R.Right <= Outer.Right)
    and (R.Bottom <= Outer.Bottom) and (R.Right > R.Left) and (R.Bottom > R.Top);
end;

procedure TestStoreLayout;
const
  Sizes: array[0..4, 0..1] of Integer = ((1520, 584), (800, 534), (1024, 640), (768, 900), (375, 700));
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  N, I, J: Integer;
  View, Panel: TRect;
  Overlap: Boolean;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    for N := 0 to High(Sizes) do
    begin
      C.SetViewport(Sizes[N, 0], Sizes[N, 1]);
      View := Rect(0, 0, Sizes[N, 0], Sizes[N, 1]);
      C.ActionOpenStore;
      Panel := C.OverlayPanelRect;
      Check(Inside(Panel, View), 'size ' + IntToStr(N) + ': the panel is on screen');
      Check(Inside(C.OverlayPortraitRect, Panel), 'size ' + IntToStr(N) + ': his portrait is in the panel');
      Check(Inside(C.OverlaySpeechRect, Panel), 'size ' + IntToStr(N) + ': his words are in the panel');
      Check(Inside(C.OverlayLeaveRect, Panel), 'size ' + IntToStr(N) + ': the Leave button is in the panel');
      Check(C.OverlayRowCount = StoreGoodCount, 'size ' + IntToStr(N) + ': every good has a row');
      Overlap := False;
      for I := 0 to C.OverlayRowCount - 1 do
      begin
        Check(Inside(C.OverlayRowRect(I), Panel), 'size ' + IntToStr(N) + ': row ' + IntToStr(I) + ' is in the panel');
        Check(Inside(C.OverlayButtonRect(I), C.OverlayRowRect(I)), 'size ' + IntToStr(N) + ': its button is in its row');
        Check(C.OverlayButtonRect(I).Bottom - C.OverlayButtonRect(I).Top >= 24, 'size ' + IntToStr(N) + ': a button you can hit');
        for J := I + 1 to C.OverlayRowCount - 1 do
          if (C.OverlayRowRect(I).Bottom > C.OverlayRowRect(J).Top) then Overlap := True;
      end;
      Check(not Overlap, 'size ' + IntToStr(N) + ': rows do not overlap');
      Check(C.OverlayRowRect(C.OverlayRowCount - 1).Bottom <= C.OverlayLeaveRect.Top, 'size ' + IntToStr(N) + ': the list ends above the Leave button');
      C.ActionCloseOverlay;
      C.ActionOpenCards;
      Check(Inside(C.OverlayPanelRect, View) and (C.OverlayRowCount = SpecialCount), 'size ' + IntToStr(N) + ': the card tray fits');
      Check(Inside(C.OverlayRowRect(SpecialCount - 1), C.OverlayPanelRect), 'size ' + IntToStr(N) + ': its last row too');
      C.ActionCloseOverlay;
    end;
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

procedure TestStore;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  Intro: TStringArray;
  I, Coins0: Integer;
  Row: TOverlayRow;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    Check(C.GetUi.StoreEnabled and (C.GetUi.StoreCaption = 'Store'), 'a fresh hand: the Store is open');
    Intro := St.FenwickIntro;
    Check(Length(Intro) >= 2, 'test set-up: Fenwick has an introduction');
    C.ActionOpenStore;
    Check(C.Overlay = okStore, 'the Store opens');
    Check(C.ShopkeeperName = 'Fenwick Grimm', 'run by Fenwick Grimm');
    Check(C.OverlayLine = Intro[0], 'the first visit starts with his introduction');
    Check(C.OverlayHint = 'tap to go on', 'which asks for a tap');
    for I := 0 to C.OverlayRowCount - 1 do
      Check(not C.OverlayRow(I).ButtonEnabled, 'row ' + IntToStr(I) + ': nothing sells during the introduction');
    for I := 1 to High(Intro) do
    begin
      C.Tap(300, 300);
      Check(C.OverlayLine = Intro[I], 'a tap brings introduction line ' + IntToStr(I + 1));
    end;
    C.Tap(300, 300);
    Check(C.OverlayHint = '', 'the introduction ends');
    Check(C.OverlayLine = St.FenwickGreet(0), 'and he greets the customer');
    Check(C.OverlayRowCount = StoreGoodCount, 'the shop lists everything');
    Row := C.OverlayRow(Ord(skWild));
    Check((Row.Title = SpecialName[skWild]) and (Row.Aside = Format('%d coins', [SpecialPrice[skWild]])), 'a card row shows its name and price');
    Check(C.OverlayRow(ArtUndo).Title <> '', 'and the undo cards are sold here too');
    Check(C.OverlayRow(ArtHint).Title <> '', 'and the hint cards');

    { a tap on a row's text: Fenwick pitches it }
    TapRowText(C, Ord(skStake));
    Check(C.OverlayLine = St.FenwickPitch('stake'), 'tapping a good gets his pitch');
    Check(C.OverlayRow(Ord(skStake)).Selected, 'and marks it');
    Check(C.Session.Inventory.SpecialCards(skStake) = 0, 'without buying it');

    { buying }
    Coins0 := C.Session.Inventory.Coins;
    Check(C.OverlayRow(Ord(skSeer)).ButtonEnabled, 'a card you can afford has a Buy button');
    TapButton(C, Ord(skSeer));
    Check(C.Session.Inventory.SpecialCards(skSeer) = 1, 'buying works');
    Check(C.Session.Inventory.Coins = Coins0 - SpecialPrice[skSeer], 'at the fixed price');
    Check(C.OverlayLine = St.FenwickBought(0), 'and he says so');
    Check(Pos('You have 1', C.OverlayRow(Ord(skSeer)).Detail) > 0, 'the row shows how many you own');
    Check(Pos(IntToStr(C.Session.Inventory.Coins), C.OverlayFooter) > 0, 'and the footer your coins');
    Check(not C.OverlayRow(Ord(skDawn)).ButtonEnabled, 'a card you can no longer afford has no Buy button (Dawn)');
    Coins0 := C.Session.Inventory.Coins;
    TapButton(C, Ord(skDawn));
    Check((C.Session.Inventory.SpecialCards(skDawn) = 0) and (C.Session.Inventory.Coins = Coins0), 'tapping it buys nothing');
    TapButton(C, ArtHint);
    Check((C.Session.Inventory.HintCards > 0) or (C.Session.Inventory.Coins < HintPackCost), 'hint cards can be bought here');

    { leaving }
    TapLeave(C);
    Check(C.Overlay = okNone, 'Leave closes the Store');
    Check(Pos(St.FenwickLeave, C.GetUi.StatusText) > 0, 'with his parting words');
    C.ActionOpenStore;
    Check(C.OverlayLine = St.FenwickGreet(1), 'the second visit has no introduction, just a greeting');
    C.KeyPress(True);
    Check(C.Overlay = okNone, 'Esc closes it');
    C.ActionOpenStore;
    C.Tap(3, 3);
    Check(C.Overlay = okNone, 'a tap outside the panel closes it');
    C.ActionOpenStore;
    C.Tap(C.OverlayPanelRect.Left + 4, C.OverlayPanelRect.Top + 4);
    Check(C.Overlay = okStore, 'but a tap on the panel itself does not');
    C.ActionCloseOverlay;
  finally
    C.Free;
  end;
  { Fenwick has been met: the next run does not repeat the introduction }
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    C.ActionOpenStore;
    Check(C.OverlayHint = '', 'the introduction is only shown once');
    Check(C.OverlayLine = St.FenwickGreet(0), 'even after a restart');
    C.ActionCloseOverlay;
    C.ActionEraseEverything;
    RunOut(C);
    C.ActionOpenStore;
    Check(C.OverlayHint = 'tap to go on', 'but Erase everything makes him introduce himself again');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

procedure TestWrapCardStock;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  Row: TOverlayRow;
  Coins0: Integer;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    C.Session.Inventory.AddCoins(500);
    C.ActionOpenStore;
    C.Tap(300, 300); C.Tap(300, 300); C.Tap(300, 300);          { the introduction }
    Row := C.OverlayRow(Ord(skEasyRule));
    Check(not Row.ButtonEnabled, 'Open wrap is not on sale at the start');
    Check((Row.Aside = 'soon') and (Pos('Not in stock', Row.Detail) > 0), 'the row says it is not in stock yet');
    Coins0 := C.Session.Inventory.Coins;
    TapButton(C, Ord(skEasyRule));
    Check(C.Session.Inventory.SpecialCards(skEasyRule) = 0, 'tapping it buys nothing');
    Check(C.Session.Inventory.Coins = Coins0, 'and costs nothing');
    Check(C.OverlayLine = St.FenwickLocked('easyrule'), 'Fenwick says it is not in yet');
    Check(C.OverlayRow(Ord(skDawn)).ButtonEnabled and C.OverlayRow(Ord(skSeer)).ButtonEnabled,
      'the other cards are on sale');
    Row := C.OverlayRow(Ord(skExtraTurn));
    Check(not Row.ButtonEnabled and (Row.Aside = 'soon'), 'the Extra turn is not on sale either: Lucien already gives three');
    TapButton(C, Ord(skExtraTurn));
    Check((C.Session.Inventory.SpecialCards(skExtraTurn) = 0) and (C.OverlayLine = St.FenwickLocked('extraturn')),
      'and Fenwick explains');
    C.ActionCloseOverlay;

    { reaching Carmilla (the first hand without the Easy rule, with fewer turn-overs) puts both on the shelf }
    Check(FirstNormalVampire = 1, 'Carmilla is the first vampire without the Easy rule');
    Check(FirstFewerTurnsVampire = 1, 'and the first with fewer turn-overs');
    C.Campaign.Advance;                                         { Lucien is beaten: on to Carmilla }
    C.ActionOpenStore;
    Check(C.OverlayRow(Ord(skExtraTurn)).ButtonEnabled, 'at Carmilla the Extra turn is on sale');
    Check(C.OverlayRow(Ord(skEasyRule)).ButtonEnabled, 'and so is the Easy rule');
    TapButton(C, Ord(skEasyRule));
    Check(C.Session.Inventory.SpecialCards(skEasyRule) = 1, 'and it can be bought');
    C.ActionCloseOverlay;
  finally
    C.Free;
  end;
  { it stays on the shelf: a new run, and a restarted campaign }
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    C.ActionRestartCampaign;
    RunOut(C);
    Check(C.Campaign.Current = 0, 'the campaign is back at the start');
    C.ActionOpenStore;
    Check(C.OverlayRow(Ord(skEasyRule)).ButtonEnabled and C.OverlayRow(Ord(skExtraTurn)).ButtonEnabled, 'but Open wrap and Full deck are still stocked');
    C.ActionCloseOverlay;
    C.ActionEraseEverything;
    RunOut(C);
    C.Session.Inventory.AddCoins(500);
    C.ActionOpenStore;
    C.Tap(300, 300); C.Tap(300, 300); C.Tap(300, 300);          { his introduction again }
    Check(C.OverlayRow(Ord(skDawn)).ButtonEnabled, 'test set-up: the introduction is over and the shop is live');
    Check(not C.OverlayRow(Ord(skEasyRule)).ButtonEnabled and not C.OverlayRow(Ord(skExtraTurn)).ButtonEnabled, 'Erase everything takes them off the shelf again');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

procedure TestCardTray;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  I, Free: Integer;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    Check(C.GetUi.CardsCaption = 'My cards (0)', 'no cards yet');
    C.ActionOpenCards;
    Check((C.Overlay = okCards) and (C.OverlayRowCount = SpecialCount), 'the tray lists the six kinds');
    for I := 0 to SpecialCount - 1 do
      Check(not C.OverlayRow(I).ButtonEnabled, 'row ' + IntToStr(I) + ': nothing to use yet');
    C.ActionCloseOverlay;
    C.Session.Inventory.AddSpecial(skSeer, 1);
    C.Session.Inventory.AddSpecial(skStake, 2);
    C.Session.Inventory.AddSpecial(skWild, 1);
    C.Session.Inventory.AddSpecial(skDawn, 1);
    Check(C.GetUi.CardsCaption = 'My cards (5)', 'the button counts them');
    C.ActionOpenCards;
    Check(C.OverlayRow(Ord(skSeer)).ButtonEnabled and C.OverlayRow(Ord(skStake)).ButtonEnabled, 'owned cards that can be used are on');
    Check(C.OverlayRow(Ord(skDawn)).ButtonEnabled, 'Dawn is on: a turn-over to add, the Easy rule to switch on');
    Check(C.OverlayRow(Ord(skStake)).ButtonText = 'Use...', 'a card that needs a target says so');
    Check(C.OverlayRow(Ord(skStake)).Aside = 'x 2', 'and the row shows how many you own');

    { Seer's eye: no target needed }
    Check(not C.Game.Revealed, 'before Seer''s eye the stock is hidden');
    TapButton(C, Ord(skSeer));
    Check(C.Overlay = okNone, 'using a card closes the tray');
    Check(C.Game.Revealed and (C.Game.StockCount > 0), 'now the top of the stock shows');
    Check(C.Session.Inventory.SpecialCards(skSeer) = 0, 'and the card is spent');
    Check(not C.GetUi.StoreEnabled, 'using a card starts the hand: the Store shuts');

    { Wood Stake: asks for a tap on the table }
    C.ActionOpenCards;
    TapButton(C, Ord(skStake));
    Check(C.GetUi.Targeting and (C.Overlay = okNone), 'the Stake waits for a card');
    Check(Pos('Wood Stake', C.GetUi.StatusText) > 0, 'and the status line says what to do');
    Check(C.CardHighlighted(27) and not C.CardHighlighted(0), 'free cards are outlined, covered ones are not');
    TapCard(C, 0);
    Check(C.GetUi.Targeting, 'a covered card is not a target: still waiting');
    Check(C.Session.Inventory.SpecialCards(skStake) = 2, 'and nothing was spent');
    TapCard(C, 27);
    Check(not C.GetUi.Targeting and C.Game.Removed(27), 'a free card is destroyed');
    Check(C.Session.Inventory.SpecialCards(skStake) = 1, 'for one Stake');
    Check(C.Game.Stakes = 1, 'counted as a stake');

    { cancelling: a tap elsewhere, Esc, New Game }
    C.ActionOpenCards;
    TapButton(C, Ord(skStake));
    C.Tap(5, 5);
    Check(not C.GetUi.Targeting and (C.Session.Inventory.SpecialCards(skStake) = 1), 'a tap elsewhere cancels, keeping the card');
    C.ActionOpenCards;
    TapButton(C, Ord(skStake));
    C.KeyPress(True);
    Check(not C.GetUi.Targeting, 'Esc cancels too');
    C.ActionOpenCards;
    TapButton(C, Ord(skStake));
    C.ActionCancel;
    Check(not C.GetUi.Targeting, 'so does Cancel');
    C.ActionOpenCards;
    TapButton(C, Ord(skStake));
    C.ActionNew;
    Check(not C.GetUi.Targeting, 'and starting a new game');
    RunOut(C);

    { a Wood Stake that wins in Free Play pays }
    C.Session.Inventory.AddSpecial(skStake, 40);
    C.KeyPress(False);
    Free := 0;
    while not C.Game.IsWon and (Free < 40) do
    begin
      Inc(Free);
      C.ActionOpenCards;
      TapButton(C, Ord(skStake));
      for I := 0 to PyramidSize - 1 do
        if C.Game.IsFree(I) then
        begin
          TapCard(C, I);
          Break;
        end;
    end;
    Check(C.Game.IsWon, 'staking every card clears the board');
    Check(C.TableMode = tmWon, 'and the win screen shows');
    Check(Pos('YOU WIN', C.GetUi.StatusText) > 0, 'and it paid');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

procedure TestStakesInDuel;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  I, Tries: Integer;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    C.ActionToggleMode;
    ClickThrough(C);
    RunOut(C);
    Check(C.Duel.Duel.State = dsPlaying, 'a duel hand');
    C.Session.Inventory.AddSpecial(skStake, 40);
    Tries := 0;
    while (C.Duel.Duel.State = dsPlaying) and (Tries < 40) do
    begin
      Inc(Tries);
      C.ActionOpenCards;
      TapButton(C, Ord(skStake));
      for I := 0 to PyramidSize - 1 do
        if C.Game.IsFree(I) and not C.Game.Removed(I) then
        begin
          TapCard(C, I);
          Break;
        end;
    end;
    Check(C.Duel.Duel.State = dsHit, 'staking the board wins a duel hand');
    Check(C.InScene, 'and its hit scene plays');
    Check(C.Duel.Campaign.Wins = 1, 'the win counts');
    C.ActionOpenCards;
    Check(C.Overlay = okNone, 'no card tray during a scene');
    ClickThrough(C);
    RunOut(C);
    Check(not C.GetUi.Targeting, 'nothing is left waiting');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

procedure TestRecordsFlow;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  U: TUiState;
  I: Integer;
begin
  WipeStore;
  StoreDelete(DefaultRecordsFile);
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    U := C.GetUi;
    Check(not U.AskInitials and (U.RecordsCaption = 'Records'), 'nothing to ask at the start');

    { a Free Play win breaks the first records }
    ClearBoard(C);
    Check(C.Game.IsWon, 'test set-up: a won hand');
    U := C.GetUi;
    Check(U.AskInitials, 'a broken record asks for initials');
    Check(Pos('Free Play longest streak', U.InitialsPrompt) > 0, 'and says which');
    Check(U.InitialsDefault = '', 'with nothing to suggest the first time');
    C.ActionSubmitInitials('sh');
    Check(not C.GetUi.AskInitials, 'answered');
    Check((C.Records.Value(rcFreeStreak) = 16) and (C.Records.Holder(rcFreeStreak) = 'SH'), 'the streak record is the whole board (16 plays), held by SH');
    Check((C.Records.FreeWins = 1) and (C.Records.FreePerfect = 1), 'one perfect win');

    { the second win breaks the run record only; the initials are suggested }
    C.Tap(5, 5);                                 { the win screen: a new hand }
    RunOut(C);
    ClearBoard(C);
    U := C.GetUi;
    Check(U.AskInitials and (Pos('most wins in a row', U.InitialsPrompt) > 0), 'two in a row is a record');
    Check(U.InitialsDefault = 'SH', 'the last initials are suggested');
    C.ActionSubmitInitials('');
    Check(C.Records.Holder(rcFreeRun) = '---', 'skipping gives dashes');

    { a fresh deal dropped does not end the run; a hand under way does }
    C.Tap(5, 5);
    RunOut(C);
    C.ActionNew;
    RunOut(C);
    Check(C.Records.FreeRun = 2, 'dropping a hand nobody started does not end the run');
    TapCard(C, 27);
    TapCard(C, 26);
    C.ActionNew;
    RunOut(C);
    Check(C.Records.FreeRun = 0, 'dropping a hand that was under way does');

    { the records page }
    C.ActionOpenRecords;
    Check((C.Overlay = okRecords) and (C.OverlayRowCount = 12), 'the records page has twelve lines');
    Check(C.OverlayRow(0).Header and (C.OverlayRow(0).Title = 'FREE PLAY'), 'a Free Play heading');
    Check(C.OverlayRow(5).Header and (C.OverlayRow(5).Title = 'CAMPAIGN'), 'and a Campaign heading');
    Check(C.OverlayRow(1).Aside = '16  SH', 'the streak with its holder');
    Check(C.OverlayRow(4).Aside = '2', 'two hands won');
    Check(Pos(St.Name(0), C.OverlayRow(7).Title) > 0, 'the fewest-lost lines name the vampires');
    Check(C.OverlayRow(7).Aside = '-', 'an unset record is a dash');
    for I := 0 to C.OverlayRowCount - 1 do
      Check(C.OverlayRow(I).ButtonText = '', 'row ' + IntToStr(I) + ' has no button');
    C.ActionCloseOverlay;
  finally
    C.Free;
  end;
  { the records survive a restart }
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    Check((C.Records.Value(rcFreeStreak) = 16) and (C.Records.FreeWins = 2), 'saved on disk');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

procedure TestCampaignRecords;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  I: Integer;
begin
  WipeStore;
  StoreDelete(DefaultRecordsFile);
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    C.ActionToggleMode;
    ClickThrough(C);
    RunOut(C);
    C.ActionNew;                                 { one lost hand against Jack }
    ClickThrough(C);
    RunOut(C);
    for I := 1 to WinsToKill do
    begin
      ClearBoard(C);
      Check(not C.GetUi.AskInitials or not C.InScene, 'no question during a scene');
      ClickThrough(C);
      RunOut(C);
    end;
    Check(C.Records.CampaignWins = WinsToKill, 'five hands won in the campaign');
    Check(C.Records.FreeWins = 0, 'none counted for Free Play');
    Check(C.Records.Value(FewestLostId(0)) = 1, 'Jack fell after one lost hand');
    Check(C.Records.Value(rcCampStreak) = 16, 'with a whole-board streak');
    Check(C.GetUi.AskInitials, 'asked once the story scenes are over');
    Check(Pos('against ' + St.Name(0), C.GetUi.InitialsPrompt) > 0, 'naming the vampire');
    C.ActionSubmitInitials('KO');
    Check(C.Records.Holder(FewestLostId(0)) = 'KO', 'initials recorded');
    Check(C.Records.CampaignsDone = 0, 'the campaign is not complete yet');
    C.ActionOpenRecords;
    Check(C.OverlayRow(7).Aside = '1  KO', 'shown on the page');
    C.ActionCloseOverlay;
    C.ActionEraseEverything;
    RunOut(C);
    Check((C.Records.CampaignWins = 0) and not C.Records.IsSet(rcCampStreak), 'Erase everything clears the records');
    Check(not C.GetUi.AskInitials, 'and nothing is left to ask');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

procedure TestSlots;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  Left: Integer;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    Check(not C.SlotInfo(1).Exists, 'slot 1 starts empty');
    TapCard(C, 27);
    Left := C.Game.CardsLeft;
    C.ActionSaveSlot(1);
    Check(C.SlotInfo(1).Exists and (C.SlotInfo(1).CardsLeft = Left), 'a saved slot shows its cards');
    Check(Pos('saved to slot 1', C.GetUi.StatusText) > 0, 'and the status says so');
    C.ActionNew;
    RunOut(C);
    Check(C.Game.CardsLeft = 28, 'a new hand');
    C.ActionLoadSlot(1);
    Check(C.Game.CardsLeft = Left, 'loading the slot brings the hand back');
    C.ActionLoadSlot(2);
    Check(Pos('could not be read', C.GetUi.StatusText) > 0, 'an empty slot is reported, not loaded');
    Check(C.Game.CardsLeft = Left, 'and changes nothing');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

procedure TestCampaign;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  U: TUiState;
  I, Coins0: Integer;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    C.ActionToggleMode;
    Check(C.CampaignMode and C.InScene, 'the campaign opens with its intro scene');
    U := C.GetUi;
    Check(U.MenuCaption = 'Menu', 'the Menu button is always the same');
    Check(U.CanSkip and U.InScene, 'the scene can be skipped');
    RunOut(C);
    Check(C.Stage.Backdrop = sbHouse, 'the story opens on the picture of the house');
    I := 0;
    while (C.Stage.Backdrop = sbHouse) and (I < 20) do     { click through the opening lines }
    begin
      C.Tap(10, 10);
      C.Tick(50);                                          { the click lets the line fade out }
      RunOut(C);
      Inc(I);
    end;
    Check(C.Stage.Backdrop = sbDialogue, 'then the dark room, where the vampire waits');
    Check(not U.UndoEnabled and not U.SaveEnabled, 'no undo or save in a scene');
    { click through every line }
    ClickThrough(C);
    Check(not C.InScene, 'clicking past the last line ends the intro');
    RunOut(C);
    Check(C.Duel.Duel.State = dsPlaying, 'a duel hand is being played');
    Check(C.PanelPlacement = ppLeft, 'with the panel on the left');
    Check((C.PanelRect.Right - C.PanelRect.Left) >= 170, 'and a panel rectangle');
    Check(C.DuelInfo.Active and (C.DuelInfo.Vampire = 0), 'the panel is about the first vampire');

    { five wins kill Jack }
    for I := 1 to WinsToKill - 1 do
    begin
      Coins0 := C.Session.Inventory.Coins;
      ClearBoard(C);
      Check(C.InScene and (C.Duel.Duel.State = dsHit), 'win ' + IntToStr(I) + ' plays the hit scene');
      Check(C.Session.Inventory.Coins = Coins0 + VampireWinCoins[0], 'and was paid at once');
      ClickThrough(C);
      RunOut(C);
      Check(C.Duel.Duel.State = dsPlaying, 'then the next hand');
    end;
    ClearBoard(C);
    Check(C.Duel.Duel.State = dsFatalBlow, 'the fifth win is the fatal blow');
    ClickThrough(C);                         { the blow, the defeat, the next intro }
    RunOut(C);
    Check(C.Duel.Duel.State = dsPlaying, 'then a hand against the next vampire');
    Check(C.Duel.Duel.Vampire = 1, 'the second vampire (Queen)');
    Check(C.Game.MaxRecycles = VampireRecycles[1], 'with his own rules');

    { giving up a hand }
    C.ActionNew;
    Check(C.InScene and (C.Duel.Duel.State = dsFreeRound), 'New Game in a duel concedes: the free round');
    C.KeyPress(True);
    RunOut(C);
    Check(C.Duel.Duel.State = dsPlaying, 'Esc skips the whole scene');

    { narrow screens: no panel, the status line carries the duel }
    C.SetViewport(600, 400);
    Check(C.PanelPlacement = ppNone, 'a narrow window has no panel');
    Check(Pos('Duel:', C.GetUi.StatusText) > 0, 'so the status line has the duel details');
    { tall screens (web): the panel goes under the table }
    C.AllowBottomPanel := True;
    C.SetViewport(768, 1024);
    Check(C.PanelPlacement = ppBottom, 'a tall screen puts the panel underneath');
    Check((C.PanelRect.Top > C.CardRect(27).Bottom) and (C.PanelRect.Bottom <= 1024),
      'below the table and inside the screen');
    Check(C.StockRect.Bottom < C.PanelRect.Top, 'the stock is above the panel');
    C.SetViewport(1520, 584);

    { back to Free Play }
    C.ActionToggleMode;
    RunOut(C);
    Check(not C.CampaignMode and (C.PanelPlacement = ppLeft), 'Free Play again, with the stats panel');
    Check(C.Game.MaxRecycles = DefaultRecycles, 'with the ordinary rules');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

{ Quitting mid-duel: the next run resumes the hand (and the wins), with no intro. }
procedure TestResumeCampaign;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  Left: Integer;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    C.ActionToggleMode;
    ClickThrough(C);
    RunOut(C);
    ClearBoard(C);                          { win 1 }
    ClickThrough(C);
    RunOut(C);
    TapCard(C, 27);
    Left := C.Game.CardsLeft;
    Check(C.Duel.Campaign.Wins = 1, 'one win in');
  finally
    C.Free;
  end;
  C := NewCtl(St, D, W);
  try
    C.Start;                               { opens in the campaign, as left }
    Check(C.CampaignMode, 'the game reopens in the campaign');
    Check(C.Game.CardsLeft = Left, 'with the duel hand put back');
    Check(C.TableMode <> tmDealing, 'shown at once, not dealt again');
    Check(C.Duel.Campaign.Wins = 1, 'and the win');
    Check(not C.InScene, 'with no intro scene');
    Check(Pos('Welcome back', C.GetUi.StatusText) > 0, 'and a welcome back');
    RunOut(C);                              { the fade in }
    { a quit between hands (after a win, during its scene) skips the intro too }
    ClearBoard(C);
    Check(C.InScene and (C.Duel.Duel.State = dsHit), 'win 2: the hit scene');
  finally
    C.Free;
  end;
  C := NewCtl(St, D, W);
  try
    C.Start;
    Check(C.CampaignMode and not C.InScene or C.NeedsTicks, 'quitting during a hit scene');
    RunOut(C);
    Check(C.Duel.Duel.State = dsPlaying, 'resumes straight into a hand');
    Check(C.Duel.Campaign.Wins = 2, 'with both wins counted');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

procedure TestStartOver;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    ClearBoard(C);                          { Free Play win: coins 75 }
    C.Tap(5, 5);
    RunOut(C);
    C.ActionSaveSlot(2);
    C.ActionToggleMode;
    ClickThrough(C);
    RunOut(C);
    ClearBoard(C);
    ClickThrough(C);
    RunOut(C);
    Check(C.Duel.Campaign.Wins = 1, 'a win in the campaign');
    C.ActionRestartCampaign;
    Check(C.Duel.Campaign.Wins = 0, 'restart: no wins');
    Check(C.Session.Inventory.Coins > StartingCoins, 'but the coins are kept');
    Check(C.InScene, 'and the opening plays again');
    ClickThrough(C);
    RunOut(C);
    C.ActionEraseEverything;
    RunOut(C);
    Check(not C.CampaignMode, 'erasing everything goes back to Free Play');
    Check(C.Session.Inventory.Coins = StartingCoins, 'with the starting coins');
    Check(C.Session.Inventory.UndoCards = 0, 'and no cards');
    Check(not C.SlotInfo(2).Exists, 'and no saved slots');
    Check(C.Duel.Campaign.Current = 0, 'and the campaign at the start');
    Check(Pos('Everything was erased', C.GetUi.StatusText) > 0, 'with a message');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

{ Taps the middle of menu button I. }
procedure TapMenuButton(C: TGameController; I: Integer);
var
  R: TRect;
begin
  R := C.MenuButtonRect(I);
  C.Tap((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
end;

procedure TestMenu;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  U: TUiState;
  I, Coins0: Integer;
  Dim0: Double;

  procedure TypeText(const T: string);
  var
    J: Integer;
  begin
    for J := 1 to Length(T) do C.TypeChar(T[J]);
  end;

begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.StartWithMenu;
    Check(C.MenuOpen, 'the program opens on the start menu');
    Check(C.MenuButtonCount = 7, 'seven buttons where the program cannot quit (the web page)');
    Check((C.MenuButtonCaption(0) = 'Campaign') and (C.MenuButtonCaption(1) = 'Free Play')
      and (C.MenuButtonCaption(2) = 'Save game') and (C.MenuButtonCaption(3) = 'Load game')
      and (C.MenuButtonCaption(4) = 'Rules') and (C.MenuButtonCaption(5) = 'Style') and (C.MenuButtonCaption(6) = 'Relics'),
      'Campaign, Free Play, Save game, Load game, Rules, Style and Relics');
    Check(not C.NeedsTicks, 'nothing animates behind the menu');
    U := C.GetUi;
    Check(not U.StoreEnabled and not U.CardsEnabled and not U.UndoEnabled and not U.RecordsEnabled and not U.SaveEnabled,
      'the toolbar is dead while the menu is up');
    C.ActionOpenStore;
    C.ActionNew;
    Check(C.MenuOpen and (C.Overlay = okNone), 'the buttons do nothing behind the menu');
    Check(not C.Session.HandStarted, 'no hand has been started behind the menu');

    { every button sits inside the drawing area and they do not overlap }
    for I := 0 to C.MenuButtonCount - 1 do
    begin
      Check((C.MenuButtonRect(I).Left >= 0) and (C.MenuButtonRect(I).Right <= 1520)
        and (C.MenuButtonRect(I).Top >= 0) and (C.MenuButtonRect(I).Bottom <= 584), 'button ' + IntToStr(I) + ' is on screen');
      if I > 0 then
        Check((C.MenuButtonRect(I).Top >= C.MenuButtonRect(I - 1).Bottom)
          or ((C.MenuButtonRect(I).Top = C.MenuButtonRect(I - 1).Top) and (C.MenuButtonRect(I).Left >= C.MenuButtonRect(I - 1).Right)),
          'and below, or beside, the one before');
    end;
    C.SetViewport(375, 560);               { a phone held upright }
    for I := 0 to C.MenuButtonCount - 1 do
      Check((C.MenuButtonRect(I).Left >= 0) and (C.MenuButtonRect(I).Right <= 375)
        and (C.MenuButtonRect(I).Bottom <= 560), 'button ' + IntToStr(I) + ' fits a phone');
    C.SetViewport(1520, 584);

    { the hidden cheat: any capitals, works every time, nothing else does }
    Coins0 := C.Session.Inventory.Coins;
    TypeText('hello there');
    Check(C.Session.Inventory.Coins = Coins0, 'ordinary typing gives nothing');
    TypeText('coffeeisNOTblood');
    Check(C.Session.Inventory.Coins = Coins0 + 900, 'the secret word gives 900 coins');
    Check(Pos('900', C.MenuNote) > 0, 'and the menu says so: ' + C.MenuNote);
    TypeText('CoffeeIsNotBlood');
    Check(C.Session.Inventory.Coins = Coins0 + 1800, 'it works every time');
    TypeText('xxcoffeeisnotblo');
    Check(C.Session.Inventory.Coins = Coins0 + 1800, 'a word that is one letter short gives nothing');
    TypeText('x');
    Check(C.Session.Inventory.Coins = Coins0 + 1800, 'and the wrong ending gives nothing');
    TypeText('coffeeisnotblood');
    Check(C.Session.Inventory.Coins = Coins0 + 2700, 'but the whole word after any junk does');

    { Free Play }
    TapMenuButton(C, 1);
    Check(not C.MenuOpen and not C.CampaignMode, 'Free Play closes the menu and deals a hand');
    RunOut(C);
    Check(C.Session.Game.CardsLeft = 28, 'a fresh hand is on the table');
    Check(C.Session.Inventory.Coins = Coins0 + 2700, 'the cheat coins stay');
    TypeText('coffeeisnotblood');
    Check(C.Session.Inventory.Coins = Coins0 + 2700, 'typing during play is not a cheat');

    { the Menu button, mid-game }
    TapCard(C, 27);
    TapCard(C, 26);
    Check(C.Session.HandStarted, 'a card was played');
    C.ActionOpenMenu;
    Check(C.MenuOpen, 'the Menu button opens the menu mid-game');
    C.KeyPress(True);
    Check(not C.MenuOpen and (C.Session.Game.CardsLeft = 26), 'Esc goes back to the very same hand');
    C.ActionOpenMenu;
    TapMenuButton(C, 1);
    Check(not C.MenuOpen and (C.Session.Game.CardsLeft = 26) and not C.CampaignMode,
      'choosing the mode you are in goes back to the same hand');

    { Campaign }
    C.ActionOpenMenu;
    TapMenuButton(C, 0);
    Check(not C.MenuOpen and C.CampaignMode and C.InScene, 'Campaign enters the duel with its opening');
    C.ActionOpenMenu;
    Check(not C.NeedsTicks, 'a scene waits while the menu is up');
    Dim0 := C.Stage.Scalar[ssDim];
    for I := 1 to 10 do C.Tick(100);
    Check(C.Stage.Scalar[ssDim] = Dim0, 'and even a stray tick does not move it on');
    C.Tap(10, 10);
    Check(C.MenuOpen, 'a tap outside the buttons does nothing');
    TapMenuButton(C, 1);
    Check(not C.CampaignMode and not C.MenuOpen, 'Free Play from the menu leaves the campaign');
    Check(C.Session.Game.CardsLeft = 26, 'and the Free Play hand is back as it was');
    Check(not (C.GetUi.StoreCaption = ''), 'with its toolbar');

    { Rules: the front end is asked to show them; the table waits until they are closed }
    C.ActionOpenMenu;
    Check(not C.GetUi.ShowRules, 'no rules until asked for');
    TapMenuButton(C, 4);
    Check(C.GetUi.ShowRules and C.MenuOpen, 'the Rules button asks the front end to show the rules');
    C.Tap(C.MenuButtonRect(0).Left + 5, C.MenuButtonRect(0).Top + 5);
    Check(C.MenuOpen, 'taps wait while the rules are up');
    C.KeyPress(True);
    Check(C.MenuOpen and C.GetUi.ShowRules, 'and so does Esc (the front end handles it)');
    Check((C.RulesSectionCount >= 8) and (Length(C.RulesPlainText) > 2000), 'the controller hands over the text');
    C.ActionRulesClosed;
    Check(not C.GetUi.ShowRules and C.MenuOpen, 'closing them leaves the menu as it was');
    C.ActionRulesClosed;
    Check(not C.GetUi.ShowRules, 'closing twice is harmless');

    { Quit }
    C.CanQuit := True;
    C.OnQuit := @W.OnQuit;
    C.ActionOpenMenu;
    Check(C.MenuButtonCount = 8, 'eight buttons where the program can quit');
    Check((C.MenuButtonCaption(4) = 'Rules') and (C.MenuButtonCaption(5) = 'Style') and (C.MenuButtonCaption(6) = 'Relics')
      and (C.MenuButtonCaption(7) = 'Quit'), 'Rules, Style, Relics, then Quit');
    for I := 0 to C.MenuButtonCount - 1 do
      Check((C.MenuButtonRect(I).Left >= 0) and (C.MenuButtonRect(I).Right <= 1520) and (C.MenuButtonRect(I).Bottom <= 584),
        'with Quit as well, button ' + IntToStr(I) + ' is on screen');
    Check((C.MenuButtonRect(5).Left >= C.MenuButtonRect(4).Right) and (C.MenuButtonRect(5).Top = C.MenuButtonRect(4).Top),
      'Style sits beside Rules');
    Check(C.MenuButtonRect(6).Top >= C.MenuButtonRect(5).Bottom, 'Relics has its own row below');
    Check((C.MenuButtonRect(7).Left >= C.MenuButtonRect(6).Right) and (C.MenuButtonRect(7).Top = C.MenuButtonRect(6).Top), 'with Quit beside it');
    TapMenuButton(C, 7);
    Check(W.Quits = 1, 'Quit tells the program to close');
    Check(C.MenuOpen, 'and the menu stays up meanwhile');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;

  { opening on the menu, then Campaign: the opening scene, with no hand resumed
    behind the menu }
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.StartWithMenu;
    C.KeyPress(True);
    Check(C.MenuOpen, 'Esc does nothing on the first menu: there is no game to go back to');
    TapMenuButton(C, 0);
    Check(C.CampaignMode and C.InScene, 'Campaign from the first menu starts the story');
    Check(C.Session.Game.CardsLeft = 28, 'with a hand already dealt for the screen to draw');
    RunOut(C);
    Check(C.Stage.Backdrop = sbHouse, 'on the house');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

{ Taps the Save / Load button of slot-screen row I. }
procedure TapSlotButton(C: TGameController; I: Integer);
var
  R: TRect;
begin
  R := C.OverlayButtonRect(I);
  C.Tap((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
end;

procedure TestSaveSlots;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  I, Left, Coins0, CampLeft: Integer;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.StartWithMenu;
    Check(not C.MenuButtonEnabled(2), 'Save is dimmed before any game has begun');
    Check(C.MenuButtonEnabled(3), 'Load is not');
    TapMenuButton(C, 2);
    Check(C.Overlay = okNone, 'tapping a dimmed Save does nothing');
    TapMenuButton(C, 3);
    Check((C.Overlay = okSlots) and (C.OverlayRowCount = 8), 'Load shows Free Play and campaign slots (two headings, six slots)');
    Check(C.OverlayRow(0).Header and C.OverlayRow(4).Header and (C.OverlayRow(0).Title = 'FREE PLAY') and (C.OverlayRow(4).Title = 'CAMPAIGN'),
      'under their headings');
    for I := 0 to 7 do Check(not C.OverlayRow(I).ButtonEnabled, 'an empty slot cannot be loaded (row ' + IntToStr(I) + ')');
    C.KeyPress(True);
    Check((C.Overlay = okNone) and C.MenuOpen, 'Esc goes back to the menu, not the table');

    { Free Play: save a hand in slot 1 }
    TapMenuButton(C, 1);
    RunOut(C);
    TapCard(C, 27);
    TapCard(C, 26);
    Left := C.Game.CardsLeft;
    C.ActionOpenMenu;
    Check(C.MenuButtonEnabled(2), 'with a hand under way, Save is on');
    TapMenuButton(C, 2);
    Check((C.Overlay = okSlots) and (C.OverlayRowCount = 4) and (C.OverlayRow(0).Title = 'FREE PLAY'),
      'Save lists the slots of the mode being played');
    Check(C.OverlayRow(1).ButtonEnabled and (C.OverlayRow(1).ButtonText = 'Save'), 'an empty slot says Save');
    TapSlotButton(C, 2);
    Check(C.SlotInfo(2).Exists and (C.SlotInfo(2).CardsLeft = Left), 'the hand is in slot 2');
    Check(C.OverlayRow(2).ButtonText = 'Replace', 'which now says Replace');
    Check(Pos('slot 2', C.GetUi.StatusText) > 0, 'and the status line says so: ' + C.GetUi.StatusText);
    C.KeyPress(True);
    C.KeyPress(True);
    Check(not C.MenuOpen, 'Esc twice is back at the table');
    TapCard(C, 25);
    TapCard(C, 24);
    Check(C.Game.CardsLeft = Left - 2, 'play on');

    { load it from the menu }
    C.ActionOpenMenu;
    TapMenuButton(C, 3);
    Check(C.OverlayRow(2).ButtonEnabled and (C.OverlayRow(2).Detail <> 'Empty'), 'slot 2 can be loaded');
    Check(not C.OverlayRow(1).ButtonEnabled, 'slot 1 is still empty');
    TapSlotButton(C, 2);
    Check(not C.MenuOpen and (C.Overlay = okNone) and not C.CampaignMode, 'loading closes the screens and the menu');
    Check(C.Game.CardsLeft = Left, 'and the hand is back as saved');

    { Campaign: dimmed during the opening scene, on once a hand is being played }
    C.ActionOpenMenu;
    TapMenuButton(C, 0);
    Check(C.CampaignMode and C.InScene, 'the campaign opens with its story');
    C.ActionOpenMenu;
    Check(not C.MenuButtonEnabled(2), 'Save is dim in the middle of a scene');
    C.KeyPress(True);
    ClickThrough(C);
    RunOut(C);
    Check(C.Duel.Duel.State = dsPlaying, 'a duel hand is under way');
    TapCard(C, 27);
    TapCard(C, 26);
    CampLeft := C.Game.CardsLeft;
    Coins0 := C.Session.Inventory.Coins;
    C.ActionOpenMenu;
    Check(C.MenuButtonEnabled(2), 'Save is on during a duel hand');
    TapMenuButton(C, 2);
    Check((C.OverlayRowCount = 4) and (C.OverlayRow(0).Title = 'CAMPAIGN'), 'it lists the campaign slots');
    TapSlotButton(C, 3);
    Check(PeekCampaignSlot(3).Exists and (PeekCampaignSlot(3).CardsLeft = CampLeft), 'the duel hand is in campaign slot 3');
    Check(not C.SlotInfo(3).Exists, 'and Free Play slot 3 is untouched');
    C.KeyPress(True);
    C.KeyPress(True);

    { change everything, then rewind }
    TapCard(C, 25);
    TapCard(C, 24);
    C.Session.Inventory.AddCoins(77);
    Check(C.Game.CardsLeft < CampLeft, 'play on');
    C.ActionOpenMenu;
    TapMenuButton(C, 3);
    Check(C.OverlayRow(7).ButtonEnabled and (C.OverlayRow(7).Detail <> 'Empty'), 'campaign slot 3 shows in the Load list');
    Check(Pos('Lucien', C.OverlayRow(7).Detail) > 0, 'with the vampire it was against: ' + C.OverlayRow(7).Detail);
    TapSlotButton(C, 7);
    Check(C.CampaignMode and not C.MenuOpen and (C.Game.CardsLeft = CampLeft), 'the campaign hand is back as saved');
    Check(C.Session.Inventory.Coins = Coins0, 'with the coins of that moment: a true rewind');
    Check(C.DuelInfo.Active and (C.Duel.Duel.State = dsPlaying), 'and the duel is being played');

    { loading a Free Play slot from inside the campaign goes to Free Play }
    C.ActionOpenMenu;
    TapMenuButton(C, 3);
    TapSlotButton(C, 2);
    Check(not C.CampaignMode and (C.Game.CardsLeft = Left), 'a Free Play slot loaded in the campaign leaves it');
    Check(C.Session.PayWinRewards, 'and Free Play pays its flat reward again');
  finally
    C.Free;
  end;

  { a campaign slot loaded straight from the first menu }
  C := NewCtl(St, D, W);
  try
    C.StartWithMenu;
    TapMenuButton(C, 3);
    Check(C.OverlayRow(7).ButtonEnabled, 'the slot is still there after a restart');
    TapSlotButton(C, 7);
    Check(C.CampaignMode and C.DuelInfo.Active and (C.Game.CardsLeft = CampLeft), 'and loads into the campaign');
    Check(C.Session.Inventory.Coins = Coins0, 'with its coins');
    RunOut(C);
    TapCard(C, 25);
    TapCard(C, 24);
    Check(C.Game.CardsLeft < CampLeft, 'the hand can be played');
  finally
    C.Free;
  end;

  { a damaged slot is refused and nothing changes }
  StoreWrite(CampaignSlotFile(1), 'tiepair-campaign-slot 1' + LineEnding + 'junk');
  C := NewCtl(St, D, W);
  try
    C.StartWithMenu;
    TapMenuButton(C, 3);
    Check(not C.OverlayRow(5).ButtonEnabled, 'a damaged slot reads as empty');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

{ Deleting a saved game from the Save / Load pages (asks first). }
procedure TapSlotDelete(C: TGameController; I: Integer);
var
  R: TRect;
begin
  R := C.OverlayButton2Rect(I);
  C.Tap((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
end;

procedure TestDeleteSaves;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.StartWithMenu;
    TapMenuButton(C, 1);
    RunOut(C);
    TapCard(C, 27);
    C.ActionSaveSlot(1);
    C.ActionSaveSlot(3);
    C.ActionOpenMenu;
    TapMenuButton(C, 3);
    Check(C.Overlay = okSlots, 'the Load page');
    Check((C.OverlayRow(1).Button2Text = 'Delete') and C.OverlayRow(1).Button2Enabled, 'a saved slot has a Delete button');
    Check((C.OverlayRow(2).Button2Text = '') and not C.OverlayRow(2).Button2Enabled, 'an empty one has none');
    Check(C.OverlayButton2Rect(1).Right <= C.OverlayButtonRect(1).Left, 'beside the Load button, to its left');
    Check(not C.GetUi.AskDelete, 'nothing is asked yet');

    { ask, and answer no }
    TapSlotDelete(C, 1);
    Check(C.GetUi.AskDelete, 'Delete asks first');
    Check((Pos('slot 1', C.GetUi.DeletePrompt) > 0) and (Pos('Free Play', C.GetUi.DeletePrompt) > 0), 'about this slot: ' + C.GetUi.DeletePrompt);
    TapSlotButton(C, 3);
    C.KeyPress(True);
    Check(C.GetUi.AskDelete and (C.Overlay = okSlots) and C.SlotInfo(3).Exists, 'the page waits for the answer');
    C.ActionAnswerDelete(False);
    Check(not C.GetUi.AskDelete and C.SlotInfo(1).Exists, 'No: the save is kept');

    { yes }
    TapSlotDelete(C, 1);
    C.ActionAnswerDelete(True);
    Check(not C.SlotInfo(1).Exists, 'Yes: the save is gone');
    Check(C.SlotInfo(3).Exists, 'the other slot is not touched');
    Check((C.OverlayRow(1).Detail = 'Empty') and (C.OverlayRow(1).Button2Text = '') and not C.OverlayRow(1).ButtonEnabled,
      'the row now says Empty, with nothing to load or delete');
    Check(Pos('Deleted slot 1', C.GetUi.StatusText) > 0, 'and the status line says so: ' + C.GetUi.StatusText);
    C.ActionAnswerDelete(True);
    Check(C.SlotInfo(3).Exists, 'answering with no question pending does nothing');

    { the Save page has it too }
    C.KeyPress(True);
    TapMenuButton(C, 2);
    Check((C.OverlayRow(3).ButtonText = 'Replace') and (C.OverlayRow(3).Button2Text = 'Delete'), 'Replace and Delete on a used slot');
    TapSlotDelete(C, 3);
    C.ActionAnswerDelete(True);
    Check(not C.SlotInfo(3).Exists, 'deleted from the Save page');
    C.KeyPress(True);
    C.KeyPress(True);

    { a campaign save }
    C.ActionToggleMode;
    ClickThrough(C);
    RunOut(C);
    C.ActionOpenMenu;
    TapMenuButton(C, 2);
    TapSlotButton(C, 2);                         { save the campaign in its slot 2 }
    Check(PeekCampaignSlot(2).Exists, 'test set-up: a campaign save');
    C.KeyPress(True);
    TapMenuButton(C, 3);
    Check(C.OverlayRow(6).Button2Text = 'Delete', 'a saved campaign slot has Delete too');
    TapSlotDelete(C, 6);
    Check(Pos('Campaign', C.GetUi.DeletePrompt) > 0, 'asking about the campaign: ' + C.GetUi.DeletePrompt);
    C.ActionAnswerDelete(True);
    Check(not PeekCampaignSlot(2).Exists, 'the campaign save is gone');
    Check((C.OverlayRow(6).Detail = 'Empty') and (C.OverlayRow(6).Button2Text = ''), 'and its row is empty');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

{ The Style page: card backs, table cloths and the moon. }
procedure TapStyleTab(C: TGameController; I: Integer);
var
  R: TRect;
begin
  R := C.OverlayTabRect(I);
  C.Tap((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2);
end;

procedure TestStyle;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  Coins0, I: Integer;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.StartWithMenu;
    Check((C.StyleBack = 0) and (C.StyleCloth = 0) and (C.StyleMoon = 0), 'the original look to begin with');
    TapMenuButton(C, 5);
    Check((C.Overlay = okStyle) and C.MenuOpen, 'the menu''s Style button opens the page over the menu');
    Check(C.OverlayTabCount = 3, 'three tabs');
    Check(C.OverlayTabSelected(0) and not C.OverlayTabSelected(1), 'the card backs first');
    Check(C.OverlayRowCount = 4, 'four card backs');
    Check((C.OverlayRow(0).ButtonText = 'In use') and not C.OverlayRow(0).ButtonEnabled and C.OverlayRow(0).Selected,
      'the original is in use');
    Check(C.OverlayRow(0).Title = St.StyleName('back.moon'), 'with its name from the story');
    Check((C.OverlayRow(1).ButtonText = 'Buy') and not C.OverlayRow(1).ButtonEnabled and (C.OverlayRow(1).Aside = '60 coins'),
      'a back costs its list price and 50 coins do not reach it');
    Check((C.OverlayRow(3).ButtonText = '') and (C.OverlayRow(3).Aside = 'locked')
      and (Pos(St.TrophyName('jack'), C.OverlayRow(3).Detail) > 0), 'the last is earned: it names the trophy');
    Check(C.OverlayRow(1).Preview = 1 * 0 + 1 + 1, 'each row has a preview to draw');
    Check(C.OverlayRow(2).Preview = 3, 'numbered by kind and item');

    { buy }
    C.Session.Inventory.AddCoins(500);
    Coins0 := C.Session.Inventory.Coins;
    Check(C.OverlayRow(1).ButtonEnabled, 'with the coins, Buy is on');
    TapSlotButton(C, 1);
    Check(C.Session.Inventory.Coins = Coins0 - BackPrice, 'buying takes the price');
    Check(C.StyleBack = 1, 'and puts it in use');
    Check((C.OverlayRow(1).ButtonText = 'In use') and (C.OverlayRow(0).ButtonText = 'Use'), 'the page says so');
    Check(Pos('Bought', C.GetUi.StatusText) > 0, 'with a message: ' + C.GetUi.StatusText);
    TapSlotButton(C, 0);
    Check(C.StyleBack = 0, 'Use on the original goes back');
    TapSlotButton(C, 1);
    Check((C.StyleBack = 1) and (C.Session.Inventory.Coins = Coins0 - BackPrice), 'using what you own costs nothing');

    { an earned one }
    C.Trophies.Award(trVampire0);
    Check((C.OverlayRow(3).ButtonText = 'Use') and C.OverlayRow(3).ButtonEnabled, 'a trophy unlocks it');
    TapSlotButton(C, 3);
    Check(C.StyleBack = 3, 'and it can be used');

    { tabs }
    TapStyleTab(C, 1);
    Check(C.OverlayTabSelected(1) and (C.OverlayRow(1).Aside = '80 coins'), 'the table cloths, at their own price');
    TapSlotButton(C, 1);
    Check(C.StyleCloth = 1, 'a cloth bought and in use');
    TapStyleTab(C, 2);
    Check((C.OverlayRow(1).Aside = '50 coins') and (C.OverlayRow(0).Title = St.StyleName('moon.pale')), 'the moons');
    TapSlotButton(C, 1);
    Check((C.StyleMoon = 1) and (C.StyleBack = 3) and (C.StyleCloth = 1), 'each kind keeps its own choice');
    C.KeyPress(True);
    Check((C.Overlay = okNone) and C.MenuOpen, 'Esc goes back to the menu');

    { it is remembered by the next run }
    C.Free;
    C := NewCtl(St, D, W);
    C.StartWithMenu;
    Check((C.StyleBack = 3) and (C.StyleCloth = 1) and (C.StyleMoon = 1), 'saved on disk, by key');

    { a choice the player does not have falls back to the original }
    C.Free;
    StoreDelete(DefaultInventoryFile);
    StoreDelete(DefaultTrophiesFile);
    C := NewCtl(St, D, W);
    C.StartWithMenu;
    Check((C.StyleBack = 0) and (C.StyleCloth = 0) and (C.StyleMoon = 0), 'without the coins spent or the trophy, the original look shows');

    { Fenwick's Store has a Style button too }
    TapMenuButton(C, 1);
    RunOut(C);
    C.ActionOpenStore;
    Check(C.OverlayExtraCount = 0, 'no extra buttons while Fenwick introduces himself');
    for I := 1 to 10 do
      if C.OverlayHint <> '' then C.Tap(5, 5);
    Check((C.OverlayExtraCount = 2) and (C.OverlayExtraCaption(0) = 'Relics') and (C.OverlayExtraCaption(1) = 'Style'), 'the Store offers Relics and Style');
    C.Tap((C.OverlayExtraRect(1).Left + C.OverlayExtraRect(1).Right) div 2, (C.OverlayExtraRect(1).Top + C.OverlayExtraRect(1).Bottom) div 2);
    Check(C.Overlay = okStyle, 'which opens the page');
    C.ActionCloseOverlay;
    C.ActionOpenCards;
    Check(C.OverlayExtraCount = 0, 'the card tray has no such buttons');
    C.ActionCloseOverlay;

    { Erase everything goes back; Restart campaign does not }
    C.Session.Inventory.AddCoins(500);
    C.ActionOpenStyle;
    TapSlotButton(C, 1);
    Check(C.StyleBack = 1, 'test set-up: a back in use');
    C.ActionCloseOverlay;
    C.ActionRestartCampaign;
    ClickThrough(C);
    RunOut(C);
    Check(C.StyleBack = 1, 'Restart campaign keeps the look');
    C.ActionEraseEverything;
    RunOut(C);
    Check((C.StyleBack = 0) and not C.Session.Inventory.BoughtCosmetic(ckBack, 1), 'Erase everything takes it all away');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

{ Fenwick's relics: bought, equipped in slots that grow, applied to the hands dealt. }
procedure TestRelicsPage;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  I: Integer;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.StartWithMenu;
    TapMenuButton(C, 1);
    RunOut(C);
    C.ActionOpenStore;
    for I := 1 to 10 do
      if C.OverlayHint <> '' then C.Tap(5, 5);
    Check(C.OverlayExtraCaption(0) = 'Relics', 'the Store has a Relics button');
    C.Tap((C.OverlayExtraRect(0).Left + C.OverlayExtraRect(0).Right) div 2, (C.OverlayExtraRect(0).Top + C.OverlayExtraRect(0).Bottom) div 2);
    Check(C.Overlay = okRelics, 'which opens the page');
    C.ActionCloseOverlay;
    C.ActionOpenStore;
    C.SetViewport(375, 560);                          { a phone held upright }
    for I := 0 to C.OverlayExtraCount - 1 do
      Check(Inside(C.OverlayExtraRect(I), C.OverlayPanelRect) and (C.OverlayExtraRect(I).Right <= C.OverlayLeaveRect.Left),
        'on a phone, extra button ' + IntToStr(I) + ' fits beside Leave');
    Check(C.OverlayExtraRect(1).Right <= C.OverlayExtraRect(0).Left, 'and the two do not overlap');
    C.SetViewport(1520, 584);
    C.ActionCloseOverlay;
    C.ActionOpenStore;
    C.Tap((C.OverlayExtraRect(0).Left + C.OverlayExtraRect(0).Right) div 2, (C.OverlayExtraRect(0).Top + C.OverlayExtraRect(0).Bottom) div 2);
    Check(C.OverlayRowCount = RelicCount, 'a row for each relic');
    Check(C.RelicSlotCount = 1, 'one slot to begin with');
    Check(C.OverlayRow(0).Title = St.RelicName('garlic'), 'named from the story');
    Check((C.OverlayRow(1).ButtonText = 'Buy') and not C.OverlayRow(1).ButtonEnabled and (C.OverlayRow(1).Aside = Format('%d coins', [RelicPrice(rlPick)])),
      'the Pick: Buy, too dear for 50 coins');
    Check(Pos(St.TrophyName('perfect'), C.OverlayRow(3).Detail) > 0, 'the Locket says a trophy also gives it');
    Check(Pos('Also earned', C.OverlayRow(1).Detail) = 0, 'the Pick is only bought');

    { buy one: it goes into the free slot, and this hand takes it at once }
    C.Session.Inventory.AddCoins(1000);
    TapSlotButton(C, 1);
    Check(C.Session.Inventory.BoughtRelic(rlPick) and C.RelicEquipped(rlPick), 'bought, and equipped in the free slot');
    Check((C.OverlayRow(1).ButtonText = 'Remove') and (C.OverlayRow(1).Aside = 'equipped'), 'the row says so');
    Check(C.Session.Game.PickOn, 'a hand not yet started has it already');
    Check(Pos('Bought', C.GetUi.StatusText) > 0, 'with a message: ' + C.GetUi.StatusText);

    { the slot is full }
    TapSlotButton(C, 2);
    Check(C.Session.Inventory.BoughtRelic(rlSpoon) and not C.RelicEquipped(rlSpoon), 'a second is bought but has no slot');
    Check(Pos('No free slot', C.GetUi.StatusText) > 0, 'and the message says why: ' + C.GetUi.StatusText);
    Check((C.OverlayRow(2).ButtonText = 'Equip') and not C.OverlayRow(2).ButtonEnabled, 'Equip is off until a slot is free');
    { a vampire trophy opens another slot }
    C.Trophies.Award(trVampire0);
    Check(C.RelicSlotCount = 2, 'a vampire trophy gives a second slot');
    Check(C.OverlayRow(2).ButtonEnabled, 'now the Spoon can go in');
    TapSlotButton(C, 2);
    Check(C.RelicEquipped(rlSpoon) and C.RelicEquipped(rlPick), 'both are equipped');
    { the Locket is given by the perfect-hand trophy }
    C.Trophies.Award(trPerfect);
    Check((C.OverlayRow(3).ButtonText = 'Equip') and (C.OverlayRow(3).Aside = ''), 'the Locket is owned through its trophy');
    { take one out }
    TapSlotButton(C, 1);
    Check(not C.RelicEquipped(rlPick) and not C.Session.Game.PickOn, 'Remove takes it out of this fresh hand too');
    Check(C.Session.Inventory.BoughtRelic(rlPick), 'but it is still yours');

    { the Moonstone: a free Show move }
    C.Trophies.Award(trVampire1);
    TapSlotButton(C, 4);                          { earned by Carmilla's trophy as well: owned, so Equip }
    Check(C.RelicEquipped(rlMoonstone), 'the Moonstone is equipped');
    C.ActionCloseOverlay;
    Check(C.GetUi.HintCaption = 'Show move (free)', 'the button says the hint is free');
    Check(C.GetUi.HintEnabled, 'and it works with no hint cards');

    { a hand under way: a relic taken out is gone at once, and the next hand has what is equipped now }
    TapCard(C, 27);
    C.ActionOpenRelics;
    TapSlotButton(C, 4);
    Check(not C.RelicEquipped(rlMoonstone) and not C.Session.FreeHintAvailable, 'removed in the middle of a hand: its free hint goes too');
    C.ActionCloseOverlay;
    C.ActionNew;
    RunOut(C);
    Check(not HasRelic(C.Session.Relics, rlMoonstone) and HasRelic(C.Session.Relics, rlSpoon) and C.Session.Game.FeedsOnce,
      'the next hand has what is equipped now');
    C.Free;

    { the choice is saved; losing a trophy (or a slot) trims it }
    C := NewCtl(St, D, W);
    C.StartWithMenu;
    Check(C.RelicEquipped(rlSpoon), 'saved on disk');
    C.Free;
    StoreDelete(DefaultTrophiesFile);
    C := NewCtl(St, D, W);
    C.StartWithMenu;
    Check((C.RelicSlotCount = 1) and C.RelicEquipped(rlSpoon) and not C.RelicEquipped(rlPick), 'with one slot only the first kept relic stays');
    Check(C.Session.Inventory.BoughtRelic(rlPick), 'nothing is lost, it just does not fit');

    { Erase everything }
    TapMenuButton(C, 1);
    RunOut(C);
    C.ActionEraseEverything;
    RunOut(C);
    Check(not C.Session.Inventory.BoughtRelic(rlPick) and not C.RelicEquipped(rlSpoon) and not C.RelicEquipped(rlPick), 'Erase everything clears them');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

{ A relic equipped in the middle of a hand, from the start menu, works at once (the Store is shut then). }
procedure TestRelicsMidHand;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  I, Coins: Integer;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    C.ActionToggleMode;
    ClickThrough(C);
    RunOut(C);
    Check(C.Duel.Duel.State = dsPlaying, 'a duel hand is being played');
    C.Session.Game.SetHazard(hzChained);
    for I := 0 to PyramidSize - 1 do C.Session.Game.SetMark(I, MarkNone);
    C.Session.Game.SetMark(25, MarkChained);
    C.Session.Inventory.AddCoins(1000);
    Check(C.Session.Inventory.BuyRelic(rlPick) and C.Session.Inventory.BuyRelic(rlSpoon), 'test set-up: the player owns the Pick and the Spoon');
    TapCard(C, 27);
    TapCard(C, 26);
    TapCard(C, 25);
    Check(not C.Game.Removed(25) and (Pos('chained', C.GetUi.StatusText) > 0), 'no Pick equipped: the chained card will not play');
    Check(not C.GetUi.StoreEnabled, 'the Store is shut in the middle of a hand');
    { the Relics button on the menu }
    C.ActionOpenMenu;
    TapMenuButton(C, 6);
    Check((C.Overlay = okRelics) and C.MenuOpen, 'the menu opens the Relics page');
    Check((C.OverlayRow(1).ButtonText = 'Equip') and C.OverlayRow(1).ButtonEnabled, 'the Pick can be equipped');
    TapSlotButton(C, 1);
    Check(C.RelicEquipped(rlPick) and C.Session.Game.PickOn, 'equipped: it works at once');
    { Fenwick does not sell in the middle of a hand }
    Coins := C.Session.Inventory.Coins;
    Check(not C.OverlayRow(0).ButtonEnabled and (C.OverlayRow(0).ButtonText = 'Buy'), 'but nothing can be bought now');
    TapSlotButton(C, 0);
    Check(not C.Session.Inventory.BoughtRelic(rlGarlic) and (C.Session.Inventory.Coins = Coins), 'a tap on it buys nothing');
    C.ActionCloseOverlay;
    Check(C.MenuOpen and (C.Overlay = okNone), 'closing the page goes back to the menu');
    C.KeyPress(True);
    Check(not C.MenuOpen, 'and Escape to the table');
    TapCard(C, 25);
    TapCard(C, 24);
    Check(C.Game.Removed(25) and C.Game.Removed(24), 'the chained card plays (with its pair) with the Pick');
    Check(C.Game.Streak = 2, 'and counts as an ordinary play');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

procedure TestBiteStatus;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  I: Integer;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    C.ActionToggleMode;
    ClickThrough(C);
    RunOut(C);
    C.Session.Game.SetHazard(hzBitten);
    for I := 0 to PyramidSize - 1 do C.Session.Game.SetMark(I, MarkNone);
    C.Session.Game.SetMark(26, MarkBitten);
    TapCard(C, 27);
    Check(Pos('Bitten', C.GetUi.StatusText) = 0, 'an ordinary card is not announced');
    TapCard(C, 26);
    Check(C.Session.Bites = 1, 'a bitten card was played');
    Check(Pos('Bitten', C.GetUi.StatusText) > 0, 'and the status line says so: ' + C.GetUi.StatusText);
    Check(C.DuelInfo.BiteCut = BitePenaltyCoins, 'the panel shows the cost');
    Check(C.Session.Game.Streak = 0, 'and the streak is gone');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

procedure TestTrickControls;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  I: Integer;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    C.ActionToggleMode;
    ClickThrough(C);
    RunOut(C);
    Check(C.Duel.Duel.State = dsPlaying, 'a duel hand is being played');
    { Carmilla's chains, put where the test wants them }
    C.Session.Game.SetHazard(hzChained);
    for I := 0 to PyramidSize - 1 do C.Session.Game.SetMark(I, MarkNone);
    C.Session.Game.SetMark(21, MarkChained);        { a King: its row neighbour 22 is played after it }
    C.Session.Game.SetMark(5, MarkChained);         { a card high up }
    Check(C.CardMark(5) = MarkChained, 'the whole pyramid is face up: a mark high up shows');
    Check(C.CardMark(21) = MarkChained, 'and so does the one on the bottom row');
    TapCard(C, 21);
    Check(not C.Game.Removed(21), 'a chained King with its neighbour still on the table does not play');
    Check(Pos('chained', C.GetUi.StatusText) > 0, 'and the player is told why: ' + C.GetUi.StatusText);
    { a Wood Stake on the neighbour frees it }
    C.Session.Inventory.AddSpecial(skStake, 1);
    Check(C.Duel.UseSpecialOn(skStake, 22, PosNone), 'a Wood Stake destroys the neighbour');
    TapCard(C, 21);
    Check(C.Game.Removed(21), 'and the chained King plays');
    C.Session.Game.SetMark(5, MarkBitten);
    Check(C.CardMark(5) = MarkBitten, 'a bite shows');
    C.Session.Game.SetMark(1, MarkCross);
    Check(C.CardMark(1) = MarkCross, 'and the silver cross under the top card');

  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

{ The silver cross lying in the open: an ordinary tap on it asks first. }
procedure TestCrossControls;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  I, K, O: Integer;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    C.ActionToggleMode;
    ClickThrough(C);
    RunOut(C);
    Check(C.Duel.Duel.State = dsPlaying, 'a duel hand is being played');
    { the silver cross in the open: an ordinary tap asks first }
    for I := 0 to PyramidSize - 1 do C.Session.Game.SetMark(I, MarkNone);
    K := -1;
    for I := 18 to 27 do
      if (K < 0) and not C.Game.Removed(I) and C.Game.CanSelect(I) then K := I;
    Check(K >= 0, 'a bottom-row card can be played');
    O := -1;
    for I := 18 to 27 do
      if (O < 0) and (I <> K) and not C.Game.Removed(I) and C.Game.CanSelect(I) then O := I;
    C.Session.Game.SetMark(K, MarkCross);
    Check(C.CardMark(K) = MarkCross, 'a bottom-row cross shows from the start');
    TapCard(C, K);
    Check(C.GetUi.AskCross and not C.Game.Removed(K), 'tapping it asks, and does not play it');
    Check(Pos('Wild card', C.GetUi.CrossPrompt) > 0, 'the question says only a Wild card claims it');
    if O >= 0 then
    begin
      TapCard(C, O);
      Check(not C.Game.Removed(O), 'the table waits for the answer');
    end;
    C.ActionAnswerCross(False);
    Check(not C.GetUi.AskCross and not C.Game.Removed(K) and (C.CardMark(K) = MarkCross), 'Keep: the card and its cross stay');
    TapCard(C, K);
    Check(C.GetUi.AskCross, 'asks again next time');
    C.ActionAnswerCross(True);
    Check(C.Game.Removed(K) and (C.Campaign.Ease = 0), 'Play it anyway: the card is played, nothing claimed');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

{ Trophies: earned by playing, shown on the shelf in the panel, a page when tapped. }
procedure TestTrophies;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  L: TTrophyLayout;
  I: Integer;
  Name1: string;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    Check(C.Trophies.Count = 0, 'a new player has no trophies');
    L := C.TrophyLayout;
    Check(not L.Chip and (L.Shelf.Right > L.Shelf.Left), 'the shelf is in the side panel');
    Check(Inside(L.Slots[0], C.PanelRect) and Inside(L.Slots[5], C.PanelRect), 'its slots are inside the panel');
    Check(C.TrophyArt(0) = ArtTrophyEmpty, 'an empty tile for a trophy not earned');

    { a perfect Free Play win earns the first two }
    ClearBoard(C);
    Check(C.Game.IsWon, 'test set-up: a won hand');
    Check(C.Trophies.Has(trFirstWin) and C.Trophies.Has(trPerfect), 'the first win and the perfect hand');
    Check(not C.Trophies.Has(trVampire0), 'but not the first vampire''s');
    Name1 := St.TrophyName('firstwin');
    Check(Pos('Trophy earned: ' + Name1, C.GetUi.StatusText) > 0, 'the status line says so: ' + C.GetUi.StatusText);
    Check(C.TrophyArt(0) = ArtTrophy0, 'its picture is drawn now');

    { tapping the shelf (even on the win screen) opens the trophy page }
    L := C.TrophyLayout;
    C.Tap((L.Shelf.Left + L.Shelf.Right) div 2, (L.Shelf.Top + L.Shelf.Bottom) div 2);
    Check(C.Overlay = okTrophies, 'the shelf opens the trophy page');
    Check(C.Game.IsWon, 'and does not deal a new hand');
    Check(C.OverlayRowCount = TrophyCount, 'one row for each trophy');
    Check((C.OverlayRow(0).Title = Name1) and (C.OverlayRow(0).Art = ArtTrophy0)
      and (C.OverlayRow(0).Detail = St.TrophyLine('firstwin')), 'an earned one: its name, its picture and its words');
    Check((C.OverlayRow(2).Detail = St.TrophyHow('jack')) and (C.OverlayRow(2).Aside = '')
      and (C.OverlayRow(2).Art = ArtTrophyEmpty), 'one not earned: how to get it, an empty tile');
    Check(C.OverlayFooter = '2 of 6 earned', 'the count: ' + C.OverlayFooter);
    for I := 0 to C.OverlayRowCount - 1 do
      Check(C.OverlayRow(I).ButtonText = '', 'row ' + IntToStr(I) + ' has no button');
    C.ActionCloseOverlay;
    Check(C.Overlay = okNone, 'closed');
    C.Tap(5, 5);
    RunOut(C);
    Check(not C.Game.IsWon, 'a tap elsewhere on the win screen still deals again');
    TapCard(C, 27);
    Check(Pos('Trophy earned', C.GetUi.StatusText) = 0, 'the news goes with the next tap on the table');
    C.ActionNew;
    RunOut(C);

    { a win with a missed move is not perfect, so a fresh player earns only the first win }
    C.ActionEraseEverything;
    RunOut(C);
    Check(C.Trophies.Count = 0, 'Erase everything clears the trophies');
  finally
    C.Free;
  end;
  { they survive a restart of the program }
  WipeStore;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    ClearBoard(C);
    Check(C.Trophies.Count = 2, 'earned again');
  finally
    C.Free;
  end;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    Check(C.Trophies.Has(trFirstWin) and C.Trophies.Has(trPerfect) and (C.Trophies.Count = 2), 'saved on disk');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

{ The campaign trophies: a vampire for each kill, and the flawless one. }
procedure TestCampaignTrophies;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  V, I: Integer;

  procedure Beat(AVampire: Integer);
  var
    N: Integer;
  begin
    for N := 1 to WinsToKill do
    begin
      if AVampire = 2 then                       { the rigged deal runs from the 7 down through the Ace to the King }
      begin
        C.Session.Inventory.AddSpecial(skEasyRule, 1);   { so the King, who has no wrap, needs this }
        C.Duel.UseSpecial(skEasyRule);
      end;
      ClearBoard(C);
      ClickThrough(C);
      RunOut(C);
    end;
  end;

begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    C.ActionToggleMode;
    ClickThrough(C);
    RunOut(C);
    C.ActionNew;                                 { one lost hand against the first vampire }
    ClickThrough(C);
    RunOut(C);
    Check(C.Duel.Campaign.LostAll = 1, 'one lost hand counted');
    Beat(0);
    Check(C.Trophies.Has(trVampire0) and not C.Trophies.Has(trVampire1), 'the first vampire''s trophy for the first kill');
    Check(C.Trophies.Has(trFirstWin) and C.Trophies.Has(trPerfect), 'with the first win and a perfect hand on the way');
    Beat(1);
    Beat(2);
    Check(C.Trophies.Has(trVampire1) and C.Trophies.Has(trVampire2), 'all three vampires');
    Check(not C.Trophies.Has(trFlawless), 'but a lost hand rules out the flawless one');
    Check(C.Trophies.Count = 5, 'five of six');

    { starting the campaign again keeps them, and a clean run earns the last one }
    C.ActionRestartCampaign;
    ClickThrough(C);
    RunOut(C);
    Check(C.Trophies.Count = 5, 'Restart campaign keeps the trophies');
    Check(C.Duel.Campaign.LostAll = 0, 'and the lost-hand count starts again');
    Beat(0);
    Beat(1);
    Beat(2);
    Check(C.Trophies.Has(trFlawless), 'a whole campaign without losing a hand: the flawless trophy');
    Check(Pos(St.TrophyName('flawless'), C.GetUi.StatusText) > 0, 'announced: ' + C.GetUi.StatusText);
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

procedure TestPrices;
var
  St: TStory;
  C: TGameController;
  D: TDecks;
  W: TWatcher;
  I: Integer;
begin
  WipeStore;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  D := TDecks.Create;
  W := TWatcher.Create;
  C := NewCtl(St, D, W);
  try
    C.Start;
    RunOut(C);
    C.ActionOpenStore;
    Check(C.OverlayRow(Ord(skWild)).Aside = Format('%d coins', [SpecialPrice[skWild]]), 'Free Play pays the list price');
    C.ActionCloseOverlay;
    C.ActionToggleMode;                      { the campaign: Jack }
    ClickThrough(C);
    RunOut(C);
    C.ActionOpenStore;
    Check(C.OverlayRow(Ord(skWild)).Aside = Format('%d coins', [DiscountedPrice(SpecialPrice[skWild], VampirePricePercent[0])]),
      'the Store is cheaper while you face Jack');
    Check(C.OverlayRow(ArtUndo).Aside = Format('%d coins', [DiscountedPrice(UndoPackCost, VampirePricePercent[0])]), 'undo packs too');
    Check(C.OverlayRow(ArtHint).Aside = Format('%d coins', [DiscountedPrice(HintPackCost, VampirePricePercent[0])]), 'and hint packs');
    for I := 0 to SpecialCount - 1 do
      Check(C.Session.Inventory.SpecialPrice(TSpecialKind(I)) < SpecialPrice[TSpecialKind(I)], 'every card is cheaper at Jack');
    C.ActionCloseOverlay;
    C.ActionToggleMode;                      { back to Free Play }
    RunOut(C);
    C.ActionOpenStore;
    Check(C.OverlayRow(Ord(skWild)).Aside = Format('%d coins', [SpecialPrice[skWild]]), 'and the list price is back in Free Play');
  finally
    C.Free; W.Free; D.Free; St.Free;
  end;
end;

begin
  CrossCardsOn := False;                  { where the silver cross lies is random: it has its own tests }
  Randomize;
  SetStoreDir('tiepair_test_controller');
  TestLayout;
  TestFreePlay;
  TestResume;
  TestSlots;
  TestRecordsFlow;
  TestCampaignRecords;
  TestStoreLayout;
  TestStore;
  TestWrapCardStock;
  TestCardTray;
  TestStakesInDuel;
  TestCampaign;
  TestResumeCampaign;
  TestStartOver;
  TestMenu;
  TestSaveSlots;
  TestDeleteSaves;
  TestStyle;
  TestRelicsPage;
  TestTrickControls;
  TestRelicsMidHand;
  TestCrossControls;
  TestTrophies;
  TestCampaignTrophies;
  TestBiteStatus;
  TestPrices;
  WipeStore;
  if Failures = 0 then WriteLn('ALL CONTROLLER TESTS PASSED') else
  begin
    WriteLn(Failures, ' FAILURES');
    Halt(1);
  end;
end.
