; Test code from Hui Wu
; Board settings: 1. Connect LCD data pins D0-D7 to PORTF0-7.
; 2. Connect the four LCD control pins BE-RS to PORTA4-7.


.include "m2560def.inc"
.include "macro_utils.asm"
.def temp3 = r16								
.def temp4 = r17								
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

.equ TONE_OFF = 0                               ; turn off tone
.equ TONE_BEEP_BEEP = 1                         ; 1 second on, 1 second off cycle (Beep-beep)
.equ TONE_BIP_BIP = 2                           ; 0.5 second on, 0.5 second off cycle (Bip-bip)

.equ CONSULTATION_TIME = 20                     ; consultation time
.equ SAME_BUTTON_DELAY = 7                      ; same button delay
.dseg
buffer_index:									
    .byte 1                                     ; buffer index
arr_tail: 
    .byte 1                                     ; array tail
buffer_address:
    .byte BUFFER_SIZE                           ; buffer address
string_arr_address:
    .byte ARRAY_SIZE                            ; string array address
tail_num_unit:									; current patient number when storing patient
    .byte 3                                     ; unit digit
tail_num_ten:
    .byte 1                                     ; ten digit
tail_num_hundred:
    .byte 1                                     ; hundred digit
arr_head:
	.byte 1
head_num_unit:
	.byte 1
head_num_ten:
	.byte 1
head_num_hundred:
	.byte 1
entry_flag:
	.byte 1

lightOn:
	.byte 1

twoSecondCounter:
    .byte 1                           ; counter for two-second intervals

tone_count: 
    .byte 1                           ; remaining count for the current tone
pb0_toggle: 
    .byte 1                           ; toggle switch for PB0 state

TempCounter:
    .byte 2                           ; temporary counter
SecondCounter: 
    .byte 1                           ; counter for seconds
empty_flag:
    .byte 1                           ; flag indicating if buffer is empty

.cseg 
.org 0x0000
    rjmp RESET               ; Reset vector

.org INT0addr
    rjmp BUTTON_ISR_0        ; INT0 interrupt vector, jumps to button ISR

.org INT1addr
    rjmp BUTTON_ISR_1        ; INT1 interrupt vector, PB1 button interrupt

.org OVF0addr
    jmp Timer0OVF            ; Timer0 overflow interrupt vector

rjmp RESET
key_map:
    .db "ABC0DEF0GHI0JKL0MNO0PQRSTUV0WXYZ"  ; key map for the keypad

RESET:
    ser temp1
    out DDRG, temp1
    ; Initialize pb0_toggle to 0, indicating no Beep initially
    ldi temp1, 0
    sts pb0_toggle, temp1

    ; Initialize timer
    ldi temp1, 0b00000000
    out TCCR0A, temp1
    ldi temp1, 0b00000011
    out TCCR0B, temp1 ; Prescaler value=64, counting 1024 us

    ; Initialize LED
    ser temp1
    out DDRC, temp1
    clr temp1
    out PORTC, temp1
    ; Initialize PORTK, PIN0 = motor, PIN1-2 = first two LEDs
    sts DDRK, temp1

    ; Initialize PB0 and PB1 as input and enable pull-up resistors
    cbi DDRD, 0                
    sbi PORTD, 0              
    cbi DDRD, 1
    sbi PORTD, 1              

    ; Configure interrupts
    ; INT0 (PB0) triggers interrupt on falling edge
    ldi temp1, (1 << ISC01)
    sts EICRA, temp1

    ; INT1 (PB1) triggers interrupt on falling edge
    ldi temp1, (1 << ISC11)
    sts EICRA+1, temp1

    ; Enable INT0 and INT1 interrupts
    sbi EIMSK, INT0
    sbi EIMSK, INT1

    clr temp1
    ldi temp2, 1
    sts buffer_index, temp1          ; re-init index of name to 0
    sts arr_tail, temp1              ; re-init index of string array to 0
    sts tail_num_unit, temp1         ; re-init tail patient number to 0
    sts tail_num_ten, temp1
    sts tail_num_hundred, temp1

    sts arr_head, temp1
    sts entry_flag, temp1
    sts head_num_unit, temp2
    sts head_num_ten, temp1
    sts head_num_hundred, temp1
				
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
	do_lcd_command 0b00001110	; Cursor on, bar, blink

	ldi temp1, PORTLDIR			; columns are outputs, rows are inputs
	sts	DDRL, temp1

	ser temp1 
	out DDRC, temp1				; set lcd output
	out DDRB, temp1
	out PORTB, temp1
