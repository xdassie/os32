; OS32 - Pure Assembly 32-bit Kernel
; Multiboot compatible kernel for GRUB

section .text align=4
global _start
global mb_header
extern rust_kernel_entry

%define VGA_ATTR 0x0F

%macro PRINTREGS 0
    ; 32-bit general purpose registers (not EIP)
    VGA_PRINT_REG32 eax, 0
    VGA_PRINT_REG32 ebx, 160
    VGA_PRINT_REG32 ecx, 320
    VGA_PRINT_REG32 edx, 480
    VGA_PRINT_REG32 esi, 640
    VGA_PRINT_REG32 edi, 800
    VGA_PRINT_REG32 ebp, 960
    VGA_PRINT_REG32 esp, 1120
    ; 16-bit segment registers
    VGA_PRINT_REG16 cs, 1280
    VGA_PRINT_REG16 ds, 1440
    VGA_PRINT_REG16 es, 1600
    VGA_PRINT_REG16 fs, 1760
    VGA_PRINT_REG16 gs, 1920
    VGA_PRINT_REG16 ss, 2080
%endmacro

%macro VGA_PRINT_REG16 2
    ; %1 = 16-bit register
    ; %2 = byte offset into VGA memory
    pushad

    ; Print register label (3 chars + colon)
    mov edi, 0xB8000
    add edi, %2
    call .pushreglabel_%1	; esi is expected to contain the address of the string label
    mov ecx, 4
%%printlabel16:
    mov al, [esi]
    mov ah, VGA_ATTR
    stosw
    inc esi
    dec ecx
    jnz %%printlabel16

    ; Print hex value (4 digits)
    add edi, 8
    mov ebx, 4
    mov ax, %1
    mov cx, ax

%%digit16:
    mov eax, ebx
    dec eax
    shl eax, 2
    mov cl, al

    movzx edx, cx
    shr edx, cl
    and edx, 0x0F

    cmp edx, 9
    jbe %%numeric16
    add dl, 'A' - 10
    jmp %%write16

%%numeric16:
    add dl, '0'

%%write16:
    mov ah, VGA_ATTR
    mov al, dl
    stosw
    dec ebx
    jnz %%digit16

    popad
%endmacro


%macro VGA_PRINT_REG32 2
    ; %1 = 32-bit register
    ; %2 = byte offset into VGA memory
    pushad

    ; Print register label (4 chars + colon)
    mov edi, 0xB8000
    add edi, %2
    call .pushreglabel_%1		; esi is expected to contain the address of the string label
    mov ecx, 5
%%printlabel32:
    mov al, [esi]
    mov ah, VGA_ATTR
    stosw
    inc esi
    dec ecx
    jnz %%printlabel32

    ; Print hex value (8 digits)
    add edi, 10
    mov ebx, 8
    mov esi, %1

%%digit32:
    mov eax, ebx
    dec eax
    shl eax, 2
    mov cl, al

    mov edx, esi
    shr edx, cl
    and edx, 0x0F

    cmp edx, 9
    jbe %%numeric32
    add dl, 'A' - 10
    jmp %%write32

%%numeric32:
    add dl, '0'

%%write32:
    mov ah, VGA_ATTR
    mov al, dl
    stosw
    dec ebx
    jnz %%digit32

    popad
%endmacro

; Multiboot header - must be at the very beginning of the loaded image
mb_header:
    dd 0x1BADB002      ; Multiboot magic number
    dd 0               ; Flags (0 = no flags, 32-bit)
    dd -(0x1BADB002 + 0)  ; Checksum (must be 0 mod 2^32)

; Entry point - comes right after multiboot header
align 4
_start:
    ; Set up stack (16KB stack at 1MB + 64KB = 0x110000, grow down)
    mov esp, stack_top
    
.animation:
    ; Clear screen with welcome message at top
    mov esi, msg
    mov edi, 0xB8000        ; VGA text buffer
    xor ecx, ecx
.print_vga_loop2:
    mov al, [esi]
    test al, al
    jz .clear_rest
    mov [edi + ecx], al
    mov byte [edi + ecx + 1], 0x0F
    add ecx, 2
    inc esi
    jmp .print_vga_loop2

