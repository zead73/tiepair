program TestDuel;

{$mode objfpc}{$H+}

uses SysUtils, Classes, {$IFNDEF PAS2JS}IniFiles,{$ENDIF} Cards, Pyramid, Inventory, Session,
  Vampires, Story, Campaign, Duel, DuelSession, DuelInfo, Settings, Specials{$IFDEF PAS2JS}, JsCompat{$ENDIF};

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

function MakeCard(Rank: Integer): TCard;
begin
  Result.Suit := suSpades;
  Result.Rank := Rank;
  Result.FaceUp := False;
end;

{ 28 pyramid cards, then 24 stock cards (the waste rank is not used in Pyramid). }
function BuildDeck(const TabRanks: array of Integer; StockRank, WasteRank: Integer): TDeck;
var
  A: TCardArray;
  I: Integer;
begin
  SetLength(A, 52);
  for I := 0 to 27 do A[I] := MakeCard(TabRanks[I]);
  for I := 28 to 51 do A[I] := MakeCard(StockRank);
  Result := TDeck.CreateFromCards(A);
end;

type
  { dmWin: a pyramid of Kings (28 taps clear it; a draw would be a missed move).
    dmStuck: a pyramid of Queens and a stock of 7s: nothing ever goes. }
  TDeckMode = (dmWin, dmStuck, dmWinSevens);
  TDecks = class
  public
    Mode: TDeckMode;
    Dealt: Integer;
    function Next: TDeck;
  end;

function TDecks.Next: TDeck;
var
  R: array[0..27] of Integer;
  I: Integer;
begin
  Inc(Dealt);
  if Mode in [dmWin, dmWinSevens] then
  begin
    for I := 0 to 27 do R[I] := 13;
    Result := BuildDeck(R, 7, 7);
  end
  else
  begin
    for I := 0 to 27 do R[I] := 12;
    Result := BuildDeck(R, 7, 7);
  end;
end;

