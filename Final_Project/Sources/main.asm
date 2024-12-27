;*****************************************************************
;* COE538 F2024 EEBOT GUIDER PROJECT                             *
;*    Jeffery Wong   501103254                                   *
;*    Alvi Alam      501111083                                   *
;*    Ademola Bello  501033487                                   *
;*                                                               *
;* This stationery serves as the framework for a                 *
;* user application (single file, absolute assembly application) *
;* For a more comprehensive program that                         *
;* demonstrates the more advanced functionality of this          *
;* processor, please see the demonstration applications          *
;* located in the examples subdirectory of the                   *
;* Freescale CodeWarrior for the HC12 Program directory          *
;*****************************************************************

; export symbols
            XDEF Entry, _Startup                                  ; export 'Entry' symbol
            ABSENTRY Entry                                        ; for absolute assembly: mark this as application entry point



; Include derivative-specific definitions 
		INCLUDE 'derivative.inc' 

; ---------------------------------------------------------------------------
;                         ’Read Guider’ Demo Routine
;
; Reads the eebot guider sensors and displays the values
;   on the Liquid Crystal Display.

; Peter Hiscocks
; Version 2

; Modified from version 1 to support selection of the individual LED
;   associated with a sensor, to reduce crosstalk from unselected sensor
;   LEDs.
; The guider hardware was modified with the addition of a 74HC138 decoder that
;   drives the individual LEDs, so that only the LED associated with a given
;   sensor is ON when that sensor is being read.
; This requires that the software be modified to enable the decoder with bit PA5
;   in PORTA.
; The CdS cells are very slow in responding to changes in light, so a 20
;   millisecond delay is inserted between selecting a particular sensor and
;   reading its value.
; Substantial improvement:
;     Draws less battery current for longer life
;     Creates less heat in the 5V logic regulator
;     Much greater contrast between dark and light readings

; Overview:
; --------
; This program is intended as a test routine for the guider sensors of the
;   eebot robot and contains routines that will be useful in the robot
;   guidance project.
; The guider consists of four absolute brightness sensors and one
;   differential brightness pair of sensors. They are arranged at the nose of
;   the robot in the following pattern (viewed from above):

;                                     A
;                                   B C D
;                                    E-F

; The sensors are cadmium sulphide (CdS) photoresistive cells, for which the
;   resistance increases with decreasing light level. The absolute cells
;   A,B,C and D are driven from a constant current source, and the voltage
;   across the cell measured via the HCS12 A/D converter channel AN1. Thus
;   the sensor reading increases as the sensor becomes darker (over a black
;   line, for example).

; The differential sensor E-F is a voltage divider with the two CdS cells E
;   and F separated 0.75 inches, which is the width of electrical tape. It is
;   intended to be used to track the edges of the electrical tape ’line’ once
;   the absolute cells have ’found’ a black line. Cell E is at the top of the
;   divider, so as the reading from this sensor increases, cell E is becoming
;   lighter, ie, cell E is straying onto the white background.
;   Simultaneously, cell F is becoming darker as it moves over the black
;   tape, and its resistance is increasing, aiding the same effect. The
;   differential action should ignore ambient light.

; The program reads the sensor values, hopefully without disturbing any
;   other settings on the robot. The values are displayed in hexadecimal on
;   the LCD. On the LCD display, the pattern is as described in the routine
;   ’DISPLAY_SENSORS’.	

; The 4 absolute sensors should show readings equivalent to approximately 2
;   volts when over a light surface and 4 volts when covered by a finger. The
;   range from light background to black tape background is typically 1.5 volts
;   over a light background to 2.4 volts over black tape.
; We have yet to quantify the readings from the differential sensor E-F.	
		

;*****************************************************************
;*                                                               *
;*                      EQUATES SECTION                          *
;*                                                               *
;*****************************************************************
; Liquid Crystal Display Equates
;-------------------------------
CLEAR_HOME                EQU           $01                       ; Clear the display and home the cursor
INTERFACE                 EQU           $38                       ; 8 bit interface, two line display
CURSOR_OFF                EQU           $0C                       ; Display on, cursor off
SHIFT_OFF                 EQU           $06                       ; Address increments, no character shift
LCD_SEC_LINE              EQU           64                        ; Starting addr. of 2nd line of LCD (note decimal value!)

; LCD Addresses
LCD_CNTR                  EQU           PTJ                       ; LCD Control Register: E = PJ7, RS = PJ6
LCD_DAT                   EQU           PORTB                     ; LCD Data Register: D7 = PB7, ... , D0 = PB0
LCD_E                     EQU           $80                       ; LCD E-signal pin
LCD_RS                    EQU           $40                       ; LCD RS-signal pin

; Delays/Intervals for EEBOT movement states
FWD_INT                   EQU           3                         ; Increase delays to make EEBOT move faster (Read sensors at longer length intervals)
FWD_L_JUNC_INT            EQU           9                         ;                 |
READ_SENS_INT             EQU           1                         ;                 |
REV_INT                   EQU           9                         ;                 |
REV_TRN_INT               EQU           46                        ;                 |
FWD_TRN_INT               EQU           30                        ;                 V

; EEBOT States
START                     EQU           0                         ; Start state
FWD                       EQU           1                         ; Forward movement state
REV                       EQU           2                         ; Reverse movement state
ALL_STP                   EQU           3                         ; All movement and operation stop state
RIGHT_ADJST               EQU           4                         ; Right adjustment state                
LEFT_ADJST                EQU           5                         ; Left adjustment state                 
REV_TRN                   EQU           6                         ; Turn after reverse state                      
READ_SENS                 EQU           7                         ; Sensor reading state
FWD_TRN                   EQU           8                         ; Forward turn state (For right turns)  
FWD_L_JUNC                EQU           9                         ; Forward state for when EEBOT is at L-shape junction           

; Other codes
NULL                      EQU           00                        ; The string ’null terminator’
CR                        EQU           $0D                       ; ’Carriage Return’ character
SPACE                     EQU           ' '                       ; The ’space’ character

;*****************************************************************
;*                                                               *
;*                    VARIABLE/DATA SECTION                      *
;*                                                               *
;*****************************************************************
;---------------------------------------------------------------------------
; Storage Registers (9S12C32 RAM space: $3800 ... $3FFF)
                          ORG $3800

SENSOR_LINE               FCB           $01                       ; Storage for guider sensor readings    (E-F)
SENSOR_BOW                FCB           $23                       ; Initialized to test values             (A)
SENSOR_PORT               FCB           $45                       ;                                        (B)
SENSOR_MID                FCB           $67                       ;                                        (C)
SENSOR_STBD               FCB           $89                       ;                                        (D)

;LINE_VAR                  FCB           $6E                       ; Variances for each sensor from testing
;BOW_VAR                   FCB           $CB                       ;
;PORT_VAR                  FCB           $CB                       ;
;MID_VAR                   FCB           $CB                       ;
;STBD_VAR                  FCB           $84                       ;

SENSOR_NUM                RMB           1                         ; The currently selected sensor

TOP_LINE                  RMB           20                        ; Top line of display
                          FCB           NULL                      ; terminated by null

BOT_LINE                  RMB           20                        ; Bottom line of display
                          FCB           NULL                      ; terminated by null

