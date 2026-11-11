; =============================================================================
; @file io_msdos20.asm
; @brief 16-bit 8086 PC-BIOS IO.SYS (0070:0000h) for Microsoft MS-DOS 2.0 (4,096 bytes)
; @description
;   Implements the MS-DOS 2.0 installable device driver chain (`CON`, `AUX`,
;   `COM1`, `PRN`, `CLOCK`, and 4-unit `DSK` block driver for `A:`, `B:`, `C:`,
;   and `D:`), bidirectional COM1 (`0x03F8`, 115200 8N1) serial I/O, on-the-fly
;   FAT12<->FAT16 translation for partitioned hard disks (`0x80` and `0x81` at
;   LBA 63), high-memory SYSINIT relocation (`8800:0000h`), System File Table
;   (SFT) expansion (`FILES=28`), standard handle redirection (`STDIN`/`STDOUT`/
;   `STDERR` -> `CON` + `AUX`), and `C:\COMMAND.COM C:\ /P` execution.
;   Assemble: nasm -f bin io_msdos20.asm -o IO.SYS
; =============================================================================

BITS 16
ORG 0x0000

bios_entry:
    jmp short init_boot

; -----------------------------------------------------------------------------
; Low-Level BIOS INT 13h LBA-to-CHS Disk I/O Helper (Sectors/Track=63, Heads=16)
; -----------------------------------------------------------------------------
int13_rw_sector:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    mov [cs:disk_drv], cl
    mov [cs:disk_cmd], ch
    mov [cs:disk_buf_off], bx
    mov [cs:disk_buf_seg], es
    mov bx, 63
    div bx
    mov cl, dl
    inc cl
    xor dx, dx
    mov bx, 16
    div bx
    mov dh, dl
    mov ch, al
    shl ah, 1
    shl ah, 1
    shl ah, 1
    shl ah, 1
    shl ah, 1
    shl ah, 1
    or cl, ah
    mov dl, [cs:disk_drv]
    mov ah, [cs:disk_cmd]
    mov al, 1
    les bx, [cs:disk_buf_off]
    int 0x13
    jc int13_err
    clc
    jmp short int13_done
int13_err:
    stc
int13_done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

disk_drv:     db 0x80
disk_cmd:     db 0x02
disk_buf_off: dw 0x0000
disk_buf_seg: dw 0x0000

; -----------------------------------------------------------------------------
; Cold Boot Loader: Loads remaining IO.SYS sectors and MSDOS.SYS into 1000:0000h
; -----------------------------------------------------------------------------
init_boot:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    cld

    ; Load remaining 7 sectors of IO.SYS (LBA 0xE1..0xE7) into 0070:0200h
    mov ax, 0x0070
    mov es, ax
    mov bx, 0x0200
    mov ax, 0x00E1
    xor dx, dx
    mov si, 7
load_iosys_loop:
    mov cl, 0x80
    mov ch, 0x02
    call int13_rw_sector
    add bx, 0x0200
    add ax, 1
    adc dx, 0
    dec si
    jnz load_iosys_loop

    ; Load 34 sectors of MS-DOS 2.0 MSDOS.SYS (LBA 0xE8..0x109) into 1000:0000h
    mov ax, 0x1000
    mov es, ax
    xor bx, bx
    mov ax, 0x00E8
    xor dx, dx
    mov si, 34
load_msdos_loop:
    mov cl, 0x80
    mov ch, 0x02
    call int13_rw_sector
    add bx, 0x0200
    add ax, 1
    adc dx, 0
    dec si
    jnz load_msdos_loop

    jmp near sysinit_entry

; -----------------------------------------------------------------------------
; MS-DOS 2.0 Built-In Device Driver Chain (0070:00BAh)
; -----------------------------------------------------------------------------
dev_con:
    dw dev_aux, 0x0070
    dw 0x8013               ; Char device | CON_IN | CON_OUT | INT 29h
    dw dev_strategy
    dw con_interrupt
    db "CON     "

