os_name                 = "alpine"
os_version              = "3.21"
os_arch                 = "x86_64"
iso_url                 = "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-standard-3.21.3-x86_64.iso"
iso_checksum            = "file:https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-standard-3.21.3-x86_64.iso.sha256"
parallels_guest_os_type = "otherlinux"
vbox_guest_os_type      = "ArchLinux_64"
vmware_guest_os_type    = "otherlinux-64"
ssh_username            = "root"
boot_command            = ["<wait20>root<enter>",
"ifconfig eth0 up && udhcpc -i eth0<enter><wait5>",
"wget http://{{ .HTTPIP }}:{{ .HTTPPort }}/alpine/answers<enter><wait>",
"setup-alpine -f answers<enter><wait5>",
"vagrant<enter><wait1>",
"vagrant<enter><wait1>",
"y<enter><wait10>",
"mount /dev/sda3 /mnt<enter>",
"echo 'PermitRootLogin yes' >> /mnt/etc/ssh/sshd_config<enter>",
"umount /mnt<enter>",
"reboot<enter>"
]
