.include "M328PDEF.inc"
.equ VALOR_T1 = 0xBDC

.CSEG
.ORG 0x00
	JMP MAIN
.ORG 0x0006
	JMP ISR_PCINT0
.ORG 0x001A
	JMP ISR_TIMER1_OVF
.ORG 0x0020
	JMP ISR_TIMER0_OVF

MAIN:
/********* CONFIGURACIÓN DEL STACK *************/
	LDI R16, LOW(RAMEND)
	OUT SPL, R16
	LDI R17, HIGH(RAMEND)
	OUT SPH, R17

SETUP:
/********* CONFIGURACIÓN DE PUERTOS *************/
	LDI R16, 0xFF
	OUT DDRD, R16  ; PD0-PD6 como salida (segmentos de displays)

	LDI R16, 0b00000111
	OUT DDRB, R16  ; PB0-PB2 como salida (transistores de displays)
	SBI DDRB, PB5  ; PB5 como salida (buzzer)

	SBI DDRD, PD7  ; PD7 como salida (transistor de displays)

	LDI R16, 0b00011111
	OUT PORTC, R16 ; PC0-PC4 como entrada con pull-up (botones)

	CBI DDRB, PB4  ; PB4 como salida (LED 1)
	CBI DDRB, PB3  ; PB3 como salida (LED 2)

/********* CONFIGURACIÓN DEL RELOJ *************/
	LDI R16, (1 << CLKPCE)
	STS CLKPR, R16
	LDI R16, 0b0000_0000
	STS CLKPR, R16  ; 16MHz sin prescaler

/********* CONFIGURACIÓN DE INTERRUPCIONES *************/
	LDI R16, (1 << PCIE1)
	STS PCICR, R16
	LDI R16, 0b00011111  ; Habilitar interrupciones en PC0-PC4 (botones)
	STS PCMSK1, R16

	SEI ; Habilitar interrupciones globales

/********* TABLA PARA DISPLAYS *************/
TABLA: .DB 0x3F, 0x06, 0x5B, 0x4F, 0X66, 0X6D, 0X7D, 0X07, 0X7F, 0X6F

/********* VARIABLES DE TIEMPO *************/
LDI R19, 0  ; Horas decenas
LDI R20, 0  ; Horas unidades
LDI R21, 0  ; Minutos decenas
LDI R22, 0  ; Minutos unidades

/********* INICIALIZAR TIMERS *************/
CALL INIC_TIMER_0
CALL INIC_TIMER_1

JMP LOOP

/*************************************/
/********* CONFIGURACIÓN DE TIMERS ***********/
/*************************************/

INIC_TIMER_0:  ; Timer 0 para retardos cortos (parpadeo, multiplexación)
	LDI R17, 0
	OUT TCCR0A, R17  ; Modo normal

	LDI R17, (1 << CS02) | (1 << CS00)  ; Prescaler 1024
	OUT TCCR0B, R17

	LDI R17, 194  ; Carga inicial (ajustar según retardo)
	OUT TCNT0, R17

	LDI R17, (1 << TOIE0)  ; Habilitar interrupción por overflow
	STS TIMSK0, R17

	RET

INIC_TIMER_1:  ; Timer 1 para conteo del tiempo (segundos, minutos, etc.)
	LDI R17, HIGH(VALOR_T1)
	STS TCNT1H, R17
	LDI R17, LOW(VALOR_T1)
	STS TCNT1L, R17

	CLR R17
	STS TCCR1A, R17  ; Modo normal

	LDI R17, (1 << CS12) | (1 << CS10)  ; Prescaler 1024
	STS TCCR1B, R17

	LDI R17, (1 << TOIE1)  ; Habilitar interrupción por overflow
	STS TIMSK1, R17

	RET

/*************************************/
/********* MANEJO DE INTERRUPCIONES ***********/
/*************************************/

ISR_TIMER0_OVF:  ; Interrupción de Timer0 (multiplexación/parpadeo)
	PUSH R17
	IN R17, SREG
	PUSH R17

	LDI R17, 194
	OUT TCNT0, R17
	SBI TIFR0, TOV0  ; Limpiar flag de overflow

	INC R23  ; Contador para multiplexación de displays
	INC R18  ; Contador de parpadeo

	POP R17
	OUT SREG, R17
	POP R17

	RETI

