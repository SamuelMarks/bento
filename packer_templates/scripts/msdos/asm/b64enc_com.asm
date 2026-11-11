; =============================================================================
; @file b64enc_com.asm
; @brief 16-bit 8086 real-mode B64ENC.COM Base64 file encoder (460 bytes)
; @description
;   Parses <INFILE> from the PSP command tail (0081h), opens it read-only via
;   INT 21h AH=3Dh, writes "===B64_START===<CRLF>" to stdout (BX=1), reads 48-byte
;   chunks (INT 21h AH=3Fh), encodes them into 64-character Base64 lines with
;   CRLF, emits "===B64_END===<CRLF>", and exits with AL=00h (AL=01h on error).
;   Assemble: nasm -f bin b64enc_com.asm -o B64ENC.COM
; =============================================================================

BITS 16
ORG 0x0100

start:
    mov si, 0x0081
    mov cl, [0x0080]
    xor ch, ch
    or cx, cx
    jnz skip_ws_loop
    jmp near exit_err

skip_ws_loop:
    lodsb
    cmp al, 0x20
    jz skip_ws_next
    cmp al, 0x09
    jz skip_ws_next
    cmp al, 0x0D
    jnz found_token
    jmp near exit_err

found_token:
    dec si
    mov dx, si
    jmp short scan_token_end

skip_ws_next:
    loop skip_ws_loop
    jmp near exit_err

scan_token_end:
    lodsb
    cmp al, 0x20
    jz terminate_token
    cmp al, 0x09
    jz terminate_token
    cmp al, 0x0D
    jz terminate_token
    jmp short scan_token_end

terminate_token:
    mov byte [si-1], 0x00
    mov ax, 0x3D00          ; INT 21h AH=3Dh AL=00h: Open file read-only
    int 0x21
    jnc open_ok
    jmp near exit_err

open_ok:
    mov [handle_var], ax
    mov dx, msg_start
    mov cx, 17
    call write_stdout

read_chunk:
    mov ah, 0x3F            ; INT 21h AH=3Fh: Read from file handle
    mov bx, [handle_var]
    mov cx, 48              ; 48 raw bytes -> 64 Base64 characters per line
    mov dx, in_buf
    int 0x21
    db 0x0F, 0x82, 0xE9, 0x00 ; jc close_and_err
    or ax, ax
    db 0x0F, 0x84, 0xCD, 0x00 ; jz done_eof

    mov si, in_buf
    mov di, out_buf
    mov cx, ax

encode_triplets:
    cmp cx, 3
    jb check_remainder
    mov al, [si]
    mov ah, [si+1]
    mov dl, [si+2]
    sub cx, 3

    mov bl, al
    shr bl, 1
    shr bl, 1
    call xlat_b64
    stosb

    mov bl, [si]
    add si, 3
    and bl, 0x03
    mov bh, cl
    mov cl, 4
    shl bl, cl
    mov al, ah
    shr al, cl
    or bl, al
    mov cl, bh
    call xlat_b64
    stosb

    mov bl, ah
    and bl, 0x0F
    shl bl, 1
    shl bl, 1
    mov al, dl
    mov bh, cl
    mov cl, 6
    shr al, cl
    mov cl, bh
    or bl, al
    call xlat_b64
    stosb

    mov bl, dl
    and bl, 0x3F
    call xlat_b64
    stosb

    or cx, cx
    jnz encode_triplets
    jmp short emit_line

check_remainder:
    cmp cx, 1
    jz rem_one_byte

    ; 2 bytes remaining
    mov al, [si]
    mov ah, [si+1]
    mov bl, al
    shr bl, 1
    shr bl, 1
    call xlat_b64
    stosb

    mov bl, [si]
    and bl, 0x03
    mov cl, 4
    shl bl, cl
    mov al, ah
    shr al, cl
    or bl, al
    call xlat_b64
    stosb

    mov bl, ah
    and bl, 0x0F
    shl bl, 1
    shl bl, 1
    call xlat_b64
    stosb

    mov al, '='
    stosb
    jmp short emit_line

rem_one_byte:
    mov al, [si]
    mov bl, al
    shr bl, 1
    shr bl, 1
    call xlat_b64
    stosb

    mov bl, [si]
    and bl, 0x03
    mov cl, 4
    shl bl, cl
    call xlat_b64
    stosb

    mov ax, 0x3D3D          ; "=="
    stosw

emit_line:
    mov ax, 0x0A0D          ; "<CRLF>"
    stosw
    mov dx, out_buf
    mov cx, di
    sub cx, out_buf
    call write_stdout
    jmp near read_chunk

done_eof:
    mov ah, 0x3E
    mov bx, [handle_var]
    int 0x21
    mov dx, msg_end
    mov cx, 15
    call write_stdout
    mov ax, 0x4C00
    int 0x21

close_and_err:
    mov ah, 0x3E
    mov bx, [handle_var]
    int 0x21

exit_err:
    mov ax, 0x4C01
    int 0x21

xlat_b64:
    xor bh, bh
    mov al, [bx + b64_table]
    ret

write_stdout:
    mov ah, 0x40
    mov bx, 1
    int 0x21
    ret

msg_start:
    db "===B64_START===", 0x0D, 0x0A
msg_end:
    db "===B64_END===", 0x0D, 0x0A
b64_table:
    db "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
handle_var:
    dw 0x0000

in_buf  equ 0x02CC
out_buf equ 0x02FC
