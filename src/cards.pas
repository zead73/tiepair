unit Cards;

{ Generic playing-card types. No game rules and no UI code in here. }

{$mode objfpc}{$H+}

interface

uses SysUtils;

type
  TSuit = (suClubs, suDiamonds, suHearts, suSpades);
  TRank = 1..13;  { 1 = Ace, 11 = Jack, 12 = Queen, 13 = King }

  TCard = record
    Suit: TSuit;
    Rank: TRank;
    FaceUp: Boolean;
  end;

  TCardArray = array of TCard;

  TDeck = class
  private
    FCards: TCardArray;
    function GetCount: Integer;
  public
    constructor Create;                  { standard 52-card deck, face down }
    { Custom deck for tests: ACards are listed in the order they will be drawn }
    constructor CreateFromCards(const ACards: TCardArray);
    procedure Shuffle;
    function Draw: TCard;                { removes and returns the top card }
    property Count: Integer read GetCount;
  end;

function CardName(const C: TCard): string;
function IsRed(const C: TCard): Boolean;

implementation

const
  SuitNames: array[TSuit] of string = ('Clubs', 'Diamonds', 'Hearts', 'Spades');
  RankNames: array[TRank] of string = ('Ace', '2', '3', '4', '5', '6', '7',
    '8', '9', '10', 'Jack', 'Queen', 'King');

function CardName(const C: TCard): string;
begin
  Result := RankNames[C.Rank] + ' of ' + SuitNames[C.Suit];
end;

function IsRed(const C: TCard): Boolean;
begin
  Result := C.Suit in [suDiamonds, suHearts];
end;

constructor TDeck.Create;
var
  S: TSuit;
  R: TRank;
  N: Integer;
begin
  inherited Create;
  SetLength(FCards, 52);
  N := 0;
  for S := Low(TSuit) to High(TSuit) do
    for R := Low(TRank) to High(TRank) do
    begin
      FCards[N].Suit := S;
      FCards[N].Rank := R;
      FCards[N].FaceUp := False;
      Inc(N);
    end;
end;

constructor TDeck.CreateFromCards(const ACards: TCardArray);
var
  I, N: Integer;
begin
  inherited Create;
  N := Length(ACards);
  SetLength(FCards, N);
  for I := 0 to N - 1 do      { Draw takes from the end, so store reversed }
    FCards[N - 1 - I] := ACards[I];
end;

function TDeck.GetCount: Integer;
begin
  Result := Length(FCards);
end;

procedure TDeck.Shuffle;
var
  I, J: Integer;
  T: TCard;
begin
  for I := High(FCards) downto 1 do   { Fisher-Yates }
  begin
    J := Random(I + 1);
    T := FCards[I];
    FCards[I] := FCards[J];
    FCards[J] := T;
  end;
end;

function TDeck.Draw: TCard;
begin
  if Length(FCards) = 0 then
    raise Exception.Create('Deck is empty');
  Result := FCards[High(FCards)];
  SetLength(FCards, Length(FCards) - 1);
end;

end.
