;
; TimerTest.asm
;
; Created: 11/1/2024 8:16:56 PM
; Author : szlsl
;


; Replace with your application code
.include "m2560def.inc"

.dseg
timeCounter:
	.byte 2
SecondCoutner:
	.byte 2

.cseg
.org 0x0000
	jmp RESET
.org INT1addr
	jmp EXIT_INT1
	jmp EXIT_INT2
.org OVF0addr
	jmp Timer0OVF

RESET:




Timer0OVF:
    push temp ; Prologue starts.
    in temp, SREG
    push temp ; Prologue starts.
    push Yh ; Save all conflict registers in the prologue.
    push YL
    push r25
    push r24 ; Prologue ends.
    ldi YL, low(TempCounter) ; Load the address of the temporary
    ldi YH, high(TempCounter) ; counter.
    ld r24, Y+ ; Load the value of the temporary counter.
    ld r25, Y
    adiw r25:r24, 1 

    cpi r24, low(1000) ; Check if (r25:r24)=1000
    brne NotSecond
    cpi r25, high(1000)
    brne NotSecond
    
    do_lcd_command 0b00000001

    subi unit, -'0'                 ; add the value of every position to '0' to get speed
    subi ten, -'0'
    subi hundred, -'0'

    do_lcd_data hundred
    do_lcd_data ten
    do_lcd_data unit

    ldi r30, 'r'                    ; display "rps"
    do_lcd_data r30 
    ldi r30, 'p'
    do_lcd_data r30 
    ldi r30, 's'
    do_lcd_data r30 

    clr ten
    clr hundred
    clr unit

    Clear TempCounter
    rjmp endif

NotSecond:
    st Y, r25 ; Store the value of the temporary counter.
    st -Y, r24
endif:
    pop r24 ; Epilogue starts;
    pop r25 ; Restore all conflict registers from the stack.
    pop YL
    pop YH
    pop temp
    out SREG, temp
    pop temp
    reti
