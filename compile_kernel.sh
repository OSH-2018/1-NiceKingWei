#!/bin/sh
sudo apt install busybox build-dep
tar xf linux-4.14.30.tar.xz
cd linux-4.14.30
make menuconfig
make -j