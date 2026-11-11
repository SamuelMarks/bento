; =============================================================================
; @file io_msdos125.asm
; @brief 16-bit 8086 PC-BIOS IO.SYS (0070:0000h) for Microsoft MS-DOS 1.25 (4,096 bytes)
; @description
;   Implements the 86-DOS / MS-DOS 1.25 BIOS jump vector table at 0070:0000h:
;   - Bidirectional COM1 (0x03F8, 115200 8N1) + BIOS INT 16h/10h console I/O.
;   - Dynamic FAT12 (MSDOS.SYS in-memory) <-> FAT16 (0x80 C: and 0x81 D: hard
;     disks at partition LBA 63) sector & FAT cluster translation for 4 drives
;     (A:, B:, C:, D:).
;   - Resident DOS 2.0/3.0+ INT 21h syscall shim (vector at 0070:0484h chaining
;     to native MS-DOS 1.25 INT 21h at [0070:0430h]) supporting 16-bit OpenWatcom
;     and C runtimes:
;       * AH=26h Create New PSP (records child CS, clamps PSP:[0002h], clears
;         PSP:[002Ch] environment selector to 0000h).
;       * AH=30h Get DOS Version (returns AL=1, AH=25 -> MS-DOS 1.25).
;       * AH=31h Terminate and Stay Resident.
;       * AH=35h Get Interrupt Vector (returns ES:BX while preserving AX).
;       * AH=3Ch Create/Truncate File & AH=5Bh Create New File (maps ASCIIZ path
;         or "CON" device to 4-slot FCB table handles BX=5..8).
;       * AH=3Dh Open File (maps ASCIIZ path or "CON" to FCB handle).
;       * AH=3Eh Close File Handle.
;       * AH=3Fh Read File Handle (bridges to FCB Random Block Read AH=27h).
;       * AH=40h Write File Handle (writes BX=1/2 to console/COM1; bridges
;         BX=5..8 to FCB Random Block Write AH=28h).
;       * AH=41h Unlink File (bridges to FCB Delete AH=13h).
;       * AH=42h Lseek File Handle (updates FCB Random Record offset).
;       * AH=43h Get/Set File Attributes.
;       * AH=44h IOCTL Get Device Information (Isatty for handles 0..4 vs >=5).
;       * AH=47h Get Current Directory.
;       * AH=48h/49h/4Ah Allocate/Free/Resize Memory Blocks.
;       * AH=4Ch Terminate Process with Return Code & AH=4Dh Get Return Code
;         (restores caller CS on stack when child called AH=26h).
;       * AH=56h Rename File (bridges to FCB Rename AH=17h).
;       * AH=63h Get DBCS Lead Byte Table, AH=66h Code Page, AH=68h Commit File.
;   Assemble: nasm -f bin io_msdos125.asm -o IO.SYS
; =============================================================================

BITS 16
ORG 0x0000

; -----------------------------------------------------------------------------
; 86-DOS / MS-DOS 1.25 BIOS Jump Table (0070:0000h .. 0070:0029h)
; -----------------------------------------------------------------------------
bios_entry:
    jmp near init_boot          ; 0000h: INIT    - Cold boot initialization
    jmp near con_stat           ; 0003h: STATUS  - Console input status
    jmp near con_in             ; 0006h: INP     - Console character input
    jmp near con_out            ; 0009h: OUTP    - Console character output
    jmp near prn_out            ; 000Ch: PRINT   - Printer character output
    jmp near aux_in             ; 000Fh: AUXIN   - Auxiliary character input
    jmp near aux_out            ; 0012h: AUXOUT  - Auxiliary character output
    jmp near dsk_read           ; 0015h: READ    - Disk sector read
    jmp near dsk_write          ; 0018h: WRITE   - Disk sector write
    jmp near dsk_chg            ; 001Bh: DSKCHG  - Disk change check
    jmp near set_date           ; 001Eh: SETDATE - Set date (days since 1980-01-01)
    jmp near set_time           ; 0021h: SETTIME - Set time
    jmp near get_time           ; 0024h: GETTIME - Get time and date
    jmp near con_flush          ; 0027h: FLUSH   - Flush console input buffer
    jmp short map_dev           ; 002Ah: MAPDEV  - Disk device mapper

map_dev:
    retf

; -----------------------------------------------------------------------------
; Low-Level BIOS INT 13h LBA-to-CHS Disk I/O Helper (Sectors/Track=63, Heads=16)
;   Inputs:  DX:AX = 32-bit LBA, CL = BIOS drive (0x80/0x81), CH = INT 13h AH (2=Read, 3=Write)
;            ES:BX = transfer buffer
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
; Cold Boot Loader: Reads remaining IO.SYS sectors and MSDOS.SYS into 0170:0000h
; -----------------------------------------------------------------------------
init_boot:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x0600
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

    ; Load 16 sectors of MSDOS.SYS (LBA 0xE8..0xF7) into 0170:0000h
    mov ax, 0x0170
    mov es, ax
    xor bx, bx
    mov ax, 0x00E8
    xor dx, dx
    mov si, 16
