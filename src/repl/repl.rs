// REPL module: PS/2 keyboard driver + shell
    use core::cell::RefCell;
    use pc_keyboard::{layouts::Us104Key, DecodedKey, HandleControl, ScancodeSet1};
    use spin::{Lazy, Mutex};
    use uart_16550::{Config, Uart16550};

    const MAX_INPUT: usize = 256;

    pub struct PS2Keyboard {
        decoder: RefCell<pc_keyboard::PS2Keyboard<Us104Key, ScancodeSet1>>,
    }

    impl PS2Keyboard {
        pub fn new() -> Self {
            PS2Keyboard {
                decoder: RefCell::new(pc_keyboard::PS2Keyboard::new(
                    ScancodeSet1::new(),
                    Us104Key,
                    HandleControl::MapLettersToUnicode,
                )),
            }
        }

        pub fn process_byte(&self, byte: u8) -> Option<DecodedKey> {
            let mut decoder = self.decoder.borrow_mut();
            match decoder.add_byte(byte) {
                Ok(Some(event)) => decoder.process_keyevent(event),
                Ok(None) => None,
                Err(_) => {
                    decoder.clear();
                    None
                }
            }
        }
    }

    pub static KEYBOARD: Lazy<Mutex<PS2Keyboard>> = Lazy::new(|| Mutex::new(PS2Keyboard::new()));

    fn process_scancode(byte: u8) -> Option<char> {
        let keyboard = KEYBOARD.lock();
        match keyboard.process_byte(byte) {
            Some(DecodedKey::Unicode(c)) => Some(c),
            Some(DecodedKey::RawKey(pc_keyboard::KeyCode::Backspace)) => Some('\x08'),
            Some(DecodedKey::RawKey(pc_keyboard::KeyCode::Return)) => Some('\n'),
            _ => None,
        }
    }

    fn poll_keyboard() -> Option<char> {
        unsafe {
            let status: u8;
            core::arch::asm!(
                "in al, dx",
                out("al") status,
                in("dx") 0x64u16,
                options(nostack, preserves_flags)
            );

            if status & 0x01 != 0 {
                let scancode: u8;
                core::arch::asm!(
                    "in al, dx",
                    out("al") scancode,
                    in("dx") 0x60u16,
                    options(nostack, preserves_flags)
                );
                process_scancode(scancode)
            } else {
                None
            }
        }
    }

    fn is_ascii_printable(c: char) -> bool {
        c >= ' ' && c <= '~'
    }

    pub fn run_repl() {
        let mut uart = unsafe { Uart16550::new_port(0x3F8).unwrap() };
        uart.init(Config::default()).ok();

        uart.send_bytes_exact(b"OS32 REPL v0.1\r\n");
        uart.send_bytes_exact(b"Type 'help' for available commands.\r\n");

        let mut input = [0u8; MAX_INPUT];
        let mut pos = 0;

        loop {
            uart.send_bytes_exact(b"> ");

            pos = 0;
            loop {
                let key = poll_keyboard();

                match key {
                    Some('\n') => {
                        uart.send_bytes_exact(b"\r\n");
                        break;
                    }
                    Some('\x08') => {
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
