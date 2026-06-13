# Security Hardening Checklist

### Image Security
- [x] LUKS2 with AES-512-XTS encryption
- [x] Argon2id KDF (memory-hard, GPU-resistant)
- [x] Network-bound unlock only (Tang/Clevis) — image is a brick offline
- [x] SHA-512 image checksums verified by initrd before mount
- [x] Signed kernel + initrd (Secure Boot with MOK)

### Boot Security
- [x] UEFI Secure Boot enabled on thin clients
- [x] iPXE binary signed with your MOK key
- [x] TLS 1.3 only — no TLS 1.2 or lower
- [x] Embedded CA in iPXE — clients reject any other certificate
- [x] MAC + UUID double-verification before image served
- [x] Boot token in HTTP header (rotated each build)
- [x] All boot attempts logged with timestamp, IP, MAC, UUID

### Kiosk OS Security
- [x] Minimal RHEL 9 install — no SSH, no shell for end users
- [x] Read-only root filesystem (overlay or squashfs)
- [x] Kiosk user with no sudo, no TTY access
- [x] Browser in isolated Wayland session (cage compositor)
- [x] Browser homepage locked to your app URL
- [x] USB storage disabled (udev rules)
- [x] Keyboard shortcuts disabled (no Ctrl+Alt+T, no F-keys)
- [x] Auto-reboot on browser crash

### Network Security
- [x] Thin clients in isolated VLAN per site
- [x] Only outbound 443 to Sites and app server allowed
- [x] No inbound connections to thin clients
- [x] DNS resolves only your app domain (local DNS override)

### Operational Security
- [x] Allowlist stored in version control (git) with audit trail
- [x] Image build is reproducible and scripted (no manual steps)
- [x] Old images purged after 2 build cycles
- [x] Boot audit log shipped to SIEM

