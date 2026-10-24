unit Sound;

{ Tiny cross-platform sound for the game. Every sound is generated in code, so
  there are no sound files to ship.

  Windows: PlaySound from memory.
  Linux:   writes a WAV to the config folder and plays it with paplay,
           pw-play or aplay (whichever is installed). If none is, it is silent.
  Web (pas2js): the page sets PlayWavHandler and plays the bytes itself. }

{$mode objfpc}{$H+}

interface

{ Build 16-bit mono PCM WAV files in memory (exposed so they can be tested). }
function MakeNoWav: string;      { raw bytes in a string }
function MakeWinWav: string;
function MakeTollWav: string;    { one low bell toll (a duel begins) }
function MakeBlowWav: string;    { a heavy thud with a crack (the fatal blow) }
function MakeStingWav: string;   { a sharp dissonant stab (a missed move) }
{ A short card "flick" at each of the given times (ms from the start). }
function MakeTicksWav(const TimesMs: array of Integer): string;

procedure PlayNo;                { negative-feedback buzz, returns immediately }
procedure PlayWin;               { victory jingle, returns immediately }
procedure PlayToll;
procedure PlayBlow;
procedure PlaySting;
{ Plays any WAV from MakeXxxWav. Name is the file name used on Linux (in the
  config folder); the caller should keep Wav around and reuse it. }
procedure PlayWav(const Name, Wav: string);

{$IFDEF PAS2JS}
type
  TPlayWavHandler = procedure(const Name, Wav: string);
var
  PlayWavHandler: TPlayWavHandler;   { set by the web page; nil = silent }
{$ENDIF}

implementation

uses
  SysUtils, Math
  {$IFDEF PAS2JS}
  {$ELSE}
  , Classes
    {$IFDEF WINDOWS}, Windows, MMSystem
    {$ELSE}, Process
    {$ENDIF}
  {$ENDIF};

const
  SampleRate = 22050;

type
  TByteArray = array of Byte;

{ The bytes as a string of characters 0..255. (A string cannot be edited in
  place on the web, and appending one character at a time is slow on the
  desktop, so each side builds it its own way.) }
function BytesToStr(const A: TByteArray): string;
var
  I: Integer;
begin
{$IFDEF PAS2JS}
  Result := '';
  for I := 0 to High(A) do Result := Result + Chr(A[I]);
{$ELSE}
  SetLength(Result, Length(A));
  for I := 0 to High(A) do Result[I + 1] := Chr(A[I]);
{$ENDIF}
end;

procedure PutLE32(var S: string; V: LongWord);
begin
  S := S + Chr(V and $FF) + Chr((V shr 8) and $FF) + Chr((V shr 16) and $FF)
         + Chr((V shr 24) and $FF);
end;

procedure PutLE16(var S: string; V: Word);
begin
  S := S + Chr(V and $FF) + Chr((V shr 8) and $FF);
end;

{ Wraps raw 16-bit mono PCM bytes in a WAV header. }
function WrapWav(const Data: string): string;
begin
  Result := 'RIFF';
  PutLE32(Result, 36 + Length(Data));
  Result := Result + 'WAVEfmt ';
  PutLE32(Result, 16);
  PutLE16(Result, 1);                   { PCM }
  PutLE16(Result, 1);                   { mono }
  PutLE32(Result, SampleRate);
  PutLE32(Result, SampleRate * 2);      { byte rate }
  PutLE16(Result, 2);                   { block align }
  PutLE16(Result, 16);                  { bits per sample }
  Result := Result + 'data';
  PutLE32(Result, Length(Data));
  Result := Result + Data;
end;

{ Two short low tones, the second lower: a "uh-oh" buzz, about 0.28 s. }
function MakeNoWav: string;
var
  I, N, Half: Integer;
  Freq, Phase, Env: Double;
  V: SmallInt;
  Data: string;
begin
  N := SampleRate * 28 div 100;
  Half := N div 2;
  Data := '';
  Phase := 0;
  for I := 0 to N - 1 do
  begin
    if I < Half then Freq := 220 else Freq := 165;
    Phase := Phase + 2 * Pi * Freq / SampleRate;
    { square-ish wave, fades out within each half so there are no clicks }
    Env := 1 - ((I mod Half) / Half);
    if Env > 0.1 then
    begin
      if Sin(Phase) >= 0 then V := Round(7000 * Env) else V := -Round(7000 * Env);
    end
    else
      V := 0;
    PutLE16(Data, Word(V));
  end;
  Result := WrapWav(Data);