ISR_TIMER1_OVF:  ; Interrupción de Timer1 (actualización de tiempo)
	PUSH R16
	IN R16, SREG
	PUSH R16

	LDI R16, HIGH(VALOR_T1)
	STS TCNT1H, R16
	LDI R16, LOW(VALOR_T1)
	STS TCNT1L, R16
	SBI TIFR1, TOV1  ; Limpiar flag de overflow

	INC R22  ; Incrementar segundos unidades
	CPI R22, 10
	BREQ MINUTO_COMPLETO
	JMP FIN_ISR_T1

MINUTO_COMPLETO:
	CLR R22
	INC R21  ; Incrementar minutos decenas
	CPI R21, 6
	BREQ HORA_COMPLETA
	JMP FIN_ISR_T1

HORA_COMPLETA:
	CLR R21
	INC R20  ; Incrementar horas unidades
	CPI R20, 10
	BREQ DECENA_HORA
	JMP FIN_ISR_T1

DECENA_HORA:
	CLR R20
	INC R19  ; Incrementar horas decenas
	CPI R19, 2
	BREQ LIMITE_24H
	JMP FIN_ISR_T1

LIMITE_24H:
	CPI R20, 4
	BREQ RESETEAR_HORA
	JMP FIN_ISR_T1

RESETEAR_HORA:
	CLR R19
	CLR R20

FIN_ISR_T1:
	POP R16
	OUT SREG, R16
	POP R16
	RETI

ISR_PCINT0:  ; Interrupción por cambio en botones (PC0-PC4)
	PUSH R17
	IN R17, SREG
	PUSH R17

	IN R0, PINC
	SBRS R0, PC0
	INC R20  ; Incrementar hora unidades
	SBRS R0, PC1
	DEC R20  ; Decrementar hora unidades
	SBRS R0, PC2
	INC R22  ; Incrementar minutos unidades
	SBRS R0, PC3
	DEC R22  ; Decrementar minutos unidades
	SBRS R0, PC4
	INC R17  ; Cambiar modo

	SBI PCIFR, PCIF0  ; Limpiar flag de interrupción

	POP R17
	OUT SREG, R17
	POP R17
	RETI


	/*************************************/
/********* MULTIPLEXACIÓN DE DISPLAYS ***********/
/*************************************/
MOSTRAR_HORA:
	; Apagar todos los transistores antes de actualizar
	LDI R16, 0b00000111
	OUT PORTB, R16
	SBI PORTD, PD7

	; Cargar dirección de la tabla de segmentos
	LDI ZH, HIGH(TABLA << 1)
	LDI ZL, LOW(TABLA << 1)

	; **Dígito 1: Horas Decenas**
	ADD ZL, R19
	LPM R25, Z  ; Cargar patrón de segmentos
	OUT PORTD, R25
	CBI PORTB, PB2  ; Activar transistor de display 1
	CALL ESPERA

	; **Dígito 2: Horas Unidades**
	ADD ZL, R20
	LPM R25, Z
	OUT PORTD, R25
	SBI PORTB, PB2  ; Apagar display anterior
	CBI PORTB, PB1  ; Activar transistor de display 2
	CALL ESPERA

	; **Dígito 3: Minutos Decenas**
	ADD ZL, R21
	LPM R25, Z
	OUT PORTD, R25
	SBI PORTB, PB1
	CBI PORTB, PB0  ; Activar transistor de display 3
	CALL ESPERA

	; **Dígito 4: Minutos Unidades**
	ADD ZL, R22
	LPM R25, Z
	OUT PORTD, R25
	SBI PORTB, PB0
	CBI PORTD, PD7  ; Activar transistor de display 4
	CALL ESPERA
	SBI PORTD, PD7  ; Apagar transistor de display 4

	RET

/*************************************/
/********* ESPERA PARA MULTIPLEXACIÓN ***********/
/*************************************/
ESPERA:
	LDI R23, 50  ; Ajusta este valor para optimizar la velocidad de refresco
