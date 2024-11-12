; Test code from Hui Wu
; Board settings: 1. Connect LCD data pins D0-D7 to PORTF0-7.
; 2. Connect the four LCD control pins BE-RS to PORTA4-7.

.include "m2560def.inc"
.def temp3 = r16								; index of string array
.def temp4 = r17								; index of name
.def input = r20
.def temp1 = r22
.def temp2 = r23

.def row    =r24								; current row number
.def col    =r25								; current column number
.def rmask   =r18								; mask for current row
.def cmask	=r19								; mask for current column

.equ PORTLDIR =0xF0								; use PortL for input/output from keypad: PL7-4, output, PL3-0, input
.equ INITCOLMASK = 0xEF							; scan from the leftmost column, the value to mask output
.equ INITROWMASK = 0x01							; scan from the bottom row
.equ ROWMASK  =0x0F								; low four bits are output from the keypad. This value mask the high 4 bits.

.equ MAX_LENGTH = 15							; name max length
.equ BUFFER_SIZE = 16							; buffer size
.equ ARRAY_SIZE = 256							; string array size

.equ TONE_OFF = 0            ; ????
.equ TONE_BEEP_BEEP = 1      ; 1????1?????? (Beep-beep)
.equ TONE_BIP_BIP = 2        ; 0.5????0.5?????? (Bip-bip)
.equ KEYBOARD_TIMER = 100
.dseg
buffer_index:									
	.byte 1
arr_tail: 
	.byte 1
buffer_address:
	.byte BUFFER_SIZE
string_arr_address:
	.byte ARRAY_SIZE
tail_num_unit:									; current patient number when storing patient
	.byte 1
tail_num_ten:
	.byte 1
tail_num_hundred:
	.byte 1

TempCounter:
    .byte 2
SecondCounter:
	.byte 2 


tone_count: 
	.byte 1          ; ?????????
pb0_toggle: 
	.byte 1          ; PB0 ??????
pb1_toggle:
	.byte 1          ; pb1 ??????


.cseg 
.org 0x0000
    rjmp RESET               ; Reset vector

.org INT0addr
    rjmp BUTTON_ISR_0    ; INT0 interrupt vector, jumps to button ISR

.org INT1addr
    rjmp BUTTON_ISR_1    ; INT1 ?????PB1 ????

jmp RESET
key_map:
	.db "ABC0DEF0GHI0JKL0MNO0PQRSTUV0WXYZ"

.macro Clear
	ldi YL, low(@0) ; load the memory address to Y
	ldi YH, high(@0)
	clr temp1
	st Y+, temp1 ; clear the two bytes at @0 in SRAM
	st Y, temp1
.endmacro

.macro storeChar
	push temp1
	push ZL
	push ZH

	lds temp1, buffer_index
    cpi temp1, MAX_LENGTH
    brge endStore								; Ignore if name length is over 15
	clr r0
    ldi ZL, low(buffer_address)
    ldi ZH, high(buffer_address)
    add ZL, temp1
    adc ZH, r0
    st Z, @0
    inc temp1										; buffer_index + 1
	sts buffer_index, temp1
endStore:
	pop ZH
	pop ZL
	pop temp1
.endmacro

.macro ld_addr									; load value from @1 register to @0 address
	push ZL
	push ZH
	ldi ZL, low(@0)
	ldi ZH, high(@0)
	ld @1, Z
	pop ZH
	pop ZL
.endmacro

.macro st_addr									; store value from @1 register to @0 address
	push ZL
	push ZH
	ldi ZL, low(@0)
	ldi ZH, high(@0)
	st Z, @1
	pop ZH
	pop ZL
.endmacro
	
.macro do_lcd_command
	push temp1
	ldi temp1, @0
	rcall lcd_command
	rcall lcd_wait
	pop temp1
.endmacro

.macro do_lcd_data_register
	push temp1
	mov temp1, @0
	rcall lcd_data
	rcall lcd_wait
	pop temp1
.endmacro

