#!/bin/sh
safe="add-auto-load-safe-path "$(pwd)
gdb -ex $safe \
    -ex "file linux-4.14.30/vmlinux" \
    -ex "set arch i386:x86-64:intel" \
    -ex "target remote localhost:1234" \
    -ex "b start_kernel" \
    -ex "c" \
    -ex "disconnect" \
    -ex "set arch i386:x86-64" \
    -ex "target remote localhost:1234"