load_msdos_loop:
    mov cl, 0x80
    mov ch, 0x02
    call int13_rw_sector
    add bx, 0x0200
    add ax, 1
    adc dx, 0
    dec si
    jnz load_msdos_loop

    jmp near sysinit_main

; -----------------------------------------------------------------------------
; Console & Serial (COM1 0x03F8) Character I/O Routines
; -----------------------------------------------------------------------------
key_Wait_char: db 0x00

poll_char_nonblock:
    mov al, [cs:key_Wait_char]
    or al, al
    jnz poll_have_char
    mov ah, 0x01
    int 0x16
    jz poll_serial_rx
    xor ah, ah
    int 0x16
    or al, al
    jnz store_polled_char
    mov al, ah
    jmp short store_polled_char

poll_serial_rx:
    push dx
    mov dx, 0x03FD
    in al, dx
    test al, 0x01
    jz poll_no_char
    mov dx, 0x03F8
    in al, dx
    pop dx
    jmp short store_polled_char

poll_no_char:
    pop dx
    xor al, al
    ret

store_polled_char:
    mov [cs:key_Wait_char], al
poll_have_char:
    or al, al
    ret

con_stat:
    call poll_char_nonblock
    retf

con_in:
    call poll_char_nonblock
    jz con_in
    mov byte [cs:key_Wait_char], 0x00
    retf

con_flush:
    mov byte [cs:key_Wait_char], 0x00
    retf

putc_both:
    push ax
    push bx
    push dx
    mov ah, 0x0E
    mov bx, 0x0007
    int 0x10
    mov ah, al
    mov dx, 0x03FD
wait_com1_tx:
    in al, dx
    test al, 0x20
    jz wait_com1_tx
    mov dx, 0x03F8
    mov al, ah
    out dx, al
    pop dx
    pop bx
    pop ax
    ret

con_out:
aux_out:
    call putc_both
    retf

aux_in:
    jmp short con_in

prn_out:
    retf

dos_day_cnt: dw 0x41A0

set_date:
    mov [cs:dos_day_cnt], ax
    retf

set_time:
    retf

get_time:
    mov ax, [cs:dos_day_cnt]
    mov cx, 0x0C00
    xor dx, dx
    retf

dsk_chg:
    mov ah, 0x01
    clc
    retf

; -----------------------------------------------------------------------------
; 86-DOS / MS-DOS 1.25 Drive Parameter Tables (INITTAB for 4 drives: A:, B:, C:, D:)
; -----------------------------------------------------------------------------
inittab:
    db 4                    ; 4 logical drives (A:, B:, C:, D:)
    db 0                    ; Unit 0 (A:)
    dw dpt_c
    db 1                    ; Unit 1 (B:)
    dw dpt_d
    db 0                    ; Unit 0 (C:)
    dw dpt_c
    db 1                    ; Unit 1 (D:)
    dw dpt_d

dpt_c:
    dw 512                  ; Bytes per sector
    db 4                    ; Sectors per cluster
    dw 123                  ; Reserved sectors before virtual FAT12
    db 1                    ; Number of FATs exposed to MSDOS.SYS
    dw 512                  ; Root directory entries
    dw 8317                 ; Total sectors exposed to FAT12 MSDOS.SYS

dpt_d:
    dw 512                  ; Bytes per sector
    db 4                    ; Sectors per cluster
    dw 59                   ; Reserved sectors before virtual FAT12
    db 1                    ; Number of FATs exposed to MSDOS.SYS
    dw 512                  ; Root directory entries
    dw 8253                 ; Total sectors on D: (patched dynamically if D: present)

drv_bios_map:   db 0x80, 0x81, 0x80, 0x81
drv_spf16_map:  dw 64, 32, 64, 32
drv_root_map:   dw 123, 59, 123, 59

cur_drv_idx:    db 0x00
rw_is_write:    db 0x00

; -----------------------------------------------------------------------------
; Disk Read / Write Entry Points with On-the-Fly FAT12 <-> FAT16 Translation
; -----------------------------------------------------------------------------
dsk_read:
    mov byte [cs:rw_is_write], 0x00
    jmp short dsk_rw_common

dsk_write:
    mov byte [cs:rw_is_write], 0x01

dsk_rw_common:
    push es
    push ds
    push di
    push si
    push bp
    push bx
    and al, 0x03
    mov [cs:cur_drv_idx], al
    push ds
    pop es
    mov di, bx
    jcxz dsk_rw_ok

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
    jc dsk_rw_err
    mov ax, es
    add ax, 0x0020
    mov es, ax
    inc dx
    loop dsk_sector_loop

