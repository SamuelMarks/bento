# Microsoft MS-DOS (1.25 / 2.0 / 4.0) Standalone Bento Builder & Vagrant Plugin Guide (`MSDOS.md`)

This guide explains how to build, package, sync, and control standalone **Microsoft MS-DOS (1.25, 2.0, and 4.00)** virtual machine images from the official [`microsoft/ms-dos`](https://github.com/microsoft/ms-dos) open-source repository across **both `aarch64` (Apple Silicon / ARM64) and `x86_64` (Intel / AMD64) hosts** using Bento and Vagrant.

---

## 1. Architecture & Supported MS-DOS Versions

1. **Multi-Version `microsoft/ms-dos` Support**:
   - **MS-DOS 1.25 (`v1.25/bin` & `v1.25/source`)**:
     - Classic flat FAT12 directory layout (`COMMAND.COM`, `SYS.COM`, `FORMAT.COM`, `CHKDSK.COM`, `DEBUG.COM`, `EDLIN.COM`, `LINK.EXE`, `EXE2BIN.EXE`, `BASIC.COM`, `BASICA.COM`, `DONKEY.BAS`).
     - Automatic flat 8.3 path mapping (`Bento::VagrantMsdos::Config#supports_subdirectories? == false`) so host files in nested directories are staged cleanly onto the root of `D:`.
   - **MS-DOS 2.0 (`v2.0/bin` & `v2.0/source`)**:
     - Introduces hierarchical subdirectories (`MKDIR`, `CHDIR`, `RMDIR`), `CONFIG.SYS`, and hard-disk support (`MSDOS.SYS`, `COMMAND.COM`, `MASM.EXE`, `LINK.EXE`, `EXE2BIN.EXE`, `DEBUG.COM`, `MORE.COM`, `FIND.EXE`, `SORT.EXE`, `FC.EXE`).
   - **MS-DOS 4.0 (`v4.0/src` & `v4.0/src/TOOLS/BLD/BIN`)**:
     - Full source release with bundled 16-bit Microsoft development tools (`MASM.EXE`, `CL.EXE`, `LINK.EXE`, `NMAKE.EXE`, `EXE2BIN.EXE`, `LIB.EXE`) staged in `C:\TOOLS\BIN`.
     - `packer_templates/scripts/msdos/build_msdos_from_source.sh` automatically normalizes line endings (`LF` -> `CRLF`) and strips stray `0x1A` (`Ctrl-Z`) EOF markers across `v4.0/src`.
2. **Cross-Architecture Execution (`aarch64` & `x86_64`)**:
   - On `aarch64` hosts (Apple Silicon macOS / Linux ARM64), `qemu-system-i386` and UTM run the 16-bit x86 MS-DOS guest via TCG software emulation (`accel=tcg`).
   - On `x86_64` hosts, QEMU/VirtualBox uses hardware acceleration (`hvf:tcg`, `kvm:tcg`, `whpx`) or TCG.
3. **Zero-Memory Serial/Telnet Guest Agent (`COM1`)**:
   - QEMU/UTM/VirtualBox bridges `COM1` (`0x3F8`, IRQ 4) to TCP Telnet (`127.0.0.1:2324` by default) or a Unix domain socket (`/tmp/msdos-serial.sock`).
   - Inside MS-DOS, `C:\AUTOEXEC.BAT` executes `SERINIT.COM` (`115200,N,8,1`) and `C:\BENTO\VAGAGENT.BAT` (`CTTY COM1`), printing `===BENTO_MSDOS_READY===`.
   - `C:\BENTO\SHUTDOWN.COM` (54-byte 8086 real-mode binary) performs APM 1.2 (`INT 15h AX=5307h`) and QEMU/Bochs/VirtualBox ACPI port poweroff (`0x604`, `0xB004`, `0x4004`) when `vagrant halt` runs.
   - `C:\BENTO\SERGET.COM` (248-byte 8086 real-mode binary) streams Base64 payloads directly from `0x3F8` (`COM1` UART) into 512-byte buffered disk writes (`Communicator#fast_upload_file!`).
4. **Tracked 16-Bit 8086 NASM Assembly Sources (`packer_templates/scripts/msdos/asm/`)**:
   - `io_msdos125.asm` (4,096 bytes): MS-DOS 1.25 `IO.SYS` (`0070:0000h`) implementing bidirectional `COM1` + BIOS console I/O, on-the-fly FAT12<->FAT16 translation for `A:`, `B:`, `C:`, and `D:`, and a resident DOS 2.0/3.0+ `INT 21h` syscall shim (`AH=26h`, `30h`, `31h`, `35h`, `3Ch`..`44h`, `47h`..`4Ah`, `4Ch`, `4Dh`, `56h`, `5Bh`, `63h`, `66h`, `68h`) bridging file handles `5..8` to 86-DOS FCBs.
   - `io_msdos20.asm` (4,096 bytes): MS-DOS 2.0 `IO.SYS` (`0070:0000h`) with `CON`, `AUX`, `COM1`, `PRN`, `CLOCK`, and 4-unit `DSK` drivers plus `FILES=28` SFT expansion.
   - `ver_com.asm` (33 bytes), `echo_com.asm` (105 bytes), `serget_com.asm` (248 bytes), `serinit_com.asm` (224 bytes), `b64enc_com.asm` (460 bytes), `b64dec_com.asm` (459 bytes), and `shutdown_com.asm` (54 bytes).
5. **Automatic MZ `.EXE` 512-Byte (`32`-Paragraph) Header Alignment (`align_mz_header_for_dos125`)**:
   - MS-DOS 1.25 `COMMAND.COM` (`EXELOAD`) rounds `e_cparhdr` up to 512-byte pages (`(HEADSIZ + 31) >> 5`). `Bento::VagrantMsdos::Communicator` automatically pads `e_cparhdr` to a multiple of 32 paragraphs (512 bytes) and strips trailing debug symbols when uploading `.EXE` binaries to MS-DOS 1.25.

---

## 2. Quick Start with `msdos-builder.sh`

```sh
# 1. Fetch microsoft/ms-dos, build MS-DOS 4.0 image, package .box files, and register in Vagrant
./msdos-builder.sh all

# Build MS-DOS 2.0 or MS-DOS 1.25 specifically:
MSDOS_VERSION=2.0 ./msdos-builder.sh all
MSDOS_VERSION=1.25 ./msdos-builder.sh all

# 2. Boot standalone MS-DOS VM in the background
./msdos-builder.sh run

# 3. Execute one-shot DOS commands over the Serial/Telnet bridge
./msdos-builder.sh ssh -c "VER"
./msdos-builder.sh ssh -c "DIR C:"

# 4. Open an interactive MS-DOS console (press Ctrl+] to disconnect)
./msdos-builder.sh ssh

# 5. Stop the standalone VM and clean sockets
./msdos-builder.sh clean
```

---

## 3. Using the `Bento::VagrantMsdos` Plugin Suite in a `Vagrantfile`

```ruby
require "bento/vagrant_msdos"

Vagrant.configure("2") do |config|
  config.vm.box = "bento/msdos-4.0"
  config.vm.guest = :msdos
  config.vm.communicator = :msdos
  config.ssh.insert_key = false

  config.msdos.host = "127.0.0.1"
  config.msdos.port = 2324
  config.msdos.dos_version = "4.0" # "1.25", "2.0", or "4.0"
  config.msdos.sync_drive = "D:"

  # Bidirectional Host <-> Guest folder synchronization
  config.vm.synced_folder ".", "/vagrant",
    type: :msdos_sync,
    drive: "D:",
    sync_direction: :bidirectional,
    crlf_convert: true
end
```

### Running Commands via `vagrant ssh` Polyfill (`Bento::VagrantMsdos::CommandSsh`)

```sh
# Non-interactive DOS command execution (returns DOS %ERRORLEVEL% and syncs D: back to host)
vagrant ssh -c "VER"
vagrant ssh -c "D:\BUILDMS.BAT"

# Interactive raw-TTY session connected to MS-DOS COM1 (C:\>)
vagrant ssh
```

### Syncing Directories (`Bento::VagrantMsdos::SyncedFolder` & `CommandSync`)

```sh
# Push host workspace files to MS-DOS D: drive (with LF -> CRLF conversion)
vagrant msdos-sync --to-guest --crlf --live

# Pull compiled .COM/.EXE/.OBJ/.TXT artifacts from MS-DOS D: back to host
vagrant msdos-sync --to-host --live
```

---

## 4. OpenWatcom v2 CMake + CTest Cross-Compilation Across MS-DOS 1.25, 2.0 & 4.00

```sh
# 1. Configure and cross-compile 16-bit DOS executables on the host with CMake + OpenWatcom v2
cmake -S . -B build-dos \
  -DCMAKE_SYSTEM_NAME=DOS \
  -DCMAKE_C_COMPILER=wcl \
  -DCMAKE_C_FLAGS="-bt=dos -ml -0 -zq"
cmake --build build-dos

# 2. Stream and execute compiled test binaries inside MS-DOS 1.25, 2.0, or 4.00 via SERGET.COM
ruby -I lib -rbento/vagrant_msdos -e '
  cfg = Bento::VagrantMsdos::Config.new
  cfg.dos_version = "1.25"
  cfg.port = 2312
  cfg.finalize!
  vm = Struct.new(:communicator, :guest).new(:msdos, :msdos)
  mach = Struct.new(:config, :data_dir).new(Struct.new(:vm, :msdos).new(vm, cfg), nil)
  comm = Bento::VagrantMsdos::Communicator.new(mach)
  comm.fast_upload_file!("build-dos/test.exe", "C:\\TEST.EXE")
  exit(comm.execute("C:\\TEST.EXE", error_check: false) { |_, d| print d })
'
```

