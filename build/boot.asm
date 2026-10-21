
; OS32 - Pure Assembly 32-bit Kernel
; Multiboot-compatible kernel for GRUB
; Assumes GRUB enters in 32-bit protected mode.

BITS 32

section .text align=4
global _start
global mb_header
extern rust_kernel_entry

%define VGA_ATTR       0x0F
%define KERNEL_CS      0x08
%define KERNEL_DS      0x10
%define IDT_ENTRIES    32
%define VGA_MEMORY     0xB8000

; ------------------------------------------------------------
; Register-label helpers
; ------------------------------------------------------------

pushreglabel_eax:
    mov esi, reg_eax
    ret
pushreglabel_ebx:
    mov esi, reg_ebx
    ret
pushreglabel_ecx:
    mov esi, reg_ecx
    ret
pushreglabel_edx:
    mov esi, reg_edx
    ret
pushreglabel_esi:
    mov esi, reg_esi
    ret
pushreglabel_edi:
    mov esi, reg_edi
    ret
pushreglabel_ebp:
    mov esi, reg_ebp
    ret
pushreglabel_esp:
    mov esi, reg_esp
    ret
pushreglabel_cs:
    mov esi, reg_cs
    ret
pushreglabel_ds:
    mov esi, reg_ds
    ret
pushreglabel_es:
    mov esi, reg_es
    ret
pushreglabel_fs:
    mov esi, reg_fs
    ret
pushreglabel_gs:
    mov esi, reg_gs
    ret
pushreglabel_ss:
    mov esi, reg_ss
    ret

; ------------------------------------------------------------
; Register-printing macros
; ------------------------------------------------------------

%macro PRINTREGS 0
    VGA_PRINT_REG32 eax, 0
    VGA_PRINT_REG32 ebx, 160
    VGA_PRINT_REG32 ecx, 320
    VGA_PRINT_REG32 edx, 480
    VGA_PRINT_REG32 esi, 640
    VGA_PRINT_REG32 edi, 800
    VGA_PRINT_REG32 ebp, 960
    VGA_PRINT_REG32 esp, 1120

    VGA_PRINT_REG16 cs, 1280
    VGA_PRINT_REG16 ds, 1440
    VGA_PRINT_REG16 es, 1600
    VGA_PRINT_REG16 fs, 1760
    VGA_PRINT_REG16 gs, 1920
    VGA_PRINT_REG16 ss, 2080
%endmacro

%macro VGA_PRINT_REG16 2
    pushad

    mov edi, VGA_MEMORY
    add edi, %2

    call pushreglabel_%1
    mov ecx, 4

%%printlabel:
    mov al, [esi]
    mov ah, VGA_ATTR
    stosw
    inc esi
    dec ecx
    jnz %%printlabel

    add edi, 8

    ; Preserve the original 16-bit register value.
    mov ax, %1
    movzx ebp, ax

    mov ebx, 4

%%digit:
    mov ecx, ebx
    dec ecx
    shl ecx, 2

    mov edx, ebp
    shr edx, cl
    and edx, 0x0F

    cmp edx, 9
    jbe %%numeric
    add dl, 'A' - 10
    jmp %%write

%%numeric:
    add dl, '0'

%%write:
    mov al, dl
    mov ah, VGA_ATTR
    stosw

    dec ebx
    jnz %%digit

    popad
%endmacro

%macro VGA_PRINT_REG32 2
    pushad

    mov edi, VGA_MEMORY
    add edi, %2

    call pushreglabel_%1
    mov ecx, 5

%%printlabel:
    mov al, [esi]
    mov ah, VGA_ATTR
    stosw
    inc esi
    dec ecx
    jnz %%printlabel

    add edi, 10

    mov ebp, %1
    mov ebx, 8

%%digit:
    mov ecx, ebx
    dec ecx
    shl ecx, 2

    mov edx, ebp
    shr edx, cl
    and edx, 0x0F

    cmp edx, 9
    jbe %%numeric
    add dl, 'A' - 10
    jmp %%write

