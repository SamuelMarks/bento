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

# Locate directories
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

UNALTERED_SHA256="638aa2c88e94385b00f4f178d071e3df0b7d9e335577a83bd533b7f2eb65adf0"

# Search candidate locations for Windows 11 ARM64 ISO
SRC_ISO="${WIN11_ISO_PATH:-}"
if [ -z "${SRC_ISO}" ] || [ ! -f "${SRC_ISO}" ]; then
    for c in "${ISO_DIR}/Win11_25H2_English_Arm64_v2.iso" "${ISO_DIR}/Win11_25H2_English_Arm64.iso" "${ISO_DIR}/Win11_24H2_English_Arm64.iso" "${ISO_DIR}/Win11_English_Arm64.iso" "${REPO_ROOT}/builds/iso/Win11_25H2_English_Arm64_v2.iso" "${REPO_ROOT}/builds/iso/Win11_25H2_English_Arm64.iso" "${SCRIPT_DIR}/builds/iso/Win11_25H2_English_Arm64_v2.iso" "${SCRIPT_DIR}/builds/iso/Win11_25H2_English_Arm64.iso"; do
        if [ -f "${c}" ]; then
            SRC_ISO="${c}"
            break
        fi
    done
fi

if [ -z "${SRC_ISO}" ] || [ ! -f "${SRC_ISO}" ]; then
    echo "================================================================================"
    echo "ERROR: Windows 11 ARM64 ISO not found!"
    echo ""
    echo "Please download the official Windows 11 ARM64 ISO from Microsoft:"
    echo "  https://www.microsoft.com/en-us/software-download/windows11arm64"
    echo ""
    echo "Expected unaltered ISO SHA256:"
    echo "  ${UNALTERED_SHA256}"
    echo ""
    echo "Place the ISO at one of the following locations or set WIN11_ISO_PATH in .env:"
    echo "  - ${ISO_DIR}/Win11_25H2_English_Arm64.iso"
    echo "  - ${REPO_ROOT}/builds/iso/Win11_25H2_English_Arm64.iso"
    echo "================================================================================"
    exit 1
fi

echo "==> Using Source Windows 11 ARM64 ISO: ${SRC_ISO}"

WORK_DIR="${ISO_DIR}/win11_arm64_src"
TARGET_ISO="${ISO_DIR}/Win11_25H2_English_Arm64_v2.iso"
TARGET_RAW="${ISO_DIR}/win11_media.raw"
CIDATA_DIR="${SCRIPT_DIR}/packer_templates/cidata"
ANSWER_FILE="${SCRIPT_DIR}/packer_templates/win_answer_files/11/arm64/Autounattend.xml"

# Extract source ISO if source directory is missing or empty
if [ ! -f "${WORK_DIR}/sources/boot.wim" ] || [ ! -f "${WORK_DIR}/sources/install.wim" ]; then
    echo "==> Extracting source ISO to ${WORK_DIR}..."
    mkdir -p "${WORK_DIR}"
    if command -v 7z >/dev/null 2>&1; then
        7z x -y -o"${WORK_DIR}" "${SRC_ISO}"
    elif command -v hdiutil >/dev/null 2>&1; then
        MOUNT_DIR=$(mktemp -d /tmp/win11_mount.XXXXXX)
        hdiutil attach -nobrowse -mountpoint "${MOUNT_DIR}" "${SRC_ISO}"
        cp -R "${MOUNT_DIR}/"* "${WORK_DIR}/"
        hdiutil detach "${MOUNT_DIR}"
        rm -rf "${MOUNT_DIR}"
    else
        echo "ERROR: Neither 7z nor hdiutil found to extract ISO."
        exit 1
    fi
fi

# Clean macOS metadata
find "${WORK_DIR}" -name "._*" -delete 2>/dev/null || true
if command -v dot_clean >/dev/null 2>&1; then
    dot_clean "${WORK_DIR}" 2>/dev/null || true
fi

# Prepare flat drivers directory
TEMP_DRV_DIR=$(mktemp -d /tmp/win11_drivers.XXXXXX)
find "${CIDATA_DIR}" -type f \( -name "*.inf" -o -name "*.sys" -o -name "*.cat" -o -name "*.dll" -o -name "*.exe" \) -exec cp {} "${TEMP_DRV_DIR}/" \;