DELAY:
	DEC R23
	BRNE DELAY
	RET

/*************************************/
/********* MANEJO DE BOTONES *********/
/*************************************/

ISR_PCINT0:  ; Interrupción por cambio en botones (PC0-PC4)
	PUSH R17
	IN R17, SREG
	PUSH R17

	IN R0, PINC
	SBRS R0, PC0
	INC R20  ; Incrementar hora unidades
	SBRS R0, PC1
	DEC R20  ; Decrementar hora unidades
	SBRS R0, PC2
	INC R22  ; Incrementar minutos unidades
	SBRS R0, PC3
	DEC R22  ; Decrementar minutos unidades
	SBRS R0, PC4
	INC R17  ; Cambiar modo

	; Limpiar flag de interrupción
	SBI PCIFR, PCIF0  

	POP R17
	OUT SREG, R17
	POP R17
	RETI

/*************************************/
/********* CAMBIOS DE MODO ***********/
/*************************************/
CAMBIAR_MODO:
	CPI R17, 0
	BREQ MODO_MOSTRAR_HORA
	CPI R17, 1
	BREQ MODO_MOSTRAR_FECHA
	CPI R17, 2
	BREQ MODO_CONFIGURAR_HORA
	CPI R17, 3
	BREQ MODO_CONFIGURAR_FECHA
	CPI R17, 4
	BREQ MODO_CONFIGURAR_ALARMA
	CPI R17, 5
	BREQ MODO_APAGAR_ALARMA
	JMP LOOP  ; Volver al loop si no es un modo válido

/*************************************/
/********* MODOS DE FUNCIONAMIENTO ***********/
/*************************************/
MODO_MOSTRAR_HORA:
	CALL MOSTRAR_HORA
	JMP LOOP

MODO_MOSTRAR_FECHA:
	CALL MOSTRAR_FECHA
	JMP LOOP

MODO_CONFIGURAR_HORA:
	CALL CAMBIAR_HORA
	JMP LOOP

MODO_CONFIGURAR_FECHA:
	CALL CAMBIAR_FECHA
	JMP LOOP

MODO_CONFIGURAR_ALARMA:
	CALL CAMBIAR_ALARMA
	JMP LOOP

MODO_APAGAR_ALARMA:
	CALL APAGAR
	JMP LOOP


	/*************************************/
/********* COMPARACIÓN DE ALARMA ***********/
/*************************************/
COMPARAR_ALARMA:
	CP R11, R19  ; Comparar horas decenas
	BRNE FIN_ALARMA
	CP R12, R20  ; Comparar horas unidades
	BRNE FIN_ALARMA
	CP R14, R21  ; Comparar minutos decenas
	BRNE FIN_ALARMA
	CP R15, R22  ; Comparar minutos unidades
	BREQ ACTIVAR_ALARMA  ; Si todas coinciden, activar alarma

FIN_ALARMA:
	RET

/*************************************/
/********* ACTIVAR ALARMA ***********/
/*************************************/
ACTIVAR_ALARMA:
	SBI PORTB, PB5  ; Encender buzzer
	SBI PORTB, PB4  ; Encender LED de alarma
	SBI PORTB, PB3  ; Encender otro LED indicador
	JMP LOOP

/*************************************/
/********* APAGAR ALARMA ***********/
/*************************************/
APAGAR:
	CBI PORTB, PB5  ; Apagar buzzer
	CBI PORTB, PB4  ; Apagar LED de alarma
	CBI PORTB, PB3  ; Apagar otro LED indicador
	JMP LOOP

	/*************************************/
/********* CAMBIO DE HORA ***********/
/*************************************/
CAMBIAR_HORA:
	SBRS R0, PC0
	INC R20  ; Incrementar horas unidades
	SBRS R0, PC1
	DEC R20  ; Decrementar horas unidades
	SBRS R0, PC2
	INC R22  ; Incrementar minutos unidades
	SBRS R0, PC3
	DEC R22  ; Decrementar minutos unidades

	; **Límites de minutos (0-59)**
	CPI R22, 10
	BREQ LIMITE_MINUTOS_UNIDADES
	CPI R21, 6
	BREQ LIMITE_MINUTOS_DECENAS

	; **Límites de horas (0-23)**
	CPI R20, 10
	BREQ LIMITE_HORAS_UNIDADES
	CPI R19, 2
	BREQ LIMITE_HORAS_DECENAS

	JMP LOOP

