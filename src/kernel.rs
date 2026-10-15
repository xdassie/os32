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
    // SAFETY: Port 0x3F8 is valid COM1 and we have exclusive access
    let mut uart = unsafe { Uart16550::new_port(0x3F8).unwrap() };
    uart.init(Config::default()).ok();
    uart.send_bytes_exact(b"Hello from the Rust kernel\r\n");
}
