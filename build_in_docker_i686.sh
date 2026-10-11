#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Build Docker image
docker build -t os32-builder .

# Run container and build/test
docker run --rm -v "$SCRIPT_DIR":/app -w /app os32-builder bash -c '
    # Assemble boot code first
    nasm -f elf32 build/boot.asm -o build/boot.o

    # Build with cargo using lld linker
    cargo build --release -Zbuild-std=core --target build/i686-none.json

    # Test in QEMU
    echo "=== Testing in QEMU ==="
    qemu-system-i386 -nographic -kernel target/i686-unknown-none/release/os32
'