%%numeric:
    add dl, '0'

%%write:
    mov al, dl
    mov ah, VGA_ATTR
    stosw

    dec ebx
    jnz %%digit

    popad
%endmacro

%macro VGA_PRINT 2
    pushad

    mov edi, VGA_MEMORY
    add edi, %2

    mov esi, %1
    mov ecx, 4

%%printlabel:
    mov al, [esi]
    mov ah, VGA_ATTR
    stosw
    inc esi
    dec ecx
    jnz %%printlabel

    mov ebx, 4

%%digit:
    mov ecx, ebx
    dec ecx
    shl ecx, 2

    mov edx, eax
    shr edx, cl
    and edx, 0x0F

    cmp edx, 9
    jbe %%numeric
    add dl, 'A' - 10
    jmp %%write

%%numeric:
    add dl, '0'

%%write:
    mov al, dl
    mov ah, VGA_ATTR
    stosw

    dec ebx
    jnz %%digit

    popad
%endmacro

; ------------------------------------------------------------
; Print IDT number at row 20 (offset = 20 * 160 = 3200)
; Input: al = IDT number
; ------------------------------------------------------------

PRINT_IDT_NUMBER:
    pushad

    mov edi, VGA_MEMORY
    add edi, 3200

    ; Print "IDT:" label
    mov byte [edi], 'I'
    mov byte [edi+1], VGA_ATTR
    inc edi
    inc edi

    mov byte [edi], 'D'
    mov byte [edi+1], VGA_ATTR
    inc edi
    inc edi

    mov byte [edi], 'T'
    mov byte [edi+1], VGA_ATTR
    inc edi
    inc edi

    mov byte [edi], ':'
    mov byte [edi+1], VGA_ATTR
    inc edi
    inc edi

    ; Print IDT number in hex (preserve original in bl)
    mov bl, al

    ; High nibble
    mov dl, bl
    shr dl, 4
    cmp dl, 9
    jbe .idt_high_numeric
    add dl, 'A' - 10
    jmp .idt_high_write
.idt_high_numeric:
    add dl, '0'
.idt_high_write:
    mov al, dl
    mov ah, VGA_ATTR
    stosw

    ; Low nibble
    mov dl, bl
    and dl, 0x0F
    cmp dl, 9
    jbe .idt_low_numeric
    add dl, 'A' - 10
    jmp .idt_low_write
.idt_low_numeric:
    add dl, '0'
.idt_low_write:
    mov al, dl
    mov ah, VGA_ATTR
    stosw

    popad
    ret

; ------------------------------------------------------------
; Print error code at bottom left (row 24, offset = 24 * 160 = 3840)
; Input: eax = error code
; ------------------------------------------------------------

PRINT_ERROR_CODE:
    VGA_PRINT err_label, 3840
    ret

; ------------------------------------------------------------
; Multiboot v1 header
; Keep this in the first 8 KiB of the loaded image.
; ------------------------------------------------------------

align 4
mb_header:
    dd 0x1BADB002
    dd 0
    dd -(0x1BADB002)

; ------------------------------------------------------------
; Kernel entry
; ------------------------------------------------------------

align 4
_start:
    cli

    ; Establish a valid stack immediately.
    mov esp, stack_top
    cld

    ; Install our GDT before using our own selectors.
    call setup_gdt

    ; Install an IDT before enabling normal interrupts.
    call setup_idt

    ; Clear VGA text buffer.
    mov edi, VGA_MEMORY
    mov ecx, 2000
    mov ax, 0x0720
    rep stosw

    ; Display boot message.
    mov esi, msg
    mov edi, VGA_MEMORY

.print_message:
    lodsb
    test al, al
    jz .start_animation

    mov ah, VGA_ATTR
    stosw
    jmp .print_message

.start_animation:
    mov word [ball_x], 0
    mov word [ball_y], 12
    mov word [ball_dx], 1

    mov ebp, 20

