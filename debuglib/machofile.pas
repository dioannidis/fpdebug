{
    fpDebug  -  A debugger for the Free Pascal Compiler.

    Copyright (c) 2012 by Graeme Geldenhuys.

    See the file LICENSE.txt, included in this distribution,
    for details about redistributing fpDebug.

    Description:
      .
}
unit machoFile;

{$mode objfpc}{$H+}

interface

//todo: powerpc, x86_64

uses
  Classes, SysUtils, macho;

type
  TMachOsection = class(TObject)
    is32   : Boolean;
    sec32  : section;
    sec64  : section_64;
  end;

  { TMachOFile }

  TMachOFile = class(TObject)
  private
    cmdbuf    : array of byte;
  public
    header    : mach_header;
    commands  : array of pload_command;
    sections  : TFPList;
    constructor Create;
    destructor Destroy; override;
    function  LoadFromStream(Stream: TStream): Boolean;
  end;


implementation


{ TMachOFile }

constructor TMachOFile.Create;
begin
  sections := TFPList.Create;
end;

destructor TMachOFile.Destroy;
var
  i : integer;
begin
  for i := 0 to sections.Count - 1 do TMachOsection(sections[i]).Free;
  sections.Free;
  inherited Destroy;
end;

function TMachOFile.LoadFromStream(Stream: TStream): Boolean;
var
  i   : Integer;
  j   : Integer;
  ofs : Integer;
  sc  : psection;
  s   : TMachOsection;
begin
  Stream.Read(header, sizeof(header));
  Result := (header.magic = MH_MAGIC) or (header.magic = MH_CIGAM);

  SetLength(cmdbuf, header.sizeofcmds);
  Stream.Read(cmdbuf[0], header.sizeofcmds);

  SetLength(commands, header.ncmds);
  ofs := 0;
  for i := 0 to header.ncmds - 1 do begin
    commands[i] := @cmdbuf[ofs];

    if commands[i]^.cmd = LC_SEGMENT then begin
      sc := @cmdbuf[ofs+sizeof(segment_command)];
      for j := 0 to psegment_command(commands[i])^.nsects- 1 do begin
        s := TMachOSection.Create;
        s.is32:=true;
        s.sec32:=sc^;
        sections.add(s);
        inc(sc);
      end;

    end;
    inc(ofs, commands[i]^.cmdsize);
  end;

end;


end.

