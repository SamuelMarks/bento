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

if [ -z "${BENTO_BUILD_FILES_DIR:-}" ]; then
    if [ -d "/Volumes/TOSHIBA_EXT" ]; then
        BENTO_BUILD_FILES_DIR="/Volumes/TOSHIBA_EXT/vagrant/build_files"
    else
        BENTO_BUILD_FILES_DIR="${REPO_ROOT}/builds/build_files"
    fi
fi
if [ -z "${BENTO_BUILD_COMPLETE_DIR:-}" ]; then
    if [ -d "/Volumes/TOSHIBA_EXT" ]; then
        BENTO_BUILD_COMPLETE_DIR="/Volumes/TOSHIBA_EXT/vagrant/build_complete"
    else
        BENTO_BUILD_COMPLETE_DIR="${REPO_ROOT}/builds/build_complete"
    fi
fi
export BENTO_BUILD_FILES_DIR
export BENTO_BUILD_COMPLETE_DIR
mkdir -p "${BENTO_BUILD_FILES_DIR}" "${BENTO_BUILD_COMPLETE_DIR}"

if [ -n "${TMPDIR:-}" ]; then
    TEST_SOCK="${TMPDIR}/.packer_sock_test_$$"
    if ! python3 -c "import socket, sys; s=socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.bind(sys.argv[1]); s.close()" "${TEST_SOCK}" 2>/dev/null; then
        echo "==> Note: Current TMPDIR (${TMPDIR}) does not support UNIX domain sockets (e.g. ExFAT)."
        echo "==> Directing Packer plugin IPC sockets to /tmp while keeping caches on external storage."
        export TMPDIR="/tmp"
    fi
    rm -f "${TEST_SOCK}" 2>/dev/null || true
fi

export PACKER_CACHE_DIR="${PACKER_CACHE_DIR:-${ISO_DIR}/.packer_cache}"
mkdir -p "${PACKER_CACHE_DIR}"

# Locate the official ISO
TARGET_ISO="${WIN11_TARGET_ISO:-${ISO_DIR}/Win11_25H2_English_Arm64_v2.iso}"
if [ ! -f "${TARGET_ISO}" ]; then
    for c in "${ISO_DIR}/Win11_25H2_English_Arm64_v2.iso" "${ISO_DIR}/Win11_25H2_English_Arm64.iso" "${ISO_DIR}/Win11_24H2_English_Arm64.iso" "${ISO_DIR}/Win11_English_Arm64.iso"; do
        if [ -f "${c}" ]; then
            TARGET_ISO="${c}"
            break
        fi
    done
fi

if [ ! -f "${TARGET_ISO}" ]; then
    echo "================================================================================"
    echo "ERROR: Windows 11 ARM64 ISO not found!"
    echo "Please download the official Windows 11 ARM64 ISO from Microsoft:"
    echo "  https://www.microsoft.com/en-us/software-download/windows11arm64"
    echo "================================================================================"
    exit 1
fi

# Prepare OEM ISO with drivers and answer file
TARGET_OEM_ISO="${ISO_DIR}/bento_win11_arm64_unattend.iso"
if [ ! -f "${TARGET_OEM_ISO}" ]; then
    "${SCRIPT_DIR}/prepare_win11_arm64_iso.sh"
fi

echo "==> Calculating SHA256 checksum for ${TARGET_ISO}..."
ISO_CHECKSUM=$(shasum -a 256 "${TARGET_ISO}" | awk '{print $1}')

echo "==> Building Windows 11 ARM64 Box with Packer..."
echo "==> Main ISO URL: file://${TARGET_ISO}"

export PACKER_PLUGIN_PATH="${PACKER_CACHE_DIR}/plugins"
mkdir -p "${PACKER_PLUGIN_PATH}"

packer init "${SCRIPT_DIR}/packer_templates/"

set -- -only=qemu.vm -timestamp-ui -force
set -- "$@" -var-file="${SCRIPT_DIR}/windows-11-aarch64.pkrvars.hcl"
set -- "$@" -var "iso_url=file://${TARGET_ISO}"
set -- "$@" -var "iso_checksum=${ISO_CHECKSUM}"
set -- "$@" -var "win11_oem_iso=${TARGET_OEM_ISO}"
set -- "$@" -var "bento_build_files_dir=${BENTO_BUILD_FILES_DIR}"
set -- "$@" -var "bento_build_complete_dir=${BENTO_BUILD_COMPLETE_DIR}"
set -- "$@" "${SCRIPT_DIR}/packer_templates/"

exec packer build "$@"