display_mode:
	cli
	clr temp1
	sts entry_flag, temp1
	sei
	rcall display_NP		                	; move cursor to the left of the 2nd line

	lds temp1, arr_head							; load arr_head in temp2
	lds temp2, arr_tail
	cp temp1, temp2
	brne someone_waiting
	jmp none_waiting
	someone_waiting:
		add_index_to_Z string_arr_address, temp1    ; Add the head index to the base address of the string array
display_head_loop1:
    inc temp1                                   ; Increment the head index
    brne no_overflow_display_head               ; If no overflow, jump to no_overflow_display_head
    ldi ZH, high(string_arr_address)            ; Load high byte of string array address into ZH
    ldi ZL, low(string_arr_address)             ; Load low byte of string array address into ZL
no_overflow_display_head:
    ld temp4, Z+                                ; Load the next character from the string array into temp4
    cpi temp4, 0                                ; Compare the character with null terminator
    breq display_head_end1                      ; If null terminator, jump to display_head_end1
    do_lcd_data_register temp4                  ; Display the character on the LCD
    rjmp display_head_loop1                     ; Repeat the loop

display_head_end1:
    display_num head_num_unit, head_num_ten, head_num_hundred ; Display the head number
    rjmp wait_a_loop              ; Jump to wait_a_loop

none_waiting:
    rcall display_none            ; Call subroutine to display "none waiting"

wait_a_loop:
    rcall readIn                  ; Call subroutine to read input
    rcall sleep_250ms             ; Call subroutine to sleep for 250ms
    cpi input, 'A'                ; Compare input with 'A'
    breq entry_mode               ; If input is 'A', jump to entry_mode
    rjmp wait_a_loop              ; Repeat the loop

entry_mode:
    rcall display_EFN             ; Call subroutine to display "Enter First Name"
setEntry_flag:
    cli                        ; Clear global interrupt flag
    ldi temp1, 1               ; Load immediate value 1 into temp1
    sts entry_flag, temp1      ; Store temp1 into entry_flag, setting it to 1
    clr temp1                  ; Clear temp1
    out PORTB, temp1           ; Output temp1 to PORTB, clearing PORTB
    sei                        ; Set global interrupt flag
whileReadIn:
    rcall readIn               ; Call subroutine to read input
    rcall sleep_250ms          ; Call subroutine to sleep for 250ms
    cpi input, 'B'             ; Compare input with 'B'
    brne continueCheck0        ; If not equal, branch to continueCheck0
    jmp delete                 ; If equal, jump to delete
	continueCheck0:
		cpi input, 'C'             ; Compare input with 'C'
		brne continueCheck1        ; If not equal, branch to continueCheck1
		jmp clear_line             ; If equal, jump to clear_line
	continueCheck1:
		cpi input, 'D'             ; Compare input with 'D'
		brne continueCheck2        ; If not equal, branch to continueCheck2
		jmp confirm_input          ; If equal, jump to confirm_input
	continueCheck2:
		cpi input, '2'             ; Compare input with '2'
		brlo whileReadIn           ; If less than, branch to whileReadIn
		cpi input, 58              ; Compare input with 58 (ASCII for ':')
		brsh whileReadIn           ; If greater than or equal, branch to whileReadIn
		clr temp1                  ; Clear temp1
		mov temp3, input           ; Move input to temp3
		cli                        ; Clear global interrupt flag
		do_lcd_command 0b00000110  ; Set LCD command for cursor move right after each input
		rcall load_char_from_map   ; Call subroutine to load character from map
		do_lcd_data_register temp2 ; Output temp2 to LCD data register
		do_lcd_command 0b00010000	; move cursor to left
		storeChar temp2
		ldi temp1, 2
		sts entry_flag, temp1
		sei
		ldi temp4, SAME_BUTTON_DELAY
READ_LOOP_2:
	rcall readIn
	rcall sleep_250ms
	cp input, temp3
	breq sameButton
	jmp notSameButton
sameButton:
	ldi temp4, SAME_BUTTON_DELAY
	inc temp1
	cli
	rcall load_char_from_map
	do_lcd_data_register temp2
	do_lcd_command 0b00010000
	rcall backspace_buffer
	storeChar temp2
	sei
notSameButton:
	dec temp4
	cpi temp4, 0
	brne READ_LOOP_2
	do_lcd_command 0b00010100
	jmp setEntry_flag