/*************************************/
/********* RESTRICCIONES HORARIO ***********/
/*************************************/
LIMITE_MINUTOS_UNIDADES:
	INC R21
	CLR R22
	JMP LOOP

LIMITE_MINUTOS_DECENAS:
	CLR R21
	CLR R22
	INC R20
	JMP LOOP

LIMITE_HORAS_UNIDADES:
	INC R19
	CLR R20
	JMP LOOP

LIMITE_HORAS_DECENAS:
	CPI R20, 4
	BREQ RESET_HORARIO
	JMP LOOP

RESET_HORARIO:
	CLR R19
	CLR R20
	JMP LOOP


	/*************************************/
/********* CAMBIO DE FECHA ***********/
/*************************************/
CAMBIAR_FECHA:
	SBRS R0, PC0
	INC R3  ; Incrementar día unidades
	SBRS R0, PC1
	DEC R3  ; Decrementar día unidades
	SBRS R0, PC2
	INC R5  ; Incrementar mes unidades
	SBRS R0, PC3
	DEC R5  ; Decrementar mes unidades

	; **Validaciones de días y meses**
	CALL VALIDAR_DIA
	CALL VALIDAR_MES
	JMP LOOP

/*************************************/
/********* RESTRICCIONES DE FECHA ***********/
/*************************************/
VALIDAR_DIA:
	MOV R25, R5  ; Cargar mes actual

	; **Meses con 31 días**
	CPI R25, 1
	BREQ LIMITE_31_DIAS
	CPI R25, 3
	BREQ LIMITE_31_DIAS
	CPI R25, 5
	BREQ LIMITE_31_DIAS
	CPI R25, 7
	BREQ LIMITE_31_DIAS
	CPI R25, 8
	BREQ LIMITE_31_DIAS
	CPI R25, 10
	BREQ LIMITE_31_DIAS
	CPI R25, 12
	BREQ LIMITE_31_DIAS

	; **Meses con 30 días**
	CPI R25, 4
	BREQ LIMITE_30_DIAS
	CPI R25, 6
	BREQ LIMITE_30_DIAS
	CPI R25, 9
	BREQ LIMITE_30_DIAS
	CPI R25, 11
	BREQ LIMITE_30_DIAS

	; **Febrero (28 días)**
	CPI R25, 2
	BREQ LIMITE_28_DIAS

	JMP LOOP

LIMITE_31_DIAS:
	CPI R3, 32
	BRSH RESET_DIA
	JMP LOOP

LIMITE_30_DIAS:
	CPI R3, 31
	BRSH RESET_DIA
	JMP LOOP

LIMITE_28_DIAS:
	CPI R3, 29
	BRSH RESET_DIA
	JMP LOOP

RESET_DIA:
	LDI R3, 1
	INC R5  ; Pasar al siguiente mes
	CALL VALIDAR_MES
	JMP LOOP

VALIDAR_MES:
	CPI R5, 13
	BREQ RESET_MES
	JMP LOOP

RESET_MES:
	LDI R5, 1  ; Reiniciar a enero
	INC R6  ; Incrementar año (suponiendo que se guarda en R6)
	JMP LOOP

	/*************************************/
