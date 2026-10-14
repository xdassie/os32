// Rust kernel module for OS32
#![no_std]
#![no_main]

use core::arch::asm;

#[unsafe(no_mangle)]
pub extern "C" fn rust_kernel_entry() {
    const SERIAL_PORT: u16 = 0x3F8;
    const MSG: &str = "Hello from the Rust kernel\r\n";

    for &byte in MSG.as_bytes() {
        // Wait for transmitter ready (THRE bit in LSR)
        let mut status: u8;
        loop {
            unsafe {
                asm!(
                    "in al, dx",
                    in("dx") 0x3FD,
                    out("al") status
                );
            }
            if status & 0x20 != 0 {
                break;
            }
        }
        // Send character
        unsafe {
            asm!("out dx, al", in("dx") SERIAL_PORT, in("al") byte);
        }
    }
}
