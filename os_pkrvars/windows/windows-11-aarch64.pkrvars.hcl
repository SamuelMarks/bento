os_name           = "windows"
os_version        = "11"
os_arch           = "aarch64"
is_windows        = true
hyperv_generation = 2

# Official download url found at https://www.microsoft.com/en-us/software-download/windows11arm64
# Expected unaltered SHA256: 638aa2c88e94385b00f4f178d071e3df0b7d9e335577a83bd533b7f2eb65adf0
iso_url      = "file:///Volumes/TOSHIBA_EXT/isos/Win11_25H2_English_Arm64_v2.iso"
iso_checksum = "9e3e390c788439e66f2dd8ea6d97c68dbd020735ec179b9d592e513107384dc9"

cpus     = 4
memory   = 6144
headless = true

boot_command      = ["<up><wait><up>"]
default_boot_wait = "1s"
vbox_boot_wait    = "10s"

qemu_accelerator      = "hvf"
qemu_use_pflash       = true
qemu_disk_interface   = "virtio"
qemu_net_device       = "virtio-net-pci"
qemu_vnc_bind_address = "127.0.0.1"

parallels_guest_os_type = "win-11"
vbox_guest_os_type      = "Windows11_arm64"
vmware_guest_os_type    = "arm-windows11-64"
utm_vm_icon             = "windows-11"
