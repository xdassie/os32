
; OS32 - Pure Assembly 32-bit Kernel
; Multiboot-compatible kernel for GRUB
; Assumes GRUB enters in 32-bit protected mode.

BITS 32

section .text align=4
global _start
global mb_header
global ring3_task
global ring3_counter_mem
extern rust_kernel_entry
extern rust_kernel_irq
extern vga_print_reg32
extern vga_print_reg16
extern vga_print
extern print_idt_number
extern print_error_code
extern print_fault_location

%define VGA_ATTR       0x0F
%define KERNEL_CS      0x08
%define KERNEL_DS      0x10
%define KERNEL_TSS     0x18
%define USER_CS        0x23        ; GDT index 4, RPL=3
%define USER_DS        0x2B        ; GDT index 5, RPL=3
%define IDT_ENTRIES    48
%define VGA_MEMORY     0xB8000

; PIC ports
%define PIC1_CMD       0x20
%define PIC1_DATA      0x21
%define PIC2_CMD       0xA0
%define PIC2_DATA      0x21

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
    ; Call Rust function: vga_print_reg16(value, offset, label)
    ; Push args right-to-left for cdecl calling convention
    push reg_%1          ; Push label pointer (3rd arg)
    push dword %2        ; Push offset (2nd arg)
    push %1              ; Push value (1st arg)
    call vga_print_reg16
    add esp, 12          ; Clean up arguments
%endmacro

%macro VGA_PRINT_REG32 2
    ; Call Rust function: vga_print_reg32(value, offset, label)
    ; Push args right-to-left for cdecl calling convention
    push reg_%1          ; Push label pointer (3rd arg)
    push dword %2        ; Push offset (2nd arg)
    push %1              ; Push value (1st arg)
    call vga_print_reg32
    add esp, 12          ; Clean up arguments
%endmacro

%macro VGA_PRINT 2
    ; Call Rust function: vga_print(value, offset, label)
    ; Push args right-to-left for cdecl calling convention
    push %1              ; Push label pointer (3rd arg)
    push dword %2        ; Push offset (2nd arg)
    push %1              ; Push value (1st arg)
    call vga_print
    add esp, 12          ; Clean up arguments
%endmacro

; ------------------------------------------------------------
; Print IDT number at row 20 (offset = 20 * 160 = 3200)
; Input: al = IDT number
; ------------------------------------------------------------

PRINT_IDT_NUMBER:
    ; Call Rust function: print_idt_number(idt_num)
    ; al already contains the IDT number
    movzx eax, al        ; Zero-extend al to eax
    push eax             ; Push idt_num as argument
    call print_idt_number
    add esp, 4           ; Clean up stack
    ret

; ------------------------------------------------------------
; Print error code at bottom left (row 24, offset = 24 * 160 = 3840)
; Input: eax = error code
; ------------------------------------------------------------

PRINT_ERROR_CODE:
    ; Call Rust function: print_error_code(error_code)
    ; eax already contains the error code
    push eax             ; Preserve caller's eax and pass as argument
    call print_error_code
    pop eax              ; Restore caller's eax
    ret

; ------------------------------------------------------------
; Print fault location (EIP) at row 23 (offset = 23 * 160 = 3680)
; Input: eax = EIP value
; ------------------------------------------------------------

PRINT_FAULT_LOCATION:
    ; Call Rust function: print_fault_location(eip)
    ; eax already contains the EIP
    push eax             ; Preserve caller's eax and pass as argument
    call print_fault_location
    pop eax              ; Restore caller's eax
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

    ; Setup TSS descriptor with correct base address
    ; Standard Intel 32-bit TSS is 104 bytes (0x68)
    ; Limit = 103 (0x67) for TSS
    ; Standard Intel descriptor format:
    ;   Bytes 0-1: limit[15:0]
    ;   Bytes 2-4: base[23:0]
    ;   Byte 5: access
    ;   Byte 6: flags(4) + limit[19:16](4)
    ;   Byte 7: base[31:24]
    mov eax, tss                    ; TSS base address
    mov word [gdt_table + 24], 0x0067     ; limit[15:0] = 0x0067
    movzx ebx, word [eax]               ; base[15:0]
    mov [gdt_table + 26], bx
    movzx ebx, byte [eax + 2]           ; base[23:16]
    mov [gdt_table + 28], bl            ; base[23:16]
    mov byte [gdt_table + 29], 0x89     ; access = 0x89 (TSS available)
    mov byte [gdt_table + 30], 0x00     ; flags + limit[19:16] = 0x00
    mov byte [gdt_table + 31], 0x00     ; base[31:24] = 0x00
    
    ; GDT limit: (6 descriptors * 8 bytes) - 1 = 47
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

    ; Initialize TSS fields
    ; esp0/ss0 for ring 0 exceptions
    mov eax, stack_top
    mov [tss], eax           ; esp0 (offset 0)
    mov word [tss + 4], KERNEL_DS  ; ss0 (offset 4)

    ; Load Task Register with TSS selector
    mov ax, KERNEL_TSS
    ltr ax

    ret

