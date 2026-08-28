# Windows 11 ARM64 Headless Packer Build

Automated, completely headless Packer template for building optimized, minimal Windows 11 ARM64 (aarch64) Vagrant boxes for QEMU / Apple Silicon (HVF).

---

## Key Features & Architecture

* **100% Headless Automated Installation**:
  * Automatically remasters the official Microsoft Windows 11 ARM64 ISO with `efisys_noprompt.bin` to eliminate the interactive *"Press any key to boot from CD or DVD"* prompt.
  * Injects VirtIO storage (`viostor`, `vioscsi`), network (`NetKVM`), and system drivers directly into `boot.wim` and executes `setup.exe` with answer file `/unattend:X:\Autounattend.xml`.
  * Pre-configures WinRM HTTP listener on port 5985 for headless CLI provisioning.

* **Minimal Footprint & Debloat Optimizations**:
  * **CompactOS**: Enables transparent kernel LZX compression (`compact.exe /CompactOS:always`), saving 4–6 GB.
  * **LZX Directory Compression**: Compresses `Program Files` and `DriverStore` using LZX.
  * **Hibernation Disabled**: Eliminates `hiberfil.sys` (`powercfg /h off`), saving 3–5 GB.
  * **Reserved Storage Disabled**: Reclaims ~7 GB via `DISM.exe /Online /Set-ReservedStorageState /State:Disabled`.
  * **Appx & Bloatware Stripping**: Removes consumer provisioned packages (Xbox, News, Weather, Solitaire, Mixed Reality, Clipchamp, Copilot, DevHome, etc.).
  * **Capabilities & FOD Pruning**: Removes unneeded language/speech models, handwriting recognition, biometric face recognition (`Hello.Face`), and legacy viewers (`WordPad`, `MathRecognizer`, `StepsRecorder`, `Fax/Scan`).
  * **WinSxS Component Store Reset**: Executes `dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase` to permanently purge superseded component versions.
  * **Background Service Optimization**: Disables high-I/O and telemetry services (`SysMain`, `WSearch`, `DiagTrack`, `dmwappushservice`, `MapsBroker`, `WerSvc`, `XboxNetApiSvc`).
  * **Zero-Wiping & ReTrim**: Cleans temporary files, wipes unallocated sectors, and trims the virtual disk so Vagrant gzip level 9 compression achieves a final `.box` size of **~3.2 – 3.8 GB**.

* **Automation Ready**:
  * Retains full PowerShell 5.1+, WinRM, WMI/CIM, .NET Framework 4.8+, and Universal C Runtime support.

---

## Build Requirements

* **Host OS**: macOS on Apple Silicon (ARM64)
* **QEMU**: `qemu-system-aarch64` with HVF acceleration
* **Packer**: `>= 1.10.0`
* **EDK2 Firmware**: `edk2-aarch64-code.fd` and `edk2-arm-vars.fd`
* **Tools**: `xorriso`, `wimlib-imagex`, `7z` (installable via Homebrew)
* **Official Windows 11 ARM64 ISO**: Download from [Microsoft Windows 11 ARM64](https://www.microsoft.com/en-us/software-download/windows11arm64)
  * Expected Unaltered SHA256: `638aa2c88e94385b00f4f178d071e3df0b7d9e335577a83bd533b7f2eb65adf0`

---

## Configuration & Environment Variables

You can configure paths via `.env` in the repository root or environment variables:

| Variable | Description | Default |
|---|---|---|
| `WIN11_ISO_PATH` | Path to the source Windows 11 ARM64 ISO | Auto-detected from `$ISO_DIR` or `./builds/iso/` |
| `ISO_DIR` | Directory containing ISO files | `$HOME/isos` or `./builds/iso` |
| `BENTO_BUILD_COMPLETE_DIR` | Output directory for finished `.box` files | `./builds/build_complete` |
| `BENTO_BUILD_FILES_DIR` | Output directory for interim build files | `./builds/build_files` |

---

## Running the Build

Run the automated build script:

```bash
./build.sh
```

The script automatically detects the official ISO, prepares the headless remastered boot media with injected VirtIO drivers, and starts the Packer build.

---

## Output

* **Final Box**: `<build_complete_dir>/windows-11-aarch64.libvirt.box` (or `qemu.box`)
* **Expected Box Size**: `~3.2 – 3.8 GB` (vs. standard `12 – 15 GB`)
* **Default Credentials**: `vagrant` / `vagrant`
