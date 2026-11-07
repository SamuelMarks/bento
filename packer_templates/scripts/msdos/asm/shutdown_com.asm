; =============================================================================
; @file shutdown_com.asm
; @brief 16-bit 8086 real-mode SHUTDOWN.COM ACPI/APM poweroff utility (54 bytes)
; @description
;   Cleanly powers off virtual machines across QEMU, UTM, Bochs, and VirtualBox:
;   1. APM 1.2 Real-Mode Connect (INT 15h AX=5301h BX=0000h)
;   2. APM 1.2 Driver Version 1.2 (INT 15h AX=530Eh BX=0000h CX=0102h)
;   3. APM 1.2 Set Power State Off (INT 15h AX=5307h BX=0001h CX=0003h)
;   4. QEMU PIIX4/ICH9 ACPI PM1a_CNT port write (out 0x0604, 0x2000)
;   5. Bochs / older QEMU poweroff port write (out 0xB004, 0x2000)
;   6. VirtualBox ACPI poweroff port write (out 0x4004, 0x3400)
;   7. Fallback DOS exit (INT 21h AX=4C00h)
;   Assemble: nasm -f bin shutdown_com.asm -o SHUTDOWN.COM
; =============================================================================

BITS 16
ORG 0x0100

start:
    ; APM 1.2 Real-Mode Interface Connect
    mov ax, 0x5301
    xor bx, bx
    int 0x15

    ; APM 1.2 Engage Driver Version 1.2
    mov ax, 0x530E
    xor bx, bx
    mov cx, 0x0102
    int 0x15

    ; APM 1.2 Set Power State = Off (0003h) for All Devices (0001h)
    mov ax, 0x5307
    mov bx, 0x0001
    mov cx, 0x0003
    int 0x15

    ; QEMU ACPI poweroff (port 0x0604 <- 0x2000)
    mov dx, 0x0604
    mov ax, 0x2000
    out dx, ax

    ; Bochs / older QEMU ACPI poweroff (port 0xB004 <- 0x2000)
    mov dx, 0xB004
    mov ax, 0x2000
    out dx, ax

    ; VirtualBox ACPI poweroff (port 0x4004 <- 0x3400)
    mov dx, 0x4004
    mov ax, 0x3400
    out dx, ax

    ; Clean DOS exit if hardware poweroff did not trap
    mov ax, 0x4C00
    int 0x21
