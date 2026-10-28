// Rust kernel module for OS32
#![no_std]
#![no_main]

use uart_16550::{Config, Uart16550};

// VGA Text Mode constants
const VGA_BUFFER: *mut u8 = 0xB8000 as *mut u8;
const VGA_COLUMNS: usize = 80;
const VGA_ROWS: usize = 25;
const VGA_ATTR_WHITE: u8 = 0x0F;

// Moving display state
static mut VGA_X: usize = 0;
static mut VGA_Y: usize = 0;
static mut VGA_DX: i32 = 1;
static mut VGA_DY: i32 = 1;
static mut VGA_FRAME: u32 = 0;

// Ring 3 task monitoring state
static mut RING3_ACTIVE: bool = false;
static mut RING3_TICKS: u32 = 0;

// Ring 3 counter - shared memory location (assembly writes, Rust reads)
extern "C" {
    static ring3_counter_mem: u32;
}

/// Clear VGA screen with spaces
unsafe fn vga_clear() {
    let total_cells = VGA_COLUMNS * VGA_ROWS;
    let mut i: usize = 0;
    while i < total_cells {
        let addr = VGA_BUFFER as usize + (i * 2);
        *(addr as *mut u8) = b' ';
        *(addr as *mut u8).offset(1) = VGA_ATTR_WHITE;
        i += 1;
    }
}

/// Write a character at position (x, y)
unsafe fn vga_write_char(x: usize, y: usize, ch: u8, attr: u8) {
    if x >= VGA_COLUMNS || y >= VGA_ROWS {
        return;
    }
    let offset = (y * VGA_COLUMNS + x) * 2;
    let addr = VGA_BUFFER as usize + offset;
    *(addr as *mut u8) = ch;
    *(addr as *mut u8).offset(1) = attr;
}

/// Write a 32-bit value as 8 hex digits at the specified VGA offset
/// This converts the VGA_PRINT_REG32 macro to Rust
#[no_mangle]
pub unsafe extern "C" fn vga_print_reg32(value: u32, offset: usize, label: *const u8) {
    let mut edi = VGA_BUFFER as usize + offset;

    // Print label (e.g., "eax:")
    let mut label_ptr = label;
    loop {
        let ch = *label_ptr;
        if ch == 0 {
            break;
        }
        label_ptr = label_ptr.add(1);
        *(edi as *mut u8) = ch;
        *(edi as *mut u8).offset(1) = VGA_ATTR_WHITE;
        edi += 2;
    }

    // Add spacing after label
    edi += 2;

    // Print 8 hex digits
    for i in (0..8).rev() {
        let nibble = ((value >> (i * 4)) & 0x0F) as u8;
        let ch = if nibble < 10 {
            b'0' + nibble
        } else {
            b'A' + nibble - 10
        };
        *(edi as *mut u8) = ch;
        *(edi as *mut u8).offset(1) = VGA_ATTR_WHITE;
        edi += 2;
    }
}

/// Write a 16-bit value as 4 hex digits at the specified VGA offset
/// This converts the VGA_PRINT_REG16 macro to Rust
#[no_mangle]
pub unsafe extern "C" fn vga_print_reg16(value: u32, offset: usize, label: *const u8) {
    let mut edi = VGA_BUFFER as usize + offset;

    // Print label (e.g., "cs:")
    let mut label_ptr = label;
    loop {
        let ch = *label_ptr;
        if ch == 0 {
            break;
        }
        label_ptr = label_ptr.add(1);
        *(edi as *mut u8) = ch;
        *(edi as *mut u8).offset(1) = VGA_ATTR_WHITE;
        edi += 2;
    }

    // Add spacing after label
    edi += 8; // 4 bytes for label + 2 bytes spacing

    // Print 4 hex digits
    for i in (0..4).rev() {
        let nibble = ((value >> (i * 4)) & 0x0F) as u8;
        let ch = if nibble < 10 {
            b'0' + nibble
        } else {
            b'A' + nibble - 10
        };
        *(edi as *mut u8) = ch;
        *(edi as *mut u8).offset(1) = VGA_ATTR_WHITE;
        edi += 2;
    }
}

