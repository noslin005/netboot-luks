#!/bin/bash
sudo mount --bind /sys/ /mnt/rootfs/sys
sudo mount --bind /proc /mnt/rootfs/proc
sudo mount --bind /dev/ /mnt/rootfs/dev
sudo cp /etc/resolv.conf /mnt/rootfs/etc/
sudo chroot /mnt/rootfs/ /bin/bash
