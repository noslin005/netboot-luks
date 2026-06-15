#!/bin/bash
# vim: set ts=4 sw=4 sts=4 expandtab smarttab:
# Author: Nilson Lopes
# File: module-setup.sh 
# Description: module setup for live-luks

check(){
    # Include if rd.live.luks=1 is set
	# or if a luks-wrapped squafs is detected
	return 255 # 255 = only include if explicity requested
}

depends(){
	echo "network crypt url-lib base systemd clevis clevis-pin-tang"
	return 0
}

install(){
    # Install binaries
	inst_multiple \
	curl \
	losetup \
	blkid \
	modprobe \
	truncate \
	dd

	# Install systems modules
	instmods \
	loop \
	dm-crypt \
	dm-mod loop \
	squashfs \
	overlay

    # Install the real CA bundle (not the symlink)
    inst_simple /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem

    # Recreate the symlink chain curl expects
    mkdir -p "${initdir}/etc/pki/tls/certs"
    ln -sf /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem "${initdir}/etc/pki/tls/certs/ca-bundle.crt"

	# Inject module script into dracut hook
	inst_hook initqueue/settled 60 "$moddir/live-luks-root.sh"
}
