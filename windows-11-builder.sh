#!/usr/bin/env bash
# ==============================================================================
# Windows 11 Automated Builder, Runner & Minimal Box Creation Tool for Bento
#
# Usage:
#   ./windows-11-builder.sh [COMMAND] [OPTIONS]
#
# Commands:
#   build          Build the Windows 11 box using Packer + auto-box compression (default)
#   box            Compress, sparsify, and package VM disk into minimal .box
#   run            Run the built VM / box directly with KVM, serial & networking
#   serial         Connect via serial to debug the running VM in real time
#   status         Show status of ISOs, build files, and running processes
#   clean          Kill running VMs/Packer instances and clean temporary locks
#
# Options:
#   --provider     qemu | virtualbox (default: auto-detected based on KVM)
#   --arch         x86_64 | aarch64  (default: auto-detected host arch)
#   --iso          Path to Windows 11 ISO (default: auto-detected)
#   --headless     true | false (default: true)
#   --debug        Enable Packer and hypervisor debug output
#   --serial       Stream serial output to terminal during build
#   --watch        Watch live serial log streaming (for serial command)
#   --tail [N]     Display last N lines of serial log (default: 50)
#   --send <CMD>   Send command string to serial console
#   --memory <MB>  Memory for runner in MB (default: 6144)
#   --cpus <N>     CPUs for runner (default: 4)
#   --vnc <PORT>   VNC display port for runner (default: none / headless)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Load .env if present
if [ -f "${SCRIPT_DIR}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${SCRIPT_DIR}/.env"
  set +a
fi

# ANSI Colors
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_CYAN="\033[36m"
C_MAGENTA="\033[35m"

log_info()    { echo -e "${C_CYAN}${C_BOLD}==> [INFO]${C_RESET} $*"; }
log_success() { echo -e "${C_GREEN}${C_BOLD}==> [SUCCESS]${C_RESET} $*"; }
log_warn()    { echo -e "${C_YELLOW}${C_BOLD}==> [WARN]${C_RESET} $*"; }
log_error()   { echo -e "${C_RED}${C_BOLD}==> [ERROR]${C_RESET} $*" >&2; }
get_file_size() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1" 2>/dev/null || wc -c < "$1" | tr -d ' '; }

# Default Parameters
COMMAND="build"
ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64|amd64) ARCH="x86_64" ;;
  aarch64|arm64) ARCH="aarch64" ;;
  *) log_error "Unsupported host architecture: ${ARCH}"; exit 1 ;;
esac

# Auto-detect hypervisor provider
if [ -e "/dev/kvm" ] && [ -w "/dev/kvm" ]; then
  PROVIDER="qemu"
elif command -v VBoxManage >/dev/null 2>&1; then
  PROVIDER="virtualbox"
elif command -v qemu-system-${ARCH} >/dev/null 2>&1; then
  PROVIDER="qemu"
else
  PROVIDER="qemu"
fi

HEADLESS="true"
DEBUG_MODE="false"
STREAM_SERIAL="false"
SERIAL_WATCH="false"
SERIAL_TAIL_LINES=""
SERIAL_SEND_CMD=""
VM_MEM="6144"
VM_CPUS="4"
VM_VNC=""
CUSTOM_ISO=""
TMP_DIR="${TMPDIR:-/tmp}"
SERIAL_SOCK="${TMP_DIR}/windows-11-serial.sock"
SERIAL_CLIENT_SOCK="${TMP_DIR}/windows-11-serial-client.sock"
SERIAL_LOG="${SCRIPT_DIR}/serial.log"
PROXY_SCRIPT="${SCRIPT_DIR}/serial_proxy.py"

# Parse CLI arguments
while [ $# -gt 0 ]; do
  case "$1" in
    build|box|run|serial|status|clean)
      COMMAND="$1"
      shift
      ;;
    --provider)
      PROVIDER="$2"
      shift 2
      ;;
    --arch)
      ARCH="$2"
      shift 2
      ;;
    --iso)
      CUSTOM_ISO="$2"
      shift 2
      ;;
    --headless)
      HEADLESS="$2"
      shift 2
      ;;
    --debug)
      DEBUG_MODE="true"
      shift
      ;;
    --serial)
      STREAM_SERIAL="true"
      shift
      ;;
    --watch)
      SERIAL_WATCH="true"
      shift
      ;;
    --tail)
      if [ $# -ge 2 ] && [[ "$2" =~ ^[0-9]+$ ]]; then
        SERIAL_TAIL_LINES="$2"
        shift 2
      else
        SERIAL_TAIL_LINES="50"
        shift
      fi
      ;;
    --send)
      SERIAL_SEND_CMD="$2"
      shift 2
      ;;
    --memory)
      VM_MEM="$2"
      shift 2
      ;;
    --cpus)
      VM_CPUS="$2"
      shift 2
      ;;
    --vnc)
      VM_VNC="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '/^# Usage:/,/^# ====/p' "${BASH_SOURCE[0]}" | head -n -1 | sed 's/^# //g' | sed 's/^#//g'
      exit 0
      ;;
    *)
      log_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# Resolve ISO Path
