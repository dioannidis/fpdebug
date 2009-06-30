unit macDbgType;

{$mode objfpc}{$H+}

interface

uses
  SysUtils,
  BaseUnix, Unix, machapi, mach_port, dbgTypes, macPtrace, macDbgProc;

type
  { TMachDbgProcess }

  TMachDbgProcess = class(TDbgProcess)
  private
    fchildpid   : TPid;
    fchildtask  : mach_port_name_t;

    catchport   : mach_port_t;
  protected
    waited      : Boolean;
    waitedsig   : Integer;

    procedure SetupChildTask(child: task_t);

  public
    procedure Terminate; override;
    function WaitNextEvent(var Event: TDbgEvent): Boolean; override;
    function GetProcessState: TDbgState; override;

    function GetThreadsCount: Integer; override;
    function GetThreadID(AIndex: Integer): TDbgThreadID; override;
    function GetThreadRegs(ThreadID: TDbgThreadID; Regs: TDbgRegisters): Boolean; override;

    function ReadMem(Offset: TDbgPtr; Count: Integer; var Data: array of byte): Integer; override;
    function WriteMem(Offset: TDbgPtr; Count: Integer; const Data: array of byte): Integer; override;

    function StartProcess(const ACmdLine: String): Boolean;
  end;

implementation

//todo: consider using mach api to launch the child process, rather than unix's fork?
function ForkAndRun(const CommandLine: String; var ChildId: TPid; var ChildTask: mach_port_name_t): Boolean;
var
  apipe : TFilDes;
  len   : Integer;
  res   : Integer;
begin
  Result := false;
  if FpPipe(apipe) < 0 then Exit;

  childid := FpFork;
  if childid < 0 then Exit;

  if childid = 0 then begin
    task_for_pid( mach_task_self, FpGetpid, childtask);
    FpWrite(apipe[1], childtask, sizeof(childtask));
    ptraceme;
    ptrace_sig_as_exc;

    res := FpExecV(CommandLine, nil);
    if res < 0 then begin
      writeln('failed to run: ', CommandLine);
      Halt;
    end;

  end else begin
    len := FpRead(apipe[0], ChildTask, sizeof(childtask) );
    Result := len = sizeof(childtask);
  end;
  FpClose(apipe[0]);
  FpClose(apipe[1]);
end;

function TMachDbgProcess.GetProcessState: TDbgState;
begin
  Result := ds_Nonstarted;
end;

function TMachDbgProcess.GetThreadsCount: Integer;
begin
  Result := 0;
end;

function TMachDbgProcess.GetThreadID(AIndex: Integer): TDbgThreadID;
begin
  Result:=nil;
end;

function TMachDbgProcess.GetThreadRegs(ThreadID: TDbgThreadID; Regs: TDbgRegisters): Boolean;
begin
  Result:=false;
end;

function TMachDbgProcess.ReadMem(Offset: TDbgPtr; Count: Integer; var Data: array of byte): Integer;
var
  r : mach_msg_type_number_t;
begin
  if mach_vm_read(fchildtask, Offset, Count, @Data[0], @r) <> 0 then
    Result := -1
  else
    Result := r;
end;

function TMachDbgProcess.WriteMem(Offset: TDbgPtr; Count: Integer; const Data: array of byte): Integer;
begin
  Result := -1;
end;

procedure TMachDbgProcess.SetupChildTask(child: task_t);
var
  res : Integer;
begin
  //task_set_exception_ports
  catchport := AllocMachPort;
  res :=  task_set_exception_ports(
    child,
    EXC_MASK_ALL,
    catchport,
    EXCEPTION_DEFAULT,
    0);
  writeln('task_set_exception_ports = ', res);
end;

procedure TMachDbgProcess.Terminate;
begin
end;

