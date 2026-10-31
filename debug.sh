#!/bin/bash
# Debug script for OS32 kernel using rust-gdb

set -e

KERNEL_BIN="target/i686-unknown-none/debug/os32"
QEMU_BIN=$(which qemu-system-i386 || echo "/usr/bin/qemu-system-i386")
RUST_GDB=$(which rust-gdb || echo "gdb")

echo "=== OS32 Kernel Debugger ==="
echo "Kernel: $KERNEL_BIN"
echo "QEMU: $QEMU_BIN"
echo "Debugger: $RUST_GDB"
echo ""

# Check if kernel binary exists
if [ ! -f "$KERNEL_BIN" ]; then
    echo "ERROR: Kernel binary not found at $KERNEL_BIN"
    echo "Run './build.sh' first to build the kernel."
    exit 1
fi

# Start QEMU with GDB stub
echo "Starting QEMU with GDB stub on port 1234..."
echo "Press Enter in another terminal to attach debugger, or wait for auto-attach..."

# Start QEMU in background with -S (start stopped) and -s (gdb stub on port 1234)
$QEMU_BIN -kernel $KERNEL_BIN -S -s -d guest_errors,int,cpu_reset -no-reboot &
QEMU_PID=$!

# Give QEMU time to start
sleep 2

# Create GDB commands file
cat > /tmp/gdb_commands.txt << 'EOF'
set pagination off
set confirm off

# Set architecture
set arch i386

# Show registers on stop
show registers

# Set breakpoints at key entry points
break _start
break kernel_main

# Continue execution
continue

# If we hit a breakpoint, show backtrace and registers
EOF

echo ""
echo "Attaching debugger..."
echo "========================"

# Attach to QEMU via GDB
$RUST_GDB -ex "target remote localhost:1234" -ex "source /tmp/gdb_commands.txt" \
    -ex "info registers" \
    -ex "x/20i $pc" \
    -ex "quit" \
    $KERNEL_BIN 2>&1 || true

# Cleanup
echo ""
echo "========================"
echo "Stopping QEMU (PID: $QEMU_PID)..."
kill $QEMU_PID 2>/dev/null || true

echo "Debug session complete."