.macro do_lcd_data_immediate
	push temp1
	ldi temp1, @0
	rcall lcd_data
	rcall lcd_wait
	pop temp1
.endmacro

.macro toInt
	mov @0, input
	subi @0, 48
.endmacro

.macro toChar
	cpi @0, 10
	brlo digit
	subi @0, 10
	subi @0, -'A'
	rjmp endToChar
	digit:
	subi @0, -'0'
	endToChar:
.endmacro

.macro clear_line_macro								; macro for clearing LCD 2nd line
	push temp1
	do_lcd_command 0b11000000						; move cursor to the left of the 2nd line
    ldi temp1, 16
repeat_lcd_data:
    do_lcd_data_immediate ' '
    dec temp1
    brne repeat_lcd_data							; if temp1 has been reduced to 0, jump out of loop
	do_lcd_command 0b11000000						; move cursor to the left of the 2nd line
	pop temp1
.endmacro

; macro for clearing buffer_index
.macro clear_buffer_index
	push temp1
    clr temp1
	st_addr buffer_index, temp1
	pop temp1
.endmacro
	
RESET:
	; ??? pb0_toggle ? 0???????Beep
    ldi r16, 0
    sts pb0_toggle, r16
	sts pb1_toggle, r16    ; ??? pb1_toggle ? 0????????PB1

	;???LED
	ser r16
	out DDRC, r16
	clr r16
	out PORTC, r16
	;???PORTK?PIN0 = motor, PIN1-2 = LED????
	sts DDRK, r16

    ; ??? PB0 ? PB1 ??????????
    cbi DDRD, 0                
    sbi PORTD, 0              
    cbi DDRD, 1
    sbi PORTD, 1              

    ; ????
    ; INT0?PB0?????????????
    ldi r16, (1 << ISC01)
    sts EICRA, r16

    ; INT1?PB1?????????????
    ldi r16, (1 << ISC11)
    sts EICRA+1, r16

    ; ?? INT0 ? INT1 ??
    sbi EIMSK, INT0
    sbi EIMSK, INT1

	clr temp1
	st_addr buffer_index, temp1							; re-init index of name to 0
	st_addr arr_tail, temp1								; re-init index of string array to 0
	st_addr tail_num_unit, temp1						; re-init tail patient number to 0
	st_addr tail_num_ten, temp1
	st_addr tail_num_hundred, temp1

	;ldi temp1, 20
	;st_addr patient_num, temp1							; re-init patient number to 0
				
	ldi temp1, low(RAMEND)								; re-init stack pointer
	out SPL, temp1
	ldi temp1, high(RAMEND)
	out SPH, temp1

	ser temp1
	out DDRF, temp1
	out DDRA, temp1
	clr temp1
	out PORTF, temp1
	out PORTA, temp1
	do_lcd_command 0b00111000	; 2x5x7
	rcall sleep_5ms
	do_lcd_command 0b00111000	; 2x5x7
	rcall sleep_1ms
	do_lcd_command 0b00111000	; 2x5x7
	do_lcd_command 0b00111000	; 2x5x7
	do_lcd_command 0b00001000	; display off
	do_lcd_command 0b00000001	; clear display
	do_lcd_command 0b00000110	; increment, no display shift
	do_lcd_command 0b00001111	; Cursor on, bar, blink

	ldi temp1, PORTLDIR			; columns are outputs, rows are inputs
	sts	DDRL, temp1

	ser temp1 
	out DDRC, temp1				; set lcd output
	rjmp display_mode

display_mode:
	do_lcd_command 0b00000001	; clear display
	do_lcd_command 0b00000110	; increment, no display shift
	do_lcd_data_immediate 'N'
	do_lcd_data_immediate 'e'
	do_lcd_data_immediate 'x'
	do_lcd_data_immediate 't'
	do_lcd_data_immediate ' '
	do_lcd_data_immediate 'P'
	do_lcd_data_immediate 'a'
	do_lcd_data_immediate 't'
	do_lcd_data_immediate 'i'
	do_lcd_data_immediate 'e'
	do_lcd_data_immediate 'n'
	do_lcd_data_immediate 't'
	do_lcd_data_immediate ':'
	do_lcd_command 0b11000000	; move cursor to the left of the 2nd line
