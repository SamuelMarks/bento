#!/bin/sh
set -eu

ISO_DIR="${ISO_DIR:-/Volumes/TOSHIBA_EXT/isos}"
BUILDS_DIR="${BUILDS_DIR:-/Volumes/TOSHIBA_EXT/vagrant}"

set -- -machine type=virt,accel=hvf -cpu host -smp 4 -m 6144M -display none
set -- "$@" -device qemu-xhci -device virtio-tablet -device virtio-net-pci,netdev=user.0
set -- "$@" -netdev user,id=user.0,hostfwd=tcp::5985-:5985
set -- "$@" -drive "file=${BUILDS_DIR}/build_files/packer-windows-11-aarch64-qemu/windows-11-aarch64,if=virtio,cache=unsafe,format=qcow2"
set -- "$@" -drive "file=${ISO_DIR}/Win11_25H2_English_Arm64_v2.iso,media=cdrom"
set -- "$@" -drive "file=${ISO_DIR}/win11_media.raw,if=virtio,cache=unsafe,format=raw"
set -- "$@" -drive "file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd,if=pflash,unit=0,format=raw,readonly=on"
set -- "$@" -drive "file=${BUILDS_DIR}/build_files/packer-windows-11-aarch64-qemu/efivars.fd,if=pflash,unit=1,format=raw"
set -- "$@" -boot strict=off -monitor unix:/tmp/qemu-monitor,server,nowait

/opt/homebrew/bin/qemu-system-aarch64 "$@" &
QEMU_PID=$!

sleep 10
echo "screendump /tmp/qemu_screen_1.ppm" | nc -U /tmp/qemu-monitor
sleep 30
echo "screendump /tmp/qemu_screen_2.ppm" | nc -U /tmp/qemu-monitor
sleep 60
echo "screendump /tmp/qemu_screen_3.ppm" | nc -U /tmp/qemu-monitor

kill "$QEMU_PID"
