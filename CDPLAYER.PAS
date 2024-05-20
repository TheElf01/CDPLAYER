{$N-,E-,G+,X-,D+,B-,S-,R-}

Const Multiplexer   = $2f;
      Maus          = $33;

      ReadLocation  = 1;
      ReadCommand   = 3;
      ReadCDInfo    = 10;
      ReadTrackInfo = 11;
      ReadCDUPCode  = 14;
      StartPlaying  = 132;
      StopPlaying   = 133;
      ResumePlaying = 136;

      Window1       : Array[1..6] of Byte = (201,205,187,186,200,188);
      Window2       : Array[1..6] of Byte = (218,196,191,179,192,217);

      StarCount     = 150;

      SpeedColors   : Array[1..3] of Byte = (8, 7, 15);

      PlayTypes     : Array[1..4] of String = ('Single Track ',
                                               'Track Loop   ',
                                               'Single CD    ',
                                               'CD Loop      ');

Type  CDRequestHeader = Record
                         Length  : Byte;
                         SubUnit : Byte;
                         Command : Byte;
                         Status  : Word;
                         Dummy   : Array[1..4] of Word;
                        end;

      CDPlayHeader    = Record
                         CDRH           : CDRequestHeader;
                         AddressingMode : Byte;
                         StartSector    : Longint;
                         SectorCount    : Longint;
                        end;

      CDReadInfos     = Record
                         CDRH            : CDRequestHeader;
                         MDescriptor     : Byte;
                         CBA             : Pointer;
                         CBS             : Word;
                         StartSectorNr   : Word;
                         VolumeID        : Pointer;
                        end;

      CDTrackInfos    = Record
                         CBC            : Byte;
                         TrackNr        : Byte;
                         StartPoint     : Longint;
                         TrackCheckInfo : Byte;
                        end;

      CDDiscInfos     = Record
                         CBC     : Byte;
                         LTrack  : Byte;
                         HTrack  : Byte;
                         LeadOut : Longint;
                        end;

      CDHeadLocation  = Record
                         CBC              : Byte;
                         AdressingMode    : Byte;
                         Location         : Longint;
                        End;

      Palette         = Array[0..16,1..3] of byte;

      Star            = Record
                         x, y  : Byte;
                         Speed : Byte;
                        end;

var MSCDEX             : Record
                          Installed  : Boolean;
                          Drives     : Word;
                          DriveChars : Array[1..26]of Byte;
                          Version    : Array[1..2] of Byte;
                         end;

    ActualCD           : CDDiscInfos;

    ActualTrack        : Record
                          TNr   : Byte;
                          Start : Longint;
                          Ende  : Longint;
                         end;

    PlayType           : Byte;
    ActualDrive        : Byte;
    CDPosition         : Byte;
    TrackPosition      : Byte;
    Cursor_X, Cursor_Y : Byte;
    FGColor, BGColor   : Byte;
    TMausByte          : Byte;
    AnimateTimer       : Byte;
    MausX, MausY, Bttn : Word;
    MainCounter        : Word;
    OMX, OMY           : Word;
    LineOfCode         : Longint;
    ActualLocation     : Longint;
    Pusher             : integer;
    TempStr1, TempStr2 : String;
    CDCode             : String;
    Finish             : Boolean;
    Playing            : Boolean;
    ResumeReady        : Boolean;
    LoopOn             : Boolean;
    CodeFile           : Text;
    MyPal              : Palette;
    StarField          : Array[1..StarCount] of Star;

{ MSCDEX ******************************************************** }

Procedure InitMSCDEX; Assembler;
asm
 mov  ax, 1500h
 int  Multiplexer
 mov  MSCDEX.Installed, 0
 or   bx, bx
 jz   @ende
 mov  mscdex.Installed, 1
 mov  mscdex.drives, bx
 mov  word ptr mscdex.DriveChars, cx
 mov  ax, 150ch
 not  bx
 int  Multiplexer
 or   bx, bx
 jz   @MSCDEX100
 xchg bl, bh
 mov  MSCDEX.Version, bx
 mov  ax, seg MSCDEX.DriveChars
 mov  es, ax
 mov  bx, offset MSCDEX.DriveChars
 mov  ax, 150dh
 int  Multiplexer
 jmp  @Ende
@MSCDEX100:
 mov  MSCDEX.Version, 100h
@ende:
end;

Procedure SendRequest(Drive : Word; Var Request); Assembler;
asm
 push bp
 mov  ax, 1510h
 mov  cx, Drive
 les  bx, Request
 int  Multiplexer
 pop  bp
end;

{ Funktionen des Players ******************************************* }

Procedure PlayCDFrames(Drive : Word; FFrame, LFrame : Longint);
 Var PlayRequest : CDPlayHeader;
begin
 PlayRequest.CDRH.Length    := 13;
 PlayRequest.CDRH.SubUnit   := Drive;
 PlayRequest.CDRH.Command   := StartPlaying;
 PlayRequest.CDRH.Status    := 0;
 PlayRequest.AddressingMode := 0;
 PlayRequest.StartSector    := FFrame;
 PlayRequest.SectorCount    := LFrame;
 SendRequest(Drive, PlayRequest);
 Playing := True;
end;

Procedure StopOrPausePlayingCD(Drive : Word);
 Var StopRequest : CDRequestHeader;
begin
 StopRequest.Length  := 13;
 StopRequest.SubUnit := Drive;
 StopRequest.Command := StopPlaying;
 StopRequest.Status  := 0;
 SendRequest(Drive, StopRequest);
 Playing := False;
end;

Procedure ResumePlayingCD(Drive : Word);
 var ResumeRequest : CDRequestHeader;
begin
 ResumeRequest.Length  := 13;
 ResumeRequest.SubUnit := Drive;
 ResumeRequest.Command := ResumePlaying;
 ResumeRequest.Status  := 0;
 SendRequest(Drive, ResumeRequest);
 Playing := True;
end;

Procedure GetCDInfo(Drive : Word);
 var RequestBuffer : CDReadInfos;