dsk_rw_ok:
    xor cx, cx
    clc
    jmp short dsk_rw_exit

dsk_rw_err:
    mov al, 0x0C
    stc

dsk_rw_exit:
    pop bx
    pop bp
    pop si
    pop di
    pop ds
    pop es
    retf

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

    ; Check if logical sector DX falls in the virtual 6-sector FAT12 window
    cmp dx, bx
    jb rw_direct_sector
    mov ax, bx
    add ax, 6
    cmp dx, ax
    jae rw_direct_sector
    mov ax, dx
    sub ax, bx
    jmp near rw_translated_fat_sector

rw_direct_sector:
    mov ax, dx
    xor dx, dx
    add ax, 63              ; Partition starts at LBA 63
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
active_fat12_base: dw 123
phys_lba_lo:       dw 0
phys_lba_hi:       dw 0

; -----------------------------------------------------------------------------
; FAT12 (3 sectors per group) <-> FAT16 (4 sectors per group) Translator
; -----------------------------------------------------------------------------
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
    add ax, 64              ; Partition LBA 63 + 1 reserved sector = LBA 64
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

    ; Convert 512 pairs of 16-bit FAT entries at 9200:0000 into 12-bit pairs at 9000:0000
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

    ; Unpack 12-bit FAT entries at 9000:0000 back to 16-bit FAT entries at 9200:0000
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

    ; Write updated 4-sector FAT16 group to FAT #1
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

    ; Mirror 4-sector FAT16 group to FAT #2
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
old_int21_off: dw 0
old_int21_seg: dw 0
fcb_slot_5:    times 40 db 0
fcb_slot_6:    times 40 db 0

; -----------------------------------------------------------------------------
; Resident INT 21h Entry Point (0070:0484h)
; -----------------------------------------------------------------------------
int21_handler:
    cmp ah, 0x35            ; AH=35h: Get Interrupt Vector (AL -> ES:BX, preserve AX)
    jnz check_ah_5b
    push ax
    xor bx, bx
    mov es, bx
    mov bl, al
    shl bx, 1
    shl bx, 1
    les bx, [es:bx]
    pop ax
    iret

check_ah_5b:
    cmp ah, 0x5B            ; AH=5Bh: Create New File (DOS 3.0+)
    jnz jump_ext_dispatch
    jmp near handle_create_file

jump_ext_dispatch:
    jmp near int21_ext_dispatch

    ; Legacy dispatch table stubs (preserved for binary offset compatibility)
    db 0x0F, 0x84, 0x0D, 0x01
    cmp ah, 0x40
    db 0x0F, 0x84, 0x2D, 0x01
    cmp ah, 0x4C
    jz legacy_exit
    jmp far [cs:old_int21_off]

    mov ax, 0x1901
    xor bx, bx
    xor cx, cx
    iret

legacy_exit:
    xor ah, ah
    jmp far [cs:old_int21_off]

    push ds
    push es
    push si
    push di
    push bx
    push cx
    push dx
    mov si, dx
    mov ax, cs
    mov es, ax
    mov di, fcb_slot_5
    mov cx, 20
    xor ax, ax
    rep stosw
    mov di, fcb_slot_5
    mov ax, 0x2901
    pushf
    call far [cs:old_int21_off]
    push cs
    pop ds
    mov dx, fcb_slot_5
    mov ah, 0x0F
    pushf
    call far [cs:old_int21_off]
    or al, al
    jnz legacy_open_err
    mov word [cs:fcb_slot_5 + 0x0E], 1
    mov word [cs:fcb_slot_5 + 0x21], 0
    mov word [cs:fcb_slot_5 + 0x23], 0
    pop dx
    pop cx
    pop bx
    pop di
    pop si
    pop es
    pop ds
    mov ax, 5
    jmp near legacy_ret_clc

legacy_open_err:
    pop dx
    pop cx
    pop bx
    pop di
    pop si
    pop es
    pop ds
    mov ax, 2
    jmp near legacy_ret_stc

    push ds
    push es
    push si
    push di
    push bx
    push cx
    push dx
    mov si, dx
    mov ax, cs
    mov es, ax
    mov di, fcb_slot_6
    mov cx, 20
    xor ax, ax
    rep stosw
    mov di, fcb_slot_6
    mov ax, 0x2901
    pushf
    call far [cs:old_int21_off]
    push cs
    pop ds
    mov dx, fcb_slot_6
    mov ah, 0x13
    pushf
    call far [cs:old_int21_off]
    mov dx, fcb_slot_6
    mov ah, 0x16
    pushf
    call far [cs:old_int21_off]
    or al, al
    jnz legacy_open_err
    mov word [cs:fcb_slot_6 + 0x0E], 1
    mov word [cs:fcb_slot_6 + 0x21], 0
    mov word [cs:fcb_slot_6 + 0x23], 0
    pop dx
    pop cx
    pop bx
    pop di
    pop si
    pop es
    pop ds
    mov ax, 6
    jmp near legacy_ret_clc

    push ds
    push dx
    push ax
    mov dx, fcb_slot_5
    cmp bx, 5
    jz legacy_close_do
    mov dx, fcb_slot_6
    cmp bx, 6
    jz legacy_close_do
    pop ax
    pop dx
    pop ds
    jmp short legacy_ret_clc