CLEAR_LINE                FCC           ' '
                          FCB           NULL                      ; terminated by null

TEMP                      RMB           1                         ; Temporary location		

; variable section
                          ORG $3850
                                      
TOF_COUNTER               dc.b          0                         ; The timer, incremented at 23Hz
CRNT_STATE                dc.b          3                         ; Current state register
CRNT_DIR                  dc.b          3                         ; Current direction
T_FWD                     ds.b          1                         ; FWD time
T_FWD_L_JUNC              ds.b          1                         ; FWD time at L-Shape junction
T_REV                     ds.b          1                         ; REV time  
T_REV_TRN                 ds.b          1                         ; TURN after reverse (180 degrees) time
T_FWD_TRN                 ds.b          1                         ; FWD_TURN time
T_READ_SENS               ds.b          1

TEN_THOUS                 ds.b          1                         ; 10,000 digit
THOUSANDS                 ds.b          1                         ;  1,000 digit
HUNDREDS                  ds.b          1                         ;    100 digit
TENS                      ds.b          1                         ;     10 digit
UNITS                     ds.b          1                         ;      1 digit
BCD_SPARE                 RMB           10      
NO_BLANK                  ds.b          1                         ; Used in 'leading zero' blanking by BCD2ASC

; For Binary to ASCII Subroutine in SUBROUTINE SECTION
HEX_TABLE                 FCC           '0123456789ABCDEF'        ; Table for converting values
              

;*****************************************************************
;*                                                               *
;*                        CODE SECTION                           *
;*                                                               *
;*****************************************************************		

                          ORG $4000                               ; Start of program text (FLASH memory)
;---------------------------------------------------------------------------
; Initialization
Entry:                
_Startup:   
                          LDS           #$4000                    ; Initialize the stack pointer       
                          CLI                                     ; Enable interrupts 
        
                          BSET          DDRA,%00000011            ; STAR_DIR, PORT_DIR 
                          BSET          DDRT,%00110000            ; STAR_SPEED, PORT_SPEED 
                                
                          JSR           INIT                      ; Initialize ports
                          JSR           openADC                   ; Initialize the ATD
                          JSR           openLCD                   ; Initialize the LCD
                          JSR           CLR_LCD_BUF               ; Write ’space’ characters to the LCD buffer

                          JSR           initAD                    ; Initialize ATD converter 
                       
                          JSR           initLCD                   ; Initialize the LCD 
                          JSR           clrLCD                    ; Clear LCD & home cursor 

                          LDX           #msg1                     ; Display msg1 
                          JSR           putsLCD                   ; " "

                          LDAA          #$C0                      ; Move LCD cursor to the 2nd row 
                          JSR           cmd2LCD
                          LDX           #msg2                     ; Display msg2 |
                          JSR           putsLCD                   ; " "
          
                          JSR           ENABLE_TOF                ; Jump to TOF initialization 

;---------------------------------------------------------------------------
; Display Sensors            
MAIN                      JSR           G_LEDS_ON                 ; Enable the guider LEDs      |-
                          JSR           READ_SENSORS              ; Read the 5 guider sensors   | | In the routine INIT_READ_SENS
                          JSR           G_LEDS_OFF                ; Disable the guider LEDs     |-
                          JSR           DISPLAY_SENSORS           ; and write them to the LCD   
                          LDY           #6000                     ; 300 ms delay to avoid
                          JSR           UPDT_DISPL               
                          LDAA          CRNT_STATE                                             
                          JSR           DISPATCHER    
                          JSR           del_50us                  ; display artifacts
                          BRA MAIN                                ; Loop forever

;---------------------------------------------------------------------------
; Data Section
msg1:                     dc.b          "Battery volt ",0
msg2:                     dc.b          "State ",0
tab:                      dc.b          "START  ",0
                          dc.b          "FWD    ",0
                          dc.b          "REV    ",0
                          dc.b          "ALL_STP",0
                          dc.b          "LEFT_ADJST ",0
                          dc.b          "RIGHT_ADJST ",0
                          dc.b          "REV_TRN",0
                          dc.b          "READ   ", 0
                          dc.b          "FWD_TRN", 0
                          dc.b          "FWD_L_JUNC", 0

;*****************************************************************
;*                                                               *
;*                      SUBROUTINE SECTION                       *
;*                                                               *
;*****************************************************************		
;---------------------------------------------------------------------------
;EEBOT Movement related subrotuines that need to be changed, i.e. DISPATCHER to INIT_ALL_STP and INIT_READ_SENS
 
DISPATCHER              CMPA            #START                    ; If it’s the START state -----------------
                        BNE             NOT_START                 ;                                          |                            
                        JSR             START_ST                  ; then call START_ST routine               |
                        BRA             DISP_EXIT                 ; and exit                                 |
                                                                  ;                                          |
NOT_START               CMPA            #FWD                      ; Compare value in ACCA to forward state   |
                        BNE             NOT_FWD                   ; Branch if state is not equal to FWD      |
                        JSR             FWD_ST                    ; If equal to FWD jump to FWD_ST           |
                        JMP             DISP_EXIT                 ; Jump to exit from state dispatcher       |                              
                                                                  ;                                          |
NOT_FWD                 CMPA            #REV                      ; Compare value in ACCA to reverse state   |
                        BNE             NOT_REV                   ; Branch if state is not equal to REV      |
                        JSR             REV_ST                    ; If equal to FWD jump to REV_ST           |
                        JMP             DISP_EXIT                 ;                                          |
                                                                  ;                                          |
NOT_REV                 CMPA            #ALL_STP                  ; Compare value in ACCA to All stop state  |
                        BNE             NOT_ALL_STOP              ;                                          |
                        JSR             ALL_STP_ST                ;                                          |
                        JMP             DISP_EXIT                 ;                                          |
                                                                  ;                                          D
NOT_ALL_STOP            CMPA            #LEFT_ADJST               ;                                          I
                        BNE             NOT_LEFT_ADJST            ;                                          S
                        JSR             LEFT_ADJST_ST             ;                                          P
                        JMP             DISP_EXIT                 ;                                          A                                                                  ; A
                                                                  ;                                          T
NOT_LEFT_ADJST          CMPA            #RIGHT_ADJST              ;                                          C
                        BNE             NOT_RIGHT_ADJST           ;                                          H
                        JSR             RIGHT_ADJST_ST            ;                                          E
                        JMP             DISP_EXIT                 ;                                          R
                                                                  ;                                          |
NOT_RIGHT_ADJST         CMPA            #REV_TRN                  ;                                          |
                        BNE             NOT_REV_TRN               ;                                          |
                        JSR             REV_TRN_ST                ;                                          |
                        JMP             DISP_EXIT                 ;                                          |
                                                                  ;                                          |
NOT_REV_TRN             CMPA            #READ_SENS                ;                                          |
                        BNE             NOT_READ_SENS             ;                                          |
                        JSR             READ_SENS_ST              ;                                          |
                        JMP             DISP_EXIT                 ;                                          |
                                                                  ;                                          |
NOT_READ_SENS           CMPA            #FWD_L_JUNC               ;                                          |
                        BNE             NOT_FWD_L_JUNC            ;                                          |
                        JSR             FWD_L_JUNC_ST             ;                                          |
                        JMP             DISP_EXIT                 ;                                          |
                                                                  ;                                          |
