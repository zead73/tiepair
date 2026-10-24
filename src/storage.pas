unit Storage;

{ Where the game keeps its saved text: coins and cards, campaign progress, the
  mode, saved hands. Everything is read and written as whole pieces of text
  under a name.

  On the desktop a name is a file path in the per-user config folder, and a
  write goes to a temporary file first and is then swapped in, so a crash part
  way through cannot destroy the previous save. In a web page (pas2js) a name
  is a key in the browser's local storage (kept in memory instead when there is
  no browser, as when running under Node for tests, where a name that was never
  written falls back to a real file of that name). No window code. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

{ True if something is stored under Name. }
function StoreExists(const Name: string): Boolean;
{ The text stored under Name (False, and Text = '', if there is none). }
function StoreRead(const Name: string; out Text: string): Boolean;
{ Replaces what is stored under Name. False if it could not be written. }
function StoreWrite(const Name, Text: string): Boolean;
{ Removes what is stored under Name, and any leftover temporary copy. }
procedure StoreDelete(const Name: string);

{ The per-user folder for the game's files (a plain prefix on the web), and the
  full name of one of them. Tests point it somewhere private with SetStoreDir. }
function StoreDir: string;
function StoreName(const FileName: string): string;
procedure SetStoreDir(const Dir: string);

implementation

{$IFDEF PAS2JS}

uses
  JS;

var
  Memory: TJSObject;

function HasBrowserStorage: Boolean;
begin
  asm
    try {
      Result = (typeof window !== 'undefined') && !!window.localStorage;
    } catch (e) {
      Result = false;
    }
  end;
end;

var
  DirOverride: string;

function StoreDir: string;
begin
  if DirOverride <> '' then Result := DirOverride else Result := 'tiepair';
end;

procedure SetStoreDir(const Dir: string);
begin
  DirOverride := Dir;
end;

function StoreName(const FileName: string): string;
begin
  Result := StoreDir + '/' + FileName;
end;

function StoreExists(const Name: string): Boolean;
var
  T: string;
begin
  Result := StoreRead(Name, T);
end;

function StoreRead(const Name: string; out Text: string): Boolean;
begin
  Text := '';
  Result := False;
  if HasBrowserStorage then
  begin
    asm
      var v = window.localStorage.getItem(Name);
      if (v !== null) { Text.set(v); Result = true; }
    end;
  end
  else if Memory.hasOwnProperty(Name) then
  begin
    Text := string(Memory[Name]);
    Result := True;
  end
  else
  begin
    { under Node, a name that was never stored may be a real file (the story
      text, in the tests) }
    asm
      try {
        if (typeof require !== 'undefined') {
          var fs = require('fs');
          if (fs.existsSync(Name)) { Text.set(fs.readFileSync(Name, 'utf8')); Result = true; }
        }
      } catch (e) { }
    end;
  end;
end;

function StoreWrite(const Name, Text: string): Boolean;
begin
  Result := False;
  if HasBrowserStorage then
  begin
    asm
      try {
        window.localStorage.setItem(Name, Text);
        window.localStorage.removeItem(Name + '.tmp');      // as on the desktop, no leftover copy
        Result = true;
      } catch (e) { Result = false; }
    end;
  end
  else
  begin
    Memory[Name] := Text;
    JSDelete(Memory, Name + '.tmp');
    Result := True;
  end;
end;

procedure StoreDelete(const Name: string);
begin
  if HasBrowserStorage then
  begin
    asm
      window.localStorage.removeItem(Name);
      window.localStorage.removeItem(Name + '.tmp');
    end;
  end
  else
  begin
    JSDelete(Memory, Name);
    JSDelete(Memory, Name + '.tmp');
  end;
end;

initialization
  Memory := TJSObject.new;

{$ELSE}

uses
  Classes;

var
  DirOverride: string;

function StoreDir: string;
begin
  if DirOverride <> '' then Result := DirOverride else Result := GetAppConfigDir(False);
end;

procedure SetStoreDir(const Dir: string);
begin
  DirOverride := Dir;
end;

function StoreName(const FileName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(StoreDir) + FileName;
end;

function StoreExists(const Name: string): Boolean;
begin
  Result := FileExists(Name);
end;

function StoreRead(const Name: string; out Text: string): Boolean;
var
  F: TFileStream;
begin
  Result := False;
  Text := '';
  if not FileExists(Name) then Exit;
  try
    F := TFileStream.Create(Name, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Text, F.Size);
      if F.Size > 0 then F.ReadBuffer(Text[1], F.Size);
      Result := True;
    finally
      F.Free;
    end;
  except
    Text := '';
    Result := False;
  end;
end;

function StoreWrite(const Name, Text: string): Boolean;
var
  F: TFileStream;
  Tmp: string;
begin
  Result := False;
  Tmp := Name + '.tmp';
  try
    ForceDirectories(ExtractFilePath(Name));
    F := TFileStream.Create(Tmp, fmCreate);
    try
      if Length(Text) > 0 then F.WriteBuffer(Text[1], Length(Text));
    finally
      F.Free;
    end;
    if FileExists(Name) then DeleteFile(Name);          { Windows cannot rename over a file }
    Result := RenameFile(Tmp, Name);
  except
    Result := False;
  end;
end;

procedure StoreDelete(const Name: string);
begin
  if FileExists(Name) then DeleteFile(Name);
  if FileExists(Name + '.tmp') then DeleteFile(Name + '.tmp');
end;

{$ENDIF}

end.