end;

{ ---- victory jingle: two bell tolls, then a rising A-minor organ arpeggio
        resolving into a held chord (about 3.6 s) ---- }

type
  TSamples = array of Double;

{ Adds one decaying sine partial to Buf, starting at StartSec. Tau is the
  decay time constant; a short attack and release avoid clicks. }
procedure AddPartial(var Buf: TSamples; StartSec, Freq, Amp, Tau, DurSec: Double);
var
  I, First, Last: Integer;
  T, Env: Double;
begin
  First := Round(StartSec * SampleRate);
  Last := Min(High(Buf), First + Round(DurSec * SampleRate));
  for I := Max(0, First) to Last do
  begin
    T := (I - First) / SampleRate;
    Env := Exp(-T / Tau);
    if T < 0.008 then Env := Env * (T / 0.008);                { attack }
    if DurSec - T < 0.05 then Env := Env * ((DurSec - T) / 0.05);  { release }
    Buf[I] := Buf[I] + Amp * Env * Sin(2 * Pi * Freq * T);
  end;
end;

procedure AddBell(var Buf: TSamples; StartSec, Freq, Amp: Double);
const
  Ratios: array[0..5] of Double = (1.0, 2.0, 2.4, 3.0, 4.2, 5.4);   { inharmonic }
  Amps:   array[0..5] of Double = (1.0, 0.7, 0.45, 0.35, 0.2, 0.12);
  Taus:   array[0..5] of Double = (1.6, 1.1, 0.8, 0.6, 0.4, 0.25);
var
  K: Integer;
begin
  for K := 0 to High(Ratios) do
    AddPartial(Buf, StartSec, Freq * Ratios[K], Amp * Amps[K], Taus[K], 2.2);
end;

procedure AddOrgan(var Buf: TSamples; StartSec, Freq, Amp, Tau, DurSec: Double);
var
  K: Integer;
begin
  for K := 1 to 4 do
    AddPartial(Buf, StartSec, Freq * K, Amp / K, Tau, DurSec);
end;

function MakeWinWav: string;
const
  A3 = 220.0; C4 = 261.63; E4 = 329.63; A4 = 440.0;
var
  Buf: TSamples;
  I, N: Integer;
  Peak, Scale: Double;
  V: SmallInt;
  Bytes: TByteArray;
begin
  N := Round(3.6 * SampleRate);
  SetLength(Buf, N);
  for I := 0 to N - 1 do Buf[I] := 0;

  AddBell(Buf, 0.00, 110.0, 0.50);               { toll ... }
  AddBell(Buf, 0.85, 110.0, 0.42);               { ... toll }

  AddOrgan(Buf, 1.70, A3, 0.30, 0.30, 0.45);     { rising arpeggio }
  AddOrgan(Buf, 1.88, C4, 0.30, 0.30, 0.45);
  AddOrgan(Buf, 2.06, E4, 0.30, 0.30, 0.45);
  AddOrgan(Buf, 2.24, A4, 0.30, 0.30, 0.55);

  AddOrgan(Buf, 2.45, A3 / 2, 0.30, 0.9, 1.1);   { held minor chord }
  AddOrgan(Buf, 2.45, A3, 0.28, 0.9, 1.1);
  AddOrgan(Buf, 2.45, C4, 0.28, 0.9, 1.1);
  AddOrgan(Buf, 2.45, E4, 0.28, 0.9, 1.1);
  AddOrgan(Buf, 2.45, A4, 0.22, 0.9, 1.1);

  Peak := 0;
  for I := 0 to N - 1 do
    if Abs(Buf[I]) > Peak then Peak := Abs(Buf[I]);
  if Peak < 1e-9 then Peak := 1;
  Scale := 0.8 * 32767 / Peak;                   { leave headroom: no clipping }

  SetLength(Bytes, N * 2);
  for I := 0 to N - 1 do
  begin
    V := Round(Buf[I] * Scale);
    Bytes[2 * I] := Word(V) and $FF;
    Bytes[2 * I + 1] := (Word(V) shr 8) and $FF;
  end;
  Result := WrapWav(BytesToStr(Bytes));
end;

{ Scales Buf so its loudest point is PeakFrac of full scale, as a WAV. }
function SamplesToWav(const Buf: TSamples; PeakFrac: Double): string;
var
  I, N: Integer;
  Peak, Scale: Double;
  V: SmallInt;
  Bytes: TByteArray;
