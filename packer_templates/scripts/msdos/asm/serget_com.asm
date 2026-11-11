; =============================================================================
; @file serget_com.asm
; @brief 16-bit 8086 real-mode SERGET.COM high-speed COM1 Base64 receiver (248 bytes)
; @description
;   Parses <OUTFILE> from the PSP command tail (0081h), creates the file via
;   INT 21h AH=3Ch, transmits "<CRLF>===SERGET_RDY===<CRLF>" directly over the
;   COM1 16550A UART (0x3F8), and polls COM1 LSR (0x3FD) to decode incoming
;   Base64 characters on the fly into 512-byte buffered disk writes (INT 21h
;   AH=40h) until an "!" end-of-stream sentinel is received.
;   Assemble: nasm -f bin serget_com.asm -o SERGET.COM
; =============================================================================

BITS 16
ORG 0x0100

start:
    mov si, 0x0081          ; Start of PSP command-line tail

skip_spaces:
    lodsb
    cmp al, 0x20
    jz skip_spaces
    jnc found_arg
    jmp exit_err

found_arg:
    dec si
    mov dx, si              ; DS:DX -> start of ASCIIZ filename

find_end:
    lodsb
    cmp al, 0x20
    ja find_end
    mov byte [si-1], 0x00   ; Null-terminate filename

    xor cx, cx              ; Normal file attributes (0)
    mov ah, 0x3C            ; INT 21h AH=3Ch: Create or truncate file
    int 0x21
    jnc create_ok
    jmp exit_err

create_ok:
    mov bx, ax              ; BX = open output file handle
    mov si, rdy_msg         ; Transmit "<CRLF>===SERGET_RDY===<CRLF>" over COM1

send_rdy:
    lodsb
    or al, al
    jz init_decoder
    mov ah, al
    mov dx, 0x03FD          ; COM1 Line Status Register (LSR)

wait_tx:
    in al, dx
    test al, 0x20           ; Transmit Holding Register Empty (THRE)?
    jz wait_tx
    mov dx, 0x03F8          ; COM1 Transmit Buffer (THR)
    mov al, ah
    out dx, al
    jmp short send_rdy

init_decoder:
    xor si, si              ; SI = 16-bit bit-accumulator
    mov byte [bit_cnt], 0   ; Clear accumulated bit count
    xor di, di              ; DI = output buffer byte index (0..511)

read_loop:
    mov dx, 0x03FD          ; COM1 Line Status Register (LSR)
poll_rx:
    in al, dx
    test al, 0x01           ; Data Ready (DR)?
    jz poll_rx
    mov dx, 0x03F8          ; COM1 Receive Buffer (RBR)
    in al, dx

    cmp al, '!'             ; '!' marks end of Base64 stream
    jz flush_and_close
    cmp al, '='             ; Ignore Base64 '=' padding characters
    jz read_loop

    cmp al, 'A'
    jb check_digit
    cmp al, 'Z'
    ja check_lower
    sub al, 'A'             ; 'A'..'Z' -> 0..25
    jmp short got_sextet

check_lower:
    cmp al, 'a'
    jb read_loop
    cmp al, 'z'
    ja read_loop
    sub al, 0x47            ; 'a'..'z' -> 26..51
    jmp short got_sextet

check_digit:
    cmp al, '0'
    jb check_plus
    cmp al, '9'
    ja read_loop
    sub al, 0xFC            ; '0'..'9' -> 52..61 (add 4)
    jmp short got_sextet

check_plus:
    cmp al, '+'
    jnz check_slash
    mov al, 62              ; '+' -> 62
    jmp short got_sextet

check_slash:
    cmp al, '/'
    jnz read_loop
    mov al, 63              ; '/' -> 63

got_sextet:
    xor ah, ah
    mov cl, 6
    shl si, cl
    or si, ax
    add byte [bit_cnt], 6
    cmp byte [bit_cnt], 8
    jb read_loop

    sub byte [bit_cnt], 8
    mov cl, [bit_cnt]
    mov ax, si
    shr ax, cl
    mov [di + out_buf], al
    inc di
    cmp di, 0x0200          ; Flush every 512 bytes
    jb read_loop

    mov cx, di
    mov dx, out_buf
    mov ah, 0x40            ; INT 21h AH=40h: Write to file handle BX
    int 0x21
    xor di, di
    jmp short read_loop

flush_and_close:
    or di, di
    jz close_file
    mov cx, di
    mov dx, out_buf
    mov ah, 0x40
    int 0x21

close_file:
    mov ah, 0x3E            ; INT 21h AH=3Eh: Close file handle BX
    int 0x21
    mov ax, 0x4C00          ; Exit with code 0
    int 0x21

exit_err:
    mov ax, 0x4C01          ; Exit with code 1
    int 0x21

rdy_msg:
    db 0x0D, 0x0A, "===SERGET_RDY===", 0x0D, 0x0A, 0x00

bit_cnt equ 0x01F8
out_buf equ 0x01F9
