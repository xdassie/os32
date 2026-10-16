// Simple shell with basic command handling

use crate::keyboard;
use uart_16550::{Config, Uart16550};

const MAX_INPUT: usize = 256;

pub fn run_shell() {
    // SAFETY: Port 0x3F8 is valid COM1 and we have exclusive access
    let mut uart = unsafe { Uart16550::new_port(0x3F8).unwrap() };
    uart.init(Config::default()).ok();

    uart.send_bytes_exact(b"OS32 Shell v0.1\r\n");
    uart.send_bytes_exact(b"Type 'help' for available commands.\r\n");

    let mut input = [0u8; MAX_INPUT];
    let mut pos = 0;

    loop {
        // Print prompt
        uart.send_bytes_exact(b"> ");

        pos = 0;
        loop {
            // Get key from keyboard (this would normally be interrupt-driven)
            // For now, we'll need to poll the keyboard controller
            let key = poll_keyboard();
            
            match key {
                Some('\n') => {
                    uart.send_bytes_exact(b"\r\n");
                    break;
                }
                Some('\x08') => {
                    // Backspace
                    if pos > 0 {
                        pos -= 1;
                        uart.send_bytes_exact(b"\x08 \x08");
                    }
                }
                Some(c) if is_ascii_printable(c) => {
                    if pos < MAX_INPUT - 1 {
                        input[pos] = c as u8;
                        pos += 1;
                        let buf = [c as u8];
                        uart.send_bytes_exact(&buf);
                    }
                }
                _ => {}
            }
        }

        // Process command
        if pos > 0 {
            let cmd = core::str::from_utf8(&input[..pos]).unwrap_or("");
            match cmd {
                "help" => {
                    uart.send_bytes_exact(b"Available commands:\r\n");
                    uart.send_bytes_exact(b"  help    Show this help message\r\n");
                }
                _ => {
                    uart.send_bytes_exact(b"Unknown command: ");
                    uart.send_bytes_exact(cmd.as_bytes());
                    uart.send_bytes_exact(b"\r\n");
                    uart.send_bytes_exact(b"Type 'help' for available commands.\r\n");
                }
            }
        }
    }
}

fn is_ascii_printable(c: char) -> bool {
    c >= ' ' && c <= '~'
}

fn poll_keyboard() -> Option<char> {
    // Poll the i8042 keyboard controller data port (0x60)
    // First check if data is available by reading status port (0x64)
    // Bit 0 = Output Buffer Full
    
    unsafe {
        // Check status port using inline assembly for x86
        let status: u8;
        core::arch::asm!("in al, dx",
            out("al") status,
            in("dx") 0x64u16,
            options(nostack, preserves_flags)
        );
        
        if status & 0x01 != 0 {
            // Data available
            let scancode: u8;
            core::arch::asm!("in al, dx",
                out("al") scancode,
                in("dx") 0x60u16,
                options(nostack, preserves_flags)
            );
            keyboard::process_scancode(scancode)
        } else {
            None
        }
    }
}
