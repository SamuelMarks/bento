# Windows 11 ARM64 Support Implementation Plan

This plan tracks the port of the Windows Server 2025 debloat and ISO handling approach over to Windows 11 ARM64, integrated inside the Bento repository but in a separate directory structure to keep it isolated.

## 1. Directory Structure and Files
- [x] Create an isolated folder `windows-11-arm64-packer` to avoid disrupting the existing 2025 setup.
- [x] Copy the `packer_templates` to `windows-11-arm64-packer/packer_templates`.
- [x] Copy the specific pkrvars (`os_pkrvars/windows/windows-11-aarch64.pkrvars.hcl`) to the new folder.
- [x] Create a `build.sh` script to parse `.env` and execute `packer build`.

## 2. Incorporate custom scripts from apter-tech repo
- [x] Integrate `auto_login.ps1` from the `apter-tech` repository into the `scripts/windows` folder.
- [x] Add the new scripts (including `debloat.ps1` and `auto_login.ps1`) to the provisioners in `pkr-builder.pkr.hcl`.

## 3. Template Answer Files for Product Key Injection
- [x] Check the `Autounattend.xml` under `win_answer_files/11/arm64/` to ensure it is correctly targeted.
- [x] Use `templatefile()` inside `pkr-sources.pkr.hcl` to render `windows_product_key` (already correctly updated globally during the 2025 work).
- [x] Replace the static `<ProductKey>` block in the Windows 11 `Autounattend.xml` with dynamic `${windows_product_key}` injection.

## 4. Validating the VMXNET3 Adapter
- [x] Verify that `var.is_windows && var.os_arch == "aarch64"` correctly maps to `vmxnet3` in `pkr-sources.pkr.hcl`.

## 5. Next Steps for the User
- [x] Run `./windows-11-arm64-packer/build.sh` on an Apple Silicon Mac using a valid Windows 11 ARM64 ISO.
