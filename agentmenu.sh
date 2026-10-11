#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Building Docker image ==="
docker build -t os32-builder:latest .

echo "=== Building kernel in Docker ==="
docker run --network=host --rm -v "$SCRIPT_DIR":/app -w /app os32-builder:latest bash -c '
    # Assemble boot code
    nasm -f elf32 build/boot.asm -o build/boot.o

    # Link the kernel
    ld.lld -m elf_i386 -T build/linker.ld build/boot.o -o os32.bin
'

# Copy the binary out (it was built in the mounted volume)
# Actually it should already be there since we mounted the volume

echo "=== Creating bootable ISO ==="
mkdir -p iso_root/boot/grub
cp os32.bin iso_root/boot/os32.bin

cat > iso_root/boot/grub/grub.cfg << 'EOF'
set timeout=0
set default=0

menuentry "OS32" {
    multiboot /boot/os32.bin
    boot
}
EOF

grub-mkrescue -o os32.iso iso_root

echo "=== Booting in QEMU ==="
echo "(Press Ctrl+C if it hangs)"
echo ""

qemu-system-i386 -cdrom os32.iso -boot d -m 512 -nographic 2>&1
