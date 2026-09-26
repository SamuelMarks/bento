# frozen_string_literal: true

#
# @file providermetadata.rb
# @brief Provider metadata discovery and hypervisor version extraction for Bento
# @description
#   Discovers packaged Vagrant box files (*.box) for a given build base,
#   calculates SHA-256 checksums and file sizes, and queries installed hypervisors
#   (including UTM, VMware, VirtualBox, Parallels, Libvirt, QEMU, Hyper-V) for version strings.
#

require 'digest'
require 'bento/common'

#
# @class ProviderMetadata
# @description Inspects built box artifacts and extracts hypervisor versions for metadata files.
#
class ProviderMetadata
  include Common

  #
  # Initializes a new ProviderMetadata inspection instance.
  #
  # @param [String] path Directory containing built box files.
  # @param [String] box_basename Base name of the box without provider extensions.
  #
  def initialize(path, box_basename)
    @base = File.join(path, box_basename)
  end

  #
  # Reads all box artifacts for the configured base and compiles metadata records.
  # Automatically aliases libvirt box artifacts to qemu boxes if present.
  #
  # @return [Array<Hash{Symbol => String}>] Array of provider metadata records.
  #
  def read
    if File.exist?("#{base}.libvirt.box")
      FileUtils.cp("#{base}.libvirt.box", "#{base}.qemu.box")
    end
    Dir.glob("#{base}.*.box").map do |file|
      {
        name: provider_from_file(file),
        version: version(provider_from_file(file)),
        file: File.basename(file).to_s,
        checksum_type: 'sha256',
        checksum: shasum(file),
        size: "#{size_in_mb(file)} MB",
      }
    end
  end

  #
  # Queries the installed version string for a given hypervisor provider.
  #
  # @param [String] provider Canonical provider identifier (e.g. 'utm', 'virtualbox').
  # @return [String] Detected hypervisor version string.
  #
  def version(provider)
    case provider
    when /vmware/
      ver_vmware
    when /virtualbox/
      ver_vbox
    when /parallels/
      ver_parallels
    when /libvirt/
      ver_libvirt
    when /qemu/
      ver_qemu
    when /hyperv/
      ver_hyperv
    when /utm/
      ver_utm
    end
  end

  #
  # Retrieves UTM version from /Applications/UTM.app bundle or utmctl CLI.
  #
  # @return [String] UTM release version string.
  # @raise [RuntimeError] If host platform is not macOS.
  #
  def ver_utm
    raise 'Platform is not macOS, exiting...' unless macos?

    if File.exist?('/Applications/UTM.app/Contents/Info.plist')
      cmd = Mixlib::ShellOut.new('defaults read /Applications/UTM.app/Contents/Info.plist CFBundleShortVersionString')
      cmd.run_command
      return cmd.stdout.strip unless cmd.error? || cmd.stdout.strip.empty?
    end

    cmd = Mixlib::ShellOut.new('utmctl --version')
    cmd.run_command
    return cmd.stdout.strip unless cmd.error? || cmd.stdout.strip.empty?

    cmd = Mixlib::ShellOut.new('utmctl version')
    cmd.run_command
    cmd.stdout.strip
  end

  #
  # Retrieves VMware Fusion or Workstation version.
  #
  # @return [String] VMware version string.
  #
  def ver_vmware
    if macos?
      path = File.join('/Applications/VMware\ Fusion.app/Contents/Library')
      fusion_cmd = File.join(path, 'vmware-vmx -v')
      cmd = Mixlib::ShellOut.new(fusion_cmd)
      cmd.run_command
      cmd.stderr.split(' ')[5]
    else
      cmd = Mixlib::ShellOut.new('vmware --version')
      cmd.run_command
      cmd.stdout.split(' ')[2]
    end
  end

  #
  # Retrieves Parallels Desktop version from prlctl CLI.
  #
  # @return [String] Parallels version string.
  # @raise [RuntimeError] If host platform is not macOS.
  #
  def ver_parallels
    raise 'Platform is not macOS, exiting...' unless macos?

    cmd = Mixlib::ShellOut.new('prlctl --version')
    cmd.run_command
    cmd.stdout.split(' ')[2]
  end

  #
  # Retrieves Oracle VirtualBox version from VBoxManage CLI.
  #
  # @return [String] VirtualBox version string.
  #
  def ver_vbox
    cmd = Mixlib::ShellOut.new('VBoxManage --version')
    cmd.run_command
    cmd.stdout.split('r').first
  end

  #
  # Retrieves Libvirt daemon version.
  #
  # @return [String] Libvirtd version string.
  #
  def ver_libvirt
    cmd = Mixlib::ShellOut.new('libvirtd -V')
    cmd.run_command
    cmd.stdout.split(' ').last
  end

  #
  # Retrieves QEMU emulator version for the target architecture.
  #
  # @return [String] QEMU version string.
  #
  def ver_qemu
    cmd = Mixlib::ShellOut.new("qemu-system-#{base.split('-').last} -version")
    cmd.run_command
    cmd.stdout.split(' ')[3]
  end

  #
  # Retrieves Microsoft Hyper-V version via PowerShell.
  #
  # @return [String] Hyper-V version string.
  #
  def ver_hyperv
    cmd = Mixlib::ShellOut.new('(Get-VMHostSupportedVersion -Default | Select-Object -Property Version | Format-Table -HideTableHeaders | Out-String).trim()')
    cmd.run_command
    cmd.stdout + 'Gen 2'
  end

  private

  # @return [String] Base box file path prefix.
  attr_reader :base

  #
  # Extracts the canonical provider name from a box file name.
  #
  # @param [String] file Path or file name of the box file.
  # @return [String] Canonical provider name (e.g. 'utm', 'vmware_desktop').
  #
  def provider_from_file(file)
    provider = file.sub(/^.*\.([^.]+)\.box$/, '\1')
    if provider == 'vmware'
      'vmware_desktop'
    else
      provider
    end
  end

  #
  # Computes the SHA-256 hexadecimal digest for a given file.
  #
  # @param [String] file Path to the file.
  # @return [String] 64-character hex checksum string.
  #
  def shasum(file)
    Digest::SHA256.file(file).hexdigest
  end

  #
  # Computes the file size in megabytes, rounded up.
  #
  # @param [String] file Path to the file.
  # @return [String] Size in MB as a string.
  #
  def size_in_mb(file)
    size = File.size(file)
    size_mb = size / MEGABYTE
    size_mb.ceil.to_s
  end
end
