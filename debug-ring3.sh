#!/bin/bash
# Debug ring 3 transition - connect to running QEMU with -s -S
# Run: qemu-system-i386 -m 256 -drive file=os32.iso,format=raw,if=ide -s -S

rust-gdb -ex "set pagination off" \
  -ex "target remote :1234" \
  -ex "b *0x01030a6" \
  -ex "continue" \
  -ex "p \$esp" \
  -ex "x/5wx \$esp" \
  -ex "si" \
  -ex "info reg" \
  -ex "quit" \
  build/boot.elf 2>&1
