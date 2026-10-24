unit Trophies;

{ The trophies a player collects and the shelf that shows them in the side
  panel. No window code.

  Six trophies, all earned deterministically:
    first win      the first hand you ever win (either mode)
    perfect hand   a hand won with no missed moves (either mode)
    one per vampire   for killing him (the fifth win against him)
    flawless       finishing the whole Campaign without losing a single hand
  They are keepsakes: Restart campaign keeps them, only Erase everything clears
  them (like the personal records). Their names and words are in story.ini.

  The shelf geometry lives here too, so the controller (which hit-tests a tap)
  and both front ends (which draw) always agree. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Types, Math, TextIni, Storage, Records, Vampires;

type
  TTrophy = (trFirstWin, trPerfect, trVampire0, trVampire1, trVampire2, trFlawless);

const
  TrophyCount = 6;
  { Names in the story file ([trophies] section: <key>.name, <key>.how, <key>.line). }
  TrophyKeys: array[TTrophy] of string =
    ('firstwin', 'perfect', 'jack', 'queen', 'king', 'flawless');

type
  TTrophies = class
  private
    FFile: string;
    FHas: array[TTrophy] of Boolean;
    FIsNew: Boolean;                  { there was no file: this is the first run with trophies }
  public
    { AFileName = '' means never load or save (used by tests). }
    constructor Create(const AFileName: string);
    procedure Save;
    procedure Reset;                  { Erase everything: all gone, saved }
    function Has(T: TTrophy): Boolean;
    function Count: Integer;
    { Earn one. True only the first time (saved at once). }
    function Award(T: TTrophy): Boolean;
    { A player who already won hands before trophies existed gets what the
      records prove: wins, perfect hands and each vampire killed (Killed =
      the campaign's count of vampires already beaten). Flawless is never
      granted this way, because history cannot prove it. Only the first time
      (when there was no trophies file), and it is saved either way. Returns
      how many trophies were granted. }
    function SeedFrom(ARecords: TRecords; Killed: Integer): Integer;
    property IsNew: Boolean read FIsNew;
  end;

function TrophyForVampire(V: Integer): TTrophy;
function DefaultTrophiesFile: string;

type
  { Where the shelf goes in the side panel. In a narrow strip (a phone held
    upright) six icons would be too small to read, so there it is a single
    chip that opens the trophy page. }
  TTrophyLayout = record
    Shelf: TRect;                     { the whole shelf: tap anywhere on it }
    Chip: Boolean;                    { a strip too narrow for icons: the portrait is drawn Reserved shorter }
    Slots: array[0..TrophyCount - 1] of TRect;   { not used when Chip }
    Reserved: Integer;                { how far above the panel's bottom padding the rest of the panel must stop }
  end;

{ Panel = the panel's rectangle; Strip = the wide panel under the table. The
  layout depends on nothing but these two. }
function TrophyLayoutFor(const Panel: TRect; Strip: Boolean): TTrophyLayout;

implementation

function TrophyForVampire(V: Integer): TTrophy;
begin
  Result := TTrophy(Ord(trVampire0) + V);
end;

function DefaultTrophiesFile: string;
begin
  Result := StoreName('trophies.ini');
end;

constructor TTrophies.Create(const AFileName: string);
var
  Ini: TTextIni;
  Text: string;
  T: TTrophy;
begin
  inherited Create;
  FFile := AFileName;
  for T := Low(TTrophy) to High(TTrophy) do FHas[T] := False;
  FIsNew := True;
  if (FFile <> '') and StoreRead(FFile, Text) then
  begin
    FIsNew := False;
    Ini := TTextIni.Create;
    try
      Ini.LoadFromText(Text);
      for T := Low(TTrophy) to High(TTrophy) do
        FHas[T] := Ini.ReadBool('Trophies', TrophyKeys[T], False);
    finally
      Ini.Free;
    end;
  end;
end;

procedure TTrophies.Save;
var
  Ini: TTextIni;
  T: TTrophy;
begin
  if FFile = '' then Exit;
  Ini := TTextIni.Create;
  try
    for T := Low(TTrophy) to High(TTrophy) do
      Ini.WriteBool('Trophies', TrophyKeys[T], FHas[T]);
    StoreWrite(FFile, Ini.ToText);
  finally
    Ini.Free;
  end;
  FIsNew := False;
end;

procedure TTrophies.Reset;
var
  T: TTrophy;
begin
  for T := Low(TTrophy) to High(TTrophy) do FHas[T] := False;
  Save;
end;

function TTrophies.Has(T: TTrophy): Boolean;
begin
  Result := FHas[T];
end;

function TTrophies.Count: Integer;
var
  T: TTrophy;
begin
  Result := 0;
  for T := Low(TTrophy) to High(TTrophy) do
    if FHas[T] then Inc(Result);
end;

function TTrophies.Award(T: TTrophy): Boolean;
begin
  Result := not FHas[T];
  if not Result then Exit;
  FHas[T] := True;
  Save;
end;

function TTrophies.SeedFrom(ARecords: TRecords; Killed: Integer): Integer;
var
  V: Integer;
begin
  Result := 0;
  if not FIsNew then Exit;
  if (ARecords.FreeWins > 0) or (ARecords.CampaignWins > 0) then
    if Award(trFirstWin) then Inc(Result);
  if ARecords.FreePerfect > 0 then
    if Award(trPerfect) then Inc(Result);
  for V := 0 to VampireCount - 1 do
    if ARecords.IsSet(FewestLostId(V)) or (Killed > V) then
      if Award(TrophyForVampire(V)) then Inc(Result);
  Save;                                  { so it never seeds again, even with nothing to grant }
end;

{ ---- the shelf ---- }

function TrophyLayoutFor(const Panel: TRect; Strip: Boolean): TTrophyLayout;
var
  W, H, I, Pad, Gap, Slot, TotalW, X, Y0, Y1, PW, MidL, MidR, RightL: Integer;
  K: Double;
begin
  Result.Shelf := Rect(0, 0, 0, 0);
  Result.Chip := False;
  Result.Reserved := 0;
  for I := 0 to TrophyCount - 1 do Result.Slots[I] := Rect(0, 0, 0, 0);
  W := Panel.Right - Panel.Left;
  H := Panel.Bottom - Panel.Top;
  if (W <= 0) or (H <= 0) then Exit;
  if not Strip then
  begin
    { the side column: a row of six slots along the bottom, under the stats }
    K := Min(W / 248, H / 524);
    if K < 0.5 then K := 0.5;
    Pad := Round(14 * K);
    Gap := Max(2, Round(5 * K));
    Slot := Min(Round(30 * K), (W - 2 * Pad - (TrophyCount - 1) * Gap) div TrophyCount);
    TotalW := TrophyCount * Slot + (TrophyCount - 1) * Gap;
    X := Panel.Left + (W - TotalW) div 2;
    Y1 := Panel.Bottom - Pad;
    Y0 := Y1 - Slot;
    Result.Chip := False;
    Result.Shelf := Rect(Panel.Left + Pad, Y0 - Round(4 * K), Panel.Right - Pad, Y1);
    for I := 0 to TrophyCount - 1 do
      Result.Slots[I] := Rect(X + I * (Slot + Gap), Y0, X + I * (Slot + Gap) + Slot, Y1);
    Result.Reserved := (Result.Shelf.Bottom - Result.Shelf.Top) + Round(6 * K);
  end
  else
  begin
    { the strip: six icons in the middle column, under who and how far in; or, when
      that column is too narrow, a chip under the portrait }
    K := Min(W / 700, H / 220);
    if K < 0.6 then K := 0.6;
    Pad := Round(12 * K);
    PW := Round((H - 2 * Pad) * 596 / 878);
    MidL := Panel.Left + 2 * Pad + PW;
    RightL := MidL + Round((W - 3 * Pad - PW) * 0.47);
    MidR := RightL - Pad;
    Gap := Max(2, Round(4 * K));
    Slot := Min(Round(26 * K), (MidR - MidL - (TrophyCount - 1) * Gap) div TrophyCount);
    Y1 := Panel.Bottom - Pad;
    if Slot >= 20 then
    begin
      TotalW := TrophyCount * Slot + (TrophyCount - 1) * Gap;
      X := MidL + ((MidR - MidL) - TotalW) div 2;
      Y0 := Y1 - Slot;
      Result.Chip := False;
      Result.Shelf := Rect(MidL, Y0 - Round(3 * K), MidR, Y1);
      for I := 0 to TrophyCount - 1 do
        Result.Slots[I] := Rect(X + I * (Slot + Gap), Y0, X + I * (Slot + Gap) + Slot, Y1);
    end
    else
    begin
      { too narrow for six icons: one chip with the count, under the portrait on the
        left (the portrait is drawn that much shorter: see Reserved) }
      Y0 := Y1 - Max(20, Round(24 * K));
      PW := Round((H - 2 * Pad - (Y1 - Y0) - Round(4 * K)) * 596 / 878);
      Result.Chip := True;
      Result.Shelf := Rect(Panel.Left + Pad, Y0, Panel.Left + Pad + Max(PW, 96), Y1);
    end;
    Result.Reserved := (Result.Shelf.Bottom - Result.Shelf.Top) + Round(4 * K);
  end;
end;

end.
