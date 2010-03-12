{$ifdef fpc}
{$mode delphi}
{$apptype console}
{$ASMMODE intel}
{$else}
{$apptype console}
{$endif}
procedure DoBreak; assembler;
asm
  int 3;
end;

procedure TestIntelBreak;
begin
  writeln('testing break point');
  try
    DoBreak;
  except
    writeln('handled!');
  end;
  writeln;
end;

procedure TestAccessViolation;
var
  p : PInteger;
begin
  writeln('testing access violation');
  p := nil;
  try
    p^ := 5;
  except
    writeln('handled access violation');
  end;
  writeln;
end;

procedure TestLoop;
var
  i : Integer;
begin
  for i := 1 to 10 do
    writeln(i);
end;

begin
  //TestIntelBreak;
  //TestAccessViolation;
  TestLoop;
  ExitCode := 55;
  //writeln('exiting with error code = ', ExitCode);
  //readln;
end.
