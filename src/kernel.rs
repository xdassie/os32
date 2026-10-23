// Rust kernel module for OS32
#![no_std]
#![no_main]

use uart_16550::{Config, Uart16550};

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
            return;
        }
        1 => {
            let mut uart = unsafe { Uart16550::new_port(0x3F8).unwrap() };
            uart.init(Config::default()).ok();
            uart.send_bytes_exact(b"Hello from the Rust keyboard IRQ\r\n");
        }
        _ => return,
    }
}