legacy_close_do:
    push cs
    pop ds
    mov ah, 0x10
    pushf
    call far [cs:old_int21_off]
    pop ax
    pop dx
    pop ds
    xor ax, ax
    jmp short legacy_ret_clc

    push ds
    push dx
    push bx
    mov ah, 0x1A
    pushf
    call far [cs:old_int21_off]
    mov dx, fcb_slot_5
    cmp bx, 5
    jz legacy_read_do
    mov dx, fcb_slot_6
legacy_read_do:
    push cs
    pop ds
    mov ah, 0x27
    pushf
    call far [cs:old_int21_off]
    mov ax, cx
    pop bx
    pop dx
    pop ds
    jmp short legacy_ret_clc

    cmp bx, 1
    jz legacy_write_con
    cmp bx, 2
    jz legacy_write_con
    push ds
    push dx
    push bx
    mov ah, 0x1A
    pushf
    call far [cs:old_int21_off]
    mov dx, fcb_slot_5
    cmp bx, 5
    jz legacy_write_do
    mov dx, fcb_slot_6
legacy_write_do:
    push cs
    pop ds
    mov ah, 0x28
    pushf
    call far [cs:old_int21_off]
    mov ax, cx
    pop bx
    pop dx
    pop ds
    jmp short legacy_ret_clc

legacy_write_con:
    push si
    push cx
    mov si, dx
    jcxz legacy_write_con_done
legacy_write_con_loop:
    lodsb
    call putc_both
    loop legacy_write_con_loop
legacy_write_con_done:
    pop cx
    pop si
    mov ax, cx
    jmp short legacy_ret_clc

legacy_ret_clc:
    push bp
    mov bp, sp
    and word [bp+6], 0xFFFE
    pop bp
    iret

legacy_ret_stc:
    push bp
    mov bp, sp
    or word [bp+6], 0x0001
    pop bp
    iret

; -----------------------------------------------------------------------------
; System Initialization (SYSINIT): UART 115200 8N1, D: BPB Probe, DOS Init & COMMAND.COM Load
; -----------------------------------------------------------------------------
sysinit_main:
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

    ; Probe secondary hard disk 0x81 (D:) partition VBR at LBA 63
    mov ax, 0x9400
    mov es, ax
    xor bx, bx
    mov ax, 63
    xor dx, dx
    mov cl, 0x81
    mov ch, 0x02
    call int13_rw_sector
    jc init_dos_kernel
    cmp word [es:0x01FE], 0xAA55
    jnz init_dos_kernel
    mov ax, [es:0x0016]     ; BPB sectors per FAT16 on D:
    or ax, ax
    jz init_dos_kernel
    mov [cs:drv_spf16_map+2], ax
    mov [cs:drv_spf16_map+6], ax
    shl ax, 1
    inc ax
    mov bx, ax
    sub ax, 6
    mov [cs:drv_root_map+2], ax
    mov [cs:drv_root_map+6], ax
    mov [cs:dpt_d+3], ax
    add bx, 32
    add bx, 0x1FDC
    mov [cs:dpt_d+8], bx

init_dos_kernel:
    push cs
    pop ds
    mov si, inittab
    mov dx, 0x8000          ; 512KB top of conventional memory for MSDOS.SYS
    call 0x0170:0x0000      ; Call MSDOS.SYS DOSINIT (returns PSP segment in DS)

    ; Hook INT 21h vector (0000:0084h) -> 0070:0484h
    push ds
    xor ax, ax
    mov es, ax
    cli
    mov ax, [es:0x0084]
    mov [cs:old_int21_off], ax
    mov ax, [es:0x0086]
    mov [cs:old_int21_seg], ax
    mov word [es:0x0084], int21_handler
    mov word [es:0x0086], 0x0070
    sti
    pop ds

    ; Load COMMAND.COM from A:/C: into initial PSP segment:0100h
    mov dx, 0x0100
    mov ah, 0x1A
    int 0x21
    mov cx, [0x0006]
    mov bx, ds
    push cs
    pop ds
    mov dx, command_fcb
    mov ah, 0x0F            ; Open COMMAND.COM via FCB
    int 0x21
    or al, al
    jnz halt_boot_err
    xor ax, ax
    mov [command_fcb + 0x21], ax
    mov [command_fcb + 0x23], ax
    inc ax
    mov [command_fcb + 0x0E], ax
    mov ah, 0x27            ; Random Block Read COMMAND.COM
    int 0x21
    mov ds, bx
    mov es, bx
    cli
    mov ss, bx
    mov sp, 0x005C
    sti
    xor ax, ax
    push ax
    mov dx, 0x0080
    mov ah, 0x1A
    int 0x21
    push bx
    mov ax, 0x0100
    push ax
    retf