delete:
	lds temp1, buffer_index
    cpi temp1, 0
    breq end_delete									; Ignore if buffer is empty
    dec temp1										; buffer_index - 1
	sts buffer_index, temp1
	do_lcd_command 0b00000100
	do_lcd_data_immediate ' '
	do_lcd_data_immediate ' '
	do_lcd_command 0b00010100
	do_lcd_command 0b00000110	; backspace on LCD
end_delete:
	jmp whileReadIn

clear_line:
	clear_buffer_index			; clear buffer_index to 0
	clear_line_macro			; clearing LCD 2nd line
	jmp whileReadIn

confirm_input:
	lds temp3, buffer_index
	cpi temp3, 0
	brne cont_confirm_input
	jmp whileReadIn
cont_confirm_input:
	cli
	lds temp3, buffer_index	; load buffer_index in temp3
	lds temp4, arr_tail		; load arr_tail in temp4
	add_index_to_Z string_arr_address, temp4 ; load string_arr_address + arr_tail in Z
	ldi YL, low(buffer_address)	; load initial buffer_address in Y
    ldi YH, high(buffer_address)
	rcall display_YNI 				; display Your Number is: on 1st line, move cursor to left of 2nd line

	; Copy buffer to string array, and display name in buffer
    clr temp1
copy_loop:
    cp temp1, temp3
    breq store_null
    ld temp2, Y+
	do_lcd_data_register temp2
	st Z+, temp2

	inc temp4
	brne copy_no_overflow
	ldi ZH, high(string_arr_address)
	ldi ZL, low(string_arr_address)
copy_no_overflow:

	inc temp1
	rjmp copy_loop

store_null:
	; After copying all char from buffer to array, store a null char after last char in array
	clr temp1
    st Z, temp1					; store null character in string array
;    add temp4, temp3			; arr_tail + buffer_index
    inc temp4					; arr_tail + 1 for null character
    clr temp3					; Reset buffer index
	sts arr_tail, temp4
	sts buffer_index, temp3
display_number:


	num_plus_1 tail_num_unit, tail_num_ten, tail_num_hundred
	display_num tail_num_unit, tail_num_ten, tail_num_hundred

	ldi temp1, 3
	sts entry_flag, temp1
	sei
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
	push temp2
	push cmask
	push rmask
	push col
	push row
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
	pop row
	pop col
	pop rmask
	pop cmask
	pop temp2
	pop temp1
	ret
display_NP:
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
	do_lcd_command 0b11000000	
	ret
display_EFN:					; LCD display Enter First Name on 1st line, move cursor to left of 2nd line
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
	ret

display_YNI:					; LCD display Your Number is: on 1st line, move cursor to left of 2nd line
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
	do_lcd_command 0b11000000			; move cursor to left of 2nd line
	ret

display_none:
	do_lcd_data_immediate 'N'
	do_lcd_data_immediate 'o'
	do_lcd_data_immediate 'n'
	do_lcd_data_immediate 'e'
	ret

flash_once:
	push temp1
	ldi temp1, 0b10101010
	out PORTC, temp1
	rcall sleep_500ms
	ldi temp1, 0
	out PORTC, temp1
	rcall sleep_500ms
	pop temp1
	ret

;
;
; Interrupt module
;
;
;

BUTTON_ISR_0:
	rcall sleep_50ms
	rcall sleep_50ms
	sbic PIND, 0
	reti
	push ZH
	push ZL
	push temp1
	push temp2
	push temp3
	push temp4
	in temp1, SREG
	push temp1

    lds temp1, pb0_toggle
    cpi temp1, 0
    breq setPB0
secondPress:
	rcall sleep_500ms
	rcall sleep_250ms
	sbic PIND, 0
	jmp EXIT_ISR_pop
    jmp EXIT_ISR
setPB0:
	ldi temp1, 1
	sts pb0_toggle, temp1
display_Beep_mode:
	lds temp1, arr_head
	lds temp2, arr_tail
	cp temp1, temp2
	brlo cont_display_Beep_mode
	lds temp1, pb0_toggle
	cpi temp1, 1
	breq first_press_no_waiting_routine
	clr temp1
	sts pb0_toggle, temp1
	ser temp1 
	sts empty_flag, temp1
	jmp EXIT_ISR
first_press_no_waiting_routine:
	clr temp1
	sts pb0_toggle, temp1
	jmp EXIT_ISR_pop
cont_display_Beep_mode:
	clr temp1
	sts empty_flag, temp1

	do_lcd_command 0b00000001	; clear display
	do_lcd_command 0b00000110	; increment, no display shift
	do_lcd_data_immediate 'C'
	do_lcd_data_immediate 'a'
	do_lcd_data_immediate 'l'
	do_lcd_data_immediate 'l'
	do_lcd_data_immediate ' '
	do_lcd_data_immediate 'P'
	do_lcd_data_immediate 'a'
	do_lcd_data_immediate 't'
	do_lcd_data_immediate 'i'
	do_lcd_data_immediate 'e'
	do_lcd_data_immediate 'n'
	do_lcd_data_immediate 't'
	do_lcd_data_immediate ':'
	do_lcd_command 0b11000000

	ser temp1
	out PORTB, temp1

	lds temp1, arr_head
	add_index_to_Z string_arr_address, temp1
display_head_loop:
	ld temp4, Z+   
	inc temp1      
	brne no_overflow
	ldi ZH, high(string_arr_address)
	ldi ZL, low(string_arr_address)
no_overflow:
	cpi temp4, 0
	breq display_head_end
	do_lcd_data_register temp4
	rjmp display_head_loop
display_head_end:
	sts arr_head, temp1
	display_num head_num_unit, head_num_ten, head_num_hundred
	num_plus_1 head_num_unit, head_num_ten, head_num_hundred
Beep_tone:
	ldi temp1, 1
	sts pb0_toggle, temp1

	ldi temp1, 5                ; init tone_count 5
	sts tone_count, temp1    

Beep_loop:
	; Check if a stop command has been received
	lds temp1, pb0_toggle
    cpi temp1, 0
    breq EXIT_ISR 
	cpi temp1, 2
	brne continue_Beep_loop1
	jmp display_Beep_mode
continue_Beep_loop1:
    lds temp1, tone_count
    cpi temp1, 0
    breq Bip_tone    
    ; Start the tone
    ser temp1
    sts PORTK, temp1
	out PORTC, temp1
    rcall sleep_1s
	sei
	; Check if a stop command has been received
	lds temp1, pb0_toggle
    cpi temp1, 0
    breq EXIT_ISR 
	cpi temp1, 2
	brne continue_Beep_loop2
	jmp display_Beep_mode
continue_Beep_loop2:
    ; Stop the tone
    ldi temp1, 0
    sts PORTK, temp1
	ldi temp1, 0
	out PORTC, temp1
    rcall sleep_1s

    ; Decrease the tone count
    lds temp1, tone_count
    dec temp1
    sts tone_count, temp1
    rjmp Beep_loop

Bip_tone:
	; Check if a stop command has been received
	lds temp1, pb0_toggle
    cpi temp1, 0
    breq EXIT_ISR 
	cpi temp1, 2
	brne continue_Bip_tone
	jmp display_Beep_mode
	continue_Bip_tone:
		; Start the tone
		ldi temp1, 0xFF
		sts PORTK, temp1
		ldi temp1, 0xFF
		out PORTC, temp1
		rcall sleep_500ms

		; Check if a stop command has been received
		lds temp1, pb0_toggle
		cpi temp1, 0
		breq EXIT_ISR 
		cpi temp1, 2
		brne continue_Bip_tone2
		jmp display_Beep_mode
	continue_Bip_tone2:
		; close tone
		ldi temp1, 0
		sts PORTK, temp1
		ldi temp1, 0
		out PORTC, temp1
		rcall sleep_500ms
		rjmp Bip_tone
    
EXIT_ISR:
	; close motor and LED
	ldi temp1, 0
    sts PORTK, temp1

	out PORTC, temp1
        
	lds temp1, pb0_toggle
	cpi temp1, 1
	brne continue_EXIT_ISR
	clr temp1
	sts pb0_toggle, temp1
	rjmp EXIT_ISR_pop
	continue_EXIT_ISR:
		clr temp1
		sts TIMSK0, temp1
		rcall display_NP			; move cursor to the left of the 2nd line
		lds temp1, arr_head							; load arr_head in temp2
		lds temp2, arr_tail
		cp temp1, temp2
		brne wait_for_call
		rcall display_none
		jmp checking_entry_flag
wait_for_call:
	add_index_to_Z string_arr_address, temp1
display_head_loop2:
	ld temp4, Z+
	cpi temp4, 0
	breq display_head_end2
	do_lcd_data_register temp4
	rjmp display_head_loop2
display_head_end2:
	display_num head_num_unit, head_num_ten, head_num_hundred
checking_entry_flag:
	lds temp1, entry_flag
	cpi temp1, 0
	breq check_timer
	jmp ret_entry_mode
check_timer:
	lds temp1, empty_flag
	cpi temp1, 0
	brne EXIT_ISR_pop