find_iso() {
  if [ -n "${CUSTOM_ISO}" ] && [ -f "${CUSTOM_ISO}" ]; then
    echo "${CUSTOM_ISO}"
    return 0
  fi
  if [ -n "${WIN11_TARGET_ISO:-}" ] && [ -f "${WIN11_TARGET_ISO}" ]; then
    echo "${WIN11_TARGET_ISO}"
    return 0
  fi
  if [ -n "${WIN11_ISO_PATH:-}" ] && [ -f "${WIN11_ISO_PATH}" ]; then
    echo "${WIN11_ISO_PATH}"
    return 0
  fi
  local search_dirs=()
  if [ -n "${ISO_DIR:-}" ] && [ -d "${ISO_DIR}" ]; then
    search_dirs+=("${ISO_DIR}")
  fi
  search_dirs+=("${SCRIPT_DIR}/builds/iso")
  for sdir in "${search_dirs[@]}"; do
    local local_iso
    local_iso=$(find "${sdir}" -maxdepth 1 -name "windows-11-${ARCH}*.iso" 2>/dev/null | head -n 1)
    if [ -n "${local_iso}" ] && [ -f "${local_iso}" ]; then
      echo "${local_iso}"
      return 0
    fi
    local_iso=$(find "${sdir}" -maxdepth 1 \( -name "*win*11*${ARCH}*.iso" -o -name "*Win*11*${ARCH}*.iso" -o -name "*Win*11*Arm64*.iso" -o -name "*Win11*${ARCH}*.iso" -o -name "*Win11*Arm64*.iso" \) 2>/dev/null | head -n 1)
    if [ -n "${local_iso}" ] && [ -f "${local_iso}" ]; then
      echo "${local_iso}"
      return 0
    fi
    local_iso=$(find "${sdir}" -maxdepth 1 -name "*windows-11*.iso" 2>/dev/null | head -n 1)
    if [ -n "${local_iso}" ] && [ -f "${local_iso}" ]; then
      echo "${local_iso}"
      return 0
    fi
  done
  echo ""
}

# Clean stale locks and background processes
cmd_clean() {
  log_info "Cleaning up stale locks, temporary build files, and processes..."
  rm -f "${SCRIPT_DIR}/builds/iso/"*.iso.lock 2>/dev/null || true
  rm -f "${SERIAL_SOCK}" "${SERIAL_CLIENT_SOCK}" 2>/dev/null || true

  # Kill background serial proxy
  pkill -f "serial_proxy.py" 2>/dev/null || true

  # Kill running packer instances for windows-11
  pkill -f "packer build.*windows-11" 2>/dev/null || true

  # Kill running QEMU instances for windows-11
  pkill -f "qemu-system-.*windows-11" 2>/dev/null || true

  # Clean VirtualBox VM if present
  if command -v VBoxManage >/dev/null 2>&1; then
    for vm in $(VBoxManage list runningvms 2>/dev/null | grep -i "windows-11" | cut -d'"' -f2); do
      log_warn "Stopping running VirtualBox Windows 11 VM ($vm)..."
      VBoxManage controlvm "$vm" poweroff 2>/dev/null || true
      sleep 1
    done
    for vm in $(VBoxManage list vms 2>/dev/null | grep -i "windows-11" | cut -d'"' -f2); do
      log_info "Unregistering VirtualBox Windows 11 VM ($vm)..."
      VBoxManage unregistervm "$vm" --delete 2>/dev/null || true
    done
  fi
  log_success "Cleanup complete."
}

# Start the serial multiplexer daemon
start_serial_proxy() {
  log_info "Starting serial console multiplexer daemon..."
  pkill -f "serial_proxy.py" 2>/dev/null || true
  rm -f "${SERIAL_CLIENT_SOCK}"

  export SERIAL_SOCK="${SERIAL_SOCK}"
  export SERIAL_CLIENT_SOCK="${SERIAL_CLIENT_SOCK}"
  export SERIAL_LOG="${SERIAL_LOG}"

  python3 "${PROXY_SCRIPT}" >/dev/null 2>&1 &
  PROXY_PID=$!
  sleep 0.5
  if kill -0 "${PROXY_PID}" 2>/dev/null; then
    log_success "Serial multiplexer running (PID: ${PROXY_PID})"
    log_info "Serial logging active at: ${SERIAL_LOG}"
  else
    log_warn "Serial multiplexer could not start. Direct socket mode will be used."
  fi
}

# Connect via serial to debug
cmd_serial() {
  # Handle --tail option
  if [ -n "${SERIAL_TAIL_LINES}" ]; then
    if [ -f "${SERIAL_LOG}" ]; then
      log_info "Displaying last ${SERIAL_TAIL_LINES} lines of ${SERIAL_LOG}:"
      tail -n "${SERIAL_TAIL_LINES}" "${SERIAL_LOG}"
    else
      log_warn "No serial log file found at ${SERIAL_LOG}"
    fi
    return 0
  fi

  # Handle --watch option
  if [ "${SERIAL_WATCH}" = "true" ]; then
    if [ -f "${SERIAL_LOG}" ]; then
      log_info "Watching live serial log ${SERIAL_LOG} (Press Ctrl+C to exit):"
      tail -f "${SERIAL_LOG}"
    else
      log_warn "No serial log file found at ${SERIAL_LOG}. Start build or run first."
    fi
    return 0
  fi

  local target_sock="${SERIAL_CLIENT_SOCK}"
  local waited=0
  while [ ! -S "${target_sock}" ] && [ ! -S "${SERIAL_SOCK}" ]; do
    if [ ${waited} -ge 5 ]; then
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done

  if [ -S "${SERIAL_CLIENT_SOCK}" ]; then
    target_sock="${SERIAL_CLIENT_SOCK}"
  elif [ -S "${SERIAL_SOCK}" ]; then
    target_sock="${SERIAL_SOCK}"
  fi

  if [ ! -S "${target_sock}" ]; then
    log_warn "Active serial socket (${SERIAL_SOCK}) is not currently open."
    if [ -f "${SERIAL_LOG}" ] && [ -s "${SERIAL_LOG}" ]; then
      log_info "Recent serial activity from ${SERIAL_LOG}:"
      echo -e "${C_CYAN}----------------------------------------------------------------${C_RESET}"
      tail -n 30 "${SERIAL_LOG}" 2>/dev/null || true
      echo -e "${C_CYAN}----------------------------------------------------------------${C_RESET}"
      log_info "To stream live serial output once the VM starts, use: ./windows-11-builder.sh serial --watch"
      return 0
    else
      log_error "No active socket or serial log found. Run './windows-11-builder.sh build' or 'run' first."
      return 1
    fi
  fi

  # Handle --send option for non-interactive command execution
  if [ -n "${SERIAL_SEND_CMD}" ]; then
    log_info "Sending command to Windows 11 serial console: ${SERIAL_SEND_CMD}"
    SERIAL_TARGET_SOCK="${target_sock}" CMD_TO_SEND="${SERIAL_SEND_CMD}" python3 -c '
import socket, sys, os, time, select

sock_path = os.environ.get("SERIAL_TARGET_SOCK", "/tmp/windows-11-serial-client.sock")
cmd = os.environ.get("CMD_TO_SEND", "") + "
"

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sock_path)
s.setblocking(False)