READ_LOOP_1:
	rcall readIn
	rcall sleep_250ms
	cpi input, 'A'
	breq entry_mode_jmp
	rjmp READ_LOOP_1
entry_mode_jmp:
	jmp entry_mode
display_mode_jmp:
	jmp display_mode
BUTTON_ISR_0:
	; ???LCD????display????
	; ...
    ; PB0 ?????????
    lds r16, pb0_toggle
    cpi r16, 0
    breq Beep_tone      ; ???????? PB0??? Beep-beep ??

    ; ???????

    rjmp EXIT_ISR
jmp_EXIT_ISR:
	jmp EXIT_ISR

BUTTON_ISR_1:
    ; PB1 ???3 ? Beeeep ? 5 ? Beep-beep??????? Bip-bip
	;3?????
	lds r16, pb1_toggle
	cpi r16, 0       ; pb1_toggle = 0 ??????PB1
	brne jmp_EXIT_ISR
	ldi r16, 0xFF
    sts PORTK, r16
	rcall flash_once
	rcall flash_once
	rcall flash_once
	ldi r16, 0
    sts PORTK, r16
	rjmp Beep_tone
flash_once:
	ldi r16, 0b10101010
	out PORTC, r16
	rcall sleep_500ms
	ldi r16, 0
	out PORTC, r16
	rcall sleep_500ms
	ret

Beep_tone:
	sei 
	ldi r16, 1
	sts pb0_toggle, r16
	sts pb1_toggle, r16       ; set pb1_toggle ? 1?????PB1????
	ldi r16, 5                ; ??????5
	sts tone_count, r16       

    ; Beep-beep ?????1????1???
Beep_loop:
	; ??????????
	lds r16, pb0_toggle
    cpi r16, 0
    breq EXIT_ISR 

    lds r16, tone_count
    cpi r16, 0
    breq Bip_tone    ; ?????0???? Bip-bip
    ; ????
    ldi r16, 0b11111111
    sts PORTK, r16
	ldi r16, 0xFF
	out PORTC, r16
    rcall sleep_1s
	  
	; ??????????
	lds r16, pb0_toggle
    cpi r16, 0
    breq EXIT_ISR 

    ; ????
    ldi r16, 0
    sts PORTK, r16
	ldi r16, 0
	out PORTC, r16
    rcall sleep_1s
    ; ????
    lds r16, tone_count
    dec r16
    sts tone_count, r16
    rjmp Beep_loop
Bip_tone:
	; ??????????
	lds r16, pb0_toggle
    cpi r16, 0
    breq EXIT_ISR 

    ; ????
    ldi r16, 0xFF
    sts PORTK, r16
	ldi r16, 0xFF
	out PORTC, r16
    rcall sleep_500ms

	; ??????????
	lds r16, pb0_toggle
    cpi r16, 0
    breq EXIT_ISR 

    ; ????
    ldi r16, 0
    sts PORTK, r16
	ldi r16, 0
	out PORTC, r16
    rcall sleep_500ms
    rjmp Bip_tone
    
EXIT_ISR:
	; ?????LED
	ldi r16, 0
    sts PORTK, r16
	ldi r16, 0
	out PORTC, r16
	ldi r16, 0                ; ?? PB0 ????
    sts pb0_toggle, r16
	sts pb1_toggle, r16       ; ?? PB1 ??
	; ???LCD??entry?????
	; ...

    reti                      ; ????

Timer0OVF:
    push temp1 ; Prologue starts.
    in temp1, SREG
    push temp1 ; Prologue starts.
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
    Clear TempCounter
 	ldi YL, low(SecondCounter) ; Load the address of the second
 	ldi YH, high(SecondCounter) ; counter.
 	ld r24, Y+ ; Load the value of the second counter.
 	ld r25, Y
 	adiw r25:r24, 1 ; Increase the second counter by one.
    rjmp endif

