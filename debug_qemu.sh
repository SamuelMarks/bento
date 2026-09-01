#!/bin/bash
rm -f /tmp/test-win.qcow2 && qemu-img create -f qcow2 /tmp/test-win.qcow2 10G > /dev/null

qemu-system-aarch64 \
  -machine virt,highmem=on,accel=hvf -cpu host -smp 4 -m 4096 \
  -drive file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd,if=pflash,unit=0,format=raw,readonly=on \
  -drive file=/tmp/test-vars.fd,if=pflash,unit=1,format=raw \
  -drive if=none,file=/tmp/test-win.qcow2,id=drive0 \
  -device nvme,drive=drive0,serial=nvme-1 \
  -device qemu-xhci \
  -drive file=/Volumes/TOSHIBA_EXT/isos/Win11_25H2_English_Arm64_v2.iso,media=cdrom,if=none,id=cd1 \
  -device usb-storage,drive=cd1,removable=on \
  -drive file=/Volumes/TOSHIBA_EXT/isos/bento_win11_arm64_unattend.iso,media=cdrom,if=none,id=cd2 \
  -device usb-storage,drive=cd2,removable=on \
  -display none -serial file:qemu_serial.log -monitor unix:/tmp/qemu-monitor.sock,server,nowait &
QEMU_PID=$!
sleep 13
echo "sendkey ret" | nc -U /tmp/qemu-monitor.sock
sleep 3
echo "sendkey f" | nc -U /tmp/qemu-monitor.sock
echo "sendkey s" | nc -U /tmp/qemu-monitor.sock
echo "sendkey 0" | nc -U /tmp/qemu-monitor.sock
echo "sendkey shift-semicolon" | nc -U /tmp/qemu-monitor.sock
echo "sendkey ret" | nc -U /tmp/qemu-monitor.sock
sleep 1
echo "sendkey c" | nc -U /tmp/qemu-monitor.sock
echo "sendkey a" | nc -U /tmp/qemu-monitor.sock
echo "sendkey t" | nc -U /tmp/qemu-monitor.sock
echo "sendkey spc" | nc -U /tmp/qemu-monitor.sock
echo "sendkey s" | nc -U /tmp/qemu-monitor.sock
echo "sendkey t" | nc -U /tmp/qemu-monitor.sock
echo "sendkey a" | nc -U /tmp/qemu-monitor.sock
echo "sendkey r" | nc -U /tmp/qemu-monitor.sock
echo "sendkey t" | nc -U /tmp/qemu-monitor.sock
echo "sendkey u" | nc -U /tmp/qemu-monitor.sock
echo "sendkey p" | nc -U /tmp/qemu-monitor.sock
echo "sendkey dot" | nc -U /tmp/qemu-monitor.sock
echo "sendkey n" | nc -U /tmp/qemu-monitor.sock
echo "sendkey s" | nc -U /tmp/qemu-monitor.sock
echo "sendkey h" | nc -U /tmp/qemu-monitor.sock
echo "sendkey ret" | nc -U /tmp/qemu-monitor.sock
sleep 3
echo "sendkey e" | nc -U /tmp/qemu-monitor.sock
echo "sendkey c" | nc -U /tmp/qemu-monitor.sock
echo "sendkey h" | nc -U /tmp/qemu-monitor.sock
echo "sendkey o" | nc -U /tmp/qemu-monitor.sock
echo "sendkey spc" | nc -U /tmp/qemu-monitor.sock
echo "sendkey t" | nc -U /tmp/qemu-monitor.sock
echo "sendkey e" | nc -U /tmp/qemu-monitor.sock
echo "sendkey s" | nc -U /tmp/qemu-monitor.sock
echo "sendkey t" | nc -U /tmp/qemu-monitor.sock
echo "sendkey ret" | nc -U /tmp/qemu-monitor.sock
sleep 2
kill $QEMU_PID