begin
  N := Length(Buf);
  Peak := 0;
  for I := 0 to N - 1 do
    if Abs(Buf[I]) > Peak then Peak := Abs(Buf[I]);
  if Peak < 1e-9 then Peak := 1;
  Scale := PeakFrac * 32767 / Peak;
  SetLength(Bytes, N * 2);
  for I := 0 to N - 1 do
  begin
    V := Round(Buf[I] * Scale);
    Bytes[2 * I] := Word(V) and $FF;
    Bytes[2 * I + 1] := (Word(V) shr 8) and $FF;
  end;
  Result := WrapWav(BytesToStr(Bytes));
end;

function MakeTollWav: string;
var
  Buf: TSamples;
  I, N: Integer;
begin
  N := Round(2.6 * SampleRate);
  Buf := nil;
  SetLength(Buf, N);
  for I := 0 to N - 1 do Buf[I] := 0;
  AddBell(Buf, 0.0, 110.0, 0.6);
  Result := SamplesToWav(Buf, 0.6);
end;

{ A falling low thump plus a short burst of noise. }
function MakeBlowWav: string;
var
  Buf: TSamples;
  I, N, Seed: Integer;
  T, Freq, Phase, Noise, Prev: Double;
begin
  N := Round(0.9 * SampleRate);
  Buf := nil;
  SetLength(Buf, N);
  Phase := 0;
  Prev := 0;
  Seed := 4242;
  for I := 0 to N - 1 do
  begin
    T := I / SampleRate;
    Freq := 45 + 60 * Exp(-T / 0.07);                      { pitch drops fast }
    Phase := Phase + 2 * Pi * Freq / SampleRate;
    Seed := (Seed * 1103515245 + 12345) and $7FFFFFFF;
    Noise := (Seed / $3FFFFFFF) - 1;
    Buf[I] := 1.0 * Exp(-T / 0.22) * Sin(Phase)                   { the thud }
            + 0.8 * Exp(-T / 0.03) * (Noise - 0.7 * Prev)         { the crack }
            + 0.25 * Exp(-T / 0.5) * Sin(2 * Pi * 98 * T);        { a low ring }
    Prev := Noise;
  end;
  { no click at the very start }
  for I := 0 to 40 do Buf[I] := Buf[I] * (I / 40);
  Result := SamplesToWav(Buf, 0.85);
end;

{ Two clashing tones (a minor second apart) with a bite of noise, gone in a
  third of a second: unpleasant on purpose, but short. }
function MakeStingWav: string;
var
  Buf: TSamples;
  I, N, Seed: Integer;
  T, Env, Noise, Prev, Wob: Double;
begin
  N := Round(0.38 * SampleRate);
  Buf := nil;
  SetLength(Buf, N);
  Seed := 777;
  Prev := 0;
  for I := 0 to N - 1 do
  begin
    T := I / SampleRate;
    Env := Exp(-T / 0.09);
    if I < 60 then Env := Env * (I / 60);
    Seed := (Seed * 1103515245 + 12345) and $7FFFFFFF;
    Noise := (Seed / $3FFFFFFF) - 1;
    Wob := 1 + 0.015 * Sin(2 * Pi * 38 * T);              { a slight shudder }
    { sawtooth-ish tones a semitone apart: 220 Hz and 233 Hz }
    Buf[I] := Env * (0.5 * (2 * Frac(T * 220 * Wob) - 1)
                   + 0.5 * (2 * Frac(T * 233 * Wob) - 1))
            + 0.5 * Exp(-T / 0.02) * (Noise - 0.8 * Prev);
    Prev := Noise;
  end;
  for I := 0 to 59 do Buf[I] := Buf[I] * (I / 60);        { no click at the start }
  Result := SamplesToWav(Buf, 0.6);
end;

{ Soft card flicks: a burst of high-passed noise plus a tiny low thump, each
  fading in about 30 ms. Quieter than the jingle so a run of them is gentle. }
function MakeTicksWav(const TimesMs: array of Integer): string;
const
  TickLen = 0.045;                               { seconds per flick }
var
  I, K, N, First, L, Seed: Integer;
  Buf: TSamples;
  Last, T, Noise, Prev, Env, Peak, Scale: Double;
  V: SmallInt;
  Bytes: TByteArray;
