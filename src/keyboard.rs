// PS/2 Keyboard driver using pc-keyboard crate

use core::cell::RefCell;
use pc_keyboard::{layouts::Us104Key, DecodedKey, HandleControl, ScancodeSet1};
use spin::{Lazy, Mutex};

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

pub static KEYBOARD: spin::Lazy<Mutex<PS2Keyboard>> = spin::Lazy::new(|| {
    Mutex::new(PS2Keyboard::new())
});

pub fn process_scancode(byte: u8) -> Option<char> {
    let keyboard = KEYBOARD.lock();
    match keyboard.process_byte(byte) {
        Some(DecodedKey::Unicode(c)) => Some(c),
        Some(DecodedKey::RawKey(pc_keyboard::KeyCode::Backspace)) => Some('\x08'),
        Some(DecodedKey::RawKey(pc_keyboard::KeyCode::Return)) => Some('\n'),
        _ => None,
    }
}
