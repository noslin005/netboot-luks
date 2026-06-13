# Create Encrypted Netboot Image

## Setup the base OS

```bash
sudo mkdir -p /mnt/rootfs
sudo dnf install -y \
    --installroot=/mnt/rootfs \
    --releasever=9 \
    --repofrompath=baseos,https://download.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/ \
    --repofrompath=appstream,https://download.rockylinux.org/pub/rocky/9/AppStream/x86_64/os/ \
    --repofrompath=crb,https://download.rockylinux.org/pub/rocky/9/CRB/x86_64/os/ \
    --disablerepo='\*' \
    --enablerepo=baseos \
    --enablerepo=appstream \
    --enablerepo=crb \
    @minimal-environment \
    clevis \
    clevis-luks \
    clevis-dracut \
    clevis-systemd \
    cryptsetup \
    dracut-network \
    dracut \
    dracut-live \
    NetworkManager \
    kernel \
    kernel-modules \
    sudo \
    procps-ng \
    bash-completion \
    glibc-langpack-en
```

## Enter CHROOT enviroment

- Setup chroot

```bash
sudo mount --bind /sys/ /mnt/rootfs/sys
sudo mount --bind /proc /mnt/rootfs/proc
sudo mount --bind /dev/ /mnt/rootfs/dev
sudo cp /etc/resolv.conf /mnt/rootfs/etc/
sudo chroot /mnt/rootfs/ /bin/bash
```

## Customization

- Copy your CA TLS Certs

```bash
# Copy the lab-ca.crt to /etc/pki/ca-trust/source/anchors/lab-ca.crt
update-ca-trust extract
```

- Install aditional packages if needed

```bash
dnf install --releasever=9 vim NetworkManager -y
```

- Fix Locale

```bash
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
dnf install --releasever=9 glibc-langpack-en -y
echo 'LANG="en_US.UTF-8"' > /etc/locale.conf

```

- Create User Account

```bash
useradd -m -G wheel -s /bin/bash kiosk -c Kiosk
passwd
```

- Create a dracut module to handle encrypted squashfs

```bash
# Assume youy have the files copied to the chroot environment
sudo install -d -u root -o root 90live-luks /usr/lib/dracut/modules.d/
```

- Configure dracut

```bash
cat <<EOF > /etc/dracut.conf.d/99-netboot.conf
hostonly="no"
hostonly_cmdline="yes"
add_dracutmodules+=" base network crypt clevis clevis-pin-tang systemd live-luks "
add_drivers+=" virtio_net virtio_pci e1000 ixgbe "
install_items+=" /usr/bin/ping /usr/bin/curl "
mdadmconf="no"
lvmconf="no"
early_microcode="no"
EOF
```

- Generate the initramfs

```bash
dracut -fv --regenerate-all --hostonly-cmdline
```

- Cleanup

```bash
rm -rf /mnt/rootfs/var/cache/dnf/*
```

---

## Exit chroot and Extract the initramfs and kernel

```bash
sudo cp /mnt/rootfs/boot/vmlinuz-5.14.0-687.12.1.el9_8.x86_64 vmlinuz
sudo cp /mnt/rootfs/boot/initramfs-5.14.0-687.12.1.el9_8.x86_64.img initrd.img
```

## Create squashfs

```bash
sudo mksquashfs /mnt/rootfs/ rootfs.luks -comp zstd -Xcompression-level 9 -wildcards -e "proc/*" -e "sys/*" -e "dev/*" -e "run/*" -e "tmp/*"
```

## Add padding for LUKS re-encryption

```bash
# Add padding for LUKS re-encryption
sudo truncate -s +32M rootfs.luks
```

## Re-encrypt the image

```bash
# Encrypt with LUKS2 (multiple keyslots)
sudo cryptsetup -q reencrypt --encrypt --type luks2 --hash sha512 --cipher aes-xts-plain64 --pbkdf argon2id --label "rocky-live-root" --resilience none --disable-locks --reduce-device-size 32M rootfs.luks --force-password
```

```bash
# OPTIONAL: Add keyfile (e.g., for automated or injected unlock)
sudo dd if=/dev/urandom of=keyfile.bin bs=2048 count=1
sudo cryptsetup luksAddKey rootfs.luks keyfile.bin
```

## Bind the container with a tang server

```bash
sudo clevis luks bind -f -d rootfs.luks tang '{"url":"https://10.12.0.100/tang"}' -- -k
```

---

## Test the image using qemu

> Copy the kernel and initramfs from chroot

```bash
#!/bin/bash
set -x

sudo qemu-system-x86_64 \
-enable-kvm \
-cpu host \
-m 8192 \
-smp 4 \
-nographic \
-kernel ./vmlinuz \
-initrd ./initrd.img \
-append "console=ttyS0 rd.neednet=1 ip=dhcp selinux=0 rd.live.luks=1 rd.live.luks.url=https://10.12.0.100/images/rootfs.luks hostname=live-luks" \
-netdev bridge,id=net0,br=virbr0 \
-device virtio-net-pci,netdev=net0
```

> If necessary add `rd.debug, rd.info or rd.shell=0` to the append line

