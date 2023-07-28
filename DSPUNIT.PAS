{**********************************************************************}
{UNIT DSPUNIT Ver 2.00                                                 }
{                                                                      }
{A real program that makes your sound to blow away.                    }
{A Sound Blaster collection routines programmed by George Papaioannou  }
{Thessaloniki 1995,96   Ver 2.00        Written For Digital SunRize    }
{                                                                      }
{                                                                      }
{Note :This Unit runs ONLY For DMA channel 1-7 and for IRQs 1-7.       }
{      Also it supports 16-Bit DMA channels.So,watch out for           }
{      any mistakes.                                                   }
{**********************************************************************}



UNIT DSPUnit;

INTERFACE

Uses Crt,Dos;

Const
     FinishDMATransferFlag  :Boolean = False;

     {Here are informations about the DMA Channel 0 - 7}
     { A)    Value = DMA_TargetAddr}
     { B)    Value = DMA_PageReg   }
     { C)    Value = DMA_ByteCount }

     DMAValues :Array [0..7,1..3] Of Byte =
     ( ($00,$87,$01),
       ($02,$83,$03),
       ($04,$81,$05),
       ($06,$82,$07),
       ($c0,$8f,$c1),
       ($c2,$8b,$c3),
       ($c4,$89,$c5),
       ($c6,$8a,$c7) );

Type
    PSample = ^Sample;
    Sample  = Record
      Data      :Pointer;    {Points to the actual data}
      Size      :Word;       {The size of the current block}
      MemOffset :Word;       {find the 20-bit address for the DMA}
      MemPage   :Byte;       {MemPage+MemOffset = 20-bit address}
      NextSam   :PSample;    {Pointer to next part of the sample}
    End;

Var
    Address,
    RealSize            :Word;
    Time_Constant       :Word;
    Freq                :Word;
    IRQ,Page            :Byte;
    IRQMask             :Byte;
    DMAMask             :Byte;
    SaveOldIRQ          :Pointer;
    BlockSample         :PSample;
    BrokenPart          :Boolean;

    DSP_RESET           :Word;
    DSP_READ_DATA       :Word;
    DSP_WRITE_DATA      :Word;
    DSP_WRITE_STATUS    :Word;
    DSP_DATA_AVAIL      :Word;

    DMA_TARGETADDR      :Byte;
    DMA_PAGEREG         :Byte;
    DMA_BYTECOUNT       :Byte;
    DMA_MASKSETRESET    :Byte;
    DMA_MODEREG1        :Byte;
    DMA_STATUSREG       :Byte;

    DMAWorking          :Boolean;
    LoopSample          :Boolean;
    SampleCopy          :PSample;
    FreqCopy            :Word;


{DeAllocate the previous reserved memory for the sample}
Procedure FreeSample(Var RSample :PSample);

{Loads a sample from the Disk}
Function LoadSample(Path :String;Var RSamples :PSample) :Byte;

{Calculate the DMA page and offset of one sample}
Procedure CalcSampleForDMA(RSamples :PSample);

{ ResetDSP returns true if reset was successful
  base should be 1 for base address 210h, 2 for 220h etc... }
function ResetDSP(base : word;IRQInt,DMA :Byte) : boolean;

Function ReadDSP : byte;

Procedure DeInitDSP;

{ Write DAC sets the speaker output level }
procedure WriteDAC(level : byte);

{ ReadDAC reads the microphone input level }
function ReadDAC : byte;

{ SpeakerOn connects the DAC to the speaker }

function SpeakerOn: byte;

{ SpeakerOff disconnects the DAC from the speaker,
  but does not affect the DAC operation }
function SpeakerOff: byte;

{ Functions to pause DMA playback }
procedure DMAStop;
procedure DMAContinue;

{ Playback plays a sample of a given size back at a given frequency
  using DMA channel 1.                                             }
Procedure Playback(RSample :PSample; frequency : word);

{Enables an IRQ}
Procedure EnableIrq;

{Disables an IRQ}
Procedure DisableIrq;

{Waits until the DMA transfer will be finished}
Procedure FinishDMATransfer;

Procedure StartPlaying;
Procedure StopPlaying;



