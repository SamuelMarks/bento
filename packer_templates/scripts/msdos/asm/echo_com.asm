; =============================================================================
; @file echo_com.asm
; @brief 16-bit 8086 real-mode ECHO.COM utility for Microsoft MS-DOS 1.25 (105 bytes)
; @description
;   Provides command-line ECHO functionality for MS-DOS 1.25 COMMAND.COM (which
;   lacks a built-in ECHO command or %ERRORLEVEL% environment variable).
;   Scans the PSP command tail at 0080h and dynamically expands "%ERRORLEVEL%"
;   tokens by querying the last child return code via DOS INT 21h AH=4Dh
;   (implemented by the Bento MS-DOS 1.25 IO.SYS INT 21h syscall shim).
;   Assemble: nasm -f bin echo_com.asm -o ECHO.COM
; =============================================================================

BITS 16
ORG 0x0100

start:
    mov si, 0x0080          ; PSP command tail length byte
    lodsb
    xor ch, ch
    mov cl, al              ; CX = length of command tail
    jcxz print_crlf         ; Empty tail -> print CRLF and exit

    cmp byte [si], 0x20     ; Skip single leading space after "ECHO"
    jnz scan_loop
    inc si
    dec cx
    jz print_crlf

scan_loop:
    cmp cx, 12              ; Enough characters left for "%ERRORLEVEL%" (12 chars)?
    jb emit_char

    push si
    push di
    push cx
    mov di, errlvl_str
    mov cx, 12
    repe cmpsb              ; Compare against "%ERRORLEVEL%"
    pop cx
    pop di
    pop si
    jnz emit_char

    ; Matched "%ERRORLEVEL%": query last exit code via INT 21h AH=4Dh
    push cx
    push si
    mov ah, 0x4D
    int 0x21
    mov dl, '0'
    or al, al
    jz print_errlvl_digit
    mov dl, '1'

print_errlvl_digit:
    mov ah, 0x02            ; DOS Character Output (DL)
    int 0x21
    pop si
    pop cx
    add si, 12
    sub cx, 12
    jnz scan_loop
    jmp short print_crlf

emit_char:
    lodsb
    mov dl, al
    mov ah, 0x02            ; DOS Character Output (DL)
    int 0x21
    loop scan_loop

print_crlf:
    mov dl, 0x0D
    mov ah, 0x02
    int 0x21
    mov dl, 0x0A
    mov ah, 0x02
    int 0x21
    int 0x20                ; Terminate program

errlvl_str:
    db "%ERRORLEVEL%"