/// Write a 32-bit value with a label at the specified VGA offset
/// This converts the VGA_PRINT macro to Rust
#[no_mangle]
pub unsafe extern "C" fn vga_print(value: u32, offset: usize, label: *const u8) {
    let mut edi = VGA_BUFFER as usize + offset;

    // Print label (4 characters)
    let mut label_ptr = label;
    loop {
        let ch = *label_ptr;
        if ch == 0 {
            break;
        }
        label_ptr = label_ptr.add(1);
        *(edi as *mut u8) = ch;
        *(edi as *mut u8).offset(1) = VGA_ATTR_WHITE;
        edi += 2;
    }

    // Print 4 hex digits
    for i in (0..4).rev() {
        let nibble = ((value >> (i * 4)) & 0x0F) as u8;
        let ch = if nibble < 10 {
            b'0' + nibble
        } else {
            b'A' + nibble - 10
        };
        *(edi as *mut u8) = ch;
        *(edi as *mut u8).offset(1) = VGA_ATTR_WHITE;
        edi += 2;
    }
}

/// Print IDT number at row 20 (offset 3200)
/// This converts the PRINT_IDT_NUMBER function to Rust
/// Input: idt_num = IDT number (0-255)
#[no_mangle]
pub unsafe extern "C" fn print_idt_number(idt_num: u8) {
    let mut edi = VGA_BUFFER as usize + 3200; // Row 20

    // Print "IDT:" label
    for ch in b"IDT:" {
        *(edi as *mut u8) = *ch;
        *(edi as *mut u8).offset(1) = VGA_ATTR_WHITE;
        edi += 2;
    }

    // Print IDT number as 2 hex digits
    for i in (0..2).rev() {
        let nibble = ((idt_num >> (i * 4)) & 0x0F) as u8;
        let ch = if nibble < 10 {
            b'0' + nibble
        } else {
            b'A' + nibble - 10
        };
        *(edi as *mut u8) = ch;
        *(edi as *mut u8).offset(1) = VGA_ATTR_WHITE;
        edi += 2;
    }
}

/// Print error code at row 24 (offset 3840)
/// This converts the PRINT_ERROR_CODE function to Rust
/// Input: error_code = 32-bit error code
#[no_mangle]
pub unsafe extern "C" fn print_error_code(error_code: u32) {
    let mut edi = VGA_BUFFER as usize + 3840; // Row 24

    // Print "ERR:" label
    for ch in b"ERR:" {
        *(edi as *mut u8) = *ch;
        *(edi as *mut u8).offset(1) = VGA_ATTR_WHITE;
        edi += 2;
    }

    // Print 4 hex digits
    for i in (0..4).rev() {
        let nibble = ((error_code >> (i * 4)) & 0x0F) as u8;
        let ch = if nibble < 10 {
            b'0' + nibble
        } else {
            b'A' + nibble - 10
        };
        *(edi as *mut u8) = ch;
        *(edi as *mut u8).offset(1) = VGA_ATTR_WHITE;
        edi += 2;
    }
}

/// Print fault location (EIP) at row 23 (offset 3680)
/// This converts the PRINT_FAULT_LOCATION function to Rust
/// Input: eip = 32-bit instruction pointer
#[no_mangle]
pub unsafe extern "C" fn print_fault_location(eip: u32) {
    let mut edi = VGA_BUFFER as usize + 3680; // Row 23

    // Print "EIP:" label
    for ch in b"EIP:" {
        *(edi as *mut u8) = *ch;
        *(edi as *mut u8).offset(1) = VGA_ATTR_WHITE;
        edi += 2;
    }

    // Skip one cell for spacing
    edi += 2;

    // Print 8 hex digits
    for i in (0..8).rev() {
        let nibble = ((eip >> (i * 4)) & 0x0F) as u8;
        let ch = if nibble < 10 {
            b'0' + nibble
        } else {
            b'A' + nibble - 10
        };
        *(edi as *mut u8) = ch;
        *(edi as *mut u8).offset(1) = VGA_ATTR_WHITE;
        edi += 2;
    }
}

