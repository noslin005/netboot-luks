#!/bin/bash
# build-netboot.sh - minimal EL10 (Rocky/Alma) live netboot image for PXE testing
#
# Produces, in $OUTPUT_DIR:
#   vmlinuz       kernel (EFI stub, boots fine from iPXE/UEFI)
#   initrd.img    dracut initramfs (livenet + dmsquash-live): pulls the root image over HTTP
#   rootfs.sqfs   squashfs holding LiveOS/rootfs.img; runs from RAM with a writable overlay
#   boot.ipxe     iPXE script that boots the three files above from $BASE_URL
#
# Usage:
#   sudo ./build-netboot.sh [--debug] [--skip-install]
#
# Flags:
#   --debug         verbose dracut; boot.ipxe gets rd.shell rd.debug
#   --skip-install  reuse the existing rootfs (skip the dnf install)
#
# Environment overrides (all optional):
#   OUTPUT_DIR   where artifacts land                  (default: ./netboot-out)
#   BASE_URL     URL the client will fetch files from  (default: http://10.77.0.10/netboot)
#   MIRROR       distro mirror root                    (default: Rocky 10)
#                AlmaLinux: MIRROR=https://repo.almalinux.org/almalinux/10
#   SSH_PUBKEY   public key to install for root, enables key-based ssh
#   WORKDIR      scratch space, needs a few GB         (default: /var/tmp/netboot-build)
#
# Build host: any EL-family system with dnf, squashfs-tools and e2fsprogs. The PXE
# server itself works if it has internet access:
#   OUTPUT_DIR=/usr/share/nginx/html/netboot sudo -E ./build-netboot.sh
#
# The image has no root password. Root auto-logs in on tty1/ttyS0 only; ssh needs SSH_PUBKEY.

set -euo pipefail

# ---------------------------------------------
# Configuration
# ---------------------------------------------
RELEASEVER="${RELEASEVER:-10}"
MIRROR="${MIRROR:-https://download.rockylinux.org/pub/rocky/${RELEASEVER}}"
WORKDIR="${WORKDIR:-/var/tmp/netboot-build}"
ROOTFS="${ROOTFS:-${WORKDIR}/rootfs}"
STAGE="${WORKDIR}/stage"
OUTPUT_DIR="${OUTPUT_DIR:-${PWD}/netboot-out}"
BASE_URL="${BASE_URL:-http://10.77.0.10/netboot}"
NETBOOT_HOSTNAME="${NETBOOT_HOSTNAME:-pxe-live}"
SSH_PUBKEY="${SSH_PUBKEY:-}"

PACKAGES=(
  kernel-core
  kernel-modules-core
  kernel-modules
  systemd
  systemd-udev
  bash
  coreutils
  util-linux
  procps-ng
  findutils
  iproute
  iputils
  NetworkManager
  openssh-server
  curl
  passwd
  shadow-utils
  glibc-langpack-en
  rootfiles
  less
  vim-minimal
  dracut
  dracut-live
  dracut-network
  zstd
)
# NOTE: kernel-modules (full NIC driver set) can be dropped for VM-only tests.


DEBUG=0
SKIP_INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --debug)        DEBUG=1 ;;
    --skip-install) SKIP_INSTALL=1 ;;
    *) echo "Unknown flag: $arg" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------
# Helpers
# ---------------------------------------------
log() { echo -e "\n\033[1;34m>>> $*\033[0m"; }
die() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

[[ $(id -u) -eq 0 ]] || die "run as root (sudo)"

for cmd in dnf mksquashfs mkfs.ext4 chroot mountpoint truncate; do
  command -v "$cmd" &>/dev/null || die "required tool not found: $cmd"
done

# Bind /dev /proc /sys into the rootfs for scriptlets and dracut.
# --make-rslave stops umount from propagating back to the host's mounts.
API_MOUNTS=(dev proc sys)

mount_api() {
  local m
  for m in "${API_MOUNTS[@]}"; do
    mkdir -p "${ROOTFS}/${m}"
    if ! mountpoint -q "${ROOTFS}/${m}"; then
      mount --rbind "/${m}" "${ROOTFS}/${m}"
      mount --make-rslave "${ROOTFS}/${m}"
    fi
  done
}

umount_api() {
  local m
  for m in "${API_MOUNTS[@]}"; do
    if mountpoint -q "${ROOTFS}/${m}" 2>/dev/null; then
      umount -R -l "${ROOTFS}/${m}" || true
    fi
  done
}

trap umount_api EXIT

mkdir -p "$OUTPUT_DIR" "$WORKDIR"

# ========================================================
# PHASE 1 - minimal rootfs
# ========================================================
if [[ $SKIP_INSTALL -eq 0 ]]; then
  log "1/4  Installing EL${RELEASEVER} rootfs -> ${ROOTFS}"

  umount_api
  rm -rf --one-file-system "${ROOTFS}"
  mkdir -p "${ROOTFS}"
  mount_api

  # --nogpgcheck: --repofrompath repos carry no gpgkey. Fine for a throwaway test
  # image over HTTPS; add --setopt=<repo>.gpgkey=... if you want verification.
  dnf install \
    --installroot="${ROOTFS}" \
    --releasever="${RELEASEVER}" \
    --repofrompath="baseos,${MIRROR}/BaseOS/x86_64/os/" \
    --repofrompath="appstream,${MIRROR}/AppStream/x86_64/os/" \
    --disablerepo='*' --enablerepo=baseos --enablerepo=appstream \
    --nogpgcheck --assumeyes \
    --setopt=install_weak_deps=False \
    --setopt=tsflags=nodocs \
    "${PACKAGES[@]}"