Begin
 ActualCD.CBC                := 10;
 RequestBuffer.CDRH.Length   := sizeof( CDRequestHeader );
 RequestBuffer.CDRH.SubUnit  := Drive;
 RequestBuffer.CDRH.Command  := ReadCommand;
 RequestBuffer.CDRH.Status   := 0;
 RequestBuffer.MDescriptor   := 0;
 RequestBuffer.CBA           := @ActualCD;
 RequestBuffer.CBS           := SizeOf(ActualCD);
 RequestBuffer.StartSectorNr := 0;
 RequestBuffer.VolumeID      := NIL;
 SendRequest(Drive, RequestBuffer.CDRH);
End;

Procedure GetTrackInfo(Drive : Word; Track : Word);
 var TrackInfoBuffer : CdTrackInfos;
Procedure GInfo;
 var RequestBuffer : CDReadInfos;
Begin
 TrackInfoBuffer.CBC         := ReadTrackInfo;
 TrackInfoBuffer.TrackNr     := Track;
 RequestBuffer.CDRH.Length   := sizeof( CDRequestHeader );
 RequestBuffer.CDRH.SubUnit  := Drive;
 RequestBuffer.CDRH.Command  := ReadCommand;
 RequestBuffer.MDescriptor   := 0;
 RequestBuffer.CBA           := @TrackInfoBuffer;
 RequestBuffer.CBS           := SizeOf(TrackInfoBuffer);
 RequestBuffer.StartSectorNR := 0;
 RequestBuffer.VolumeID      := NIL;
 SendRequest(Drive, RequestBuffer.CDRH);
End;
begin
 If Track <> ActualCD.HTrack then
    begin
     ActualTrack.TNr   := Track;
     Ginfo;
     ActualTrack.Start := TrackInfoBuffer.StartPoint - 362;
     Inc(Track);
     Ginfo;
     ActualTrack.Ende  := TrackInfoBuffer.StartPoint - ActualTrack.Start
                                                     - 220;
    end
   else
    begin
     ActualTrack.TNr   := Track;
     Ginfo;
     ActualTrack.Start := TrackInfoBuffer.StartPoint - 362;
     ActualTrack.Ende  := ActualCD.LeadOut;
    end;
end;

Procedure GetCDLocation(Drive : Word);
 var PRequest : CDHeadLocation;
     RequestBuffer : CDReadInfos;
Begin
 PRequest.CBC                := ReadLocation;
 PRequest.AdressingMode      := 1;
 RequestBuffer.CDRH.Length   := sizeof( CDRequestHeader );
 RequestBuffer.CDRH.SubUnit  := Drive;
 RequestBuffer.CDRH.Command  := ReadCommand;
 RequestBuffer.MDescriptor   := 0;
 RequestBuffer.CBA           := @PRequest;
 RequestBuffer.CBS           := SizeOf(PRequest);
 RequestBuffer.StartSectorNR := 0;
 RequestBuffer.VolumeID      := NIL;
 SendRequest(Drive, RequestBuffer.CDRH);
 ActualLocation := PRequest.Location;
End;

Function CDInserted : boolean;
begin
 ActualCD.LeadOut := 0;
 GetCDInfo(ActualDrive);
 If ActualCD.LeadOut < 150 then CDInserted:=False else CDInserted := True;
end;

{ Zeit-Umrechnungen ****************************************************** }

Procedure RedBook2Time(RBTime : Longint; Var Min, Sec, Frame : Word);
begin
 Frame  := Word(RBTime       ) and $00FF;
 Sec    := Word(RBTime shr  8) and $00FF;
 Min    := Word(RBTime shr 16) and $00FF;
 If Min <> 0 then
    begin
     if Sec < 2 then Dec(Min);
     if Sec = 0 then Sec := 60;
     if Sec = 1 then Sec := 61;
     Sec := Sec - 2;
    end else
     If (Min = 0) and (Sec = 1) then Sec := Sec - 1 else Sec := Sec - 2;
end;

Function RedBook2HSG(RedBook : Longint) : Longint;
 var Min, Sec, Frame : Word;
Begin
 Frame := Word(RedBook       ) and $00FF;
 Sec   := Word(RedBook shr  8) and $00FF;
 Min   := Word(RedBook shr 16) and $00FF;
 REDBOOK2HSG := Min * LongInt(4500) + Sec * LongInt(75) + Frame - 150;
End;

{ CRT-Ersatz ************************************************************ }

Procedure SetStandardTextMode; Assembler;
asm
 mov  ax, 3
 int  10h
end;

Procedure SetSpecialTextMode; Assembler;
asm
 mov  ax, 3
 int  10h
 mov  ax, 1102h
 mov  bl, 0
 int  10h
 mov  dx, 03d4h
 mov  al, 9h
 out  dx, al
 inc  dx
 in   al, dx
 and  al, 0e0h
 or   al, 07h
 out  dx, al
 mov  dx, 03d4h
 mov  ax, 9012h
 out  dx, ax
end;

Procedure SetBorder(Color : Word); Assembler;
asm
 mov  ax, 0b00h
 mov  bx, Color
 int  10h
end;

Procedure WriteChar(Zeichen : byte);
 Var ColorByte : Byte;
begin
 ColorByte := Lo(BGColor) shl 4 + lo(FGColor);
 Mem[$B800:(Cursor_Y shl 6 + Cursor_y shl 4 + Cursor_x)*2+1]:=ColorByte;
 Mem[$B800:(Cursor_Y shl 6 + Cursor_y shl 4 + Cursor_x)*2]:=Zeichen;
 inc(Cursor_x);
 If Cursor_x = 80 then begin Cursor_x:=0; Inc(Cursor_y); end;
 if Cursor_y > 49 then Cursor_y := 0;
end;

Procedure MyWriteln(Satz : String);
 var TempBg  : Byte;
     Counter : Word;
begin
 TempBg := BgColor;
 for counter := 1 to length(Satz) do
     begin
      BgColor:=TempBg;
      if (cursor_x = MausX) and (Cursor_y = MausY) then
         BGColor:=Mem[$B800:(Cursor_Y shl 6+
                      Cursor_y shl 4+Cursor_x)*2+1] or 2;
      WriteChar(ord(Satz[counter]));
     end;
 if cursor_x <> 0 then
    begin
     inc(Cursor_y);
     Cursor_x := 0;
     if Cursor_y > 49 then Cursor_y := 0;
    end;
end;


