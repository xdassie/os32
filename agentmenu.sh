#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Building Docker image ==="
docker build --network=host -t os32-builder:latest .

echo "=== Building kernel ==="
docker run --network=host --rm -v "$SCRIPT_DIR":/app -w /app os32-builder:latest bash -c '
    source $HOME/.cargo/env
    # Build Rust kernel module with custom target
    cd src && cargo -Zbuild-std=core,alloc -Zbuild-std-features=compiler-builtins-mem \
        -Zunstable-options -Zjson-target-spec \
        build --target ../targets/i686-unknown-none.json --release && \
    cp target/i686-unknown-none/release/libkernel.a ../build/kernel.a && \
    cd .. && \
    echo "Rust module compiled successfully"
    nasm -g -f elf32 build/boot.asm -o build/boot.o
    ld.lld -m elf_i386 -T build/linker.ld build/boot.o build/kernel.a -o build/boot.elf
'

cp build/boot.elf os32.elf

echo "=== Validating multiboot kernel ==="
if grub-file --is-x86-multiboot os32.elf; then
    echo "✓ Valid multiboot kernel"
else
    echo "✗ Invalid multiboot kernel"
    exit 1
fi

echo "=== Creating ISO with loopback support ==="
rm -rf iso_root
mkdir -p iso_root/boot/grub
cp os32.elf iso_root/boot/os32.elf

# Main GRUB config for direct El Torito boot
cat > iso_root/boot/grub/grub.cfg << 'EOF'
set timeout=0
set default=0

menuentry "OS32" {
    multiboot /boot/os32.elf
    boot
}
EOF

# loopback.cfg for Super Grub2 Disk loopback boot
cat > iso_root/boot/grub/loopback.cfg << 'EOF'
set timeout=0
set default=0

menuentry "OS32 (from ISO)" {
    multiboot /boot/os32.elf
    boot
}
EOF

echo "=== ISO structure ==="
find iso_root -type f | sort

echo "=== Creating bootable ISO ==="
grub-mkrescue -o os32.iso iso_root 2>&1 | grep -v "^xorriso\|^Drive\|^Media\|^Added\|^ISO image\|^Written\|^Writing" || true

echo ""
echo "=== ISO created: os32.iso ==="
file os32.iso
echo "Size: $(du -h os32.iso | cut -f1)"

echo ""
echo "=== Inspecting ISO contents ==="
isoinfo -l -i os32.iso 2>/dev/null | grep -E "(os32\.elf|loopback\.cfg|grub\.cfg)" || echo "Files not found in listing"

echo ""
echo "=== Testing in QEMU (CD-ROM) ==="
timeout 8 qemu-system-i386 -m 512 -nographic -cdrom os32.iso -boot d -serial stdio 2>&1 | tail -10 || true

echo ""
echo "=== Testing in QEMU (HD/loopback) ==="
timeout 8 qemu-system-i386 -m 512 -nographic -drive file=os32.iso,format=raw,if=ide -serial stdio 2>&1 | tail -10 || true

echo ""
echo "=== Super Grub2 Disk USB Testing ==="
echo "Run ./test-sg2d.sh separately to test with the USB drive"
echo "(requires sudo for USB device access)"