IMPLEMENTATION

{************************************************************}
{Procedure FinishDMATransfer                                 }
{IT WORKS ONLY FOR THE DMA CHANNEL 1                         }
{************************************************************}

Procedure FinishDMATransfer;Assembler;
Asm;
     mov   cl,DMAMask
     mov   ah,1
     shl   ah,cl
     xor   dx,dx
     mov   dl,DMA_StatusReg
@L1: in    al,dx    {Get status}
     test  al,ah    {Check bit for DMA channel }
     jz    @L1     {Keep checking}
End;


{****************************************************************}
{Procedyre FreeSample                                            }
{A little piece of code that Deletes all blocks of any sample    }
{****************************************************************}

Procedure FreeSample(Var RSample :PSample);
Var
   TRSample     :PSample;
Begin
     IF RSample = Nil Then
        Exit;

     TRSample:=RSample;
     Repeat

       RSample:=TRSample;
       TRSample:=TRSample^.NextSam;
       IF RSample <> Nil Then
       Begin
          FreeMem(RSample^.Data,RSample^.Size);
          Dispose(RSample);
       End;

     Until (RSample=Nil);

     RSample:=Nil;
End;

{*******************************************************************}
{Function LoadSample                                                }
{A function that loads from the disk a sampled file with any size   }
{*******************************************************************}

Function LoadSample(Path :String;Var RSamples :PSample) :Byte;
Var
   F                    :File;      {File type}
   RFileSize            :Longint;   {The size}
   Readed               :Word;      {Bytes that have readed}
   Temp                 :Word;      {Temporary Var}
   InnerLoop            :Byte;      {How many Breaks will build the program}
   PrevSam,HeadSam      :PSample;   {Some pointers just for mess}
   Sound                :Pointer;
   MemOffset            :Word;      {Keep the 20-bit in these two variables}
   MemPage              :Byte;
   I                    :Byte;      {A classic Variable for Loops}
Begin
   {Initialize}

   PrevSam:=Nil;
   HeadSam:=Nil;

   {Start the process}

   Assign(F,Path);
   Reset(F,1);

   IF IOResult <> 0 Then
   Begin
      Writeln('Problem with the given file.I can''t open it.');
      Exit;
   End;

   RFileSize:=FileSize(F);

   {If the Sample is greater than 64k then break it in small pieces of shit}

   IF RFileSize > 64000 Then
   Begin
      Temp:=RFileSize div 64000;
      IF (RFileSize mod 64000) = 0 Then
         InnerLoop:=Temp
      Else
         InnerLoop:=Temp+1;

      For I:=1 to InnerLoop Do
      Begin
          New(RSamples);
          RSamples^.NextSam:=Nil;


          {Keep the start of the chain}

          IF HeadSam = Nil Then
             HeadSam:=RSamples;

          {Keep track of the address of every individual block}

          IF PrevSam <> Nil Then
             PrevSam^.NextSam:=RSamples;

          {If RFileSize is bigger than 64k then take a whole 64k part}
          {and subtract from the real size}

          IF RFileSize >= 64000 Then
          Begin
            RSamples^.Size:=64000;
            RFileSize:=RFileSize-64000;
          End
          Else
          Begin

          {Else take the remainer part and set the initial size equal to zero}

            RSamples^.Size:=RFileSize;
            RFileSize:=0;
          End;

          {Get mem for the current block}
          GetMem(RSamples^.Data,RSamples^.Size);


          {Calculate the Mem Offset and the Page to speed up the things}

          Sound:=RSamples^.Data;
          Asm;

          les si,Sound {Load the 32 bit address}
          mov ax,es

          rol  ax,1
          rol  ax,1
          rol  ax,1
          rol  ax,1

          mov  bl,al
          and  bl,0fh
          and  al,0f0h
          add  ax,si
          adc  bl,0

          mov  MemOffset,ax
          mov  MemPage,bl

          End;

          {Save them for later use}

          RSamples^.MemOffset:=MemOffset;
          RSamples^.MemPage:=MemPage;


          {Read from disk the proper size}
          BlockRead(F,RSamples^.Data^,RSamples^.Size,Readed);

          {IF and error was encountered then Free all Part-block Samples and Halt }

          IF Readed < RSamples^.Size Then
          Begin
             Writeln('Not all bytes were readed.An Error was occured');
             FreeSample(RSamples);
             Close(F);
             LoadSample:=1;
             Exit;
          End;



          PrevSam:=RSamples;
      End
   End
   Else

   {IF God bless you is smaller or even equal-Thanks God-with 64k then  }
   {just ask yourself why are you so lucky guy ? Just handle it as a    }
   {normal piece of shit.                                               }
   Begin

       New(RSamples);
       HeadSam:=RSamples;
       RSamples^.NextSam:=Nil;
       RSamples^.Size:=RFileSize;
       GetMem(RSamples^.Data,RSamples^.Size);

       {Calculate the Mem Offset and the Page to speed up the things}

       Sound:=RSamples^.Data;
       Asm;

       les si,Sound {Load the 32 bit address}
       mov ax,es

       rol  ax,1
       rol  ax,1
       rol  ax,1
       rol  ax,1

       mov  bl,al
       and  bl,0fh
       and  al,0f0h
       add  ax,si
       adc  bl,0

       mov  MemOffset,ax
       mov  MemPage,bl

       End;

       {Save them for later use}

       RSamples^.MemOffset:=MemOffset;
       RSamples^.MemPage:=MemPage;


       BlockRead(F,RSamples^.Data^,RSamples^.Size,Readed);

       {IF and error was encountered then Free all Part-Samples and Halt }

       IF Readed < RSamples^.Size Then
       Begin
          Writeln('Not all bytes were readed.An Error was occured');
          FreeSample(RSamples);
          Close(F);
          LoadSample:=1;
          Exit;
       End;

   End;

   Close(F);
   LoadSample:=0;
   RSamples:=HeadSam;
