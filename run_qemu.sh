#!/usr/bin/env bash
set -e
ISO_DIR="${ISO_DIR:-/Volumes/TOSHIBA_EXT/isos}"
BUILDS_DIR="${BUILDS_DIR:-/Volumes/TOSHIBA_EXT/vagrant}"

mkdir -p "${BUILDS_DIR}/build_files/packer-windows-11-aarch64-qemu"
qemu-img create -f qcow2 "${BUILDS_DIR}/build_files/packer-windows-11-aarch64-qemu/windows-11-aarch64" 131072M