NOT_FWD_L_JUNC          CMPA            #FWD_TRN                  ;                                          |
                        BNE             NOT_FWD_TRN               ;                                          |
                        JSR             FWD_TRN_ST                ;                                          |
                        JMP             DISP_EXIT                 ;                                          |
                                                                  ;                                          |
NOT_FWD_TRN             SWI                                       ; Else the CRNT_ST is not defined, so stop |
                                                                  ;                                          |
DISP_EXIT               RTS                                       ; Exit from the state dispatcher ----------
                                                                  
;*****************************************************************
; EEBOT in Start State
START_ST                BRCLR           PORTAD0,$04,NO_FWD        ; If front bumper is clear (0) branch to NO_FWD  
                        JSR             INIT_FWD                  ; Jump to INIT_FWD subroutine to initialize forward state
                        MOVB            #FWD, CRNT_STATE          ; Move byte of FWD state to Current state (set current state as FWD)
                        BRA             START_EXIT                ; and return

NO_FWD                  NOP                                       ; Else

START_EXIT              RTS                                       ; return to the MAIN routine

;*****************************************************************
; EEBOT in Forward State (For any case)
FWD_ST                  BRSET           PORTAD0,$04,NO_FWD_BUMP   ; If bumper is set (1) then branch to NO_FWD_BUMP (bow bumper NOT activated)
                        JSR             INIT_REV                  ; Jump to INIT_REV to initilize reverse state (bow bumper activated)
                        MOVB            #REV, CRNT_STATE          ; Set current state as REV
                        JMP             FWD_EXIT                  ; and return

NO_FWD_BUMP             BRSET           PORTAD0,$08,NO_REAR_BUMP  ; If stern bumper is not activated branch to NO_REAR_BUMP 
                        JSR             INIT_ALL_STP              ; Jump to INIT_ALL_STOP to initialize all stop state (stern bumper activated)
                        MOVB            #ALL_STP,CRNT_STATE       ; Set current state to ALL_STP
                        JMP             FWD_EXIT                  ; and return

NO_REAR_BUMP            LDAA            TOF_COUNTER               ; Load ACCA with Timer overflow counter
                        CMPA            T_FWD                     ; Compare value in ACCA with the value of the FWD state time 
                        BNE             NO_READ_SENS              ; Branch to NO_READ_SENS if T_FWD is not equal to TOF_COUNTER (Stay in Forward State)
                        JSR             INIT_READ_SENS            ; Jump to INIT_READ_SENS to initialize sensore reading state (T_FWD = TOF_COUNTER)
                        MOVB            #READ_SENS, CRNT_STATE    ; Set current state to READ_SENS
                        JMP             FWD_EXIT                  ; and return
                
NO_READ_SENS            NOP                                       ; Not reading sensors/No operation

FWD_EXIT                RTS                                       ; return to the MAIN routine

;*****************************************************************
; EEBOT in Reverse State
REV_ST                  LDAA            TOF_COUNTER               ; Load ACCA with Timer overflow counter
                        CMPA            T_REV                     ; Compare value in ACCA with the value of the REV state time 
                        BNE             REV_ST                    ; Branch to NO_READ_SENS if T_REV is not equal to TOF_COUNTER (Stay in Reverse state)
                        JSR             INIT_REV_TRN              ; Jump to INIT_REV_TURN to initialize the turn once state (T_REV = TOF_COUNTER)
                        MOVB            #REV_TRN,CRNT_STATE       ; Set current state to REV_TRN
                        BRA             REV_EXIT                  ; and return
                
REV_EXIT                RTS                                       ; return to the MAIN routine

;*****************************************************************
; EEBOT in All Operations Stopped State
ALL_STP_ST              BRSET           PORTAD0,$04,NO_START      ; If stern bumper is activated, stay in NO_START state 
                        BCLR            PTT,%00110000             ; Once stern bumper is released
                        MOVB            #START,CRNT_STATE         ; Set current state to START 
                        BRA             ALL_STP_EXIT              ; and return
                      
NO_START                NOP                                       ; Else

ALL_STP_EXIT            RTS                                       ; return to the MAIN routine

;*****************************************************************
; EEBOT in Forward Right Turn State
FWD_TRN_ST              LDAA            TOF_COUNTER               ; Load ACCA with Timer overflow counter
                        CMPA            T_FWD_TRN                 ; Compare value in ACCA with the value of the T_FWD_TRN 
                        BNE             FWD_TRN_ST                ; If value of TOF_COUNTER and T_FWD_TRN are not equal branch to FWD_TRN_ST 
                        JSR             INIT_FWD                  ; Otherwise jump to INIT_FWD to initalize forward state
                        MOVB            #FWD,CRNT_STATE           ; set state to FWD
                        BRA             FWD_TRN_EXIT              ; and return
               
NO_FWD_FT               NOP                                       ; Else

FWD_TRN_EXIT            RTS                                       ; return to the MAIN routine

;*****************************************************************
; EEBOT in Forward State (at L-Shape Junction)
FWD_L_JUNC_ST           LDAA            TOF_COUNTER               ; Load ACCA with Timer overflow counter
                        CMPA            T_FWD_L_JUNC              ; Compare value in ACCA with the value of the T_FWD_L_JUNC 
                        BNE             FWD_L_JUNC_ST             ; If value of TOF_COUNTER and T_FWD_L_JUNC are not equal branch to FWD_L_JUNC_ST
                        JSR             INIT_FWD                  ; Jump to INIT_FWD to initialize forward state 
                        MOVB            #FWD,CRNT_STATE           ; Set current state to FWD
                        BRA             FWD_EXIT                  ; and return          

FWD_L_JUNC_EXIT         RTS                                       ; return to the MAIN routine

;*****************************************************************
; EEBOT in Turn Once State
REV_TRN_ST              LDAA            TOF_COUNTER               ; Load ACCA with TOF_COUNTER value
                        CMPA            T_REV_TRN                 ; Compare T_REV_TRN value with TOF_COUNTER value
                        BNE             REV_TRN_ST                ; Branch to REV_TRN_ST, if value of TOF_COUNTER and T_REV_TRN are not equal
                        JSR             INIT_FWD                  ; Otherwise, jump to INIT_FWD
                        MOVB            #FWD,CRNT_STATE           ; Set current state to FWD
                        BRA             REV_TRN_EXIT              ; and return
             
NO_FWD_T                NOP                                       ; Else

REV_TRN_EXIT            RTS                                       ; return to the MAIN routine

;*****************************************************************
; EEBOT in Right Adustment State
RIGHT_ADJST_ST          BRSET           PORTAD0,$04,NO_FWD_BUMP2  ; If bow bumper is not activated branch to NO_FWD_BUMP2 
                        JSR             INIT_REV                  ; Otherwise, if bow bumper is activated, jump to INIT_REV
                        MOVB            #REV, CRNT_STATE          ; Set current state to REV
                        JMP             RIGHT_ADJST_EXIT          ; and return

NO_FWD_BUMP2            BRSET           PORTAD0,$08,NO_REAR_BUMP2 ; If stern bumper is not activated branch to NO_REAR_BUMP2 
                        JSR             INIT_ALL_STP              ; Otherwise, if stern bumper is activated, jump to INIT_ALL_STP 
                        MOVB            #ALL_STP,CRNT_STATE       ; Set current state to ALL_STP
                        JMP             RIGHT_ADJST_EXIT          ; and return
                