End;


{****************************************************************}
{Procedure CalcSampleForDMA                                      }
{****************************************************************}
Procedure CalcSampleForDMA(RSamples :PSample);
Var
   Sound                :Pointer;
   MemOffset            :Word;      {Keep the 20-bit in these two variables}
   MemPage              :Byte;
Begin
       Sound:=RSamples^.Data;
       Asm;
          les si,Sound {Load the 32 bit address}
          mov ax,es

          rol  ax,1
          rol  ax,1
          rol  ax,1
          rol  ax,1

          mov  bl,al
          and  bl,0fh
          and  al,0f0h
          add  ax,si
          adc  bl,0

          mov  MemOffset,ax
          mov  MemPage,bl
       End;
       {Save them for later use}

       RSamples^.MemOffset:=MemOffset;
       RSamples^.MemPage:=MemPage;
       RSamples^.NextSam:=Nil;
End;

Procedure EnableIRQ;Assembler;
Asm;
     in al,21h
     mov dx,21h
     mov ah,IRQMask
     not ah
     and al,ah
     out dx,al
End;


Procedure DisableIRQ;Assembler;
Asm;
     in al,21h
     mov dx,21h
     or al,IRQMask
     out dx,al
End;

Procedure DeInitDSP;
Var
   ReadByte      :Byte;
   Er            :Byte;
Begin
    StopPlaying;
    Er:=SpeakerOff;

    Port[DSP_RESET] := 1;
    Delay(100);
    Port[DSP_RESET] := 0;
    Delay(100);

    LoopSample:=False;
    SampleCopy:=Nil;
    FreqCopy:=0;

End;


Procedure WriteDSP2(value : byte);
Begin
  while Port[DSP_WRITE_STATUS] And $80 <> 0 do;
  Port[DSP_WRITE_DATA] := value;
End;

Procedure WriteDSP(Value :Byte);assembler;
Asm;
     mov dx,DSP_WRITE_STATUS
@L1: in  al,dx
     and al,80h
     jnz @L1
     mov al,Value
     out dx,al
End;

Function ReadDSP2 : byte;
Begin
  while Port[DSP_DATA_AVAIL] and $80 = 0 do;
  ReadDSP2 := Port[DSP_READ_DATA];
End;

