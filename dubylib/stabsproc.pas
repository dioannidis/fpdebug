unit stabsProc; 

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, stabs; 
  
type
  TStabSymArray = array [Word] of TStabSym;
  PStabSymArray = ^TStabSymArray;
  
  TStabProcParams = record
    Name    : String;    
  end;
  
  TStabsCallback = class(TObject)
  public
    procedure DeclareType(const TypeName: AnsiString); virtual; abstract;
    procedure StartFile(const FileName: AnsiString; FirstAddr: LongWord); virtual; abstract;
    procedure DeclareLocalVar(const Name: AnsiString; Addr: LongWord); virtual; abstract;
    
    procedure CodeLine(LineNum: Integer; Addr: LongWord); virtual; abstract;
    
    procedure StartProc(const Name: AnsiString; const StabParams : array of TStabProcParams; ParamsCount: Integer; LineNum: Integer; Addr: LongWord); virtual; abstract;
    procedure EndProc(const Name: AnsiString); virtual; abstract;
    
    procedure AsmSymbol(const SymName: AnsiString; Addr: LongWord); virtual; abstract;
  end;
  
  { TStabsReader }

  TStabsReader = class(TObject)
  private
    Stabs     : PStabSymArray;
    StabsCnt  : Integer;
    StrSyms   : PByteArray;
    StrLen    : Integer;
    fCallback : TStabsCallback;
    
    fProcStack  : TStringList;
    
    function CurrentProcName: AnsiString;
    procedure PushProc(const Name: AnsiString);
    procedure PopProc;

    function StabStr(strx: integer): AnsiString;
    
    procedure DoReadStabs;
    procedure HandleSourceFile(var index: Integer);
    procedure HandleLSym(var index: Integer);
    procedure HandleFunc(var index: Integer);
    procedure HandleLine(var index: Integer);
    procedure HandleAsmSym(var index: Integer);
    
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure ReadStabs(const StabsBuf : array of Byte; StabsLen: Integer; 
      const StabStrBuf: array of byte; StabStrLen: Integer; Callback: TStabsCallback);
  end;
  

implementation

{ TStabsReader }

function TStabsReader.CurrentProcName: AnsiString; 
begin
  if fProcStack.Count > 0 then Result := fProcStack[fProcStack.Count-1]
  else Result := '';
end;

procedure TStabsReader.PushProc(const Name: AnsiString); 
begin
  fProcStack.Add(Name);
end;

procedure TStabsReader.PopProc; 
begin
  fProcStack.Delete(fProcStack.Count-1);
end;

function TStabsReader.StabStr(strx: integer): AnsiString; 
begin
  if strx = 0 then Result := ''
  else Result := PChar(@StrSyms^[strx]);
end;

procedure TStabsReader.DoReadStabs; 
var
  i     : Integer;
begin
  i := 0;  
  while i < StabsCnt do 
    case Stabs^[i].n_type of
      N_SO:   
        HandleSourceFile(i);
      N_LSYM: 
        HandleLSym(i);
      N_FUN:  
        HandleFunc(i);
      N_EXT, N_TYPE, N_TYPE or N_EXT, N_PEXT or N_TYPE: 
        HandleAsmSym(i);
    else
      inc(i);    
    end;
end;

procedure TStabsReader.HandleSourceFile(var index: Integer); 
var
  fileaddr  : LongWord;
  filename  : AnsiString;
begin
  fileaddr := Stabs^[Index].n_value;
  filename := '';
  while (Stabs^[Index].n_type = N_SO) and (Stabs^[Index].n_value = fileaddr) do begin
    filename := filename + StabStr(Stabs^[Index].n_strx);
    inc(index);
  end;
  
  if Assigned(fCallback) then fCallback.StartFile(filename, fileaddr);
end;

procedure TStabsReader.HandleLSym(var index: Integer); 
begin
  if Assigned(fCallback) then 
    fCallback.DeclareType(StabStr(Stabs^[Index].n_strx));
  inc(index);
end;

procedure TStabsReader.HandleFunc(var index: Integer); 
var
  funsym  : TStabSym;
  Params  : array of TStabProcParams;
  i, j    : integer;
  funnm   : AnsiString;
begin
  SetLength(Params, 0);
  funsym := Stabs^[index];
  funnm := StabStr(funsym.n_strx);
  inc(index);
  
  if funnm = '' then begin
    if Assigned(fCallback) then fCallback.EndProc( CurrentProcName );
    PopProc;
    Exit;
  end;
  
  i := index;
  j := 0;
  for i := index to StabsCnt - 1 do begin
    if (Stabs^[i].n_type = N_PSYM) then begin
      if j = length(Params) then begin
        if j = 0 then SetLength(Params, 4)
        else SetLength(Params, j * 4);
      end;
      Params[j].Name := StabStr(Stabs^[index].n_strx);
      inc(j);
    end else
      Break;
  end;

  PushProc(funnm);
  if Assigned(fCallback) then 
    fCallback.StartProc(funnm, Params, j, funsym.n_desc, funsym.n_value );
end;

procedure TStabsReader.HandleLine(var index: Integer); 
begin
  if Assigned(fCallback) then 
    fCallback.CodeLine( Stabs^[index].n_desc, Stabs^[index].n_value );
  inc(index);
end;

procedure TStabsReader.HandleAsmSym(var index: Integer);
begin
  if Assigned(fCallback) then
    fCallBack.AsmSymbol(StabStr( Stabs^[index].n_strx ), Stabs^[index].n_value );
  inc(index);
end;

constructor TStabsReader.Create; 
begin
  fProcStack := TStringList.Create;
end;

destructor TStabsReader.Destroy;  
begin
  fProcStack.Free;
  inherited Destroy;  
end;

procedure HandlePSym(var index: Integer);
begin
  inc(index);
end;
    

procedure TStabsReader.ReadStabs(const StabsBuf: array of Byte; StabsLen: Integer;  
  const StabStrBuf: array of byte; StabStrLen: Integer; Callback: TStabsCallback); 
begin
  Stabs := @StabsBuf;
  StabsCnt := StabsLen div sizeof(TStabSym);
  StrSyms := @StabStrBuf[0];
  StrLen := StabStrLen;
  fCallback := Callback;
  DoReadStabs;
end;


end.