{ Takes away the rigged winning hand's Kings, front-most first. }
procedure WinHand(DS: TDuelSession);
var
  A, B, Guard: Integer;
begin
  Guard := 0;
  while (DS.Duel.State = dsPlaying) and DS.Session.Game.FindRemoval(0, A, B) and (Guard < 100) do
  begin
    Inc(Guard);
    DS.Remove(A, B);
  end;
end;

{ Draws and turns over until the stock and its turn-overs are used up (or the hand ends,
  or the duel waits for the player to use an undo card). }
procedure ExhaustStock(DS: TDuelSession);
var
  Guard: Integer;
begin
  Guard := 0;
  while (DS.Duel.State = dsPlaying) and not DS.StuckWaiting and (Guard < 400) and (DS.DrawStock or DS.Recycle) do
    Inc(Guard);
end;

{ Duel only: four wins (each followed by its hit scene), then the fifth, which
  is left at the fatal blow. }
procedure ToFatalBlow(D: TDuel);
var
  I: Integer;
begin
  for I := 1 to WinsToKill - 1 do
  begin
    D.HandWon;
    D.SceneDone;
  end;
  D.HandWon;
end;

{ With rigged winning decks: wins WinsToKill hands, leaving the duel at the
  fatal blow. Each earlier win's hit scene is finished (which deals the next hand). }
procedure WinDuel(DS: TDuelSession);
var
  I: Integer;
begin
  for I := 1 to WinsToKill do
  begin
    WinHand(DS);
    if I < WinsToKill then DS.SceneDone;
  end;
end;

function StoryPath: string;
begin
{$IFDEF PAS2JS}
  Result := 'assets/story/story.ini';          { run from the project folder }
{$ELSE}
  Result := ExtractFilePath(ParamStr(0)) + '../assets/story/story.ini';
{$ENDIF}
end;

procedure TestStory;
var
  St: TStory;
  V, T: Integer;
  Missing: TStringArray;
  Names, Lines: TStringList;
begin
  St := TStory.Create;
  Names := TStringList.Create;
  try
    St.LoadFromFile(StoryPath);
    Missing := St.Validate;
    if Length(Missing) > 0 then
      Check(False, 'the shipped story file is missing: ' + Missing[0])
    else
      Check(True, 'the shipped story file has every required entry');
    for V := 0 to VampireCount - 1 do
    begin
      Check(St.Name(V) <> '', 'vampire ' + IntToStr(V) + ' has a name');
      Check(St.Title(V) <> '', 'vampire ' + IntToStr(V) + ' has a title');
      Check(Length(St.Intro(V)) >= 1, 'vampire ' + IntToStr(V) + ' has an intro');
      Check(Length(St.Strike(V)) >= 1, 'vampire ' + IntToStr(V) + ' has a strike line');
      Check(Length(St.Defeat(V)) >= 1, 'vampire ' + IntToStr(V) + ' has a defeat line');
      for T := 1 to 3 do
        Check(Length(St.Taunt(V, T)) >= 1, 'vampire ' + IntToStr(V) + ' has a tier ' + IntToStr(T) + ' taunt');
      Check(Names.IndexOf(St.Name(V)) < 0, 'vampire names are distinct');
      Names.Add(St.Name(V));
    end;
    for V := 0 to VampireCount - 1 do
      for T := 1 to WinsToKill - 1 do
        Check(Length(St.Hit(V, T)) >= 1, 'vampire ' + IntToStr(V) + ' has a line for win ' + IntToStr(T));
    Check(St.Hit(0, 0)[0] = St.Hit(0, 1)[0], 'win 0 uses the first hit line');
    Check(St.Hit(0, 9)[0] = St.Hit(0, WinsToKill - 1)[0], 'a win past the last hit uses the last hit line');
    Check(St.Hit(0, 1)[0] <> St.Hit(0, 2)[0], 'each hit has its own line');
    Check(St.HitPaidFormat <> '', 'the hit pay line exists');
    Check(St.Taunt(0, 0)[0] = St.Taunt(0, 1)[0], 'tier 0 uses the tier 1 taunt');
    Check(St.Taunt(0, 9)[0] = St.Taunt(0, 3)[0], 'tier 9 uses the tier 3 taunt');
    Check(Length(St.Premise) >= 1, 'campaign has a premise');
    Check(Pos('"', St.Premise[1]) > 0, 'quotes inside a line are kept');
    Check(St.CampaignTitle <> '', 'campaign has a title');
    Check(Length(St.Finale) >= 1, 'finale has lines');
    Check(St.FinaleCaption = 'I can''t believe you won. Twice.', 'finale caption matches the win screen');

    { a story file that lacks one vampire's hit line is reported }
    St.LoadFromFile(StoryPath);
    Lines := TStringList.Create;
    try
      Lines.LoadFromFile(StoryPath);
      for T := Lines.Count - 1 downto 0 do
        if Pos('hit3.1=', Lines[T]) = 1 then Lines.Delete(T);
      St.LoadFromText(Lines.Text);
    finally
      Lines.Free;
    end;
    Missing := St.Validate;
    Check((Length(Missing) = VampireCount) and (Pos('hit3.1', Missing[0]) > 0),
      'a missing hit line is reported for each vampire');
    St.LoadFromFile(StoryPath);

    { numbered lines stop at the first gap, and blank / missing entries are reported }
    St.LoadFromText('[jack]'#10'intro.1=one'#10'intro.2=two'#10'intro.4=four'#10);
    Check(Length(St.Intro(0)) = 2, 'lines stop at a gap (got ' + IntToStr(Length(St.Intro(0))) + ')');
    Check(St.Intro(0)[1] = 'two', 'lines are in order');
    Missing := St.Validate;
    Check(Length(Missing) > 10, 'a nearly empty story file reports many missing entries');
    Check(St.Name(1) = '', 'a missing entry reads as empty, not an error');
  finally
    St.Free;
    Names.Free;
  end;
end;

procedure TestCampaign;
var
  C, C2: TCampaign;
  F: string;
  Ini: TIniFile;
begin
  C := TCampaign.Create('');
  try
    Check((C.Current = 0) and (C.LostHands = 0), 'fresh campaign starts at the first vampire');
    Check(not C.IsComplete, 'not complete at the start');
    C.AddLostHand;
    C.AddLostHand;
    Check(C.LostHands = 2, 'lost hands count up');
    C.Advance;
    Check((C.Current = 1) and (C.LostHands = 0), 'advancing moves on and clears lost hands');
    C.Advance;
    C.Advance;
    Check(C.IsComplete and (C.Current = VampireCount), 'three victories complete it');
    C.Advance;
    Check(C.Current = VampireCount, 'cannot advance past the end');
    C.AddLostHand;
    Check(C.LostHands = 0, 'no lost hands once complete');
    C.Reset;
    Check((C.Current = 0) and not C.IsComplete, 'reset starts over');
  finally
    C.Free;
  end;

  { wins }
  C := TCampaign.Create('');
  try
    Check(C.Wins = 0, 'no wins at the start');
    Check(not C.RecordWin and (C.Wins = 1), 'the first win is not the kill');
    C.AddLostHand;
    C.AddLostHand;
    Check(C.LostHands = 2, 'two lost hands');
    Check(not C.RecordWin and (C.Wins = 2), 'a second win');
    Check(C.LostHands = 0, 'a win clears the lost-hand count');
    Check(not C.RecordWin and not C.RecordWin, 'wins three and four are not the kill');
    Check(C.TotalLost = 2, 'the lost hands in the whole duel are counted (a win only forgets the cut)');
    Check(C.Wins = WinsToKill - 1, 'four wins');
    Check(C.RecordWin, 'the fifth win is the kill');
    Check(C.Wins = WinsToKill, 'five wins are counted');
    C.Advance;
    Check((C.Current = 1) and (C.Wins = 0), 'the next vampire starts with no wins');
    Check(C.TotalLost = 0, 'and no lost hands');
    C.RecordWin;
    C.Reset;
    Check(C.Wins = 0, 'reset clears the wins');
    C.Advance; C.Advance; C.Advance;
    Check(not C.RecordWin and (C.Wins = 0), 'no wins to record once complete');
  finally
    C.Free;
  end;

  F := GetTempDir + 'tiepair_test_campaign.ini';
  if FileExists(F) then DeleteFile(F);
  C := TCampaign.Create(F);
  try
    C.Advance;
    C.AddLostHand;
    C.AddLostHand;
  finally
    C.Free;
  end;
  C2 := TCampaign.Create(F);
  try
    Check((C2.Current = 1) and (C2.LostHands = 2), 'progress survives save and load');
    C2.RecordWin;
    C2.RecordWin;
    C2.AddLostHand;
  finally
    C2.Free;
  end;

  C2 := TCampaign.Create(F);
  try
    Check((C2.Wins = 2) and (C2.LostHands = 1), 'wins and lost hands survive save and load');
    Check(C2.TotalLost = 3, 'and the duel total (2 earlier + 1)');
    Check(C2.Current = 1, 'on the same vampire');
    C2.RecordWin; C2.RecordWin; C2.RecordWin;       { the kill, saved at once }
  finally
    C2.Free;
  end;
  C2 := TCampaign.Create(F);
  try
    Check((C2.Current = 2) and (C2.Wins = 0) and (C2.LostHands = 0),
      'a vampire killed before quitting stays dead, and the next duel starts clean');
  finally
    C2.Free;
  end;
  Ini := TIniFile.Create(F);
  try
    Ini.WriteInteger('Campaign', 'Current', 0);
    Ini.WriteInteger('Campaign', 'Wins', -2);
    Ini.WriteBool('Campaign', 'KillPending', False);
  finally
    Ini.Free;
  end;
  C2 := TCampaign.Create(F);
  try
    Check(C2.Wins = 0, 'a negative win count is cleared');
  finally
    C2.Free;
  end;
  Ini := TIniFile.Create(F);
  try
    Ini.WriteInteger('Campaign', 'Current', 0);
    Ini.WriteInteger('Campaign', 'Wins', 99);
    Ini.WriteBool('Campaign', 'KillPending', False);
  finally
    Ini.Free;
  end;
  C2 := TCampaign.Create(F);
  try
    Check((C2.Current = 1) and (C2.Wins = 0), 'five or more saved wins count as a kill');
  finally
    C2.Free;
  end;
  Ini := TIniFile.Create(F);
  try
    Ini.WriteInteger('Campaign', 'Current', 0);
    Ini.WriteInteger('Campaign', 'Wins', 3);
    Ini.WriteBool('Campaign', 'KillPending', False);
  finally
    Ini.Free;
  end;
  C2 := TCampaign.Create(F);
  try
    Check((C2.Current = 0) and (C2.Wins = 3), 'a normal win count is kept');
  finally
    C2.Free;
  end;

  { a damaged or hand-edited file is made safe }
  Ini := TIniFile.Create(F);
  try
    Ini.WriteInteger('Campaign', 'Current', 99);
    Ini.WriteInteger('Campaign', 'LostHands', -4);
  finally
    Ini.Free;
  end;
  C2 := TCampaign.Create(F);
  try
    Check(C2.Current = VampireCount, 'an out-of-range vampire is clamped');
    Check(C2.LostHands = 0, 'a negative or finished lost-hand count is cleared');
  finally
    C2.Free;
  end;
  Ini := TIniFile.Create(F);
  try
    Ini.WriteInteger('Campaign', 'Current', -3);
    Ini.WriteInteger('Campaign', 'LostHands', 7);
  finally
    Ini.Free;
  end;
  C2 := TCampaign.Create(F);
  try
    Check(C2.Current = 0, 'a negative vampire is clamped to the first');
    Check(C2.LostHands = 7, 'lost hands kept for an unfinished duel');
  finally
    C2.Free;
  end;
  DeleteFile(F);
  C2 := TCampaign.Create(F);                   { missing file = fresh }
  try
    Check((C2.Current = 0) and (C2.LostHands = 0), 'a missing file starts fresh');
  finally
    C2.Free;
  end;
end;

procedure TestDuelMachine;
var
  C: TCampaign;
  D: TDuel;
  V, N: Integer;
begin
  C := TCampaign.Create('');
  D := TDuel.Create(C);
  try
    Check(D.State = dsIntro, 'a duel starts with the intro');
    Check(not D.InProgress, 'a new vampire has not been fought yet');
    Check(not D.HandWon, 'cannot win a hand during the intro');
    Check(not D.HandLost(lrStuck), 'cannot lose a hand during the intro');
    Check(D.State = dsIntro, 'illegal events change nothing');
    Check(D.SceneDone and (D.State = dsPlaying), 'the intro leads to play');
    Check(not D.SceneDone, 'there is no scene to finish while playing');

    { wins 1-4 are hits: paid at once, then straight back to play }
    Check(not D.NextWinKills, 'the first win is not the kill');
    Check(D.KillBonus = 0, 'so there is no bonus');
    Check(D.HandWon and (D.State = dsHit), 'a win is a hit');
    Check(D.Wins = 1, 'one win');
    Check(D.LastReward.Coins = VampireWinCoins[0], 'a hit pays the per-win coins');
    Check(D.LastReward.UndoCards = 0, 'a hit pays no undo card');
    Check(D.LastReward.HintCards = HitHintCards, 'a hit pays a hint card');
    Check(not D.HandWon, 'cannot win twice');
    Check(D.InProgress, 'the vampire has now been fought');
    Check(D.SceneDone and (D.State = dsPlaying), 'the hit scene leads straight back to play (no new intro)');
    D.HandWon; D.SceneDone;
    D.HandWon; D.SceneDone;
    Check(D.Wins = 3, 'three wins');
    Check(D.HandWon and (D.State = dsHit) and (D.Wins = 4), 'the fourth win is still a hit');
    D.SceneDone;

    { the fifth is the kill }
    Check(D.NextWinKills, 'the next win kills');
    Check(D.KillBonus = VampireKillBonus[0], 'and carries the kill bonus');
    Check(D.HandWon and (D.State = dsFatalBlow), 'the fifth win is the fatal blow');
    Check(D.LastReward.Coins = VampireWinCoins[0] + VampireKillBonus[0], 'the kill pays the per-win coins plus the bonus');
    Check(D.LastReward.UndoCards = WinUndoCards, 'the kill pays the undo card');
    Check(D.LastReward.HintCards = WinHintCards, 'the kill pays the hint cards');
    Check(D.SceneDone and (D.State = dsDefeated), 'blow scene leads to the defeat scene');
    Check(D.SceneDone and (D.State = dsIntro), 'defeat scene leads to the next intro');
    Check((D.Vampire = 1) and (D.Wins = 0), 'the next vampire is up with no wins');
    Check(not D.InProgress, 'and has not been fought');
    D.SceneDone;
    Check(D.Spoils = VampireWinCoins[1], 'the second vampire pays his own per-win coins');

    { a lost hand: free round, no game over, the next win pays less, tier rises }
    Check(D.Tier = 0, 'no taunt tier before any loss');
    Check(D.HandLost(lrStuck) and (D.State = dsFreeRound), 'a lost hand gives the free round');
    Check(D.LastLoss = lrStuck, 'the loss reason is kept');
    Check((D.LostHands = 1) and (D.Tier = 1), 'one lost hand, tier 1');
    Check(D.Spoils = VampireWinCoins[1] - SpoilsStep, 'the next win pays one step less');
    Check(not D.HandLost(lrStuck), 'cannot lose a hand during the free round');
    Check(D.SceneDone and (D.State = dsPlaying), 'the free round leads back to play');
    Check(D.InProgress, 'a lost hand also counts as having fought him');
    D.HandLost(lrConceded);
    Check(D.LastLoss = lrConceded, 'conceding is recorded as such');
    D.SceneDone;
    D.HandLost(lrStuck);
    D.SceneDone;
    Check(D.Tier = 3, 'tier caps at 3 after three lost hands');
    D.HandLost(lrStuck);
    D.SceneDone;
    Check(D.Tier = 3, 'tier stays at 3 after four');
    Check(D.LostHands = 4, 'lost hands keep counting');
    Check(D.Spoils = VampireWinCoins[1] - 4 * SpoilsStep, 'four lost hands: four steps off');
    N := 0;
    while (D.Spoils > SpoilsFloor) and (N < 40) do      { lose until the pay reaches the floor }
    begin
      D.HandLost(lrStuck);
      D.SceneDone;
      Inc(N);
    end;
    Check(D.Spoils = SpoilsFloor, 'the cut reaches the floor');
    D.HandLost(lrStuck);
    D.SceneDone;
    Check(D.Spoils = SpoilsFloor, 'the cut stops at the floor');
    Check(D.HandWon and (D.LastReward.Coins = SpoilsFloor), 'the win pays the floor');
    Check(D.LostHands = 0, 'a win forgets the lost hands');
    Check(D.Tier = 0, 'and the taunts start again');
    D.SceneDone;
    Check(D.Spoils = VampireWinCoins[1], 'the next win pays in full again');
    Check(D.Wins = 1, 'the lost hands never took a win away');

    { the cut applies to the next win only }
    D.HandLost(lrStuck); D.SceneDone;
    Check(D.Spoils = VampireWinCoins[1] - SpoilsStep, 'one lost hand: a step off');
    D.HandWon; D.SceneDone;
    Check(D.Spoils = VampireWinCoins[1], 'and it is forgotten after the win');
    Check(D.Wins = 2, 'two wins');

    { the kill bonus is not cut by lost hands }
    D.HandWon; D.SceneDone;                           { win 3 }
    D.HandWon; D.SceneDone;                           { win 4 }
    for V := 1 to 20 do begin D.HandLost(lrStuck); D.SceneDone; end;
    Check(D.NextWinKills, 'the next win kills');
    Check(D.HandWon and (D.State = dsFatalBlow), 'the kill');
    Check(D.LastReward.Coins = SpoilsFloor + VampireKillBonus[1],
      'the kill bonus survives any number of lost hands');
    D.SceneDone; D.SceneDone;                         { blow, defeat }
    Check((D.Vampire = 2) and (D.State = dsIntro) and (D.LostHands = 0) and (D.Wins = 0),
      'the next duel starts with a clean slate');

    { a hundred lost hands: still playing, still the floor }
    D.SceneDone;
    for V := 1 to 100 do
    begin
      D.HandLost(lrStuck);
      D.SceneDone;
    end;
    Check(D.Spoils = SpoilsFloor, 'the pay bottoms out at the floor');
    Check(D.State = dsPlaying, 'a hundred lost hands still leave you playing: no game over');

    { the third kill completes the campaign }
    ToFatalBlow(D);
    D.SceneDone; D.SceneDone;
    Check(D.State = dsComplete, 'beating the last vampire completes the campaign');
    Check(C.IsComplete, 'and the campaign record says so');
    Check(not D.SceneDone, 'nothing to finish once complete');
    Check(not D.HandWon, 'no hand to win once complete');
    Check(D.Spoils = 0, 'nothing more to win');
    Check(not D.NextWinKills and (D.KillBonus = 0) and not D.InProgress, 'and no kill pending');
  finally
    D.Free;
    C.Free;
  end;
end;

procedure TestDuelMisses;
var
  C: TCampaign;
  D: TDuel;
  S: TGameSession;
  DS: TDuelSession;
  Decks: TDecks;
  Coins0, I: Integer;
begin
  C := TCampaign.Create('');
  D := TDuel.Create(C);
  try
    D.SceneDone;
    Check(D.HandWon(2) and (D.LastReward.Coins = VampireWinCoins[0] - 2 * MissPenaltyCoins),
      'a win pays less for each missed move');
    D.SceneDone;
    D.HandWon; D.SceneDone; D.HandWon; D.SceneDone; D.HandWon; D.SceneDone;   { wins 2-4 }
    { the fifth: misses cut the per-win part only, never the bonus }
    Check(D.HandWon(2) and (D.LastReward.Coins
      = VampireWinCoins[0] - 2 * MissPenaltyCoins + VampireKillBonus[0]),
      'the kill bonus is not cut by missed moves');
    D.SceneDone; D.SceneDone; D.SceneDone;               { blow, defeat, intro }
    D.HandLost(lrStuck);                                  { one lost hand, then ... }
    D.SceneDone;
    Check(D.HandWon(2) and (D.LastReward.Coins = VampireWinCoins[1] - SpoilsStep - 2 * MissPenaltyCoins),
      'lost hands and misses add up');
    D.SceneDone;
    Check(D.HandWon(1000) and (D.LastReward.Coins = SpoilsFloor), 'many misses still pay the floor');
    D.SceneDone;
    D.HandWon; D.SceneDone;
    D.HandWon; D.SceneDone;                              { wins 3 and 4 }
    Check(D.HandWon(1000) and (D.LastReward.Coins = SpoilsFloor + VampireKillBonus[1]),
      'a hundred misses cut the per-win part to the floor but never touch the bonus');
  finally
    D.Free;
    C.Free;
  end;

  S := TGameSession.Create('');
  S.HazardsOn := False;                       { the tricks have their own tests }
  C := TCampaign.Create('');
  DS := TDuelSession.Create(S, C);
  Decks := TDecks.Create;
  try
    DS.OnNeedDeck := @Decks.Next;
    DS.Activate;
    Decks.Mode := dmWinSevens;
    DS.SceneDone;
    Check(DS.PayoutNow = VampireWinCoins[0], 'the preview starts at the full per-win pay');
    Coins0 := S.Inventory.Coins;
    for I := 1 to 2 do DS.DrawStock;                     { the winning deck has moves available: misses }
    Check(S.Misses = 2, 'two misses in the duel');
    Check(DS.PayoutNow = VampireWinCoins[0] - 2 * MissPenaltyCoins, 'the preview shrinks');
    WinHand(DS);
    Check(DS.Duel.State = dsHit, 'the hand is still won: a hit');
    Check(S.Inventory.Coins = Coins0 + VampireWinCoins[0] - 2 * MissPenaltyCoins, 'and the reduced pay was paid');
    Check(DS.LastPaid.Coins = VampireWinCoins[0] - 2 * MissPenaltyCoins, 'LastPaid says so');
    { before the killing win the preview includes the bonus }
    DS.SceneDone;
    DS.Duel.HandWon; DS.SceneDone;                        { wins 2, 3 and 4 (rules only) }
    DS.Duel.HandWon; DS.SceneDone;
    DS.Duel.HandWon; DS.SceneDone;
    Check(DS.Duel.NextWinKills, 'the next win kills');
    Check(DS.PayoutNow = VampireWinCoins[0] + VampireKillBonus[0], 'the preview shows the bonus');
  finally
    Decks.Free; DS.Free; C.Free; S.Free;
  end;
end;

procedure TestDuelInfo;
var
  S: TGameSession;
  C: TCampaign;
  DS: TDuelSession;
  Decks: TDecks;
  St: TStory;
  Inf: TDuelInfo;
  I: Integer;
begin
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  S := TGameSession.Create('');
  S.HazardsOn := False;                       { the tricks have their own tests }
  C := TCampaign.Create('');
  DS := TDuelSession.Create(S, C);
  Decks := TDecks.Create;
  try
    DS.OnNeedDeck := @Decks.Next;
    DS.Activate;
    Decks.Mode := dmWinSevens;
    DS.SceneDone;
    Inf := GetDuelInfo(DS, St);
    Check(Inf.Active and (Inf.Vampire = 0) and (Inf.DuelNumber = 1) and (Inf.DuelCount = VampireCount), 'the first duel');
    Check((Inf.Name = St.Name(0)) and (Inf.Title = St.Title(0)), 'with the story''s name and title');
    Check((Inf.PerWin = VampireWinCoins[0]) and (Inf.PayNow = VampireWinCoins[0]), 'full pay to begin with');
    Check((Inf.Wins = 0) and (Inf.WinsNeeded = WinsToKill) and (Inf.KillBonus = 0), 'no wins yet, no bonus yet');
    Check((Inf.LostHandsCut = 0) and (Inf.MissCut = 0) and not Inf.AtFloor, 'nothing taken off yet');

    for I := 1 to 2 do DS.DrawStock;                    { two missed moves }
    Inf := GetDuelInfo(DS, St);
    Check((Inf.Misses = 2) and (Inf.MissCut = 2 * MissPenaltyCoins), 'misses are counted');
    Check(Inf.PayNow = Inf.PerWin - Inf.LostHandsCut - Inf.MissCut + Inf.KillBonus, 'the lines add up to what is paid');
    Check(Inf.PayNow = DS.PayoutNow, 'and match the controller''s figure');

    DS.Concede;                                          { a lost hand }
    DS.SceneDone;
    Inf := GetDuelInfo(DS, St);
    Check((Inf.LostHands = 1) and (Inf.LostHandsCut = SpoilsStep), 'a lost hand is counted');
    Check(Inf.Misses = 0, 'misses start over with the new hand');
    Check(Inf.PayNow = Inf.PerWin - SpoilsStep, 'pay reflects the lost hand');

    { the floor }
    for I := 1 to 40 do
    begin
      DS.Concede;
      DS.SceneDone;
    end;
    Inf := GetDuelInfo(DS, St);
    Check(Inf.PayNow = SpoilsFloor, 'pay bottoms out at the floor');
    Check(Inf.AtFloor, 'and the panel is told the minimum is holding it up');
    Check(Inf.LostHandsCut = Inf.PerWin - SpoilsFloor, 'the cut shown is the real one, not the plain sum');
    Check(Inf.PayNow = DS.PayoutNow, 'still matching the controller');

    { wins fill the pips; the fifth shows the bonus }
    DS.Duel.HandWon; DS.SceneDone;                       { rules only: win 1 }
    DS.Duel.HandWon; DS.SceneDone;
    Inf := GetDuelInfo(DS, St);
    Check((Inf.Wins = 2) and (Inf.LostHands = 0) and (Inf.LostHandsCut = 0), 'two wins, and the cut is forgotten');
    Check(Inf.PayNow = Inf.PerWin, 'full pay again');
    DS.Duel.HandWon; DS.SceneDone;
    DS.Duel.HandWon; DS.SceneDone;
    Inf := GetDuelInfo(DS, St);
    Check((Inf.Wins = WinsToKill - 1) and (Inf.KillBonus = VampireKillBonus[0]), 'the next win is the kill');
    Check(Inf.PayNow = Inf.PerWin + Inf.KillBonus, 'its pay includes the bonus');
    Check(Inf.PayNow = DS.PayoutNow, 'matching the controller');
    DS.Concede; DS.SceneDone;
    Inf := GetDuelInfo(DS, St);
    Check(Inf.PayNow = Inf.PerWin - SpoilsStep + Inf.KillBonus, 'a lost hand cuts the per-win part only');
    Check(not Inf.AtFloor, 'not at the floor');

    { second vampire, then the end }
    WinHand(DS);
    Decks.Mode := dmWin;
    DS.SceneDone; DS.SceneDone;
    Inf := GetDuelInfo(DS, St);
    Check((Inf.Vampire = 1) and (Inf.DuelNumber = 2) and (Inf.Name = St.Name(1)), 'the second duel');
    Check((Inf.PerWin = VampireWinCoins[1]) and (Inf.Wins = 0), 'with its own pay and no wins');
    C.Advance; C.Advance;
    DS.Duel.Start;
    Inf := GetDuelInfo(DS, St);
    Check(not Inf.Active, 'no panel once the campaign is complete');
  finally
    Decks.Free; DS.Free; C.Free; S.Free; St.Free;
  end;

  { stuck with an undo card is reported }
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  S := TGameSession.Create('');
  S.HazardsOn := False;                       { the tricks have their own tests }
  C := TCampaign.Create('');
  DS := TDuelSession.Create(S, C);
  Decks := TDecks.Create;
  try
    Decks.Mode := dmStuck;
    DS.OnNeedDeck := @Decks.Next;
    S.Inventory.AddUndoCards(1);
    DS.Activate;
    DS.SceneDone;
    ExhaustStock(DS);
    Check(GetDuelInfo(DS, St).StuckWaiting, 'the panel is told to show the stuck prompt');
    DS.UseUndo;
    Check(not GetDuelInfo(DS, St).StuckWaiting, 'and to drop it after the undo');
  finally
    Decks.Free; DS.Free; C.Free; S.Free; St.Free;
  end;
end;

{ Each vampire's hands follow his level (wrap, stock size). }
procedure TestLevels;
var
  S: TGameSession;
  C: TCampaign;
  DS: TDuelSession;
  Decks: TDecks;
  St: TStory;
  V: Integer;
  Inf: TDuelInfo;
begin
  for V := 0 to VampireCount - 1 do
    Check((VampireRecycles[V] >= 1) and (VampireRecycles[V] <= 9),
      'vampire ' + IntToStr(V) + ' has a possible number of turn-overs');
  Check(VampireEasy[0], 'the first level has the Easy rule');
  Check(VampireRecycles[1] < VampireRecycles[0], 'the second level allows fewer turn-overs');
  Check(not VampireEasy[1] and not VampireEasy[2], 'the second and third levels are plain Pyramid');

  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  S := TGameSession.Create('');
  S.HazardsOn := False;                       { the tricks have their own tests }
  C := TCampaign.Create('');
  DS := TDuelSession.Create(S, C);
  Decks := TDecks.Create;
  try
    Decks.Mode := dmWin;
    DS.OnNeedDeck := @Decks.Next;
    DS.Activate;
    for V := 0 to VampireCount - 1 do
    begin
      DS.SceneDone;                                       { the intro: the first hand }
      Check(S.Game.MaxRecycles = VampireRecycles[V], 'vampire ' + IntToStr(V) + ': the turn-overs');
      Check(S.Game.UnderPairs = VampireEasy[V], 'vampire ' + IntToStr(V) + ': the Easy rule');
      Inf := GetDuelInfo(DS, St);
      Check((Inf.Recycles = VampireRecycles[V]) and (Inf.Easy = VampireEasy[V]),
        'vampire ' + IntToStr(V) + ': the panel is told the same');
      DS.Concede;                                         { a lost hand: the same level again }
      DS.SceneDone;
      Check((S.Game.MaxRecycles = VampireRecycles[V]) and (S.Game.UnderPairs = VampireEasy[V]),
        'vampire ' + IntToStr(V) + ': the next hand is the same level');
      WinDuel(DS);                                        { five wins: the vampire falls }
      DS.SceneDone; DS.SceneDone;
    end;
    Check(DS.Duel.State = dsComplete, 'campaign complete');
    Check(not GetDuelInfo(DS, St).Active, 'no level to show once complete');
    DS.Deactivate;
    Check(not S.Easy and (S.Recycles = DefaultRecycles), 'leaving the campaign restores the ordinary rules');
    S.NewGame;
    Check((S.Game.StockCount = StockStart) and not S.Game.UnderPairs and (S.Game.MaxRecycles = DefaultRecycles),
      'so a Free Play deal is ordinary');
  finally
    Decks.Free; DS.Free; C.Free; S.Free; St.Free;
  end;
end;

procedure TestSettings;
var
  F, G: string;
  St, St2: TSettings;
  C: TCampaign;
  Ini: TIniFile;
begin
  F := GetTempDir + 'tiepair_test_settings.ini';
  G := GetTempDir + 'tiepair_test_settings_campaign.ini';
  if FileExists(F) then DeleteFile(F);
  if FileExists(G) then DeleteFile(G);

  St := TSettings.Create(F);
  C := TCampaign.Create(G);
  try
    Check(St.Mode = gmFreePlay, 'a missing file starts in Free Play');
    Check(not ShouldResumeCampaign(St, C), 'and does not resume a campaign');
    St.Mode := gmCampaign;
    St.Save;
  finally
    St.Free;
  end;
  St2 := TSettings.Create(F);
  try
    Check(St2.Mode = gmCampaign, 'the mode survives save and load');
    Check(ShouldResumeCampaign(St2, C), 'a campaign in progress is resumed');

    C.Advance; C.Advance;                          { one vampire to go }
    Check(ShouldResumeCampaign(St2, C), 'still resumed with the last vampire to fight');
    C.Advance;                                     { finished }
    Check(not ShouldResumeCampaign(St2, C), 'a finished campaign is never restarted for you');
    C.Reset;
    St2.Mode := gmFreePlay;
    St2.Save;
  finally
    St2.Free;
  end;
  St := TSettings.Create(F);
  try
    Check(St.Mode = gmFreePlay, 'switching back to Free Play is remembered');
    Check(not ShouldResumeCampaign(St, C), 'and not resumed');
  finally
    St.Free;
  end;

  { garbage in the file means Free Play, not a crash }
  Ini := TIniFile.Create(F);
  try
    Ini.WriteString('Settings', 'Mode', 'banana');
  finally
    Ini.Free;
  end;
  St := TSettings.Create(F);
  try
    Check(St.Mode = gmFreePlay, 'an unknown mode reads as Free Play');
  finally
    St.Free;
  end;
  Ini := TIniFile.Create(F);
  try
    Ini.WriteString('Settings', 'Mode', 'campaign');          { case does not matter }
  finally
    Ini.Free;
  end;
  St := TSettings.Create(F);
  try
    Check(St.Mode = gmCampaign, 'the mode name is not case sensitive');
  finally
    St.Free;
  end;

  { no file name: never touches the disk }
  St := TSettings.Create('');
  try
    St.Mode := gmCampaign;
    St.Save;
    Check(St.Mode = gmCampaign, 'an unsaved settings object just holds its value');
  finally
    St.Free;
  end;
  C.Free;
  DeleteFile(F);
  DeleteFile(G);
end;

procedure TestPremiseSeen;
var
  F: string;
  C, C2: TCampaign;
begin
  F := GetTempDir + 'tiepair_test_premise.ini';
  if FileExists(F) then DeleteFile(F);
  C := TCampaign.Create(F);
  try
    Check(not C.PremiseSeen, 'a new campaign has not shown its premise');
    C.MarkPremiseSeen;
    Check(C.PremiseSeen, 'marking it works');
    C.Advance;
    Check(C.PremiseSeen, 'moving on does not clear it');
  finally
    C.Free;
  end;
  C2 := TCampaign.Create(F);
  try
    Check(C2.PremiseSeen, 'it survives save and load (so quitting does not replay the opening)');
    C2.Reset;
    Check(not C2.PremiseSeen, 'starting the campaign over shows the opening again');
  finally
    C2.Free;
  end;
  C2 := TCampaign.Create(F);
  try
    Check(not C2.PremiseSeen, 'and that is saved too');
  finally
    C2.Free;
  end;
  DeleteFile(F);
end;

procedure TestResume;
var
  F: string;
  C: TCampaign;
  D: TDuel;
begin
  F := GetTempDir + 'tiepair_test_resume.ini';
  if FileExists(F) then DeleteFile(F);
  C := TCampaign.Create(F);
  D := TDuel.Create(C);
  try
    D.SceneDone; ToFatalBlow(D); D.SceneDone; D.SceneDone;  { beat the first vampire }
    D.SceneDone;
    D.HandWon; D.SceneDone;                                { one win on the second }
    D.HandLost(lrStuck);
    D.SceneDone;
    D.HandLost(lrConceded);                                { then two lost hands }
  finally
    D.Free;
    C.Free;
  end;
  C := TCampaign.Create(F);                                { "quit and come back" }
  D := TDuel.Create(C);
  try
    Check(D.State = dsIntro, 'resuming starts at the intro');
    Check(D.Vampire = 1, 'resumes at the second vampire');
    Check(D.LostHands = 2, 'the lost hands are remembered');
    Check(D.Wins = 1, 'and the win');
    Check(D.Spoils = VampireWinCoins[1] - 2 * SpoilsStep, 'so is the shrunken pay');
    Check(D.InProgress, 'the vampire counts as already met (no second intro)');
  finally
    D.Free;
    C.Free;
  end;
  { a finished campaign resumes as complete }
  C := TCampaign.Create(F);
  try
    C.Advance; C.Advance;
  finally
    C.Free;
  end;
  C := TCampaign.Create(F);
  D := TDuel.Create(C);
  try
    Check(D.State = dsComplete, 'a finished campaign resumes as complete');
  finally
    D.Free;
    C.Free;
  end;
  DeleteFile(F);
end;

procedure TestSessionWin;
var
  S: TGameSession;
  C: TCampaign;
  DS: TDuelSession;
  Decks: TDecks;
  Coins0: Integer;
begin
  S := TGameSession.Create('');
  S.HazardsOn := False;                       { the tricks have their own tests }
  C := TCampaign.Create('');
  DS := TDuelSession.Create(S, C);
  Decks := TDecks.Create;
  try
    DS.OnNeedDeck := @Decks.Next;
    DS.Activate;
    Check(not S.PayWinRewards, 'campaign mode turns off the flat win reward');
    Check(DS.Duel.State = dsIntro, 'starts at the intro');
    Check(Decks.Dealt = 0, 'no hand is dealt during the intro');
    Check(not DS.Remove(27, PosNone), 'the board is locked during a scene');
    Check(not DS.DrawStock, 'drawing is locked too');
    Check(DS.UseHint = hrNoMoves, 'hints do nothing during a scene');

    Check(DS.SceneDone, 'the intro scene ends');
    Check(DS.Duel.State = dsPlaying, 'now playing');
    Check(Decks.Dealt = 1, 'and the first hand was dealt');
    Check(S.Game.CardsLeft = 28, 'a full board');
    Coins0 := S.Inventory.Coins;
    Decks.Mode := dmWin;                       { the hand is already dealt: rig the next ones only }
    S.NewGameFrom(Decks.Next);                 { replace the current hand with a winnable one }
    WinHand(DS);
    Check(DS.Duel.State = dsHit, 'clearing the board is a hit, not the kill');
    Check(S.Inventory.Coins = Coins0 + VampireWinCoins[0], 'paid the win once, not the flat reward as well');
    Check(S.Inventory.UndoCards = 0, 'a hit gives no undo card');
    Check(S.Inventory.HintCards = HitHintCards, 'a hit gives its hint card');
    Check(DS.LastPaid.Coins = VampireWinCoins[0], 'LastPaid records it');
    Check(C.Wins = 1, 'and the win is counted');
    Check(not DS.Remove(0, PosNone), 'the board is locked after the win');
    Check(DS.SceneDone and (DS.Duel.State = dsPlaying), 'hit scene done: back to play');
    Check(Decks.Dealt = 3, 'and the next hand was dealt');
    Check(S.Game.CardsLeft = 28, 'a full board');
    { three more hits, then the kill }
    Coins0 := S.Inventory.Coins;
    WinHand(DS);                                 { win 2 }
    DS.SceneDone;
    WinHand(DS);                                 { win 3 }
    DS.SceneDone;
    WinHand(DS);                                 { win 4 }
    DS.SceneDone;
    Check(S.Inventory.Coins = Coins0 + 3 * VampireWinCoins[0], 'each hit paid at once');
    Check(C.Wins = WinsToKill - 1, 'four wins');
    Check(DS.Duel.State = dsPlaying, 'still playing');
    Coins0 := S.Inventory.Coins;
    WinHand(DS);                                 { win 5 }
    Check(DS.Duel.State = dsFatalBlow, 'the fifth win is the fatal blow');
    Check(S.Inventory.Coins = Coins0 + VampireWinCoins[0] + VampireKillBonus[0], 'the kill paid its per-win coins plus the bonus');
    Check(S.Inventory.UndoCards = WinUndoCards, 'paid the undo card');
    Check(S.Inventory.HintCards = (WinsToKill - 1) * HitHintCards + WinHintCards, 'and the hint cards');
    Check(DS.LastPaid.Coins = VampireWinCoins[0] + VampireKillBonus[0], 'LastPaid records the kill');
    Check(DS.SceneDone and (DS.Duel.State = dsDefeated), 'blow scene done');
    Check(DS.SceneDone and (DS.Duel.State = dsIntro) and (C.Current = 1) and (C.Wins = 0), 'defeat scene done: next vampire, no wins');
    Check(Decks.Dealt = 6, 'no new hand until the next intro is done');
    DS.Deactivate;
    Check(S.PayWinRewards, 'leaving campaign mode restores the flat win reward');
  finally
    Decks.Free;
    DS.Free;
    C.Free;
    S.Free;
  end;
end;

procedure TestSessionStuck;
var
  S: TGameSession;
  C: TCampaign;
  DS: TDuelSession;
  Decks: TDecks;
  I: Integer;
begin
  { stuck with no undo card: the hand is lost automatically }
  S := TGameSession.Create('');
  S.HazardsOn := False;                       { the tricks have their own tests }
  C := TCampaign.Create('');
  DS := TDuelSession.Create(S, C);
  Decks := TDecks.Create;
  try
    Decks.Mode := dmStuck;
    DS.OnNeedDeck := @Decks.Next;
    DS.Activate;
    DS.SceneDone;
    Check(DS.Duel.State = dsPlaying, 'playing a hand that cannot be won');
    for I := 1 to 20 do DS.DrawStock;
    Check(DS.Duel.State = dsPlaying, 'still playing with cards left in the stock');
    Check(not DS.StuckWaiting, 'not stuck yet');
    ExhaustStock(DS);                                      { the rest of the stock, and the turn-overs }
    Check(DS.Duel.State = dsFreeRound, 'stuck with no undo card: the free round');
    Check(DS.Duel.LastLoss = lrStuck, 'recorded as stuck');
    Check(C.LostHands = 1, 'one lost hand');
    Check(S.CanShop, 'a hand lost by being stuck is over: the shop is open');
    Check(not DS.DrawStock, 'the board is locked during the free round');
    DS.SceneDone;
    Check(DS.Duel.State = dsPlaying, 'back to play after the free round');
    Check(S.Game.StockCount = StockStart, 'with a fresh deal');
    Check(Decks.Dealt = 2, 'a new hand was dealt');
  finally
    Decks.Free; DS.Free; C.Free; S.Free;
  end;

  { stuck with an undo card: wait, and let the player undo }
  S := TGameSession.Create('');
  S.HazardsOn := False;                       { the tricks have their own tests }
  C := TCampaign.Create('');
  DS := TDuelSession.Create(S, C);
  Decks := TDecks.Create;
  try
    Decks.Mode := dmStuck;
    DS.OnNeedDeck := @Decks.Next;
    S.Inventory.AddUndoCards(1);
    DS.Activate;
    DS.SceneDone;
    ExhaustStock(DS);
    Check(DS.Duel.State = dsPlaying, 'stuck but holding an undo card: the hand is not lost yet');
    Check(DS.StuckWaiting, 'the window is told to wait for the player');
    Check(DS.UseUndo, 'the player undoes the last draw');
    Check(not DS.StuckWaiting, 'no longer stuck');
    Check(S.Inventory.UndoCards = 0, 'the undo card was spent');
    Check(DS.DrawStock, 'draw the last card again');
    Check(DS.Duel.State = dsFreeRound, 'stuck again with no undo card left: lost');
  finally
    Decks.Free; DS.Free; C.Free; S.Free;
  end;

  { stuck with an undo card, but the player gives up instead }
  S := TGameSession.Create('');
  S.HazardsOn := False;                       { the tricks have their own tests }
  C := TCampaign.Create('');
  DS := TDuelSession.Create(S, C);
  Decks := TDecks.Create;
  try
    Decks.Mode := dmStuck;
    DS.OnNeedDeck := @Decks.Next;
    S.Inventory.AddUndoCards(1);
    DS.Activate;
    DS.SceneDone;
    ExhaustStock(DS);
    Check(DS.Concede, 'the player concedes');
    Check((DS.Duel.State = dsFreeRound) and (DS.Duel.LastLoss = lrConceded), 'free round, recorded as conceded');
    Check(S.Inventory.UndoCards = 1, 'the unused undo card is kept');
  finally
    Decks.Free; DS.Free; C.Free; S.Free;
  end;
end;

procedure TestSessionConcedeAndSpoils;
var
  S: TGameSession;
  C: TCampaign;
  DS: TDuelSession;
  Decks: TDecks;
  Coins0: Integer;
begin
  S := TGameSession.Create('');
  S.HazardsOn := False;                       { the tricks have their own tests }
  C := TCampaign.Create('');
  DS := TDuelSession.Create(S, C);
  Decks := TDecks.Create;
  try
    DS.OnNeedDeck := @Decks.Next;
    DS.Activate;
    Check(not DS.Concede, 'cannot concede during the intro');
    Decks.Mode := dmStuck;
    DS.SceneDone;
    Check(S.CanShop, 'a freshly dealt duel hand: the shop is open');
    DS.DrawStock;
    Check(not S.CanShop, 'mid-hand in a duel: the shop is shut');
    Check(DS.Concede, 'New Game during a duel concedes the hand');
    Check(S.CanShop, 'a conceded hand is over: the shop is open');
    Check(not S.CanUseUndo, 'and the conceded hand cannot be undone');
    Check(not DS.Concede, 'cannot concede twice');
    Check(C.LostHands = 1, 'it counts as a lost hand');
    Decks.Mode := dmWin;
    DS.SceneDone;                                        { free round done: win hand dealt }
    Coins0 := S.Inventory.Coins;
    WinHand(DS);
    Check(S.Inventory.Coins = Coins0 + VampireWinCoins[0] - SpoilsStep,
      'the win pays a step less after one lost hand');
    Check(C.LostHands = 0, 'and the win forgets the lost hand');
  finally
    Decks.Free; DS.Free; C.Free; S.Free;
  end;
end;

procedure TestWholeCampaign;
var
  S: TGameSession;
  C: TCampaign;
  DS: TDuelSession;
  Decks: TDecks;
  V, Expect: Integer;
begin
  S := TGameSession.Create('');
  S.HazardsOn := False;                       { the tricks have their own tests }
  C := TCampaign.Create('');
  DS := TDuelSession.Create(S, C);
  Decks := TDecks.Create;
  try
    Decks.Mode := dmWin;
    DS.OnNeedDeck := @Decks.Next;
    DS.Activate;
    Expect := S.Inventory.Coins;
    for V := 0 to VampireCount - 1 do
    begin
      Check(DS.Duel.State = dsIntro, 'intro for vampire ' + IntToStr(V));
      Check(DS.Duel.Vampire = V, 'fighting vampire ' + IntToStr(V));
      DS.SceneDone;
      WinDuel(DS);
      Check(DS.Duel.State = dsFatalBlow, 'the fifth win kills vampire ' + IntToStr(V));
      Expect := Expect + WinsToKill * VampireWinCoins[V] + VampireKillBonus[V];
      DS.SceneDone;
      DS.SceneDone;
    end;
    Check(DS.Duel.State = dsComplete, 'campaign complete after fifteen wins');
    Check(S.Inventory.Coins = Expect, 'total coins paid across the campaign');
    Check(S.Inventory.UndoCards = VampireCount * WinUndoCards, 'undo cards across the campaign');
    Check(S.Inventory.HintCards = VampireCount * ((WinsToKill - 1) * HitHintCards + WinHintCards),
      'hint cards across the campaign');
    Check(not DS.Remove(0, PosNone), 'nothing to take away when complete');
    DS.Restart;
    Check((C.Current = 0) and (DS.Duel.State = dsIntro), 'restart begins a new campaign');
  finally
    Decks.Free; DS.Free; C.Free; S.Free;
  end;
end;

procedure TestSavedWithSession;
var
  F, G: string;
  S: TGameSession;
  C, C2: TCampaign;
  DS: TDuelSession;
  Decks: TDecks;
begin
  F := GetTempDir + 'tiepair_test_duelcampaign.ini';
  G := GetTempDir + 'tiepair_test_duelinv.ini';
  if FileExists(F) then DeleteFile(F);
  if FileExists(G) then DeleteFile(G);
  S := TGameSession.Create(G);
  S.HazardsOn := False;                       { the tricks have their own tests }
  C := TCampaign.Create(F);
  DS := TDuelSession.Create(S, C);
  Decks := TDecks.Create;
  try
    Decks.Mode := dmStuck;
    DS.OnNeedDeck := @Decks.Next;
    DS.Activate;
    DS.SceneDone;
    DS.Concede;                                  { one lost hand, saved at once }
    C2 := TCampaign.Create(F);
    try
      Check((C2.LostHands = 1) and (C2.Current = 0), 'the lost hand was written to disk straight away');
    finally
      C2.Free;
    end;
    DS.SceneDone;
    Decks.Mode := dmWin;
    S.NewGameFrom(Decks.Next);
    WinDuel(DS);                                 { the kill is paid and saved at once }
  finally
    Decks.Free;
    { deliberately NOT freeing the session first: simulate a crash after the kill,
      before the blow and defeat scenes have finished }
  end;
  C2 := TCampaign.Create(F);
  try
    Check(C2.Current = 1, 'the killed vampire stays dead after a crash: no second reward from him');
    Check(C2.LostHands = 0, 'and the next duel starts clean');
  finally
    C2.Free;
  end;
  DS.Free;                                       { in this order: the controller points at the session }
  C.Free;
  S.Free;
  S := TGameSession.Create(G);
  S.HazardsOn := False;                       { the tricks have their own tests }
  try
    Check(S.Inventory.UndoCards = WinUndoCards, 'the kill reward was written to disk straight away');
  finally
    S.Free;
  end;
  DeleteFile(F);
  DeleteFile(G);
end;

procedure TestWinsSavedAtOnce;
var
  F, G: string;
  S: TGameSession;
  C, C2: TCampaign;
  DS: TDuelSession;
  Decks: TDecks;
  Coins0: Integer;
begin
  F := GetTempDir + 'tiepair_test_winsc.ini';
  G := GetTempDir + 'tiepair_test_winsi.ini';
  if FileExists(F) then DeleteFile(F);
  if FileExists(G) then DeleteFile(G);
  S := TGameSession.Create(G);
  S.HazardsOn := False;                       { the tricks have their own tests }
  C := TCampaign.Create(F);
  DS := TDuelSession.Create(S, C);
  Decks := TDecks.Create;
  try
    Decks.Mode := dmWin;
    DS.OnNeedDeck := @Decks.Next;
    DS.Activate;
    DS.SceneDone;
    Coins0 := S.Inventory.Coins;
    WinHand(DS);                                 { win 1; no scene has finished yet }
    C2 := TCampaign.Create(F);                   { "crash" here: read what is on disk }
    try
      Check((C2.Current = 0) and (C2.Wins = 1), 'the win is on disk before its scene ends');
    finally
      C2.Free;
    end;
    DS.SceneDone;
    S.SaveNow;
  finally
    Decks.Free; DS.Free; C.Free; S.Free;
  end;
  S := TGameSession.Create(G);
  S.HazardsOn := False;                       { the tricks have their own tests }
  try
    Check(S.Inventory.Coins = Coins0 + VampireWinCoins[0], 'and so are the coins it paid');
    Check(S.Inventory.HintCards = HitHintCards, 'and the hint card');
  finally
    S.Free;
  end;
  C := TCampaign.Create(F);
  try
    Check(C.Wins = 1, 'the next run starts with the win counted');
    Check(TDuel.Create(C).InProgress, 'and treats him as already met');
  finally
    C.Free;
  end;
  DeleteFile(F);
  DeleteFile(G);
end;

{ The vampires' tricks in the duel: each vampire deals his own, bites cost coins at
  the win, and the panel's numbers add up. }
procedure TestTricksInDuel;
var
  S: TGameSession;
  C: TCampaign;
  DS: TDuelSession;
  D: TDuel;
  Inf: TDuelInfo;
  H: TSavedHand;
  V, I, Bitten, Chained: Integer;
  Decks: TDecks;
  St: TStory;
begin
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  { what each vampire deals }
  Decks := TDecks.Create;
  for V := 0 to VampireCount - 1 do
  begin
    S := TGameSession.Create('');
    C := TCampaign.Create('');
    DS := TDuelSession.Create(S, C);
    try
      DS.OnNeedDeck := @Decks.Next;
      Decks.Mode := dmWinSevens;
      while C.Current < V do C.Advance;
      DS.Activate;
      DS.SceneDone;
      Check(S.Game.Hazard = VampireHazard[V], 'vampire ' + IntToStr(V) + ' deals his own trick');
      Bitten := 0;
      Chained := 0;
      for I := 0 to PyramidSize - 1 do
      begin
        if S.Game.Mark(I) = MarkBitten then Inc(Bitten);
        if S.Game.Mark(I) = MarkChained then Inc(Chained);
      end;
      case VampireHazard[V] of
        hzBitten: Check((Bitten = BittenCount) and (Chained = 0), 'with his bitten cards');
        hzChained: Check((Chained = ChainedCount) and (Bitten = 0), 'with his chained cards');
        hzHunger: Check((Bitten = 0) and (Chained = 0), 'with no marks (he eats instead)');
      end;
    finally
      DS.Free; S.Free; C.Free;
    end;
  end;
  Decks.Free;
  { Free Play has none, even after a duel }
  S := TGameSession.Create('');
  C := TCampaign.Create('');
  DS := TDuelSession.Create(S, C);
  try
    DS.Activate;
    DS.Deactivate;
    S.NewGame;
    Check(S.Game.Hazard = hzNone, 'leaving the campaign leaves the tricks behind');
  finally
    DS.Free; S.Free; C.Free;
  end;
  { what a bite costs at the win }
  C := TCampaign.Create('');
  D := TDuel.Create(C);
  try
    D.Start;
    D.SceneDone;
    D.HandWon(0, 2);
    Check(D.LastReward.Coins = VampireWinCoins[0] - 2 * BitePenaltyCoins, 'two bites cost two bites'' coins');
  finally
    D.Free; C.Free;
  end;
  C := TCampaign.Create('');
  D := TDuel.Create(C);
  try
    D.Start;
    D.SceneDone;
    D.HandWon(1, 100);
    Check(D.LastReward.Coins = SpoilsFloor, 'however many, the floor holds');
  finally
    D.Free; C.Free;
  end;
  { the panel adds up }
  S := TGameSession.Create('');
  S.HazardsOn := False;
  C := TCampaign.Create('');
  DS := TDuelSession.Create(S, C);
  try
    DS.Activate;
    DS.SceneDone;
    S.NewGame;
    S.ExportHand(H);
    H.Bites := 2;
    H.Misses := 1;
    Check(S.ImportHand(H), 'a hand with bites and a miss');
    Inf := GetDuelInfo(DS, St);
    Check((Inf.Bites = 2) and (Inf.BiteCut = 2 * BitePenaltyCoins) and (Inf.MissCut = MissPenaltyCoins), 'the panel counts both');
    Check(Inf.PayNow = Inf.PerWin - Inf.MissCut - Inf.BiteCut, 'the lines add up to the pay');
    Check(Inf.PayNow = DS.PayoutNow, 'and match what is paid');
    Check(Inf.HazardText <> '', 'and says what his trick is: ' + Inf.HazardText);
  finally
    DS.Free; S.Free; C.Free; St.Free;
  end;
end;

{ ---- the silver cross (Easy-Vampire card) ---- }

function CrossIndex(S: TGameSession): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to PyramidSize - 1 do
    if (S.Game.Mark(I) = MarkCross) and not S.Game.Removed(I) then Exit(I);
end;

{ The cross lies wherever the deal put it; these tests want it in a known place. }
procedure MoveCross(S: TGameSession; NewIndex: Integer);
var
  X: Integer;
begin
  X := CrossIndex(S);
  if X >= 0 then S.Game.SetMark(X, MarkNone);
  S.Game.SetMark(NewIndex, MarkCross);
end;

{ Takes away some Kings from the bottom row (the cross sits on one that is left). }
procedure FreePeaks(DS: TDuelSession);
begin
  DS.Remove(21, PosNone);
  DS.Remove(22, PosNone);
end;

procedure TestSilverCross;
var
  S: TGameSession;
  C, C2: TCampaign;
  DS: TDuelSession;
  Decks: TDecks;
  St: TStory;
  Inf: TDuelInfo;
  X, I, Seen: Integer;
  F: string;
begin
  CrossCardsOn := True;
  Decks := TDecks.Create;
  St := TStory.Create;
  St.LoadFromFile(StoryPath);
  try
    Decks.Mode := dmWin;

    { which game carries it: chosen at random, once, for the Queen and the King only }
    Seen := 0;
    for I := 1 to 200 do
    begin
      C := TCampaign.Create('');
      Check(C.CrossGame < 1, 'the first vampire never carries one');
      C.Advance;
      Check((C.CrossGame >= 1) and (C.CrossGame <= 3), 'the Queen carries it in game 1, 2 or 3');
      if (C.CrossGame >= 1) and (C.CrossGame <= 3) then Seen := Seen or (1 shl C.CrossGame);
      C.Advance;
      Check((C.CrossGame >= 1) and (C.CrossGame <= 3), 'and so does the King');
      C.Advance;
      Check(C.CrossGame < 1, 'a finished campaign has none');
      C.Free;
    end;
    Check(Seen = (2 or 4 or 8), 'all of games 1, 2 and 3 come up');

    { Jack's hands never have one, even when told to }
    S := TGameSession.Create('');
    S.HazardsOn := False;
    C := TCampaign.Create('');
    DS := TDuelSession.Create(S, C);
    try
      DS.OnNeedDeck := @Decks.Next;
      C.SetCrossGame(1);
      DS.Activate;
      DS.SceneDone;
      Check(CrossIndex(S) = -1, 'no cross in the first vampire''s hand');
    finally
      DS.Free; S.Free; C.Free;
    end;

    { the Queen: game 2 carries it; a lost game 2 is dealt again with a cross }
    S := TGameSession.Create('');
    S.HazardsOn := False;
    C := TCampaign.Create('');
    DS := TDuelSession.Create(S, C);
    try
      DS.OnNeedDeck := @Decks.Next;
      C.Advance;
      C.SetCrossGame(2);
      DS.Activate;
      DS.SceneDone;
      Check(CrossIndex(S) = -1, 'game 1 has no cross when game 2 carries it');
      WinHand(DS);
      DS.SceneDone;
      X := CrossIndex(S);
      Check(X >= 0, 'game 2 has it');
      Check(S.Game.HasMark(MarkCross), 'HasMark sees it');
      Inf := GetDuelInfo(DS, St);
      Check(Pos('silver cross', Inf.CrossText) > 0, 'the panel mentions it: ' + Inf.CrossText);
      DS.Concede;
      DS.SceneDone;
      Check(CrossIndex(S) >= 0, 'a lost game is dealt again with the cross');
      WinHand(DS);
      DS.SceneDone;
      Check(CrossIndex(S) = -1, 'game 3 has none');
      Check(C.Ease = 0, 'nothing was claimed by playing through');
    finally
      DS.Free; S.Free; C.Free;
    end;

    { claiming it with a Wild card: the Queen, until she falls }
    S := TGameSession.Create('');
    S.HazardsOn := False;
    C := TCampaign.Create('');
    DS := TDuelSession.Create(S, C);
    try
      DS.OnNeedDeck := @Decks.Next;
      C.Advance;
      C.SetCrossGame(1);
      DS.Activate;
      DS.SceneDone;
      Check(CrossIndex(S) >= 0, 'the cross is down');
      MoveCross(S, 27);                                 { on a free card of the bottom row, for this test }
      X := 27;
      S.Inventory.AddSpecial(skWild, 1);
      FreePeaks(DS);
      Check(DS.UseSpecialOn(skWild, X, 26), 'a Wild card on the cross (and its partner)');
      Check(C.Ease = -1, 'the Queen is weakened until she falls');
      Check(not C.EaseLive, 'but this hand was dealt before: it is unchanged');
      Check(C.CrossGame = -1, 'and the cross is spent');
      Check(CrossIndex(S) = -1, 'gone from the table');
      Check(Pos('silver cross is yours', S.Note) > 0, 'the note says so: ' + S.Note);
      Check(S.Game.MaxRecycles = VampireRecycles[1], 'her turn-overs stay hers for this hand');
      Inf := GetDuelInfo(DS, St);
      Check(not Inf.Eased and (Pos('claimed', Inf.CrossText) > 0), 'the panel: claimed, from the next hand: ' + Inf.CrossText);
      DS.Concede;
      DS.SceneDone;
      Check(C.EaseLive, 'the next hand is dealt weakened');
      Check((S.Game.MaxRecycles = VampireRecycles[0]) and S.Game.UnderPairs and (S.Hazard = hzNone),
        'at Lucien''s level: the Easy rule, his turn-overs, no trick');
      Inf := GetDuelInfo(DS, St);
      Check(Inf.Eased and (Inf.Recycles = VampireRecycles[0]) and Inf.Easy and (Inf.HazardText = ''),
        'and the panel says so');
      Check(Pos('until the duel ends', Inf.CrossText) > 0, 'until the duel ends: ' + Inf.CrossText);
      Check(Inf.PerWin = VampireWinCoins[1], 'the pay stays hers');
      WinHand(DS);
      DS.SceneDone;
      Check((C.Ease = -1) and C.EaseLive and (S.Game.MaxRecycles = VampireRecycles[0]),
        'a win does not end it: the next hand is weakened too');
      { she falls: it ends }
      for I := 1 to WinsToKill do C.RecordWin;
      C.Advance;
      Check((C.Ease = 0) and not C.EaseLive and (C.Current = 2), 'when she falls, the cross is gone');
    finally
      DS.Free; S.Free; C.Free;
    end;

    { a cross in the open bottom row is claimed the same way, at once }
    S := TGameSession.Create('');
    S.HazardsOn := False;
    C := TCampaign.Create('');
    DS := TDuelSession.Create(S, C);
    try
      DS.OnNeedDeck := @Decks.Next;
      C.Advance;
      C.SetCrossGame(1);
      DS.Activate;
      DS.SceneDone;
      MoveCross(S, 27);
      S.Inventory.AddSpecial(skWild, 1);
      Check(DS.UseSpecialOn(skWild, 27, 26), 'a Wild card on a bottom-row cross, on the first move');
      Check(C.Ease = -1, 'claims it');
    finally
      DS.Free; S.Free; C.Free;
    end;

    { the King: two hands, won or lost; lost one counts too }
    S := TGameSession.Create('');
    S.HazardsOn := False;
    C := TCampaign.Create('');
    DS := TDuelSession.Create(S, C);
    try
      DS.OnNeedDeck := @Decks.Next;
      C.Advance;
      C.Advance;
      C.SetCrossGame(1);
      DS.Activate;
      DS.SceneDone;
      Check(CrossIndex(S) >= 0, 'the cross is down for the King too');
      MoveCross(S, 27);
      X := 27;
      Check(not S.Game.UnderPairs, 'his own hand is plain Pyramid');
      S.Inventory.AddSpecial(skWild, 1);
      FreePeaks(DS);
      Check(DS.UseSpecialOn(skWild, X, 26), 'claimed');
      Check(C.Ease = 2, 'two hands');
      DS.Concede;                                       { the claiming hand does not count }
      DS.SceneDone;
      Check(C.Ease = 2, 'the hand it was claimed in is not one of the two');
      Check(C.EaseLive and S.Game.UnderPairs and (S.Game.MaxRecycles = VampireRecycles[0]), 'first weakened hand');
      DS.Concede;                                       { a lost hand uses one up }
      DS.SceneDone;
      Check(C.Ease = 1, 'a lost hand counts');
      Check(C.EaseLive and S.Game.UnderPairs, 'second weakened hand');
      Inf := GetDuelInfo(DS, St);
      Check(Pos('last hand', Inf.CrossText) > 0, 'the panel: the last hand: ' + Inf.CrossText);
      WinHand(DS);
      DS.SceneDone;
      Check((C.Ease = 0) and not C.EaseLive, 'a win counts too: it is over');
      Check(not S.Game.UnderPairs, 'the King''s own rules are back');
      Check(S.Game.MaxRecycles = VampireRecycles[2], 'his turn-overs');
    finally
      DS.Free; S.Free; C.Free;
    end;

    { a Wood Stake or an ordinary play destroys it without claiming }
    S := TGameSession.Create('');
    S.HazardsOn := False;
    C := TCampaign.Create('');
    DS := TDuelSession.Create(S, C);
    try
      DS.OnNeedDeck := @Decks.Next;
      C.Advance;
      C.SetCrossGame(1);
      DS.Activate;
      DS.SceneDone;
      MoveCross(S, 27);
      X := 27;
      S.Inventory.AddSpecial(skStake, 1);
      FreePeaks(DS);
      Check(DS.UseSpecialOn(skStake, X, PosNone), 'a Wood Stake on the cross');
      Check((C.Ease = 0) and (CrossIndex(S) = -1), 'destroys it, claims nothing');
      Check(Pos('splinters', S.Note) > 0, 'the note: ' + S.Note);
      DS.Concede;
      DS.SceneDone;
      Check(CrossIndex(S) >= 0, 'but a lost game still carries it again');
      MoveCross(S, 27);
      Check(DS.Remove(27, PosNone), 'the cross card taken away as an ordinary move');
      WinHand(DS);
      DS.SceneDone;
      Check(C.Ease = 0, 'an ordinary play claims nothing');
    finally
      DS.Free; S.Free; C.Free;
    end;

    { everything survives a save and a load }
    F := GetTempDir + 'tiepair_test_cross.ini';
    if FileExists(F) then DeleteFile(F);
    C := TCampaign.Create(F);
    C.Advance;
    C.SetCrossGame(2);
    C.ClaimCross;
    C.BeginHand;
    C2 := TCampaign.Create(F);
    Check((C2.Ease = -1) and C2.EaseLive and (C2.CrossGame = -1), 'the file keeps the claim');
    C2.Free;
    C2 := TCampaign.Create('');
    C2.ImportText(C.ExportText);
    Check((C2.Ease = -1) and C2.EaseLive and (C2.Current = 1), 'a save slot keeps the claim');
    C2.Free;
    C.Free;
    DeleteFile(F);
    C := TCampaign.Create(F);
    C.Advance;
    C.SetCrossGame(3);
    C.Save;
    C2 := TCampaign.Create(F);
    Check(C2.CrossGame = 3, 'and which game carries it (no re-roll on load)');
    C2.Free;
    C.Free;
    DeleteFile(F);
  finally
    St.Free;
    Decks.Free;
    CrossCardsOn := False;
  end;
end;

{ Design checks on the numbers, so a later tweak cannot quietly break them. }
procedure TestBalanceShape;
var
  V, N: Integer;
  Both: Boolean;
begin
  Both := False;
  for V := 0 to VampireCount - 1 do
    if not VampireEasy[V] and ((VampireRecycles[V] < VampireRecycles[0]) or (VampireHazard[V] = hzHunger)) then Both := True;
  Check(Both, 'some vampire has plain rules and fewer turn-overs (or hunger), or the Dawn card would never be worth its price');
  Check(FirstNormalVampire < VampireCount, 'a vampire plays plain Pyramid (the Easy rule card has a use)');
  for V := 0 to VampireCount - 1 do
    for N := V + 1 to VampireCount - 1 do
      Check(VampireHazard[V] <> VampireHazard[N], 'no two vampires share a trick');
  for V := 0 to VampireCount - 1 do
    Check(VampireHazard[V] <> hzNone, 'every vampire has a trick');
  Check(FirstFewerTurnsVampire < VampireCount, 'a vampire allows fewer turn-overs (the Extra turn has a use)');
  for V := 1 to VampireCount - 1 do
  begin
    Check(VampireWinCoins[V] > VampireWinCoins[V - 1], 'each vampire pays more per win than the last');
    Check(VampireKillBonus[V] > VampireKillBonus[V - 1], 'and a bigger kill bonus');
  end;
  Check(VampireWinCoins[0] - SpoilsStep >= SpoilsFloor + SpoilsStep,
    'the first vampire''s pay survives a lost hand without hitting the floor');
  Check(VampireWinCoins[0] <= WinCoins, 'the campaign does not pay an ordinary hand more than Free Play does at the first level');
  Check(SpecialPrice[skDawn] < SpecialPrice[skExtraTurn] + SpecialPrice[skEasyRule],
    'Dawn costs less than the two cards it combines');
  Check(SpecialPrice[skDawn] > SpecialPrice[skExtraTurn], 'but more than either');
end;

begin
  CrossCardsOn := False;                  { where the silver cross lies is random: it has its own tests }
  TestStory;
  TestCampaign;
  TestDuelMachine;
  TestTricksInDuel;
  TestSilverCross;
  TestBalanceShape;
  TestDuelMisses;
  TestDuelInfo;
  TestLevels;
  TestSettings;
  TestPremiseSeen;
  TestResume;
  TestSessionWin;
  TestSessionStuck;
  TestSessionConcedeAndSpoils;
  TestWholeCampaign;
  TestSavedWithSession;
  TestWinsSavedAtOnce;
  if Failures = 0 then WriteLn('ALL DUEL TESTS PASSED') else
  begin
    WriteLn(Failures, ' FAILURES');
    Halt(1);
  end;
end.
