# ==========================================
# Stage 1: Build iPXE from source
# ==========================================
FROM rockylinux:9 AS builder

# Install development tools and iPXE dependencies
RUN dnf update -y && dnf install -y \
    mtools \
    gcc \
    make \
    perl \
    binutils \
    xz-devel \
    zlib-devel \
    mtools \
    syslinux \
    openssl \
    openssl-devel \
    git \
    && dnf clean all

# Clone the official iPXE repository
WORKDIR /build
RUN git clone https://github.com/ipxe/ipxe.git

# Set working directory to the source folder
WORKDIR /build/ipxe/src

# Optional: If you have a custom embedded script, copy it in.
# COPY boot.ipxe .

COPY boot.ipxe ./boot.ipxe
COPY ca.crt ./ca.pem
COPY client.key ./client.key
COPY client.crt ./client.pem

# Build the standard 64-bit EFI binary
# If using an embedded script, append EMBED=boot.ipxe to the make command
RUN make bin-x86_64-efi/ipxe.efi \
    EMBED=boot.ipxe \
    TRUST=ca.pem \
    -j4

# ==========================================
# Stage 2: Create a minimal Rocky-based output image
# ==========================================
FROM rockylinux:9-minimal

# Copy the compiled EFI binary from the builder stage
COPY --from=builder /build/ipxe/src/bin-x86_64-efi/ipxe.efi /binaries/ipxe.efi

# Set the default command
CMD ["echo", "Your iPXE EFI binary is located at /binaries/ipxe.efi"]
