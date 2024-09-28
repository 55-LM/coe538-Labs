;*****************************************************************
;*      COE538 Lab 2 Assignment 1: Part 1, 2 and 3               *
;*                                                               *
;* The routines of all the exercises are contained within this   *
;* program. Comment out the every part excpet the one needed to  *
;* run                                                           *
;* Author: Alvi Alam                                             *
;*****************************************************************

; export symbols
            XDEF Entry, _Startup            ; export 'Entry' symbol
            ABSENTRY Entry        ; for absolute assembly: mark this as application entry point


; Include derivative-specific definitions 
		INCLUDE 'derivative.inc' 



;********************************************************************
;* Code section                                                           *
;********************************************************************
            ORG   $4000


Entry:
_Startup:
     
;********************************************************************
;* Part 1                                                           *
;********************************************************************     

;LDAA #$FF                       ; ACCA = $FF
;            STAA DDRH                       ; Config. Port H for output
;            STAA PERT                       ; Enab. pull-up res. of Port T
;      
;Loop:       LDAA PTT                        ; Read Port T
;            STAA PTH                        ; Display SW1 on LED1 connected to Port H
;            BRA  Loop                       ; Loop
    
;********************************************************************
;* Part 2                                                           *
;********************************************************************

;BSET  DDRP,%11111111            ; Configure Port P for output (LED2 cntrl)
;            BSET  DDRE,%00010000            ; Configure pin PE4 for output (enable bit)
;            BCLR  PORTE,%00010000           ; Enable keypad
;                                   
;Loop:       LDAA  PTS                       ; Read a key code into AccA
;            LSRA                            ; Shift right AccA
;            LSRA                            ; -"-
;            LSRA                            ; -"-
;            LSRA                            ; -"-
;            STAA  PTP                       ; Output AccA content to LED2
;            BRA   Loop                      ; Loop
                     
;********************************************************************
;* Part 3                                                           *
;********************************************************************
            BSET DDRP, %11111111            ; Config. Port P for output
            LDAA  #%10000000                ; Prepare to drive PP7 high

MainLoop:   STAA  PTP                       ; Drive PP7
            LDX   #$1FFF                    ; Initialize the loop counter

Delay:      DEX                             ; Decrement the loop counter
            BNE   Delay                     ; If not done, continue to loop
            EORA  #%10000000                ; Toggle the MSB of AccA
            BRA   MainLoop                  ; Go to MainLoop
           

;**************************************************************
;*                 Interrupt Vectors                          *
;**************************************************************
            ORG   $FFFE
            DC.W  Entry           ; Reset Vector
