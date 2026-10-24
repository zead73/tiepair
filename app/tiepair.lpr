program tiepair;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, // this includes the LCL widgetset
  SysUtils, Forms, MainForm;

{$R cards.res}

{ Save files live in <config dir>/<this name>. Pin it, so renaming the exe
  does not make the player's coins and cards disappear. }
function FixedAppName: string;
begin
  Result := 'tiepair';
end;

begin
  OnGetApplicationName := @FixedAppName;
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