; ------------------------------------------------------------
; Special IDT handler for int 0x3 (breakpoint) - wait for keypress
; ------------------------------------------------------------

idt_handler_3:
    cli
    cld

    ; Set up data segment for VGA access
    mov ax, KERNEL_DS
    mov ds, ax
    mov es, ax

    ; Wait for PS/2 keyboard output buffer to be full
.wait_for_key:
    in al, 0x64
    test al, 1
    jz .wait_for_key

    ; Read scancode from data port
    in al, 0x60

    ; Print "KEY:" label at row 20, col 0 (offset 3200)
    mov edi, VGA_MEMORY
    add edi, 3200

    mov byte [edi], 'K'
    mov byte [edi+1], VGA_ATTR
    inc edi
    inc edi

    mov byte [edi], 'E'
    mov byte [edi+1], VGA_ATTR
    inc edi
    inc edi

    mov byte [edi], 'Y'
    mov byte [edi+1], VGA_ATTR
    inc edi
    inc edi

    mov byte [edi], ':'
    mov byte [edi+1], VGA_ATTR
    inc edi
    inc edi

    ; Print scancode as 2 hex digits
    mov bl, al

    ; High nibble
    mov dl, bl
    shr dl, 4
    cmp dl, 9
    jbe .key_high_numeric
    add dl, 'A' - 10
    jmp .key_high_write
.key_high_numeric:
    add dl, '0'
.key_high_write:
    mov al, dl
    mov ah, VGA_ATTR
    stosw

    ; Low nibble
    mov dl, bl
    and dl, 0x0F
    cmp dl, 9
    jbe .key_low_numeric
    add dl, 'A' - 10
    jmp .key_low_write
.key_low_numeric:
    add dl, '0'
.key_low_write:
    mov al, dl
    mov ah, VGA_ATTR
    stosw

    iret

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
    ; Stack layout after pushad + push idt_num:
    ;   [esp+0] = idt_num (pushed by PRINT_IDT_NUMBER)
    ;   [esp+4] = return address
    ;   [esp+8..39] = pushad saved registers (32 bytes)
    ;   [esp+40] = error code (pushed by CPU)
    ;   [esp+44] = ss (pushed by CPU)
    ;   [esp+48] = eip (pushed by CPU)
%if %1 == 8 || %1 == 10 || %1 == 11 || %1 == 12 || %1 == 13 || %1 == 14 || %1 == 17
    mov eax, [esp + 40]
    call PRINT_ERROR_CODE
%endif

    ; For IDT 0xD (General Protection Fault), print faulting EIP
    ; EIP is at [esp+48] (after error code at +40 and ss at +44)
%if %1 == 13
    mov eax, [esp + 48]
    call PRINT_FAULT_LOCATION
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
; IDT_HANDLER 3 - custom handler above
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

%macro IRQ_HANDLER 2
idt_handler_%1:
    cli
    cld

    ; Save current segment registers
    push ds
    push es
    push fs
    push gs

    ; Load kernel data segment for Rust code
    mov ax, KERNEL_DS
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    ; Preserve interrupted general-purpose registers
    pushad

    ; Send EOI to the correct PIC(s).
    mov al, 0x20
%if %1 >= 0x28
    out PIC2_CMD, al       ; Slave PIC for IRQ 8-15
