#!/bin/bash
# Interactive debug script for OS32 kernel using rust-gdb

KERNEL_BIN="target/i686-unknown-none/debug/os32"
QEMU_BIN=$(which qemu-system-i386 || echo "/usr/bin/qemu-system-i386")
RUST_GDB=$(which rust-gdb || echo "gdb")

echo "=== OS32 Kernel Interactive Debugger ==="
echo ""

# Check if kernel binary exists
if [ ! -f "$KERNEL_BIN" ]; then
    echo "ERROR: Kernel binary not found at $KERNEL_BIN"
    echo "Run './build.sh' first to build the kernel."
    exit 1
fi

# Start QEMU with GDB stub (stopped at start)
echo "Starting QEMU with GDB stub on port 1234..."
echo "QEMU will start PAUSED at the first instruction."
echo ""

$QEMU_BIN -kernel $KERNEL_BIN -S -s -d guest_errors,int,cpu_reset -no-reboot &
QEMU_PID=$!

# Give QEMU time to start
sleep 2

echo "QEMU started with PID: $QEMU_PID"
echo ""
echo "Opening interactive GDB session..."
echo "Useful commands:"
echo "  break _start        - Set breakpoint at entry point"
echo "  break kernel_main   - Set breakpoint at kernel_main"
echo "  continue            - Continue execution"
echo "  stepi               - Step one instruction"
echo "  nexti               - Step over instruction"
echo "  info registers      - Show all registers"
echo "  x/10i \$eip         - Disassemble 10 instructions from EIP"
echo "  x/16wx 0x47d00      - Examine GDT area"
echo "  x/32wx 0x90000      - Examine TSS area"
echo "  kill                - Stop QEMU and exit"
echo ""
echo "========================"

# Start interactive GDB
$RUST_GDB -ex "target remote localhost:1234" $KERNEL_BIN

# Cleanup on exit
echo ""
echo "========================"
echo "Stopping QEMU..."
kill $QEMU_PID 2>/dev/null || true
echo "Done."