Function ReadDSP :Byte;Assembler;
Asm;
     mov dx,DSP_DATA_AVAIL
@L1: in  al,dx
     and al,80h
     jz @L1
     mov dx,DSP_READ_DATA
     in  al,dx
End;


Procedure WriteDAC(level : byte);
Begin
  WriteDSP($10);
  WriteDSP(level);
End;

Function ReadDAC : byte;
Begin
  WriteDSP($20);
  ReadDAC := ReadDSP;
End;

Function SpeakerOn: byte;
Begin
  WriteDSP($D1);
End;

Function SpeakerOff: byte;
Begin
  WriteDSP($D3);
End;

Procedure DMAContinue;
Begin
  WriteDSP($D4);
End;

Procedure DMAStop;
Begin
  WriteDSP($D0);
End;



{**************************************************************}
{The most critical part is to set the DMA and take care all the}
{work that will be staring after we call the playback routine  }
{**************************************************************}


Procedure Dma_Transfer;
Var
   DMAPort      :Byte;
Begin
  DMAPort:=DMAMask or 4;
  Port[DMA_MaskSetReset] := DMAPort;       {Mask On (Disable) Channel 1}
  Port[$0C] := 0;       {Clear byte pointer Pointer (Flip-Flop)}
  Port[DMA_ModeReg1] := $49;         {Prepare DMA for READ access}
  Port[DMA_TargetAddr] := Lo(Address); {Send the Address}
  Port[DMA_TargetAddr] := Hi(Address);
  Port[DMA_PageReg] := Page;        {Send the Page}
  Port[DMA_ByteCount] := Lo(RealSize); {And finally send the Size of the imminent sample}
  Port[DMA_ByteCount] := Hi(RealSize);
  Port[DMA_MaskSetReset] := DMAMask;    {Mask Off (Enable) Channel 1}


  {Set the playback frequency }
  Time_constant := Round(256 - 1000000 div freq);
  WriteDSP($40);    {Send to DSP the Freq}
  WriteDSP(Lo(time_constant));


  {Set the playback type (8-bit) DMA}
  WriteDSP($14);
  WriteDSP(Lo(Realsize));
  WriteDSP(Hi(Realsize));
End;

Procedure SetNextBlock;
Var
   Size         :Word;
   DOfs         :Word;
   Sound        :Pointer;
   MemOffset    :Word;
   MemPage      :Byte;

