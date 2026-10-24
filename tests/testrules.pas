program testrules;

{ The player's rules text: every card, every vampire and every number the game
  really uses must be in it, and nothing may be left over from formatting. }

{$mode objfpc}{$H+}

uses SysUtils, Classes, Pyramid, Inventory, Specials, Vampires, Duel, Story, Rules, Cosmetics, Relics
  {$IFDEF PAS2JS}, JsCompat{$ENDIF};

var
  Failures: Integer = 0;

procedure Check(Cond: Boolean; const Msg: string);
begin
  if not Cond then
  begin
    WriteLn('FAIL: ', Msg);
    Inc(Failures);
  end;
end;

function StoryPath: string;
begin
{$IFDEF PAS2JS}
  Result := 'assets/story/story.ini';          { run from the project folder }
{$ELSE}
  Result := ExtractFilePath(ParamStr(0)) + '../assets/story/story.ini';
{$ENDIF}
end;

var
  St: TStory;
  Text, Body: string;
  I: Integer;
  K: TSpecialKind;
begin
  St := TStory.Create;
  try
    St.LoadFromFile(StoryPath);
    Check(RulesSectionCount >= 8, 'a reasonable number of sections');
    Text := RulesPlainText(St);
    for I := 0 to RulesSectionCount - 1 do
    begin
      Body := RulesBody(I, St);
      Check(RulesHeading(I, St) <> '', 'section ' + IntToStr(I) + ' has a heading');
      Check(Length(Body) > 60, 'section ' + IntToStr(I) + ' has a body');
      Check(Pos(UpperCase(RulesHeading(I, St)), Text) > 0, 'section ' + IntToStr(I) + ' is in the plain text');
      Check((Pos('%d', Body) = 0) and (Pos('%s', Body) = 0), 'section ' + IntToStr(I) + ' has no leftover %d or %s (a Format mistake)');
      Check(Pos('  ', Body) = 0, 'section ' + IntToStr(I) + ' has no double spaces');
    end;
    for K := Low(TSpecialKind) to High(TSpecialKind) do
    begin
      Check(Pos(SpecialName[K], Text) > 0, SpecialName[K] + ' is described');
      Check(Pos(SpecialName[K] + ' (' + IntToStr(SpecialPrice[K]) + ' coins)', Text) > 0, SpecialName[K] + ' is shown with its real price');
    end;
    for I := 0 to VampireCount - 1 do
      Check(Pos(St.Name(I), Text) > 0, 'vampire ' + IntToStr(I) + ' is named');
    Check(Pos('Bitten', Text) > 0, 'the bite trick');
    Check(Pos('Chained', Text) > 0, 'the chain trick');
    Check(Pos('Hunger', Text) > 0, 'the hunger trick');
    Check(Pos('silver cross', Text) > 0, 'the silver cross');
    Check(Pos('Wild card', RulesBody(8, St)) > 0, 'and how to claim it');
    Check(Pos('Records', Text) > 0, 'the Records');
    Check(Pos(St.TrophyName('flawless'), Text) > 0, 'the trophies are listed by name');
    Check(Pos(Format('%d coins for a card back', [BackPrice]), Text) > 0, 'the Style prices');
    Check(Pos(St.RelicName('pick') + ' (' + IntToStr(RelicPrice(rlPick)) + ' coins)', Text) > 0, 'every relic with its real price');
    Check(Pos(St.RelicName('moonstone') + ' (' + IntToStr(RelicPrice(rlMoonstone)) + ' coins)', Text) > 0, 'the Moonstone too');
    Check(Pos('Erase everything', RulesBody(10, St)) > 0, 'and what clears them');
    Check(Pos('undo card', Text) > 0, 'undo cards');
    Check(Pos(Format('%d coins', [WinCoins]), Text) > 0, 'the Free Play pay');
    Check(Pos(Format('%d coins', [BitePenaltyCoins]), Text) > 0, 'the bite cost');
    Check(Pos(Format('%dth draw', [FeedEvery]), Text) > 0, 'the hunger rhythm');
    Check(Pos(Format('%d vampires', [VampireCount]), Text) > 0, 'the number of vampires');
    Check(Pos('coffee', LowerCase(Text)) = 0, 'the hidden word is not given away');
    Check(Pos(RulesBreak, RulesBody(1, St)) > 0, 'paragraphs are separated');
  finally
    St.Free;
  end;
  if Failures = 0 then WriteLn('ALL RULES TESTS PASSED')
  else
  begin
    WriteLn(Failures, ' FAILURES');
    Halt(1);
  end;
end.
