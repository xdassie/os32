#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Super Grub2 Disk USB Testing ==="
echo ""

# Check if ISO exists
if [ ! -f os32.iso ]; then
    echo "Error: os32.iso not found. Run ./agentmenu.sh first."
    exit 1
fi

echo "Copying ISO to USB BOOTISOS directory..."
cp os32.iso /run/media/dave/SG2DISOS/BOOTISOS/
echo "✓ ISO copied to /run/media/dave/SG2DISOS/BOOTISOS/os32.iso"
echo ""

echo "Unmounting USB drive partitions..."
sudo umount /dev/sda1 /dev/sda2 2>/dev/null || true
echo "✓ USB drive unmounted"
echo ""

echo "=== Booting QEMU from USB drive ==="
echo "Press 'l' for Loopback ISO Boot, then select os32.iso"
echo ""
echo "Running: sudo qemu-system-i386 -m 512  -hda /dev/sda -boot c"
echo "(You will be prompted for your sudo password)"
echo ""

sudo qemu-system-i386 -m 512  -hda /dev/sda -boot c 

echo ""
echo "Remounting USB drive..."
sudo mount /dev/sda1 /run/media/dave/SG2DBOOT 2>/dev/null || true
sudo mount /dev/sda2 /run/media/dave/SG2DISOS 2>/dev/null || true
echo "✓ USB drive remounted"
