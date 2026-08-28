# Windows Support Implementation Plan

This document outlines the step-by-step plan to integrate Windows Server 2025 support, utilizing a locally provided ISO, a valid product key stored in `.env`, and employing a debloating strategy similar to tiny11builder.

## 1. Local Storage and ISO Configuration
- [x] Configure Packer to use `/Volumes/TOSHIBA_EXT/vagrant` for storing the build output (Vagrant boxes, packer output).
- [x] Update `os_pkrvars/windows/windows-2025-x86_64.pkrvars.hcl` to use the local ISO:
  - `iso_url` should point to `file:///Volumes/TOSHIBA_EXT/isos/en-us_windows_server_2025_x64_dvd_b7ec10f3.iso`.
- [x] Calculate the SHA-256 checksum of `/Volumes/TOSHIBA_EXT/isos/en-us_windows_server_2025_x64_dvd_b7ec10f3.iso` and update the `iso_checksum` in `windows-2025-x86_64.pkrvars.hcl`.

## 2. Secure and Prepare `.env` File
- [x] Verify that `.env` is present in `.gitignore` to prevent accidental commits of valid product keys.
- [x] Fix the typo in `.env`: Rename `WINDOWS_SERVER_2005_STANDARD_EDITION` to `WINDOWS_SERVER_2025_STANDARD_EDITION`.
- [x] Ensure the `.env` file is loaded correctly by the build system (either in `bin/bento` using `dotenv` in Ruby, or by a bash wrapper) so its variables are available to Packer.

## 3. Configure Packer Variables
- [x] Open `packer_templates/pkr-variables.pkr.hcl`.
- [x] Add a new input variable for the product key to allow dynamic injection:
  ```hcl
  variable "windows_product_key" {
    type    = string
    default = ""
    description = "The valid product key for Windows Server, typically loaded from .env"
  }
  ```
- [x] Map the `.env` variable to Packer's environment variable by exporting `PKR_VAR_windows_product_key=$WINDOWS_SERVER_2025_STANDARD_EDITION` prior to running the packer build.

## 4. Debloating / tiny11builder Integration
- [x] Research `tiny11builder` (https://github.com/ntdevlabs/tiny11builder) and similar approaches (like `winutil` or standard DISM/PowerShell debloat scripts) to identify safe debloating steps for Windows Server 2025.
- [x] Create a PowerShell provisioning script (e.g., `packer_templates/scripts/windows/debloat.ps1`) that applies these optimizations.
  - Remove unnecessary AppxPackages.
  - Disable telemetry and unnecessary services.
  - Optimize the registry for performance.
- [x] Integrate the debloat script into the Packer `build` block in `packer_templates/pkr-builder.pkr.hcl` as a provisioner.

## 5. Template the Answer Files (`Autounattend.xml`)
- [x] Rename existing static answer files to signify they are templates (e.g., `packer_templates/win_answer_files/2025/Autounattend.xml.pkrtpl.hcl`), or keep the name and use them in a `templatefile()` function call.
- [x] Modify the `<ProductKey>` block within the `Autounattend.xml` files for the `windowsPe` pass (both standard and `hyperv-gen2`).
- [x] Inject the key conditionally in the XML:
  ```xml
  <ProductKey>
    %{ if windows_product_key != "" }<Key>${windows_product_key}</Key>%{ endif }
    <WillShowUI>OnError</WillShowUI>
  </ProductKey>
  ```
- [x] Repeat this templating process for `packer_templates/win_answer_files/2025/arm64/Autounattend.xml` and `packer_templates/win_answer_files/2025/hyperv-gen2/Autounattend.xml`.

## 6. Update Packer Sources to Render Templates
- [x] Open `packer_templates/pkr-sources.pkr.hcl`.
- [x] Locate the `cd_files` block (around line 257) that statically copies the `Autounattend.xml`.
- [x] Replace or supplement `cd_files` with `cd_content` for Windows builds to dynamically render the XML answer files at build time:
  ```hcl
  cd_content = var.is_windows ? {
    "Autounattend.xml" = templatefile(
      "${path.root}/win_answer_files/${var.os_version}/Autounattend.xml",
      { windows_product_key = var.windows_product_key }
    )
  } : null
  ```
  *(Note: Ensure compatibility with the `hyperv_generation == 2` logic already present for path selection).*

## 7. Testing and Validation
- [x] Run a test build of `windows-2025-x86_64` using VirtualBox, VMware, or Parallels.
- [x] Verify that the local ISO is successfully mounted/used.
- [x] Monitor the Windows installation phase to confirm the setup accepts the product key without manual UI intervention.
- [x] Boot the generated vagrant box and execute `slmgr /xpr` or similar to verify activation/license status.
- [x] Verify that the debloating script ran successfully and the resulting image is optimized.
- [x] Document the requirement to add the product key to `.env` in `TESTING.md` or `README.md`.
