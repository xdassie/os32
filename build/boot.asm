; OS32 - Pure Assembly 32-bit Kernel
; Multiboot compatible kernel for GRUB

section .text align=4
global _start
global mb_header

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
    
    ; Initialize serial port COM1 (0x3F8) for 9600 baud
    mov dx, 0x3F9           ; Interrupt Enable Register
    mov al, 0x00
    out dx, al
    
    ; Enter divisor latch mode
    mov dx, 0x3FB           ; Line Control Register
    mov al, 0x80
    out dx, al
    
    ; Set baud rate to 9600 (divisor = 12)
    mov dx, 0x3F8           ; Divisor Latch Low
    mov al, 12
    out dx, al
    mov dx, 0x3F9           ; Divisor Latch High
    mov al, 0x00
    out dx, al
    
    ; Exit divisor latch mode, 8 data bits, no parity, 1 stop bit
    mov dx, 0x3FB           ; Line Control Register
    mov al, 0x03
    out dx, al
    
    ; Clear FIFO
    mov dx, 0x3FC           ; FIFO Control Register
    mov al, 0x01
    out dx, al
    
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
    ; Print message to serial port (COM1 at 0x3F8)
    mov esi, msg
.print_serial_loop:
    mov al, [esi]           ; Load character
    test al, al             ; Check for null terminator
    jz .halt
    
    ; Save character to BL since AL will be used for status check
    mov bl, al
    
    ; Wait for transmitter to be ready
.wait_throttle:
    mov dx, 0x3FD           ; Line Status Register
    in al, dx
    test al, 0x20           ; Check THRE (Transmitter Holding Register Empty)
    jz .wait_throttle
    
    mov dx, 0x3F8           ; Data Register
    mov al, bl              ; Restore character
    out dx, al              ; Send character
    
    inc esi                 ; Next character
    jmp .print_serial_loop
    
    ; Halt the CPU forever
.halt:
.halt_loop:
    cli             ; Disable interrupts
    hlt             ; Halt until next interrupt
    jmp .halt_loop  ; Just in case, loop forever

section .data align=4
msg: db "OS32 booted successfully!", 0

section .bss align=4096
stack_bottom:
    resb 16384              ; 16KB stack
stack_top:
