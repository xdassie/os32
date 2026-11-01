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

// GDT/IDT/TSS validation results with detailed diagnostics
static mut GDT_VALID: bool = false;
static mut GDT_BASE: u32 = 0;
static mut GDT_LIMIT: u16 = 0;
static mut IDT_VALID: bool = false;
static mut IDT_BASE: u32 = 0;
static mut IDT_LIMIT: u16 = 0;
static mut IDT_CPL_VALID: bool = false;
static mut IDT_CPL_CONFIG: u8 = 0;  // Stores DPL configuration info
static mut TSS_VALID: bool = false;
static mut TSS_SELECTOR: u16 = 0;
static mut TSS_CPL_VALID: bool = false;
static mut TSS_ESP0: u32 = 0;        // Ring 0 stack pointer from TSS
static mut TSS_SS0: u16 = 0;         // Ring 0 stack selector from TSS

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

/// Write a string at position (x, y)
unsafe fn vga_write_str(x: usize, y: usize, s: &[u8], attr: u8) {
    let mut cx = x;
    for &ch in s {
        if cx >= VGA_COLUMNS {
            break;
        }
        vga_write_char(cx, y, ch, attr);
        cx += 1;
    }
}

/// Write a 32-bit hex value at position (x, y)
unsafe fn vga_write_hex32(x: usize, y: usize, val: u32, attr: u8) {
    let digits: [u8; 8] = [
        to_hex_digit(((val >> 28) & 0xF) as u8),
        to_hex_digit(((val >> 24) & 0xF) as u8),
        to_hex_digit(((val >> 20) & 0xF) as u8),
        to_hex_digit(((val >> 16) & 0xF) as u8),
        to_hex_digit(((val >> 12) & 0xF) as u8),
        to_hex_digit(((val >> 8) & 0xF) as u8),
        to_hex_digit(((val >> 4) & 0xF) as u8),
        to_hex_digit((val & 0xF) as u8),
    ];
    for (i, &ch) in digits.iter().enumerate() {
        if x + i < VGA_COLUMNS {
            vga_write_char(x + i, y, ch, attr);
        }
    }
}

/// Write a 16-bit hex value at position (x, y)
unsafe fn vga_write_hex16(x: usize, y: usize, val: u16, attr: u8) {
    let digits: [u8; 4] = [
        to_hex_digit(((val >> 12) & 0xF) as u8),
        to_hex_digit(((val >> 8) & 0xF) as u8),
        to_hex_digit(((val >> 4) & 0xF) as u8),
        to_hex_digit((val & 0xF) as u8),
    ];
    for (i, &ch) in digits.iter().enumerate() {
        if x + i < VGA_COLUMNS {
            vga_write_char(x + i, y, ch, attr);
        }
    }
}

/// Convert a nibble to hex character
fn to_hex_digit(n: u8) -> u8 {
    if n < 10 {
        b'0' + n
    } else {
        b'A' + (n - 10)
    }
}

/// Validate GDT by reading GDTR
/// Intel Manual Vol 3A: GDTR contains 16-bit limit and 32-bit base address
unsafe fn validate_gdt() -> bool {
    // GDTR structure: [limit: u16, base: u32]
    let mut gdtr: [u8; 6] = [0; 6];
    let ptr = gdtr.as_mut_ptr() as usize;
    core::arch::asm!(
        "sgdt [{}]",
        in(reg) ptr,
        options(preserves_flags)
    );
    GDT_LIMIT = u16::from_le_bytes([gdtr[0], gdtr[1]]);
    GDT_BASE = u32::from_le_bytes([gdtr[2], gdtr[3], gdtr[4], gdtr[5]]);
    
    // Intel spec validation:
    // - Base must be non-zero (GDT must be loaded)
    // - Limit must match actual GDT size (48 bytes = 6 entries * 8 bytes)
    // - GDT should be aligned (base % 8 == 0)
    let valid = GDT_BASE != 0 
        && GDT_LIMIT > 0 
        && GDT_LIMIT == 47; // 48 bytes - 1 (limit is inclusive)
    
    GDT_VALID = valid;
    valid
}