s.sendall(cmd.encode("utf-8"))

end_time = time.time() + 3.0
output = b""
while time.time() < end_time:
    r, _, _ = select.select([s], [], [], 0.2)
    if s in r:
        data = s.recv(4096)
        if not data:
            break
        output += data

s.close()
sys.stdout.buffer.write(output)
sys.stdout.flush()
'
    return 0
  fi

  # Interactive serial console session
  echo -e "${C_YELLOW}${C_BOLD}================================================================${C_RESET}"
  echo -e "${C_YELLOW}${C_BOLD}  CONNECTED TO WINDOWS 11 SERIAL CONSOLE (COM1)                ${C_RESET}"
  echo -e "${C_YELLOW}  - Live terminal stream connected to VM COM1 serial port       ${C_RESET}"
  echo -e "${C_YELLOW}  - To exit this console session: Press Ctrl+C                  ${C_RESET}"
  echo -e "${C_YELLOW}${C_BOLD}================================================================${C_RESET}"

  SERIAL_TARGET_SOCK="${target_sock}" python3 -c '
import socket, sys, select, os, tty, termios

sock_path = os.environ.get("SERIAL_TARGET_SOCK", "/tmp/windows-11-serial-client.sock")
if not os.path.exists(sock_path):
    sock_path = "/tmp/windows-11-serial.sock"

try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock_path)
except Exception as e:
    print(f"\033[31mError connecting to {sock_path}: {e}\033[0m")
    sys.exit(1)

old_settings = None
is_tty = sys.stdin.isatty()