function GetSigStr(sig: integer): String;
begin
  case sig of
  SIGHUP:  Result := 'SIGHUP';  { hangup  }
  SIGINT:  Result := 'SIGINT'; { interrupt  }
  SIGQUIT:  Result := 'SIGQUIT'; { quit  }
  SIGILL :  Result := 'SIGILL'; { illegal instruction (not reset when caught)  }
  SIGTRAP:  Result := 'SIGTRAP';  { trace trap (not reset when caught)  }
  SIGABRT:  Result := 'SIGABRT'; { abort()  }
  //SIGIOT:   Result := 'SIGIOT'; { compatibility  }
  SIGEMT:   Result := 'SIGEMT'; { EMT instruction  }
  SIGFPE:   Result := 'SIGFPE'; { floating point exception  }
  SIGKILL:  Result := 'SIGKILL'; { kill (cannot be caught or ignored)  }
  SIGBUS :  Result := 'SIGBUS'; { bus error  }
  SIGSEGV:  Result := 'SIGSEGV';  { segmentation violation  }
  SIGSYS :  Result := 'SIGSYS';  { bad argument to system call  }
  SIGPIPE:  Result := 'SIGPIPE';  { write on a pipe with no one to read it  }
  SIGALRM:  Result := 'SIGALRM';  { alarm clock  }
  SIGTERM:  Result := 'SIGTERM'; { software termination signal from kill  }
  SIGURG:   Result := 'SIGURG'; { urgent condition on IO channel  }
  SIGSTOP:  Result := 'SIGSTOP';  { sendable stop signal not from tty  }
  SIGTSTP:  Result := 'SIGTSTP';  { stop signal from tty  }
  SIGCONT:  Result := 'SIGCONT'; { continue a stopped process  }
  SIGCHLD:  Result := 'SIGCHLD'; { to parent on child stop or exit  }
  SIGTTIN:  Result := 'SIGTTIN';  { to readers pgrp upon background tty read  }
  SIGTTOU:  Result := 'SIGTTOU'; { like TTIN for output if (tp->t_local&LTOSTOP)  }
  SIGIO:    Result := 'SIGIO';  { input/output possible signal  }
  SIGXCPU:  Result := 'SIGXCPU';  { exceeded CPU time limit  }
  SIGXFSZ:  Result := 'SIGXFSZ';  { exceeded file size limit  }
  SIGVTALRM:  Result := 'SIGVTALRM';  { virtual time alarm  }
  SIGPROF:  Result := 'SIGPROF'  ;  { profiling time alarm  }
  SIGWINCH:  Result := 'SIGWINCH' ;  { window size changes  }
  SIGINFO:  Result := 'SIGINFO';  { information request  }
  SIGUSR1:  Result := 'SIGUSR1';   { user defined signal 1  }
  SIGUSR2:  Result := 'SIGUSR2';   { user defined signal 2  }
  end;
end;

function TMachDbgProcess.WaitNextEvent(var Event: TDbgEvent): Boolean;
var
  st  : Integer;
  sig : integer;
  res : Integer;
begin
  if fchildpid = 0 then begin
    Result := false;
    Exit;
  end;

  FillChar(Event, SizeOf(Event), 0);
  if waited then begin
    if waitedsig = 5 then
      sig := 0
    else
      sig := waitedsig;
    ptrace_cont(fchildpid, CONT_STOP_ADDR, sig)
  end;

  waited := false;
  res := FpWaitpid(fchildpid, st, 0);
  Result := res > 0;
  if not Result then begin
    writeln('waitpid = ', res);
    Exit;
  end;
  waited := true;

  if res = 0 then
    Event.Kind := dek_ProcessTerminated
  else begin
    with Event do begin
      Debug := 'wait st = ' + IntToStr(st) + '; ';
      if WIFSTOPPED(st) then begin
        waitedsig := wstopsig(st);

        if waitedsig = SIGTRAP
          then Event.Kind := dek_BreakPoint
          else Event.Kind := dek_Other;

        Debug := Debug + ' stop sig = ' + IntToStr(waitedsig) + ' ' + GetSigStr(waitedsig) ;

      end else if wifsignaled(st) then Debug := Debug + ' term sig = ' + IntToStr(wtermsig(st))
      else if wifexited(st) then begin
        Event.Kind := dek_ProcessTerminated;
        Debug := Debug + ' exitcode = ' + IntToStr(wexitStatus(st))
      end else
        Debug := Debug + ' unknown state?';
      Debug := Debug + '; ';
    end;
  end;
end;


function TMachDbgProcess.StartProcess(const ACmdLine: String): Boolean;
begin
  Result := ForkAndRun(ACmdLine, fchildpid, fchildtask);
  SetupChildTask(fchildtask);
end;

function MachDebugProcessStart(const ACmdLine: String): TDbgProcess;
var
  machdbg : TMachDbgProcess;
begin
  machdbg := TMachDbgProcess.Create;
  if machdbg.StartProcess(ACmdLine) then
    Result := machdbg
  else begin
    machdbg.Free;
    Result := nil;
  end;
end;

procedure InitMachDebug;
begin
  DebugProcessStart := @MachDebugProcessStart;
end;

initialization
  InitMachDebug;

end.
