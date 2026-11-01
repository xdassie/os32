#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Running QEMU with VGA display ==="
echo "Press Ctrl+C after seeing the output to stop"

# Run QEMU with VGA and capture screen after 5 seconds
timeout 8 qemu-system-i386 -m 512 -cdrom os32.iso -boot d \
    -display sdl \
    -serial null \
    -no-reboot 2>&1 || true

echo ""
echo "=== Test complete ==="
