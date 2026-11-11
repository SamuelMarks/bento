; =============================================================================
; @file ver_com.asm
; @brief 16-bit 8086 real-mode VER.COM utility for Microsoft MS-DOS 1.25 (33 bytes)
; @description
;   Prints "<CRLF>MS-DOS Version 1.25<CRLF>" to standard output via DOS INT 21h
;   AH=09h and terminates cleanly via INT 20h.
;   Assemble: nasm -f bin ver_com.asm -o VER.COM
; =============================================================================

BITS 16
ORG 0x0100

start:
    mov dx, msg             ; DS:DX -> "$"-terminated version banner
    mov ah, 0x09            ; DOS 1.x+ Print String (AH=09h)
    int 0x21
    int 0x20                ; DOS 1.x Program Terminate

msg:
    db 0x0D, 0x0A, "MS-DOS Version 1.25", 0x0D, 0x0A, "$"