Procedure Gotoxy(x,y : Byte);
begin
 Cursor_x := x; Cursor_y := y;
end;

Function KeyPressed : boolean;
Inline($B4/$0B/$CD/$21/$24/$FE);

Function ReadKey : Byte; Assembler;
asm
 mov  ah, 8
 int  21h
end;

Procedure Input(Var InOut : String; InLength : Byte);
 var EnteredKey : Byte;
     Laenge     : Byte;
begin
 InOut  := '';
 Laenge := 0;
 repeat
  repeat until keypressed;
  EnteredKey := ReadKey;
  If EnteredKey <> 0 then
     begin
      If (EnteredKey <> 9) and (EnteredKey <> 27) and
         (EnteredKey <> 13) then
         begin
          If EnteredKey = 8 then
             begin
              If Ord(InOut[0])-1 >= 0 then
                 begin
                  InOut[0] := Chr(Ord(InOut[0]) - 1);
                  Gotoxy(Cursor_X-1,Cursor_Y);
                  WriteChar(0);
                  Gotoxy(Cursor_X-1,Cursor_Y);
                  Dec(Laenge);
                 end;
             end
            else
             begin
              InOut[0] := Chr(Ord(InOut[0]) + 1);
              InOut[Ord(InOut[0])] := Chr(EnteredKey);
              WriteChar(EnteredKey);
              Inc(Laenge);
             end;
         end;
     end
   else EnteredKey := ReadKey;
 until (EnteredKey = 13) or (Laenge = InLength-1);
end;

Procedure DrawWindow(Typ : Byte; x1, y1, x2, y2 : Byte; FG, BC : Byte);
 var Counter, Counter2 : Byte;
begin
 FGColor := FG;
 BGColor := BC;
 gotoxy(x1, y1);
 Case Typ of 1 : begin
                  WriteChar(Window1[1]);
                  for Counter := x1 to x2 - 2 do WriteChar(Window1[2]);
                  WriteChar(Window1[3]);
                  for Counter := y1 to y2 - 2 do
                      begin
                       Gotoxy(x1, Counter + 1);
                       WriteChar(Window1[4]);
                       for Counter2 := x1 to x2 - 2 do WriteChar(0);
                       WriteChar(Window1[4]);
                      end;
                  Gotoxy(x1, y2);
                  WriteChar(Window1[5]);
                  for Counter := x1 to x2 - 2 do WriteChar(Window1[2]);
                  WriteChar(Window1[6]);
                 end;
             2 : begin
                  WriteChar(Window2[1]);
                  for Counter := x1 to x2 - 2 do WriteChar(Window2[2]);
                  WriteChar(Window2[3]);
                  for Counter := y1 to y2 - 2 do
                      begin
                       Gotoxy(x1, Counter + 1);
                       WriteChar(Window2[4]);
                       for Counter2 := x1 to x2 - 2 do WriteChar(0);
                       WriteChar(Window2[4]);
                      end;
                  Gotoxy(x1, y2);
                  WriteChar(Window2[5]);
                  for Counter := x1 to x2 - 2 do WriteChar(Window2[2]);
                  WriteChar(Window2[6]);
                 end;
      end;
end;

Procedure DrawBlk(x, y1, y2 : Byte);
 var Counter : Word;
begin
 Gotoxy(x,y1);
 WriteChar(30);
 Gotoxy(x,y2);
 WriteChar(31);
 for Counter := y1+1 to y2-1 do
     begin
      gotoxy(x, Counter);
      WriteChar(177);
     end;
end;

Procedure WrapLine(x, y, length : Byte);
 var Counter : Word;
begin
 gotoxy(x,y);
 WriteChar(195);
 For Counter := 1 to length do WriteChar(196);
 WriteChar(180);
end;

Procedure ActualizeStatus;
 var Min , Sec , Frame  : Word;
     Min2, Sec2, Frame2 : Word;
     TempTime           : longint;
begin
 TempStr1 := '';
 TempStr2 := '';
 Gotoxy(59,17); FgColor := 13; BgColor := 5; MyWriteln(PlayTypes[PlayType]);
 If Playing or ResumeReady then
    begin
     If ActualTrack.Tnr = ActualCD.Htrack then
         If ActualLocation > ActualTrack.Ende - 100 then
            begin
             If LoopOn and (PlayType = 4) then
                begin
                 bgColor:=5; fgColor:=13;
                 Gotoxy(9,22);
                 MyWriteln('                  ');
                 GetTrackInfo(ActualDrive, 1);
                 ActualLocation := 0;
                end;
             Playing := False;
             Exit;
            end;
         If (ActualLocation > ActualTrack.Ende + ActualTrack.Start + 200)
            and (ActualTrack.Tnr <> ActualCD.HTrack) then
           begin
            if LoopOn and (PlayType = 2) then
               begin
                bgColor:=5; fgColor:=13;
                Gotoxy(9,22);
                MyWriteln('                  ');
                Playing := False;
                exit;
               end;
            inc(ActualTrack.Tnr);
            GetTrackInfo(ActualDrive, ActualTrack.TNr);
           end;
     RedBook2Time(ActualLocation, Min, Sec, Frame);
     TempTime := (Min * 60 + Sec) - (Min2 * 60 + Sec2);
     RedBook2Time(ActualTrack.start+362, Min2, Sec2, Frame2);
     TempTime := (Min * 60 + Sec) - (Min2 * 60 + Sec2);
     Min2 := TempTime div 60;
     Sec2 := TempTime mod 60;
     Str(Min, TempStr1);
     If TempStr1[0] = Chr(1) then
        begin
         TempStr1[0] := Chr(2);
         TempStr1[2] := TempStr1[1];
         TempStr1[1] := '0';
        end;
     If Ord(TempStr1[0]) > 2 then TempStr1[0] := Chr(2);
     Tempstr2 := Tempstr1+':';
     Str(Sec, TempStr1);
     If TempStr1[0] = Chr(1) then
        begin
         TempStr1[0] := Chr(2);
         TempStr1[2] := TempStr1[1];
         TempStr1[1] := '0';
        end;
     If Ord(TempStr1[0]) > 2 then TempStr1[0] := Chr(2);
     Tempstr2 := TempStr2 + Tempstr1;
     str(ActualTrack.TNr, TempStr1);
     bgColor:=5; fgColor:=13;
     Gotoxy(6,17);
     If TempStr1[0] = Chr(1) then
        begin
         TempStr1[0] := Chr(2);
         TempStr1[2] := TempStr1[1];
         TempStr1[1] := '0';
        end;
     MyWriteln('T'+Tempstr1+':');
     Gotoxy(17,17);
     bgColor:=5; fgColor:=13;
     If Playing then MyWriteln(TempStr2) else
        If not ResumeReady then MyWriteln(TempStr2);
     Str(Min2, TempStr1);
     If TempStr1[0] = Chr(1) then
        begin
         TempStr1[0] := Chr(2);
         TempStr1[2] := TempStr1[1];
         TempStr1[1] := '0';
        end;
     If Ord(TempStr1[0]) > 2 then TempStr1[0] := Chr(2);
     Tempstr2 := Tempstr1+':';
     Str(Sec2, TempStr1);
     If TempStr1[0] = Chr(1) then
        begin
         TempStr1[0] := Chr(2);
         TempStr1[2] := TempStr1[1];
         TempStr1[1] := '0';
        end;
     If Ord(TempStr1[0]) > 2 then TempStr1[0] := Chr(2);
     Tempstr2 := TempStr2 + Tempstr1;
     bgColor:=5; fgColor:=13;
     Gotoxy(11,17);
     MyWriteln(TempStr2+'/');
    end else
    begin
     bgColor:=5; fgColor:=13;
     Gotoxy(6,17);
     MyWriteln('                  ');
    end;
