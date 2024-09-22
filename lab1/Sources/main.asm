;********************************************************************
;*       Assignment: Multiplication Program                         *
;*                                                                  *
;* This program executes unsigned multiplication of two 8-bit       *
;* numbers, MULTIPLICAND and MULTIPLIER and leaves the reuslt in    *
;* the 16-bit memory location 'PRODUCT'.                            *
;* Author: Alvi Alam                                                *
;********************************************************************
; export symbols
            XDEF Entry, _Startup          ; export ‘Entry’ symbol
            ABSENTRY Entry                ; for absolute assembly: mark
                                          ; this as applicat. entry point
; Include derivative-specific definitions
            INCLUDE 'derivative.inc'
;********************************************************************
;* Code section                                                     *
;********************************************************************
              ORG   $3000
            
MULTIPLICAND  FCB   05                    ; First Number
MULTIPLIER    FCB   03                    ; Second Number
PRODUCT       RMB    2                    ; Result of Multiplication (2 bytes of storage due to 16-bit result)
;********************************************************************
;* The actual program starts here                                   *
;********************************************************************
            ORG   $4000
Entry:
_Startup:
            LDAA MULTIPLICAND             ; Get the first number into ACCA
            LDAB MULTIPLIER               ; Get the second number into ACCB
            MUL                           ; Multiply the 8-bit values in ACCA and ACCB
            STD  PRODUCT                  ; and store the product in ACCD
            SWI                           ; break to the monitor 

;********************************************************************
;* Interrupt Vectors                                                *
;********************************************************************
            ORG $FFFE
            FDB Entry ; Reset Vector