Begin
   IF BlockSample = Nil Then
   Begin
      DMAWorking:=False;
      StopPlaying;
      Exit;
   End;


   Size := BlockSample^.Size - 2; {Real Size-2}

   IF BrokenPart=True Then
   Begin
       Asm;
           mov bx,RealSize
           mov cx,size
           sub cx,bx
           mov bl,Page
           inc bl
           xor ax,ax

           mov Address,ax
           mov Page,bl
           mov RealSize,cx
           mov BrokenPart,False
       End;
   End
   Else
   Begin
          {Load the precalculated values}

          MemOffset:=BlockSample^.MemOffset;
          MemPage:=BlockSample^.MemPage;

          Asm;

          mov ax,MemOffset
          mov Address,ax
          mov bl,MemPage
          mov Page,bl

          push ax


          {Until now we have computed 20-bit address and Page number}

          {Now it's time to make another baby step...}
          {Check to see if we have to break the DMA  }
          {process in two stages following the rule :}
          {IF Offset+Size > FFFF  Then break it.     }

          add  ax,size
          jnc  @One_Transfer


          pop  ax
          mov  cx,0ffffh
          sub  cx,ax


          mov RealSize,cx
          mov BrokenPart,True
          jmp @Finish

       @One_Transfer:

          pop ax         {Take back from stack our offset}
          mov cx,size

          mov RealSize,cx
          mov BrokenPart,False
       @Finish:

       End;
   End;


   DMA_Transfer;
   IF FinishDMATransferFlag = True Then
      FinishDMATransfer;

   IF BrokenPart = False Then
      BlockSample:=BlockSample^.NextSam;
End;

Procedure Playback(RSample :PSample; frequency : word);
Var
     Er           :Byte;
     DSeg,DOfs    :Word;
     Size         :Word;
     Sound        :Pointer;
Begin

  {If we have nothing to play then exit}

  IF (LoopSample=False) or (SampleCopy=Nil) Then
  Begin
      IF RSample = Nil Then
         Exit;

      SampleCopy:=RSample;
      FreqCopy:=Frequency;
      StartPlaying;
  End;

  DMAWorking:=True;
  BrokenPart:=False;
  BlockSample:=RSample;
  Freq:=Frequency;  {Set the global variable Freq}

  SetNextBlock;

  IF FinishDMATransferFlag = True Then
  Begin
     Repeat
     Until DMAWorking=False;
  End;

End;

{$F+}
Procedure NewIRQ(Flags, CS, IP, AX, BX, CX, DX, SI, DI, DS, ES, BP: Word);Interrupt;
Var
   ReadDSPIn    :Byte;
Begin
  ReadDSPIn:=Port[DSP_DATA_AVAIL];
  Port[$20]:=$20;
  SetNextBlock;
End;
{$F-}


Function ResetDSP(Base: Word;IRQInt,DMA :Byte) : Boolean;
Var
   Er   :Byte;
Begin
  Case IRQInt of
      2:IRQ:=$0A;
      3:IRQ:=$0B;
      5:IRQ:=$0D;
      7:IRQ:=$0F;
      Else
      Begin
         IRQ:=0;
         ResetDsp:=False;
         Exit;
      End;
  End;

  {Do this for the Procedures Enable-Disable IRQ}
  Asm;
    mov cl,IRQInt
    mov ah,1
    shl ah,cl
    mov IRQMask,ah
  End;

  DMAMask:=DMA;

  Case Base of
     $210:Base:=1;
     $220:Base:=2;
     $230:Base:=3;
     $240:Base:=4;
  End;

  Base:=Base * $10;

  { Calculate the port addresses }
  DSP_RESET := base + $206;
  DSP_READ_DATA := base + $20A;
  DSP_WRITE_DATA := base + $20C;
  DSP_WRITE_STATUS := base + $20C;
  DSP_DATA_AVAIL := base + $20E;

  { Reset the DSP, and give some nice long delays just to be safe }
  Port[DSP_RESET] := 1;
  Delay(10);
  Port[DSP_RESET] := 0;
  Delay(10);

  IF (Port[DSP_DATA_AVAIL] And $80 = $80) And
     (Port[DSP_READ_DATA] = $AA) then
  Begin

    IF DMAMask <= 3 Then
    Begin
       DMA_MaskSetReset:=$0A;
       DMA_ModeReg1:=$0B;
       DMA_StatusReg:=$08;
    End
    Else
    Begin
       DMA_MaskSetReset:=$CA;
       DMA_ModeReg1:=$CB;
       DMA_StatusReg:=$C8;
    End;

    DMA_TargetAddr:=DMAValues[DMAMask,1];
    DMA_PageReg:=DMAValues[DMAMask,2];
    DMA_ByteCount:=DMAValues[DMAMask,3];

    IF DMAMask > 3 Then
       DMAMask:=DMAMask - 4;

    Er:=SpeakerOn;
    ResetDSP:=True;
    DMAStop;
  End
  Else
    ResetDSP:=False;

End;

Procedure StopPlaying;
Begin
    IF LoopSample Then
    Begin
       DMAStop;
       Port[$20]:=$20;
       PlayBack(SampleCopy,FreqCopy);
       Exit;
    End;

    DMAStop;
    Port[DMA_MaskSetReset] :=DMAMask;       {Mask On (Disable) Channel 1}
    DisableIRQ;
    Port[$20]:=$20;
    SetIntVec(IRQ,SaveOldIRQ);

    LoopSample:=False;
    SampleCopy:=Nil;
    FreqCopy:=0;

End;

Procedure StartPlaying;
Var
   Er   :Byte;
Begin
    DisableIRQ;
    GetIntVec(IRQ,SaveOldIRQ);
    SetIntVec(IRQ,@NewIRQ);
    EnableIRQ;
End;

BEGIN
   LoopSample:=False;
   SampleCopy:=Nil;
   FreqCopy:=0;
END.
