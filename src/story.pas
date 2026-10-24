unit Story;

{ Reads the campaign's words from assets/story/story.ini (a plain text file the
  author edits). No window code. Nothing here affects how the game plays. }

{$mode objfpc}{$H+}

interface

uses
{$IFNDEF PAS2JS}
  Classes,
{$ENDIF}
  SysUtils, TextIni, Storage, Vampires, Specials, Trophies, Cosmetics, Relics;

type
  TStringArray = array of string;

  TStory = class
  private
    FIni: TTextIni;
    procedure Release;
  public
    destructor Destroy; override;
    { The story as text (what the web version, which has no files, uses). }
    procedure LoadFromText(const Text: string);
    procedure LoadFromFile(const FileName: string);
{$IFNDEF PAS2JS}
    procedure LoadFromStream(AStream: TStream);
{$ENDIF}
    function Value(const Section, Key: string): string;
    { Prefix.1, Prefix.2, ... in order, stopping at the first one that is missing. }
    function Lines(const Section, Prefix: string): TStringArray;

    function Name(V: Integer): string;
    function Title(V: Integer): string;
    function Intro(V: Integer): TStringArray;
    { Tier 1..3: what the vampire says after your 1st, 2nd, 3rd-or-later lost hand. }
    function Taunt(V, Tier: Integer): TStringArray;
    { What the vampire says after your Nth win against him (N = 1..WinsToKill-1;
      the fifth win is the fatal blow, see Strike). }
    function Hit(V, N: Integer): TStringArray;
    function Strike(V: Integer): TStringArray;
    { What the vampire says about his trick in the middle of a hand (optional). }
    function Trick(V: Integer): TStringArray;
    function Defeat(V: Integer): TStringArray;
    function CampaignTitle: string;
    function Premise: TStringArray;
    function Finale: TStringArray;
    function FinaleCaption: string;
    { Narrator lines. The two with numbers are format strings (see story.ini). }
    function LostStuck: string;
    function LostConceded: string;
    function SpoilsNowFormat: string;
    function HitPaidFormat: string;
    function SpoilsPaidFormat: string;

    { Fenwick Grimm, the Store's keeper. Greet / Bought / Broke take any number
      and pick that one in turn (counting from 0). Pitch keys are Specials'
      SpecialKey ('extraturn', ...) plus 'undo' and 'hint'. }
    function FenwickName: string;
    function FenwickTitle: string;
    function FenwickIntro: TStringArray;
    function FenwickGreet(N: Integer): string;
    function FenwickBought(N: Integer): string;
    function FenwickBroke(N: Integer): string;
    function FenwickClosed: string;
    function FenwickLocked(const Key: string): string;   { a good he does not stock yet }
    function FenwickLeave: string;
    function FenwickPitch(const Key: string): string;

    { Lists every required entry that is missing or empty (empty = all good). }
    { A trophy's name, how it is earned, and what it says once you have it. Key is
      one of TrophyKeys. }
    function TrophyName(const Key: string): string;
    function TrophyHow(const Key: string): string;
    function TrophyLine(const Key: string): string;
    { A Style item's name and a line about it. Key is Cosmetics.CosmeticStoryKey ('back.blood'). }
    function StyleName(const Key: string): string;
    function StyleLine(const Key: string): string;
    { A relic's name and what it does. Key is Relics.RelicKey. }
    function RelicName(const Key: string): string;
    function RelicLine(const Key: string): string;
    function Validate: TStringArray;
  end;

implementation

destructor TStory.Destroy;
begin
  Release;
  inherited Destroy;
end;

procedure TStory.Release;
begin
  FreeAndNil(FIni);
end;

procedure TStory.LoadFromText(const Text: string);
begin
  Release;
  FIni := TTextIni.Create;
  FIni.LoadFromText(Text);
end;

procedure TStory.LoadFromFile(const FileName: string);
var
  Text: string;
begin
  if not StoreRead(FileName, Text) then Text := '';
  LoadFromText(Text);
end;

{$IFNDEF PAS2JS}
procedure TStory.LoadFromStream(AStream: TStream);
var
  Text: string;
begin
  SetLength(Text, AStream.Size - AStream.Position);
  if Length(Text) > 0 then AStream.ReadBuffer(Text[1], Length(Text));
  LoadFromText(Text);
end;
{$ENDIF}

function TStory.Value(const Section, Key: string): string;
begin
  if FIni = nil then Result := ''
  else Result := Trim(FIni.ReadString(Section, Key, ''));
end;

function TStory.Lines(const Section, Prefix: string): TStringArray;
var
  N: Integer;
  S: string;
begin
  Result := nil;
  N := 1;
  repeat
    S := Value(Section, Prefix + '.' + IntToStr(N));
    if S = '' then Break;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := S;
    Inc(N);
  until False;
end;

function TStory.Name(V: Integer): string;
begin
  Result := Value(VampireKey[V], 'name');
end;

function TStory.Title(V: Integer): string;
begin
  Result := Value(VampireKey[V], 'title');
end;

function TStory.Intro(V: Integer): TStringArray;
begin
  Result := Lines(VampireKey[V], 'intro');
end;

function TStory.Taunt(V, Tier: Integer): TStringArray;
begin
  if Tier < 1 then Tier := 1;
  if Tier > 3 then Tier := 3;
  Result := Lines(VampireKey[V], 'taunt' + IntToStr(Tier));
end;

function TStory.Hit(V, N: Integer): TStringArray;
begin
  if N < 1 then N := 1;
  if N > WinsToKill - 1 then N := WinsToKill - 1;
  Result := Lines(VampireKey[V], 'hit' + IntToStr(N));
end;

function TStory.Trick(V: Integer): TStringArray;
begin
  Result := Lines(VampireKey[V], 'trick');
end;

function TStory.Strike(V: Integer): TStringArray;
begin
  Result := Lines(VampireKey[V], 'strike');
end;

function TStory.Defeat(V: Integer): TStringArray;
begin
  Result := Lines(VampireKey[V], 'defeat');
end;

function TStory.CampaignTitle: string;
begin
  Result := Value('campaign', 'title');
end;

function TStory.Premise: TStringArray;
begin
  Result := Lines('campaign', 'premise');
end;

function TStory.Finale: TStringArray;
begin
  Result := Lines('finale', 'finale');
end;

function TStory.FinaleCaption: string;
begin
  Result := Value('finale', 'caption');
end;

function TStory.LostStuck: string;
begin
  Result := Value('campaign', 'lost.stuck');
end;

function TStory.LostConceded: string;
begin
  Result := Value('campaign', 'lost.conceded');
end;

function TStory.SpoilsNowFormat: string;
begin
  Result := Value('campaign', 'spoils.now');
end;

function TStory.HitPaidFormat: string;
begin
  Result := Value('campaign', 'hit.paid');
end;

function TStory.SpoilsPaidFormat: string;
begin
  Result := Value('campaign', 'spoils.paid');
end;

function TStory.FenwickName: string;
begin
  Result := Value('fenwick', 'name');
end;

function TStory.FenwickTitle: string;
begin
  Result := Value('fenwick', 'title');
end;

function TStory.FenwickIntro: TStringArray;
begin
  Result := Lines('fenwick', 'intro');
end;

{ The Nth of Prefix.1, Prefix.2, ... (wrapping round); '' if there are none. }
function Rotate(AStory: TStory; const Prefix: string; N: Integer): string;
var
  L: TStringArray;
begin
  L := AStory.Lines('fenwick', Prefix);
  if Length(L) = 0 then
    Result := ''
  else
    Result := L[((N mod Length(L)) + Length(L)) mod Length(L)];
end;

function TStory.FenwickGreet(N: Integer): string;
begin
  Result := Rotate(Self, 'greet', N);
end;

function TStory.FenwickBought(N: Integer): string;
begin
  Result := Rotate(Self, 'bought', N);
end;

function TStory.FenwickBroke(N: Integer): string;
begin
  Result := Rotate(Self, 'broke', N);
end;

function TStory.FenwickClosed: string;
begin
  Result := Value('fenwick', 'closed.1');
end;

function TStory.FenwickLocked(const Key: string): string;
begin
  Result := Value('fenwick', 'locked.' + Key);
end;

function TStory.FenwickLeave: string;
begin
  Result := Value('fenwick', 'leave.1');
end;

function TStory.FenwickPitch(const Key: string): string;
begin
  Result := Value('fenwick', 'pitch.' + Key);
end;

function TStory.TrophyName(const Key: string): string;
begin
  Result := Value('trophies', Key + '.name');
end;

function TStory.TrophyHow(const Key: string): string;
begin
  Result := Value('trophies', Key + '.how');
end;

function TStory.TrophyLine(const Key: string): string;
begin
  Result := Value('trophies', Key + '.line');
end;

function TStory.StyleName(const Key: string): string;
begin
  Result := Value('style', Key + '.name');
end;

function TStory.StyleLine(const Key: string): string;
begin
  Result := Value('style', Key + '.line');
end;

function TStory.RelicName(const Key: string): string;
begin
  Result := Value('relics', Key + '.name');
end;

function TStory.RelicLine(const Key: string): string;
begin
  Result := Value('relics', Key + '.line');
end;

function TStory.Validate: TStringArray;
var
  V, T: Integer;
  RR: TRelic;
  CK: TCosmeticKind;
  CI: Integer;
  K: TSpecialKind;
  TR: TTrophy;

  procedure Need(const Section, Key: string);
  begin
    if Value(Section, Key) = '' then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := '[' + Section + '] ' + Key;
    end;
  end;

begin
  Result := nil;
  Need('campaign', 'title');
  Need('campaign', 'premise.1');
  Need('campaign', 'lost.stuck');
  Need('campaign', 'lost.conceded');
  Need('campaign', 'spoils.now');
  Need('campaign', 'spoils.paid');
  Need('campaign', 'hit.paid');
  for V := 0 to VampireCount - 1 do
  begin
    Need(VampireKey[V], 'name');
    Need(VampireKey[V], 'title');
    Need(VampireKey[V], 'intro.1');
    for T := 1 to 3 do Need(VampireKey[V], 'taunt' + IntToStr(T) + '.1');
    for T := 1 to WinsToKill - 1 do Need(VampireKey[V], 'hit' + IntToStr(T) + '.1');
    Need(VampireKey[V], 'strike.1');
    Need(VampireKey[V], 'defeat.1');
  end;
  Need('fenwick', 'name');
  Need('fenwick', 'title');
  Need('fenwick', 'intro.1');
  Need('fenwick', 'greet.1');
  Need('fenwick', 'bought.1');
  Need('fenwick', 'broke.1');
  Need('fenwick', 'closed.1');
  Need('fenwick', 'locked.easyrule');
  Need('fenwick', 'locked.extraturn');
  Need('fenwick', 'leave.1');
  for K := Low(TSpecialKind) to High(TSpecialKind) do Need('fenwick', 'pitch.' + SpecialKey[K]);
  Need('fenwick', 'pitch.undo');
  Need('fenwick', 'pitch.hint');
  Need('finale', 'finale.1');
  Need('finale', 'caption');
  for RR := Low(TRelic) to High(TRelic) do
  begin
    Need('relics', RelicKey(RR) + '.name');
    Need('relics', RelicKey(RR) + '.line');
  end;
  for CK := Low(TCosmeticKind) to High(TCosmeticKind) do
    for CI := 0 to CosmeticsPerKind - 1 do
    begin
      Need('style', CosmeticStoryKey(CK, CI) + '.name');
      Need('style', CosmeticStoryKey(CK, CI) + '.line');
    end;
  for TR := Low(TTrophy) to High(TTrophy) do
  begin
    Need('trophies', TrophyKeys[TR] + '.name');
    Need('trophies', TrophyKeys[TR] + '.how');
    Need('trophies', TrophyKeys[TR] + '.line');
  end;
end;

end.