dev_aux:
    dw dev_com1, 0x0070
    dw 0x8000               ; Char device
    dw dev_strategy
    dw aux_interrupt
    db "AUX     "

dev_com1:
    dw dev_prn, 0x0070
    dw 0x8000               ; Char device
    dw dev_strategy
    dw aux_interrupt
    db "COM1    "

dev_prn:
    dw dev_clock, 0x0070
    dw 0x8000               ; Char device
    dw dev_strategy
    dw prn_interrupt
    db "PRN     "

dev_clock:
    dw dev_dsk, 0x0070
    dw 0x8008               ; Char device | CLOCK$
    dw dev_strategy
    dw clock_interrupt
    db "CLOCK   "

dev_dsk:
    dw 0xFFFF, 0xFFFF
    dw 0x0000               ; Block device (4 units: A:, B:, C:, D:)
    dw dev_strategy
    dw dsk_interrupt
    db 4, "       "

req_hdr_off: dw 0x0000
req_hdr_seg: dw 0x0000

dev_strategy:
    mov [cs:req_hdr_off], bx
    mov [cs:req_hdr_seg], es
    retf

; -----------------------------------------------------------------------------
; CON Device Driver (BIOS Keyboard INT 16h + COM1 0x03F8 & BIOS Video INT 10h)
; -----------------------------------------------------------------------------
con_lookahead: db 0x00

con_poll:
    mov al, [cs:con_lookahead]
    or al, al
    jnz con_have_char
    mov ah, 0x01
    int 0x16
    jz con_poll_com1
    xor ah, ah
    int 0x16
    or al, al
    jnz con_save_char
    mov al, ah
    jmp short con_save_char
con_poll_com1:
    push dx
    mov dx, 0x03FD
    in al, dx
    test al, 0x01
    jz con_no_char
    mov dx, 0x03F8
    in al, dx
    pop dx
    jmp short con_save_char
con_no_char:
    pop dx
    xor al, al
    ret
con_save_char:
    mov [cs:con_lookahead], al
con_have_char:
    or al, al
    ret

con_putc:
    push ax
    push bx
    push dx
    mov ah, 0x0E
    mov bx, 0x0007
    int 0x10
    pop dx
    pop bx
    pop ax
    ret

int29_handler:
    call con_putc
    iret

con_interrupt:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    lds bx, [cs:req_hdr_off]
    mov al, [bx+2]
    cmp al, 4
    jz con_read
    cmp al, 5
    jz con_peek
    cmp al, 7
    jz con_flush
    cmp al, 8
    jz con_write
    cmp al, 9
    jz con_write
    jmp near dev_exit_done

con_peek:
    call con_poll
    db 0x0F, 0x84, 0x66, 0x04 ; jz dev_exit_busy
    mov [bx+0x0D], al
    jmp near dev_exit_done

con_flush:
    mov byte [cs:con_lookahead], 0x00
    jmp near dev_exit_done

con_read:
    mov cx, [bx+0x12]
    les di, [bx+0x0E]
    jcxz con_read_done
con_read_loop:
    call con_poll
    jz con_read_loop
    mov byte [cs:con_lookahead], 0x00
    stosb
    loop con_read_loop
con_read_done:
    jmp near dev_exit_done

con_write:
    mov cx, [bx+0x12]
    les di, [bx+0x0E]
    jcxz con_write_done
con_write_loop:
    mov al, [es:di]
    inc di
    call con_putc
    loop con_write_loop
con_write_done:
    jmp near dev_exit_done

; -----------------------------------------------------------------------------
; AUX / COM1 Device Driver (Direct 16550A UART 0x03F8 I/O)
; -----------------------------------------------------------------------------
aux_lookahead: db 0x00

aux_poll:
    mov al, [cs:aux_lookahead]
    or al, al
    jnz aux_have_char
    push dx
    mov dx, 0x03FD
    in al, dx
    test al, 0x01
    jz aux_no_char
    mov dx, 0x03F8
    in al, dx
    pop dx
    mov [cs:aux_lookahead], al
    or al, al
    jnz aux_have_char
    ret
