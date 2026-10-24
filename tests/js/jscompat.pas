unit JsCompat;

{ Lets the desktop test programs run unchanged under pas2js + Node: supplies the
  few desktop routines and classes they call (a random seed, Halt, a temp
  folder, file checks, TIniFile, saving a string list) that pas2js's runtime
  does not have. Added to the test programs only for pas2js; the desktop tests
  never see it. Files are Storage names (kept in memory under Node). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, TextIni;

var
  RandSeed: LongInt;

procedure Randomize;
procedure Halt(Code: Integer);
function GetTempDir: string;
function FileExists(const FileName: string): Boolean;
function DeleteFile(const FileName: string): Boolean;
function ForceDirectories(const Dir: string): Boolean;
function RemoveDir(const Dir: string): Boolean;
function ParamStr(N: Integer): string;

const
  PathDelim = '/';

type
  { Like the desktop TIniFile: every write goes straight to the file. }
  TIniFile = class(TTextIni)
  private
    FFile: string;
    procedure Flush;
  public
    constructor Create(const AFileName: string);
    procedure WriteString(const Section, Key, Value: string);
    procedure WriteInteger(const Section, Key: string; Value: Integer);
    procedure WriteBool(const Section, Key: string; Value: Boolean);
  end;

  TStringListFileHelper = class helper for TStringList
    procedure SaveToFile(const FileName: string);
    procedure LoadFromFile(const FileName: string);
  end;

implementation

uses
  Storage;

procedure Randomize;
begin
  { JavaScript seeds its own random numbers }
end;

procedure Halt(Code: Integer);
begin
  asm
    process.exit(Code);
  end;
end;

function GetTempDir: string;
begin
  Result := 'tmp/';
end;

function FileExists(const FileName: string): Boolean;
begin
  Result := StoreExists(FileName);
end;

function DeleteFile(const FileName: string): Boolean;
begin
  StoreDelete(FileName);
  Result := True;
end;

function ForceDirectories(const Dir: string): Boolean;
begin
  Result := True;                      { there are no folders: names are just keys }
end;

function RemoveDir(const Dir: string): Boolean;
begin
  Result := True;
end;

function ParamStr(N: Integer): string;
begin
  Result := 'test';
end;

constructor TIniFile.Create(const AFileName: string);
var
  Text: string;
begin
  inherited Create;
  FFile := AFileName;
  if StoreRead(FFile, Text) then LoadFromText(Text);
end;

procedure TIniFile.Flush;
begin
  StoreWrite(FFile, ToText);
end;

procedure TIniFile.WriteString(const Section, Key, Value: string);
begin
  inherited WriteString(Section, Key, Value);
  Flush;
end;

procedure TIniFile.WriteInteger(const Section, Key: string; Value: Integer);
begin
  inherited WriteInteger(Section, Key, Value);
  Flush;
end;

procedure TIniFile.WriteBool(const Section, Key: string; Value: Boolean);
begin
  inherited WriteBool(Section, Key, Value);
  Flush;
end;

procedure TStringListFileHelper.SaveToFile(const FileName: string);
begin
  StoreWrite(FileName, Text);
end;

procedure TStringListFileHelper.LoadFromFile(const FileName: string);
var
  S: string;
begin
  if StoreRead(FileName, S) then Text := S else Text := '';
end;

end.