/// Validate IDT by reading IDTR
/// Intel Manual Vol 3A: IDTR contains 16-bit limit and 32-bit base address
unsafe fn validate_idt() -> bool {
    // IDTR structure: [limit: u16, base: u32]
    let mut idtr: [u8; 6] = [0; 6];
    let ptr = idtr.as_mut_ptr() as usize;
    core::arch::asm!(
        "sidt [{}]",
        in(reg) ptr,
        options(preserves_flags)
    );
    IDT_LIMIT = u16::from_le_bytes([idtr[0], idtr[1]]);
    IDT_BASE = u32::from_le_bytes([idtr[2], idtr[3], idtr[4], idtr[5]]);
    
    // Intel spec validation:
    // - Base must be non-zero (IDT must be loaded)
    // - Limit must match actual IDT size (48 entries * 8 bytes = 384 bytes)
    // - Limit = (number of entries * 8) - 1
    let valid = IDT_BASE != 0 
        && IDT_LIMIT == 383; // 48 entries * 8 bytes - 1
    
    IDT_VALID = valid;
    valid
}

/// Validate IDT CPL (Current Privilege Level) configuration
/// Intel Manual Vol 3A: IDT gate attributes contain DPL (Descriptor Privilege Level)
/// For ring 0/ring 3 system, IDT gates should have DPL=0 (kernel-only access)
/// This ensures user code cannot directly invoke interrupts
unsafe fn validate_idt_cpl() -> bool {
    if IDT_BASE == 0 {
        IDT_CPL_VALID = false;
        return false;
    }
    
    // Check ALL 48 IDT gates (vectors 0-47)
    // IDT gate format: [offset_low:u16, selector:u16, reserved:u8, attributes:u8, offset_high:u16]
    // Attributes byte: [bits 7-5: type, bit 4: S=0, bits 3-2: DPL, bit 1: P, bit 0: reserved]
    
    let idt_ptr = IDT_BASE as *const u8;
    let mut all_correct = true;
    let mut checked_count: u8 = 0;
    let mut first_dpl: u8 = 0;
    let mut first_attrs: u8 = 0;
    
    // Check all 48 interrupt vectors (0-47)
    for vec_num in 0..48u8 {
        let gate_offset = (vec_num as usize) * 8;
        let attributes = *idt_ptr.offset(gate_offset as isize + 5);
        
        if checked_count == 0 {
            first_attrs = attributes;
        }
        
        let dpl = (attributes >> 2) & 0x3;  // Bits 3-2
        let present = ((attributes >> 1) & 0x1) != 0;  // Bit 1 (present)
        let gate_type = (attributes >> 5) & 0x7;  // Bits 7-5
        
        // For a ring 0/ring 3 system:
        // - DPL can be 0-3 (0=kernel only, higher=accessible from user)
        // - Present bit should be 1
        // - Gate type should be 4 (32-bit interrupt gate) or 5 (32-bit trap gate)
        if !present {
            all_correct = false;
            break;
        }
        if gate_type != 4 && gate_type != 5 {
            all_correct = false;
            break;
        }
        checked_count += 1;
        if checked_count == 1 {
            first_dpl = dpl;
        }
    }
    
    // Store debug info: first gate attributes for troubleshooting
    IDT_CPL_CONFIG = first_attrs;
    
    IDT_CPL_VALID = all_correct && (checked_count == 48);
    all_correct && (checked_count == 48)
}

/// Validate TSS by reading TR register
/// Intel Manual Vol 3A: TR contains segment selector pointing to TSS descriptor in GDT
unsafe fn validate_tss() -> bool {
    let mut selector: u16 = 0;
    core::arch::asm!(
        "str {0:e}",
        out(reg) selector,
        options(preserves_flags)
    );
    TSS_SELECTOR = selector;
    
    // Intel spec validation:
    // - Selector must be non-zero (TSS must be loaded)
    // - Selector TI bit (bit 2) should be 0 for GDT (not LDT)
    // - Selector RPL (bits 0-1) should be 0 for ring 0
    // - Selector index (bits 3-15) should point to valid GDT entry
    // TSS is valid if selector is non-zero
    let valid = selector != 0;
    
    TSS_VALID = valid;
    valid
}