aux_no_char:
    pop dx
    xor al, al
    ret
aux_have_char:
    or al, al
    ret

aux_putc:
    push ax
    push dx
    mov ah, al
    mov dx, 0x03FD
aux_wait_thre:
    in al, dx
    test al, 0x20
    jz aux_wait_thre
    mov dx, 0x03F8
    mov al, ah
    out dx, al
    pop dx
    pop ax
    ret

aux_interrupt:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    lds bx, [cs:req_hdr_off]
    mov al, [bx+2]
    cmp al, 4
    jz aux_read
    cmp al, 5
    jz aux_peek
    cmp al, 7
    jz aux_flush
    cmp al, 8
    jz aux_write
    cmp al, 9
    jz aux_write
    jmp near dev_exit_done

aux_peek:
    call aux_poll
    db 0x0F, 0x84, 0xC0, 0x03 ; jz dev_exit_busy
    mov [bx+0x0D], al
    jmp near dev_exit_done

aux_flush:
    mov byte [cs:aux_lookahead], 0x00
    jmp near dev_exit_done

aux_read:
    mov cx, [bx+0x12]
    les di, [bx+0x0E]
    jcxz aux_read_done
aux_read_loop:
    call aux_poll
    jz aux_read_loop
    mov byte [cs:aux_lookahead], 0x00
    stosb
    loop aux_read_loop
aux_read_done:
    jmp near dev_exit_done

aux_write:
    mov cx, [bx+0x12]
    les di, [bx+0x0E]
    jcxz aux_write_done
aux_write_loop:
    mov al, [es:di]
    inc di
    call aux_putc
    loop aux_write_loop
aux_write_done:
    jmp near dev_exit_done

; -----------------------------------------------------------------------------
; PRN & CLOCK$ Device Drivers
; -----------------------------------------------------------------------------
prn_interrupt:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    jmp near dev_exit_done

clock_data:
    dw 0x41A0
    db 0x00, 0x0C, 0x00, 0x00

clock_interrupt:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    lds bx, [cs:req_hdr_off]
    mov al, [bx+2]
    cmp al, 4
    jz clock_read
    cmp al, 8
    jz clock_write
    cmp al, 9
    jz clock_write
    jmp near dev_exit_done
clock_read:
    les di, [bx+0x0E]
    push cs
    pop ds
    mov si, clock_data
    mov cx, 6
    rep movsb
    jmp near dev_exit_done
clock_write:
    lds si, [bx+0x0E]
    push cs
    pop es
    mov di, clock_data
    mov cx, 6
    rep movsb
    jmp near dev_exit_done

; -----------------------------------------------------------------------------
; Block Device Driver (4 Units: A:, B:, C:, D:) with FAT12<->FAT16 Translation
; -----------------------------------------------------------------------------
bpb_ptr_table:
    dw bpb_c, bpb_d, bpb_c, bpb_d

bpb_c:
    dw 512                  ; Bytes per sector
    db 4                    ; Sectors per cluster
    dw 117                  ; Reserved sectors before virtual FAT12
    db 1                    ; Number of FATs exposed to FAT12
    dw 512                  ; Root directory entries
    dw 16481                ; Total sectors exposed to FAT12
    db 0xF8                 ; Media descriptor
    dw 12                   ; Virtual FAT12 sectors per FAT

bpb_d:
    dw 512                  ; Bytes per sector
    db 4                    ; Sectors per cluster
    dw 53                   ; Reserved sectors before virtual FAT12
    db 1                    ; Number of FATs exposed to FAT12
    dw 512                  ; Root directory entries
    dw 16417                ; Total sectors on D:
    db 0xF8                 ; Media descriptor
    dw 12                   ; Virtual FAT12 sectors per FAT

