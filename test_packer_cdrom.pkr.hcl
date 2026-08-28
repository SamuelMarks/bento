source "qemu" "test" {
  iso_url      = "file:///dev/null"
  iso_checksum = "none"
  ssh_username = "test"
  cd_content = {
    "test.txt" = "hello"
  }
  cdrom_interface = "virtio"
  qemuargs = [
    ["-machine", "virt"]
  ]
}
build {
  sources = ["source.qemu.test"]
}
