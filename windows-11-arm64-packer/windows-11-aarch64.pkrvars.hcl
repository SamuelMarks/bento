os_name           = "windows"
os_version        = "11"
os_arch           = "aarch64"
is_windows        = true
hyperv_generation = 2
# Download url's found at https://www.microsoft.com/en-us/software-download/windows11arm64
iso_url                 = "file:///Volumes/TOSHIBA_EXT/isos/Win11_25H2_English_Arm64_v2.iso"
iso_checksum            = "638aa2c88e94385b00f4f178d071e3df0b7d9e335577a83bd533b7f2eb65adf0"
parallels_guest_os_type = "win-11"
vbox_guest_os_type      = "Windows11_arm64"
vmware_guest_os_type    = "arm-windows11-64"
utm_vm_icon             = "windows-11"
default_boot_wait       = "2s"
vbox_boot_wait          = "10s"
boot_command            = ["<space><space><wait><space><space><wait><space><space><wait><space><space><wait><space><space><wait><space><space><wait><space><space><wait><space><space>"]
cd_files                = []
qemu_accelerator        = "hvf"
qemuargs = [
    ["-device", "qemu-xhci"],
    ["-device", "virtio-tablet"],
    ["-drive", "file=/Users/samuel/repos/bento/windows-11-arm64-packer/builds/iso/virtio-win.iso,media=cdrom,readonly=on,file.locking=off,index=3"],
    ["-drive", "file=/Users/samuel/repos/bento/windows-11-arm64-packer/builds/iso/windows-11-aarch64-4416c24b.iso,media=cdrom,readonly=on,file.locking=off,index=2"],
    ["-drive", "file={{ .OutputDir }}/{{ .Name }},if=virtio,cache=writeback,discard=unmap,format=qcow2,index=1"],
    ["-boot", "order=c,order=d"]
]
qemu_vnc_bind_address = "0.0.0.0"