drv_bios_map:   db 0x80, 0x81, 0x80, 0x81
drv_spf16_map:  dw 64, 32, 64, 32
drv_root_map:   dw 117, 53, 117, 53

dsk_interrupt:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    lds bx, [cs:req_hdr_off]
    mov al, [bx+2]
    cmp al, 0
    jz dsk_init
    cmp al, 1
    jz dsk_media_check
    cmp al, 2
    jz dsk_build_bpb
    cmp al, 4
    jz dsk_read
    cmp al, 8
    jz dsk_write
    cmp al, 9
    jz dsk_write
    jmp near dev_exit_done

dsk_init:
    mov byte [bx+0x0D], 4
    mov word [bx+0x12], bpb_ptr_table
    mov word [bx+0x14], 0x0070
    jmp near dev_exit_done

dsk_media_check:
    mov byte [bx+0x0E], 1
    jmp near dev_exit_done

dsk_build_bpb:
    mov al, [bx+1]
    and ax, 0x0003
    shl ax, 1
    mov si, ax
    mov ax, [cs:si + bpb_ptr_table]
    mov byte [bx+0x0D], 0xF8
    mov [bx+0x12], ax
    mov word [bx+0x14], 0x0070
    jmp near dev_exit_done

dsk_read:
    mov byte [cs:rw_is_write], 0x00
    jmp short dsk_rw_common

dsk_write:
    mov byte [cs:rw_is_write], 0x01

dsk_rw_common:
    mov al, [bx+1]
    and ax, 0x0003
    mov [cs:cur_drv_idx], al
    mov cx, [bx+0x12]
    mov dx, [bx+0x14]
    les di, [bx+0x0E]
    jcxz dsk_rw_done

dsk_sector_loop:
    push cx
    push dx
    push es
    push di
    call rw_single_logical_sector
    pop di
    pop es
    pop dx
    pop cx
    jc dsk_rw_error
    mov ax, es
    add ax, 0x0020
    mov es, ax
    inc dx
    loop dsk_sector_loop

dsk_rw_done:
    jmp near dev_exit_done

dsk_rw_error:
    lds bx, [cs:req_hdr_off]
    mov word [bx+0x12], 0
    mov word [bx+0x03], 0x810C
    jmp near dev_exit_return

cur_drv_idx: db 0x00
rw_is_write: db 0x00

rw_single_logical_sector:
    mov al, [cs:cur_drv_idx]
    xor ah, ah
    mov si, ax
    mov cl, [cs:si + drv_bios_map]
    mov [cs:active_bios_drv], cl
    shl si, 1
    mov ax, [cs:si + drv_spf16_map]
    mov [cs:active_spf16], ax
    mov bx, [cs:si + drv_root_map]
    mov [cs:active_fat12_base], bx

    cmp dx, bx
    jb rw_direct_sector
    mov ax, bx
    add ax, 12
    cmp dx, ax
    jae rw_direct_sector
    mov ax, dx
    sub ax, bx
    jmp near rw_translated_fat_sector

rw_direct_sector:
    mov ax, dx
    xor dx, dx
    add ax, 63
    adc dx, 0
    mov [cs:phys_lba_lo], ax
    mov [cs:phys_lba_hi], dx
    cmp byte [cs:rw_is_write], 0x00
    jnz rw_direct_write

    push es
    push di
    mov ax, 0x9400
    mov es, ax
    xor bx, bx
    mov ax, [cs:phys_lba_lo]
    mov dx, [cs:phys_lba_hi]
    mov cl, [cs:active_bios_drv]
    mov ch, 0x02
    call int13_rw_sector
    pop di
    pop es
    jc rw_direct_read_ret
    push ds
    mov ax, 0x9400
    mov ds, ax
    xor si, si
    mov cx, 0x0100
    rep movsw
    pop ds
    clc
rw_direct_read_ret:
    ret

