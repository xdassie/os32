#!/bin/bash
# Automated debug script for OS32 kernel - runs diagnostic commands

KERNEL_BIN="os32.elf"
QEMU_BIN=$(which qemu-system-i386 || echo "/usr/bin/qemu-system-i386")
RUST_GDB=$(which rust-gdb || echo "gdb")

echo "=== OS32 Kernel Auto-Debugger ==="
echo ""

if [ ! -f "$KERNEL_BIN" ]; then
    echo "ERROR: Kernel binary not found."
    exit 1
fi

# Start QEMU with GDB stub
$QEMU_BIN -kernel $KERNEL_BIN -S -s -no-reboot &
QEMU_PID=$!
sleep 2

# Create GDB command script for automated debugging
cat > /tmp/gdb_auto.txt << 'GDBEOF'
set pagination off
set confirm off
set arch i386

target remote localhost:1234

echo "=== Initial State ==="
info registers

echo ""
echo "=== Entry Point Disassembly (0x7c00) ==="
x/20i 0x7c00

echo ""
echo "=== Jumping to _start ==="
break _start
continue

echo ""
echo "=== At _start ==="
info registers

echo ""
echo "=== Disassembly at EIP ==="
x/20i $eip

echo ""
echo "=== Stepping through setup_gdt ==="
break setup_gdt
continue

echo ""
echo "=== At setup_gdt ==="
info registers
x/20i $eip

echo ""
echo "=== Continuing to kernel_main ==="
break kernel_main
continue

echo ""
echo "=== At kernel_main ==="
info registers
x/20i $eip

# Show GDT
echo ""
echo "=== GDT Register ==="
info registers gdtr

# Show IDT  
echo ""
echo "=== IDT Register ==="
info registers idtr

# Show TR (TSS register)
echo ""
echo "=== TR Register ==="
info registers

quit
GDBEOF

echo "Running automated debug sequence..."
echo ""

$RUST_GDB -batch -x /tmp/gdb_auto.txt $KERNEL_BIN 2>&1

# Cleanup
kill $QEMU_PID 2>/dev/null || true
echo ""
echo "=== Debug Complete ==="
