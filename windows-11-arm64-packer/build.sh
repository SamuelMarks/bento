#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "${SCRIPT_DIR}/.." && pwd)

# Load .env if present
if [ -f "${REPO_ROOT}/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "${REPO_ROOT}/.env"
    set +a
fi

# Locate directories with portable defaults
ISO_DIR="${ISO_DIR:-}"
if [ -z "${ISO_DIR}" ]; then
    if [ -d "/Volumes/TOSHIBA_EXT/isos" ]; then
        ISO_DIR="/Volumes/TOSHIBA_EXT/isos"
    elif [ -d "${REPO_ROOT}/builds/iso" ]; then
        ISO_DIR="${REPO_ROOT}/builds/iso"
    else
        ISO_DIR="${SCRIPT_DIR}/builds/iso"
    fi
fi

TARGET_ISO="${WIN11_TARGET_ISO:-${ISO_DIR}/Win11_25H2_English_Arm64_v2.iso}"
TARGET_RAW="${WIN11_TARGET_RAW:-${ISO_DIR}/win11_media.raw}"

# Auto-prepare ISO if remastered files are missing
if [ ! -f "${TARGET_ISO}" ] || [ ! -f "${TARGET_RAW}" ]; then
    echo "==> Preparing Windows 11 ARM64 ISO and installation media..."
    "${SCRIPT_DIR}/prepare_win11_arm64_iso.sh"
fi

if [ ! -f "${TARGET_ISO}" ]; then
    echo "================================================================================"
    echo "ERROR: Windows 11 ARM64 ISO not found!"
    echo "Please download the official Windows 11 ARM64 ISO from Microsoft:"
    echo "  https://www.microsoft.com/en-us/software-download/windows11arm64"
    echo "Expected unaltered ISO SHA256:"
    echo "  638aa2c88e94385b00f4f178d071e3df0b7d9e335577a83bd533b7f2eb65adf0"
    echo "================================================================================"
    exit 1
fi

echo "==> Calculating SHA256 checksum for ${TARGET_ISO}..."
ISO_CHECKSUM=$(shasum -a 256 "${TARGET_ISO}" | awk '{print $1}')

echo "==> Building Windows 11 ARM64 Box with Packer..."
echo "==> ISO URL:      file://${TARGET_ISO}"
echo "==> ISO Checksum: ${ISO_CHECKSUM}"

packer init -upgrade "${SCRIPT_DIR}/packer_templates/"

set -- -only=qemu.vm -timestamp-ui -force
set -- "$@" -var-file="${SCRIPT_DIR}/windows-11-aarch64.pkrvars.hcl"
set -- "$@" -var "iso_url=file://${TARGET_ISO}"
set -- "$@" -var "iso_checksum=${ISO_CHECKSUM}"
set -- "$@" "${SCRIPT_DIR}/packer_templates/"

exec packer build "$@"