halt_boot_err:
    hlt
    jmp short halt_boot_err

command_fcb:
    db 1, "COMMAND COM"
    times 31 db 0

; -----------------------------------------------------------------------------
; Extended DOS 2.0/3.0+ INT 21h Syscall Dispatcher (0070:0760h)
; -----------------------------------------------------------------------------
int21_ext_dispatch:
    cmp ah, 0x26
    db 0x0F, 0x84, 0x98, 0x00 ; jz handle_create_psp
    cmp ah, 0x30
    db 0x0F, 0x84, 0xBD, 0x00 ; jz handle_get_version
    cmp ah, 0x31
    db 0x0F, 0x84, 0xBE, 0x00 ; jz handle_tsr
    cmp ah, 0x3C
    db 0x0F, 0x84, 0x26, 0x02 ; jz handle_create_file
    cmp ah, 0x3D
    db 0x0F, 0x84, 0xC2, 0x01 ; jz handle_open_file
    cmp ah, 0x3E
    db 0x0F, 0x84, 0x6D, 0x02 ; jz handle_close_file
    cmp ah, 0x3F
    db 0x0F, 0x84, 0x8C, 0x02 ; jz handle_read_file
    cmp ah, 0x40
    db 0x0F, 0x84, 0xB9, 0x02 ; jz handle_write_file
    cmp ah, 0x41
    db 0x0F, 0x84, 0x09, 0x03 ; jz handle_unlink_file
    cmp ah, 0x42
    db 0x0F, 0x84, 0x2F, 0x03 ; jz handle_lseek_file
    cmp ah, 0x43
    db 0x0F, 0x84, 0x77, 0x03 ; jz handle_chmod_file
    cmp ah, 0x44
    db 0x0F, 0x84, 0xB9, 0x03 ; jz handle_ioctl
    cmp ah, 0x47
    db 0x0F, 0x84, 0xCF, 0x03 ; jz handle_getcwd
    cmp ah, 0x48
    db 0x0F, 0x84, 0xCF, 0x03 ; jz handle_alloc_mem
    cmp ah, 0x49
    db 0x0F, 0x84, 0xCF, 0x03 ; jz handle_free_resize_mem
    cmp ah, 0x4A
    db 0x0F, 0x84, 0xC8, 0x03 ; jz handle_free_resize_mem
    cmp ah, 0x4C
    db 0x0F, 0x84, 0x62, 0x00 ; jz handle_exit_proc
    cmp ah, 0x4D
    db 0x0F, 0x84, 0x75, 0x00 ; jz handle_get_errorlevel
    cmp ah, 0x56
    db 0x0F, 0x84, 0xB7, 0x03 ; jz handle_rename_file
    cmp ah, 0x63
    db 0x0F, 0x84, 0x08, 0x04 ; jz handle_dbcs_table
    cmp ah, 0x66
    db 0x0F, 0x84, 0x0A, 0x04 ; jz handle_codepage
    cmp ah, 0x68
    db 0x0F, 0x84, 0x0D, 0x04 ; jz handle_commit_file
    jmp far [cs:old_int21_off]

; AH=26h: Create New Program Segment Prefix (PSP) at segment DX
handle_create_psp:
    mov [cs:saved_child_cs], dx
    push bp
    mov bp, sp
    push ds
    mov ds, [bp+4]          ; Caller's CS on interrupt stack
    cmp word [0x0002], 0x1000
    jae clear_psp_env
    mov word [0x0002], 0x8000
clear_psp_env:
    mov word [0x002C], 0x0000
    pop ds
    pop bp
    jmp far [cs:old_int21_off]
    times 5 db 0x90

; AH=30h: Get DOS Version -> AL=1, AH=25 (MS-DOS 1.25)
handle_get_version:
    mov ax, 0x1901
    xor bx, bx
    xor cx, cx
    iret

; AH=31h: Terminate and Stay Resident & AH=4Ch: Terminate with Return Code
handle_tsr:
    mov [cs:last_exit_code], al
    jmp short do_terminate_proc

handle_exit_proc:
    mov [cs:last_exit_code], al
do_terminate_proc:
    push bp
    mov bp, sp
    mov ax, [cs:saved_child_cs]
    or ax, ax
    jz chain_dos_terminate
    mov [bp+4], ax          ; Restore PSP CS on stack for MS-DOS 1.25 AH=00h
chain_dos_terminate:
    pop bp
    xor ah, ah
    jmp far [cs:old_int21_off]

