#!/bin/sh
qemu-system-x86_64 -kernel linux-4.14.30/arch/x86/boot/bzImage -initrd initrd.img-nixos -S -s -nographic -vnc :2  -m 2048 -append nokaslr