.clear_rest:
    ; Clear rest of screen (80x25 = 2000 cells = 4000 bytes)
    mov ecx, 4000
    mov edi, 0xB8000
    xor eax, eax
    rep stosb

    ; Start bouncing ball animation
    mov word [ball_x], 0    ; Reset ball position
    mov word [ball_y], 12   ; Start in middle vertically
    mov word [ball_dx], 1   ; Move right initially
    ; run splash loop ebp number of times
    mov ebp, 20
    
    jmp .animation_loop

.animation_loop:
    ; Calculate ball position in VGA memory
    ; cell_index = ball_y * 80 + ball_x
    mov ax, [ball_y]
    mov bx, 80
    mul bx                  ; AX = ball_y * 80
    add ax, [ball_x]        ; AX = cell index
    mov bx, ax
    mov ax, 2               ; 2 bytes per cell
    mul bx                  ; AX = byte offset
    mov edi, 0xB8000        ; Full 32-bit VGA address
    add edi, eax            ; EDI = VGA address + offset

    ; Clear old position (draw space with gray attribute)
    mov word [edi], 0x0720        ; ' ' with gray attribute

    ; Update ball position
    mov ax, [ball_x]
    add ax, [ball_dx]
    cmp ax, 78              ; Right edge (80 cols - 2)
    jl .check_left
    mov ax, 78
    mov word [ball_dx], -1
.check_left:
    cmp ax, 0
    jge .store_x
    mov ax, 0
    mov word [ball_dx], 1
.store_x:
    mov [ball_x], ax

    ; Calculate new ball position in VGA memory
    mov ax, [ball_y]
    mov bx, 80
    mul bx
    add ax, [ball_x]
    mov bx, ax
    mov ax, 2
    mul bx
    mov edi, 0xB8000        ; Full 32-bit VGA address
    add edi, eax            ; EDI = VGA address + offset

    ; Draw new ball position (white block)
    mov word [edi], 0x0FB0        ; '░' with white attribute

    ; Delay (simple busy loop for animation speed)
    mov ecx, 5000000
.delay_loop:
    dec ecx
    jnz .delay_loop
    dec ebp
    jz .kernel
    jmp .animation_loop
.kernel:
    ; Save GDT descriptor to buffer for Rust kernel
    sgdt [gdt_buffer]
        
    ; Call Rust kernel entry point (after splashscreen setup)
    PRINTREGS
    call rust_kernel_entry
    PRINTREGS
    hlt

; Label stubs for register name push (called by macros)
.pushreglabel_eax:
    mov esi, reg_eax
    ret
.pushreglabel_ebx:
    mov esi, reg_ebx
    ret
.pushreglabel_ecx:
    mov esi, reg_ecx
    ret
.pushreglabel_edx:
    mov esi, reg_edx
    ret
.pushreglabel_esi:
    mov esi, reg_esi
    ret
.pushreglabel_edi:
    mov esi, reg_edi
    ret
.pushreglabel_ebp:
    mov esi, reg_ebp
    ret
.pushreglabel_esp:
    mov esi, reg_esp
    ret
.pushreglabel_cs:
    mov esi, reg_cs
    ret
.pushreglabel_ds:
    mov esi, reg_ds
    ret
.pushreglabel_es:
    mov esi, reg_es
    ret
.pushreglabel_fs:
    mov esi, reg_fs
    ret
.pushreglabel_gs:
    mov esi, reg_gs
    ret
.pushreglabel_ss:
    mov esi, reg_ss
    ret

section .data align=4
msg: db "OS32 booted successfully!", 0
; 32-bit register labels
reg_eax: db "eax:", 0
reg_ebx: db "ebx:", 0
reg_ecx: db "ecx:", 0
reg_edx: db "edx:", 0
reg_esi: db "esi:", 0
reg_edi: db "edi:", 0
reg_ebp: db "ebp:", 0
reg_esp: db "esp:", 0
; 16-bit segment register labels
reg_cs:  db "cs:", 0
reg_ds:  db "ds:", 0
reg_es:  db "es:", 0
reg_fs:  db "fs:", 0
reg_gs:  db "gs:", 0
reg_ss:  db "ss:", 0

section .bss align=4096
stack_bottom:
    resb 16384              ; 16KB stack
stack_top:
ball_x: resw 1              ; Ball X position
ball_y: resw 1              ; Ball Y position
ball_dx: resw 1             ; Ball X direction (+1 or -1)
gdt_buffer: resb 8          ; GDT descriptor buffer (limit: 2 bytes, base: 6 bytes)
