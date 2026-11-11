; =============================================================================
; @file serinit_com.asm
; @brief 16-bit 8086 real-mode SERINIT.COM UART & INT 14h initializer (224 bytes)
; @description
;   1. Configures BIOS Data Area [0040:0000] = 0x03F8 (COM1 base) and timeout.
;   2. Programs the 16550A UART at 0x03F8 to 115200 baud, 8N1, FIFO enabled,
;      and asserts DTR|RTS|OUT2 (0x0B).
;   3. Installs a resident hardware UART INT 14h handler at 0000:0200h that
;      polls 0x03F8/0x03FD directly and asserts DCD|DSR|CTS (0xB0) so MS-DOS
;      and FreeDOS `CTTY COM1` never block on virtual modem status lines.
;   4. Scans segment 0070h to apply FreeDOS 1.3 kernel COM1 polling patches
;      when running under FreeDOS (no-op under Microsoft MS-DOS).
;   Assemble: nasm -f bin serinit_com.asm -o SERINIT.COM
; =============================================================================

BITS 16
ORG 0x0100

start:
    cli
    mov ax, 0x0040
    mov es, ax
    mov word [es:0x0000], 0x03F8    ; BDA COM1 base I/O port = 0x03F8
    mov byte [es:0x007C], 0x01      ; BDA COM1 timeout = 1 tick

    ; Disable UART interrupts (IER = 0)
    mov dx, 0x03F9
    xor al, al
    out dx, al

    ; Enable Divisor Latch Access Bit (LCR = 0x80)
    mov dx, 0x03FB
    mov al, 0x80
    out dx, al

    ; Set divisor = 1 (115200 baud: DLL = 1, DLM = 0)
    mov dx, 0x03F8
    mov al, 0x01
    out dx, al
    mov dx, 0x03F9
    xor al, al
    out dx, al

    ; 8 data bits, no parity, 1 stop bit (LCR = 0x03)
    mov dx, 0x03FB
    mov al, 0x03
    out dx, al

    ; Enable and clear 14-byte FIFO queues (FCR = 0xC7)
    mov dx, 0x03FA
    mov al, 0xC7
    out dx, al

    ; Assert DTR, RTS, OUT2 (MCR = 0x0B)
    mov dx, 0x03FC
    mov al, 0x0B
    out dx, al

    ; Clear pending receive buffer byte
    mov dx, 0x03F8
    in al, dx

    ; Copy resident INT 14h handler (70 bytes) to 0000:0200h (unused IVT top)
    xor ax, ax
    mov es, ax
    mov di, 0x0200
    mov si, int14_handler
    mov cx, 0x0046
    rep movsb

    ; Point INT 14h vector (0000:0050h) to 0000:0200h
    mov word [es:0x0050], 0x0200
    mov word [es:0x0052], 0x0000

    ; Scan segment 0070h for FreeDOS 1.3 kernel serial status wait loops
    mov ax, 0x0070
    mov es, ax
    xor di, di
    mov cx, 0x2000

scan_kernel:
    cmp word [es:di], 0x0788
    jnz check_second_sig
    cmp word [es:di+2], 0xB5E9
    jnz check_second_sig
    mov byte [es:di+3], 0xDB

check_second_sig:
    cmp word [es:di], 0x20A8
    jnz next_byte
    cmp word [es:di+2], 0xF674
    jnz next_byte
    mov word [es:di+2], 0x9090

next_byte:
    inc di
    loop scan_kernel

    sti
    mov ax, 0x4C00
    int 0x21

; -----------------------------------------------------------------------------
; Resident INT 14h Handler (relocated to 0000:0200h, 70 bytes)
; -----------------------------------------------------------------------------
int14_handler:
    push dx
    cmp ah, 0x01
    jz int14_tx
    cmp ah, 0x02
    jz int14_rx
    cmp ah, 0x03
    jz int14_status
    jmp short int14_status

int14_tx:
    push ax
    mov dx, 0x03FD
wait_thre:
    in al, dx
    test al, 0x20
    jz wait_thre
    pop ax
    mov dx, 0x03F8
    out dx, al
    mov ah, 0x60
    mov al, 0xB0
    pop dx
    iret

int14_rx:
    mov dx, 0x03FD
wait_dr:
    in al, dx
    test al, 0x01
    jz wait_dr
    mov dx, 0x03F8
    in al, dx
    xor ah, ah
    pop dx
    iret

int14_status:
    mov dx, 0x03FD
    in al, dx
    and al, 0x61
    mov ah, al
    mov dx, 0x03FE
    in al, dx
    or al, 0xB0
    pop dx
    iret