NO_REAR_BUMP2           CMPA            #$6E                      ; Compare the value in ACCA with $6E
                        BLO             NO_FWD_RT                 ; If value in ACCA is less than $6E branch to NO_FWD_RT
                        JSR             INIT_FWD                  ; Otherwise, jump to INIT_FWD
                        MOVB            #FWD,CRNT_STATE           ; Set current state to FWD
                        JMP             RIGHT_ADJST_EXIT          ; and return
                
NO_FWD_RT               LDAA            TOF_COUNTER               ; Load ACCA with TOF_COUNTER
                        CMPA            T_READ_SENS               ; Compare value in ACCA with T_READ_SENS
                        BNE             NO_READ_SENS2             ; If values in both are not equal, branch to NO_READ_SENS2
                        JSR             INIT_READ_SENS            ; Otherwise, jump to INIT_READ_SENS
                        MOVB            #READ_SENS, CRNT_STATE    ; Set current state to READ_SENS
                        JMP             RIGHT_ADJST_EXIT          ; and return

NO_READ_SENS2           NOP                                       ; Else

RIGHT_ADJST_EXIT        RTS                                       ; return to the MAIN routine

;*****************************************************************
; EEBOT in Left Adjustment State
LEFT_ADJST_ST           BRSET           PORTAD0,$04,NO_FWD_BUMP3  ; Bow bumper not activated, branch to NO_FWD_BUMP3
                        JSR             INIT_REV                  ; Otherwise, jump to INIT_REV
                        MOVB            #REV, CRNT_STATE          ; Set current state to REV
                        JMP             LEFT_ADJST_EXIT           ; and return

NO_FWD_BUMP3            BRSET           PORTAD0,$08,NO_REAR_BUMP3 ; Stern bumper not activated, branch to NO_REAR_BUMP3
                        JSR             INIT_ALL_STP              ; Otherwise, jump to INIT_ALL_STP
                        MOVB            #ALL_STP,CRNT_STATE       ; Set current state to ALL_STP
                        JMP             LEFT_ADJST_EXIT           ; and return
                
NO_REAR_BUMP3           LDAA            SENSOR_LINE               ; Load ACCA with SENSOR_LINE value
                        CMPA            #$74                      ; Compare SENSOR_LINE value with $74
                        BHI             NO_FWD_LT                 ; If SENSOR_LINE value is greater than $74, branch to NO_FWD_LT
                        JSR             INIT_FWD                  ; Otherwise, jump to INIT_FWD
                        MOVB            #FWD,CRNT_STATE           ; Set current state to FWD
                        JMP             LEFT_ADJST_EXIT           ; and return
                
NO_FWD_LT               LDAA            TOF_COUNTER               ; Load ACCA with TOF_COUNTER value
                        CMPA            T_READ_SENS               ; Compare TOF_COUNTER value with T_READ_SENS value
                        BNE             NO_READ_SENS3             ; Branch to NO_READ_SENS3 if the two are not equal
                        JSR             INIT_READ_SENS            ; Otherwise, jump to INIT_READ_SENS
                        MOVB            #READ_SENS, CRNT_STATE    ; Set current state to READ_SENS
                        JMP             LEFT_ADJST_EXIT           ; and return
                
NO_READ_SENS3           NOP                                       ; Else 
              
LEFT_ADJST_EXIT         RTS                                       ; return to the MAIN routine

;*****************************************************************
; EEBOT in Sensor Reading State (Decison Making)
READ_SENS_ST            LDAA            SENSOR_STBD               ; Load ACCA with value of SENSOR_STBD  
                        CMPA            #$84                      ; Compare it with $84
                        BLS             NO_RIGHT                  ; Branch to NO_RIGHT if SENSOR_STBD value is less than $84
                        JSR             INIT_FWD_TRN              ; Otherwise, jump to INIT_FWD_TRN
                        MOVB            #FWD_TRN, CRNT_STATE      ; Set current state to FWD_TRN
                        JMP             READ_SENS_EXIT            ; Jump to READ_SENS_EXIT

; If EEBOT can't turn right
NO_RIGHT                LDAA            SENSOR_BOW                ; Load ACCA with value of SENSOR_BOW  
                        CMPA            #$CB                      ; Compare it with $CB
                        BHS             NO_STRAIGHT               ; Branch to NO_STRAIGHT if SENSOR_BOW value is greater than $CB
                        BRA             NO_LEFT                   ; Otherwise, branch to NO_LEFT

; If EEBOT can't go staright 
NO_STRAIGHT             LDAA            SENSOR_PORT               ; Load ACCA with value of SENSOR_PORT  
                        CMPA            #$CB                      ; Compare it with $CB
                        BLS             NO_LEFT                   ; Branch to NO_LEFT if SENSOR_PORT value is less than CB
                        JSR             INIT_FWD_L_JUNC           ; Otherwise, jump to INIT_FWD_L_JUNC
                        MOVB            #FWD_L_JUNC, CRNT_STATE   ; Set current state to FWD_L_JUNC
                        JMP             READ_SENS_EXIT            ; Jump to READ_SENS_EXIT

; If EEBOT can't turn left
NO_LEFT                 LDAA            SENSOR_LINE               ; Load ACCA with value of SENSOR_LINE  
                        CMPA            #$6E                      ; Compare it with $6E
                        BHS             NO_RIGHT_ADJST            ; Branch to NO_RIGHT_ADJST if SENSOR_LINE value is greater than $6E
                        JSR             INIT_RIGHT_ADJST          ; Otherwise, jump to INIT_RIGHT_ADJST
                        MOVB            #RIGHT_ADJST,CRNT_STATE   ; Set current state to RIGHT_ADJST
                        JMP             READ_SENS_EXIT            ; Jump to READ_SENS_EXIT

; If EEBOT can't adjust right                
NO_RIGHT_ADJST          LDAA            SENSOR_LINE               ; Load ACCA with value of SENSOR_LINE  
                        CMPA            #$74                      ; Compare it with $74
                        BLS             NO_LEFT_ADJST             ; Branch to NO_LEFT_ADJST if SENSOR_LINE value is less than $74
                        JSR             INIT_LEFT_ADJST           ; Otherwise, jump to INIT_LEFT_ADJST
                        MOVB            #LEFT_ADJST,CRNT_STATE    ; Set current state to LEFT_ADJST
                        JMP             READ_SENS_EXIT            ; Jump to READ_SENS_EXIT

; If EEBOT can't adjust left              
NO_LEFT_ADJST           JSR             INIT_FWD                  ; Jump to INIT_FWD            
                        MOVB            #FWD,CRNT_STATE           ; Set current state to FWD    
                        JMP             READ_SENS_EXIT            ; Jump to READ_SENS_EXIT      
                             
READ_SENS_EXIT          RTS                                       ; return to the MAIN routine

;*****************************************************************
INIT_FWD                BCLR            PORTA,%00000011           ; Set FWD direction for both motors
                        BSET            PTT,%00110000             ; Turn on the drive motors
                        LDAA            TOF_COUNTER               ; Mark the fwd time Tfwd
                        ADDA            #FWD_INT
                        STAA            T_FWD
                        RTS