end;

{ Effekte ************************************************************** }

procedure getpalette(P : Palette);
 var Counter : Word;
begin
 for Counter:=0 to 16 do
     begin
      Port[$3C7]:=Counter;
      P[Counter,1]:=Port[$3C9];
      P[Counter,2]:=Port[$3C9];
      P[Counter,3]:=Port[$3C9];
     end;
end;

procedure VSync; assembler;
asm
   mov  dx,3DAh
@VBLactive:
   in   al,dx
   test al,8
   jnz  @VBLactive
@noVBL:
   in   al,dx
   test al,8
   jz   @noVBL
end;

Procedure FadingBlue;
begin
 Inc(MyPal[1,3], Pusher);
 if MyPal[1,3] = 63 then Pusher:= -1;
 if MyPal[1,3] = 0  then Pusher:= +1;
 Vsync;
 port[$3c8]:=1;
 port[$3c9]:=MyPal[1,1];
 port[$3c9]:=MyPal[1,2];
 port[$3c9]:=MyPal[1,3];
end;

Procedure InitStars;
 var Counter : Word;
begin
 for Counter := 1 to StarCount do
     begin
      StarField[counter].x     := random(81);
      StarField[counter].y     := random(50);
      StarField[counter].Speed := Random(3) + 1;
     end;
end;

Procedure AnimateStars;
 var Counter : Word;
begin
 bgcolor := 0;
 if AnimateTimer mod 2 = 0 then
    for Counter := 1 to StarCount do
        begin
         If Byte(StarField[counter].x + StarField[counter].Speed) > 80 then
            begin
             Gotoxy(StarField[counter].x, StarField[counter].y);
             if Mem[$B800:(Cursor_Y shl 6 +
                    Cursor_y shl 4 + Cursor_x)*2+1] and 240 = 0 then
                WriteChar(0);
             StarField[counter].x     := 0;
             StarField[counter].y     := random(50);
             StarField[counter].Speed := Random(3) + 1;
            end;
         Gotoxy(StarField[counter].x, StarField[counter].y);
         if Mem[$B800:(Cursor_Y shl 6 + Cursor_y shl 4 + Cursor_x)*2+1]
                and 240 = 0 then WriteChar(0);
         Inc(StarField[counter].x, StarField[counter].Speed);
         Gotoxy(StarField[counter].x, StarField[counter].y);
         FGColor:= SpeedColors[StarField[counter].Speed];
         if Mem[$B800:(Cursor_Y shl 6 + Cursor_y shl 4 + Cursor_x)*2+1]
                and 240 = 0 then WriteChar(249);
        end;
end;

{ Funktionen des DateiSystems ******************************************* }

Function FileExists(FileName : String) : Boolean;
 var totest : TexT;
begin
 assign(totest, FileName);
 {$I-}
  reset(totest);
 {$I+}
 if IoResult <> 0 then FileExists := False;
end;

function SearchForCDCode : Boolean;
 var SearchTemp : String;
begin
 LineOfCode := 0;
 SearchTemp := '';
 reset(CodeFile);
 Repeat
  Readln(CodeFile, SearchTemp);
  Inc(LineOfCode);
 until eof(CodeFile) or (SearchTemp = CDCode);
 If not eof(CodeFile) then SearchForCDCode := True else
                           SearchForCDCode := False;
end;

Function GetCDName : String;
 var Temp    : String;
begin
 If SearchForCDCode then
    begin
     readln(CodeFile, Temp);
     GetCDName := Temp;
    end
   else
    begin
     GetCDName := 'Unknown CD...'
    end;
end;

Function GetTrackName(Track : Word) : String;
 var ReadBuffer : String;
     Counter    : Word;
begin
 If GetCDName <> 'Unknown CD...' then
    begin
     for counter  := 1 to Track do Readln(CodeFile,ReadBuffer);
     GetTrackName := ReadBuffer;
    end
   else
    begin
     Str(Track, ReadBuffer);
     GetTrackName := 'Track Nr.'+ReadBuffer;
    end;
end;
{ Maus-Steuerung ******************************************************** }

Function InitMouse : Boolean; Assembler;
asm
 mov  ax, 0
 int  Maus
 cmp  ax, 0ffffh
 je   @ende
 mov  al, 0
@ende:
end;

Procedure SetUpMausMovement(MinX, MaxX, MinY, MaxY : Word); Assembler;
asm
 mov  ax, 7
 mov  cx, MinX
 mov  dx, MaxX
 int  Maus
 mov  ax, 8
 mov  cx, MinY
 mov  dx, MaxY
 int  Maus
end;

Procedure ActualizeMausData; Assembler;
asm
 mov  ax, 3
 int  Maus
 shr  dx, 3
 shr  cx, 3
 mov  MausX, CX
 mov  MausY, DX
 mov  Bttn , BX
