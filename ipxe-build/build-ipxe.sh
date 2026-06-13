#!/bin/bash
set -ex
docker build -t rocky-ipxe .
mkdir -p output
docker run --rm -v $(pwd)/output:/out rocky-ipxe cp -a /binaries/ipxe.efi /out/
