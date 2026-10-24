unit TextIni;

{ A small settings-file reader and writer that works on a string, so it needs
  no files and no desktop-only units (it also compiles with pas2js for the web
  version). The format is the usual one:

      [Section]
      Key=Value
      ; a comment

  Names are matched without regard to case. Reading is forgiving: a missing or
  unreadable entry gives the default you pass. Entries and sections you did not
  touch are kept when the text is written back out. No window code. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  TTextIni = class
  private
    FSections: array of string;       { entry I is Key[I]=Value[I] in section Sections[I] }
    FKeys: array of string;
    FValues: array of string;
    FCount: Integer;
    FOrder: array of string;          { sections in the order they first appear }
    function IndexOf(const Section, Key: string): Integer;
    procedure NoteSection(const Section: string);
  public
    procedure LoadFromText(const Text: string);
    function ToText: string;
    function ReadString(const Section, Key, Default: string): string;
    function ReadInteger(const Section, Key: string; Default: Integer): Integer;
    function ReadBool(const Section, Key: string; Default: Boolean): Boolean;
    procedure WriteString(const Section, Key, Value: string);
    procedure WriteInteger(const Section, Key: string; Value: Integer);
    procedure WriteBool(const Section, Key: string; Value: Boolean);
  end;

implementation

function SameName(const A, B: string): Boolean;
begin
  Result := LowerCase(A) = LowerCase(B);
end;

procedure TTextIni.NoteSection(const Section: string);
var
  I: Integer;
begin
  for I := 0 to High(FOrder) do
    if SameName(FOrder[I], Section) then Exit;
  SetLength(FOrder, Length(FOrder) + 1);
  FOrder[High(FOrder)] := Section;
end;

function TTextIni.IndexOf(const Section, Key: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to FCount - 1 do
    if SameName(FSections[I], Section) and SameName(FKeys[I], Key) then
    begin
      Result := I;
      Exit;
    end;
end;

procedure TTextIni.LoadFromText(const Text: string);
var
  P, Start: Integer;
  Line, Section, Key: string;
  EqPos: Integer;

  procedure Take(const S: string);
  var
    T: string;
  begin
    T := Trim(S);
    if T = '' then Exit;
    if (T[1] = ';') or (T[1] = '#') then Exit;
    if (T[1] = '[') and (T[Length(T)] = ']') then
    begin
      Section := Trim(Copy(T, 2, Length(T) - 2));
      NoteSection(Section);
      Exit;
    end;
    EqPos := Pos('=', T);
    if EqPos < 2 then Exit;                  { no key: not an entry }
    Key := Trim(Copy(T, 1, EqPos - 1));
    WriteString(Section, Key, Trim(Copy(T, EqPos + 1, Length(T))));
  end;

begin
  SetLength(FSections, 0);
  SetLength(FKeys, 0);
  SetLength(FValues, 0);
  SetLength(FOrder, 0);
  FCount := 0;
  Section := '';
  Start := 1;
  for P := 1 to Length(Text) + 1 do
    if (P > Length(Text)) or (Text[P] = #10) then
    begin
      Line := Copy(Text, Start, P - Start);
      Start := P + 1;
      Take(Line);
    end;
end;

function TTextIni.ToText: string;
var
  S, I: Integer;
begin
  Result := '';
  for S := 0 to High(FOrder) do
  begin
    Result := Result + '[' + FOrder[S] + ']' + #10;
    for I := 0 to FCount - 1 do
      if SameName(FSections[I], FOrder[S]) then
        Result := Result + FKeys[I] + '=' + FValues[I] + #10;
  end;
end;

function TTextIni.ReadString(const Section, Key, Default: string): string;
var
  I: Integer;
begin
  I := IndexOf(Section, Key);
  if I < 0 then Result := Default else Result := FValues[I];
end;

function TTextIni.ReadInteger(const Section, Key: string; Default: Integer): Integer;
begin
  Result := StrToIntDef(ReadString(Section, Key, ''), Default);
end;

function TTextIni.ReadBool(const Section, Key: string; Default: Boolean): Boolean;
begin
  Result := ReadInteger(Section, Key, Ord(Default)) <> 0;
end;

procedure TTextIni.WriteString(const Section, Key, Value: string);
var
  I: Integer;
begin
  I := IndexOf(Section, Key);
  if I >= 0 then
  begin
    FValues[I] := Value;
    Exit;
  end;
  NoteSection(Section);
  if FCount >= Length(FKeys) then
  begin
    SetLength(FSections, FCount + 16);
    SetLength(FKeys, FCount + 16);
    SetLength(FValues, FCount + 16);
  end;
  FSections[FCount] := Section;
  FKeys[FCount] := Key;
  FValues[FCount] := Value;
  Inc(FCount);
end;

procedure TTextIni.WriteInteger(const Section, Key: string; Value: Integer);
begin
  WriteString(Section, Key, IntToStr(Value));
end;

procedure TTextIni.WriteBool(const Section, Key: string; Value: Boolean);
begin
  if Value then WriteString(Section, Key, '1') else WriteString(Section, Key, '0');
end;

end.