try:
    if is_tty:
        old_settings = termios.tcgetattr(sys.stdin)
        tty.setraw(sys.stdin.fileno())

    try:
        s.sendall(b"
")
    except Exception:
        pass

    while True:
        watch_list = [s]
        if is_tty:
            watch_list.append(sys.stdin)

        r, _, _ = select.select(watch_list, [], [], 0.5)
        if s in r:
            data = s.recv(4096)
            if not data:
                break
            sys.stdout.buffer.write(data)
            sys.stdout.flush()

        if is_tty and sys.stdin in r:
            user_input = sys.stdin.buffer.read(1)
            if not user_input or user_input == b"\x03":
                break
            s.sendall(user_input)
except KeyboardInterrupt:
    pass
finally:
    if old_settings:
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)
    s.close()
    print("
\033[33m[Serial connection closed]\033[0m")
'
}

# Show status
cmd_status() {
  log_info "Windows 11 Bento Environment Status:"
  echo "  Architecture   : ${ARCH}"
  echo "  Provider       : ${PROVIDER}"
  echo "  Serial Socket  : ${SERIAL_SOCK} (exists: $([ -S "${SERIAL_SOCK}" ] && echo yes || echo no))"
  echo "  Client Socket  : ${SERIAL_CLIENT_SOCK} (exists: $([ -S "${SERIAL_CLIENT_SOCK}" ] && echo yes || echo no))"

  if [ -f "${SERIAL_LOG}" ]; then
    local log_lines
    log_lines=$(wc -l < "${SERIAL_LOG}")
    local log_bytes
    log_bytes=$(wc -c < "${SERIAL_LOG}")
    echo "  Serial Log     : ${SERIAL_LOG} (${log_bytes} bytes, ${log_lines} lines)"
    if [ "${log_lines}" -gt 0 ]; then
      local last_entry
      last_entry=$(tail -n 1 "${SERIAL_LOG}" | tr '
' ' ')
      echo "  Last Log Entry : ${last_entry}"
    fi
  else
    echo "  Serial Log     : Not yet created"
  fi

  local iso_path
  iso_path="$(find_iso)"
  if [ -n "${iso_path}" ]; then
    local iso_sz
    iso_sz=$(du -h "${iso_path}" | cut -f1)
    echo "  ISO Located    : ${iso_path} (${iso_sz})"
  else
    echo "  ISO Located    : None found in builds/iso"
  fi

  echo ""
  echo "Disk Images (builds/build_files/):"
  local found_disks=0
  for d in "${SCRIPT_DIR}/builds/build_files"/*/*windows-11* "${SCRIPT_DIR}/builds/build_files"/*/box*.img; do
    if [ -f "$d" ]; then
      local dsz
      dsz=$(du -h "$d" | cut -f1)
      local dbytes
      dbytes=$(get_file_size "$d")
      echo -e "  - $(basename "$(dirname "$d")")/$(basename "$d") : ${C_CYAN}${dsz}${C_RESET} (${dbytes} bytes)"
      found_disks=1
    fi
  done
  if [ ${found_disks} -eq 0 ]; then
    echo "  (None found)"
  fi

  echo ""
  echo "Running Processes:"
  ps aux | grep -E "packer.*windows-11|qemu-system-.*windows-11|serial_proxy.py" | grep -v grep || echo "  (None)"

  echo ""
  echo "Built Boxes (builds/build_complete/):"
  if ls "${SCRIPT_DIR}/builds/build_complete/"*windows-11*.box 1>/dev/null 2>&1; then
    for b in "${SCRIPT_DIR}/builds/build_complete/"*windows-11*.box; do
      local bsz
      bsz=$(du -h "$b" | cut -f1)
      local bsz_bytes
      bsz_bytes=$(get_file_size "$b")
      echo -e "  - $(basename "$b") : ${C_GREEN}${C_BOLD}${bsz}${C_RESET} (${bsz_bytes} bytes)"
    done
  else
    echo "  (No .box files built yet)"
  fi
}

# Run built box/disk directly with KVM, serial and port forwards
cmd_run() {
  local disk_img=""
  local candidates=(
    "${SCRIPT_DIR}/builds/build_files/packer-windows-11-${ARCH}-qemu/windows-11-amd64"
    "${SCRIPT_DIR}/builds/build_files/packer-windows-11-${ARCH}-qemu/windows-11-${ARCH}"
    "${SCRIPT_DIR}/builds/build_files/packer-windows-11-${ARCH}-qemu/box.img"
    "${SCRIPT_DIR}/builds/build_files/packer-windows-11-${ARCH}-qemu/box_optimized.img"
  )

  for candidate in "${candidates[@]}"; do
    if [ -f "${candidate}" ]; then
      disk_img="${candidate}"
      break
    fi
  done

  # Also check if box exists and extract if necessary
  if [ -z "${disk_img}" ]; then
    local box_file
    box_file=$(find "${SCRIPT_DIR}/builds/build_complete" -name "*windows-11*.box" 2>/dev/null | head -n 1)
    if [ -n "${box_file}" ]; then
      log_info "Extracting box.img from ${box_file}..."
      local extract_dir="${SCRIPT_DIR}/builds/build_files/packer-windows-11-${ARCH}-qemu"
      mkdir -p "${extract_dir}"
      tar -xf "${box_file}" -C "${extract_dir}" box.img 2>/dev/null || true
      if [ -f "${extract_dir}/box.img" ]; then
        disk_img="${extract_dir}/box.img"
      fi
    fi
  fi

  if [ -z "${disk_img}" ]; then
    log_error "No built disk image found. Run './windows-11-builder.sh build' first."
    exit 1
  fi

  # Find UEFI firmware code and vars
  local brew_prefix=""
  if command -v brew >/dev/null 2>&1; then
    brew_prefix="$(brew --prefix 2>/dev/null)"
  fi

  local efi_code=""
  local efi_vars=""
  if [ "${ARCH}" = "x86_64" ]; then
    local efi_candidates=(
      "${QEMU_EDK2_CODE:-}"
      "${QEMU_BIOS:-}"
      "/usr/share/OVMF/OVMF_CODE.fd"
      "/usr/share/OVMF/OVMF_CODE_4M.fd"
      "/usr/share/ovmf/OVMF.fd"
      "/usr/share/edk2/ovmf/OVMF_CODE.fd"
      "/usr/share/edk2-ovmf/x64/OVMF_CODE.fd"
      ${brew_prefix:+"${brew_prefix}/share/qemu/edk2-x86_64-code.fd"}
      "/opt/homebrew/share/qemu/edk2-x86_64-code.fd"
      "/usr/local/share/qemu/edk2-x86_64-code.fd"
      "/opt/local/share/qemu/edk2-x86_64-code.fd"
      "/usr/share/qemu/edk2-x86_64-code.fd"
      "/usr/share/qemu/OVMF.fd"
      "C:/Program Files/qemu/share/edk2-x86_64-code.fd"
      "C:/msys64/mingw64/share/qemu/edk2-x86_64-code.fd"
    )
    for c in "${efi_candidates[@]}"; do
      if [ -n "$c" ] && [ -f "$c" ]; then efi_code="$c"; break; fi
    done
    local var_candidates=(
      "${QEMU_EDK2_VARS:-}"
      "/usr/share/OVMF/OVMF_VARS.fd"
      "/usr/share/OVMF/OVMF_VARS_4M.fd"
      "/usr/share/ovmf/OVMF_VARS.fd"
      "/usr/share/edk2/ovmf/OVMF_VARS.fd"
      "/usr/share/edk2-ovmf/x64/OVMF_VARS.fd"
      ${brew_prefix:+"${brew_prefix}/share/qemu/edk2-i386-vars.fd"}
      "/opt/homebrew/share/qemu/edk2-i386-vars.fd"
      "/usr/local/share/qemu/edk2-i386-vars.fd"
      "/opt/local/share/qemu/edk2-i386-vars.fd"
      "/usr/share/qemu/edk2-i386-vars.fd"
      "C:/Program Files/qemu/share/edk2-i386-vars.fd"
      "C:/msys64/mingw64/share/qemu/edk2-i386-vars.fd"
    )
    for v in "${var_candidates[@]}"; do
      if [ -n "$v" ] && [ -f "$v" ]; then efi_vars="$v"; break; fi
    done
  else
    local efi_candidates=(
      "${QEMU_EDK2_CODE:-}"
      "${QEMU_BIOS:-}"
      ${brew_prefix:+"${brew_prefix}/share/qemu/edk2-aarch64-code.fd"}
      "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
      "/usr/share/AAVMF/AAVMF_CODE.fd"
      "/usr/share/AAVMF/AAVMF32_CODE.fd"
      "/usr/share/qemu/edk2-aarch64-code.fd"
      "/usr/share/edk2/aarch64/QEMU_EFI-pflash.raw"
      "/usr/share/edk2/aarch64/QEMU_EFI.fd"
      "/usr/share/edk2-armvirt/aarch64/QEMU_EFI.fd"
      "/usr/local/share/qemu/edk2-aarch64-code.fd"
      "/opt/local/share/qemu/edk2-aarch64-code.fd"
      "C:/Program Files/qemu/share/edk2-aarch64-code.fd"
      "C:/msys64/mingw64/share/qemu/edk2-aarch64-code.fd"
    )
    for c in "${efi_candidates[@]}"; do
      if [ -n "$c" ] && [ -f "$c" ]; then efi_code="$c"; break; fi
    done
    local var_candidates=(
      "${QEMU_EDK2_VARS:-}"
      ${brew_prefix:+"${brew_prefix}/share/qemu/edk2-arm-vars.fd"}
      "/opt/homebrew/share/qemu/edk2-arm-vars.fd"
      "/usr/share/AAVMF/AAVMF_VARS.fd"
      "/usr/share/qemu/edk2-arm-vars.fd"
      "/usr/share/edk2/aarch64/vars-template-pflash.raw"
      "/usr/share/edk2-armvirt/aarch64/QEMU_VARS.fd"
      "/usr/local/share/qemu/edk2-arm-vars.fd"
      "/opt/local/share/qemu/edk2-arm-vars.fd"
      "C:/Program Files/qemu/share/edk2-arm-vars.fd"
      "C:/msys64/mingw64/share/qemu/edk2-arm-vars.fd"
    )
    for v in "${var_candidates[@]}"; do
      if [ -n "$v" ] && [ -f "$v" ]; then efi_vars="$v"; break; fi
    done
  fi

  log_info "Starting Windows 11 VM directly with QEMU (${ARCH})..."
  echo "  Disk Image     : ${disk_img}"
  echo "  UEFI Firmware  : ${efi_code:-'(none)'}"
  echo "  CPUs / Memory  : ${VM_CPUS} CPUs, ${VM_MEM} MB RAM"
  echo "  WinRM Forward  : 127.0.0.1:5985"
  echo "  RDP Forward    : 127.0.0.1:3389"
  echo "  SSH Forward    : 127.0.0.1:2222"
  echo "  Serial Console : ${SERIAL_SOCK}"

  # Clean stale socket
  rm -f "${SERIAL_SOCK}"

  # Start serial multiplexer
  start_serial_proxy

  echo -e "${C_GREEN}${C_BOLD}VM is starting. In another terminal, run './windows-11-builder.sh serial' to connect.${C_RESET}"

  local host_os="linux"
  case "$(uname -s)" in
    Darwin*) host_os="darwin" ;;
    Linux*)  host_os="linux" ;;
    CYGWIN*|MINGW*|MSYS*) host_os="windows" ;;
  esac

  local qemu_accel="kvm"
  if [ "${host_os}" = "darwin" ]; then
    qemu_accel="hvf"
  elif [ "${host_os}" = "windows" ]; then
    qemu_accel="whpx"
  fi

  local qemu_mach="q35,accel=${qemu_accel}"
  if [ "${ARCH}" = "aarch64" ]; then
    qemu_mach="virt,highmem=on,accel=${qemu_accel}"
  fi

  local qemu_cmd=(
    "qemu-system-${ARCH}"
    "-name" "windows-11-${ARCH}"
    "-machine" "${qemu_mach}"
    "-cpu" "host"
    "-smp" "${VM_CPUS}"
    "-m" "${VM_MEM}"
  )

  if [ -n "${efi_code}" ]; then
    qemu_cmd+=("-drive" "if=pflash,format=raw,readonly=on,file=${efi_code}")
  fi

  # Setup writable NVRAM efivars
  local disk_dir
  disk_dir="$(dirname "${disk_img}")"
  local run_vars="${disk_dir}/efivars_run.fd"
  if [ -f "${disk_dir}/efivars.fd" ]; then
    cp -f "${disk_dir}/efivars.fd" "${run_vars}"
    qemu_cmd+=("-drive" "if=pflash,format=raw,file=${run_vars}")
  elif [ -n "${efi_vars}" ]; then
    cp -f "${efi_vars}" "${run_vars}"
    qemu_cmd+=("-drive" "if=pflash,format=raw,file=${run_vars}")
  fi

  if [ "${ARCH}" = "aarch64" ]; then
    qemu_cmd+=(
      "-drive" "file=${disk_img},if=none,id=disk0,cache=writeback,discard=unmap"
      "-device" "nvme,serial=nvme0,drive=disk0"
      "-netdev" "user,id=user.0,hostfwd=tcp::5985-:5985,hostfwd=tcp::3389-:3389,hostfwd=tcp::2222-:22"
      "-device" "virtio-net-pci,netdev=user.0"
      "-device" "qemu-xhci"
      "-device" "usb-kbd"
      "-device" "usb-tablet"
      "-device" "ramfb"
    )
  else
    qemu_cmd+=(
      "-drive" "file=${disk_img},if=none,id=disk0,cache=writeback,discard=unmap"
      "-device" "ide-hd,drive=disk0,bus=ide.0"
      "-netdev" "user,id=user.0,hostfwd=tcp::5985-:5985,hostfwd=tcp::3389-:3389,hostfwd=tcp::2222-:22"
      "-device" "virtio-net-pci,netdev=user.0"
      "-device" "qemu-xhci"
      "-device" "usb-kbd"
      "-device" "usb-tablet"
      "-vga" "std"
    )
  fi

  if [ -n "${VM_VNC}" ]; then
    qemu_cmd+=("-vnc" ":${VM_VNC}")
    log_info "VNC display accessible on port 590${VM_VNC}"
  elif [ "${HEADLESS}" = "true" ]; then
    qemu_cmd+=("-display" "none")
  fi

  qemu_cmd+=(
    "-chardev" "socket,id=ser0,path=${SERIAL_SOCK},server=on,wait=off"
    "-serial" "chardev:ser0"
  )

  exec "${qemu_cmd[@]}"
}