%endif
    out PIC1_CMD, al       ; Master PIC

    ; Pass IRQ number = vector - 0x20
    push dword (%1 - 0x20)
    call rust_kernel_irq
    add esp, 4             ; Remove argument

    ; Restore interrupted registers
    popad

    ; Restore segment registers
    pop gs
    pop fs
    pop es
    pop ds

    iret
%endmacro

; ------------------------------------------------------------
; Ring 3 task - runs in user mode, increments counter
; ------------------------------------------------------------

ring3_task:
    ; Ring 3 entry point!
    nop                         ; First instruction in ring 3
    nop
    nop
    ; Load ring 3 data segment (DS/ES not auto-loaded by IRET)
    mov ax, USER_DS
    mov ds, ax
    mov es, ax
    ; Write 'R3' to VGA to confirm ring 3 entry
    mov edi, VGA_MEMORY
    mov word [edi], 0x0752      ; 'R' white on black
    mov word [edi + 2], 0x0733  ; '3' white on black

    ; Initialize ring 3 counter location
    mov dword [ring3_counter_mem], 0

.r3_loop:
    ; Increment counter (visible from ring 0 via memory)
    inc dword [ring3_counter_mem]

    ; Small delay
    mov ecx, 1000
.r3_delay:
    dec ecx
    jnz .r3_delay

    ; Continue looping - stay in ring 3
    jmp .r3_loop

IRQ_HANDLER 32, 0   ; Timer
IRQ_HANDLER 33, 1   ; Keyboard
IRQ_HANDLER 34, 2   ; Cascade
IRQ_HANDLER 35, 3   ; COM2
IRQ_HANDLER 36, 4   ; COM1
IRQ_HANDLER 37, 5   ; LPT2
IRQ_HANDLER 38, 6   ; FDD
IRQ_HANDLER 39, 7   ; LPT1
IRQ_HANDLER 40, 8   ; RTC
IRQ_HANDLER 41, 9   ; Reserved
IRQ_HANDLER 42, 10  ; Reserved
IRQ_HANDLER 43, 11  ; Reserved
IRQ_HANDLER 44, 12  ; PS/2 Mouse
IRQ_HANDLER 45, 13  ; COPROC
IRQ_HANDLER 46, 14  ; ATA
IRQ_HANDLER 47, 15  ; ATA

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
    IDT_GATE 32
    IDT_GATE 33
    IDT_GATE 34
    IDT_GATE 35
    IDT_GATE 36
    IDT_GATE 37
    IDT_GATE 38
    IDT_GATE 39
    IDT_GATE 40
    IDT_GATE 41
    IDT_GATE 42
    IDT_GATE 43
    IDT_GATE 44
    IDT_GATE 45
    IDT_GATE 46
    IDT_GATE 47

    ; IDTR limit and base.
    mov word [idt_ptr], idt_table_end - idt_table - 1
    mov dword [idt_ptr + 2], idt_table

    lidt [idt_ptr]
    ret

; ------------------------------------------------------------
; PIC initialization
; Remap PIC1 to 0x20-0x2F, PIC2 to 0x28-0x2F
; ------------------------------------------------------------

setup_pic:
    cli

    ; Save current masks
    in al, PIC1_DATA
    mov ah, al
    in al, PIC2_DATA
    mov bh, al

    ; Start initialization sequence (ICW1)
    mov al, 0x11
    out PIC1_CMD, al
    out PIC2_CMD, al

    ; Set vector offsets (ICW2)
    ; PIC1 -> 0x20, PIC2 -> 0x28
    mov al, 0x20
    out PIC1_DATA, al
    mov al, 0x28
    out PIC2_DATA, al

    ; Tell PICs we have 2 PICs (ICW3)
    mov al, 0x04
    out PIC1_DATA, al
    mov al, 0x02
    out PIC2_DATA, al

    ; ICW4: 8086 mode
    mov al, 0x01
    out PIC1_DATA, al
    out PIC2_DATA, al

    ; Restore masks
    mov al, ah
    out PIC1_DATA, al
    mov al, bh
    out PIC2_DATA, al

    ret

; Send EOI to PIC
send_eoi:
    mov al, 0x20
    out PIC1_CMD, al
    ; Check if IRQ from secondary PIC (IRQ 8-15 -> vectors 0x28-0x2F)
    ; For now, always send to both to be safe
    out PIC2_CMD, al
    ret