.animation_loop:
    ; Erase the previous ball position.
    movzx eax, word [ball_y]
    imul eax, 80
    movzx ebx, word [ball_x]
    add eax, ebx
    shl eax, 1

    mov edi, VGA_MEMORY
    add edi, eax
    mov word [edi], 0x0720

    ; Update horizontal position.
    mov ax, [ball_x]
    add ax, [ball_dx]

    cmp ax, 78
    jle .check_left

    mov ax, 78
    mov word [ball_dx], -1

.check_left:
    cmp ax, 0
    jge .store_x

    xor ax, ax
    mov word [ball_dx], 1

.store_x:
    mov [ball_x], ax

    ; Draw the ball at the new position.
    movzx eax, word [ball_y]
    imul eax, 80
    movzx ebx, word [ball_x]
    add eax, ebx
    shl eax, 1

    mov edi, VGA_MEMORY
    add edi, eax
    mov word [edi], 0x0FB0

    ; Animation delay.
    mov ecx, 5000000

.delay_loop:
    dec ecx
    jnz .delay_loop

    dec ebp
    jnz .animation_loop

    jmp kernel

; ------------------------------------------------------------
; GDT setup
;
; GDTR format in 32-bit mode:
;   offset +0: 16-bit limit
;   offset +2: 32-bit linear base
;
; Selectors:
;   0x00 = null
;   0x08 = ring 0 code
;   0x10 = ring 0 data
; ------------------------------------------------------------

setup_gdt:
    cli

    mov word [gdt_buffer], gdt_end - gdt_table - 1
    mov dword [gdt_buffer + 2], gdt_table

    lgdt [gdt_buffer]

    ; Reload CS with a far jump.
    jmp KERNEL_CS:.reload_cs

.reload_cs:
    mov ax, KERNEL_DS
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ret

; ------------------------------------------------------------
; IDT handler macro
; ------------------------------------------------------------

%macro IDT_HANDLER 1
idt_handler_%1:
    cli
    cld

    pushad
    ; Print IDT number at row 20
    mov al, %1
    call PRINT_IDT_NUMBER

    ; Save segment registers and load kernel data selector.
    xor eax, eax
    mov ax, ds
    push eax

    mov ax, KERNEL_DS
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    ; Handle error codes for vectors that push them
    ; Vectors 8, 10, 11, 12, 13, 14, 17 push CPU error codes on Pentium
    ; Error code is at [esp+36] after pushad + segment save (32 + 4 bytes)
%if %1 == 8 || %1 == 10 || %1 == 11 || %1 == 12 || %1 == 13 || %1 == 14 || %1 == 17
    mov eax, [esp + 36]
    call PRINT_ERROR_CODE
%endif

    PRINTREGS

    ; Restore the saved segment value and general registers.
    pop eax
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    popad

    ; Remove error code from stack if present (adjusts esp for iret)
%if %1 == 8 || %1 == 10 || %1 == 11 || %1 == 12 || %1 == 13 || %1 == 14 || %1 == 17
    add esp, 4
%endif

.halt:
    hlt
    jmp .halt
%endmacro

; Generate handlers for vectors 0-31
IDT_HANDLER 0
IDT_HANDLER 1
IDT_HANDLER 2
IDT_HANDLER 3
IDT_HANDLER 4
IDT_HANDLER 5
IDT_HANDLER 6
IDT_HANDLER 7
IDT_HANDLER 8
IDT_HANDLER 9
IDT_HANDLER 10
IDT_HANDLER 11
IDT_HANDLER 12
IDT_HANDLER 13
IDT_HANDLER 14
IDT_HANDLER 15
IDT_HANDLER 16
IDT_HANDLER 17
IDT_HANDLER 18
IDT_HANDLER 19
IDT_HANDLER 20
IDT_HANDLER 21
IDT_HANDLER 22
IDT_HANDLER 23
IDT_HANDLER 24
IDT_HANDLER 25
IDT_HANDLER 26
IDT_HANDLER 27
IDT_HANDLER 28
IDT_HANDLER 29
IDT_HANDLER 30
IDT_HANDLER 31