# Multi-stage aggressive box size reduction pipeline
cmd_box() {
  local provider="${1:-${PROVIDER}}"
  log_info "================================================================"
  log_info "  AGGRESSIVE VAGRANT .BOX SIZE REDUCTION PIPELINE (${ARCH}, ${provider})"
  log_info "================================================================"

  local base_files_dir="${BENTO_BUILD_FILES_DIR:-${SCRIPT_DIR}/builds/build_files}"
  local build_files_dir="${base_files_dir}/packer-windows-11-${ARCH}-${provider}"
  local complete_dir="${BENTO_BUILD_COMPLETE_DIR:-${SCRIPT_DIR}/builds/build_complete}"
  mkdir -p "${complete_dir}"

  local box_name="windows-11-${ARCH}.${provider}.box"
  local target_box="${complete_dir}/${box_name}"

  if [ "${provider}" = "qemu" ]; then
    local src_img=""
    local candidates=(
      "${build_files_dir}/windows-11-amd64"
      "${build_files_dir}/windows-11-${ARCH}"
      "${build_files_dir}/box.img"
    )

    for candidate in "${candidates[@]}"; do
      if [ -f "${candidate}" ]; then
        src_img="${candidate}"
        break
      fi
    done

    # Check builds/build_complete if packer's vagrant post-processor already built a base box
    if [ -z "${src_img}" ]; then
      local existing_box
      existing_box=$(find "${complete_dir}" -name "*windows-11*.box" 2>/dev/null | head -n 1)
      if [ -n "${existing_box}" ]; then
        log_info "Extracting disk image from existing box (${existing_box}) for optimization..."
        mkdir -p "${build_files_dir}"
        tar -xf "${existing_box}" -C "${build_files_dir}" box_0.img 2>/dev/null || tar -xf "${existing_box}" -C "${build_files_dir}" box.img 2>/dev/null || true
        if [ -f "${build_files_dir}/box_0.img" ]; then
          mv -f "${build_files_dir}/box_0.img" "${build_files_dir}/box.img"
        fi
        if [ -f "${build_files_dir}/box.img" ]; then
          src_img="${build_files_dir}/box.img"
        fi
      fi
    fi

    if [ -z "${src_img}" ]; then
      log_error "Could not find QEMU disk image in ${build_files_dir}"
      exit 1
    fi

    local orig_bytes
    orig_bytes=$(get_file_size "${src_img}")
    local orig_mb=$((orig_bytes / 1024 / 1024))
    log_info "Step 1: Input disk image: ${src_img}"
    log_info "        Original disk image size: ${orig_mb} MB ($((orig_mb / 1024)) GB)"

    # Step 2: Multi-threaded zero-block sparsification and cluster compression
    # -c enables zlib cluster compression
    # -S 4k unmaps and discards every 4KB block containing only zeroes
    # -m 16 uses 16 parallel coroutines for high-speed conversion
    # -W allows out-of-order writes
    # -p shows real-time progress
    local opt_img="${build_files_dir}/box_optimized.img"
    log_info "Step 2: Multi-threaded sparsification (-S 4k) & zlib cluster compression (-c)..."
    qemu-img convert -p -m 16 -W -O qcow2 -c -S 4k "${src_img}" "${opt_img}"

    local opt_bytes
    opt_bytes=$(get_file_size "${opt_img}")
    local opt_mb=$((opt_bytes / 1024 / 1024))
    local saved_mb=$((orig_mb - opt_mb))
    log_success "Compressed disk image size: ${opt_mb} MB (Direct disk savings: ${saved_mb} MB)"

    mv -f "${opt_img}" "${build_files_dir}/box.img"

    local virt_gb
    virt_gb=$(qemu-img info --output=json "${src_img}" | python3 -c "import sys, json; print(int(json.load(sys.stdin).get('virtual-size', 68719476736) / (1024**3)))" 2>/dev/null || echo "64")

    # Step 3: Generate Vagrant metadata and template
    # vagrant-qemu uses box_format: "libvirt" (v1 format)
    local meta_provider="${provider}"
    if [ "${provider}" = "qemu" ]; then
      meta_provider="libvirt"
    fi
    log_info "Step 3: Generating Vagrant metadata (${meta_provider}, virtual_size: ${virt_gb} GB) and Vagrantfile template..."
    cat << EOF > "${build_files_dir}/metadata.json"
{
  "provider": "${meta_provider}",
  "format": "qcow2",
  "virtual_size": ${virt_gb}
}
EOF

    cat << 'EOF' > "${build_files_dir}/Vagrantfile"
Vagrant.configure("2") do |config|
  config.vm.guest = :windows
  config.vm.communicator = "winrm"
  config.vm.boot_timeout = 600
  config.winrm.username = "vagrant"
  config.winrm.password = "vagrant"
  config.winrm.retry_limit = 30
  config.winrm.retry_delay = 10
  config.ssh.username = "vagrant"
  config.ssh.insert_key = false
  config.ssh.private_key_path = File.expand_path("~/.vagrant.d/insecure_private_key")
  config.ssh.shell = "powershell"

  config.vm.network :forwarded_port, guest: 22, host: 2222, id: 'ssh', auto_correct: true
  config.vm.network :forwarded_port, guest: 3389, host: 3389, id: 'rdp', auto_correct: true
  config.vm.network :forwarded_port, guest: 5985, host: 5985, id: 'winrm', auto_correct: true

  # Synced folder: rsync works without host privileges or password prompts
  config.vm.synced_folder ".", "/vagrant", type: "rsync"

  config.vm.provider :libvirt do |lv|
    lv.cpus = 4
    lv.memory = 6144
    lv.video_type = "virtio"
    lv.nic_model_type = "virtio"
    lv.driver = "kvm"
  end

  is_darwin = /darwin/ =~ RUBY_PLATFORM
  is_windows = /mswin|mingw|cygwin/ =~ RUBY_PLATFORM
  accel = is_darwin ? "hvf" : (is_windows ? "whpx" : "kvm")

  host_cpu = (RbConfig::CONFIG["host_cpu"] || RUBY_PLATFORM).downcase
  is_arm = host_cpu =~ /aarch64|arm64/

  config.vm.provider :qemu do |qe|
    if is_arm
      qe.arch = "aarch64"
      qe.machine = "virt,highmem=on,accel=#{accel}"
      qe.cpu = "host"
      qe.smp = "4"
      qe.memory = "4096M"
      qe.firmware_format = nil
      qe.drive_interface = "none"
      qe.net_device = "virtio-net-pci"
      qe.ssh_auto_correct = true

      bios_candidates = [
        ENV["QEMU_EDK2_PATH"],
        ENV["QEMU_BIOS"],
        "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
        "/usr/share/AAVMF/AAVMF_CODE.fd",
        "/usr/share/AAVMF/AAVMF32_CODE.fd",
        "/usr/share/qemu/edk2-aarch64-code.fd",
        "/usr/share/edk2/aarch64/QEMU_EFI-pflash.raw",
        "/usr/share/edk2/aarch64/QEMU_EFI.fd",
        "/usr/share/edk2-armvirt/aarch64/QEMU_EFI.fd",
        "/usr/local/share/qemu/edk2-aarch64-code.fd",
        "/opt/local/share/qemu/edk2-aarch64-code.fd",
        "C:/Program Files/qemu/share/edk2-aarch64-code.fd",
        "C:/msys64/mingw64/share/qemu/edk2-aarch64-code.fd"
      ].compact
      bios_path = bios_candidates.find { |path| File.exist?(path) }

      extra_args = []
      extra_args.push("-bios", bios_path) if bios_path
      extra_args.push(
        "-device", "nvme,serial=nvme0,drive=disk0",
        "-device", "ramfb",
        "-device", "qemu-xhci",
        "-device", "usb-kbd",
        "-device", "usb-tablet"
      )
      qe.extra_qemu_args = extra_args
    else
      qe.arch = "x86_64"
      qe.machine = "q35,accel=#{accel}"
      qe.cpu = "host"
      qe.smp = "4"
      qe.memory = "4096M"
      qe.drive_interface = "ide"
      qe.net_device = "virtio-net-pci"
      qe.ssh_auto_correct = true

      ovmf_candidates = [
        ENV["QEMU_EDK2_PATH"],
        ENV["QEMU_BIOS"],
        "/usr/share/OVMF/OVMF_CODE.fd",
        "/usr/share/OVMF/OVMF_CODE_4M.fd",
        "/usr/share/ovmf/OVMF.fd",
        "/usr/share/edk2/ovmf/OVMF_CODE.fd",
        "/usr/share/edk2-ovmf/x64/OVMF_CODE.fd",
        "/opt/homebrew/share/qemu/edk2-x86_64-code.fd",
        "/usr/local/share/qemu/edk2-x86_64-code.fd",
        "/opt/local/share/qemu/edk2-x86_64-code.fd",
        "/usr/share/qemu/edk2-x86_64-code.fd",
        "C:/Program Files/qemu/share/edk2-x86_64-code.fd",
        "C:/msys64/mingw64/share/qemu/edk2-x86_64-code.fd"
      ].compact
      ovmf_path = ovmf_candidates.find { |path| File.exist?(path) }

      extra_args = []
      extra_args.push("-bios", ovmf_path) if ovmf_path
      extra_args.push(
        "-device", "qemu-xhci",
        "-device", "usb-kbd",
        "-device", "usb-tablet",
        "-vga", "std"
      )
      qe.extra_qemu_args = extra_args
    end
  end
end
EOF

    # Step 4: Archive into .box with maximum level-9 compression and sparse support
    log_info "Step 4: Compacting into .box with sparse block preservation & level-9 compression..."
    local tmp_box="${target_box}.tmp"

    local tar_cmd="tar"
    local tar_sparse="--sparse"
    if command -v gtar >/dev/null 2>&1; then
      tar_cmd="gtar"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
      tar_sparse=""
    fi

    if command -v pigz >/dev/null 2>&1; then
      log_info "Using parallel pigz for maximum compression (-9) across all CPU cores..."
      (
        cd "${build_files_dir}"
        ${tar_cmd} ${tar_sparse} -I 'pigz -9' -cf "${tmp_box}" metadata.json Vagrantfile box.img
      )
    else
      log_info "Using gzip -9 for maximum compression..."
      (
        cd "${build_files_dir}"
        GZIP="-9" ${tar_cmd} ${tar_sparse} -czf "${tmp_box}" metadata.json Vagrantfile box.img
      )
    fi

    mv -f "${tmp_box}" "${target_box}"

    # Also link libvirt box to match vagrant provider convention
    local libvirt_box="${complete_dir}/windows-11-${ARCH}.libvirt.box"
    if [ "${target_box}" != "${libvirt_box}" ]; then
      cp -f "${target_box}" "${libvirt_box}"
    fi

    local box_bytes
    box_bytes=$(get_file_size "${target_box}")
    local box_mb=$((box_bytes / 1024 / 1024))
    local total_saved_mb=$((orig_mb - box_mb))

    echo ""
    echo -e "${C_GREEN}${C_BOLD}================================================================${C_RESET}"
    echo -e "${C_GREEN}${C_BOLD}  WINDOWS 11 VAGRANT .BOX OPTIMIZATION SUMMARY                 ${C_RESET}"
    echo -e "${C_GREEN}${C_BOLD}================================================================${C_RESET}"
    echo -e "  Target Box Path  : ${target_box}"
    echo -e "  Libvirt Box Path : ${libvirt_box}"
    echo -e "  Uncompressed Disk: ${orig_mb} MB ($((orig_mb / 1024)) GB)"
    echo -e "  Optimized Disk   : ${opt_mb} MB ($((opt_mb / 1024)) GB)"
    echo -e "  FINAL .BOX SIZE  : ${C_GREEN}${C_BOLD}${box_mb} MB ($((box_bytes / 1024 / 1024 / 1024)) GB)${C_RESET}"
    echo -e "  Total Reduction  : ${C_GREEN}${C_BOLD}${total_saved_mb} MB reclaimed${C_RESET}"
    echo -e "${C_GREEN}${C_BOLD}================================================================${C_RESET}"

  elif [ "${provider}" = "virtualbox" ]; then
    local vdi_path
    vdi_path=$(find "${build_files_dir}" -name "*.vdi" 2>/dev/null | head -n 1)
    if [ -n "${vdi_path}" ]; then
      log_info "Compacting VirtualBox VDI disk to reclaim zeroed sectors..."
      VBoxManage modifymedium disk "${vdi_path}" --compact
    fi
    log_info "Packaging VirtualBox .box with maximum level-9 compression..."
    local tmp_box="${target_box}.tmp"
    if command -v pigz >/dev/null 2>&1; then
      (
        cd "${build_files_dir}"
        tar --sparse -I 'pigz -9' -cf "${tmp_box}" *
      )
    else
      (
        cd "${build_files_dir}"
        GZIP="-9" tar --sparse -czf "${tmp_box}" *
      )
    fi
    mv -f "${tmp_box}" "${target_box}"
    local box_bytes
    box_bytes=$(get_file_size "${target_box}")
    log_success "Created optimized box: ${target_box} ($((box_bytes / 1024 / 1024)) MB)"
  fi
}

