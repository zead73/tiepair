unit CardImages;

{ Card pictures for the table. UI code (uses Graphics).

  Faces come from the PNGs embedded in the exe (see make-resources.sh) and are
  smoothly scaled to the current card size, then cached. The card back is
  drawn in code, so it is crisp at any size. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, IntfGraphics, GraphType, LCLType,
  FPImage, FPCanvas, FPImgCanv, FPReadPNG, Cards, Cosmetics;

type
  TCardImages = class
  private
    FW, FH: Integer;
    FMasters: array[TSuit, TRank] of TFPMemoryImage;
    FFaces: array[TSuit, TRank] of TBitmap;
    procedure ClearFaces;
    function Master(S: TSuit; R: TRank): TFPMemoryImage;
    function BuildFace(S: TSuit; R: TRank): TBitmap;
  public
    destructor Destroy; override;
    { Call before drawing; rescales (lazily) only if the size changed. }
    procedure SetSize(W, H: Integer);
    function Face(const C: TCard): TBitmap;
  end;

{ Which card back is drawn (see Cosmetics; 0 is the original). The window sets it. }
var
  BackStyle: Integer = 0;

procedure DrawCardBack(ACanvas: TCanvas; const R: TRect);
{ A card back in a given style (the Style page's previews). }
procedure DrawCardBackStyle(ACanvas: TCanvas; const R: TRect; AStyle: Integer);
{ A Cosmetics colour (0xRRGGBB) as a canvas colour. }
function StyleColor(C: Integer): TColor;

{ Shared by the win screen: load an embedded PNG, and scale any image smoothly
  into a new TBitmap with alpha. Caller owns both results. }
function LoadResourceImage(const ResName: string): TFPMemoryImage;
function ScaleToBitmap(Src: TFPCustomImage; W, H: Integer): TBitmap;
{ The two halves of ScaleToBitmap: smooth scaling, then conversion to a bitmap
  (optionally darkened: Brightness 1 = unchanged, 0 = black; alpha is kept). }
function ScaleToImage(Src: TFPCustomImage; W, H: Integer): TFPMemoryImage;
function ImageToBitmap(Img: TFPCustomImage; Brightness: Double): TBitmap;

implementation

const
  SuitFile: array[TSuit] of string = ('clubs', 'diamonds', 'hearts', 'spades');

destructor TCardImages.Destroy;
var
  S: TSuit;
  R: TRank;
begin
  ClearFaces;
  for S := Low(TSuit) to High(TSuit) do
    for R := Low(TRank) to High(TRank) do
      FMasters[S, R].Free;
  inherited Destroy;
end;

procedure TCardImages.ClearFaces;
var
  S: TSuit;
  R: TRank;
begin
  for S := Low(TSuit) to High(TSuit) do
    for R := Low(TRank) to High(TRank) do
    begin
      FFaces[S, R].Free;
      FFaces[S, R] := nil;
    end;
end;

procedure TCardImages.SetSize(W, H: Integer);
begin
  if (W = FW) and (H = FH) then Exit;
  ClearFaces;
  FW := W;
  FH := H;
end;

function LoadResourceImage(const ResName: string): TFPMemoryImage;
var
  RS: TResourceStream;
begin
  RS := TResourceStream.Create(HInstance, UpperCase(ResName), RT_RCDATA);
  try
    Result := TFPMemoryImage.Create(0, 0);
    Result.LoadFromStream(RS);
  finally
    RS.Free;
  end;
end;

function ScaleToImage(Src: TFPCustomImage; W, H: Integer): TFPMemoryImage;
var
  Cv: TFPImageCanvas;
  Interp: TMitchelInterpolation;
begin
  Result := TFPMemoryImage.Create(W, H);
  Cv := TFPImageCanvas.Create(Result);
  Interp := TMitchelInterpolation.Create;
  try
    Cv.Interpolation := Interp;
    Cv.StretchDraw(0, 0, W, H, Src);
  finally
    Cv.Free;
    Interp.Free;
  end;
end;

function ImageToBitmap(Img: TFPCustomImage; Brightness: Double): TBitmap;
var
  Li: TLazIntfImage;
  X, Y: Integer;
  C: TFPColor;
begin
  Li := TLazIntfImage.Create(Img.Width, Img.Height, [riqfRGB, riqfAlpha]);
  try
    for Y := 0 to Img.Height - 1 do
      for X := 0 to Img.Width - 1 do
      begin
        C := Img.Colors[X, Y];
        if Brightness < 1 then
        begin
          C.Red := Round(C.Red * Brightness);
          C.Green := Round(C.Green * Brightness);
          C.Blue := Round(C.Blue * Brightness);
        end;
        Li.Colors[X, Y] := C;
      end;
    Result := TBitmap.Create;
    Result.LoadFromIntfImage(Li);
  finally
    Li.Free;
  end;
end;

function ScaleToBitmap(Src: TFPCustomImage; W, H: Integer): TBitmap;
var
  Img: TFPMemoryImage;
begin
  Img := ScaleToImage(Src, W, H);
  try
    Result := ImageToBitmap(Img, 1);
  finally
    Img.Free;
  end;
end;

function TCardImages.Master(S: TSuit; R: TRank): TFPMemoryImage;
begin
  if FMasters[S, R] = nil then
    FMasters[S, R] := LoadResourceImage(Format('card_%s_%.2d', [SuitFile[S], R]));
  Result := FMasters[S, R];
end;

function TCardImages.BuildFace(S: TSuit; R: TRank): TBitmap;
begin
  Result := ScaleToBitmap(Master(S, R), FW, FH);
end;

function TCardImages.Face(const C: TCard): TBitmap;
begin
  if FFaces[C.Suit, C.Rank] = nil then
    FFaces[C.Suit, C.Rank] := BuildFace(C.Suit, C.Rank);
  Result := FFaces[C.Suit, C.Rank];
end;

{ ---- card back: deep burgundy, gold frame, diamond lattice, crescent moon ---- }

function StyleColor(C: Integer): TColor;
begin
  Result := RGBToColor(ColorR(C), ColorG(C), ColorB(C));
end;

procedure DrawCardBack(ACanvas: TCanvas; const R: TRect);
begin
  DrawCardBackStyle(ACanvas, R, BackStyle);
end;

procedure DrawCardBackStyle(ACanvas: TCanvas; const R: TRect; AStyle: Integer);
var
  Wine, WineDark, WineLine, Gold, GoldDim: TColor;     { style 0 is RGB(42,13,26), (13,6,8), (74,26,44), (201,162,74), (122,42,58) }
  W, H, Inset, K, Step, Lo, Hi, CX, CY, Rad: Integer;
  L, T, Rt, B: Integer;
begin
  Wine := StyleColor(BackColor(AStyle, 0));
  WineDark := StyleColor(BackColor(AStyle, 1));
  WineLine := StyleColor(BackColor(AStyle, 2));
  Gold := StyleColor(BackColor(AStyle, 3));
  GoldDim := StyleColor(BackColor(AStyle, 4));
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  with ACanvas do
  begin
    Brush.Style := bsSolid;
    Pen.Style := psSolid;
    Pen.Width := 1;
    Pen.Color := WineDark;
    Brush.Color := Wine;
    RoundRect(R, W div 8, W div 8);

    { lattice, clipped by hand to the inner panel }
    Inset := W div 7;
    L := R.Left + Inset;
    T := R.Top + Inset;
    Rt := R.Right - Inset;
    B := R.Bottom - Inset;
    Pen.Color := WineLine;
    Step := W div 5;
    if Step < 4 then Step := 4;
    K := T - Rt;                                   { lines y = x + K }
    while K <= B - L do
    begin
      Lo := L; if T - K > Lo then Lo := T - K;
      Hi := Rt; if B - K < Hi then Hi := B - K;
      if Lo < Hi then Line(Lo, Lo + K, Hi, Hi + K);
      Inc(K, Step);
    end;
    K := T + L;                                    { lines y = K - x }
    while K <= B + Rt do
    begin
      Lo := L; if K - B > Lo then Lo := K - B;
      Hi := Rt; if K - T < Hi then Hi := K - T;
      if Lo < Hi then Line(Lo, K - Lo, Hi, K - Hi);
      Inc(K, Step);
    end;

    { frames }
    Brush.Style := bsClear;
    Pen.Color := Gold;
    Pen.Width := W div 40 + 1;
    RoundRect(R.Left + W div 12, R.Top + W div 12, R.Right - W div 12,
      R.Bottom - W div 12, W div 10, W div 10);
    Pen.Width := 1;
    Pen.Color := GoldDim;
    RoundRect(R.Left + W div 8 + 1, R.Top + W div 8 + 1, R.Right - W div 8 - 1,
      R.Bottom - W div 8 - 1, W div 12, W div 12);

    { medallion with a crescent moon }
    CX := (R.Left + R.Right) div 2;
    CY := (R.Top + R.Bottom) div 2;
    Rad := W * 28 div 100;
    Brush.Style := bsSolid;
    Brush.Color := WineDark;
    Pen.Color := Gold;
    Pen.Width := W div 50 + 1;
    Ellipse(CX - Rad, CY - Rad, CX + Rad + 1, CY + Rad + 1);
    Pen.Width := 1;
    Pen.Color := Gold;
    Brush.Color := Gold;
    Rad := W * 17 div 100;
    Ellipse(CX - Rad, CY - Rad, CX + Rad + 1, CY + Rad + 1);
    Brush.Color := WineDark;
    Pen.Color := WineDark;
    Rad := W * 15 div 100;
    Ellipse(CX - Rad + W * 7 div 100, CY - Rad - W * 3 div 100,
      CX + Rad + W * 7 div 100 + 1, CY + Rad - W * 3 div 100 + 1);
    { small four-point star }
    Brush.Color := Gold;
    Pen.Color := Gold;
    K := W * 7 div 100;
    CX := CX + W * 12 div 100;
    CY := CY - W * 11 div 100;
    Polygon([Point(CX, CY - K), Point(CX + K div 3, CY - K div 3),
             Point(CX + K, CY), Point(CX + K div 3, CY + K div 3),
             Point(CX, CY + K), Point(CX - K div 3, CY + K div 3),
             Point(CX - K, CY), Point(CX - K div 3, CY - K div 3)]);
    Brush.Style := bsSolid;
    if H < 0 then ;   { H unused otherwise; keeps the compiler quiet }
  end;
end;

end.