end;

Procedure ActualizeShowedMaus;
begin
 If (OMX <> MausX) or (OMY <> MausY) then
    begin
     Gotoxy(OMX, OMY);
     Mem[$B800:(Cursor_Y shl 6 + Cursor_y shl 4 + Cursor_x)*2+1]:=TMausByte;
     OMX:=MausX;
     OMY:=MausY;
     gotoxy(MausX, MausY);
     TMausByte:=Mem[$B800:(Cursor_Y shl 6 + Cursor_y shl 4 + Cursor_x)*2+1];
     Mem[$B800:(Cursor_Y shl 6 + Cursor_y shl 4 + Cursor_x)*2+1]:=TMausByte
                                                                or 2 shl 4;
    end;
end;

Function MouseIn(x1, y1, x2, y2 : Byte) : Boolean;
begin
 MouseIn := (MausX + 1 > x1) and (MausX - 1 < x2) and
            (MausY + 1 > y1) and (MausY - 1 < y2);
end;

Procedure Check4MausCommand;
 var TempTime        : Longint;
     Min, Sec, Frame : Word;
     Counter         : Word;
     Changer         : Text;
     InputText       : String;
begin
 If MouseIn(56,9,73,13) then
    begin
     fgColor:=13; bgcolor:=5;
     Gotoxy(10,47);
 MyWriteln('                CD-Drive chooser.                           ');
    end
   else
 If MouseIn(6,9,23,13) then
    begin
     fgColor:=13; bgcolor:=5;
     Gotoxy(10,47);
 MyWriteln('           Information about the CD-ROM drive.              ');
    end
   else
 If MouseIn(27,25,52,27) then
    begin
     fgColor:=13; bgcolor:=5;
     Gotoxy(10,47);
 MyWriteln('    Error messages / CD Name  Right Button = Change name    ');
    end
   else
 If MouseIn(12,40,23,43) then
    begin
     fgColor:=13; bgcolor:=5;
     Gotoxy(10,47);
 MyWriteln('      Quit the program. The music will stop playing.        ');
    end
   else
 If MouseIn(56,40,67,43) then
    begin
     fgColor:=13; bgcolor:=5;
     Gotoxy(10,47);
 MyWriteln('        Quit the program. The music will continue.          ');
    end
   else
 If MouseIn(12,26,23,28) then
    begin
     fgColor:=13; bgcolor:=5;
     Gotoxy(10,47);
 MyWriteln('                    Start to play the CD.                   ');
    end
   else
 If MouseIn(12,29,23,31) then
    begin
     fgColor:=13; bgcolor:=5;
     Gotoxy(10,47);
 MyWriteln('    Pause the music, press Continue to start it again.      ');
    end
   else
 If MouseIn(12,32,23,34) then
    begin
     fgColor:=13; bgcolor:=5;
     Gotoxy(10,47);
 MyWriteln('      Start the music agian if you have pressed pause.      ');
    end
   else
 If MouseIn(12,35,23,37) then
    begin
     fgColor:=13; bgcolor:=5;
     Gotoxy(10,47);
 MyWriteln('                       Stop the music                       ');
    end
   else
 If MouseIn(56,26,67,28) then
    begin
     fgColor:=13; bgcolor:=5;
     Gotoxy(10,47);
 MyWriteln('               Only one track will be played.               ');
    end
   else
 If MouseIn(56,29,67,31) then
    begin
     fgColor:=13; bgcolor:=5;
     Gotoxy(10,47);
 MyWriteln('            One track will be played over and over.         ');
    end
   else
 If MouseIn(56,32,67,34) then
    begin
     fgColor:=13; bgcolor:=5;
     Gotoxy(10,47);
 MyWriteln('               The whole CD will be played once.            ');
    end
   else
 If MouseIn(56,35,67,37) then
    begin
     fgColor:=13; bgcolor:=5;
     Gotoxy(10,47);
 MyWriteln('         The whole CD will be played over and over.         ');
    end
   else
 If MouseIn(10,47,70,47) then
    begin
     fgColor:=12; bgcolor:=5;
     Gotoxy(10,47);
 MyWriteln('           Go away, here is nothing of interest.            ');
    end
   else
 If MouseIn(27,35,52,43) then
    begin
     fgColor:=13; bgcolor:=5;
     Gotoxy(10,47);
 MyWriteln('  Left Button = Choose Track, Right Button = Rename Track.  ');
    end
   else
 If MouseIn(55,16,74,18) then
    begin
     fgColor:=13; bgcolor:=5;
     Gotoxy(10,47);
 MyWriteln('               Shows the way of playing the CD.             ');
    end
   else
 If MouseIn(5,16,24,18) then
    begin
     fgColor:=13; bgcolor:=5;
     Gotoxy(10,47);
 MyWriteln('        Shows how long the Song/CD has been playing.        ');
    end
   else
    begin
     fgColor:=13; bgcolor:=5;
     Gotoxy(10,47); MyWriteln('');
    end;
 If MouseIn(56,9,73,13) and (Bttn = 1) then
    begin
     if CDPosition + MausY - 9 < MSCDEX.Drives then
        begin
         If Playing then StopOrPausePlayingCD(ActualDrive);
         ActualCD.LeadOut := 0;
         GetCDInfo(MSCDEX.DriveChars[CDPosition + MausY - 8]);
         If ActualCD.LeadOut < 150 then
            begin
             gotoxy(27,26); FgColor := 12; BgColor := 5;
             MyWriteln('       No CD found.       ');
             TrackPosition   := 0;
             ActualTrack.TNr := 0;
             for Counter := 1 to 9 do
                 begin
                  If Counter <= ActualCD.HTrack then
                     begin
                      gotoxy(28,34 + Counter);
                      MyWriteln('                         ');
                     end;
                 end;
            end
           else
            begin
             Str(ActualCD.LeadOut, TempStr1);
             Str(ActualCD.HTrack,  TempStr2);
             CDCode := TempStr1 + TempStr2;
             gotoxy(28,26); FgColor := 12; BgColor := 5;
             TempStr1:=GetCDName;
             For Counter := 0 to 25 - Length(TempStr1) do
                 TempStr1 := TempStr1 + ' ';
             TempStr1[0] := chr(ord(TempStr1[0]) - 1);
             MyWriteln(TempStr1);
             close(CodeFile);
             TrackPosition   :=0;
             ActualTrack.Tnr :=1;
             for Counter := 1 to 9 do
                 begin
                  If Counter <= ActualCD.HTrack then
                     begin
                      TempStr1:=GetTrackName(Counter);
                      close(CodeFile);
                      gotoxy(28,34 + Counter);
                      MyWriteln('                         ');
                      gotoxy(28,34 + Counter);
                      If ActualCD.HTrack >= Counter then
                         MyWriteln(TempStr1);
                     end;
                 end;
             ActualDrive:=MSCDEX.DriveChars[CDPosition + MausY-8];
            end;
        end;
     exit;
    end;
 If AnimateTimer mod 5 = 0 then
    If MouseIn(74,9,74,9) and (bttn = 1) then
       begin
        FgColor := 11;
        if 1 - CDPosition > 1 then
           begin
            dec(CDPosition);
            for Counter := 1 + CDPosition to 5 + CDPosition do
                begin
                 If Counter <= MSCDEX.Drives then
                    begin
                     gotoxy(7,12+counter-CDPosition);
                     Str(Counter, TempStr1);
                     MyWriteln(TempStr1+'.    Drive: '+
                               chr(Ord('A')+MSCDEX.DriveChars[1]));
                    end;
                end;
           end;
       end;
 If AnimateTimer mod 5 = 0 then
    If MouseIn(74,13,74,13) and (bttn = 1) then
       begin
        FgColor := 11;
        if MSCDEX.Drives > 5 + CDPosition then
           begin
            inc(CDPosition);
            for Counter := 1 + CDPosition to 5 + CDPosition do
                begin
                 If Counter <= MSCDEX.Drives then
                    begin
                     gotoxy(7,12+counter-CDPosition);
                     Str(Counter, TempStr1);
                     MyWriteln(TempStr1+'.    Drive: '+
                               chr(Ord('A')+MSCDEX.DriveChars[1]));
                    end;
                end;
           end;
       end;
 If AnimateTimer mod 5 = 0 then
    If MouseIn(53,35,53,35) and (bttn = 1) then
       begin
        FgColor := 12;
        if ActualCD.LTrack <> 1 - TrackPosition then
           begin
            dec(TrackPosition);
            for Counter := 1 + TrackPosition to 9 + TrackPosition do
                begin
                 If Counter <= ActualCD.HTrack then
                    begin
                     TempStr1:=GetTrackName(Counter);
                     close(CodeFile);
                     gotoxy(28,34 + Counter-TrackPosition);
                     MyWriteln('                         ');
                     gotoxy(28,34 + Counter-TrackPosition);
                     If ActualCD.HTrack >= Counter then MyWriteln(TempStr1);
                    end;
                end;
           end;
       end;
 If AnimateTimer mod 5 = 0 then
    If MouseIn(53,43,53,43) and (bttn = 1) then
       begin
        FgColor := 12;
        if ActualCD.HTrack > 9 + TrackPosition then
           begin
            inc(TrackPosition);
            for Counter := 1 + TrackPosition to 9 + TrackPosition do
                begin
                 If Counter <= ActualCD.HTrack then
                    begin
                     TempStr1:=GetTrackName(Counter);
                     close(CodeFile);
                     gotoxy(28,34 + Counter-TrackPosition);
                     MyWriteln('                         ');
                     gotoxy(28,34 + Counter-TrackPosition);
                     If ActualCD.HTrack >= Counter then MyWriteln(TempStr1);
                    end;
                end;
           end;
       end;
 If MouseIn(56,26,67,28) and (Bttn = 1) then PlayType := 1;
 If MouseIn(56,29,67,31) and (Bttn = 1) then PlayType := 2;
 If MouseIn(56,32,67,34) and (Bttn = 1) then PlayType := 3;
 If MouseIn(56,35,67,37) and (Bttn = 1) then PlayType := 4;
 If MouseIn(12,26,23,28) and (Bttn = 1) then
    begin
     LoopOn := False;
     If ActualDrive <> 0 then
        begin
         ActualLocation := 0;
         GetTrackInfo(ActualDrive, ActualTrack.TNr);
         If PlayType = 1 then PlayCDFrames(ActualDrive,
                                           RedBook2HSG(ActualTrack.Start),
                                           RedBook2HSG(ActualTrack.Ende));
         If PlayType = 2 then
            begin
             LoopOn := True;
             PlayCDFrames(ActualDrive, RedBook2HSG(ActualTrack.Start),
                                       RedBook2HSG(ActualTrack.Ende));
            end;
         If PlayType = 3 then PlayCDFrames(ActualDrive,
                                           RedBook2HSG(ActualTrack.Start),
                                           Redbook2HSG(ActualCD.LeadOut));
         If PlayType = 4 then
            begin
             LoopOn := True;
             PlayCDFrames(ActualDrive, RedBook2HSG(ActualTrack.Start),
                                       Redbook2HSG(ActualCD.LeadOut));
            end;
        end;
    end;
 If MouseIn(12,29,23,31) and (Bttn = 1) then
    begin
     If Playing then
        begin
         StopOrPausePlayingCD(ActualDrive);
         ResumeReady:=True;
        end;
    end;
 If MouseIn(12,32,23,34) and (Bttn = 1) then
    begin
     If ResumeReady then ResumePlayingCD(ActualDrive);
     ResumeReady := False;
    end;
 If MouseIn(12,35,23,37) and (Bttn = 1) then
    begin
     ResumeReady     := False;
     LoopOn          := False;
     ActualTrack.Tnr := 1;
     GetTrackInfo(ActualDrive, ActualTrack.TNr);
     StopOrPausePlayingCD(ActualDrive);
    end;
 If MouseIn(12,40,23,43) and (bttn = 1) then
    begin
     StopOrPausePlayingCD(ActualDrive);
     Finish := True;
    end;
 If MouseIn(27,35,52,43) and (bttn = 1) then
    begin
     ActualLocation  := 0;
     ResumeReady     := False;
     ActualTrack.TNr := MausY - 34 + TrackPosition;
     GetTrackInfo(ActualDrive, ActualTrack.TNr);
     LoopOn := False;
     If Playing then
        begin
         StopOrPausePlayingCD(ActualDrive);
         If PlayType = 1 then PlayCDFrames(ActualDrive,
                                           RedBook2HSG(ActualTrack.Start),
                                           RedBook2HSG(ActualTrack.Ende))
                                           else
         If PlayType = 2 then
            begin
             LoopOn := True;
             PlayCDFrames(ActualDrive, RedBook2HSG(ActualTrack.Start),
                                       RedBook2HSG(ActualTrack.Ende));
            end else
         If PlayType = 3 then PlayCDFrames(ActualDrive,
                                           RedBook2HSG(ActualTrack.Start),
                                           Redbook2HSG(ActualCD.LeadOut-
                                                       ActualTrack.Start))
                                           else
         If PlayType = 4 then
            begin
             LoopOn := True;
             PlayCDFrames(ActualDrive, RedBook2HSG(ActualTrack.Start),
                                       Redbook2HSG(ActualCD.LeadOut-
                                                   ActualTrack.Start));
            end;
        end;
    end;
 If not Playing then
    begin
     If MouseIn(27,32,52,32) and (bttn = 2) then
        begin
         If SearchForCDCode = False then
            begin
             close(CodeFile);
             DrawWindow(2,26,15,53,17,14,5);
             Gotoxy(28,16); Input(InputText,25);
             Append(CodeFile);
             Writeln(CodeFile, CDCode);
             Writeln(CodeFile, InputText);
             For Counter := ActualCD.LTrack to ActualCD.HTrack do
                 begin
                  Write(CodeFile,'Track Nr.');
                  Writeln(CodeFile, Counter);
                 end;
             close(CodeFile);
            end
           else
            begin
             close(CodeFile);
             Assign(Changer, 'Change.Dat');
             Rewrite(Changer);
             Reset(CodeFile);
             For Counter := 1 to lineOfCode do
                 begin
                  Readln(CodeFile, InputText);
                  Writeln(Changer, InputText);
                 end;
             Readln(CodeFile, InputText);
             DrawWindow(2,26,15,53,17,14,5);
             Gotoxy(28,16); Input(InputText,25);
             Writeln(Changer, InputText);
             If not EOF(CodeFile) then
                Repeat
                 Readln(CodeFile, InputText);
                 Writeln(Changer, InputText);
                until Eof(CodeFile);
             Close(Changer);
             Close(CodeFile);
             erase(Codefile);
             Rename(Changer, 'CDCodes.Dat');
            end;
         DrawWindow(2,26,15,53,17,0,0);
         If SearchForCDCode then;
         Readln(CodeFile, InputText);
         close(CodeFile);
         BgColor := 5;
         FgColor := 12;
         gotoxy(28,32); MyWriteln('                         ');
         gotoxy(28,32); MyWriteln(InputText);
        end;
     If MouseIn(27,35,52,43) and (bttn = 2) then
        begin
         TempTime := MausY - 34 + TrackPosition;
         If SearchForCDCode = False then
            begin
             close(CodeFile);
             DrawWindow(2,26,15,53,17,14,5);
             Gotoxy(28,16); Input(InputText,25);
             Append(CodeFile);
             Writeln(CodeFile, CDCode);
             Writeln(CodeFile, 'Known CD...');
             For Counter := ActualCD.LTrack to ActualCD.HTrack do
                 begin
                  if Counter <> TempTime then
                     begin
                      Write(CodeFile,'Track Nr.');
                      Writeln(CodeFile, Counter);
                     end
                    else
                     Writeln(CodeFile, InputText);
                 end;
             close(CodeFile);
            end
           else
            begin
             close(CodeFile);
             Assign(Changer, 'Change.Dat');
             Rewrite(Changer);
             Reset(CodeFile);
             For Counter := 1 to lineOfCode + TempTime do
                 begin
                  Readln(CodeFile, InputText);
                  Writeln(Changer, InputText);
                 end;
             Readln(CodeFile, InputText);
             DrawWindow(2,26,15,53,17,14,5);
             Gotoxy(28,16); Input(InputText,25);
             Writeln(Changer, InputText);
             If not EOF(CodeFile) then
                Repeat
                 Readln(CodeFile, InputText);
                 Writeln(Changer, InputText);
                until Eof(CodeFile);
             Close(Changer);
             Close(CodeFile);
             erase(Codefile);
             Rename(Changer, 'CDCodes.Dat');
            end;
         DrawWindow(2,26,15,53,17,0,0);
         FgColor := 12;
         BgColor := 5;
         for Counter := 1 + TrackPosition to 9 + TrackPosition do
             begin
              If Counter <= ActualCD.HTrack then
                 begin
                  TempStr1:=GetTrackName(Counter);
                  close(CodeFile);
                  gotoxy(28,34 + Counter-TrackPosition);
                  MyWriteln('                         ');
                  gotoxy(28,34 + Counter-TrackPosition);
                  If ActualCD.HTrack >= Counter then MyWriteln(TempStr1);
                 end;
             end;
        end;
    end;
 if MouseIn(56,40,67,43) And (bttn = 1) then Finish := True;