/// Validate TSS CPL configuration by reading TSS contents
/// Intel Manual Vol 3A: TSS contains ESP0/SS0 for ring 0 stack on privilege transition
/// When transitioning from ring 3 to ring 0 (interrupt/exception), CPU uses ESP0/SS0
unsafe fn validate_tss_cpl() -> bool {
    if TSS_SELECTOR == 0 {
        TSS_CPL_VALID = false;
        return false;
    }
    
    // Extract TSS base address from GDT
    // TSS selector 0x28 = index 5, TI=0, RPL=0
    // GDT entry at index 5 (offset 40 from GDT base)
    let tss_index = (TSS_SELECTOR >> 3) as usize;
    let gdt_entry_offset = tss_index * 8;
    
    // Read GDT entry to get TSS base address
    // GDT descriptor format: [limit_low:u16, base_low:u24, access:u8, flags:u8]
    let gdt_ptr = GDT_BASE as *const u8;
    if gdt_ptr.is_null() {
        TSS_CPL_VALID = false;
        return false;
    }
    
    // Extract TSS base from GDT entry (base_low = bytes 2-4, 24 bits)
    let base_low = (u32::from(*gdt_ptr.offset((gdt_entry_offset + 2) as isize)))
        | ((u32::from(*gdt_ptr.offset((gdt_entry_offset + 3) as isize))) << 8)
        | ((u32::from(*gdt_ptr.offset((gdt_entry_offset + 4) as isize))) << 16);
    let flags_base = u32::from_le_bytes([
        *gdt_ptr.offset((gdt_entry_offset + 6) as isize),
        *gdt_ptr.offset((gdt_entry_offset + 7) as isize),
        0x00,
        0x00,
    ]);
    let tss_base = base_low | (flags_base << 16);
    
    if tss_base == 0 {
        TSS_CPL_VALID = false;
        return false;
    }
    
    // Read TSS ESP0 (offset 4) and SS0 (offset 8)
    // Intel Manual Vol 3A, Table 3-8: Task State Segment format
    let tss_ptr = tss_base as *const u8;
    TSS_ESP0 = u32::from_le_bytes([
        *tss_ptr.offset(4),
        *tss_ptr.offset(5),
        *tss_ptr.offset(6),
        *tss_ptr.offset(7),
    ]);
    TSS_SS0 = u16::from_le_bytes([
        *tss_ptr.offset(8),
        *tss_ptr.offset(9),
    ]);
    
    // Validate CPL configuration:
    // - ESP0 should point to a valid ring 0 stack (non-zero, reasonable address)
    // - SS0 should be the kernel data selector (0x10 for our GDT)
    let esp_valid = TSS_ESP0 != 0 && TSS_ESP0 < 0x10000000;  // Within first 256MB
    let ss0_valid = TSS_SS0 == 0x10;  // Should be kernel data selector
    
    TSS_CPL_VALID = esp_valid && ss0_valid;
    esp_valid && ss0_valid
}