/********* MOSTRAR FECHA ***********/
/*************************************/
MOSTRAR_FECHA:
	; Apagar todos los transistores antes de actualizar
	LDI R16, 0b00000111
	OUT PORTB, R16
	SBI PORTD, PD7

	; Cargar dirección de la tabla de segmentos
	LDI ZH, HIGH(TABLA << 1)
	LDI ZL, LOW(TABLA << 1)

	; **Dígito 1: Día Decenas**
	ADD ZL, R2
	LPM R25, Z
	OUT PORTD, R25
	CBI PORTB, PB2  ; Activar transistor de display 1
	CALL ESPERA

	; **Dígito 2: Día Unidades**
	ADD ZL, R3
	LPM R25, Z
	OUT PORTD, R25
	SBI PORTB, PB2
	CBI PORTB, PB1  ; Activar transistor de display 2
	CALL ESPERA

	; **Dígito 3: Mes Decenas**
	ADD ZL, R4
	LPM R25, Z
	OUT PORTD, R25
	SBI PORTB, PB1
	CBI PORTB, PB0  ; Activar transistor de display 3
	CALL ESPERA

	; **Dígito 4: Mes Unidades**
	ADD ZL, R5
	LPM R25, Z
	OUT PORTD, R25
	SBI PORTB, PB0
	CBI PORTD, PD7  ; Activar transistor de display 4
	CALL ESPERA
	SBI PORTD, PD7  ; Apagar transistor de display 4

	RET

	/*************************************/
/********* MOSTRAR ALARMA ***********/
/*************************************/
MOSTRAR_ALARMA:
	; Apagar todos los transistores antes de actualizar
	LDI R16, 0b00000111
	OUT PORTB, R16
	SBI PORTD, PD7

	; Cargar dirección de la tabla de segmentos
	LDI ZH, HIGH(TABLA << 1)
	LDI ZL, LOW(TABLA << 1)

	; **Dígito 1: Horas Decenas (Alarma)**
	ADD ZL, R11
	LPM R25, Z
	OUT PORTD, R25
	CBI PORTB, PB2  ; Activar transistor de display 1
	CALL ESPERA

	; **Dígito 2: Horas Unidades (Alarma)**
	ADD ZL, R12
	LPM R25, Z
	OUT PORTD, R25
	SBI PORTB, PB2
	CBI PORTB, PB1  ; Activar transistor de display 2
	CALL ESPERA

	; **Dígito 3: Minutos Decenas (Alarma)**
	ADD ZL, R14
	LPM R25, Z
	OUT PORTD, R25
	SBI PORTB, PB1
	CBI PORTB, PB0  ; Activar transistor de display 3
	CALL ESPERA

	; **Dígito 4: Minutos Unidades (Alarma)**
	ADD ZL, R15
	LPM R25, Z
	OUT PORTD, R25
	SBI PORTB, PB0
	CBI PORTD, PD7  ; Activar transistor de display 4
	CALL ESPERA
	SBI PORTD, PD7  ; Apagar transistor de display 4

	RET

/*************************************/
/********* LOOP PRINCIPAL ***********/
/*************************************/
LOOP:
	CALL COMPARAR_ALARMA  ; Verifica si la alarma debe activarse
	CALL CAMBIAR_MODO  ; Cambia el modo según el botón presionado

	; **Multiplexación de los displays**
	CPI R17, 0
	BREQ MOSTRAR_HORA
	CPI R17, 1
	BREQ MOSTRAR_FECHA
	CPI R17, 4
	BREQ MOSTRAR_ALARMA

	JMP LOOP  ; Mantenerse en el bucle principal


	/*************************************/
/********* MEJORA EN MULTIPLEXACIÓN ***********/
/*************************************/
ESPERA_MULTIPLEX:
	LDI R23, 75  ; Ajuste fino del tiempo de refresco
DELAY_LOOP:
	DEC R23
	BRNE DELAY_LOOP
	RET

	/*************************************/
/********* REINICIO COMPLETO ***********/
/*************************************/
RESET_TOTAL:
	CLR R19  ; Horas Decenas
	CLR R20  ; Horas Unidades
	CLR R21  ; Minutos Decenas
	CLR R22  ; Minutos Unidades

	LDI R2, 0  ; Día Decenas
	LDI R3, 1  ; Día Unidades
	LDI R4, 0  ; Mes Decenas
	LDI R5, 1  ; Mes Unidades

	CLR R11  ; Horas Alarma Decenas
	CLR R12  ; Horas Alarma Unidades
	CLR R14  ; Minutos Alarma Decenas
	CLR R15  ; Minutos Alarma Unidades

	LDI R17, 0  ; Reiniciar al modo de mostrar hora
	JMP LOOP