;*****************************************************************
INIT_REV                BSET            PORTA,%00000011           ; Set REV direction for both motors
                        BSET            PTT,%00110000             ; Turn on the drive motors
                        LDAA            TOF_COUNTER               ; Mark the fwd time Tfwd
                        ADDA            #REV_INT
                        STAA            T_REV
                        RTS
                        
;*****************************************************************
INIT_ALL_STP            BCLR            PTT,%00110000             ; Turn off the drive motors
                        RTS


;*****************************************************************
INIT_FWD_TRN            BCLR            PORTA,%00000001           ; Set direction for right motor 
                        BSET            PTT,%00010000             ; Turn on the drive motors motor
                        LDAA            TOF_COUNTER               ; Mark the fwd_turn time Tfwdturn
                        ADDA            #FWD_TRN_INT
                        STAA            T_FWD_TRN
                        RTS
                        
;*****************************************************************
INIT_FWD_L_JUNC         BCLR            PORTA,%00000011           ; Set FWD direction for both motors
                        BSET            PTT,%00110000             ; Turn on the drive motors
                        LDAA            TOF_COUNTER               ; Mark the fwd time Tfwd
                        ADDA            #FWD_L_JUNC_INT
                        STAA            T_FWD_L_JUNC
                        RTS

;*****************************************************************
INIT_REV_TRN            BCLR            PORTA,%00000010           ; Set FWD dir. for STARBOARD (right) motor
                        LDAA            TOF_COUNTER               ; Mark the fwd_turn time Tfwdturn
                        ADDA            #REV_TRN_INT
                        STAA            T_REV_TRN
                        RTS

;*****************************************************************
INIT_RIGHT_ADJST        BCLR            PORTA,%00000010           ; Set  direction for right motor
                        BSET            PORTA,%00000001           ; Set  direction for left motor 
                        BSET            PTT,%00110000             ; Turn on the drive motors
                        RTS

;*****************************************************************
INIT_LEFT_ADJST         BCLR            PORTA,%00000001           ; Set  direction for left motor
                        BSET            PORTA,%00000010           ; Set  direction for right motor  
                        BSET            PTT,%00110000             ; Turn on the drive motors
                        RTS                             

;*****************************************************************             
INIT_READ_SENS          BCLR            PTT,%00110000             ; Turn off the drive motors
                        JSR             G_LEDS_ON                 ; Enable the guider LEDs        |- 
                        JSR             READ_SENSORS              ; Read the 5 guider sensors     | |-From MAIN routine
                        JSR             G_LEDS_OFF                ; Disable the guider LEDs       |-
                        LDAA            TOF_COUNTER               ; Mark the fwd time Tfwd
                        ADDA            #READ_SENS_INT
                        STAA            T_READ_SENS
                        RTS
                   

;GIVEN SUBROUTINES START HERE
;---------------------------------------------------------------------------
; Initialize ports

INIT                      BCLR          DDRAD,$FF                 ; Make PORTAD an input (DDRAD @ $0272)
                          BSET          DDRA,$FF                  ; Make PORTA an output (DDRA @ $0002)
                          BSET          DDRB,$FF                  ; Make PORTB an output (DDRB @ $0003)
                          BSET          DDRJ,$C0                  ; Make pins 7,6 of PTJ outputs (DDRJ @ $026A)
                          RTS
                                    
;---------------------------------------------------------------------------
; Initialize the ADC

openADC                   MOVB          #$80,ATDCTL2              ; Turn on ADC (ATDCTL2 @ $0082)
                          LDY           #1                        ; Wait for 50 us for ADC to be ready
                          JSR           del_50us                  ; - " -
                          MOVB          #$20,ATDCTL3              ; 4 conversions on channel AN1 (ATDCTL3 @ $0083)
                          MOVB          #$97,ATDCTL4              ; 8-bit resolution, prescaler=48 (ATDCTL4 @ $0084)
                          RTS
                        
;---------------------------------------------------------------------------
; Clear LCD Buffer

; This routine writes ’space’ characters (ascii 20) into the LCD display
; buffer in order to prepare it for the building of a new display buffer.
; This needs only to be done once at the start of the program. Thereafter the
; display routine should maintain the buffer properly.

CLR_LCD_BUF               LDX           #CLEAR_LINE
                          LDY           #TOP_LINE
                          JSR           STRCPY

CLB_SECOND                LDX           #CLEAR_LINE
                          LDY           #BOT_LINE
                          JSR           STRCPY

CLB_EXIT                  RTS 
           
;---------------------------------------------------------------------------
; String Copy

; Copies a null-terminated string (including the null) from one location to
;   another

; Passed: X contains starting address of null-terminated string
;   Y contains first address of destination

STRCPY                    PSHX                                    ; Protect the registers used
                          PSHY
                          PSHA

STRCPY_LOOP               LDAA          0,X                       ; Get a source character
                          STAA          0,Y                       ; Copy it to the destination
                          BEQ           STRCPY_EXIT               ; If it was the null, then exit
                          INX                                     ; Else increment the pointers
                          INY
                          BRA           STRCPY_LOOP               ; and do it again

STRCPY_EXIT               PULA                                    ; Restore the registers
                          PULY
                          PULX
                          RTS
                          
;---------------------------------------------------------------------------
; Guider LEDs ON

; This routine enables the guider LEDs so that readings of the sensor
;   correspond to the ’illuminated’ situation.

; Passed: Nothing
; Returns: Nothing
; Side: PORTA bit 5 is changed

G_LEDS_ON                 BSET          PORTA,%00100000           ; Set bit 5
                          RTS

;                                       
; Guider LEDs OFF

; This routine disables the guider LEDs. Readings of the sensor
;   correspond to the ’ambient lighting’ situation.

; Passed: Nothing
; Returns: Nothing
; Side: PORTA bit 5 is changed

G_LEDS_OFF                BCLR          PORTA,%00100000           ; Clear bit 5
                          RTS
                          
;---------------------------------------------------------------------------
; Read Sensors
;
; This routine reads the eebot guider sensors and puts the results in RAM
;   registers.

; Note: Do not confuse the analog multiplexer on the Guider board with the
;   multiplexer in the HCS12. The guider board mux must be set to the
;   appropriate channel using the SELECT_SENSOR routine. The HCS12 always
;   reads the selected sensor on the HCS12 A/D channel AN1.

; The A/D conversion mode used in this routine is to read the A/D channel
;   AN1 four times into HCS12 data registers ATDDR0,1,2,3. The only result
;   used in this routine is the value from AN1, read from ATDDR0. However,
;   other routines may wish to use the results in ATDDR1, 2 and 3.
; Consequently, Scan=0, Mult=0 and Channel=001 for the ATDCTL5 control word.

; Passed: None
; Returns: Sensor readings in:
;          SENSOR_LINE (0) (Sensor E/F)
;          SENSOR_BOW (1) (Sensor A)
;          SENSOR_PORT (2) (Sensor B)
;          SENSOR_MID (3) (Sensor C)
;          SENSOR_STBD (4) (Sensor D)
; Note:
;   The sensor number is shown in brackets
;
; Algorithm:
;     Initialize the sensor number to 0
;     Initialize a pointer into the RAM at the start of the Sensor Array storage