begin
  Last := 0;
  for K := 0 to High(TimesMs) do
    if TimesMs[K] > Last then Last := TimesMs[K];
  N := Round((Last / 1000 + 0.12) * SampleRate);
  Buf := nil;
  SetLength(Buf, N);
  for I := 0 to N - 1 do Buf[I] := 0;
  L := Round(TickLen * SampleRate);
  Seed := 12345;
  for K := 0 to High(TimesMs) do
  begin
    First := Round(TimesMs[K] / 1000 * SampleRate);
    Prev := 0;
    for I := 0 to L - 1 do
    begin
      if First + I >= N then Break;
      Seed := (Seed * 1103515245 + 12345) and $7FFFFFFF;       { cheap noise }
      Noise := (Seed / $3FFFFFFF) - 1;
      T := I / SampleRate;
      Env := Exp(-T / 0.009);
      if I < 24 then Env := Env * (I / 24);                    { no click }
      Buf[First + I] := Buf[First + I]
        + 0.55 * Env * (Noise - 0.85 * Prev)                   { high-passed noise }
        + 0.25 * Env * Sin(2 * Pi * 150 * T);                  { soft thump }
      Prev := Noise;
    end;
  end;
  Peak := 0;
  for I := 0 to N - 1 do
    if Abs(Buf[I]) > Peak then Peak := Abs(Buf[I]);
  if Peak < 1e-9 then Peak := 1;
  Scale := 0.55 * 32767 / Peak;
  SetLength(Bytes, N * 2);
  for I := 0 to N - 1 do
  begin
    V := Round(Buf[I] * Scale);
    Bytes[2 * I] := Word(V) and $FF;
    Bytes[2 * I + 1] := (Word(V) shr 8) and $FF;
  end;
  Result := WrapWav(BytesToStr(Bytes));
end;

{$IFDEF PAS2JS}
procedure PlayWav(const Name, Wav: string);
begin
  if Assigned(PlayWavHandler) then PlayWavHandler(Name, Wav);
end;
{$ELSE}
{$IFDEF WINDOWS}
var
  Playing: string;     { keeps the bytes alive while PlaySound plays them }

procedure PlayWav(const Name, Wav: string);
begin
  Playing := Wav;
  PlaySound(PChar(Playing), 0, SND_MEMORY or SND_ASYNC or SND_NODEFAULT);
end;
{$ELSE}
function FindPlayer(out Exe: string): Boolean;
var
  Names: array[0..2] of string = ('paplay', 'pw-play', 'aplay');
  I: Integer;
begin
  Result := False;
  for I := 0 to High(Names) do
  begin
    Exe := FileSearch(Names[I], GetEnvironmentVariable('PATH'));
    if Exe <> '' then Exit(True);
  end;
end;

{ Writes Wav to <config dir>/<Name> if the file is missing or a different
  size (so an updated sound replaces an old file), then plays it. }
procedure PlayWav(const Name, Wav: string);
var
  Dir, FileName, Exe: string;
  F: TFileStream;
  P: TProcess;
  Stale: Boolean;
begin
  if not FindPlayer(Exe) then Exit;
  Dir := IncludeTrailingPathDelimiter(GetAppConfigDir(False));
  FileName := Dir + Name;
  try
    Stale := True;
    if FileExists(FileName) then
    begin
      F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
      try
        Stale := F.Size <> Length(Wav);
      finally
        F.Free;
      end;
    end;
    if Stale then
    begin
      ForceDirectories(Dir);
      F := TFileStream.Create(FileName, fmCreate);
      try
        F.WriteBuffer(Wav[1], Length(Wav));
      finally
        F.Free;
      end;
    end;
    P := TProcess.Create(nil);
    try
      P.Executable := Exe;
      P.Parameters.Add(FileName);
      P.Options := [];                  { do not wait for it to finish }
      P.Execute;
    finally
      P.Free;
    end;
  except
    { sound is a nicety; never let it break the game }
  end;
end;
{$ENDIF}
{$ENDIF}

var
  NoCache, WinCache, TollCache, BlowCache, StingCache: string;       { each sound is built once }

procedure PlayNo;
begin
  if NoCache = '' then NoCache := MakeNoWav;
  PlayWav('no.wav', NoCache);
end;

procedure PlayWin;
begin
  if WinCache = '' then WinCache := MakeWinWav;
  PlayWav('win.wav', WinCache);
end;

procedure PlayToll;
begin
  if TollCache = '' then TollCache := MakeTollWav;
  PlayWav('toll.wav', TollCache);
end;

procedure PlayBlow;
begin
  if BlowCache = '' then BlowCache := MakeBlowWav;
  PlayWav('blow.wav', BlowCache);
end;

procedure PlaySting;
begin
  if StingCache = '' then StingCache := MakeStingWav;
  PlayWav('sting.wav', StingCache);
end;

end.