NotSecond:
    st Y, r25 ; Store the value of the temporary counter.
    st -Y, r24
endif:
    pop r24 ; Epilogue starts;
    pop r25 ; Restore all conflict registers from the stack.
    pop YL
    pop YH
    pop temp1
    out SREG, temp1
    pop temp1
    reti


entry_mode:
	do_lcd_command 0b00000001
	do_lcd_data_immediate 'E'
	do_lcd_data_immediate 'n'
	do_lcd_data_immediate 't'
	do_lcd_data_immediate 'e'
	do_lcd_data_immediate 'r'
	do_lcd_data_immediate ' '
	do_lcd_data_immediate 'F'
	do_lcd_data_immediate 'i'
	do_lcd_data_immediate 'r'
	do_lcd_data_immediate 's'
	do_lcd_data_immediate 't'
	do_lcd_data_immediate ' '
	do_lcd_data_immediate 'N'
	do_lcd_data_immediate 'a'
	do_lcd_data_immediate 'm'
	do_lcd_data_immediate 'e'
	do_lcd_command 0b11000000

whileReadIn:
	rcall readIn
	rcall sleep_250ms
	cpi input, 'B'
	brne continueCheck0
	jmp delete
	continueCheck0:
	cpi input, 'C'
	brne continueCheck1 
	jmp clear_line
	continueCheck1:
	cpi input, 'D'
	brne continueCheck2
	jmp confirm_input
	continueCheck2:
	cpi input, '2'
	brlo whileReadIn
	cpi input, 58
	brsh whileReadIn			; 

	clr temp1
	mov temp3, input
	do_lcd_command 0b00000110	; cursor move right after each input
	rcall load_char_from_map
	do_lcd_data_register temp2
	do_lcd_command 0b00010000	; move cursor to left
	storeChar temp2
	ldi temp4, 5
READ_LOOP_2:
	rcall readIn
	rcall sleep_250ms
	cp input, temp3
	breq sameButton
	jmp notSameButton
sameButton:
	ldi temp4, 10
	inc temp1
	rcall load_char_from_map
	out PORTC, temp1
	do_lcd_data_register temp2
	do_lcd_command 0b00010000
	rcall backspace_buffer
	storeChar temp2
notSameButton:
	dec temp4
	cpi temp4, 0
	brne READ_LOOP_2
	do_lcd_command 0b00010100
	jmp whileReadIn


delete:
	rcall backspace_buffer
	do_lcd_command 0b00000100
	do_lcd_data_immediate ' '
	do_lcd_data_immediate ' '
	do_lcd_command 0b00010100
	do_lcd_command 0b00000110	; backspace on LCD
	jmp whileReadIn

clear_line:
	clear_buffer_index			; clear buffer_index to 0
	clear_line_macro			; clearing LCD 2nd line
	jmp whileReadIn

confirm_input:
	lds temp3, buffer_index; load buffer_index in temp3
	lds temp4, arr_tail		; load arr_tail in temp4
	clr r0						; load initial string_arr_address + arr_tail in Y
	ldi YL, low(string_arr_address)
	ldi YH, high(string_arr_address)
	add YL, temp4
	adc YH, r0
	ldi ZL, low(buffer_address)	; load initial buffer_address in Z
    ldi ZH, high(buffer_address)

	; clear screen and display prompt message on 1st line
	do_lcd_command 0b00000001				; clear screen
	do_lcd_command 0b00000110				; set cursor left to right
	do_lcd_data_immediate 'Y'
	do_lcd_data_immediate 'o'
	do_lcd_data_immediate 'u'
	do_lcd_data_immediate 'r'
	do_lcd_data_immediate ' '
	do_lcd_data_immediate 'N'
	do_lcd_data_immediate 'u'
	do_lcd_data_immediate 'm'
	do_lcd_data_immediate 'b'
	do_lcd_data_immediate 'e'
	do_lcd_data_immediate 'r'
	do_lcd_data_immediate ' '
	do_lcd_data_immediate 'i'
	do_lcd_data_immediate 's'
	do_lcd_data_immediate ':'
	
    ; Copy buffer to string array, and display name in buffer
	do_lcd_command 0b11000000			; move cursor to left of 2nd line
    clr temp1
