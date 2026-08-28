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

# Streamline install.wim: If multiple editions exist, export only Windows 11 Pro (index 3 or name match) to minimize image size
if command -v wimlib-imagex >/dev/null 2>&1; then
    WIM_COUNT=$(wimlib-imagex info "${WORK_DIR}/sources/install.wim" | grep "Image Count:" | awk '{print $3}')
    if [ "${WIM_COUNT}" -gt 1 ]; then
        echo "==> Streamlining install.wim: exporting Windows 11 Pro to reduce box and build size..."
        PRO_INDEX=$(wimlib-imagex info "${WORK_DIR}/sources/install.wim" | grep -B 2 "Name:.*Windows 11 Pro" | grep "Index:" | head -n1 | awk '{print $2}')
        if [ -z "${PRO_INDEX}" ]; then
            PRO_INDEX=3
        fi
        wimlib-imagex export "${WORK_DIR}/sources/install.wim" "${PRO_INDEX}" "${WORK_DIR}/sources/install_pro.wim" --compress=LZX
        mv "${WORK_DIR}/sources/install_pro.wim" "${WORK_DIR}/sources/install.wim"
    fi
fi

# Create startup.nsh at root of ISO to ensure EDK2 automatically boots without dropping to UEFI Shell
cat << 'EOF' > "${WORK_DIR}/startup.nsh"
@echo -off
if exist fs0:\efi\boot\bootaa64.efi then
  fs0:\efi\boot\bootaa64.efi
endif
if exist fs1:\efi\boot\bootaa64.efi then
  fs1:\efi\boot\bootaa64.efi
endif
if exist fs2:\efi\boot\bootaa64.efi then
  fs2:\efi\boot\bootaa64.efi
endif
\efi\boot\bootaa64.efi
\EFI\BOOT\BOOTAA64.EFI
EOF

# Prepare flat drivers directory
TEMP_DRV_DIR=$(mktemp -d /tmp/win11_drivers.XXXXXX)
find "${CIDATA_DIR}" -type f \( -name "*.inf" -o -name "*.sys" -o -name "*.cat" -o -name "*.dll" -o -name "*.exe" \) -exec cp {} "${TEMP_DRV_DIR}/" \;

# Prepare scripts to inject into WinPE
TEMP_SCRIPTS_DIR=$(mktemp -d /tmp/win11_scripts.XXXXXX)

cat << 'EOF' > "${TEMP_SCRIPTS_DIR}/install_drivers.cmd"
@echo off
echo ========================================================
echo  Bento Windows 11 ARM64 WinPE Pre-Installation Setup
echo ========================================================

echo [WinPE] Injecting LabConfig bypasses into registry...
reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassTPMCheck /t REG_DWORD /d 1 /f
reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassSecureBootCheck /t REG_DWORD /d 1 /f
reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassRAMCheck /t REG_DWORD /d 1 /f
reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassCPUCheck /t REG_DWORD /d 1 /f
reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassStorageCheck /t REG_DWORD /d 1 /f
reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassDiskCheck /t REG_DWORD /d 1 /f
reg.exe add "HKLM\SYSTEM\Setup\LabConfig" /v BypassNRO /t REG_DWORD /d 1 /f
reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f

echo [WinPE] Loading VirtIO drivers from X:\drivers...
for /r X:\drivers %%i in (*.inf) do (
    echo Loading driver: %%i
    drvload.exe "%%i"
)

echo [WinPE] Initializing WinPE networking and volume management...
wpeinit

echo [WinPE] Refreshing mount points...
mountvol.exe /R
mountvol.exe /E
wpeutil.exe UpdateBootInfo

echo [WinPE] Locating Autounattend.xml...
set UNATTEND=
if exist X:\Autounattend.xml set UNATTEND=X:\Autounattend.xml
for %%d in (D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist %%d:\Autounattend.xml set UNATTEND=%%d:\Autounattend.xml
)
echo [WinPE] Using answer file: %UNATTEND%

echo [WinPE] Searching for install.wim...
for %%d in (D E F G H I J K L M N O P Q R S T U V W Y Z C) do (
    if exist %%d:\sources\install.wim (
        echo [WinPE] Found installation source on %%d:
        cd /d %%d:
        if defined UNATTEND (
            echo [WinPE] Starting setup.exe /unattend:%UNATTEND%
            setup.exe /unattend:%UNATTEND%
        ) else (
            echo [WinPE] Starting setup.exe
            setup.exe
        )
        goto :done
    )
)

echo [WinPE] ERROR: install.wim not found on any volume!
pause
cmd.exe

:done
EOF

cat << 'EOF' > "${TEMP_SCRIPTS_DIR}/winpeshl.ini"
[LaunchApps]
"cmd.exe", "/c X:\install_drivers.cmd"
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
    echo "==> Injecting VirtIO drivers, winpeshl.ini, and automated setup scripts into boot.wim..."
    cat << EOF > "${TEMP_SCRIPTS_DIR}/wim_cmds.txt"
delete --force --recursive /drivers
add ${TEMP_DRV_DIR} /drivers
add ${TEMP_SCRIPTS_DIR}/Autounattend.xml /Autounattend.xml
add ${TEMP_SCRIPTS_DIR}/install_drivers.cmd /install_drivers.cmd
add ${TEMP_SCRIPTS_DIR}/winpeshl.ini /Windows/System32/winpeshl.ini
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
    hdiutil create -size 8g -fs ExFAT -layout MBRSPUD -volname "WIN11" -srcfolder "${WORK_DIR}" -format UDRW -ov "${TEMP_DMG}"
    mv "${TEMP_DMG}" "${TARGET_RAW}"
fi

# Build bootable UEFI ISO with xorriso
if command -v xorriso >/dev/null 2>&1; then
    echo "==> Mastering bootable UEFI ISO: ${TARGET_ISO}..."
    rm -f "${TARGET_ISO}"
    xorriso -as mkisofs -iso-level 4 -l -R -J -V "CCCOMA_A64FRE_EN-US_DV9" -e efi/microsoft/boot/efisys_noprompt.bin -no-emul-boot -isohybrid-gpt-basdat -o "${TARGET_ISO}" "${WORK_DIR}"
fi

CALCULATED_SHA256=$(shasum -a 256 "${TARGET_ISO}" | awk '{print $1}')
echo "==> Remastered ISO SHA256: ${CALCULATED_SHA256}"
echo "WIN11_TARGET_ISO=${TARGET_ISO}"
echo "WIN11_TARGET_RAW=${TARGET_RAW}"
echo "WIN11_ISO_CHECKSUM=${CALCULATED_SHA256}"