; ------------------------------------------------------------
; IDT setup
;
; Each gate is 8 bytes:
;   +0: handler offset bits 0-15
;   +2: code selector
;   +4: reserved byte
;   +5: attributes (0x8E)
;   +6: handler offset bits 16-31
; ------------------------------------------------------------

%macro IDT_GATE 1
    mov eax, idt_handler_%1
    stosw
    mov ax, KERNEL_CS
    stosw
    mov al, 0
    stosb
    mov al, 0x8E
    stosb
    mov eax, idt_handler_%1
    shr eax, 16
    stosw
%endmacro

setup_idt:
    cli
    mov edi, idt_table

    IDT_GATE 0
    IDT_GATE 1
    IDT_GATE 2
    IDT_GATE 3
    IDT_GATE 4
    IDT_GATE 5
    IDT_GATE 6
    IDT_GATE 7
    IDT_GATE 8
    IDT_GATE 9
    IDT_GATE 10
    IDT_GATE 11
    IDT_GATE 12
    IDT_GATE 13
    IDT_GATE 14
    IDT_GATE 15
    IDT_GATE 16
    IDT_GATE 17
    IDT_GATE 18
    IDT_GATE 19
    IDT_GATE 20
    IDT_GATE 21
    IDT_GATE 22
    IDT_GATE 23
    IDT_GATE 24
    IDT_GATE 25
    IDT_GATE 26
    IDT_GATE 27
    IDT_GATE 28
    IDT_GATE 29
    IDT_GATE 30
    IDT_GATE 31

    ; IDTR limit and base.
    mov word [idt_ptr], idt_table_end - idt_table - 1
    mov dword [idt_ptr + 2], idt_table

    lidt [idt_ptr]
    ret



; ------------------------------------------------------------
; Kernel handoff
; ------------------------------------------------------------

kernel:
    cli

    ; GDT and IDT have already been initialized.
    ; Interrupts remain disabled until an IRQ/PIC policy is set.
    call rust_kernel_entry
    int 0x3
.halt:
    cli
    hlt
    jmp .halt

; ------------------------------------------------------------
; Read-only initialized data
; ------------------------------------------------------------

section .rodata align=8

msg:
    db "OS32 booted successfully!", 0

reg_eax: db "eax:", 0
reg_ebx: db "ebx:", 0
reg_ecx: db "ecx:", 0
reg_edx: db "edx:", 0
reg_esi: db "esi:", 0
reg_edi: db "edi:", 0
reg_ebp: db "ebp:", 0
reg_esp: db "esp:", 0

reg_cs: db "cs:", 0
reg_ds: db "ds:", 0
reg_es: db "es:", 0
reg_fs: db "fs:", 0
reg_gs: db "gs:", 0
reg_ss: db "ss:", 0

err_label: db "ERR:", 0

; ------------------------------------------------------------
; GDT descriptors
; These must exist in memory before LGDT executes.
; ------------------------------------------------------------

section .data align=8

gdt_table:
    dq 0x0000000000000000  ; Null descriptor
    dq 0x00CF9A000000FFFF  ; 0x08: flat ring 0 code
    dq 0x00CF92000000FFFF  ; 0x10: flat ring 0 data
gdt_end:

; ------------------------------------------------------------
; Zero-initialized data
; ------------------------------------------------------------

section .bss align=4096

stack_bottom:
    resb 16384
stack_top:

ball_x:
    resw 1

ball_y:
    resw 1

ball_dx:
    resw 1

; GDTR: 2-byte limit + 4-byte base.
gdt_buffer:
    resb 6

; IDTR: 2-byte limit + 4-byte base.
idt_ptr:
    resb 6

; 32 entries x 8 bytes per entry.
idt_table:
    resb 32 * 8
idt_table_end:
