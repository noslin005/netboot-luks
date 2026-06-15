#!/bin/bash
set -x

sudo qemu-system-x86_64 \
    -enable-kvm \
    -cpu host \
    -m 8192 \
    -smp 4 \
    -display vnc=127.0.0.1:0 \
    -kernel ./vmlinuz \
    -initrd ./initrd.img \
    -append "rd.neednet=1 ip=dhcp selinux=0 \
             rd.live.luks=1 \
             rd.live.luks.url=http://192.168.24.1:8080/rootfs.luks \
             rd.live.luks.key=/usr/share/.luks.key \
             rd.shell=1 \
             hostname=live-luks" \
    -netdev bridge,id=net0,br=virbr0 \
    -device virtio-net-pci,netdev=net0 
