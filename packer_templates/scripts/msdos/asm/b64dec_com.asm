; =============================================================================
; @file b64dec_com.asm
; @brief 16-bit 8086 real-mode B64DEC.COM Base64 file decoder (459 bytes)
; @description
;   Parses <SRC.B64> and <DST.BIN> from the PSP command tail (0081h), opens
;   <SRC.B64> read-only (INT 21h AH=3Dh), creates <DST.BIN> (INT 21h AH=3Ch),
;   decodes Base64 quartet blocks while skipping whitespace and handling '='
;   padding, writes binary output (INT 21h AH=40h), and exits with AL=00h.
;   Assemble: nasm -f bin b64dec_com.asm -o B64DEC.COM
; =============================================================================

BITS 16
ORG 0x0100

start:
    mov si, 0x0081
    mov cl, [0x0080]
    xor ch, ch
    call next_arg
    or dx, dx
    jnz got_src_arg
    jmp near exit_err

got_src_arg:
    mov [src_ptr], dx
    call next_arg
    or dx, dx
    jnz got_dst_arg
    jmp near exit_err

got_dst_arg:
    mov [dst_ptr], dx
    mov ax, 0x3D00          ; Open source file read-only
    mov dx, [src_ptr]
    int 0x21
    jnc open_src_ok
    jmp near exit_err

open_src_ok:
    mov [in_handle], ax
    mov ah, 0x3C            ; Create destination binary file
    xor cx, cx
    mov dx, [dst_ptr]
    int 0x21
    jnc create_dst_ok
    jmp near close_src_err

create_dst_ok:
    mov [out_handle], ax
    xor bp, bp              ; BP = quartet index (0..3)

read_chunk:
    mov ah, 0x3F
    mov bx, [in_handle]
    mov cx, 0x0100
    mov dx, read_buf
    int 0x21
    db 0x0F, 0x82, 0x81, 0x00 ; jc close_both_err
    or ax, ax
    jz eof_flush
    mov si, read_buf
    mov cx, ax

char_loop:
    lodsb
    cmp al, '='
    jz handle_padding
    call decode_sextet
    cmp al, 0xFF
    jz next_char
    mov bx, bp
    mov [bx + qbuf], al
    inc bp
    cmp bp, 4
    jnz next_char
    call flush_full_triplet
    xor bp, bp
    jmp short next_char

handle_padding:
    cmp bp, 2
    jz pad_two_sextets
    cmp bp, 3
    jz pad_three_sextets
    jmp short eof_flush

next_char:
    loop char_loop
    jmp short read_chunk

pad_three_sextets:
    call pack_first_two
    mov [obuf], al
    mov [obuf+1], ah
    mov cx, 2
    call write_out
    jmp short close_ok

pad_two_sextets:
    call pack_first_two
    mov [obuf], al
    mov cx, 1
    call write_out
    jmp short close_ok

eof_flush:
    cmp bp, 2
    jz eof_two
    cmp bp, 3
    jz eof_three
    jmp short close_ok

eof_three:
    xor bp, bp
    jmp short pad_three_sextets

eof_two:
    xor bp, bp
    jmp short pad_two_sextets

close_ok:
    mov ah, 0x3E
    mov bx, [out_handle]
    int 0x21
    mov ah, 0x3E
    mov bx, [in_handle]
    int 0x21
    mov ax, 0x4C00
    int 0x21

close_both_err:
    mov ah, 0x3E
    mov bx, [out_handle]
    int 0x21
close_src_err:
    mov ah, 0x3E
    mov bx, [in_handle]
    int 0x21
exit_err:
    mov ax, 0x4C01
    int 0x21

next_arg:
    xor dx, dx
    or cx, cx
    jz next_arg_ret
skip_leading:
    lodsb
    dec cx
    cmp al, 0x20
    jz skip_leading_check
    cmp al, 0x09
    jz skip_leading_check
    cmp al, 0x0D
    jz next_arg_none
    dec si
    inc cx
    mov dx, si
scan_arg_chars:
    or cx, cx
    jz term_at_si
    lodsb
    dec cx
    cmp al, 0x20
    jz term_before_si
    cmp al, 0x09
    jz term_before_si
    cmp al, 0x0D
    jz term_before_si
    jmp short scan_arg_chars

term_before_si:
    mov byte [si-1], 0x00
    ret

term_at_si:
    mov byte [si], 0x00
    ret

skip_leading_check:
    or cx, cx
    jnz skip_leading
next_arg_none:
    xor dx, dx
next_arg_ret:
    ret

decode_sextet:
    cmp al, 'A'
    jb dec_digit
    cmp al, 'Z'
    ja dec_lower
    sub al, 'A'
    ret
dec_lower:
    cmp al, 'a'
    jb dec_invalid
    cmp al, 'z'
    ja dec_invalid
    sub al, 0x47
    ret
dec_digit:
    cmp al, '0'
    jb dec_plus
    cmp al, '9'
    ja dec_invalid
    sub al, 0xFC
    ret
dec_plus:
    cmp al, '+'
    jnz dec_slash
    mov al, 62
    ret
dec_slash:
    cmp al, '/'
    jnz dec_invalid
    mov al, 63
    ret
dec_invalid:
    mov al, 0xFF
    ret

pack_first_two:
    mov al, [qbuf]
    shl al, 1
    shl al, 1
    mov bl, [qbuf+1]
    shr bl, 1
    shr bl, 1
    shr bl, 1
    shr bl, 1
    or al, bl
    mov ah, [qbuf+1]
    shl ah, 1
    shl ah, 1
    shl ah, 1
    shl ah, 1
    mov bl, [qbuf+2]
    shr bl, 1
    shr bl, 1
    or ah, bl
    ret

flush_full_triplet:
    push cx
    push si
    call pack_first_two
    mov [obuf], al
    mov [obuf+1], ah
    mov al, [qbuf+2]
    mov cl, 6
    shl al, cl
    or al, [qbuf+3]
    mov [obuf+2], al
    mov cx, 3
    call write_out
    pop si
    pop cx
    ret

write_out:
    mov ah, 0x40
    mov bx, [out_handle]
    mov dx, obuf
    int 0x21
    ret

src_ptr:    dw 0x0000
dst_ptr:    dw 0x0000
in_handle:  dw 0x0000
out_handle: dw 0x0000
qbuf:       db 0, 0, 0, 0
obuf:       db 0, 0, 0, 0

read_buf equ 0x02CB