rw_direct_write:
    push ds
    push es
    push di
    mov ax, es
    mov ds, ax
    mov si, di
    mov ax, 0x9400
    mov es, ax
    xor di, di
    mov cx, 0x0100
    rep movsw
    pop di
    pop es
    pop ds
    push es
    mov ax, 0x9400
    mov es, ax
    xor bx, bx
    mov ax, [cs:phys_lba_lo]
    mov dx, [cs:phys_lba_hi]
    mov cl, [cs:active_bios_drv]
    mov ch, 0x03
    call int13_rw_sector
    pop es
    ret

active_bios_drv:   db 0x80
active_spf16:      dw 64
active_fat12_base: dw 117
phys_lba_lo:       dw 0
phys_lba_hi:       dw 0

rw_translated_fat_sector:
    xor dx, dx
    mov bx, 3
    div bx
    mov [cs:fat_grp_idx], ax
    mov [cs:fat_grp_rem], dx
    push es
    push di
    mov ax, [cs:fat_grp_idx]
    shl ax, 1
    shl ax, 1
    add ax, 64
    mov [cs:fat16_cur_lba], ax
    mov bx, 0x9200
    mov es, bx
    xor bx, bx
    mov si, 4

load_fat16_grp:
    mov ax, [cs:fat16_cur_lba]
    xor dx, dx
    mov cl, [cs:active_bios_drv]
    mov ch, 0x02
    call int13_rw_sector
    db 0x0F, 0x82, 0x3F, 0x01 ; jc fat_rw_fail
    add bx, 0x0200
    inc word [cs:fat16_cur_lba]
    dec si
    jnz load_fat16_grp

    push ds
    mov ax, 0x9200
    mov ds, ax
    mov ax, 0x9000
    mov es, ax
    xor si, si
    xor di, di
    mov cx, 0x0200

fat16_to_fat12_loop:
    lodsw
    and ax, 0x0FFF
    mov bx, ax
    lodsw
    and ax, 0x0FFF
    mov [es:di], bl
    mov dl, al
    shl dl, 1
    shl dl, 1
    shl dl, 1
    shl dl, 1
    and bh, 0x0F
    or dl, bh
    mov [es:di+1], dl
    shr ax, 1
    shr ax, 1
    shr ax, 1
    shr ax, 1
    mov [es:di+2], al
    add di, 3
    loop fat16_to_fat12_loop

    pop ds
    pop di
    pop es
    cmp byte [cs:rw_is_write], 0x00
    jnz fat12_write_back

    push ds
    mov ax, [cs:fat_grp_rem]
    mov cl, 9
    shl ax, cl
    mov si, ax
    mov ax, 0x9000
    mov ds, ax
    mov cx, 0x0100
    rep movsw
    pop ds
    clc
    ret

fat12_write_back:
    push ds
    push es
    push di
    mov ax, es
    mov ds, ax
    mov si, di
    mov ax, [cs:fat_grp_rem]
    mov cl, 9
    shl ax, cl
    mov di, ax
    mov ax, 0x9000
    mov es, ax
    mov cx, 0x0100
    rep movsw

    mov ax, 0x9000
    mov ds, ax
    mov ax, 0x9200
    mov es, ax
    xor si, si
    xor di, di
    mov cx, 0x0200

fat12_to_fat16_loop:
    mov al, [si]
    mov ah, [si+1]
    and ah, 0x0F
    cmp ax, 0x0FF0
    jb store_first_fat16
    or ax, 0xF000
store_first_fat16:
    stosw
    mov al, [si+1]
    mov ah, [si+2]
    shr ax, 1
    shr ax, 1
    shr ax, 1
    shr ax, 1
    and ax, 0x0FFF
    cmp ax, 0x0FF0
    jb store_second_fat16
    or ax, 0xF000
store_second_fat16:
    stosw
    add si, 3
    loop fat12_to_fat16_loop

    mov ax, [cs:fat_grp_idx]
    shl ax, 1
    shl ax, 1
    add ax, 64
    mov [cs:fat16_cur_lba], ax
    mov ax, 0x9200
    mov es, ax
    xor bx, bx
    mov si, 4