; AH=4Dh: Get Return Code (ERRORLEVEL) of Last Child Process
handle_get_errorlevel:
    xor ah, ah
    mov al, [cs:last_exit_code]
    jmp near ret_clear_carry

; Map file handle BX (5..8) -> FCB pointer in CS:DI
map_handle_to_fcb:
    cmp bx, 5
    jz fcb_is_5
    cmp bx, 6
    jz fcb_is_6
    cmp bx, 7
    jz fcb_is_7
    cmp bx, 8
    jz fcb_is_8
    stc
    ret
fcb_is_5:
    mov di, fcb_slot_5
    clc
    ret
fcb_is_6:
    mov di, fcb_slot_6
    clc
    ret
fcb_is_7:
    mov di, fcb_slot_7
    clc
    ret
fcb_is_8:
    mov di, fcb_slot_8
    clc
    ret

; Normalize ASCIIZ path in DS:SI -> flat 8.3 filename in CS:path_scratch (CS:0C24h)
normalize_asciiz_to_fcb_name:
    push ax
    push bx
    push cx
    push di
    mov ax, cs
    mov es, ax
    mov di, path_scratch
    xor dl, dl
    cmp byte [si], 0x00
    jz norm_done
    cmp byte [si+1], ':'
    jnz scan_last_sep
    mov dl, [si]
    add si, 2
scan_last_sep:
    mov bx, si
scan_sep_loop:
    lodsb
    or al, al
    jz copy_base_name
    cmp al, 0x5C
    jz update_base_ptr
    cmp al, '/'
    jnz scan_sep_loop
update_base_ptr:
    mov bx, si
    jmp short scan_sep_loop
copy_base_name:
    mov si, bx
    or dl, dl
    jz copy_chars
    mov al, dl
    stosb
    mov al, ':'
    stosb
copy_chars:
    mov cx, 14
copy_chars_loop:
    lodsb
    stosb
    or al, al
    jz norm_done
    loop copy_chars_loop
    xor al, al
    stosb
norm_done:
    mov ax, cs
    mov ds, ax
    mov si, path_scratch
    pop di
    pop cx
    pop bx
    pop ax
    ret

; Allocate a free FCB slot (returns handle BX=5..8, FCB in CS:DI)
alloc_fcb_slot:
    mov bx, 5
    mov di, fcb_slot_5
    cmp byte [cs:di+1], 0x00
    jz alloc_slot_done
    mov bx, 6
    mov di, fcb_slot_6
    cmp byte [cs:di+1], 0x00
    jz alloc_slot_done
    mov bx, 7
    mov di, fcb_slot_7
    cmp byte [cs:di+1], 0x00
    jz alloc_slot_done
    mov bx, 8
    mov di, fcb_slot_8
alloc_slot_done:
    ret

; Parse ASCIIZ path DS:DX into FCB at CS:DI via INT 21h AH=29h AL=01h
parse_path_into_fcb:
    mov si, dx
    call normalize_asciiz_to_fcb_name
    push di
    mov cx, 20
    xor ax, ax
    rep stosw
    pop di
    push di
    mov ax, 0x2901
    pushf
    call far [cs:old_int21_off]
    pop di
    ret

; Check if FCB name is "CON        " (returns Carry=1 if CON device)
check_fcb_is_con:
    cmp word [cs:di+1], 0x4F43  ; "CO"
    jnz not_con_dev
    cmp word [cs:di+3], 0x204E  ; "N "
    jnz not_con_dev
    cmp word [cs:di+5], 0x2020  ; "  "
    jz is_con_dev
not_con_dev:
    clc
    ret
is_con_dev:
    mov byte [cs:di+1], 0x00
    stc
    ret

; AH=3Dh: Open File (ASCIIZ DS:DX -> handle in AX)
handle_open_file:
    push ds
    push es
    push si
    push di
    push bx
    push cx
    push dx
    call alloc_fcb_slot
    call parse_path_into_fcb
    call check_fcb_is_con
    jnc open_disk_fcb
    pop dx
    pop cx
    pop bx
    pop di
    pop si
    pop es
    pop ds
    mov ax, 1
    jmp near ret_clear_carry

open_disk_fcb:
    mov dx, di
    mov ah, 0x0F
    pushf
    call far [cs:old_int21_off]
    or al, al
    jnz open_create_failed
    mov word [cs:di+0x0E], 1
    mov word [cs:di+0x21], 0
    mov word [cs:di+0x23], 0
    mov ax, bx
    pop dx
    pop cx
    pop bx
    pop di
    pop si
    pop es
    pop ds
    jmp near ret_clear_carry

open_create_failed:
    mov byte [cs:di+1], 0x00
    pop dx
    pop cx
    pop bx
    pop di
    pop si
    pop es
    pop ds
    mov ax, 2
    jmp near ret_set_carry