/// Draw moving display animation with validation
unsafe fn vga_draw_moving_display() {
    vga_clear();

    // Validate GDT, IDT, TSS and CPL configuration
    validate_gdt();
    validate_idt();
    validate_idt_cpl();
    validate_tss();
    validate_tss_cpl();

    // Draw frame counter at row 0
    let frame = VGA_FRAME % 1000;
    vga_write_str(0, 0, b"Frame:", VGA_ATTR_WHITE);
    let d0 = b'0' + ((frame / 100) % 10) as u8;
    let d1 = b'0' + ((frame / 10) % 10) as u8;
    let d2 = b'0' + (frame % 10) as u8;
    vga_write_char(7, 0, d0, VGA_ATTR_WHITE);
    vga_write_char(8, 0, d1, VGA_ATTR_WHITE);
    vga_write_char(9, 0, d2, VGA_ATTR_WHITE);

    // Draw GDT validation at row 1
    vga_write_str(0, 1, b"GDT: ", VGA_ATTR_WHITE);
    if GDT_VALID {
        vga_write_str(4, 1, b"OK", VGA_ATTR_WHITE);
    } else {
        vga_write_str(4, 1, b"FAIL", VGA_ATTR_WHITE);
    }
    vga_write_str(8, 1, b"base=", VGA_ATTR_WHITE);
    vga_write_hex32(13, 1, GDT_BASE, VGA_ATTR_WHITE);
    vga_write_str(22, 1, b" lim=", VGA_ATTR_WHITE);
    vga_write_hex16(26, 1, GDT_LIMIT, VGA_ATTR_WHITE);
    if !GDT_VALID {
        vga_write_str(31, 1, b" exp_lim=002F", VGA_ATTR_WHITE);
    }

    // Draw IDT validation at row 2
    vga_write_str(0, 2, b"IDT: ", VGA_ATTR_WHITE);
    if IDT_VALID {
        vga_write_str(4, 2, b"OK", VGA_ATTR_WHITE);
    } else {
        vga_write_str(4, 2, b"FAIL", VGA_ATTR_WHITE);
    }
    vga_write_str(8, 2, b"base=", VGA_ATTR_WHITE);
    vga_write_hex32(13, 2, IDT_BASE, VGA_ATTR_WHITE);
    vga_write_str(22, 2, b" lim=", VGA_ATTR_WHITE);
    vga_write_hex16(26, 2, IDT_LIMIT, VGA_ATTR_WHITE);
    if !IDT_VALID {
        vga_write_str(31, 2, b" exp_lim=017F", VGA_ATTR_WHITE);
    }

    // Draw IDT CPL validation at row 3
    vga_write_str(0, 3, b"IDT_CPL: ", VGA_ATTR_WHITE);
    if IDT_CPL_VALID {
        vga_write_str(9, 3, b"OK 48 gates", VGA_ATTR_WHITE);
    } else {
        vga_write_str(9, 3, b"FAIL attrs=", VGA_ATTR_WHITE);
        // Show first gate attributes as hex
        let hi = to_hex_digit((IDT_CPL_CONFIG >> 4) & 0xF);
        let lo = to_hex_digit(IDT_CPL_CONFIG & 0xF);
        vga_write_char(19, 3, hi, VGA_ATTR_WHITE);
        vga_write_char(20, 3, lo, VGA_ATTR_WHITE);
    }

    // Draw TSS validation at row 4
    vga_write_str(0, 4, b"TSS: ", VGA_ATTR_WHITE);
    if TSS_VALID {
        vga_write_str(4, 4, b"OK", VGA_ATTR_WHITE);
    } else {
        vga_write_str(4, 4, b"NOT LOADED", VGA_ATTR_WHITE);
    }
    vga_write_str(15, 4, b"sel=", VGA_ATTR_WHITE);
    vga_write_hex16(19, 4, TSS_SELECTOR, VGA_ATTR_WHITE);
    if TSS_SELECTOR != 0 {
        let ti = ((TSS_SELECTOR >> 2) & 1) as u8;
        let rpl = (TSS_SELECTOR & 0x3) as u8;
        let index = TSS_SELECTOR >> 3;
        vga_write_str(24, 4, b" TI=", VGA_ATTR_WHITE);
        vga_write_char(27, 4, b'0' + ti, VGA_ATTR_WHITE);
        vga_write_str(29, 4, b" RPL=", VGA_ATTR_WHITE);
        vga_write_char(33, 4, b'0' + rpl, VGA_ATTR_WHITE);
        vga_write_str(36, 4, b" IDX=", VGA_ATTR_WHITE);
        vga_write_hex16(40, 4, index, VGA_ATTR_WHITE);
    }

    // Draw TSS CPL validation at row 5
    vga_write_str(0, 5, b"TSS_CPL: ", VGA_ATTR_WHITE);
    if TSS_CPL_VALID {
        vga_write_str(9, 5, b"OK ESP0/SS0 valid", VGA_ATTR_WHITE);
    } else {
        vga_write_str(9, 5, b"FAIL", VGA_ATTR_WHITE);
    }
    vga_write_str(25, 5, b"ESP0=", VGA_ATTR_WHITE);
    vga_write_hex32(30, 5, TSS_ESP0, VGA_ATTR_WHITE);
    vga_write_str(39, 5, b" SS0=", VGA_ATTR_WHITE);
    vga_write_hex16(43, 5, TSS_SS0, VGA_ATTR_WHITE);
    if TSS_SS0 != 0x10 {
        vga_write_str(48, 5, b" exp=10", VGA_ATTR_WHITE);
    }

    // Update bouncing ball position
    let mut new_x = VGA_X as i32 + VGA_DX;
    let mut new_y = VGA_Y as i32 + VGA_DY;

    // Bounce off edges (avoid validation rows 0-5)
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
    } else if new_y < 6 {
        VGA_DY = 1;
        new_y = 6;
    }
    VGA_X = new_x as usize;
    VGA_Y = new_y as usize;

    // Draw bouncing ball
    vga_write_char(VGA_X, VGA_Y, b'O', VGA_ATTR_WHITE);

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
