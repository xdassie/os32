[bits 32]

; Multiboot header
align 4
multiboot_header:
    dd 0x1BADB002          ; Magic number
    dd 0                   ; Flags (0 = no flags)
    dd 0 - (0x1BADB002 + 0) ; Checksum

; Entry point
global _start
_start:
    ; Set up stack
    mov esp, 0x90000       ; Set stack to 0x90000 (576KB)
    
    ; Call Rust kernel
    call kernel_main
    
    ; Halt the CPU
    cli
.halt:
    hlt
    jmp .halt

; Stubs for Rust to call
global print_vga
print_vga:
    ret

global halt_forever
halt_forever:
    cli
.halt_loop:
    hlt
    jmp .halt_loop