; Loop  Store %10000001 to the ATDCTL5 (to select AN1 and start a conversion)
;       Repeat
;         Read ATDSTAT0
;       Until Bit SCF of ATDSTAT0 == 1 (at which time the conversion is complete)
;       Store the contents of ATDDR0L at the pointer
;       If the pointer is at the last entry in Sensor Array, then
;           Exit
;       Else
;           Increment the sensor number
;           Increment the pointer
;       Loop again.

READ_SENSORS              CLR           SENSOR_NUM                ; Select sensor number 0
                          LDX           #SENSOR_LINE              ; Point at the start of the sensor array

RS_MAIN_LOOP              LDAA          SENSOR_NUM                ; Select the correct sensor input
                          JSR           SELECT_SENSOR             ; on the hardware
                          LDY           #400                      ; 20 ms delay to allow the
                          JSR           del_50us                  ; sensor to stabilize
                          
                          LDAA          #%10000001                ; Start A/D conversion on AN1
                          STAA          ATDCTL5
                          BRCLR         ATDSTAT0,$80,*            ; Repeat until A/D signals done
                          
                          LDAA          ATDDR0L                   ; A/D conversion is complete in ATDDR0L
                          STAA          0,X                       ; so copy it to the sensor register
                          CPX           #SENSOR_STBD              ; If this is the last reading
                          BEQ           RS_EXIT                   ; Then exit
                          
                          INC           SENSOR_NUM                ; Else, increment the sensor number
                          INX                                     ; and the pointer into the sensor array
                          BRA           RS_MAIN_LOOP              ; and do it again

RS_EXIT                   RTS                          
                          
;---------------------------------------------------------------------------
; Select Sensor
;
; This routine selects the sensor number passed in ACCA. The motor direction
;   bits 0, 1, the guider sensor select bit 5 and the unused bits 6,7 in the
;   same machine register PORTA are not affected.
; Bits PA2,PA3,PA4 are connected to a 74HC4051 analog mux on the guider board,
;   which selects the guider sensor to be connected to AN1.

; Passed: Sensor Number in ACCA
; Returns: Nothing
; Side Effects: ACCA is changed

; Algorithm:
; First, copy the contents of PORTA into a temporary location TEMP and clear
;     the sensor bits 2,3,4 in the TEMP to zeros by ANDing it with the mask
;     11100011. The zeros in the mask clear the corresponding bits in the
;     TEMP. The 1’s have no effect.
; Next, move the sensor selection number left two positions to align it
;     with the correct bit positions for sensor selection.
; Clear all the bits around the (shifted) sensor number by ANDing it with
;   the mask 00011100. The zeros in the mask clear everything except
;   the sensor number.
; Now we can combine the sensor number with the TEMP using logical OR.
;   The effect is that only bits 2,3,4 are changed in the TEMP, and these
;   bits now correspond to the sensor number.
; Finally, save the TEMP to the hardware.

SELECT_SENSOR             PSHA                                    ; Save the sensor number for the moment
                  
                          LDAA          PORTA                     ; Clear the sensor selection bits to zeros
                          ANDA          #%11100011                ;
                          STAA          TEMP                      ; and save it into TEMP
                          
                          PULA                                    ; Get the sensor number
                          ASLA                                    ; Shift the selection number left, twice
                          ASLA ;
                          ANDA          #%00011100                ; Clear irrelevant bit positions
                          
                          ORAA          TEMP                      ; OR it into the sensor bit positions
                          STAA          PORTA                     ; Update the hardware
                          RTS

;---------------------------------------------------------------------------
; Display Sensor Readings
;
; Passed: Sensor values in RAM locations SENSOR_LINE through SENSOR_STBD.
; Returns: Nothing
; Side: Everything

; This routine writes the sensor values to the LCD. It uses the ’shadow buffer’ approach.
;   The display buffer is built by the display controller routine and then copied in its
;   entirety to the actual LCD display. Although simpler approaches will work in this
;   application, we take that approach to make the code more re-useable.
; It’s important that the display controller not write over other information on the
;   LCD, so writing the LCD has to be centralized with a controller routine like this one.
; In a more complex program with additional things to display on the LCD, this routine
;   would be extended to read other variables and place them on the LCD. It might even
;   read some ’display select’ variable to determine what should be on the LCD.

; For the purposes of this routine, we’ll put the sensor values on the LCD
;   in such a way that they (sort of) mimic the position of the sensors, so
;   the display looks like this:
;     01234567890123456789
;     ___FF_______________
;     PP_MM_SS_LL_________

; Where FF is the front sensor, PP is port, MM is mid, SS is starboard and
;   LL is the line sensor.

; The corresponding addresses in the LCD buffer are defined in the following
; equates (In all cases, the display position is the MSDigit).

DP_FRONT_SENSOR           EQU           TOP_LINE+3
DP_PORT_SENSOR            EQU           BOT_LINE+0
DP_MID_SENSOR             EQU           BOT_LINE+3
DP_STBD_SENSOR            EQU           BOT_LINE+6
DP_LINE_SENSOR            EQU           BOT_LINE+9

DISPLAY_SENSORS           LDAA          SENSOR_BOW                ; Get the FRONT sensor value
                          JSR           BIN2ASC                   ; Convert to ascii string in D
                          LDX           #DP_FRONT_SENSOR          ; Point to the LCD buffer position
                          STD           0,X                       ; and write the 2 ascii digits there
                          
                          LDAA          SENSOR_PORT               ; Repeat for the PORT value
                          JSR           BIN2ASC
                          LDX           #DP_PORT_SENSOR
                          STD           0,X
                          
                          LDAA          SENSOR_MID                ; Repeat for the MID value
                          JSR           BIN2ASC
                          LDX           #DP_MID_SENSOR
                          STD           0,X
                          
                          LDAA          SENSOR_STBD               ; Repeat for the STARBOARD value
                          JSR           BIN2ASC
                          LDX           #DP_STBD_SENSOR
                          STD           0,X
                          
                          LDAA          SENSOR_LINE               ; Repeat for the LINE value
                          JSR           BIN2ASC
                          LDX           #DP_LINE_SENSOR
                          STD           0,X
                          
                          LDAA          #CLEAR_HOME               ; Clear the display and home the cursor
                          JSR           cmd2LCD                   ;         "
                          
                          LDY           #40                       ; Wait 2 ms until "clear display" command is complete
                          JSR           del_50us
                          
                          LDX           #TOP_LINE                 ; Now copy the buffer top line to the LCD
                          JSR           putsLCD
                          
                          LDAA          #LCD_SEC_LINE             ; Position the LCD cursor on the second line
                          JSR           LCD_POS_CRSR
                          
                          LDX           #BOT_LINE                 ; Copy the buffer bottom line to the LCD
                          JSR           putsLCD
                          RTS
                  
;---------------------------------------------------------------------------
; Binary to ASCII
;
; Converts an 8 bit binary value in ACCA to the equivalent ASCII character 2
;   character string in accumulator D
; Uses a table-driven method rather than various tricks.

; Passed: Binary value in ACCA
; Returns: ASCII Character string in D
; Side Fx: ACCB is destroyed

; HEX_TABLE is initialized in VARIABLES/DATA SECTION