copy_loop:
    cp temp1, temp3
    breq store_null
    ld temp2, Z+
	do_lcd_data_register temp2
	st Y+, temp2
	inc temp1
	rjmp copy_loop

store_null:
	; After copying all char from buffer to array, store a null char after last char in array
	clr temp1
    st Y, temp1
    add temp4, temp3			; arr_tail + buffer_index
    inc temp4					; arr_tail + 1 for null character
    clr temp3					; Reset buffer index
	st_addr arr_tail, temp4
	st_addr buffer_index, temp3

display_number:
	ld_addr tail_num_unit, temp1
	ld_addr tail_num_ten, temp2
	ld_addr tail_num_hundred, temp3
	cpi temp1, 9
	brne unit_plus_1
	clr temp1
	cpi temp2, 9
	brne ten_plus_1
	clr temp2
	cpi temp3, 9
	brne hundred_plus_1
	clr temp3
unit_plus_1:
	inc temp1
	jmp tail_num_end
ten_plus_1:
	inc temp2
	jmp tail_num_end
hundred_plus_1:
	inc temp3
	jmp tail_num_end
tail_num_end:
	do_lcd_command 0b11001111					; set DD RAM address = 0x4F, last one of 2nd line
	do_lcd_command 0b00000100					; 0b000001 I/D S, I/D = 0, cursor move left
	subi temp1, -'0'
	subi temp2, -'0'
	subi temp3, -'0'
	do_lcd_data_register temp1
	do_lcd_data_register temp2
	do_lcd_data_register temp3
	subi temp1, '0'
	subi temp2, '0'
	subi temp3, '0'
	st_addr tail_num_unit, temp1
	st_addr tail_num_ten, temp2
	st_addr tail_num_hundred, temp3

wait_confirm:									; wait patient's second D input to confirm, and change to display mode
	rcall readIn
	rcall sleep_250ms
	cpi input, 'D'
	brne wait_confirm
    jmp display_mode

.equ LCD_RS = 7
.equ LCD_E = 6
.equ LCD_RW = 5
.equ LCD_BE = 4

.macro lcd_set
	sbi PORTA, @0
.endmacro
.macro lcd_clr
	cbi PORTA, @0
.endmacro

backspace_buffer:									; function for backspace in buffer
	push temp1
	lds temp1, buffer_index
    cpi temp1, 0
    breq end_backspace_buffer						; Ignore if buffer is empty
    dec temp1										; buffer_index - 1
	sts buffer_index, temp1
end_backspace_buffer:
	pop temp1
	ret

load_char_from_map:
	mov temp2, input
	cpi input, '7'
	breq FourChar
	cpi input, '9'
	breq FourChar
	cpi temp1, 3
	breq clrIndex
	rjmp loadKey
clrIndex:
	clr temp1
	rjmp loadKey
FourChar:
	cpi temp1, 4
	breq clrIndex
loadKey:
	ldi ZL, low(key_map << 1)
	ldi ZH, high(key_map << 1)
	clr r0
	subi temp2, '2'
	lsl temp2
	lsl temp2
	add temp2, temp1
	add ZL, temp2
	adc ZL, r0
	lpm temp2, Z
	ret



lcd_command:
	out PORTF, temp1
	nop
	lcd_set LCD_E
	nop
	nop
	nop
	lcd_clr LCD_E
	nop
	nop
	nop
	ret

lcd_data:
	out PORTF, temp1
	lcd_set LCD_RS
	nop
	nop
	nop
	lcd_set LCD_E
	nop
	nop
	nop
	lcd_clr LCD_E
	nop
	nop
	nop
	lcd_clr LCD_RS
	ret

lcd_wait:
	push temp1
	clr temp1
	out DDRF, temp1
	out PORTF, temp1
	lcd_set LCD_RW
lcd_wait_loop:
	nop
	lcd_set LCD_E
	nop
	nop
    nop
	in temp1, PINF
	lcd_clr LCD_E
	sbrc temp1, 7
	rjmp lcd_wait_loop
	lcd_clr LCD_RW
	ser temp1
	out DDRF, temp1
	pop temp1
	ret

.equ F_CPU = 16000000
.equ DELAY_1MS = F_CPU / 4 / 1000 - 4
; 4 cycles per iteration - setup/call-return overhead

sleep_1ms:
	push r24
	push r25
	ldi r25, high(DELAY_1MS)
	ldi r24, low(DELAY_1MS)
delayloop_1ms:
	sbiw r25:r24, 1
	brne delayloop_1ms
	pop r25
	pop r24
	ret

sleep_5ms:
	rcall sleep_1ms
	rcall sleep_1ms
	rcall sleep_1ms
	rcall sleep_1ms
	rcall sleep_1ms
	ret

sleep_50ms:
	push temp1;
	ldi temp1, 10
	while:
		cpi temp1, 0
		breq endwhile
		dec temp1
		rcall sleep_5ms
		rjmp while
	endWhile:
	pop temp1
	ret
sleep_250ms:
	push temp1
	ldi temp1, 3
	sleep_250ms_while:
		cpi temp1, 0
		breq sleep_250ms_while_endwhile
		dec temp1
		rcall sleep_50ms
		rjmp sleep_250ms_while
	sleep_250ms_while_endwhile:
	pop temp1
	ret

sleep_500ms:
	push temp1
	ldi temp1, 10
	sleep_500ms_while:
		cpi temp1, 0
		breq sleep_500ms_while_endwhile
		dec temp1
		rcall sleep_50ms
		rjmp sleep_500ms_while
	sleep_500ms_while_endwhile:
	pop temp1
	ret

sleep_1s:
		rcall sleep_500ms
		rcall sleep_500ms
		ret

readIn:
	push temp1
	ser input
	ldi cmask, INITCOLMASK		; initial column mask
	clr	col						; initial column
colloop:
	cpi col, 4
	breq convert_end
	sts	PORTL, cmask				; set column to mask value (one column off)
	ldi temp1, 0xFF
delay:
	dec temp1
	brne delay

	lds	temp1, PINL				; read PORTL
	andi temp1, ROWMASK
	cpi temp1, 0xF				; check if any rows are on
	breq nextcol
								; if yes, find which row is on
	ldi rmask, INITROWMASK		; initialise row check
	clr	row						; initial row
rowloop:
	cpi row, 4
	breq convert_end
	mov temp2, temp1
	and temp2, rmask				; check masked bit
	breq convert 				; if bit is clear, convert the bitcode
	inc row						; else move to the next row
	lsl rmask					; shift the mask to the next bit
	jmp rowloop

nextcol:
	lsl cmask					; else get new mask by shifting and 
	inc col						; increment column value
	jmp colloop					; and check the next column

convert:
	cpi col, 3					; if column is 3 we have a letter
	breq letters				
	cpi row, 3					; if row is 3 we have a symbol or 0
	breq symbols

	mov temp1, row				; otherwise we have a number in 1-9
	lsl temp1
	add temp1, row				; temp1 = row * 3
	add temp1, col				; add the column address to get the value
	subi temp1, -'1'			; add the value of character '0'
	jmp convert_end

letters:
	ldi temp1, 'A'
	add temp1, row				; increment the character 'A' by the row value
	jmp convert_end

symbols:
	cpi col, 0					; check if we have a star
	breq star
	cpi col, 1					; or if we have zero
	breq zero					
	ldi temp1, '#'				; if not we have hash
	jmp convert_end
star:
	ldi temp1, '*'				; set to star
	jmp convert_end
zero:
	ldi temp1, '0'				; set to zero

convert_end:
	mov input, temp1			; write value to PORTC
	pop temp1
	ret