; AH=3Ch & AH=5Bh: Create File (ASCIIZ DS:DX -> handle in AX)
handle_create_file:
    push ds
    push es
    push si
    push di
    push bx
    push cx
    push dx
    call alloc_fcb_slot
    call parse_path_into_fcb
    call check_fcb_is_con
    jnc create_disk_fcb
    pop dx
    pop cx
    pop bx
    pop di
    pop si
    pop es
    pop ds
    mov ax, 1
    jmp near ret_clear_carry

create_disk_fcb:
    mov dx, di
    mov ah, 0x13            ; Delete existing file if any
    pushf
    call far [cs:old_int21_off]
    mov dx, di
    mov ah, 0x16            ; FCB Create File
    pushf
    call far [cs:old_int21_off]
    or al, al
    jnz open_create_failed
    mov word [cs:di+0x0E], 1
    mov word [cs:di+0x21], 0
    mov word [cs:di+0x23], 0
    mov ax, bx
    pop dx
    pop cx
    pop bx
    pop di
    pop si
    pop es
    pop ds
    jmp near ret_clear_carry

; AH=3Eh: Close File Handle BX
handle_close_file:
    cmp bx, 4
    jna close_done_ok
    push ds
    push dx
    push di
    call map_handle_to_fcb
    jc close_pop_done
    push cs
    pop ds
    mov dx, di
    mov ah, 0x10
    pushf
    call far [cs:old_int21_off]
    mov byte [cs:di+1], 0x00
close_pop_done:
    pop di
    pop dx
    pop ds
close_done_ok:
    xor ax, ax
    jmp near ret_clear_carry

; AH=3Fh: Read from File Handle BX (CX bytes into DS:DX)
handle_read_file:
    cmp bx, 4
    jna read_eof_zero
    push ds
    push dx
    push bx
    push di
    call map_handle_to_fcb
    jc read_pop_zero
    mov ah, 0x1A            ; Set DTA = DS:DX
    pushf
    call far [cs:old_int21_off]
    push cs
    pop ds
    mov dx, di
    mov ah, 0x27            ; FCB Random Block Read
    pushf
    call far [cs:old_int21_off]
    mov ax, cx
    pop di
    pop bx
    pop dx
    pop ds
    jmp near ret_clear_carry

read_pop_zero:
    pop di
    pop bx
    pop dx
    pop ds
read_eof_zero:
    xor ax, ax
    jmp near ret_clear_carry

; AH=40h: Write to File Handle BX (CX bytes from DS:DX)
handle_write_file:
    cmp bx, 1
    jz write_to_console
    cmp bx, 2
    jz write_to_console
    cmp bx, 4
    jna write_std_noop
    push ds
    push dx
    push bx
    push di
    call map_handle_to_fcb
    jc write_bad_handle
    mov ah, 0x1A            ; Set DTA = DS:DX
    pushf
    call far [cs:old_int21_off]
    push cs
    pop ds
    mov dx, di
    mov ah, 0x28            ; FCB Random Block Write
    pushf
    call far [cs:old_int21_off]
    mov ax, cx
    pop di
    pop bx
    pop dx
    pop ds
    jmp near ret_clear_carry

write_bad_handle:
    pop di
    pop bx
    pop dx
    pop ds
    mov ax, 6
    jmp near ret_set_carry

write_std_noop:
    mov ax, cx
    jmp near ret_clear_carry

write_to_console:
    push si
    push cx
    mov si, dx
    jcxz write_con_done
write_con_loop:
    lodsb
    call putc_both
    loop write_con_loop
write_con_done:
    pop cx
    pop si
    mov ax, cx
    jmp near ret_clear_carry

; AH=41h: Unlink (Delete) File DS:DX
handle_unlink_file:
    push ds
    push es
    push si
    push di
    push bx
    push cx
    push dx
    mov di, fcb_temp_work
    call parse_path_into_fcb
    mov dx, di
    mov ah, 0x13
    pushf
    call far [cs:old_int21_off]
    pop dx
    pop cx
    pop bx
    pop di
    pop si
    pop es
    pop ds
    or al, al
    jnz unlink_err
    xor ax, ax
    jmp near ret_clear_carry
unlink_err:
    mov ax, 2
    jmp near ret_set_carry

; AH=42h: Lseek File Handle BX (AL=origin, CX:DX=offset -> DX:AX)
handle_lseek_file:
    cmp bx, 4
    jna lseek_std_zero
    push di
    call map_handle_to_fcb
    jc lseek_bad_handle
    cmp al, 0x00
    jz lseek_set
    cmp al, 0x01
    jz lseek_cur
    mov ax, [cs:di+0x10]
    mov bx, [cs:di+0x12]
    add ax, dx
    adc bx, cx
    jmp short lseek_store
lseek_cur:
    mov ax, [cs:di+0x21]
    mov bx, [cs:di+0x23]
    add ax, dx
    adc bx, cx
    jmp short lseek_store
