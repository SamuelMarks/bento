#!/usr/bin/env bash
set -e

# Load environment variables if .env exists
if [ -f "../.env" ]; then
    export $(grep -v '^#' ../.env | xargs)
fi

echo "Building Windows 11 ARM64 Box..."
packer init -upgrade packer_templates/
packer build \
  -only=qemu.vm \
  -timestamp-ui \
  -force \
  -var-file=windows-11-aarch64.pkrvars.hcl \
  packer_templates/