else
  log "1/4  Skipping rootfs install (--skip-install)"
  [[ -d "${ROOTFS}/usr" ]] || die "no rootfs at ${ROOTFS}; run without --skip-install"
fi

# ========================================================
# PHASE 2 - configuration
# ========================================================
log "2/4  Configuring rootfs"
mount_api

chroot "${ROOTFS}" /usr/bin/env NB_HOSTNAME="${NETBOOT_HOSTNAME}" SSH_PUBKEY="${SSH_PUBKEY}" /bin/bash -eu <<'CHROOT'
umask 022
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo "${NB_HOSTNAME}" > /etc/hostname
echo 'PXE netboot test image (running from RAM)' > /etc/motd

# No root password; autologin on the consoles only
passwd -l root >/dev/null
for unit in getty@tty1 serial-getty@ttyS0; do
  mkdir -p "/etc/systemd/system/${unit}.service.d"
done
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
EOF

cat > /etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --keep-baud 115200,57600,38400,9600 %I $TERM
EOF

if [[ -n "${SSH_PUBKEY}" ]]; then
  install -d -m 700 /root/.ssh
  echo "${SSH_PUBKEY}" > /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
fi

systemctl enable NetworkManager sshd
systemctl set-default multi-user.target
: > /etc/machine-id          # regenerated on every boot
CHROOT

# ========================================================
# PHASE 3 - initramfs + kernel
# ========================================================
log "3/4  Building dracut initramfs"

cat > "${ROOTFS}/etc/dracut.conf.d/99-netboot.conf" <<'EOF'
hostonly="no"
add_dracutmodules+=" dmsquash-live livenet "
add_drivers+=" virtio_net virtio_blk virtio_pci "
early_microcode="no"
compress="zstd"
EOF

KVER=$(ls "${ROOTFS}/usr/lib/modules" | sort -V | tail -1)
[[ -n "$KVER" ]] || die "no kernel found in ${ROOTFS}/usr/lib/modules"

DRACUT_ARGS=(--force --no-hostonly --kver "$KVER")
[[ $DEBUG -eq 1 ]] && DRACUT_ARGS+=(-v)

chroot "${ROOTFS}" /bin/dracut "${DRACUT_ARGS[@]}" /tmp/initrd.img

# dracut writes the initramfs 0600; nginx runs unprivileged, so make it readable.
install -m 0644 "${ROOTFS}/tmp/initrd.img" "${OUTPUT_DIR}/initrd.img"
[[ -f "${ROOTFS}/usr/lib/modules/${KVER}/vmlinuz" ]] || die "vmlinuz missing for ${KVER}"
install -m 0644 "${ROOTFS}/usr/lib/modules/${KVER}/vmlinuz" "${OUTPUT_DIR}/vmlinuz"

# ========================================================
# PHASE 4 - root image + iPXE script
# ========================================================
log "4/4  Building rootfs.sqfs"

umount_api
# Remove unnecessary files
rm -rf --one-file-system \
  "${ROOTFS:?}"/tmp/* "${ROOTFS:?}"/boot/* "${ROOTFS:?}"/var/cache/dnf/* 2>/dev/null || true

# dmsquash-live's canonical layout: squashfs containing LiveOS/rootfs.img (ext4)
rm -rf "${STAGE}"
mkdir -p "${STAGE}/LiveOS"
USED_MB=$(du -sm --apparent-size "${ROOTFS}" | cut -f1)
IMG_MB=$(( USED_MB * 125 / 100 + 64 ))
truncate -s "${IMG_MB}M" "${STAGE}/LiveOS/rootfs.img"
mkfs.ext4 -q -F -L rootfs -d "${ROOTFS}" "${STAGE}/LiveOS/rootfs.img"

rm -f "${OUTPUT_DIR}/rootfs.sqfs"
mksquashfs "${STAGE}" "${OUTPUT_DIR}/rootfs.sqfs" -comp zstd -Xcompression-level 9 -noappend -quiet
chmod 0644 "${OUTPUT_DIR}/rootfs.sqfs"
rm -rf "${STAGE}"

CMDLINE="root=live:${BASE_URL}/rootfs.sqfs rd.neednet=1 ip=dhcp selinux=0 console=tty0 console=ttyS0,115200n8"
if [[ $DEBUG -eq 1 ]]; then
  CMDLINE+=" rd.shell rd.debug"
fi

cat > "${OUTPUT_DIR}/boot.ipxe" <<EOF
#!ipxe
echo Booting netboot test image from ${BASE_URL}
kernel ${BASE_URL}/vmlinuz ${CMDLINE} initrd=initrd.img
initrd ${BASE_URL}/initrd.img
boot
EOF
chmod 0644 "${OUTPUT_DIR}/boot.ipxe"

log "Done. Artifacts in ${OUTPUT_DIR}:"
ls -lh "${OUTPUT_DIR}"
cat <<EOF

Next steps:
  1. Serve ${OUTPUT_DIR} at ${BASE_URL}/ (e.g. copy to /usr/share/nginx/html/netboot/).
  2. Point the client port's bootfile-name DHCP option at ${BASE_URL}/boot.ipxe
  3. The client needs about 4 GB RAM: the root image is downloaded into memory.
EOF
