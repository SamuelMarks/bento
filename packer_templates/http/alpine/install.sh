#!/bin/sh
set -x
HTTPIP=$1
HTTPPORT=$2

wget http://${HTTPIP}:${HTTPPORT}/alpine/answers -O answers

# Find the installation disk (ignoring loops, cdroms, ramdisks)
DISK=$(ls /sys/block | grep -E '^sd|^vd|^nvme' | head -n 1)

sed -i "s|/dev/sda|/dev/$DISK|g" answers

setup-alpine -f answers <<ANSWERS
vagrant
vagrant
vagrant
vagrant
y
ANSWERS

# Wait for disk to settle
sleep 5

# Mount the root partition. sys install creates 3 partitions (boot, swap, root).
mount /dev/${DISK}3 /mnt
if [ $? -ne 0 ]; then
  mount /dev/${DISK}p3 /mnt
fi

echo 'PermitRootLogin yes' >> /mnt/etc/ssh/sshd_config
echo 'PasswordAuthentication yes' >> /mnt/etc/ssh/sshd_config

# Install sudo and bash in the new system since bento relies on them
sed -i 's/^#//g' /mnt/etc/apk/repositories
chroot /mnt apk update
chroot /mnt apk add sudo bash

mkdir -p /mnt/etc/sudoers.d
echo 'vagrant ALL=(ALL) NOPASSWD: ALL' > /mnt/etc/sudoers.d/vagrant
chmod 440 /mnt/etc/sudoers.d/vagrant

# Ensure user exists, set bash shell, set passwords
chroot /mnt adduser -D -g "" vagrant || true
sed -i '/^vagrant:/s|:[^:]*$|:/bin/bash|' /mnt/etc/passwd
echo "/bin/bash" >> /mnt/etc/shells

echo "vagrant:vagrant" | chroot /mnt chpasswd
echo "root:vagrant" | chroot /mnt chpasswd

umount /mnt
sync
sleep 5
reboot
