;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Bluejay digital ESC firmware for controlling brushless motors in multirotors
;
; Copyleft  2022-2023 Daniel Mosquera
; Copyright 2020-2022 Mathias Rasmussen
; Copyright 2011-2017 Steffen Skaug
;
; This file is part of Bluejay.
;
; Bluejay is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 3 of the License, or
; (at your option) any later version.
;
; Bluejay is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with Bluejay.  If not, see <http://www.gnu.org/licenses/>.
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;
; Hardware definition file "X" for EFM8BB21F16G-QFN20 + FD6288.
;
; PORT 0                   |  PORT 1                   |  PWM    COM    PWM    LED
; P0 P1 P2 P3 P4 P5 P6 P7  |  P0 P1 P2 P3 P4 P5 P6 P7  |  inv    inv    side    n
; -----------------------  |  -----------------------  |  -------------------------
; Ap Ac Bp Bc __ RX __ Cp  |  Cc __ __ Vn Am Bm Cm __  |  no     no     high   _
;
; Driver channel 1/2/3 is called phase A/B/C in this file. Its pairing with the
; three physical motor pads must be verified on the actual PCB before power-up.
; P0.5 is the inherited candidate signal input and also requires PCB confirmation.
; Vn is a scaled VBUS/2 reference, not necessarily a three-phase star point.
;
;**** **** **** **** **** **** **** **** **** **** **** **** ****

IF MCU_TYPE != MCU_BB2
    __ERROR__ "Layout X requires an EFM8BB2 target"
ENDIF

; FD6288 cannot use Bluejay's DEADTIME=0 mode. In that mode Bluejay leaves LIN
; asserted and only PWM-switches HIN; FD6288 suppresses both outputs for HIN=LIN=1.
IF DEADTIME == 0
    __ERROR__ "Layout X with FD6288 requires non-zero DEADTIME"
ENDIF

PWM_ACTIVE_HIGH EQU 1                   ; FD6288 HIN inputs are active high
COM_ACTIVE_HIGH EQU 1                   ; FD6288 LIN inputs are active high

COMPARATOR_PORT EQU 1                   ; P1.3-P1.6 use comparator 1
COMPARATOR_INVERT EQU 0                 ; Compare phase tap against VBUS/2 reference

PCA0CPM_POWER EQU PCA0CPM0
PCA0CPL_POWER EQU PCA0CPL0
PCA0CPH_POWER EQU PCA0CPH0

PCA0CPM_DAMP EQU PCA0CPM1
PCA0CPL_DAMP EQU PCA0CPL1
PCA0CPH_DAMP EQU PCA0CPH1

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; PORT 0 definitions
;**** **** **** **** **** **** **** **** **** **** **** **** ****
C_Pwm EQU 7                            ; FD6288 HIN3
;     EQU 6
RTX_PIN EQU 5                          ; Candidate DShot signal input; verify on PCB
;     EQU 4
B_Com EQU 3                            ; FD6288 LIN2
B_Pwm EQU 2                            ; FD6288 HIN2
A_Com EQU 1                            ; FD6288 LIN1
A_Pwm EQU 0                            ; FD6288 HIN1

P0_DRIVER_PINS EQU (1 SHL A_Pwm) + (1 SHL A_Com) + (1 SHL B_Pwm) + (1 SHL B_Com) + (1 SHL C_Pwm)
P0_DIGITAL EQU P0_DRIVER_PINS + (1 SHL RTX_PIN)
P0_INIT EQU NOT P0_DRIVER_PINS          ; Drivers off; unused/open-drain latches high
P0_PUSHPULL EQU P0_DRIVER_PINS
P0_SKIP EQU 0FFh

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; PORT 1 definitions
;**** **** **** **** **** **** **** **** **** **** **** **** ****
;     EQU 7
C_Mux EQU 6                            ; Driver channel 3 BEMF tap
B_Mux EQU 5                            ; Driver channel 2 BEMF tap
A_Mux EQU 4                            ; Driver channel 1 BEMF tap
V_Mux EQU 3                            ; Scaled half-bus BEMF reference
;     EQU 2
;     EQU 1
C_Com EQU 0                            ; FD6288 LIN3

P1_DIGITAL EQU (1 SHL C_Com)           ; BEMF inputs remain analog
P1_INIT EQU NOT (1 SHL C_Com)          ; LIN3 off; analog/open-drain latches high
P1_PUSHPULL EQU (1 SHL C_Com)
P1_SKIP EQU 0FFh

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; PORT 2 definitions
;**** **** **** **** **** **** **** **** **** **** **** **** ****
DebugPin EQU 0

P2_DIGITAL EQU (1 SHL DebugPin)
P2_PUSHPULL EQU (1 SHL DebugPin)
P2_SKIP EQU (1 SHL DebugPin)

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Custom PWM phase routing across P0 and P1
;**** **** **** **** **** **** **** **** **** **** **** **** ****
P_A_Pwm EQU P0.A_Pwm
P_A_Com EQU P0.A_Com
P_B_Pwm EQU P0.B_Pwm
P_B_Com EQU P0.B_Com
P_C_Pwm EQU P0.C_Pwm
P_C_Com EQU P1.C_Com

Set_Pwm_Phase_A MACRO
    mov  P0SKIP, #(NOT ((1 SHL A_Pwm) + (1 SHL A_Com)))
    mov  P1SKIP, #0FFh
ENDM

Set_Pwm_Phase_B MACRO
    mov  P0SKIP, #(NOT ((1 SHL B_Pwm) + (1 SHL B_Com)))
    mov  P1SKIP, #0FFh
ENDM

; With only P0.7 and P1.0 unskipped, the crossbar places CEX0 on HIN3 and
; CEX1 on LIN3, continuing across the port boundary in pin order.
Set_Pwm_Phase_C MACRO
    mov  P0SKIP, #(NOT (1 SHL C_Pwm))
    mov  P1SKIP, #(NOT (1 SHL C_Com))
ENDM

Set_All_Pwm_Phases_Off MACRO
    mov  P0SKIP, #0FFh
    mov  P1SKIP, #0FFh
ENDM

;**** **** **** **** **** **** **** **** **** **** **** **** ****
; Inherit base layout
;**** **** **** **** **** **** **** **** **** **** **** **** ****
$set (CUSTOM_PWM_PHASE)
$include (Base.inc)
