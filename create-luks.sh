#!/bin/bash

set -ex

# Create squashfs
sudo rm -rf rootfs.luks
sudo mksquashfs \
/mnt/rootfs/ \
rootfs.luks \
-comp zstd \
-Xcompression-level 9 \
-wildcards \
-e "proc/*" \
-e "sys/*" \
-e "dev/*" \
-e "run/*" \
-e "tmp/*" \
-e "var/cache/dnf/*" \
-e "var/lib/dnf/*" \
-e "usr/share/doc/*" \
-e "usr/share/man/*" \
-e "usr/share/locale/*" \
-e "boot/*"               

echo "squashfs size: $(ls -lh rootfs.luks | awk '{print $5}')"

# Add 64MB for LUKS2 header + keyslots + alignment
sudo truncate -s +64M rootfs.luks

# Generate key if not exists
if [ ! -f luks.key ]; then
    sudo dd if=/dev/urandom bs=64 count=1 of=luks.key status=none
    sudo chmod 600 luks.key
    echo "Generated new LUKS key"
fi

# Encrypt in-place
sudo cryptsetup reencrypt \
--batch-mode \
--encrypt \
--type luks2 \
--hash sha512 \
--cipher aes-xts-plain64 \
--key-size 512 \
--pbkdf argon2id \
--resilience none \
--reduce-device-size 64M \
--disable-locks \
--label "rocky-live-luks" \
--key-file luks.key \
rootfs.luks

sudo cryptsetup -q luksAddKey rootfs.luks --key-file luks.key --force-password
#sudo clevis luks bind -d rootfs.luks tang '{"url":"https://10.12.0.100/tang"}' -- -k

echo "LUKS UUID: $(sudo cryptsetup luksDump rootfs.luks | awk '/^UUID/{print $2}')"
echo "Done: $(ls -lh rootfs.luks | awk '{print $5}')"

