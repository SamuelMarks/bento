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
mkdir -p "${ISO_DIR}"

TARGET_OEM_ISO="${ISO_DIR}/bento_win11_arm64_unattend.iso"
CIDATA_DIR="${SCRIPT_DIR}/packer_templates/cidata"
ANSWER_FILE="${SCRIPT_DIR}/packer_templates/win_answer_files/11/arm64/Autounattend.xml"

echo "==> Preparing Windows 11 ARM64 OEM ISO with drivers and answer file..."

WORK_DIR=$(mktemp -d /tmp/bento_oem.XXXXXX)

# 1. Copy VirtIO drivers preserving directory structure
cp -R "${CIDATA_DIR}/"* "${WORK_DIR}/"

# 2. Render Autounattend.xml
python3 -c "
import re
content = open('${ANSWER_FILE}').read()
key = '${WIN11_PRODUCT_KEY:-W269N-WFGWX-YVC9B-4J6C9-T83GX}'
content = re.sub(r'%\{\s*if\s+windows_product_key\s*!=\s*\"\"\s*\}.*?%\{\s*endif\s*\}', f'<Key>{key}</Key>', content, flags=re.DOTALL)

open('${WORK_DIR}/Autounattend.xml', 'w').write(content)
"

# 3. Create startnet.cmd to force drvload of virtio storage drivers immediately in WinPE
mkdir -p "${WORK_DIR}/Windows/System32"
cat << 'EOF' > "${WORK_DIR}/Windows/System32/startnet.cmd"
wpeinit
@echo off
echo Loading VirtIO Drivers...
drvload.exe "\viostor\w11\ARM64\viostor.inf"
drvload.exe "\vioscsi\w11\ARM64\vioscsi.inf"
drvload.exe "\NetKVM\w11\ARM64\netkvm.inf"
EOF

# 4. Create startup.nsh to skip 'Press any key to boot from CD' and start setup automatically
cat << 'EOF' > "${WORK_DIR}/startup.nsh"
@echo -off
if exist fs0:\EFI\Microsoft\Boot\bootmgfw.efi then
  fs0:\EFI\Microsoft\Boot\bootmgfw.efi
endif
if exist fs1:\EFI\Microsoft\Boot\bootmgfw.efi then
  fs1:\EFI\Microsoft\Boot\bootmgfw.efi
endif
if exist fs2:\EFI\Microsoft\Boot\bootmgfw.efi then
  fs2:\EFI\Microsoft\Boot\bootmgfw.efi
endif
if exist fs3:\EFI\Microsoft\Boot\bootmgfw.efi then
  fs3:\EFI\Microsoft\Boot\bootmgfw.efi
endif
if exist fs0:\efi\boot\bootaa64.efi then
  fs0:\efi\boot\bootaa64.efi
endif
if exist fs1:\efi\boot\bootaa64.efi then
  fs1:\efi\boot\bootaa64.efi
endif
if exist fs2:\efi\boot\bootaa64.efi then
  fs2:\efi\boot\bootaa64.efi
endif
if exist fs3:\efi\boot\bootaa64.efi then
  fs3:\efi\boot\bootaa64.efi
endif
\efi\boot\bootaa64.efi
\EFI\BOOT\BOOTAA64.EFI
EOF

# 4. Generate ISO
if command -v hdiutil >/dev/null 2>&1; then
    hdiutil makehybrid -iso -joliet -default-volume-name "OEMDRV" -o "${TARGET_OEM_ISO}" "${WORK_DIR}"
elif command -v mkisofs >/dev/null 2>&1; then
    mkisofs -J -R -V "OEMDRV" -o "${TARGET_OEM_ISO}" "${WORK_DIR}"
elif command -v xorriso >/dev/null 2>&1; then
    xorriso -as mkisofs -J -R -V "OEMDRV" -o "${TARGET_OEM_ISO}" "${WORK_DIR}"
else
    echo "ERROR: hdiutil, mkisofs, or xorriso required to create ISO."
    exit 1
fi

rm -rf "${WORK_DIR}"

echo "WIN11_TARGET_OEM_ISO=${TARGET_OEM_ISO}"
echo "==> OEM ISO generation complete!"

