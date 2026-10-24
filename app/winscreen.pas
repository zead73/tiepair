unit WinScreen;

{ The "you won" picture (the three vampires and a caption). UI code.
  The picture is embedded in the exe (assets/win/win_screen.png) and scaled to
  fit the area it is given, keeping its proportions; the scaled copy is cached
  per size. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, FPImage, CardImages;

type
  TWinScreenImage = class
  private
    FMaster: TFPMemoryImage;
    FBmp: TBitmap;
    FW, FH: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    { Draws the picture centred inside Area; returns the rectangle it used. }
    function Draw(ACanvas: TCanvas; const Area: TRect): TRect;
  end;

implementation

constructor TWinScreenImage.Create;
begin
  inherited Create;
  FMaster := LoadResourceImage('win_screen');
end;

destructor TWinScreenImage.Destroy;
begin
  FBmp.Free;
  FMaster.Free;
  inherited Destroy;
end;

function TWinScreenImage.Draw(ACanvas: TCanvas; const Area: TRect): TRect;
var
  AW, AH, W, H: Integer;
begin
  AW := Area.Right - Area.Left;
  AH := Area.Bottom - Area.Top;
  if (AW < 16) or (AH < 16) then
  begin
    Result := Rect(0, 0, 0, 0);
    Exit;
  end;
  { fit inside the area, keeping the picture's proportions }
  W := AW;
  H := Round(W * FMaster.Height / FMaster.Width);
  if H > AH then
  begin
    H := AH;
    W := Round(H * FMaster.Width / FMaster.Height);
  end;
  if (FBmp = nil) or (W <> FW) or (H <> FH) then
  begin
    FBmp.Free;
    FBmp := ScaleToBitmap(FMaster, W, H);
    FW := W;
    FH := H;
  end;
  Result.Left := Area.Left + (AW - W) div 2;
  Result.Top := Area.Top + (AH - H) div 2;
  Result.Right := Result.Left + W;
  Result.Bottom := Result.Top + H;
  ACanvas.Draw(Result.Left, Result.Top, FBmp);
end;

end.