BIN2ASC                   PSHA                                    ; Save a copy of the input number on the stack
                          TAB                                     ; and copy it into ACCB
                          ANDB          #%00001111                ; Strip off the upper nibble of ACCB
                          CLRA                                    ; D now contains 000n where n is the LSnibble
                          ADDD          #HEX_TABLE                ; Set up for indexed load
                          XGDX
                          LDAA          0,X                       ; Get the LSnibble character
                          
                          PULB                                    ; Retrieve the input number into ACCB
                          PSHA                                    ; and push the LSnibble character in its place
                          RORB                                    ; Move the upper nibble of the input number
                          RORB                                    ; into the lower nibble position.
                          RORB
                          RORB
                          ANDB          #%00001111                ; Strip off the upper nibble
                          CLRA                                    ; D now contains 000n where n is the MSnibble
                          ADDD          #HEX_TABLE                ; Set up for indexed load
                          XGDX
                          LDAA          0,X                       ; Get the MSnibble character into ACCA
                          PULB                                    ; Retrieve the LSnibble character into ACCB
                          RTS

;---------------------------------------------------------------------------
; Routines to control the Liquid Crystal Display

;---------------------------------------------------------------------------
; Initialize the LCD

openLCD                   LDY           #2000                     ; Wait 100 ms for LCD to be ready
                          JSR           del_50us                  ;         "
                          LDAA          #INTERFACE                ; Set 8-bit data, 2-line display, 5x8 font
                          JSR           cmd2LCD                   ;         "
                          LDAA          #CURSOR_OFF               ; Display on, cursor off, blinking off
                          JSR           cmd2LCD                   ;         "
                          LDAA          #SHIFT_OFF                ; Move cursor right (address increments, no char. shift)
                          JSR           cmd2LCD                   ;         "
                          LDAA          #CLEAR_HOME               ; Clear the display and home the cursor
                          JSR           cmd2LCD                   ;         "
                          LDY           #40                       ; Wait 2 ms until "clear display" command is complete
                          JSR           del_50us                  ;         "
                          RTS

;---------------------------------------------------------------------------
; Send a command in accumulator A to the LCD

cmd2LCD:                  BCLR          LCD_CNTR,LCD_RS           ; select the LCD Instruction Register 
                          JSR           dataMov                   ; send data to IR or DR of the LCD
                          RTS

;---------------------------------------------------------------------------
; Send a character in accumulator in A to LCD

putcLCD                   BSET          LCD_CNTR,LCD_RS           ; select the LCD Data register (DR)
                          JSR           dataMov                   ; send data to to IR or DR of the LCD
                          RTS
                      
;---------------------------------------------------------------------------
; Send a NULL-terminated string pointed to by X

putsLCD                   LDAA          1,X+                      ; get one character from the string
                          BEQ           donePS                    ; reach NULL character?
                          JSR           putcLCD
                          BRA           putsLCD
donePS                    RTS

           
;---------------------------------------------------------------------------
; Send data to the LCD IR or DR depending on the RS signal

dataMov                   BSET          LCD_CNTR,LCD_E            ; pull the LCD E-sigal high
                          STAA          LCD_DAT                   ; send the upper 4 bits of data to LCD
                          BCLR          LCD_CNTR,LCD_E            ; pull the LCD E-signal low to complete the write oper.
                          LSLA                                    ; match the lower 4 bits with the LCD data pins
                          LSLA                                    ; -"-
                          LSLA                                    ; -"-
                          LSLA                                    ; -"-
                          BSET          LCD_CNTR,LCD_E            ; pull the LCD E signal high
                          STAA          LCD_DAT                   ; send the lower 4 bits of data to LCD
                          BCLR          LCD_CNTR,LCD_E            ; pull the LCD E-signal low to complete the write oper.
                          LDY           #1                        ; adding this delay will complete the internal
                          JSR           del_50us                  ; operation for most instructions
                          RTS

initAD                    MOVB          #$C0,ATDCTL2              ; power up AD, select fast flag clear
                          JSR           del_50us                  ; wait for 50 us
                          MOVB          #$00,ATDCTL3              ; 8 conversions in a sequence
                          MOVB          #$85,ATDCTL4              ; res=8, conv-clks=2, prescal=12
                          BSET          ATDDIEN,$0C               ; configure pins AN03,AN02 as digital inputs
                          RTS


;---------------------------------------------------------------------------
; Position the Cursor
;
; This routine positions the display cursor in preparation for the writing
;   of a character or string.
; For a 20x2 display:
; The first line of the display runs from 0 .. 19.
; The second line runs from 64 .. 83.

; The control instruction to position the cursor has the format
;         1aaaaaaa
; where aaaaaaa is a 7 bit address.

; Passed: 7 bit cursor Address in ACCA
; Returns: Nothing
; Side Effects: None

LCD_POS_CRSR              ORAA          #%10000000                ; Set the high bit of the control word
                          JSR           cmd2LCD                   ; and set the cursor address
                          RTS

;---------------------------------------------------------------------------
; Other utility subroutines from previous labs

;*****************************************************************
initLCD                   BSET          DDRB,%11111111            ; configure pins PS7,PS6,PS5,PS4 for output
                          BSET          DDRJ,%11000000            ; configure pins PE7,PE4 for output
                          LDY           #2000                     ; wait for LCD to be ready
                          JSR           del_50us                  ; -"-
                          LDAA          #$28                      ; set 4-bit data, 2-line display
                          JSR           cmd2LCD                   ; -"-
                          LDAA          #$0C                      ; display on, cursor off, blinking off
                          JSR           cmd2LCD                   ; -"-
                          LDAA          #$06                      ; move cursor right after entering a character
                          JSR           cmd2LCD                   ; -"-
                          RTS

;*****************************************************************
;* Clear display and home cursor *
;*****************************************************************
clrLCD                    LDAA          #$01                      ; clear cursor and return to home position
                          JSR           cmd2LCD                   ; -"-
                          LDY           #40                       ; wait until "clear cursor" command is complete
                          JSR           del_50us                  ; -"-
                          RTS

;---------------------------------------------------------------------------
; 50 Microsecond Delay
del_50us:                 PSHX                                    ; 2 E-clk
eloop:                    LDX           #30                       ; 2 E-clk -
iloop:                    PSHA                                    ; 2 E-clk |
                          PULA                                    ; 3 E-clk |
                          PSHA                                    ; 2 E-clk | 50us
                          PULA                                    ; 3 E-clk |
                          PSHA                                    ; 2 E-clk |
                          PULA                                    ; 3 E-clk |
                          PSHA                                    ; 2 E-clk |
                          PULA                                    ; 3 E-clk |
                          PSHA                                    ; 2 E-clk |
                          PULA                                    ; 3 E-clk |
                          PSHA                                    ; 2 E-clk |
                          PULA                                    ; 3 E-clk |
                       
                          NOP                                     ; 1 E-clk |
                          NOP                                     ; 1 E-clk |
                          DBNE          X,iloop                   ; 3 E-clk -
                          DBNE          Y,eloop                   ; 3 E-clk
                          PULX                                    ; 3 E-clk
                          RTS                                     ; 5 E-clk
                        
;---------------------------------------------------------------------------
; Integer to BCD Conversion Routine