# Prepare scripts to inject into WinPE
TEMP_SCRIPTS_DIR=$(mktemp -d /tmp/win11_scripts.XXXXXX)
cat << 'EOF' > "${TEMP_SCRIPTS_DIR}/install_drivers.cmd"
@echo off
echo Loading VirtIO storage, network, and system drivers...
for %%i in (X:\drivers\*.inf) do drvload.exe "%%i"

echo Initializing WinPE...
wpeinit

echo Refreshing mount points...
mountvol.exe /R
mountvol.exe /E
wpeutil.exe UpdateBootInfo

echo === FSUTIL DRIVES ===
fsutil.exe fsinfo drives

echo Checking for installation media...
for %%d in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist %%d:\sources\install.wim (
        if not "%%d:"=="X:" (
            echo Found install.wim on %%d:!
            cd /d %%d:
            echo Starting setup.exe /unattend:X:\Autounattend.xml...
            setup.exe /unattend:X:\Autounattend.xml
            goto :done
        )
    )
)

echo ERROR: Media not found!
pause
cmd.exe

:done
EOF

cat << 'EOF' > "${TEMP_SCRIPTS_DIR}/startnet.cmd"
@echo off
wpeinit
call X:\install_drivers.cmd
EOF

cp "${ANSWER_FILE}" "${TEMP_SCRIPTS_DIR}/Autounattend.xml"
cp "${ANSWER_FILE}" "${WORK_DIR}/Autounattend.xml"

# Update boot.wim index 1 & 2 using wimlib-imagex
if command -v wimlib-imagex >/dev/null 2>&1; then
    echo "==> Injecting VirtIO drivers and automated setup scripts into boot.wim..."
    cat << EOF > "${TEMP_SCRIPTS_DIR}/wim_cmds.txt"
delete --force --recursive /drivers
add ${TEMP_DRV_DIR} /drivers
add ${TEMP_SCRIPTS_DIR}/Autounattend.xml /Autounattend.xml
add ${TEMP_SCRIPTS_DIR}/install_drivers.cmd /install_drivers.cmd
add ${TEMP_SCRIPTS_DIR}/startnet.cmd /Windows/System32/startnet.cmd
EOF

    wimlib-imagex update "${WORK_DIR}/sources/boot.wim" 1 < "${TEMP_SCRIPTS_DIR}/wim_cmds.txt"
    wimlib-imagex update "${WORK_DIR}/sources/boot.wim" 2 < "${TEMP_SCRIPTS_DIR}/wim_cmds.txt"
fi

rm -rf "${TEMP_DRV_DIR}" "${TEMP_SCRIPTS_DIR}"

# Build ExFAT raw installation media disk
if command -v hdiutil >/dev/null 2>&1; then
    echo "==> Generating ExFAT raw media image: ${TARGET_RAW}..."
    TEMP_DMG="${TARGET_RAW}.dmg"
    rm -f "${TARGET_RAW}" "${TEMP_DMG}"
    hdiutil create -size 9g -fs ExFAT -layout MBRSPUD -volname "WIN11" -srcfolder "${WORK_DIR}" -format UDRW -ov "${TEMP_DMG}"
    mv "${TEMP_DMG}" "${TARGET_RAW}"
fi

# Build bootable UEFI ISO with xorriso
if command -v xorriso >/dev/null 2>&1; then
    echo "==> Mastering bootable UEFI ISO: ${TARGET_ISO}..."
    rm -f "${TARGET_ISO}"
    xorriso -as mkisofs -iso-level 4 -l -R -J -V "CCCOMA_A64FRE_EN-US_DV9" -eltorito-alt-boot -e efi/microsoft/boot/efisys_noprompt.bin -no-emul-boot -isohybrid-gpt-basdat -o "${TARGET_ISO}" "${WORK_DIR}"
fi

CALCULATED_SHA256=$(shasum -a 256 "${TARGET_ISO}" | awk '{print $1}')
echo "==> Remastered ISO SHA256: ${CALCULATED_SHA256}"
echo "WIN11_TARGET_ISO=${TARGET_ISO}"
echo "WIN11_TARGET_RAW=${TARGET_RAW}"
echo "WIN11_ISO_CHECKSUM=${CALCULATED_SHA256}"
