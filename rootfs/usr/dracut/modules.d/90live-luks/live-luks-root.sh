#!/bin/bash
# vim: set ts=4 sw=4 sts=4 expandtab smarttab:
# Author: Nilson Lopes
# File: live-luks-root.sh
# Description: Dracut module to allow booting a live encrypted squash image
# shellcheck disable=SC1091

PATH=/usr/sbin:/usr/bin:/sbin:/bin

# Load dracut libs 
type getarg &>/dev/null || . /lib/dracut-lib.sh
type fetch_url &>/dev/null || . /lib/url-lib.sh

# Variables
NEWROOT="${NEWROOT:-/sysroot}"
SQUASH_MNT="/run/initramfs/squash"
ROOTFS_BASE="/run/rootfs"
LUKS_IMAGE="/run/initramfs/rootfs.luks"
MAPPER_NAME="luks-live"


# Argument Checks
# Continue only if rd.live.luks=1
getargbool 0 rd.live.luks || exit 0
live_luks_url=$(getarg rd.live.luks.url)
[ -z "$live_luks_url" ] && die "rd.live.luks.url not set"

LUKS_KEY=$(getarg rd.live.luks.key)
[ -z "$LUKS_KEY" ] && LUKS_KEY="-"

RUN_SIZE=$(getarg rd.run.size)
[ -z "$RUN_SIZE" ] && RUN_SIZE="4G"

info "Resizing /run to $RUN_SIZE"
mount -o remount,size="$RUN_SIZE" /run 2>/dev/null || warn "resize failed"


# Check Network
info "Waiting for network..."
retries=30
until ip route show default | grep -q default || [ $retries -eq 0 ]; do
    sleep 2
    ((retries--))
done
[ $retries -eq 0 ] && die "No default route after timeout";

# Download Image
mkdir -p /run/initramfs
info "Fetching: $live_luks_url"
IMAGE_SIZE=$(curl -sI "$live_luks_url"|awk -v IGNORECASE=1 '/^content-length/{print $NF}'|tr -d '\r')
[ -z $IMAGE_SIZE  ] && die "Received empty file"
truncate -s "$IMAGE_SIZE" "$LUKS_IMAGE" || die "Failed to allocate $IMAGE_SIZE bytes - not enough RAM"
info "Alocated $IMAGE_SIZE bytes for live image"

if ! fetch_url "$live_luks_url" "$LUKS_IMAGE"; then
    die "Failed to download image from $live_luks_url"
    exit 254
else
    info "Fetched Image: $live_luks_url"
fi
# Load Kernel Modules
modprobe loop >/dev/null || true
modprobe dm-mod 2>/dev/null || true
modprobe dm-crypt 2>/dev/null || true
modprobe squashfs 2>/dev/null || true
modprobe overlay 2>/dev/null || true

# Mount the Luks image to a loopback device
loop_dev=$(losetup --find --show "$LUKS_IMAGE")
[ -z "$loop_dev" ] && die "Failed to create loop device"

# Create a cleanup hook to detach loop device
# shellcheck disable=SC2154
printf "%s\n" "losetup -d $loop_dev" > "${hookdir}/cleanup/live-luks-20-loop.sh"

# Detect and Mount Luks Device
if ! cryptsetup isLuks "$loop_dev" 2>/dev/null; then
    warn "$loop_dev is not a luks device - using loop device directly"
    SQUASH_DEV="$loop_dev"
else
    luks_uuid="$(blkid "${loop_dev}" -o value -s UUID)"
    [ -z "$luks_uuid" ] && die "Unable to read UUID for device $loop_dev"

    # Create disk by-uuid sysmlink so systemd can find the device
    ln -sf "$loop_dev" "/dev/disk/by-uuid/$luks_uuid"

    # Writing crypttab lets systemd-cryptsetup handle unlock
    info "Writing crypttab entry for $MAPPER_NAME"
    printf "%s %s - luks" "$MAPPER_NAME" "$loop_dev" >> /etc/crypttab

    # Calls systemd-cryptsetup to unlock the device
    # Format: systemd-cryptsetup attach <name> <device> <keyfile> <options>
    /usr/lib/systemd/systemd-cryptsetup attach "$MAPPER_NAME" "$loop_dev" "$LUKS_KEY" "luks,tries=1,token-timeout=30" >&1
    sleep 2

    # Check if device is unlocked
    if [ ! -b "/dev/mapper/$MAPPER_NAME" ]; then
        die "Failed to unlock device encrypted device $loop_dev"
        exit 1
    fi
    info "Device $loop_dev unlock succeed"
    printf "%s\n" "cryptsetup close $MAPPER_NAME" > "${hookdir}/cleanup/live-luks-10-mapper.sh"
    SQUASH_DEV="/dev/mapper/$MAPPER_NAME"
fi

# Mount squashfs
mkdir -p "$SQUASH_MNT" "$ROOTFS_BASE" /run/overlays/upper /run/overlays/work
mount -t squashfs -o ro "$SQUASH_DEV" "$SQUASH_MNT" || die "Failed to mount squashfs from $SQUASH_DEV"
info "squashfs mounted at $SQUASH_MNT"

# Overlays
mount --bind "$SQUASH_MNT" "$ROOTFS_BASE"
mount -t overlay live-luks-rootfs -o lowerdir="$ROOTFS_BASE",upperdir=/run/overlays/upper,workdir=/run/overlays/work "$NEWROOT" || die "Failed to mount overlayfs on $NEWROOT"

# Jump into the new root
#SYSTEMD_IN_INITRD=lenient exec switch_root "$NEWROOT" /init
exit 0

