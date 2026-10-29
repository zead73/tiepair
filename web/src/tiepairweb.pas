program tiepairweb;

{ The web version of Tiepair: the same game (GameController and everything
  under it) running in a browser. This file is the page's glue: it loads the
  pictures, makes the canvas fit the screen (and the screen's pixel density),
  turns taps, keys and button presses into controller calls, and repaints when
  the controller says something changed. Saved data goes to the browser's local
  storage (see Storage). }

{$mode objfpc}{$H+}

uses
  JS, Web, SysUtils, Math, Types, Cards, Story, Sound, Storage, Settings, HandFile,
  GameController, Cosmetics, WebView, VrPanel;

type
  TVrFrameFn = function(T: Double): Integer of object;
  TVrTapFn = procedure(X, Y: Double) of object;
  TVrTableFn = function: TJSArray of object;
  TVrSlotFn = procedure(Slot: Integer) of object;
  TVrMarkFn = function(Kind: Integer): TJSObject of object;
  TVrBackFn = function: TJSObject of object;
  TVrDebugFn = procedure(const S: string) of object;
  TVrStyleFn = function: TJSArray of object;
  TVrBoolFn = procedure(B: Boolean) of object;

  TWebApp = class
  private
    FCtl: TGameController;
    FStory: TStory;
    FView: TWebView;
    FCanvas: TJSHTMLCanvasElement;
    FStageBox: TJSElement;
    FCtx: TJSCanvasRenderingContext2D;
    FScheduled: Boolean;
    FLastTs: Double;
    FW, FH: Integer;
    FDpr: Double;
    FLastStatus: string;
    FAudioUnlocked: Boolean;
    FAskingInitials: Boolean;
    FAskingCross: Boolean;
    FAskingDelete: Boolean;
    FShowingRules: Boolean;
    { VR: the game on a flat panel (see VrPanel); the page's own canvas is not drawn then }
    FVr: Boolean;                          { a VR session is running }
    FVrDirty: Boolean;                     { the panel needs repainting }
    FVrExit: Boolean;                      { the player pressed Exit VR }
    FVrWasTable: Boolean;                  { the cards were shown as a 3D table at the last frame }
    FVrLast: Double;
    FVrCanvas: TJSHTMLCanvasElement;
    FVrCtx: TJSCanvasRenderingContext2D;
    FVrView: TWebView;
    FVrPanel: TVrPanel;
    function El(const Id: string): TJSElement;
    procedure SetText(const Id, Value: string);
    procedure SetOn(const Id: string; AOn: Boolean);
    procedure Show(const Id: string; AShow: Boolean);
    procedure Listen(const Id, Event: string; AHandler: TJSEventHandler);
    procedure ApplyUi;
    procedure FitCanvas;
    procedure DoPaint;
    procedure Invalidate;
    procedure Changed;
    procedure Frame(aTime: TJSDOMHighResTimeStamp);
    procedure UnlockAudio;
    function OnPointerDown(Event: TEventListenerEvent): Boolean;
    function OnKeyDown(Event: TEventListenerEvent): Boolean;
    function OnResize(Event: TEventListenerEvent): Boolean;
    function OnNew(Event: TEventListenerEvent): Boolean;
    function OnUndo(Event: TEventListenerEvent): Boolean;
    function OnHint(Event: TEventListenerEvent): Boolean;
    function OnMode(Event: TEventListenerEvent): Boolean;
    function OnStore(Event: TEventListenerEvent): Boolean;
    function OnCards(Event: TEventListenerEvent): Boolean;
    function OnCancel(Event: TEventListenerEvent): Boolean;
    function OnRecords(Event: TEventListenerEvent): Boolean;
    function OnInitialsOk(Event: TEventListenerEvent): Boolean;
    function OnInitialsSkip(Event: TEventListenerEvent): Boolean;
    procedure AnswerInitials(AOk: Boolean);
    procedure FinishInitials(const S: string);
    procedure VrEnter;
    procedure VrExit;
    function VrFrame(T: Double): Integer;
    procedure VrTap(X, Y: Double);
    function VrTable: TJSArray;
    procedure VrTapSlot(Slot: Integer);
    function VrMark(Kind: Integer): TJSObject;
    function VrBack: TJSObject;
    procedure VrDebug(const S: string);
    function VrStyle: TJSArray;
    procedure VrSetCheats(B: Boolean);
    procedure VrButton(Id: Integer);
    procedure VrAnswer(K: TVrDialog; Choice: Integer; const Text: string);
    procedure VrInvalidate;
    procedure InstallVrBridge;
    function OnCrossKeep(Event: TEventListenerEvent): Boolean;
    function OnCrossPlay(Event: TEventListenerEvent): Boolean;
    procedure AnswerCross(APlayIt: Boolean);
    procedure AnswerDelete(ADelete: Boolean);
    function OnDeleteKeep(Event: TEventListenerEvent): Boolean;
    function OnDeleteGo(Event: TEventListenerEvent): Boolean;
    procedure CloseRules;
    function OnRulesClose(Event: TEventListenerEvent): Boolean;
    procedure FillRules;
    function OnMenu(Event: TEventListenerEvent): Boolean;
    function OnStartOver(Event: TEventListenerEvent): Boolean;
    function OnSkip(Event: TEventListenerEvent): Boolean;
    function OnEraseAll(Event: TEventListenerEvent): Boolean;
    function OnRestartCampaign(Event: TEventListenerEvent): Boolean;
    function OnOverCancel(Event: TEventListenerEvent): Boolean;
  public
    procedure Run;
    procedure Boot;
  end;

var
  App: TWebApp;

procedure GlueLoadImages(Pairs: TJSArray; Done: TProc); external name 'TCGlue.loadImages';
function GlueStory: string; external name 'TCGlue.getStory';
procedure GluePlayWav(const Name, Wav: string); external name 'TCGlue.playWav';
procedure GlueUnlockAudio; external name 'TCGlue.unlockAudio';
procedure GluePersist; external name 'TCGlue.persistStorage';

procedure WebPlayWav(const Name, Wav: string);
begin
  GluePlayWav(Name, Wav);
end;

function IsTouchScreen: Boolean;
begin
  asm
    Result = ('ontouchstart' in window) || (navigator.maxTouchPoints > 0);
  end;
end;

{ ---- small DOM helpers ---- }

function TWebApp.El(const Id: string): TJSElement;
begin
  Result := document.getElementById(Id);
end;

procedure TWebApp.SetText(const Id, Value: string);
var
  E: TJSElement;
begin
  E := El(Id);
  if E <> nil then E.textContent := Value;
end;

procedure TWebApp.SetOn(const Id: string; AOn: Boolean);
var
  E: TJSElement;
begin
  E := El(Id);
  if E = nil then Exit;
  { a button that is "off" looks dim but still answers a tap (to say why) }
  asm
    if (AOn) { E.classList.remove('off'); E.setAttribute('aria-disabled', 'false'); }
    else { E.classList.add('off'); E.setAttribute('aria-disabled', 'true'); }
  end;
end;

procedure TWebApp.Show(const Id: string; AShow: Boolean);
var
  E: TJSElement;
begin
  E := El(Id);
  if E = nil then Exit;
  asm
    E.style.display = AShow ? '' : 'none';
  end;
end;

procedure TWebApp.Listen(const Id, Event: string; AHandler: TJSEventHandler);
var
  E: TJSElement;
begin
  E := El(Id);
  if E <> nil then E.addEventListener(Event, AHandler);
end;

{ ---- keeping the page in step with the game ---- }

procedure TWebApp.ApplyUi;
var
  U: TUiState;
begin
  U := FCtl.GetUi;
  if U.StatusText <> FLastStatus then
  begin
    SetText('status', U.StatusText);
    FLastStatus := U.StatusText;
  end;
  SetText('btnMode', U.EasyCaption);
  SetOn('btnMode', U.EasyEnabled);
  SetText('btnUndo', U.UndoCaption);
  SetText('btnHint', U.HintCaption);
  SetText('btnMenu', U.MenuCaption);
  SetText('btnStore', U.StoreCaption);
  SetText('btnCards', U.CardsCaption);
  SetOn('btnNew', not FCtl.MenuOpen);
  SetOn('btnStartOver', not FCtl.MenuOpen);
  SetOn('btnUndo', U.UndoEnabled);
  SetOn('btnHint', U.HintEnabled);
  SetOn('btnStore', U.StoreEnabled);
  SetOn('btnCards', U.CardsEnabled);
  Show('btnSkip', U.CanSkip);
  Show('btnCancel', U.Targeting);
  SetText('btnRecords', U.RecordsCaption);
  SetOn('btnRecords', U.RecordsEnabled);
  if U.ShowRules and not FShowingRules then
  begin
    FShowingRules := True;
    if FVr then
      FVrPanel.OpenDialog(vdRules, '')
    else
    begin
      FillRules;
      Show('dlgRules', True);
      asm
        var rb = document.getElementById('rulesBody');
        if (rb) { rb.scrollTop = 0; }
        var rc = document.getElementById('rulesClose');
        if (rc) { rc.focus(); }
      end;
    end;
  end;
  if U.AskDelete and not FAskingDelete then
  begin
    FAskingDelete := True;
    if FVr then
      FVrPanel.OpenDialog(vdDelete, U.DeletePrompt)
    else
    begin
      SetText('deletePrompt', U.DeletePrompt);
      Show('dlgDelete', True);
      asm
        var kb = document.getElementById('deleteKeep');
        if (kb) { kb.focus(); }
      end;
    end;
  end;
  if U.AskCross and not FAskingCross then
  begin
    FAskingCross := True;
    if FVr then
      FVrPanel.OpenDialog(vdCross, U.CrossPrompt)
    else
    begin
      SetText('crossPrompt', U.CrossPrompt);
      Show('dlgCross', True);
      asm
        var kb = document.getElementById('crossKeep');
        if (kb) { kb.focus(); }
      end;
    end;
  end;
  if U.AskInitials and not FAskingInitials then
  begin
    FAskingInitials := True;
    if FVr then
      FVrPanel.OpenDialog(vdInitials, U.InitialsPrompt, U.InitialsDefault)
    else
    begin
      SetText('initialsPrompt', U.InitialsPrompt);
      asm
        var inp = document.getElementById('initialsInput');
        if (inp) { inp.value = U.InitialsDefault; }
      end;
      Show('dlgInitials', True);
      asm
        var inp2 = document.getElementById('initialsInput');
        if (inp2) { inp2.focus(); inp2.select(); }
      end;
    end;
  end;
end;

procedure TWebApp.Changed;
begin
  ApplyUi;
  Invalidate;
end;

{ Sizes the canvas to its box, and to the screen's pixel density. }
procedure TWebApp.FitCanvas;
var
  W, H: Integer;
  D: Double;
begin
  W := FStageBox.clientWidth;
  H := FStageBox.clientHeight;
  if W < 50 then W := 50;
  if H < 50 then H := 50;
  D := window.devicePixelRatio;
  if D < 1 then D := 1;
  if D > 3 then D := 3;
  if (W = FW) and (H = FH) and (D = FDpr) then Exit;
  FW := W;
  FH := H;
  FDpr := D;
  FCanvas.width := Round(W * D);
  FCanvas.height := Round(H * D);
  FCanvas.style.setProperty('width', IntToStr(W) + 'px');
  FCanvas.style.setProperty('height', IntToStr(H) + 'px');
end;

procedure TWebApp.DoPaint;
begin
  FitCanvas;
  FView.Paint(FW, FH, FDpr);
end;

procedure TWebApp.Invalidate;
begin
  if FVr then                              { in VR the session's own frame loop paints }
  begin
    FVrDirty := True;
    Exit;
  end;
  if FScheduled then Exit;
  FScheduled := True;
  window.requestAnimationFrame(@Frame);
end;

procedure TWebApp.Frame(aTime: TJSDOMHighResTimeStamp);
var
  Delta: Double;
begin
  FScheduled := False;
  if FCtl.NeedsTicks then
  begin
    if FLastTs = 0 then Delta := 16 else Delta := aTime - FLastTs;
    FLastTs := aTime;
    FCtl.Tick(Round(Delta));            { calls Changed, which asks for another frame }
  end
  else
    FLastTs := 0;
  DoPaint;
  if FCtl.NeedsTicks then Invalidate;
end;

procedure TWebApp.UnlockAudio;
begin
  if FAudioUnlocked then Exit;
  FAudioUnlocked := True;
  GlueUnlockAudio;                      { phones only allow sound after a tap }
end;

{ ---- input ---- }

function TWebApp.OnPointerDown(Event: TEventListenerEvent): Boolean;
var
  Rect: TJSDOMRect;
  X, Y: Integer;
begin
  UnlockAudio;
  Event.preventDefault;
  Rect := FCanvas.getBoundingClientRect;
  X := Round(TJSMouseEvent(Event).clientX - Rect.left);
  Y := Round(TJSMouseEvent(Event).clientY - Rect.top);
  FCtl.SetViewport(FW, FH);
  FCtl.Tap(X, Y);
  Result := False;
end;

function TWebApp.OnKeyDown(Event: TEventListenerEvent): Boolean;
begin
  UnlockAudio;
  if FShowingRules then                    { the rules: Esc closes; arrows and the wheel scroll }
  begin
    if string(TJSObject(Event)['key']) = 'Escape' then CloseRules;
    Result := string(TJSObject(Event)['key']) = 'Escape';
    Exit;
  end;
  if FAskingDelete then                    { delete a saved game: Esc = keep it }
  begin
    if string(TJSObject(Event)['key']) = 'Escape' then AnswerDelete(False);
    Result := string(TJSObject(Event)['key']) <> 'Enter';
    Exit;
  end;
  if FAskingCross then                     { the silver cross question: Esc = keep it }
  begin
    if string(TJSObject(Event)['key']) = 'Escape' then AnswerCross(False);
    Result := string(TJSObject(Event)['key']) <> 'Enter';     { Enter presses the focused button }
    Exit;
  end;
  if FAskingInitials then                  { the initials question: Enter = OK, Esc = skip }
  begin
    if string(TJSObject(Event)['key']) = 'Enter' then AnswerInitials(True)
    else if string(TJSObject(Event)['key']) = 'Escape' then AnswerInitials(False);
    Result := True;
    Exit;
  end;
  if ((string(TJSObject(Event)['key']) = ' ') or (string(TJSObject(Event)['key']) = 'Enter')) and FCtl.KeyAdvances then
  begin
    Event.preventDefault;                  { Space and Enter move the story on, and press no button as well }
    asm
      if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
    end;
    FCtl.KeyPress(False);
    Result := False;
    Exit;
  end;
  FCtl.KeyPress(string(TJSObject(Event)['key']) = 'Escape');
  if FCtl.MenuOpen and (Length(string(TJSObject(Event)['key'])) = 1) then
    FCtl.TypeChar(string(TJSObject(Event)['key'])[1]);        { the menu's hidden cheat word }
  Result := True;
end;

function TWebApp.OnResize(Event: TEventListenerEvent): Boolean;
begin
  Invalidate;
  Result := True;
end;

function TWebApp.OnNew(Event: TEventListenerEvent): Boolean;
begin
  UnlockAudio;
  FCtl.ActionNew;
  Result := True;
end;

function TWebApp.OnUndo(Event: TEventListenerEvent): Boolean;
begin
  UnlockAudio;
  if FCtl.GetUi.UndoEnabled then FCtl.ActionUndo;
  Result := True;
end;

function TWebApp.OnHint(Event: TEventListenerEvent): Boolean;
begin
  UnlockAudio;
  if FCtl.GetUi.HintEnabled then FCtl.ActionHint;
  Result := True;
end;

{ The Store button answers even when shut: Fenwick says why. }
function TWebApp.OnMode(Event: TEventListenerEvent): Boolean;
begin
  FCtl.ActionToggleEasy;
  Result := True;
end;

function TWebApp.OnStore(Event: TEventListenerEvent): Boolean;
begin
  UnlockAudio;
  FCtl.ActionOpenStore;
  Result := True;
end;

function TWebApp.OnCards(Event: TEventListenerEvent): Boolean;
begin
  UnlockAudio;
  FCtl.ActionOpenCards;
  Result := True;
end;

function TWebApp.OnCancel(Event: TEventListenerEvent): Boolean;
begin
  FCtl.ActionCancel;
  Result := True;
end;

function TWebApp.OnRecords(Event: TEventListenerEvent): Boolean;
begin
  UnlockAudio;
  FCtl.ActionOpenRecords;
  Result := True;
end;

{ The initials question: OK sends what was typed, Skip sends nothing. }
procedure TWebApp.AnswerInitials(AOk: Boolean);
var
  S: string;
begin
  S := '';
  if AOk then
  begin
    asm
      var inp = document.getElementById('initialsInput');
      S = inp ? inp.value : '';
    end;
  end;
  FinishInitials(S);
end;

procedure TWebApp.FinishInitials(const S: string);
begin
  Show('dlgInitials', False);
  FAskingInitials := False;
  FCtl.ActionSubmitInitials(S);
end;

{ The rules: one heading and some paragraphs for each section, in a scrolling box. }
procedure TWebApp.FillRules;
var
  I, N: Integer;
  Heads, Bodies: TJSArray;
begin
  N := FCtl.RulesSectionCount;
  Heads := TJSArray.new;
  Bodies := TJSArray.new;
  for I := 0 to N - 1 do
  begin
    Heads.push(FCtl.RulesHeading(I));
    Bodies.push(FCtl.RulesBody(I));
  end;
  asm
    var box = document.getElementById('rulesBody');
    if (box) {
      box.textContent = '';
      for (var i = 0; i < Heads.length; i++) {
        var h = document.createElement('h3');
        h.textContent = Heads[i];
        box.appendChild(h);
        var paras = Bodies[i].split('\n');
        for (var j = 0; j < paras.length; j++) {
          if (paras[j] === '') { continue; }
          var p = document.createElement('p');
          p.textContent = paras[j];
          box.appendChild(p);
        }
      }
    }
  end;
end;

procedure TWebApp.CloseRules;
begin
  Show('dlgRules', False);
  FShowingRules := False;
  FCtl.ActionRulesClosed;
end;

function TWebApp.OnRulesClose(Event: TEventListenerEvent): Boolean;
begin
  CloseRules;
  Result := True;
end;

{ Deleting a saved game: Delete it, or Keep it. }
procedure TWebApp.AnswerDelete(ADelete: Boolean);
begin
  Show('dlgDelete', False);
  FAskingDelete := False;
  FCtl.ActionAnswerDelete(ADelete);
end;

function TWebApp.OnDeleteKeep(Event: TEventListenerEvent): Boolean;
begin
  AnswerDelete(False);
  Result := True;
end;

function TWebApp.OnDeleteGo(Event: TEventListenerEvent): Boolean;
begin
  AnswerDelete(True);
  Result := True;
end;

{ The silver cross question: Play it anyway, or Keep the cross. }
procedure TWebApp.AnswerCross(APlayIt: Boolean);
begin
  Show('dlgCross', False);
  FAskingCross := False;
  FCtl.ActionAnswerCross(APlayIt);
end;

function TWebApp.OnCrossKeep(Event: TEventListenerEvent): Boolean;
begin
  AnswerCross(False);
  Result := True;
end;

function TWebApp.OnCrossPlay(Event: TEventListenerEvent): Boolean;
begin
  AnswerCross(True);
  Result := True;
end;

function TWebApp.OnInitialsOk(Event: TEventListenerEvent): Boolean;
begin
  AnswerInitials(True);
  Result := True;
end;

function TWebApp.OnInitialsSkip(Event: TEventListenerEvent): Boolean;
begin
  AnswerInitials(False);
  Result := True;
end;

function TWebApp.OnMenu(Event: TEventListenerEvent): Boolean;
begin
  UnlockAudio;
  FCtl.ActionOpenMenu;
  Result := True;
end;

function TWebApp.OnStartOver(Event: TEventListenerEvent): Boolean;
begin
  UnlockAudio;
  Show('dlgOver', True);
  Result := True;
end;

{ ---- VR ---- }

procedure TWebApp.VrInvalidate;
begin
  FVrDirty := True;
end;

{ A VR session began (vr.js asks for this first, then calls VrFrame every frame). }
procedure TWebApp.VrEnter;
begin
  UnlockAudio;
  FVr := True;
  FVrDirty := True;
  FVrExit := False;
  FVrWasTable := False;
  FVrLast := 0;
end;

{ The session ended: a dialog still open on the panel is answered the safe way (keep, cancel,
  skip) so that nothing is left waiting where the page cannot show it. }
procedure TWebApp.VrExit;
var
  K: TVrDialog;
begin
  K := FVrPanel.Dialog;
  if K <> vdNone then
  begin
    FVrPanel.CloseDialog;
    if K = vdInitials then VrAnswer(K, 1, '') else VrAnswer(K, 0, '');
  end;
  FVr := False;
  FVrExit := False;
  Invalidate;
end;

{ One VR frame: lets the game's own time go by, repaints the panel if anything changed.
  Returns 1 when the panel's picture changed, plus 2 when the player asked to leave. }
function TWebApp.VrFrame(T: Double): Integer;
var
  Delta: Double;
  Table: Boolean;
begin
  Result := 0;
  if FCtl.NeedsTicks then
  begin
    if FVrLast = 0 then Delta := 16 else Delta := T - FVrLast;
    if Delta > 100 then Delta := 100;
    FVrLast := T;
    FCtl.Tick(Round(Delta));
    FVrDirty := True;
  end
  else
    FVrLast := 0;
  Table := FVrPanel.TableActive;
  if Table <> FVrWasTable then
  begin
    FVrWasTable := Table;
    FVrDirty := True;
  end;
  if FVrDirty then
  begin
    FVrDirty := False;
    if Table then FVrPanel.PaintHud else FVrPanel.Paint;
    Result := 1;
  end;
  if Table then Result := Result + 4;
  if FVrExit then Result := Result + 2;
end;

{ The 3D table's numbers (see TVrPanel.TableSnapshot): nil when the flat panel is shown. }
function TWebApp.VrTable: TJSArray;
begin
  Result := FVrPanel.TableSnapshot;
end;

procedure TWebApp.VrTapSlot(Slot: Integer);
begin
  UnlockAudio;
  FVrPanel.TapSlot(Slot);
  FVrDirty := True;
end;

function TWebApp.VrMark(Kind: Integer): TJSObject;
begin
  Result := FVrPanel.MarkCanvas(Kind);
end;

function TWebApp.VrBack: TJSObject;
begin
  Result := FVrView.BackCardCanvas(328, 464);
end;

procedure TWebApp.VrSetCheats(B: Boolean);
begin
  FVrPanel.Cheats := B;
  FVrDirty := True;
end;

function TWebApp.VrStyle: TJSArray;
begin
  Result := FVrPanel.StyleList;
end;

procedure TWebApp.VrDebug(const S: string);
begin
  if S = FVrPanel.DebugText then Exit;
  FVrPanel.DebugText := S;
  FVrDirty := True;
end;

procedure TWebApp.VrTap(X, Y: Double);
begin
  UnlockAudio;
  FVrPanel.Tap(X, Y);
  FVrDirty := True;
end;

procedure TWebApp.VrButton(Id: Integer);
begin
  case Id of
    vbNew: FCtl.ActionNew;
    vbUndo: if FCtl.GetUi.UndoEnabled then FCtl.ActionUndo;
    vbStore: FCtl.ActionOpenStore;
    vbHint: if FCtl.GetUi.HintEnabled then FCtl.ActionHint;
    vbCards: FCtl.ActionOpenCards;
    vbMenu: FCtl.ActionOpenMenu;
    vbStartOver: FVrPanel.OpenDialog(vdOver, '');
    vbRecords: FCtl.ActionOpenRecords;
    vbMode: if FCtl.GetUi.EasyEnabled then FCtl.ActionToggleEasy;
    vbExit: FVrExit := True;
    vbSkip: FCtl.SkipPressed;
    vbCancel: FCtl.ActionCancel;
    vbCheat: FVrPanel.TypeCheat;
  end;
  FVrDirty := True;
end;

procedure TWebApp.VrAnswer(K: TVrDialog; Choice: Integer; const Text: string);
begin
  case K of
    vdCross: AnswerCross(Choice = 1);
    vdDelete: AnswerDelete(Choice = 1);
    vdOver:
      if Choice = 1 then FCtl.ActionRestartCampaign
      else if Choice = 2 then FCtl.ActionEraseEverything;
    vdInitials:
      if Choice = 0 then FinishInitials(Text) else FinishInitials('');
    vdRules: CloseRules;
  end;
  FVrDirty := True;
end;

{ What vr.js talks to: the panel's canvas, and the few things it asks the game to do. }
procedure TWebApp.InstallVrBridge;
var
  W, H: Integer;
  D: Double;
  EnterCb, ExitCb: TVrNotify;
  FrameCb: TVrFrameFn;
  TapCb: TVrTapFn;
  TableCb: TVrTableFn;
  SlotCb: TVrSlotFn;
  MarkCb: TVrMarkFn;
  BackCb: TVrBackFn;
  DebugCb: TVrDebugFn;
  StyleCb: TVrStyleFn;
  CheatsCb: TVrBoolFn;
begin
  W := VrW;
  H := VrH;
  D := VrDpr;
  EnterCb := @VrEnter;                    { (named here so that the compiler keeps them) }
  ExitCb := @VrExit;
  FrameCb := @VrFrame;
  TapCb := @VrTap;
  TableCb := @VrTable;
  SlotCb := @VrTapSlot;
  MarkCb := @VrMark;
  BackCb := @VrBack;
  DebugCb := @VrDebug;
  StyleCb := @VrStyle;
  CheatsCb := @VrSetCheats;
  asm
    window.TCVR = {
      canvas: this.FVrCanvas, width: W, height: H, dpr: D, barHeight: 84,
      enter: EnterCb, exit: ExitCb, frame: FrameCb, tap: TapCb,
      table: TableCb, tapSlot: SlotCb, mark: MarkCb, back: BackCb, debug: DebugCb, style: StyleCb, setCheats: CheatsCb
    };
  end;
end;

function TWebApp.OnEraseAll(Event: TEventListenerEvent): Boolean;
begin
  Show('dlgOver', False);
  FCtl.ActionEraseEverything;
  Result := True;
end;

function TWebApp.OnRestartCampaign(Event: TEventListenerEvent): Boolean;
begin
  Show('dlgOver', False);
  FCtl.ActionRestartCampaign;
  Result := True;
end;

function TWebApp.OnOverCancel(Event: TEventListenerEvent): Boolean;
begin
  Show('dlgOver', False);
  Result := True;
end;

function TWebApp.OnSkip(Event: TEventListenerEvent): Boolean;
begin
  UnlockAudio;
  FCtl.SkipPressed;
  Result := True;
end;

{ ---- starting up ---- }

procedure TWebApp.Boot;
begin
  FStory := TStory.Create;
  FStory.LoadFromText(GlueStory);
  PlayWavHandler := @WebPlayWav;
  FCanvas := TJSHTMLCanvasElement(El('table'));
  FStageBox := El('stage');
  FCtx := FCanvas.getContextAs2DContext('2d');
  FCtl := TGameController.Create(FStory);
  FCtl.AllowBottomPanel := True;          { tall screens put the panel under the table }
  FCtl.OnChange := @Changed;
  FView := TWebView.Create(FCtx, FCtl);
  FView.TouchScreen := IsTouchScreen;
  FVrCanvas := TJSHTMLCanvasElement(document.createElement('canvas'));
  FVrCanvas.width := Round(VrW * VrDpr);
  FVrCanvas.height := Round(VrH * VrDpr);
  FVrCtx := FVrCanvas.getContextAs2DContext('2d');
  FVrView := TWebView.Create(FVrCtx, FCtl);
  FVrView.TouchScreen := True;
  FVrPanel := TVrPanel.Create(FCtl, FVrView, FVrCtx);
  FVrPanel.OnButton := @VrButton;
  FVrPanel.OnAnswer := @VrAnswer;
  FVrPanel.OnInvalidate := @VrInvalidate;
  FitCanvas;
  FCtl.SetViewport(FW, FH);

  FCanvas.addEventListener('pointerdown', @OnPointerDown);
  window.addEventListener('keydown', @OnKeyDown);
  window.addEventListener('resize', @OnResize);
  window.addEventListener('orientationchange', @OnResize);
  Listen('btnNew', 'click', @OnNew);
  Listen('btnUndo', 'click', @OnUndo);
  Listen('btnHint', 'click', @OnHint);
  Listen('btnMode', 'click', @OnMode);
  Listen('btnStore', 'click', @OnStore);
  Listen('btnCards', 'click', @OnCards);
  Listen('btnCancel', 'click', @OnCancel);
  Listen('btnRecords', 'click', @OnRecords);
  Listen('rulesClose', 'click', @OnRulesClose);
  Listen('deleteKeep', 'click', @OnDeleteKeep);
  Listen('deleteGo', 'click', @OnDeleteGo);
  Listen('crossKeep', 'click', @OnCrossKeep);
  Listen('crossPlay', 'click', @OnCrossPlay);
  Listen('initialsOk', 'click', @OnInitialsOk);
  Listen('initialsSkip', 'click', @OnInitialsSkip);
  Listen('btnMenu', 'click', @OnMenu);
  Listen('btnStartOver', 'click', @OnStartOver);
  Listen('btnSkip', 'click', @OnSkip);
  Listen('btnEraseAll', 'click', @OnEraseAll);
  Listen('btnRestartCampaign', 'click', @OnRestartCampaign);
  Listen('btnOverCancel', 'click', @OnOverCancel);

  InstallVrBridge;                        { vr.js (the "Enter VR" button) finds the game here }
  GluePersist;                            { ask the browser not to clear our saves }
  Show('loading', False);
  FCtl.StartWithMenu;                     { the start menu first (a web page cannot quit) }
  ApplyUi;
  Invalidate;
end;

procedure TWebApp.Run;
var
  Pairs: TJSArray;
  Su, R: Integer;
  V: Integer;
const
  Suits: array[0..3] of string = ('clubs', 'diamonds', 'hearts', 'spades');
  Vamps: array[0..2] of string = ('jack', 'queen', 'king');
  SpecialArt: array[0..19] of string = ('extraturn', 'easyrule', 'dawn', 'wild', 'seer', 'stake', 'undo', 'hint',
    'trophy_firstwin', 'trophy_perfect', 'trophy_jack', 'trophy_queen', 'trophy_king', 'trophy_flawless',
    '', 'relic_garlic', 'relic_pick', 'relic_spoon', 'relic_locket', 'relic_moonstone');
begin
  Pairs := TJSArray.new;
  for Su := 0 to 3 do
    for R := 1 to 13 do
    begin
      Pairs.push('card_' + Suits[Su] + '_' + Format('%.2d', [R]));
      Pairs.push('assets/cards/card_' + Suits[Su] + '_' + Format('%.2d', [R]) + '.png');
    end;
  for V := 0 to 2 do
  begin
    Pairs.push('vampire_' + Vamps[V]);
    Pairs.push('assets/vampires/vampire_' + Vamps[V] + '.png');
    Pairs.push('vampire_' + Vamps[V] + '_fangs');
    Pairs.push('assets/vampires/vampire_' + Vamps[V] + '_fangs.png');
    Pairs.push('vampire_' + Vamps[V] + '_cup');
    Pairs.push('assets/vampires/vampire_' + Vamps[V] + '_cup.png');
  end;
  Pairs.push('house');
  Pairs.push('assets/house/house.png');
  for V := 1 to 3 do                       { the moons of the Style page }
  begin
    Pairs.push(HouseImageKey(V));
    Pairs.push('assets/house/' + HouseImageKey(V) + '.png');
  end;
  Pairs.push('win_screen');
  Pairs.push('assets/win/win_screen.png');
  Pairs.push('shopkeeper');
  Pairs.push('assets/shopkeeper/shopkeeper.png');
  for V := 0 to 19 do
    if SpecialArt[V] <> '' then
    begin
      Pairs.push('special_' + SpecialArt[V]);
      Pairs.push('assets/specials/special_' + SpecialArt[V] + '.png');
    end;
  GlueLoadImages(Pairs, @Boot);
end;

begin
  App := TWebApp.Create;
  App.Run;
end.