lseek_set:
    mov ax, dx
    mov bx, cx
lseek_store:
    mov [cs:di+0x21], ax
    mov [cs:di+0x23], bx
    mov dx, bx
    pop di
    jmp near ret_clear_carry
lseek_bad_handle:
    pop di
    mov ax, 6
    jmp near ret_set_carry
lseek_std_zero:
    xor ax, ax
    xor dx, dx
    jmp near ret_clear_carry

; AH=43h: Get/Set File Attributes (AL=00h Get, AL=01h Set)
handle_chmod_file:
    cmp al, 0x01
    jz chmod_set_ok
    push ds
    push es
    push si
    push di
    push bx
    push cx
    push dx
    mov di, fcb_temp_work
    call parse_path_into_fcb
    mov dx, di
    mov ah, 0x0F
    pushf
    call far [cs:old_int21_off]
    or al, al
    jnz chmod_not_found
    mov dx, di
    mov ah, 0x10
    pushf
    call far [cs:old_int21_off]
    pop dx
    pop cx
    pop bx
    pop di
    pop si
    pop es
    pop ds
    xor cx, cx
    xor ax, ax
    jmp near ret_clear_carry
chmod_not_found:
    pop dx
    pop cx
    pop bx
    pop di
    pop si
    pop es
    pop ds
    mov ax, 2
    jmp near ret_set_carry
chmod_set_ok:
    xor ax, ax
    jmp near ret_clear_carry

; AH=44h: IOCTL (AL=00h Get Device Info)
handle_ioctl:
    cmp al, 0x00
    jnz ioctl_other_ok
    cmp bx, 4
    jna ioctl_char_dev
    xor dx, dx
    mov ax, dx
    jmp near ret_clear_carry
ioctl_char_dev:
    mov dx, 0x0083          ; Character device (ISDEV | Console In/Out)
    mov ax, dx
    jmp near ret_clear_carry
ioctl_other_ok:
    xor ax, ax
    jmp near ret_clear_carry

; AH=47h: Get Current Directory (writes "" into DS:SI)
handle_getcwd:
    mov byte [si], 0x00
    xor ax, ax
    jmp short ret_clear_carry

; AH=48h: Allocate Memory (returns insufficient memory BX=0 so Watcom uses DGROUP brk)
handle_alloc_mem:
    mov ax, 8
    xor bx, bx
    jmp short ret_set_carry

; AH=49h / AH=4Ah: Free / Resize Memory Block
handle_free_resize_mem:
    xor ax, ax
    jmp short ret_clear_carry

; AH=56h: Rename File (DS:DX -> ES:DI)
handle_rename_file:
    push ds
    push es
    push si
    push di
    push bx
    push cx
    push dx
    push ds
    push dx
    mov ax, es
    mov ds, ax
    mov dx, di
    mov di, fcb_temp_work
    call parse_path_into_fcb
    mov si, fcb_temp_work + 1
    mov di, rename_dst_name
    mov cx, 11
    rep movsb
    pop dx
    pop ds
    mov di, fcb_temp_work
    call parse_path_into_fcb
    mov byte [cs:fcb_temp_work + 0x10], 0x00
    mov si, rename_dst_name
    mov di, fcb_temp_work + 0x11
    mov cx, 11
    rep movsb
    mov dx, fcb_temp_work
    mov ah, 0x17
    pushf
    call far [cs:old_int21_off]
    pop dx
    pop cx
    pop bx
    pop di
    pop si
    pop es
    pop ds
    or al, al
    jnz rename_failed
    xor ax, ax
    jmp short ret_clear_carry
rename_failed:
    mov ax, 5
    jmp short ret_set_carry

; AH=63h: Get DBCS Lead Byte Table (points DS:SI to empty word 0000h)
handle_dbcs_table:
    push cs
    pop ds
    mov si, empty_dbcs_tbl
    xor al, al
    jmp short ret_clear_carry

; AH=66h: Get/Set Global Code Page (437 US)
handle_codepage:
    mov bx, 437
    mov dx, 437
    xor ax, ax
    jmp short ret_clear_carry

; AH=68h: Commit / Flush File
handle_commit_file:
    xor ax, ax
    jmp short ret_clear_carry

ret_clear_carry:
    push bp
    mov bp, sp
    and word [bp+6], 0xFFFE
    pop bp
    iret

ret_set_carry:
    push bp
    mov bp, sp
    or word [bp+6], 0x0001
    pop bp
    iret

empty_dbcs_tbl:  dw 0x0000
                 dw 0x0000
saved_child_cs:  dw 0x0000
last_exit_code:  db 0x00

path_scratch    equ 0x0C24
rename_dst_name equ 0x0C38
fcb_slot_7      equ 0x0C44
fcb_slot_8      equ 0x0C6C
fcb_temp_work   equ 0x0C94

times 4096 - ($ - $$) db 0x00
