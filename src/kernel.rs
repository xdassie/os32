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

/// Clear VGA screen with spaces
unsafe fn vga_clear() {
    let total_cells = VGA_COLUMNS * VGA_ROWS;
    let mut i: usize = 0;
    while i < total_cells {
        let addr = VGA_BUFFER as usize + (i * 2);
        *(addr as *mut u8) = VGA_ATTR_WHITE;
        *(addr as *mut u8).offset(1) = b' ';
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
    *(addr as *mut u8) = attr;
    *(addr as *mut u8).offset(1) = ch;
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

    // Draw frame counter at top
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
    return;
}

#[no_mangle]
pub extern "C" fn rust_kernel_irq(irq_number: u32) {
    match irq_number {
        0 => {
            unsafe {
                vga_draw_moving_display();
            }
        }
        1 => {
            let mut uart = unsafe { Uart16550::new_port(0x3F8).unwrap() };
            uart.init(Config::default()).ok();
            uart.send_bytes_exact(b"Hello from the Rust keyboard IRQ\r\n");
        }
        _ => return,
    }
}