write_fat1_loop:
    mov ax, [cs:fat16_cur_lba]
    xor dx, dx
    mov cl, [cs:active_bios_drv]
    mov ch, 0x03
    call int13_rw_sector
    add bx, 0x0200
    inc word [cs:fat16_cur_lba]
    dec si
    jnz write_fat1_loop

    mov ax, [cs:fat_grp_idx]
    shl ax, 1
    shl ax, 1
    add ax, 64
    add ax, [cs:active_spf16]
    mov [cs:fat16_cur_lba], ax
    xor bx, bx
    mov si, 4

write_fat2_loop:
    mov ax, [cs:fat16_cur_lba]
    xor dx, dx
    mov cl, [cs:active_bios_drv]
    mov ch, 0x03
    call int13_rw_sector
    add bx, 0x0200
    inc word [cs:fat16_cur_lba]
    dec si
    jnz write_fat2_loop

    pop di
    pop es
    pop ds
    clc
    ret

fat_rw_fail:
    pop di
    pop es
    stc
    ret

fat_grp_idx:   dw 0
fat_grp_rem:   dw 0
fat16_cur_lba: dw 0

dev_exit_busy:
    lds bx, [cs:req_hdr_off]
    mov word [bx+0x03], 0x0300
    jmp short dev_exit_return

dev_exit_done:
    lds bx, [cs:req_hdr_off]
    mov word [bx+0x03], 0x0100

dev_exit_return:
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    retf

; -----------------------------------------------------------------------------
; Resident INT 14h Serial BIOS Handler & INT 24h Critical Error Handler
; -----------------------------------------------------------------------------
int14_handler:
    or dx, dx
    jnz int14_ret
    cmp ah, 0x00
    jz int14_init
    cmp ah, 0x01
    jz int14_tx
    cmp ah, 0x02
    jz int14_rx
    cmp ah, 0x03
    jz int14_status
int14_ret:
    iret

int14_init:
    mov ax, 0x6030
    iret

int14_tx:
    call aux_putc
    mov ah, 0x60
    iret

int14_rx:
    call aux_poll
    jz int14_rx
    mov byte [cs:aux_lookahead], 0x00
    mov ah, 0x00
    iret

int14_status:
    push dx
    mov dx, 0x03FD
    in al, dx
    mov ah, al
    mov al, 0x30
    pop dx
    iret

int24_handler:
    xor al, al
    iret

; -----------------------------------------------------------------------------
; SYSINIT: UART Init, D: BPB Probe, High-Memory Relocation & COMMAND.COM Exec
; -----------------------------------------------------------------------------
sysinit_entry:
    mov dx, 0x03F9
    xor al, al
    out dx, al
    mov dx, 0x03FB
    mov al, 0x80
    out dx, al
    mov dx, 0x03F8
    mov al, 0x01
    out dx, al
    mov dx, 0x03F9
    xor al, al
    out dx, al
    mov dx, 0x03FB
    mov al, 0x03
    out dx, al
    mov dx, 0x03FA
    mov al, 0xC7
    out dx, al
    mov dx, 0x03FC
    mov al, 0x0B
    out dx, al

    xor ax, ax
    mov es, ax
    mov word [es:0x0400], 0x03F8
    mov byte [es:0x047C], 0x01
    cli
    mov word [es:0x0050], int14_handler
    mov word [es:0x0052], 0x0070
    mov word [es:0x00A4], int29_handler
    mov word [es:0x00A6], 0x0070
    sti

    ; Probe secondary hard disk 0x81 (D:) partition VBR at LBA 63
    mov ax, 0x9400
    mov es, ax
    xor bx, bx
    mov ax, 63
    xor dx, dx
    mov cl, 0x81
    mov ch, 0x02
    call int13_rw_sector
    jc relocate_sysinit
    cmp word [es:0x01FE], 0xAA55
    jnz relocate_sysinit
    mov ax, [es:0x0016]
    or ax, ax
    jz relocate_sysinit
    mov [cs:drv_spf16_map+2], ax
    mov [cs:drv_spf16_map+6], ax
    shl ax, 1
    inc ax
    sub ax, 12
    mov [cs:drv_root_map+2], ax
    mov [cs:drv_root_map+6], ax
    mov [cs:bpb_d+3], ax