/// Draw moving display animation
unsafe fn vga_draw_moving_display() {
    vga_clear();

    // Update position
    let mut new_x = VGA_X as i32 + VGA_DX;
    let mut new_y = VGA_Y as i32 + VGA_DY;

    // Bounce off edges
    if new_x >= VGA_COLUMNS as i32 {
        VGA_DX = -1;
        new_x = VGA_COLUMNS as i32 - 1;
    } else if new_x < 0 {
        VGA_DX = 1;
        new_x = 0;
    }
    if new_y >= VGA_ROWS as i32 {
        VGA_DY = -1;
        new_y = VGA_ROWS as i32 - 1;
    } else if new_y < 0 {
        VGA_DY = 1;
        new_y = 0;
    }
    VGA_X = new_x as usize;
    VGA_Y = new_y as usize;

    // Draw frame counter at row 0
    let frame = VGA_FRAME % 1000;
    vga_write_char(0, 0, b'F', VGA_ATTR_WHITE);
    vga_write_char(1, 0, b'r', VGA_ATTR_WHITE);
    vga_write_char(2, 0, b'a', VGA_ATTR_WHITE);
    vga_write_char(3, 0, b'm', VGA_ATTR_WHITE);
    vga_write_char(4, 0, b'e', VGA_ATTR_WHITE);
    vga_write_char(5, 0, b':', VGA_ATTR_WHITE);

    // Draw frame number digits
    let d0 = b'0' + ((frame / 100) % 10) as u8;
    let d1 = b'0' + ((frame / 10) % 10) as u8;
    let d2 = b'0' + (frame % 10) as u8;
    vga_write_char(7, 0, d0, VGA_ATTR_WHITE);
    vga_write_char(8, 0, d1, VGA_ATTR_WHITE);
    vga_write_char(9, 0, d2, VGA_ATTR_WHITE);

    // Draw Ring 3 status at row 1
    vga_write_char(0, 1, b'R', VGA_ATTR_WHITE);
    vga_write_char(1, 1, b'3', VGA_ATTR_WHITE);
    vga_write_char(2, 1, b':', VGA_ATTR_WHITE);
    if RING3_ACTIVE {
        vga_write_char(4, 1, b'R', VGA_ATTR_WHITE);
        vga_write_char(5, 1, b'U', VGA_ATTR_WHITE);
        vga_write_char(6, 1, b'N', VGA_ATTR_WHITE);
    } else {
        vga_write_char(4, 1, b'H', VGA_ATTR_WHITE);
        vga_write_char(5, 1, b'L', VGA_ATTR_WHITE);
        vga_write_char(6, 1, b'T', VGA_ATTR_WHITE);
    }

    // Draw Ring 3 counter at row 1, col 10
    vga_write_char(10, 1, b'C', VGA_ATTR_WHITE);
    vga_write_char(11, 1, b':', VGA_ATTR_WHITE);
    let r3c = ring3_counter_mem % 10000;
    let rd0 = b'0' + ((r3c / 1000) % 10) as u8;
    let rd1 = b'0' + ((r3c / 100) % 10) as u8;
    let rd2 = b'0' + ((r3c / 10) % 10) as u8;
    let rd3 = b'0' + (r3c % 10) as u8;
    vga_write_char(13, 1, rd0, VGA_ATTR_WHITE);
    vga_write_char(14, 1, rd1, VGA_ATTR_WHITE);
    vga_write_char(15, 1, rd2, VGA_ATTR_WHITE);
    vga_write_char(16, 1, rd3, VGA_ATTR_WHITE);

    // Draw Ring 3 ticks at row 2
    vga_write_char(0, 2, b'T', VGA_ATTR_WHITE);
    vga_write_char(1, 2, b':', VGA_ATTR_WHITE);
    let r3t = RING3_TICKS % 10000;
    let td0 = b'0' + ((r3t / 1000) % 10) as u8;
    let td1 = b'0' + ((r3t / 100) % 10) as u8;
    let td2 = b'0' + ((r3t / 10) % 10) as u8;
    let td3 = b'0' + (r3t % 10) as u8;
    vga_write_char(3, 2, td0, VGA_ATTR_WHITE);
    vga_write_char(4, 2, td1, VGA_ATTR_WHITE);
    vga_write_char(5, 2, td2, VGA_ATTR_WHITE);
    vga_write_char(6, 2, td3, VGA_ATTR_WHITE);

    // Draw bouncing ball
    let cx = VGA_X;
    let cy = VGA_Y;
    vga_write_char(cx, cy, b'O', VGA_ATTR_WHITE);

    VGA_FRAME += 1;
}

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[no_mangle]
pub extern "C" fn rust_kernel_entry() {
    unsafe {
        RING3_ACTIVE = true;
    }
}

#[no_mangle]
pub extern "C" fn rust_kernel_irq(irq_number: u32) {
    match irq_number {
        0 => {
            unsafe {
                RING3_TICKS += 1;
                vga_draw_moving_display();
            }
        }
        _ => {}
    }
}