open_timer:
	ser temp1
	out PORTC, temp1
	ldi temp1, 1<<TOIE0
	ldi temp1, CONSULTATION_TIME
	sts SecondCounter, temp1
	sts TIMSK0, temp1
	ldi temp1, 10
	sts lightOn, temp1
	clr temp1
	sts twoSecondCounter, temp1
	ser temp1
	out PORTG, temp1
EXIT_ISR_pop:

	pop temp1
	out SREG, temp1
	pop temp4
	pop temp3
	pop temp2
	pop temp1
	pop ZL
	pop ZH	
	;sbi EIMSK, INT0
	rcall sleep_1s
    reti                      ; Return from interrupt

ret_entry_mode:
	rcall sleep_1s
	rcall sleep_1s
	rcall sleep_1s
	clr temp1
	out PORTB, temp1
	lds temp1, entry_flag
	cpi temp1, 3
	brne cont_ret_entry_mode
	rjmp confirm_phase
cont_ret_entry_mode:
	rcall display_EFN
	lds temp1, buffer_index
	ldi ZL, low(buffer_address)
	ldi ZH, high(buffer_address)
	clr temp2
read_loop:
	cp temp2, temp1
	breq end_buffer

	ld temp3, Z+
	do_lcd_data_register temp3
	inc temp2
	rjmp read_loop

end_buffer:
	lds temp1, entry_flag
	cpi temp1, 2
	breq same_cursor_pos
	jmp check_timer
same_cursor_pos:
	do_lcd_command 0b00010000
	jmp check_timer

confirm_phase:
	rcall display_YNI
	lds temp1, arr_tail
	dec temp1
	add_index_to_Z string_arr_address, temp1

backward_loop:
	dec temp1
	ld temp4, -Z
	cpi temp1, 0
	breq find_head
	cpi temp4, 0
	breq find_head_with_Z
	rjmp backward_loop
find_head_with_Z:
	adiw Z, 1
find_head:
	ld temp4, Z+
	cpi temp4, 0
	brne continue_find_head
	jmp display_current_tail
continue_find_head:
	do_lcd_data_register temp4
	rjmp find_head
display_current_tail:
	display_num tail_num_unit, tail_num_ten, tail_num_hundred
	jmp EXIT_ISR_pop

BUTTON_ISR_1:
    ; PB1 interrupt: 3 seconds of Beeeep followed by 5 Beep-beeps, then infinite loop of Bip-bip
	rcall sleep_500ms
	rcall sleep_500ms
	sbic PIND, 1
	reti

	push ZH
	push ZL
	push temp1
	push temp2
	push temp3
	push temp4
	in temp1, SREG
	push temp1

	lds temp1, pb0_toggle
	cpi temp1, 0       ; When pb1_toggle = 0, PB1 cannot be started.
	breq EXIT_ISR1
	
	ldi temp1, 0xFF
    sts PORTK, temp1
	rcall flash_once
	rcall flash_once
	rcall flash_once
	ldi temp1, 0
    sts PORTK, temp1

	ldi temp1, 2
	sts pb0_toggle, temp1
EXIT_ISR1:
	pop temp1
	out SREG, temp1
	pop temp4
	pop temp3
	pop temp2
	pop temp1
	pop ZL
	pop ZH	
	reti


.equ full_pattern = 0xFF   ;1-7

Timer0OVF:
	push temp4
	push temp3
	push temp2
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
	lds temp2, SecondCounter
	dec temp2
	sts SecondCounter, temp2
	cpi temp2, 0
	breq disableTimer
	lds temp3, twoSecondCounter
	cpi temp3, 1
	breq Trigger
	inc temp3
	sts twoSecondCounter, temp3
	rjmp endif
Trigger:
	clr temp3
	sts twoSecondCounter, temp3
	lds temp3, lightOn
	cpi temp3, 3
	brlo killPortG
	dec temp3
	sts lightOn, temp3
	ldi temp4, 10
	sub temp4, temp3
	ldi temp3, 0xFF
rightShiftLoop:
	lsr temp3
	dec temp4
	cpi temp4, 0
	brne rightShiftLoop
	out PORTC, temp3
	rjmp endif
killPortG:
	ldi temp4, 1
	out PORTG, temp4
	dec temp3
	sts lightOn, temp3
	rjmp endif

disableTimer:
	clr temp1
	out PORTG, temp1
	ldi temp1, 0<<TOIE0
	sts TIMSK0, temp1
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
	pop temp2
	pop temp3
	pop temp4
    reti