# Main build execution
cmd_build() {
  log_info "Starting Windows 11 Build Pipeline:"
  echo "  Architecture : ${ARCH}"
  echo "  Provider     : ${PROVIDER}"
  echo "  Headless     : ${HEADLESS}"
  echo "  Debug        : ${DEBUG_MODE}"

  # 1. Clean prior locks and processes
  cmd_clean

  # 2. Check and locate ISO
  local iso_path
  iso_path="$(find_iso)"
  if [ -z "${iso_path}" ]; then
    log_warn "No Windows 11 ISO found locally. Packer will use the remote URL in pkrvars."
  else
    log_info "Using local Windows 11 ISO: ${iso_path} ($(du -h "${iso_path}" | cut -f1))"
  fi

  # 3. Setup background serial port multiplexer and logger
  start_serial_proxy

  # 4. If stream serial requested, tail serial.log in background
  if [ "${STREAM_SERIAL}" = "true" ]; then
    log_info "Live serial output streaming enabled. Displaying serial log:"
    tail -f "${SERIAL_LOG}" &
    TAIL_PID=$!
    trap 'kill "${TAIL_PID}" 2>/dev/null || true' EXIT
  fi

  # 5. Locate pkrvars
  local pkrvars="${SCRIPT_DIR}/os_pkrvars/windows/windows-11-${ARCH}.pkrvars.hcl"
  if [ ! -f "${pkrvars}" ]; then
    log_error "Configuration file ${pkrvars} does not exist."
    exit 1
  fi

  if [ "${ARCH}" = "aarch64" ] && [ "${PROVIDER}" = "qemu" ] && [ -f "${SCRIPT_DIR}/windows-11-arm64-packer/build.sh" ]; then
    log_info "Executing dedicated Windows 11 ARM64 QEMU build pipeline..."
    "${SCRIPT_DIR}/windows-11-arm64-packer/build.sh"
    cmd_box "${PROVIDER}"
    log_success "Windows 11 build and box creation completed successfully!"
    return 0
  fi

  log_info "Validating Packer templates..."
  packer validate -var-file="${pkrvars}" "${SCRIPT_DIR}/packer_templates"

  log_info "Executing Packer Build for Windows 11 (${PROVIDER})..."
  local pkr_opts=("-timestamp-ui" "-force" "-var-file=${pkrvars}")

  local effective_iso="${CUSTOM_ISO:-${iso_path}}"
  if [ -n "${effective_iso}" ]; then
    pkr_opts+=("-var" "iso_url=file://${effective_iso}")
    if [ -f "${effective_iso}.sha256" ]; then
      pkr_opts+=("-var" "iso_checksum=$(cat "${effective_iso}.sha256")")
    elif [ -n "${PKR_VAR_iso_checksum:-}" ]; then
      pkr_opts+=("-var" "iso_checksum=${PKR_VAR_iso_checksum}")
    fi
  fi

  if [ "${PROVIDER}" = "qemu" ]; then
    pkr_opts+=("-only=qemu.vm")
  elif [ "${PROVIDER}" = "virtualbox" ]; then
    pkr_opts+=("-only=virtualbox-iso.vm")
  fi

  pkr_opts+=("-var" "headless=${HEADLESS}")
  if [ "${DEBUG_MODE}" = "true" ]; then
    pkr_opts+=("-debug")
    export PACKER_LOG=1
  fi

  log_info "Running: packer build ${pkr_opts[*]} ${SCRIPT_DIR}/packer_templates"
  packer build "${pkr_opts[@]}" "${SCRIPT_DIR}/packer_templates"

  # 6. Apply post-build multi-stage size optimizations
  cmd_box "${PROVIDER}"

  log_success "Windows 11 build and box creation completed successfully!"
}

# Main Entrypoint
case "${COMMAND}" in
  build)  cmd_build ;;
  box)    cmd_box "${PROVIDER}" ;;
  run)    cmd_run ;;
  serial) cmd_serial ;;
  status) cmd_status ;;
  clean)  cmd_clean ;;
  *)
    log_error "Unknown command: ${COMMAND}"
    exit 1
    ;;
esac