; ------------------------------------------------------------
; Page table setup - DISABLED for now (flat memory model)
; Re-enable when virtual memory needed
; ------------------------------------------------------------

; ------------------------------------------------------------
; Kernel handoff
; ------------------------------------------------------------

kernel:
    ; GDT and IDT have already been initialized.
    ; Initialize PIC before enabling interrupts.
    call setup_pic
    call rust_kernel_entry
    ; Continue - launch ring 3 task via IRET
    sti

    ; Initialize ring 3 counter
    xor eax, eax
    mov dword [ring3_counter_mem], eax

    ; Ring 3 transition via IRET
    ; Push frame: ss, esp, eflags, cs, eip (IRET pops in reverse)
    ; Selectors: USER_CS=0x20, USER_DS=0x28 (DPL=3)
    ; Use 32-bit pushes to ensure proper stack alignment

    push dword USER_DS         ; ss (32-bit, zero-extended)
    push ring3_stack_top       ; esp (32-bit)
    push dword 0x202           ; eflags (32-bit, reserved bit 1 + IF)
    push dword USER_CS         ; cs (32-bit, zero-extended)
    push ring3_task            ; eip (32-bit)

    iret

.halt:
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
    dq 0x0000890000000000  ; 0x18: TSS descriptor (placeholder - runtime sets base)
    dq 0x00CFFA000000FFFF  ; 0x20: flat ring 3 code (access=0xFA=DPL3+Type10, base=0)
    dq 0x00CFF2000000FFFF  ; 0x28: flat ring 3 data (access=0xF2=DPL3+Type2, base=0)
gdt_end:

; ------------------------------------------------------------
; Zero-initialized data
; ------------------------------------------------------------

section .bss align=4096

stack_bottom:
    resb 32768
stack_top:

ball_x:
    resw 1

ball_y:
    resw 1

ball_dx:
    resw 1

; Ring 3 stack
ring3_stack_bottom:
    resb 4096
ring3_stack_top:

; Ring 3 counter (shared with Rust)
ring3_counter_mem:
    resd 1

; GDTR: 2-byte limit + 4-byte base.
gdt_buffer:
    resb 6

; IDTR: 2-byte limit + 4-byte base.
idt_ptr:
    resb 6

; 48 entries x 8 bytes per entry.
idt_table:
    resb 48 * 8
idt_table_end:

; TSS (Task State Segment) - 32 bytes for protected mode
; Moved to .data section to allow initialization
; 32-bit TSS format (104 bytes = 0x68)
section .data align=8

tss:
    ; Intel 32-bit Task State Segment (104 bytes, limit=103=0x67)
    dd stack_top        ; esp0 (offset 0x00)
    dw KERNEL_DS        ; ss0 (offset 0x04)
    dw 0                ; reserved (offset 0x06)
    dd 0                ; esp1 (offset 0x08)
    dw 0                ; ss1 (offset 0x0C)
    dw 0                ; reserved (offset 0x0E)
    dd 0                ; esp2 (offset 0x10)
    dw 0                ; ss2 (offset 0x14)
    dw 0                ; reserved (offset 0x16)
    dd 0                ; cr3 (offset 0x18)
    dd 0                ; eip (offset 0x1C)
    dd 0                ; eflags (offset 0x20)
    dd 0                ; eax (offset 0x24)
    dd 0                ; ecx (offset 0x28)
    dd 0                ; edx (offset 0x2C)
    dd 0                ; ebx (offset 0x30)
    dd 0                ; esp (offset 0x34)
    dd 0                ; ebp (offset 0x38)
    dd 0                ; esi (offset 0x3C)
    dd 0                ; edi (offset 0x40)
    dw 0                ; es (offset 0x44)
    dw 0                ; cs (offset 0x48)
    dw 0                ; ss (offset 0x4C)
    dw 0                ; ds (offset 0x50)
    dw 0                ; fs (offset 0x54)
    dw 0                ; gs (offset 0x58)
    dw 0                ; ldt (offset 0x5C)
    dw 0                ; trace bit + reserved (offset 0x60)
    dw 0FFh             ; iomap_base (offset 0x64, must be 0xFF for no I/O map)
    ; Total size: 104 bytes (0x68), limit = 103 (0x67)
