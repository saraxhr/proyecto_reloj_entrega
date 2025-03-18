;*************
;*     Configuración inicial       *
;*************
.include "m328pdef.inc"

;*************
;*     Registros y Variables       *
;*************
.def temp = r16
.def temp2 = r9
.def sreg_temp = r17
.def display_actual = r18
.def digit_sel = r19
.def modo = r20
.def debounce_counter = r21
.def estado = r22
.def hora_h = r23
.def hora_l = r24
.def min_h = r25   
.def min_l = r12   
.def dia_d = r13   
.def dia_u = r14  
.def mes_d = r15 
.def mes_u = r10   
.def alarma_h = r11
.def alarma_m = r8 



; Variables en SRAM
.dseg
.org 0x100
ticks_250ms: .byte 1
segundos: .byte 1

;*************
;*     Definición de pines          *
;*************
.equ BUTTON_MODE = PINC0  
.equ BUTTON_SEL = PINC1   
.equ BUTTON_INC = PINC2   
.equ BUTTON_DEC = PINC3   
.equ LED1 = PB3          
.equ LED2 = PB4          

; Tabla de segmentos (cátodo común)
tabla_7seg:
    .db 0b00111111, 0b00000110  ; 0, 1
    .db 0b01011011, 0b01001111  ; 2, 3
    .db 0b01100110, 0b01101101  ; 4, 5
    .db 0b01111101, 0b00000111  ; 6, 7
    .db 0b01111111, 0b01101111  ; 8, 9



;*************
;*     Constantes                  *
;*************
.cseg
.org 0x0000
    rjmp RESET
.org 0x0020
    rjmp TIMER0_OVF    

;*************
;*     Programa principal          *
;*************
RESET:
    ; Configuración del stack pointer
    ldi temp, high(RAMEND)
    out SPH, temp
    ldi temp, low(RAMEND)
    out SPL, temp

    ; Configuración de puertos
    ldi temp, 0xFF
    out DDRD, temp      ; PORTD como salida (para los segmentos)
    ldi temp, (1<<PB0)|(1<<PB1)|(1<<PB2)|(1<<LED1)|(1<<LED2)
    out DDRB, temp     


	

    ; Configuración de entradas
    ldi temp, 0x00
    out DDRC, temp      
    ldi temp, (1<<BUTTON_MODE)|(1<<BUTTON_SEL)|(1<<BUTTON_INC)|(1<<BUTTON_DEC)
    out PORTC, temp     

    ; Inicialización de variables
    clr temp
    mov estado, temp
    mov hora_h, temp
    mov hora_l, temp
    mov min_h, temp
    mov min_l, temp
    mov dia_d, temp
    mov dia_u, temp
    mov mes_d, temp
    mov mes_u, temp
    mov alarma_h, temp
    mov alarma_m, temp
    sts ticks_250ms, temp
    clr display_actual
    clr digit_sel

    ; Configuración Timer0
    ldi temp, (1<<CS01)    
    out TCCR0B, temp
    ldi temp, (1<<TOIE0)   
    sts TIMSK0, temp

    sei  

MAIN_LOOP:
    rcall CHECK_BUTTONS
    rjmp MAIN_LOOP

;*************
;*     Rutina de Timer            *
;*************
TIMER0_OVF:
    push temp
    in temp, SREG
    push temp
    push sreg_temp

    ; Moverse al siguiente display
    inc display_actual
    cpi display_actual, 4  ; Hay 4 displays (0,1,2,3)
    brne CONTINUE_TIMER
    clr display_actual  ; Si llega a 4, reiniciar a 0




CONTINUE_TIMER:
    lds temp, ticks_250ms
    inc temp
    cpi temp, 240
    brne UPDATE_DISPLAYS

    clr temp
    sts ticks_250ms, temp

UPDATE_DISPLAYS:
    ; Apagar todos los displays primero
    ldi temp, 0x00
    out PORTB, temp  

    ; Mostrar el dígito correspondiente
    mov temp, display_actual
    cpi temp, 0
    breq SHOW_H10
    cpi temp, 1
    breq SHOW_H1
    cpi temp, 2
    breq SHOW_M10
    cpi temp, 3
    breq SHOW_M1
    rjmp END_TIMER

SHOW_H10:        
    mov temp, hora_h
    rcall OBTENER_PATRON
    out PORTD, temp  
    ldi temp, (1 << PB0)  
    out PORTB, temp  
    rjmp END_TIMER

SHOW_H1:         
    mov temp, hora_l
    rcall OBTENER_PATRON
    out PORTD, temp  
    ldi temp, (1 << PB1)  
    out PORTB, temp  
    rjmp END_TIMER

SHOW_M10:        
    mov temp, min_h
    rcall OBTENER_PATRON
    out PORTD, temp  
    ldi temp, (1 << PB2)  
    out PORTB, temp  
    rjmp END_TIMER

SHOW_M1:         
    mov temp, min_l
    rcall OBTENER_PATRON
    out PORTD, temp  
    ldi temp, (1 << PB3)  
    out PORTB, temp  

END_TIMER:
    pop sreg_temp
    pop temp
    out SREG, temp
    pop temp
    reti


;*************
;*     MANEJO DE BOTONES            *
;*************
CHECK_BUTTONS:
    sbis PINC, BUTTON_MODE
    rcall CAMBIAR_MODO
    sbis PINC, BUTTON_SEL
    rcall SELECCIONAR_DIGITO
    sbis PINC, PC2    ; Cambiado a PC2 (Incremento)
    rcall INCREMENTAR
    sbis PINC, PC3    ; Cambiado a PC3 (Tto)
    rcall DECREMENTAR
    ret

;*************
;*     CAMBIAR MODO        *
;*************
CAMBIAR_MODO:
    rcall DEBOUNCE
    inc estado
    cpi estado, 9
    brne UPDATE_LEDS
    clr estado  

UPDATE_LEDS:
    rcall CHECK_LED
    ret

;*************
;*     SELECCIONAR DÍGITO        *
;*************
SELECCIONAR_DIGITO:
    rcall DEBOUNCE
    inc digit_sel
    cpi digit_sel, 4
    brne EXIT_SEL
    clr digit_sel
EXIT_SEL:
    ret

;*************
;*     CHECK LEDS        *
;*************
CHECK_LED:
    cpi estado, 1
    breq LED_HORA
    cpi estado, 2
    breq LED_HORA
    cpi estado, 4
    breq LED_FECHA
    cpi estado, 5
    breq LED_FECHA
    cpi estado, 7
    breq LED_ALARMA
    cpi estado, 8
    breq LED_ALARMA

    cbi PORTB, LED1
    cbi PORTB, LED2
    ret

LED_HORA:
    sbi PORTB, LED1
    sbi PORTB, LED2
    ret

LED_FECHA:
    sbi PORTB, LED1
    sbi PORTB, LED2
    ret

LED_ALARMA:
    cbi PORTB, LED1
    sbi PORTB, LED2
    ret

;*************
;*     INCREMENTAR/DECREMENTAR        *
;*************
INCREMENTAR:
    rcall DEBOUNCE
    cpi estado, 1
    breq INC_HORA
    cpi estado, 2
    breq INC_MIN
    ret

INC_HORA:
    inc hora_l
    cpi hora_l, 10
    brne EXIT_INC
    clr hora_l
    inc hora_h
    cpi hora_h, 3
    brne EXIT_INC
    clr hora_h
EXIT_INC:
    ret

INC_MIN:
    inc min_l
    ldi temp, 10       ; Cargar el valor 10 en un registro válido
    cp min_l, temp     ; Comparar min_l con 10
    brne EXIT_INC      ; Si no son iguales, saltar a EXIT_INC; ? Cambié CONTINUAR por EXIT_INC

    clr min_l
    inc min_h
    cpi min_h, 6
    brne EXIT_INC
    clr min_h
    rjmp INC_HORA


	DECREMENTAR:
    ; Disminuir horas, minutos, fecha o alarma dependiendo del estado actual
    CPI estado, 1
    BRNE CHECK_DEC_2
    RJMP Dec_Horas
CHECK_DEC_2:
    CPI estado, 2
    BRNE CHECK_DEC_4
    RJMP Dec_Minutos
CHECK_DEC_4:
    CPI estado, 4
    BRNE CHECK_DEC_5
    RJMP Dec_Mes
CHECK_DEC_5:
    CPI estado, 5
    BRNE CHECK_DEC_7
    RJMP Dec_Dia
CHECK_DEC_7:
    CPI estado, 7
    BRNE CHECK_DEC_8
    RJMP Dec_Minutos_Alarma
CHECK_DEC_8:
    CPI estado, 8
    BRNE END_DEC
    RJMP Dec_Horas_Alarma

END_DEC:
    RET  ; Salir si el estado no es válido




;*************************
; DECREMENTAR HORAS
;*************************
Dec_Horas:
    CPI hora_l, 0
    BRNE Dec_Horas_U
    CPI hora_h, 0
    BRNE Dec_Horas_D
    LDI hora_h, 2
    LDI hora_l, 3
    RET

Dec_Horas_U:
    DEC hora_l
    RET

Dec_Horas_D:
    LDI hora_l, 9
    DEC hora_h
    RET

;*************************
; DECREMENTAR MINUTOS
;*************************
Dec_Minutos:
    MOV temp, min_l  ; ? Usar temp como intermediario
    CPI temp, 0
    BRNE Dec_Minutos_U
    MOV temp, min_h
    CPI temp, 0
    BRNE Dec_Minutos_D
    LDI temp, 5
    MOV min_h, temp
    LDI temp, 9
    MOV min_l, temp
    RJMP Dec_Horas

Dec_Minutos_U:
    DEC min_l
    RET

Dec_Minutos_D:
    LDI temp, 9
    MOV min_l, temp
    DEC min_h
    RET

;*************************
; DECREMENTAR MES
;*************************
Dec_Mes:
    MOV temp, mes_d  
    CPI temp, 0
    BRNE Dec_Mes_Norm
    MOV temp, mes_u
    CPI temp, 1
    BRNE Dec_Mes_Norm
    LDI temp, 1
    MOV mes_d, temp
    LDI temp, 2
    MOV mes_u, temp
    RET

Dec_Mes_Norm:
    MOV temp, mes_u
    CPI temp, 0
    BRNE Dec_Mes_OnlyU
    LDI temp, 9
    MOV mes_u, temp
    DEC mes_d
    RET

Dec_Mes_OnlyU:
    DEC mes_u
    RET

;*************************
; DECREMENTAR DÍA
;*************************
Dec_Dia:
    LDI temp, 0
    CP dia_d, temp
    BRNE Dec_Dia_Norm

    CP dia_u, temp
    BRNE Dec_Dia_Norm

    CALL Dec_Mes
    CALL Obtener_Limite_Dia
    MOV dia_d, temp
    MOV dia_u, temp2
    RET

Dec_Dia_Norm:
    LDI temp, 0
    CP dia_u, temp
    BRNE Dec_Dia_U

    LDI temp, 9
    MOV dia_u, temp
    DEC dia_d
    RET

Dec_Dia_U:
    DEC dia_u
    RET

;*************************
; OBTENER LÍMITE DE DÍAS SEGÚN EL MES ACTUAL
;*************************
Obtener_Limite_Dia:
    ; Verificar si el mes es FEBRERO (28 días)
    LDI temp, 0
    CP mes_d, temp
    BRNE NoFebrero
    LDI temp, 2
    CP mes_u, temp
    BRNE NoFebrero
    LDI temp, 2  ; Decenas = 2
    LDI temp, 8   ; ? Cargar valor en temp (que sí soporta LDI)
	MOV temp2, temp  ; ? Moverlo a temp2

    RET

NoFebrero:
    ; Verificar si el mes tiene 30 días (Abril, Junio, Septiembre, Noviembre)
    LDI temp, 0
    CP mes_d, temp
    BRNE NoMes30
    LDI temp, 4  ; Abril (04)
    CP mes_u, temp
    BREQ Mes30
    LDI temp, 6  ; Junio (06)
    CP mes_u, temp
    BREQ Mes30
    LDI temp, 9  ; Septiembre (09)
    CP mes_u, temp
    BREQ Mes30

    LDI temp, 1
    CP mes_d, temp
    BRNE NoMes30
    LDI temp, 1  ; Noviembre (11)
    CP mes_u, temp
    BREQ Mes30

NoMes30:
    ; Si no es febrero ni un mes de 30 días, entonces tiene 31 días
    LDI temp, 3  ; ? Decenas = 3
    LDI temp, 1  ; ? Cargar 1 en un registro válido
    MOV temp2, temp  ; ? Moverlo a temp2
    RET


Mes30:
    ; Si el mes es 04, 06, 09 o 11, asignar 30 días
    LDI temp, 3  ; ? Decenas = 3
    LDI temp, 0  ; ? Cargar 0 en un registro válido
    MOV temp2, temp  ; ? Moverlo a temp2 si está en r8-r15
    RET


;*************************
; DECREMENTAR HORAS ALARMA
;*************************
Dec_Horas_Alarma:
    MOV temp, alarma_h
    CPI temp, 0
    BRNE Dec_Horas_Alarma_Norm
    LDI temp, 2
    MOV alarma_h, temp
    LDI temp, 3
    MOV alarma_m, temp
    RET

Dec_Horas_Alarma_Norm:
    DEC alarma_h
    RET

;*************************
; DECREMENTAR MINUTOS ALARMA
;*************************
Dec_Minutos_Alarma:
    MOV temp, alarma_m
    CPI temp, 0
    BRNE Dec_Minutos_Alarma_Norm
    LDI temp, 5
    MOV alarma_m, temp
    RJMP Dec_Horas_Alarma

Dec_Minutos_Alarma_Norm:
    DEC alarma_m
    RET



DEBOUNCE:
    ldi temp, 255
DEBOUNCE_LOOP:
    dec temp
    brne DEBOUNCE_LOOP
    ret

	OBTENER_PATRON:
    push ZH
    push ZL
    push temp  

    ldi ZH, high(tabla_7seg * 2)
    ldi ZL, low(tabla_7seg * 2)
    add ZL, temp
    brcc SKIP_INC
    inc ZH
SKIP_INC:
    lpm temp, Z  ; Carga el patrón correcto

    pop temp  
    pop ZL
    pop ZH
    ret
