; OS32 - Pure Assembly 32-bit Kernel
; Multiboot compatible kernel for GRUB

section .text align=4
global _start
global mb_header
extern rust_kernel_entry

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
    
    ; Print message to VGA text mode
    mov esi, msg
    mov edi, 0xB8000        ; VGA text buffer address
    xor ecx, ecx            ; ECX = offset (byte index)
.print_vga_loop:
    mov al, [esi]           ; Load character
    test al, al             ; Check for null terminator
    jz .after_vga
    mov [edi + ecx], al     ; Store character
    mov byte [edi + ecx + 1], 0x0F  ; Attribute: white on black
    add ecx, 2              ; Move to next character cell (2 bytes each)
    inc esi                 ; Next character in string
    jmp .print_vga_loop

.after_vga:
    ; Start infinite animation
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
    
    ; Call Rust kernel entry point (after splashscreen setup)
    call rust_kernel_entry
    
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
    mov ecx, 50000
.delay_loop:
    dec ecx
    jnz .delay_loop

    jmp .animation_loop

section .data align=4
msg: db "OS32 booted successfully!", 0

section .bss align=4096
stack_bottom:
    resb 16384              ; 16KB stack
stack_top:
ball_x: resw 1              ; Ball X position
ball_y: resw 1              ; Ball Y position
ball_dx: resw 1             ; Ball X direction (+1 or -1)