end;

{ In- / Outitialisation ************************************************ }

Procedure DrawBoxes;
 Var Counter : Word;
begin
 DrawWindow(1,2,2,77,4,13,5);
 gotoxy(4,3);
 bgColor:=5;
 fgColor:=10;
 MyWriteln('    Prophecy''s CD-Player V1.0'+
           ' ** FREEWARE ** Coded By Andreas Ertelt');
 DrawWindow(2,5,8,24,14,14,5);
 gotoxy(9,8);
 MyWriteln('Drive-Status');
 fgColor:=10;
 gotoxy(7,10);
 Str(MSCDEX.Version[1], TempStr1);
 Str(MSCDEX.Version[2], TempStr2);
 TempStr1 := 'Version: '+TempStr1+'.'+TempStr2;
 MyWriteln(TempStr1);
 Str(MSCDEX.Drives, TempStr1);
 Gotoxy(7,11);
 MyWriteln('CD-Drive: '+TempStr1);
 gotoxy(7,12);
 MyWriteln('1. Drive: '+chr(Ord('A')+Byte(MSCDEX.DriveChars[1])));
 DrawWindow(2,9,46,70,48,14,5);
 Gotoxy(24,46);
 MyWriteln('Information from the CD-player');
 DrawWindow(2,26,34,53,44,14,5);
 DrawBlk(53,35,43);
 Gotoxy(30,34);
 MyWriteln('Name of the tracks:');
 DrawWindow(1,26,25,53,27,14,5);
 Gotoxy(32,25);
 MyWriteln('Name of the CD:');
 FgColor:=12;
 gotoxy(27,26);
 MyWriteln('     No drive choosen.    ');
 DrawWindow(2,55,8,74,14,14,5);
 DrawBlk(74,9,13);
 gotoxy(58,8);
 MyWriteln('CD-ROM Drives');
 fgcolor:=11;
 for Counter := 1 to 5 do
     begin
      gotoxy(57,8+Counter);
      If MSCDEX.Drives >= Counter then MyWriteln('   Drive '+
         chr(Ord('A')+Byte(MSCDEX.DriveChars[counter])));
     end;
 DrawWindow(2,11,25,24,44,14,5);
 WrapLine(11,39,12);
 fgColor:=11;
 Gotoxy(13,27); MyWriteln('   Play  ');
 Gotoxy(13,30); MyWriteln('  Pause! ');
 Gotoxy(13,33); MyWriteln(' Continue');
 Gotoxy(13,36); MyWriteln('   Stop  ');
 Gotoxy(13,42); MyWriteln('   Quit  ');
 DrawWindow(2,55,25,68,44,14,5);
 WrapLine(55,39,12);
 fgColor:=11;
 Gotoxy(56,27); MyWriteln('Single Track');
 Gotoxy(56,30); MyWriteln(' Track Loop ');
 Gotoxy(56,33); MyWriteln(' Single  CD ');
 Gotoxy(56,36); MyWriteln('  CD  Loop  ');
 Gotoxy(56,42); MyWriteln('    Quit    ');
 DrawWindow(2,5,16,24,18,14,5);
 Gotoxy(9,16); MyWriteln('Track-Time:');
 DrawWindow(2,55,16,74,18,14,5);
 Gotoxy(58,16); MyWriteln('Way of playing:');