relocate_sysinit:
    push cs
    pop ds
    mov ax, 0x8800
    mov es, ax
    xor si, si
    xor di, di
    mov cx, 0x0800
    rep movsw
    jmp 0x8800:sysinit_high

sysinit_high:
    mov ax, 0x1000
    mov ds, ax
    mov ax, 0x0170
    mov es, ax
    xor si, si
    xor di, di
    mov cx, 0x2200
    rep movsw

    cli
    mov ax, 0x8800
    mov ss, ax
    mov sp, 0x7FF0
    sti

    mov ax, 0x0070
    mov ds, ax
    mov si, dev_con
    mov dx, 0x8000
    call 0x0170:0x0000      ; Call MS-DOS 2.0 DOSINIT

    mov [cs:sysvars_off], di
    mov [cs:sysvars_seg], es

    ; Copy initial PSP to 87E0:0000h and set active PSP
    mov ax, 0x87E0
    mov es, ax
    xor si, si
    xor di, di
    mov cx, 0x0080
    rep movsw
    mov bx, 0x87E0
    mov ah, 0x50
    int 0x21

    ; Expand System File Table (SFT) chain at 8600:0000h (+20 entries -> 28 files)
    les bx, [cs:sysvars_off]
    les bx, [es:bx+4]
    mov word [es:bx], 0x0000
    mov word [es:bx+2], 0x8600
    mov ax, 0x8600
    mov es, ax
    xor di, di
    mov ax, 0xFFFF
    stosw
    stosw
    mov ax, 20
    stosw
    xor ax, ax
    mov cx, 500
    rep stosw

    ; Install critical error handler INT 24h and select default drive C: (DL=2)
    mov ax, 0x0070
    mov ds, ax
    mov dx, int24_handler
    mov ax, 0x2524
    int 0x21
    mov ah, 0x0E
    mov dl, 2
    int 0x21

    ; Open standard handles 0 (STDIN), 1 (STDOUT), 2 (STDERR) -> CON, 3 -> AUX, 4 -> PRN
    push cs
    pop ds
    mov ah, 0x3E
    xor bx, bx
    int 0x21
    mov ah, 0x3E
    mov bx, 2
    int 0x21
    mov dx, str_con
    mov ax, 0x3D02
    int 0x21
    push ax
    mov bx, 1
    mov ah, 0x3E
    int 0x21
    pop bx
    mov ah, 0x45
    int 0x21
    mov ah, 0x45
    int 0x21
    mov dx, str_aux
    mov ax, 0x3D02
    int 0x21
    mov dx, str_prn
    mov ax, 0x3D01
    int 0x21

    ; EXEC C:\COMMAND.COM with tail " C:\ /P<CR>"
    push cs
    pop ds
    push cs
    pop es
    mov [exec_param_blk + 4], cs
    mov [exec_param_blk + 8], cs
    mov [exec_param_blk + 12], cs
    mov dx, str_command
    mov bx, exec_param_blk
    mov ax, 0x4B00
    int 0x21
halt_loop:
    hlt
    jmp short halt_loop

sysvars_off: dw 0x0000
sysvars_seg: dw 0x0000
str_con:     db "CON", 0
str_aux:     db "AUX", 0
str_prn:     db "PRN", 0
str_command: db "C:", 0x5C, "COMMAND.COM", 0

exec_param_blk:
    dw 0x0000
    dw cmd_tail, 0x8800
    dw fcb_blank, 0x8800
    dw fcb_blank, 0x8800

cmd_tail:
    db 7, " C:", 0x5C, " /P", 0x0D
fcb_blank:
    db 0, "           "

times 4096 - ($ - $$) db 0x00
