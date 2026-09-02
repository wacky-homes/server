#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

mkdir -p .output

read -p "Is ./installer/config.toml updated? [Ny]: " yn
case $yn in
    [Yy]* ) break;;
    * ) exit;;
esac

podman build -t localhost/wacky-homes-installer:latest -f ./installer/Containerfile .

podman run \
    --rm \
    -it \
    --privileged \
    --pull=newer \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    -v ./installer/config.toml:/config.toml:ro \
    -v ./.output:/output \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type bootc-installer \
    --rootfs xfs \
    --installer-payload-ref ghcr.io/wacky-homes/server:latest \
    localhost/wacky-homes-installer:latest

echo ""
if [ -e .output/bootiso/install.iso ]; then
    echo "ISO ready at .output/bootiso/installer.iso"
    echo "Flash it to a USB drive with: sudo dd if=.output/bootiso/install.iso of=/dev/sdX bs=8M status=progress"
else
    echo "Failed to build installer"
fi