end;

Procedure Initialisation;
 var Counter : Word;
begin
 If not FileExists('CDCodes.dat') then
    begin
     Assign(CodeFile, 'CDCodes.dat');
     ReWrite(CodeFile);
    end
   else
    begin
     Assign(CodeFile, 'CDCodes.dat');
     Reset(CodeFile);
    end;
 close(CodeFile);
 PlayType        := 1;
 CDPosition      := 0;
 TrackPosition   := 0;
 ActualDrive     := 0;
 ActualTrack.Tnr := 2;
 Pusher          := 1;
 Finish          := False;
 Playing         := False;
 ResumeReady     := False;
 LoopOn          := False;
 Cursor_X        := 0;
 Cursor_Y        := 0;
 TMausByte       := Mem[$B800:(Cursor_Y shl 6 +
                    Cursor_y shl 4 + Cursor_x)*2+1];
 OMX             := 100;
 OMY             := 100;
 FillChar(ActualCD,SizeOf(ActualCD),0);
 InitStars;
 InitMscdex;
 If not MSCDEX.Installed then
    begin
     Writeln(' - Error: MSCDEX not installed...');
     Halt;
    end;
 if (MSCDEX.Version[1] < 2) or ((MSCDEX.Version[1] = 2) and
    (MSCDEX.Version[2] < 1)) then
    begin
     Writeln(' - Error: MSCDEX-Version 2.1 or later needed...');
     Halt;
    end;
 SetSpecialTextMode;
 If not InitMouse then
    begin
     SetStandardTextMode;
     Writeln(' - Errorr: No mouse installed...');
     Halt;
    end;
 SetUpMausMovement(1,638,1,392);
 GetPalette(MyPal);
 MyPal[5,1]:=0;
 MyPal[5,2]:=0;
 MyPal[5,3]:=32;
 port[$3c8]:=5;
 port[$3c9]:=MyPal[5,1];
 port[$3c9]:=MyPal[5,2];
 port[$3c9]:=MyPal[5,3];
 MyPal[1,1]:=0;
 MyPal[1,2]:=0;
 MyPal[1,3]:=0;
 port[$3c8]:=1;
 port[$3c9]:=MyPal[1,1];
 port[$3c9]:=MyPal[1,2];
 port[$3c9]:=MyPal[1,3];
 SetBorder(1);
 DrawBoxes;
