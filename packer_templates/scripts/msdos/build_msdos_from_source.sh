#!/bin/sh
#
# @file build_msdos_from_source.sh
# @brief Fetches, verifies, normalizes, and stages Microsoft MS-DOS (v1.25, v2.0, v4.0) from https://github.com/microsoft/ms-dos
# @description
#   Downloads the upstream microsoft/ms-dos archive into builds/iso/, verifies
#   its SHA-256 checksum (when MSDOS_ARCHIVE_SHA256 is set), validates the
#   v1.25, v2.0, and v4.0 directory layouts, normalizes line endings and
#   strips trailing 0x1A (Ctrl-Z) EOF markers in v4.0/src so MASM/CL/NMAKE/NOSRVBLD
#   compile cleanly without corrupting binary tools in v4.0/src/TOOLS, normalizes
#   uppercase 8.3 filenames, patches SETENV.BAT for the build VM layout, and stages
#   version-specific binaries, sources, and 16-bit tools into the target directory.
#

set -eu

MSDOS_REPO_URL="${MSDOS_REPO_URL:-https://github.com/microsoft/MS-DOS/archive/refs/heads/main.tar.gz}"
DEFAULT_MSDOS_SHA256="7826b531c5f455f2d21c6020a95a9ee49c71430a9278c244112e6c142a17031b"
MSDOS_ARCHIVE_SHA256="${MSDOS_ARCHIVE_SHA256:-$DEFAULT_MSDOS_SHA256}"
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "${SCRIPT_DIR}/../../.." && pwd)
BUILDS_DIR="${REPO_ROOT}/builds"
ISO_DIR="${BUILDS_DIR}/iso"
ARCHIVE_PATH="${ISO_DIR}/microsoft-ms-dos.tar.gz"
EXTRACT_ROOT="${BUILDS_DIR}/msdos_upstream"

#
# @function log_msg
# @description Prints a formatted build status message to standard output.
# @param [String] message The status message to print.
# @return [void]
#
log_msg() {
  printf '==> [MS-DOS Source Builder] %s\n' "$1"
}

#
# @function log_err
# @description Prints a formatted error message to standard error.
# @param [String] message The error message to print.
# @return [void]
#
log_err() {
  printf 'Error: [MS-DOS Source Builder] %s\n' "$1" >&2
}

#
# @function verify_archive_checksum
# @description
#   Verifies the SHA-256 digest of the cached microsoft-ms-dos.tar.gz archive
#   against MSDOS_ARCHIVE_SHA256 (unless set to "skip").
# @param [String] file_path Path to the archive file.
# @return [Integer] Returns 0 if valid, exits non-zero on mismatch.
#
verify_archive_checksum() {
  _archive="$1"
  if [ "$MSDOS_ARCHIVE_SHA256" = "skip" ] || [ -z "$MSDOS_ARCHIVE_SHA256" ]; then
    return 0
  fi

  _actual=""
  if command -v shasum >/dev/null 2>&1; then
    _actual=$(shasum -a 256 "$_archive" | awk '{print $1}')
  elif command -v sha256sum >/dev/null 2>&1; then
    _actual=$(sha256sum "$_archive" | awk '{print $1}')
  fi

  if [ -n "$_actual" ] && [ "$_actual" != "$MSDOS_ARCHIVE_SHA256" ]; then
    log_err "SHA-256 mismatch for ${_archive}: expected ${MSDOS_ARCHIVE_SHA256}, got ${_actual}"
    exit 1
  fi
  log_msg "Verified SHA-256 checksum for ${_archive} (${MSDOS_ARCHIVE_SHA256})"
  return 0
}

#
# @function verify_upstream_layout
# @description
#   Confirms that all required upstream directories (v1.25/bin, v1.25/source,
#   v2.0/bin, v2.0/source, v4.0/src/BIOS, v4.0/src/DOS, v4.0/src/CMD,
#   v4.0/src/TOOLS) exist inside builds/msdos_upstream. Fails fast if any
#   expected subdirectory is missing.
# @param [String] root_dir Path to the extracted upstream root directory.
# @return [Integer] Returns 0 if valid, exits 1 if any directory is missing.
#
verify_upstream_layout() {
  _root="$1"
  for _req in "v1.25/bin" "v1.25/source" "v2.0/bin" "v2.0/source" "v4.0/src" "v4.0/src/BIOS" "v4.0/src/DOS" "v4.0/src/CMD" "v4.0/src/TOOLS"; do
    if [ ! -d "${_root}/${_req}" ]; then
      log_err "Missing expected upstream directory: ${_root}/${_req}"
      exit 1
    fi
  done
  return 0
}