int2BCD                   XGDX                                    ; Save the binary number into .X
                          LDAA          #0                        ; Clear the BCD_BUFFER
                          STAA          TEN_THOUS
                          STAA          THOUSANDS
                          STAA          HUNDREDS
                          STAA          TENS
                          STAA          UNITS
                          STAA          BCD_SPARE
                          STAA          BCD_SPARE+1
                          
                          CPX           #0                        ; Check for a zero input
                          BEQ           CON_EXIT                  ; and if so, exit

                          XGDX                                    ; Not zero, get the binary number back to .D as dividend
                          LDX           #10                       ; Setup 10 (Decimal!) as the divisor
                          IDIV                                    ; Divide: Quotient is now in .X, remainder in .D
                          STAB          UNITS                     ; Store remainder
                          CPX           #0                        ; If quotient is zero,
                          BEQ           CON_EXIT                  ; then exit

                          XGDX                                    ; swap first quotient back into .D
                          LDX           #10                       ; and setup for another divide by 10
                          IDIV
                          STAB          TENS
                          CPX           #0
                          BEQ           CON_EXIT

                          XGDX                                    ; Swap quotient back into .D
                          LDX           #10                       ; and setup for another divide by 10
                          
                          IDIV
                          STAB          HUNDREDS
                          CPX           #0
                          BEQ           CON_EXIT

                          XGDX                                    ; Swap quotient back into .D
                          LDX           #10                       ; and setup for another divide by 10
                          IDIV
                          STAB          THOUSANDS
                          CPX           #0
                          BEQ           CON_EXIT

                          XGDX                                    ; Swap quotient back into .D
                          LDX           #10                       ; and setup for another divide by 10
                          IDIV
                          STAB          TEN_THOUS

CON_EXIT                  RTS                                     ; We're done the conversion

;---------------------------------------------------------------------------
; BCD to ASCII Conversion Routine

BCD2ASC                   LDAA          #0                        ; Initialize the blanking flag
                          STAA          NO_BLANK

C_TTHOU                   LDAA          TEN_THOUS                 ; Check the 'ten_thousands' digit
                          ORAA          NO_BLANK    
                          BNE           NOT_BLANK1

ISBLANK1                  LDAA          #' '                      ; It's blank
                          STAA          TEN_THOUS                 ; so store a space
                          BRA           C_THOU                    ;  and check the ?thousands? digit

NOT_BLANK1                LDAA          TEN_THOUS                 ; Get the ?ten_thousands? digit
                          ORAA          #$30                      ;  Convert to ascii
                          STAA          TEN_THOUS
                          LDAA          #$1                       ; Signal that we have seen a ?non-blank? digit
                          STAA          NO_BLANK

C_THOU                    LDAA          THOUSANDS                 ; Check the thousands digit for blankness
                          ORAA          NO_BLANK                  ; If it's blank and 'no-blank' is still zero
                          BNE           NOT_BLANK2

ISBLANK2                  LDAA          #' '                      ; Thousands digit is blank
                          STAA          THOUSANDS                 ; so store a space
                          BRA           C_HUNS                    ; and check the hundreds digit

NOT_BLANK2                LDAA          THOUSANDS                 ; (similar to 'ten_thousands' case)
                          ORAA          #$30
                          STAA          THOUSANDS
                          LDAA          #$1
                          STAA          NO_BLANK

C_HUNS                    LDAA          HUNDREDS                  ; Check the hundreds digit for blankness
                          ORAA          NO_BLANK                  ; If it's blank and 'no-blank' is still zero
                          BNE           NOT_BLANK3

ISBLANK3                  LDAA          #' '                      ; Hundreds digit is blank
                          STAA          HUNDREDS                  ; so store a space
                          BRA           C_TENS                    ; and check the tens digit

NOT_BLANK3                LDAA          HUNDREDS                  ; (similar to 'ten_thousands' case)
                          ORAA          #$30
                          STAA          HUNDREDS
                          LDAA          #$1
                          STAA          NO_BLANK

C_TENS                    LDAA          TENS                      ; Check the tens digit for blankness
                          ORAA          NO_BLANK                  ; If it's blank and 'no-blank' is still zero
                          BNE           NOT_BLANK4  ;

ISBLANK4                  LDAA          #' '                      ; Tens digit is blank
                          STAA          TENS                      ; so store a space
                          BRA           C_UNITS                   ; and check the units digit

NOT_BLANK4                LDAA          TENS                      ; (similar to 'ten_thousands' case)
                          ORAA          #$30
                          STAA          TENS

C_UNITS                   LDAA          UNITS                     ; No blank check necessary, convert to ascii.
                          ORAA          #$30
                          STAA          UNITS

                          RTS                                     ; We're done
            
;---------------------------------------------------------------------------
; Enable Timer Overflow

ENABLE_TOF                LDAA          #%10000000
                          STAA          TSCR1                     ; Enable TCNT
                          STAA          TFLG2                     ; Clear TOF
                          LDAA          #%10000100                ; Enable TOI and select prescale factor equal to 16
                          STAA          TSCR2
                          RTS

;---------------------------------------------------------------------------
; Timer Overflow Interrupt Service Routine

TOF_ISR                   INC           TOF_COUNTER
                          LDAA          #%10000000                ; Clear
                          STAA          TFLG2                     ; TOF
                          RTI
            
;---------------------------------------------------------------------------
; Display Update Routine (Battery Voltage + Current State)

UPDT_DISPL                MOVB          #$90,ATDCTL5              ; R-just., uns., sing. conv., mult., ch=0, start
                          BRCLR         ATDSTAT0,$80,*            ; Wait until the conver. seq. is complete
                          
              	                                                  ; Display the battery voltage
                          LDAA          ATDDR0L                   ; Load the ch0 result - battery volt - into A
                          LDAB          #39                       ; AccB = 39
                          MUL                                     ; AccD = 1st result x 39
                          ADDD          #600                      ; AccD = 1st result x 39 + 600
                          
                          JSR           int2BCD
                          JSR           BCD2ASC
                          
                          LDAA          #$8F                      ; move LCD cursor to the 1st row, end of msg1
                          JSR           cmd2LCD                   ;         "
                          
                          LDAA          TEN_THOUS                 ; output the TEN_THOUS ASCII character
                          JSR           putcLCD                   ;         "
                          
                          LDAA          THOUSANDS                 ;output the THOUSANDS ASCII character
                          JSR           putcLCD                   ;         "
                          
                          LDAA          #$2E                      ;output the '.' character
                          JSR           putcLCD                   ;         "
                          
                          LDAA          HUNDREDS                  ;output the HUNDREDS ASCII character
                          JSR           putcLCD                   ;         "
                                                                  ;-------------------------
                          LDAA          #$C6                      ; Move LCD cursor to the 2nd row, end of msg2
                          JSR           cmd2LCD                   ;
                          LDAB          CRNT_STATE                ; Display current state
                          LSLB                                    ;         "
                          LSLB                                    ;         "
                          LSLB                                    ;         "
                          LDX           #tab                      ;         "
                          ABX                                     ;         "
                          JSR           putsLCD                   ;         "
                          RTS            
                                                
;*****************************************************************
;*                                                               *
;*                      Interrupt Vectors                        *
;*                                                               *
;*****************************************************************
                          ORG           $FFFE
                          DC.W          Entry                     ; Reset Vector
                          
                          ORG           $FFDE
                          DC.W          TOF_ISR                   ; Timer Overflow Interrupt Vector
