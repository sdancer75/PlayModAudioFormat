{$G+}

Uses Crt,DspUnit;

Const
   NewMod31     :Boolean = True; {IF it's the newer mod with 31 instruments}
   Instruments  :Byte    = 31;
   NumOfPatterns:Byte    = 0;
   MaxSamples   :Byte    = 0;
   ComputerSpeed:Byte    = 6;
   HzTable      :Array [1..7] of Word =(8000,10000,12000,14000,16000,18000,22000);
   TestSpeed    :Word = 1375;
   MAXBUFFSIZE        = 7000;

  {********************************}
  { figures out the step for each  }
  { note that it plays- this number}
  { is divided by the FREQ of the  }
  { note.                          }
  {********************************}

   CountTbl     :Array [1..14] OF Word =
     ($0C780,  {8000 HZ 116640}
      $00001,
      $06C80,  {10000 HZ 93312}
      $00001,
      $02FC0,  {12000 HZ 77760}
      $00001,
      $0045B,  {14000 HZ 66651}
      $00001,
      $0E3D0,  {16000 HZ 58320}
      $00000,
      $0CA80,  {18000 HZ 51840}
      $00000,
      $0A5AE,  {22000 HZ 42414}
      $00000);


Type
   {Samples Structure}

   SampleStruc = Record
        SamName      :Array [1..22] of Char;   {sample name}
        SamLength    :Word;         {sample length - AMIGA's format}
        SamFineTune  :Byte;         {sample fine tune}
        SamVolume    :Byte;         {sample volume 0-64}
        SamRepeat    :Word;         {sample repeat - AMIGA's format}
        SamRepLen    :Word;         {sample repeat - length AMIGA's format}
   End;

   PSampleInfo = ^SampleInfo;
   SampleInfo  = Record
     Data      :Pointer;    {Points to the actual data}
     Size      :Word;       {The size of the current block}
     NextSam   :PSampleInfo;    {Pointer to next part of the sample}
   End;


Var
   Samples              :Array[1..31] of SampleStruc;
   NumOfSequences       :Byte; {Or SongLength - Range 1 to 128}
   RestartByte          :Byte; {Not Used}
   Sequences            :Array [0..127] of Byte; {Indicate the appropriate pattern}
                                         {to play at this given position}
   Patterns             :Pointer; {It contains all patterns 1024 bytes long each}
   SamplesData          :Array[1..31] of PSampleInfo; {Here where it is the actual}
                                      {samples Data}
   ModTitle             :Array [1..20] of Char;
   ModFile              :File;
   FilePath             :String;
   Hz                   :Word;
   SampleRate           :ShortInt;
   Count                :Array [1..2] Of Word;
   BufferSizeCHart      :Array [0..32] Of Word;
   EffectCmdAndXY       :Word;
   EffectCmd            :Byte;
   Frequency            :Word;
   SampleNum            :Word;
   DMABuffer1           :PSample;
   PrevCurTrak          :Word;
   CurSeg               :Array [0..3] Of PSampleInfo;

Const
   CurBuffSize          :Word = 0;
   NewBufferFlag        :Word = 0;
   NewBufferSize        :Word = 0;

   CurPattern           :Word = 0;
   CurNote              :Word = 0;
   CurSequence          :Word = 0;

   FreqVelocity         :Array [0..3] Of Word = (0,0,0,0);
   VolumeSlideFlag      :Array [0..3] Of Word = (0,0,0,0);
   VolumeSlideCount     :Array [0..3] Of Word = (0,0,0,0);
   VolumeSlideCountTemp :Array [0..3] Of Word = (0,0,0,0);

   CurTrak              :Array [0..3] Of Word = (0,0,0,0);
   CurByte              :Array [0..3] Of Word = (0,0,0,0);
   CurLeng              :Array [0..3] Of Word = (0,0,0,0);
   CurLoopLength        :Array [0..3] Of Word = (0,0,0,0);
   CurStartLoop         :Array [0..3] Of Word = (0,0,0,0);
   VolOverride          :Array [0..3] Of Word = (0,0,0,0);
   Special              :Array [0..3] Of Word = (0,0,0,0);

   Freq                 :Array [0..3] Of Word = ($100,$100,$100,$100);
   TempFreq             :Array [0..3] Of Word = ($100,$100,$100,$100);
   CurVolume            :Array [0..11] Of Byte =(64,64,64,64,64,64,64,64,64,64,64,64);
   Buffer1Size          :Word = 31000;
   TrakUpDateNum        :Byte = 0;
   WaitforfreqVel       :Word = 0;
   FreqWait             :Word = 0;



{**********************************************************************}
{Procedure Mod31OrMod15                                                }
{Determines if the file being loaded is The new one with 31 instruments}
{or an old one with 15 instruments.The rest informations are idedical. }
{Note :It's not working always ???                                     }
{**********************************************************************}
Function Mod31OrMod15(ModFilePath :String) :Integer;
Var
   IOR  :Integer;
   Sign :Array [1..4] of Char;
   Er   :Integer;
Begin
     Assign(ModFile,ModFilePath);
     Reset(ModFile,1);
     IOR:=IOResult;

     IF IOR<>0 Then
     Begin
         Mod31OrMod15:=IOR;
         Exit;
     End;

     Seek(ModFile,1080);

     BlockRead(ModFile,Sign,SizeOf(Sign),Er);
     IOR:=IOResult;

     IF IOR<>0 Then
     Begin
         Mod31OrMod15:=IOR;
         Exit;
     End;

     IF (Sign='M.K.') or (Sign='FLT4') or (Sign='FLT8') Then
        NewMod31:=True
     Else
        NewMod31:=False;

     Close(ModFile);
     Mod31OrMod15:=0;
End;

{****************************************************************}
{Procedyre FreeSample                                            }
{A little piece of code that Deletes all blocks of any sample    }
{****************************************************************}

Procedure FreeSampleStruc(RSample :PSampleInfo);
Var
   TRSample     :PSampleInfo;
Begin

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

End;


{**********************************************************************}
{Procedure LoadModFile                                                 }
{The actual loading process.It seperates the header from the whole body}
{and put each thing to the proper data positions.                      }
{**********************************************************************}
Function LoadModFile(ModFilePath :String) :Integer;
Var
   IOR                  :Integer;
   SampleLength         :LongInt;
   PrevSam,HeadSam      :PSampleInfo;   {Some pointers just for mess}
   FSample              :PSampleInfo;
   I,J                  :Byte;
   SamLength,SamRepeat,
   SamRepLen            :Word;
   Value,Temp           :Byte;
   InnerLoop            :Byte;
Begin
     IOR:=Mod31OrMod15(ModFilePath);
     IF IOR <> 0 Then
     Begin
         LoadModFile:=IOR;
         Exit;
     End;

     IF NewMod31 Then
        Instruments:=31
     Else
        Instruments:=15;

     Assign(ModFile,ModFilePath);
     Reset(ModFile,1);
     IOR:=IOResult;

     IF IOR<>0 Then
     Begin
         LoadModFile:=IOR;
         Exit;
     End;

     {Load Module Title}
     BlockRead(ModFile,ModTitle,$14,IOR);

     {Load Samples Structure}
     For I:=1 to Instruments do
     Begin
         BlockRead(ModFile,Samples[I],$1E,IOR);

         SamLength:=Samples[I].SamLength;
         SamRepeat:=Samples[I].SamRepeat;
         SamRepLen:=Samples[I].SamRepLen;

         {Reverse cos it is in AMIGA's Format}
         Asm;
            mov   ax,SamLength
            xchg  ah,al
            shl   ax,1
            mov   SamLength,ax

            mov   ax,SamRepeat
            xchg  ah,al
            shl   ax,1
            mov   SamRepeat,ax

            mov   ax,SamRepLen
            xchg  ah,al
            shl   ax,1
            mov   SamRepLen,ax
         End;

         Samples[I].SamLength:=SamLength;
         Samples[I].SamRepeat:=SamRepeat;
         Samples[I].SamRepLen:=SamRepLen;

     End;


     {Load Number of Sequences & Some other Infos}

     BlockRead(ModFile,NumOfSequences,1,IOR);
     BlockRead(ModFile,RestartByte,1,IOR);
     BlockRead(ModFile,Sequences,128,IOR);

     {Load patterns}
     Seek(ModFile,$043C);

     For I:=1 to NumOfSequences do
     Begin
         Value:=Sequences[I];
         IF NumOfPatterns < Value Then
            NumOfPatterns:=Value;
     End;

     Inc(NumOfPatterns);
     GetMem(Patterns,NumOfPatterns*1024);
     BlockRead(ModFile,Patterns^,NumOfPatterns*1024,IOR);

     {Load Actual Sample Data}

     For I:=1 to Instruments do
     Begin
         SampleLength:=Samples[I].SamLength;

         FSample:=Nil;
         HeadSam:=Nil;
         PrevSam:=Nil;

         IF SampleLength > 0 Then
         Begin

                Inc(MaxSamples);
                {If the Sample is greater than 64k then break it in small pieces of shit}

                IF SampleLength > 64000 Then
                Begin
                   Temp:=SampleLength div 64000;
                   IF (SampleLength mod 64000) = 0 Then
                      InnerLoop:=Temp
                   Else
                      InnerLoop:=Temp+1;

                   For J:=1 to InnerLoop Do
                   Begin
                       New(FSample);
                       FSample^.NextSam:=Nil;


                       {Keep the start of the chain}

                       IF HeadSam = Nil Then
                          HeadSam:=FSample;

                       {Keep track of the address of every individual block}

                       IF PrevSam <> Nil Then
                          PrevSam^.NextSam:=FSample;

                       {If SampleLength is bigger than 64k then take a whole 64k part}
                       {and subtract from the real size}

                       IF SampleLength >= 64000 Then
                       Begin
                         FSample^.Size:=64000;
                         SampleLength:=SampleLength-64000;
                       End
                       Else
                       Begin

                       {Else take the remainer part and set the initial size equal to zero}

                         FSample^.Size:=SampleLength;
                         SampleLength:=0;
                       End;

                       {Get mem for the current block}
                       GetMem(FSample^.Data,FSample^.Size);
                       BlockRead(ModFile,FSample^.Data^,FSample^.Size);
                       PrevSam:=FSample;
                   End;

                   SamplesData[I]:=HeadSam;
                End {If SampleLength > 64}
                Else
                Begin
                   New(FSample);
                   FSample^.Size:=SampleLength;
                   GetMem(FSample^.Data,FSample^.Size);
                   BlockRead(ModFile,FSample^.Data^,FSample^.Size);
                   FSample^.NextSam:=Nil;
                   SamplesData[I]:=FSample;
                End;
         End; {Sample > 0}
     End;   {For I}

     LoadModFile:=0;
     Close(ModFile);
End;


Procedure ShowModInfo;
Var
   I    :Integer;
Begin
      Writeln;
      Writeln('-----------------------------------------------------------------');
      Writeln('Mod Title =',ModTitle);
      Writeln('Max Samples =',MaxSamples);
      Writeln('Number Of patterns =',NumOfPatterns);
      Writeln('Number Of sequences =',NumOfSequences);
      Writeln('Restart Byte =',RestartByte);
      Writeln('New Mod file (31 Instruments) =',NewMod31);
      Writeln('Path =',FilePath);

      Writeln;
      For I:=1 to MaxSamples do
         Writeln(Samples[I].SamName :22,'  Len=',Samples[I].SamLength:6,
                 '  Tune=',Samples[I].SamFineTune:1,'  Vol=',Samples[I].SamVolume:2,
                 '  RepPoint=',Samples[I].SamRepeat:6,'  RepLen=',Samples[I].SamRepLen);

      Writeln;
      Writeln('-----------------------------------------------------------------');

End;

Procedure SelectHz;
Var
   WordT        :Word;
   I            :Byte;
Begin
    Hz:=HzTable[ComputerSpeed];
    FreqWait:=Round( (Hz*350) / 10000 );
    WordT:=((100*10000) div hz);
    Asm;
      mov ax,WordT
      neg al
      mov [SampleRate],al
    End;

    Count[1]:=CountTbl[(ComputerSpeed shl 1)+1];
    Count[2]:=CountTbl[(ComputerSpeed shl 1)+1+1];
    BufferSizeCHart[0]:=336;
    BufferSizeCHart[1]:=500;
    For I:=2 To 32 do
        BufferSizeCHart[I]:=Round((I*TestSpeed)/7);

    NewBufferSize:=Round((BufferSizeCHart[(6 shl 1)]*hz) / 1000);
End;

{*********************************************}
{EFFECT SLIDEUP                               }
{*********************************************}
Procedure cmSlideUp(TrackNum,XYCommand :Byte);
Begin
    FreqVelocity[TrackNum]:=Word(XYCommand);
End;

{*********************************************}
{EFFECT SLIDEDOWN                             }
{*********************************************}
Procedure cmSlideDown(TrackNum,XYCommand :Byte);
Begin
    FreqVelocity[TrackNum]:=Not Word(XYCommand);
End;

{*********************************************}
{EFFECT VOLSLIDE                              }
{*********************************************}
Procedure cmVolSlide(TrackNum,XYCommand :Byte);
Begin
   IF (XYCommand and $F0) <> 0 Then
   Begin
      XYCommand:=XYCommand shr 4;
      VolumeSlideFlag[TrackNum]:=1;
   End
   Else
      VolumeSlideFlag[TrackNum]:=$FFFF;

   XYCommand:=XYCommand and $0F;
   XYCommand:=XYCommand xor $0F;
   Inc(XYCommand);
   VolumeSlideCount[TrackNum]:=XYCommand shl 4;
End;

{*********************************************}
{EFFECT SETSEED                               }
{*********************************************}
Procedure cmSetSpeed(TrackNum,XYCommand :Byte);
Begin
    IF XYCommand > $1F Then
       Exit;

    NewBufferSize:=Round( (BufferSizeCHart[XYCommand]*Hz) /10000 );
End;

{*********************************************}
{EFFECT VOLUMESet                             }
{*********************************************}
Procedure cmVolumeSet(TrackNum,XYCommand :Byte);
Begin
    IF XYCommand = 0 Then
    Begin
       CurVolume[TrackNum]:=XYCommand;
       VolOverride[TrackNum]:=1;
    End
    Else
    Begin
       CurVolume[TrackNum]:=(XYCommand-1) and $3F;
       VolOverride[TrackNum]:=1;
    End;
End;


{*********************************************}
{EFFECT JUMP                                  }
{*********************************************}
Procedure cmJump(TrackNum,XYCommand :Byte);
Begin
    CurNote:=0;
    CurPattern:=Sequences[XYCommand];
End;

{*********************************************}
{EFFECT BREAK                                 }
{*********************************************}
Procedure cmBreak(TrackNum,XYCommand :Byte);
Begin
     CurNote:=64;
End;


{****************************************************}
{Procedure ReadNotes                                 }
{****************************************************}
Procedure ReadNotes;
Var
   _Bx            :Word;
   PatSeg,PatOfs  :Word;
   _Si,_Bp        :Word;
   XYCommand      :Byte;
Begin
    IF NewBufferFlag=2 Then
    Begin
        NewBufferFlag:=0;
        NewBufferSize:=0;
    End;

    For _Bx:=0 To 3 do
    Begin
      FreqVelocity[_Bx]:=0;
      VolumeSlideFlag[_Bx]:=0;
      VolumeSlideCount[_Bx]:=600;
    End;

    _Si:=(CurPattern shl 10)+(CurNote shl 4);

    PatSeg:=Seg(Patterns^);
    PatOfs:=Ofs(Patterns^);

{****************************************************************}
{Info for each note:                                             }
{                                                                }
{ _____byte 1_____   byte2_    _____byte 3_____   byte4_         }
{/                \ /      \  /                \ /      \        }
{0000          0000-00000000  0000          0000-00000000        }
{Upper four    12 bits for    Lower four    Effect command.      }
{bits of sam-  note period.   bits of sam-                       }
{ple number.                  ple number.                        }
{****************************************************************}
    Asm;
       push ds
       mov si,PatOfs
       add si,_si
       mov ax,PatSeg
       mov ds,ax
       cld
    End;

    For _Bp:=0 to 3 do
    Begin
       Asm;
	  lodsb           {;al=high nybble for inst/ low nybble for high freq}
	  mov     dh,al
	  lodsb           {;al=byte for freq}
	  mov     dl,al   {;dx holds freq}
	  lodsb           {;high nybble for low inst/ low nybble  command}
	  mov     cl,al   {;cl=al}
	  xor     ch,ch   {;ch=0}
	  shr     cx,4    {;clears effect nibble,so cx=low nibble of sample num}
	  mov     ah,cl   {;ah=cl=low nibble of sample number}
	  mov     ch,al   {;ch=al 3th byte}
	  lodsb           {;xy for command,the last byte (no 4)}
	  mov     cl,al   {;cl=effect byte}
	  push    cx      {;save cx=3th and 4th byte (effects) with the lo sample}
                          {;num in the first nibble (Right most) of the cx}
	  mov     al,dh   {;al=first byte (1 nibble=samnum,2 nibble=freq)}
	  and     al,11110000b  {;Keep only sample num}
	  or      al,ah   {;AL=chain the hi and lo nibble of the sample number}
	  xor     ah,ah   {;clear ah}
          {*************** Ax Holds the Sample Number *************}
          mov     SampleNum,ax
  @dontstoreinst:
	  mov     al,dh   {;dh=first byte (1 nibble=samnum,2 nibble=freq)}
	  and     dh,01111b {;Clear the 1st nibble = sample num}
          {************** Cx & Dx Holds the Frequency 12-Bit ************}
	  mov     cx,dx {;dl=already holds the low 8-bit freaq+dh (4-Bit) = 12bit}
	  cmp     cx,5 {;If effect no 5 then dont do the frequency}
	  jbe     @Dontdofreq
          push    bx
          push    ds
          mov     bx,Seg @Data
          mov     ds,bx
          mov     bx,Offset Count
	  mov     ax,ds:[bx]
	  mov     dx,ds:[bx+2]
          pop     ds
          pop     bx
	  div     cx
          mov     Frequency,ax
  @dontdofreq:
	  mov     ax,bx
	  pop     cx {;3th and the 4th byte}
	  and     ch,1111b {;Now clear the upper nibble = lo nibble of sample num}
          {**************** Cx Holds the 12-bit effect command *********}
          mov     EffectCmdAndXY,cx
          mov     EffectCmd,ch
          mov     XYCommand,cl
       End;

       CurTrak[_Bp]:=SampleNum;
       Freq[_Bp]:=Frequency;
       VolOverride[_Bp]:=0;

       {*********** Call Effect commands *********}
       Case EffectCmd Of
          1:cmSlideUp(_Bp,XYCommand);
          2:cmSlideDown(_Bp,XYCommand);
         10:cmVolSlide(_Bp,XYCommand);
         11:cmJUMP(_Bp,XYCommand);
         12:cmVOLUMESET(_Bp,XYCommand);
         13:cmBREAK(_Bp,XYCommand);
         15:cmSetSpeed(_Bp,XYCommand);
       End;

   End;

   Asm;
      pop ds
   End;
End;

Procedure UpDate;
Var
   _Bp          :Byte;
   Imul         :Integer;
   SamSeg,SamOfs,
   DMASeg,DMAOfs:Word;
   I            :Word;
   TByte        :Byte;
Begin

   IF NewBufferSize<>0 Then
   Begin
      Buffer1Size:=NewBufferSize;
      Inc(NewBufferFlag);
   End;

   CurBuffSize:=Buffer1Size;
   DMASeg:=Seg(DMABuffer1^.Data^);
   DMAOfs:=Ofs(DMABuffer1^.Data^);

   {Clear DMABuffer with 128's}
   Asm;
     mov ax,DMASeg
     mov es,ax
     mov di,DMAOfs
     mov ax,8080h
     mov cx,[CurBuffSize]
     shr cx,1
     jnc @NoStosb
     stosb
   @NoStosb:
     rep stosw
   End;

   For _Bp:=3 downTo 0 do
   Begin
        IF (CurTrak[_Bp] = 0) and (_Bp=0) Then
        Begin
           Inc(CurNote);
           IF CurNote >= 64 Then
           Begin
               CurNote:=0;
               Inc(CurSequence);
               IF CurSequence > NumOfSequences Then
                  CurSequence:=0;
               CurPattern:=Sequences[CurSequence];
           End;
           ReadNotes;
        End
        Else
        IF (CurTrak[_Bp] = 0) and (_Bp<>0) Then
        {Track Not Empty}
        Begin
           Inc(TrakUpDateNum);

           {Track No continue}
           IF Hi(CurTrak[_Bp]) = 0 Then
           Begin
              WaitForFreqVel:=FreqWait;
              PrevCurTrak:=CurTrak[_Bp];
              CurTrak[_Bp]:=(Lo(CurTrak[_Bp]) shl 8)+Lo(CurTrak[_Bp]);
              CurSeg[_Bp]:=SamplesData[PrevCurTrak];
              CurLeng[_Bp]:=Samples[PrevCurTrak].SamLength;
              CurByte[_Bp]:=0;

              IF VolOverride[_Bp] = 0 Then
                CurVolume[_Bp]:=(Samples[PrevCurTrak].SamVolume-1) and $3F;

              Special[_Bp]:=0;
              IF Samples[PrevCurTrak].SamRepeat >= 10 Then
              Begin
                  CurLoopLength[_Bp]:=Samples[PrevCurTrak].SamRepeat;
                  CurStartLoop[_Bp]:=Samples[PrevCurTrak].SamRepLen;
                  Special[_Bp]:=1;
              End;
           End;


           SamSeg:=Seg(CurSeg[_Bp]^.Data^);
           SamOfs:=Ofs(CurSeg[_Bp]^.Data^)+CurByte[_Bp];

           DMASeg:=Seg(DMABuffer1^.Data^);
           DMAOfs:=Ofs(DMABuffer1^.Data^);
           I:=0;

           While (I<CurBuffSize) and (SamOfs < CurLeng[_Bp]) and (Special[_Bp] = 1) do
           Begin
                While (I<CurBuffSize) and (SamOfs < CurLeng[_Bp]) do
                Begin
                    TByte:=Mem[SamSeg:SamOfs];
                    Imul:=CurVolume[_Bp] * TByte;
                    TByte:=Mem[DMASeg:DMAOfs];
                    TByte:=TByte+Hi(Imul);
                    Inc(DMAOfs);
                    Inc(I);


                    IF WaitForFreqVel = 0 Then
                    Begin
                        WaitForFreqVel:=FreqWait;
                        Freq[_Bp]:=Freq[_Bp]+FreqVelocity[_Bp];
                    End;

                    TByte:=Hi(TempFreq[_Bp]+Freq[_Bp]);
                    SamOfs:=SamOfs+TByte;

                    TempFreq[_Bp]:=Lo(TempFreq[_Bp]+Freq[_Bp]);

                End;

                {Repeat loop}
                IF Special[_Bp] = 1 Then
                Begin
                  SamOfs:=Ofs(CurSeg[_Bp]^.Data^)+CurStartLoop[_Bp];
                  IF (CurLoopLength[_Bp]+CurStartLoop[_Bp]) < CurLeng[_Bp] Then
                     CurLeng[_Bp]:=CurLoopLength[_Bp]+CurStartLoop[_Bp];
                End
                Else
                IF Special[_Bp] = 0 Then
                   CurTrak[_Bp]:=0;
           End;{While}

           CurByte[_Bp]:=SamOfs;
        End; {If}

   End;{For}

End;

Procedure Init;
Var
   I    :Word;
Begin
   New(DMABuffer1);
   GetMem(DMABuffer1^.Data,MAXBUFFSIZE);
   DMABuffer1^.Size:=MAXBUFFSIZE;
   DMABuffer1^.NextSam:=Nil;
   CalcSampleForDma(DMABuffer1);
End;

Var
   Er           :Integer;
   DspEr        :Boolean;
   I            :Byte;
Begin
   TextColor(7);
   TextBackGround(0);
   ClrScr;
   Writeln;
   Writeln('Mod Player ver 1.00');
   Writeln;
   Init;

   IF ParamCount < 1 Then
   Begin
       Writeln('No parametres ? Sorry but no *.Mod file');
       halt(0);
   End;

   FilePath:=ParamStr(1);

   Er:=LoadModFile(FilePath);
   IF Er<>0 Then
   Begin
       For I:=1 to Instruments do
           FreeSampleStruc(SamplesData[I]);
       Writeln('Something wrong !!!');
   End
   Else
   Begin
      ShowModInfo;
      SelectHz;
      DspEr:=ResetDsp(2,5);
      IF DspEr=False Then
      Begin
          Writeln('Error while initializing the DSP');
          For I:=1 to MaxSamples do
              FreeSampleStruc(SamplesData[I]);
          Halt(0)
      End;
      Writeln('Now Playing !!!!!');

      CurNote:=0;
      CurPattern:=Sequences[CurSequence];
      ReadNotes;
      PlayBack(DMABuffer1,18000);
   End;

End.