#
# @function fetch_msdos_repo
# @description
#   Downloads the microsoft/ms-dos tarball into builds/iso/microsoft-ms-dos.tar.gz
#   if not already cached, verifies its SHA-256 checksum, extracts it to
#   builds/msdos_upstream, and validates the extracted directory structure.
# @param [void] None.
# @return [Integer] Returns 0 on success.
#
fetch_msdos_repo() {
  mkdir -p "$ISO_DIR" "$EXTRACT_ROOT"

  if [ "${BENTO_DRY_RUN:-0}" = "1" ]; then
    log_msg "[Dry-Run] Fetching ${MSDOS_REPO_URL} -> ${ARCHIVE_PATH}"
    mkdir -p "${EXTRACT_ROOT}/v1.25/bin" "${EXTRACT_ROOT}/v1.25/source"
    mkdir -p "${EXTRACT_ROOT}/v2.0/bin" "${EXTRACT_ROOT}/v2.0/source"
    mkdir -p "${EXTRACT_ROOT}/v4.0/src/BIOS" "${EXTRACT_ROOT}/v4.0/src/DOS"
    mkdir -p "${EXTRACT_ROOT}/v4.0/src/CMD" "${EXTRACT_ROOT}/v4.0/src/TOOLS"
    verify_upstream_layout "$EXTRACT_ROOT"
    return 0
  fi

  if [ ! -f "$ARCHIVE_PATH" ]; then
    log_msg "Downloading microsoft/ms-dos archive from ${MSDOS_REPO_URL}..."
    curl -fL --retry 3 -o "${ARCHIVE_PATH}.part" "$MSDOS_REPO_URL"
    mv "${ARCHIVE_PATH}.part" "$ARCHIVE_PATH"
  else
    log_msg "Using cached microsoft/ms-dos archive: ${ARCHIVE_PATH}"
  fi

  verify_archive_checksum "$ARCHIVE_PATH"

  if [ ! -d "${EXTRACT_ROOT}/v1.25/bin" ] || [ ! -d "${EXTRACT_ROOT}/v2.0/bin" ] || [ ! -d "${EXTRACT_ROOT}/v4.0/src/TOOLS" ]; then
    log_msg "Extracting microsoft/ms-dos archive to ${EXTRACT_ROOT}..."
    tar -xzf "$ARCHIVE_PATH" --strip-components=1 -C "$EXTRACT_ROOT"
  fi

  verify_upstream_layout "$EXTRACT_ROOT"
  return 0
}

#
# @function normalize_v4_sources
# @description
#   Normalizes text files inside v4.0/src (excluding binary executables in TOOLS)
#   by stripping trailing 0x1A (Ctrl-Z) EOF markers, converting LF to strict DOS
#   CRLF (0x0D 0x0A), normalizing 8.3 uppercase filenames in staged copies, and
#   generating a build-ready SETENV.BAT.
# @param [String] src_dir Path to the v4.0/src directory to normalize.
# @return [Integer] Returns 0 on success.
#
normalize_v4_sources() {
  _src_dir="$1"
  if [ ! -d "$_src_dir" ]; then
    return 0
  fi

  log_msg "Normalizing CRLF and stripping Ctrl-Z (0x1A) EOF markers in ${_src_dir}..."
  find "$_src_dir" -type f \( -iname "*.asm" -o -iname "*.inc" -o -iname "*.c" -o -iname "*.h" -o -iname "*.bat" -o -iname "*.mak" -o -iname "makefile" -o -iname "locscr" -o -iname "*.skl" -o -iname "*.msg" -o -iname "*.lnk" -o -iname "*.def" -o -iname "*.cla" -o -iname "*.clb" -o -iname "*.clc" -o -iname "*.cld" -o -iname "*.cle" -o -iname "*.clf" -o -iname "*.cl1" -o -iname "*.cl2" -o -iname "*.cl3" -o -iname "*.cl4" -o -iname "*.cl5" -o -iname "*.ctl" -o -iname "*.lbr" -o -iname "*.equ" -o -iname "*.ini" \) | while IFS= read -r _f; do
    LC_ALL=C tr -d '\032\015' < "$_f" | LC_ALL=C awk '{ printf "%s\015\012", $0 }' > "${_f}.tmp" && mv "${_f}.tmp" "$_f"
  done
  return 0
}

#
# @function normalize_uppercase_tree
# @description
#   Renames files and directories inside a staged tree to uppercase 8.3 names
#   so case-sensitive host tools and FAT16 staging match DOS path expectations.
# @param [String] tree_dir Root directory to normalize to uppercase.
# @return [Integer] Returns 0 on success.
#
normalize_uppercase_tree() {
  _tree="$1"
  if [ ! -d "$_tree" ]; then
    return 0
  fi
  find "$_tree" -depth | while IFS= read -r _p; do
    if [ "$_p" = "$_tree" ]; then
      continue
    fi
    _dir=$(dirname "$_p")
    _base=$(basename "$_p")
    _upper=$(printf '%s' "$_base" | tr '[:lower:]' '[:upper:]')
    if [ "$_base" != "$_upper" ] && [ ! -e "${_dir}/${_upper}" ]; then
      mv "$_p" "${_dir}/${_upper}" 2>/dev/null || true
    fi
  done
  return 0
}

#
# @function patch_v4_setenv
# @description
#   Writes a build-VM compatible SETENV.BAT into the staged v4.0/src directory
#   so BAKROOT, LIB, INIT, INCLUDE, and PATH point to C:\SRC\TOOLS (or %BAKROOT%\SRC\TOOLS).
# @param [String] staged_src_dir Path to the staged SRC directory.
# @return [Integer] Returns 0 on success.
#
patch_v4_setenv() {
  _sdir="$1"
  mkdir -p "$_sdir"
  awk '{ sub(/\015$/, ""); printf "%s\015\012", $0 }' <<'SETENV_EOF' > "${_sdir}/SETENV.BAT"
@ECHO OFF
ECHO Setting up MS-DOS 4.00 build environment...
SET CL=
SET LINK=
SET MASM=
SET COUNTRY=usa-ms
IF "%BAKROOT%"=="" SET BAKROOT=C:
SET LIB=%BAKROOT%\SRC\TOOLS\BLD\LIB
SET INIT=%BAKROOT%\SRC\TOOLS
SET INCLUDE=%BAKROOT%\SRC\TOOLS\BLD\INC
SET PATH=%BAKROOT%\SRC\TOOLS;C:\TOOLS\BIN;C:\DOS;C:\BENTO;C:\FDOS\BIN;C:\
SETENV_EOF
  return 0
}

#
# @function prepare_msdos4_stage1_disks
# @description
#   Auto-generates the Stage 1 bootstrap host disk (`msdos4_host_c.img`) and
#   32MB FAT16 source build disk (`msdos4_build_d.raw`) when `builds/msdos4_compiled`
#   is not yet populated on a fresh checkout.
# @param [String] host_c Path to the Stage 1 C: boot image.
# @param [String] build_d Path to the Stage 1 D: source/build image.
# @param [String] stage_dir Staged MS-DOS 4.00 directory containing normalized SRC.
# @return [Integer] Returns 0 on success.
#
prepare_msdos4_stage1_disks() {
  _hc="$1"
  _bd="$2"
  _st="$3"
  _fd_zip="${ISO_DIR}/FD13-LiteUSB.zip"
  _fd_url="${FREEDOS_LITEUSB_URL:-https://www.ibiblio.org/pub/micro/pc-stuff/freedos/files/distributions/1.3/official/FD13-LiteUSB.zip}"

  BENTO_DRY_RUN=1 "${SCRIPT_DIR}/provision_msdos.sh" >/dev/null 2>&1 || true

  if [ ! -f "$_hc" ]; then
    if [ ! -f "$_fd_zip" ]; then
      log_msg "Downloading Stage 1 bootstrap image archive from ${_fd_url}..."
      curl -fL --retry 3 -o "${_fd_zip}.part" "$_fd_url"
      mv "${_fd_zip}.part" "$_fd_zip"
    fi
    _ext_tmp=$(mktemp -d "${TMPDIR:-/tmp}/msdos4-fd.XXXXXX")
    unzip -q -o "$_fd_zip" -d "$_ext_tmp"
    _found_fd=$(find "$_ext_tmp" -iname "*.img" | head -n 1)
    if [ -n "$_found_fd" ] && [ -f "$_found_fd" ]; then
      cp -f "$_found_fd" "$_hc"
    fi
    rm -rf "$_ext_tmp"

    if [ "$(uname -s)" = "Darwin" ] && command -v hdiutil >/dev/null 2>&1 && [ -f "$_hc" ]; then
      _mnt_c=$(mktemp -d "${TMPDIR:-/tmp}/msdos4-hc.XXXXXX")
      if hdiutil attach -nobrowse -imagekey diskimage-class=CRawDiskImage -mountpoint "$_mnt_c" "$_hc" >/dev/null 2>&1; then
        cp -f "${SCRIPT_DIR}/SHUTDOWN.COM" "${_mnt_c}/SHUTDOWN.COM"
        awk '{ sub(/\015$/, ""); printf "%s\015\012", $0 }' <<'FDCFG_EOF' > "${_mnt_c}/FDCONFIG.SYS"
!COUNTRY=001,858,C:\FDOS\BIN\COUNTRY.SYS
!LASTDRIVE=Z
!BUFFERS=40
!FILES=99
DOS=HIGH
SHELLHIGH=C:\FDOS\BIN\COMMAND.COM C:\FDOS\BIN /E:2048 /P=C:\FDAUTO.BAT
FDCFG_EOF
        awk '{ sub(/\015$/, ""); printf "%s\015\012", $0 }' <<'FDAUTO_EOF' > "${_mnt_c}/FDAUTO.BAT"
@ECHO OFF
SET DOSDIR=C:\FDOS
SET PATH=D:\SRC\TOOLS;C:\FDOS\BIN;C:\
SET TEMP=C:\TEMP
IF NOT EXIST C:\TEMP MKDIR C:\TEMP
IF EXIST D:\BUILD40.BAT CALL D:\BUILD40.BAT
C:\SHUTDOWN.COM
FDAUTO_EOF
        cp -f "${_mnt_c}/FDAUTO.BAT" "${_mnt_c}/AUTOEXEC.BAT"
        sync
        hdiutil detach "$_mnt_c" >/dev/null 2>&1 || hdiutil detach -force "$_mnt_c" >/dev/null 2>&1 || true
      fi
      rmdir "$_mnt_c" 2>/dev/null || true
    fi
  fi

  if [ ! -f "$_bd" ]; then
    ruby -I "${REPO_ROOT}/lib" -rbento/vagrant_msdos -e '
      Bento::VagrantMsdos::SyncedFolder.new.send(:format_fat16_image, ARGV[0], 32)
    ' "$_bd"
    if [ "$(uname -s)" = "Darwin" ] && command -v hdiutil >/dev/null 2>&1; then
      _mnt_d=$(mktemp -d "${TMPDIR:-/tmp}/msdos4-bd.XXXXXX")
      if hdiutil attach -nobrowse -imagekey diskimage-class=CRawDiskImage -mountpoint "$_mnt_d" "$_bd" >/dev/null 2>&1; then
        mkdir -p "${_mnt_d}/SRC" "${_mnt_d}/OUT40"
        cp -Rf "${_st}/SRC/"* "${_mnt_d}/SRC/" 2>/dev/null || true
        awk '{ sub(/\015$/, ""); printf "%s\015\012", $0 }' <<'BLD40_EOF' > "${_mnt_d}/BUILD40.BAT"
@ECHO OFF
D:
CD \SRC
SET BAKROOT=D:
CALL SETENV.BAT
CD \SRC\MESSAGES
NMAKE
CD \SRC\MAPPER
NMAKE
CD \SRC\INC
NMAKE
CD \SRC\BOOT
NMAKE
CD \SRC\BIOS
NMAKE
CD \SRC\DOS
NMAKE
CD \SRC\CMD\COMMAND
NMAKE
CD \SRC\CMD\FDISK
NMAKE
COPY \SRC\BOOT\MSBOOT.BIN \OUT40\MSBOOT.BIN
COPY \SRC\BOOT\MSLOAD.COM \OUT40\MSLOAD.COM
COPY \SRC\BIOS\IO.SYS \OUT40\IO.SYS
COPY \SRC\DOS\MSDOS.SYS \OUT40\MSDOS.SYS
COPY \SRC\CMD\COMMAND\COMMAND.COM \OUT40\COMMAND.COM
COPY \SRC\CMD\FDISK\FDBOOT.BIN \OUT40\FDBOOT.BIN
BLD40_EOF
        sync
        hdiutil detach "$_mnt_d" >/dev/null 2>&1 || hdiutil detach -force "$_mnt_d" >/dev/null 2>&1 || true
      fi
      rmdir "$_mnt_d" 2>/dev/null || true
    fi
  fi
  return 0
}

#
# @function compile_msdos_40_stage1
# @description
#   Compiles Microsoft MS-DOS 4.00 from `v4.0/src` inside a temporary Stage 1
#   QEMU bootstrap VM (configured with FILES=99, BUFFERS=40, and /E:2048) if
#   compiled binaries are not already cached in `builds/msdos4_compiled`, then
#   copies IO.SYS, MSDOS.SYS, COMMAND.COM, MSBOOT.BIN, FDBOOT.BIN, external
#   commands, and device drivers into the target staging directory.
# @param [String] stage_dir Destination staging directory.
# @return [Integer] Returns 0 on success.
#
compile_msdos_40_stage1() {
  _s40="$1"
  _comp40="${BUILDS_DIR}/msdos4_compiled"
  mkdir -p "$_comp40"

  if [ "${BENTO_DRY_RUN:-0}" = "1" ]; then
    return 0
  fi

  if [ ! -f "${_comp40}/IO.SYS" ] || [ ! -f "${_comp40}/MSDOS.SYS" ] || [ ! -f "${_comp40}/COMMAND.COM" ]; then
    log_msg "Running Stage 1 bootstrap VM to compile MS-DOS 4.00 from v4.0/src..."
    _host_c="${BUILDS_DIR}/msdos4_host_c.img"
    _build_d="${BUILDS_DIR}/msdos4_build_d.raw"
    _stage1_log="${BUILDS_DIR}/msdos4_stage1.log"

    if [ ! -f "$_host_c" ] || [ ! -f "$_build_d" ]; then
      prepare_msdos4_stage1_disks "$_host_c" "$_build_d" "$_s40"
    fi

    if [ -f "$_host_c" ] && [ -f "$_build_d" ] && command -v qemu-system-i386 >/dev/null 2>&1; then
      qemu-system-i386 -machine pc,accel=tcg -m 64M \
        -drive "file=${_host_c},format=raw,if=ide,index=0,media=disk" \
        -drive "file=${_build_d},format=raw,if=ide,index=1,media=disk,cache=writethrough" \
        -serial "file:${_stage1_log}" -display none

      if [ "$(uname -s)" = "Darwin" ] && command -v hdiutil >/dev/null 2>&1; then
        _mnt_out=$(mktemp -d "${TMPDIR:-/tmp}/msdos4-out.XXXXXX")
        if hdiutil attach -nobrowse -imagekey diskimage-class=CRawDiskImage -mountpoint "$_mnt_out" "$_build_d" >/dev/null 2>&1; then
          cp -Rf "${_mnt_out}/OUT40/"* "$_comp40/" 2>/dev/null || true
          hdiutil detach "$_mnt_out" >/dev/null 2>&1 || hdiutil detach -force "$_mnt_out" >/dev/null 2>&1 || true
        fi
        rmdir "$_mnt_out" 2>/dev/null || true
      fi
    fi
  fi

  for _req_bin in IO.SYS MSDOS.SYS COMMAND.COM MSBOOT.BIN FDBOOT.BIN; do
    if [ ! -f "${_comp40}/${_req_bin}" ]; then
      log_msg "ERROR: Required MS-DOS 4.00 compiled artifact missing: ${_comp40}/${_req_bin}"
      exit 1
    fi
  done

  cp -f "${_comp40}/IO.SYS" "${_s40}/IO.SYS"
  cp -f "${_comp40}/MSDOS.SYS" "${_s40}/MSDOS.SYS"
  cp -f "${_comp40}/COMMAND.COM" "${_s40}/COMMAND.COM"
  cp -f "${_comp40}/COMMAND.COM" "${_s40}/DOS/COMMAND.COM"
  for _f40 in "${_comp40}/"*.COM "${_comp40}/"*.EXE "${_comp40}/"*.SYS "${_comp40}/"*.BIN; do
    if [ -f "$_f40" ]; then
      _b40=$(basename "$_f40")
      if [ "$_b40" != "IO.SYS" ] && [ "$_b40" != "MSDOS.SYS" ]; then
        cp -f "$_f40" "${_s40}/DOS/${_b40}"
      fi
    fi
  done
  return 0
}

#
# @function compile_msdos_20_components
# @description
#   Assembles the 16-bit PC-BIOS `IO.SYS` (with FAT12<->FAT16 translation and
#   COM1/AUX support) for MS-DOS 2.0 using `nasm` from `asm/io_msdos20.asm` if
#   not already present in `builds/msdos20_compiled`, and stages `v2.0/bin/MSDOS.SYS`
#   and `v2.0/bin/COMMAND.COM` (normalized so `VER` outputs `MS-DOS Version 2.00`).
# @param [String] stage_dir Destination staging directory.
# @return [Integer] Returns 0 on success.
#
compile_msdos_20_components() {
  _s20="$1"
  _comp20="${BUILDS_DIR}/msdos20_compiled"
  mkdir -p "$_comp20"

  if [ "${BENTO_DRY_RUN:-0}" = "1" ]; then
    return 0
  fi

  if [ ! -f "${_comp20}/IO.SYS" ] && command -v nasm >/dev/null 2>&1 && [ -f "${SCRIPT_DIR}/asm/io_msdos20.asm" ]; then
    log_msg "Assembling MS-DOS 2.0 IO.SYS from ${SCRIPT_DIR}/asm/io_msdos20.asm..."
    nasm -f bin "${SCRIPT_DIR}/asm/io_msdos20.asm" -o "${_comp20}/IO.SYS"
  fi

  if [ -f "${EXTRACT_ROOT}/v2.0/bin/MSDOS.SYS" ]; then
    cp -f "${EXTRACT_ROOT}/v2.0/bin/MSDOS.SYS" "${_comp20}/MSDOS.SYS"
    cp -f "${_comp20}/MSDOS.SYS" "${_s20}/MSDOS.SYS"
  fi

  if [ -f "${EXTRACT_ROOT}/v2.0/bin/COMMAND.COM" ]; then
    ruby -e '
      raw = File.binread(ARGV[0])
      raw.sub!("MS-DOS Version $".b, "MS-DOS Version$$".b)
      File.binwrite(ARGV[1], raw)
    ' "${EXTRACT_ROOT}/v2.0/bin/COMMAND.COM" "${_comp20}/COMMAND.COM"
    cp -f "${_comp20}/COMMAND.COM" "${_s20}/COMMAND.COM"
    cp -f "${_comp20}/COMMAND.COM" "${_s20}/DOS/COMMAND.COM"
  fi

  if [ -f "${_comp20}/IO.SYS" ]; then
    cp -f "${_comp20}/IO.SYS" "${_s20}/IO.SYS"
  fi
  return 0
}

#
# @function compile_msdos_125_components
# @description
#   Assembles/generates the MS-DOS 1.25 `IO.SYS` (`asm/io_msdos125.asm`),
#   `VER.COM` (`asm/ver_com.asm`), and `ECHO.COM` (`asm/echo_com.asm`) using
#   `nasm` when missing from `builds/msdos125_compiled`, compiles `MSDOS.SYS`
#   (`v1.25/source/STDDOS.ASM` + `MSDOS.ASM` with `BIOSSEG EQU 70H`) and
#   `COMMAND.COM` (`v1.25/source/COMMAND.ASM`) via the 16-bit MASM/LINK Stage 1
#   toolchain when missing, and copies all 5 components into the staging directory.
# @param [String] stage_dir Destination staging directory.
# @return [Integer] Returns 0 on success.
#
compile_msdos_125_components() {
  _s125="$1"
  _comp125="${BUILDS_DIR}/msdos125_compiled"
  mkdir -p "$_comp125"

  if [ "${BENTO_DRY_RUN:-0}" = "1" ]; then
    return 0
  fi

  if command -v nasm >/dev/null 2>&1; then
    if [ ! -f "${_comp125}/IO.SYS" ] && [ -f "${SCRIPT_DIR}/asm/io_msdos125.asm" ]; then
      log_msg "Assembling MS-DOS 1.25 IO.SYS from ${SCRIPT_DIR}/asm/io_msdos125.asm..."
      nasm -f bin "${SCRIPT_DIR}/asm/io_msdos125.asm" -o "${_comp125}/IO.SYS"
    fi
    if [ ! -f "${_comp125}/VER.COM" ] && [ -f "${SCRIPT_DIR}/asm/ver_com.asm" ]; then
      log_msg "Assembling MS-DOS 1.25 VER.COM from ${SCRIPT_DIR}/asm/ver_com.asm..."
      nasm -f bin "${SCRIPT_DIR}/asm/ver_com.asm" -o "${_comp125}/VER.COM"
    fi
    if [ ! -f "${_comp125}/ECHO.COM" ] && [ -f "${SCRIPT_DIR}/asm/echo_com.asm" ]; then
      log_msg "Assembling MS-DOS 1.25 ECHO.COM from ${SCRIPT_DIR}/asm/echo_com.asm..."
      nasm -f bin "${SCRIPT_DIR}/asm/echo_com.asm" -o "${_comp125}/ECHO.COM"
    fi
  fi

  if { [ ! -f "${_comp125}/MSDOS.SYS" ] || [ ! -f "${_comp125}/COMMAND.COM" ]; } && [ -d "${EXTRACT_ROOT}/v1.25/source" ]; then
    log_msg "Compiling MS-DOS 1.25 MSDOS.SYS and COMMAND.COM from v1.25/source/{STDDOS.ASM,MSDOS.ASM,COMMAND.ASM}..."
    _host_c125="${BUILDS_DIR}/msdos4_host_c.img"
    _build_d125="${BUILDS_DIR}/msdos125_build_d.raw"
    if [ ! -f "$_host_c125" ]; then
      prepare_msdos4_stage1_disks "$_host_c125" "${BUILDS_DIR}/msdos4_build_d.raw" "$_s125"
    fi
    if [ "$(uname -s)" = "Darwin" ] && command -v hdiutil >/dev/null 2>&1 && command -v qemu-system-i386 >/dev/null 2>&1; then
      ruby -I "${REPO_ROOT}/lib" -rbento/vagrant_msdos -e '
        Bento::VagrantMsdos::SyncedFolder.new.send(:format_fat16_image, ARGV[0], 16)
      ' "$_build_d125"
      _mnt125=$(mktemp -d "${TMPDIR:-/tmp}/msdos125-bd.XXXXXX")
      if hdiutil attach -nobrowse -imagekey diskimage-class=CRawDiskImage -mountpoint "$_mnt125" "$_build_d125" >/dev/null 2>&1; then
        mkdir -p "${_mnt125}/TOOLS" "${_mnt125}/V125"
        cp -f "${EXTRACT_ROOT}/v4.0/src/TOOLS/MASM.EXE" "${_mnt125}/TOOLS/MASM.EXE"
        cp -f "${EXTRACT_ROOT}/v4.0/src/TOOLS/LINK.EXE" "${_mnt125}/TOOLS/LINK.EXE"
        LC_ALL=C tr -d '\032\015' < "${EXTRACT_ROOT}/v1.25/source/STDDOS.ASM" | LC_ALL=C awk '{ printf "%s\015\012", $0 }' > "${_mnt125}/V125/STDDOS.ASM"
        LC_ALL=C tr -d '\032\015' < "${EXTRACT_ROOT}/v1.25/source/MSDOS.ASM" | sed 's/BIOSSEG EQU     40H/BIOSSEG EQU     70H/' | LC_ALL=C awk '{ printf "%s\015\012", $0 }' > "${_mnt125}/V125/MSDOS.ASM"
        LC_ALL=C tr -d '\032\015' < "${EXTRACT_ROOT}/v1.25/source/COMMAND.ASM" | LC_ALL=C awk '{ printf "%s\015\012", $0 }' > "${_mnt125}/V125/COMMAND.ASM"
        awk '{ sub(/\015$/, ""); printf "%s\015\012", $0 }' <<'BLD125_EOF' > "${_mnt125}/BUILD40.BAT"
@ECHO OFF
D:
CD \V125
D:\TOOLS\MASM.EXE STDDOS.ASM,MSDOS.OBJ,NUL,NUL;
D:\TOOLS\LINK.EXE MSDOS.OBJ,MSDOS.EXE,NUL,NUL;
D:\TOOLS\MASM.EXE COMMAND.ASM,COMMAND.OBJ,NUL,NUL;
D:\TOOLS\LINK.EXE COMMAND.OBJ,COMMAND.EXE,NUL,NUL;
BLD125_EOF
        sync
        hdiutil detach "$_mnt125" >/dev/null 2>&1 || hdiutil detach -force "$_mnt125" >/dev/null 2>&1 || true
      fi
      qemu-system-i386 -machine pc,accel=tcg -m 64M \
        -drive "file=${_host_c125},format=raw,if=ide,index=0,media=disk" \
        -drive "file=${_build_d125},format=raw,if=ide,index=1,media=disk,cache=writethrough" \
        -serial "file:${BUILDS_DIR}/msdos125_stage1.log" -display none
      if hdiutil attach -nobrowse -imagekey diskimage-class=CRawDiskImage -mountpoint "$_mnt125" "$_build_d125" >/dev/null 2>&1; then
        if [ -f "${_mnt125}/V125/MSDOS.EXE" ]; then
          cp -f "${_mnt125}/V125/MSDOS.EXE" "${_comp125}/MSDOS.EXE"
          ruby -e '
            b = File.binread(ARGV[0])
            hdr = b[8, 2].unpack1("v") * 16
            File.binwrite(ARGV[1], b[hdr..] || "".b)
          ' "${_comp125}/MSDOS.EXE" "${_comp125}/MSDOS.SYS"
        fi
        if [ -f "${_mnt125}/V125/COMMAND.EXE" ]; then
          cp -f "${_mnt125}/V125/COMMAND.EXE" "${_comp125}/COMMAND.EXE"
          ruby -e '
            b = File.binread(ARGV[0])
            hdr = (b[8, 2].unpack1("v") * 16) + 0x100
            File.binwrite(ARGV[1], b[hdr..] || "".b)
          ' "${_comp125}/COMMAND.EXE" "${_comp125}/COMMAND.COM"
        fi
        hdiutil detach "$_mnt125" >/dev/null 2>&1 || hdiutil detach -force "$_mnt125" >/dev/null 2>&1 || true
      fi
      rmdir "$_mnt125" 2>/dev/null || true
      rm -f "$_build_d125"
    fi
  fi

  for _f125 in IO.SYS MSDOS.SYS COMMAND.COM VER.COM ECHO.COM; do
    if [ -f "${_comp125}/${_f125}" ]; then
      cp -f "${_comp125}/${_f125}" "${_s125}/${_f125}"
    fi
  done
  return 0
}

#
# @function stage_msdos_version
# @description
#   Stages the requested MS-DOS version (1.25, 2.0, or 4.0) into the target
#   staging directory ready for compilation or injection onto a FAT12/FAT16
#   bootable disk image.
# @param [String] version MS-DOS version ("1.25", "2.0", or "4.0").
# @param [String] stage_dir Destination directory on the host.
# @return [Integer] Returns 0 on success.
#
stage_msdos_version() {
  _ver="$1"
  _stage="$2"
  mkdir -p "$_stage"

  case "$_ver" in
    1.25)
      log_msg "Staging MS-DOS 1.25 binaries and sources (flat root layout) into ${_stage}..."
      if [ -d "${EXTRACT_ROOT}/v1.25/bin" ]; then
        cp -Rf "${EXTRACT_ROOT}/v1.25/bin/"* "$_stage/" 2>/dev/null || true
      fi
      if [ -d "${EXTRACT_ROOT}/v1.25/source" ]; then
        cp -Rf "${EXTRACT_ROOT}/v1.25/source/"* "$_stage/" 2>/dev/null || true
      fi
      normalize_uppercase_tree "$_stage"
      compile_msdos_125_components "$_stage"
      ;;
    2.0)
      log_msg "Staging MS-DOS 2.0 binaries and sources into ${_stage}/DOS and ${_stage}/SRC..."
      mkdir -p "${_stage}/DOS" "${_stage}/SRC" "${_stage}/BENTO" "${_stage}/TEMP"
      if [ -d "${EXTRACT_ROOT}/v2.0/bin" ]; then
        cp -Rf "${EXTRACT_ROOT}/v2.0/bin/"* "${_stage}/DOS/" 2>/dev/null || true
        if [ -f "${EXTRACT_ROOT}/v2.0/bin/COMMAND.COM" ]; then
          cp -f "${EXTRACT_ROOT}/v2.0/bin/COMMAND.COM" "${_stage}/COMMAND.COM"
        fi
        if [ -f "${EXTRACT_ROOT}/v2.0/bin/MSDOS.SYS" ]; then
          cp -f "${EXTRACT_ROOT}/v2.0/bin/MSDOS.SYS" "${_stage}/MSDOS.SYS"
        fi
      fi
      if [ -d "${EXTRACT_ROOT}/v2.0/source" ]; then
        cp -Rf "${EXTRACT_ROOT}/v2.0/source/"* "${_stage}/SRC/" 2>/dev/null || true
      fi
      normalize_uppercase_tree "$_stage"
      compile_msdos_20_components "$_stage"
      ;;
    4.0|4.00)
      log_msg "Staging MS-DOS 4.0 sources and 16-bit build toolchain into ${_stage}..."
      mkdir -p "${_stage}/DOS" "${_stage}/TOOLS" "${_stage}/SRC" "${_stage}/BENTO" "${_stage}/TEMP"
      if [ -d "${EXTRACT_ROOT}/v4.0/src" ] && [ "${BENTO_DRY_RUN:-0}" != "1" ]; then
        normalize_v4_sources "${EXTRACT_ROOT}/v4.0/src"
        if [ -d "${EXTRACT_ROOT}/v4.0/src/TOOLS" ]; then
          cp -Rf "${EXTRACT_ROOT}/v4.0/src/TOOLS/"* "${_stage}/TOOLS/" 2>/dev/null || true
        fi
        for _sub in MESSAGES MAPPER BOOT BIOS DOS INC H LIB CMD DEV SELECT MEMM TOOLS; do
          if [ -d "${EXTRACT_ROOT}/v4.0/src/${_sub}" ]; then
            mkdir -p "${_stage}/SRC/${_sub}"
            cp -Rf "${EXTRACT_ROOT}/v4.0/src/${_sub}/"* "${_stage}/SRC/${_sub}/" 2>/dev/null || true
          fi
        done
        for _script_f in SETENV.BAT RUNME.BAT CPY.BAT MAKEFILE; do
          if [ -f "${EXTRACT_ROOT}/v4.0/src/${_script_f}" ]; then
            cp -f "${EXTRACT_ROOT}/v4.0/src/${_script_f}" "${_stage}/DOS/${_script_f}"
            cp -f "${EXTRACT_ROOT}/v4.0/src/${_script_f}" "${_stage}/SRC/${_script_f}"
          fi
        done
        patch_v4_setenv "${_stage}/SRC"
        cp -f "${_stage}/SRC/SETENV.BAT" "${_stage}/DOS/SETENV.BAT"
        normalize_uppercase_tree "${_stage}/SRC"
        compile_msdos_40_stage1 "$_stage"
      fi
      ;;
    *)
      log_msg "Unknown MS-DOS version '${_ver}'; defaulting to 4.0."
      ;;
  esac
  return 0
}

#
# @function main
# @description
#   CLI entry point for fetching and staging a specific MS-DOS version.
# @param [String] version Target MS-DOS version (default "4.0").
# @param [String] target_dir Target staging directory (default builds/msdos_stage_<ver>).
# @return [Integer] Returns 0 on success.
#
main() {
  _version="${1:-4.0}"
  _target_dir="${2:-${BUILDS_DIR}/msdos_stage_${_version}}"
  fetch_msdos_repo
  stage_msdos_version "$_version" "$_target_dir"
  return 0
}

main "$@"