end;

Procedure Outitialisation;
begin
 SetStandardTextmode;
end;

{ Hauptprogramm ********************************************************* }

begin
 Initialisation;
 repeat
  ActualizeMausData;
  ActualizeShowedMaus;
  AnimateStars;
  FadingBlue;
  Inc(AnimateTimer);
  If ActualDrive <> 0 then
     if not CDInserted then
        begin
         gotoxy(27,26); FgColor := 12; BgColor := 5;
         MyWriteln('      No CD Inserted      ');
         TrackPosition   := 0;
         ActualTrack.TNr := 0;
         for MainCounter := 1 to 9 do
             begin
              If MainCounter <= ActualCD.HTrack then
                 begin
                  gotoxy(28,34 + MainCounter);
                  MyWriteln('                         ');
                 end;
             end;
         ActualDrive    := 0;
         ActualLocation := 0;
        end
       else
        begin
         GetCDLocation(ActualDrive);
        end;
  If not Playing and not ResumeReady then
     begin
      StopOrPausePlayingCD(ActualDrive);
     end;
  If LoopOn and not Playing and not ResumeReady then
     begin
      If PlayType = 2 then PlayCDFrames(ActualDrive,
                                        RedBook2HSG(ActualTrack.Start),
                                        RedBook2HSG(ActualTrack.Ende));
      If PlayType = 4 then
         begin
          PlayCDFrames(ActualDrive,
          RedBook2HSG(ActualTrack.Start),Redbook2HSG(ActualCD.LeadOut));
         end;
      GetCDLocation(ActualDrive);
     end;
  Check4MausCommand;
  ActualizeStatus;
 until finish;
 Outitialisation;
end.
