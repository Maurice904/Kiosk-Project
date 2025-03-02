/*
 * macro_untils.asm
 *
 *  Created: 2024/11/13 14:05:54
 *   Author: 16141
 */ 
 .include "m2560def.inc"
 .macro Clear
	ldi YL, low(@0) ; load the memory address to Y
	ldi YH, high(@0)
	clr temp1
	st Y+, temp1 ; clear the two bytes at @0 in SRAM
	st Y, temp1
.endmacro

.macro num_plus_1	
	push temp1
	push temp2
	push temp3
	lds temp1, @0
	lds temp2, @1
	lds temp3, @2							; @0: register store unit, @1: register store ten, @2: register store hundred
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
	jmp num_plus_end
ten_plus_1:
	inc temp2
	jmp num_plus_end
hundred_plus_1:
	inc temp3
	jmp num_plus_end
num_plus_end:
	sts @0, temp1
	sts @1, temp2
	sts @2, temp3
	pop temp3
	pop temp2
	pop temp1
.endmacro

.macro storeChar
	push temp1
	push ZL
	push ZH
	lds temp1, buffer_index
    cpi temp1, MAX_LENGTH
    brge endStore								; Ignore if name length is over 15
	add_index_to_Z buffer_address, temp1		; load buffer_address + buffer_index in Z
    st Z, @0
    inc temp1										; buffer_index + 1
	sts buffer_index, temp1
endStore:
	pop ZH
	pop ZL
	pop temp1
.endmacro

.macro display_num								; @0: register store unit, @1: register store ten, @2: register store hundred
	push temp1
	push temp2
	push temp3
	do_lcd_command 0b11001111					; set DD RAM address = 0x4F, last one of 2nd line
	do_lcd_command 0b00000100					; 0b000001 I/D S, I/D = 0, cursor move left
	lds temp1, @0
	lds temp2, @1
	lds temp3, @2
	subi temp1, -'0'
	subi temp2, -'0'
	subi temp3, -'0'
	do_lcd_data_register temp1
	do_lcd_data_register temp2
	do_lcd_data_register temp3
	subi temp1, '0'
	subi temp2, '0'
	subi temp3, '0'
	sts @0, temp1
	sts @1, temp2
	sts @2, temp3
	pop temp3
	pop temp2
	pop temp1
.endmacro
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.macro add_index_to_Z							; @0: address, @1: the register stores index
	clr r0										
	ldi ZL, low(@0)
	ldi ZH, high(@0)
	add ZL, @1
	adc ZH, r0
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
	sts buffer_index, temp1
	pop temp1
.endmacro