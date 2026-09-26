# frozen_string_literal: true

#
# @file providermetadata_spec.rb
# @brief Specification tests for ProviderMetadata class
# @description
#   Exhaustively tests provider metadata inspection, box checksumming, provider detection,
#   and hypervisor version queries (UTM, Parallels, VMware, VirtualBox, Libvirt, QEMU, Hyper-V)
#   with 100% line and branch coverage.
#

require 'bento/providermetadata'

RSpec.describe ProviderMetadata do
  let(:tmpdir) { Dir.mktmpdir }
  let(:box_basename) { 'macos-14-aarch64' }

  subject(:provider_meta) { described_class.new(tmpdir, box_basename) }

  after { FileUtils.rm_rf(tmpdir) }

  describe '#read' do
    context 'with no box files present' do
      it 'returns an empty array' do
        expect(provider_meta.read).to eq([])
      end
    end

    context 'with a single utm box file' do
      let(:box_file) { File.join(tmpdir, "#{box_basename}.utm.box") }

      before do
        File.write(box_file, 'fake utm box content')
        allow(provider_meta).to receive(:version).with('utm').and_return('4.6.5')
      end

      it 'returns one provider entry' do
        result = provider_meta.read
        expect(result.length).to eq(1)
      end

      it 'sets the provider name to utm' do
        expect(provider_meta.read.first[:name]).to eq('utm')
      end

      it 'sets the file to just the basename' do
        expect(provider_meta.read.first[:file]).to eq(File.basename(box_file))
      end

      it 'sets checksum_type to sha256' do
        expect(provider_meta.read.first[:checksum_type]).to eq('sha256')
      end

      it 'calculates a sha256 checksum' do
        result = provider_meta.read.first
        expected = Digest::SHA256.file(box_file).hexdigest
        expect(result[:checksum]).to eq(expected)
      end

      it 'reports size in MB' do
        expect(provider_meta.read.first[:size]).to match(/\d+ MB/)
      end
    end

    context 'with a single virtualbox box file' do
      let(:box_file) { File.join(tmpdir, "#{box_basename}.virtualbox.box") }

      before do
        File.write(box_file, 'fake box content')
        allow(provider_meta).to receive(:version).with('virtualbox').and_return('7.1.0')
      end

      it 'returns one provider entry' do
        result = provider_meta.read
        expect(result.length).to eq(1)
      end

      it 'sets the provider name to virtualbox' do
        expect(provider_meta.read.first[:name]).to eq('virtualbox')
      end
    end

    context 'with a vmware box file' do
      let(:box_file) { File.join(tmpdir, "#{box_basename}.vmware.box") }

      before do
        File.write(box_file, 'fake vmware box')
        allow(provider_meta).to receive(:version).with('vmware_desktop').and_return('13.0')
      end

      it 'maps vmware to vmware_desktop provider name' do
        result = provider_meta.read
        expect(result.first[:name]).to eq('vmware_desktop')
      end
    end

    context 'with a libvirt box file' do
      let(:libvirt_file) { File.join(tmpdir, "#{box_basename}.libvirt.box") }

      before do
        File.write(libvirt_file, 'fake libvirt box')
        allow(provider_meta).to receive(:version).and_return('9.0')
      end

      it 'copies libvirt box to a qemu box' do
        provider_meta.read
        expect(File.exist?(File.join(tmpdir, "#{box_basename}.qemu.box"))).to be true
      end

      it 'includes both libvirt and qemu in providers' do
        result = provider_meta.read
        names = result.map { |p| p[:name] }
        expect(names).to include('libvirt', 'qemu')
      end
    end
  end

  describe '#version' do
    it 'dispatches to ver_utm for utm' do
      expect(provider_meta).to receive(:ver_utm).and_return('4.6.5')
      expect(provider_meta.version('utm')).to eq('4.6.5')
    end

    it 'dispatches to ver_vmware for vmware' do
      expect(provider_meta).to receive(:ver_vmware).and_return('13.5')
      expect(provider_meta.version('vmware_desktop')).to eq('13.5')
    end

    it 'dispatches to ver_parallels for parallels' do
      expect(provider_meta).to receive(:ver_parallels).and_return('20.1')
      expect(provider_meta.version('parallels')).to eq('20.1')
    end

    it 'dispatches to ver_vbox for virtualbox' do
      expect(provider_meta).to receive(:ver_vbox).and_return('7.1.0')
      expect(provider_meta.version('virtualbox')).to eq('7.1.0')
    end

    it 'dispatches to ver_libvirt for libvirt' do
      expect(provider_meta).to receive(:ver_libvirt).and_return('9.0.0')
      expect(provider_meta.version('libvirt')).to eq('9.0.0')
    end

    it 'dispatches to ver_qemu for qemu' do
      expect(provider_meta).to receive(:ver_qemu).and_return('9.1.0')
      expect(provider_meta.version('qemu')).to eq('9.1.0')
    end

    it 'dispatches to ver_hyperv for hyperv' do
      expect(provider_meta).to receive(:ver_hyperv).and_return('10.0 Gen 2')
      expect(provider_meta.version('hyperv')).to eq('10.0 Gen 2')
    end

    it 'returns nil for an unknown provider' do
      expect(provider_meta.version('docker')).to be_nil
    end
  end

  describe '#ver_utm' do
    it 'raises if not on macOS' do
      allow(provider_meta).to receive(:macos?).and_return(false)
      expect { provider_meta.ver_utm }.to raise_error(/Platform is not macOS/)
    end

    it 'reads version from Info.plist if available on macOS' do
      allow(provider_meta).to receive(:macos?).and_return(true)
      allow(File).to receive(:exist?).with('/Applications/UTM.app/Contents/Info.plist').and_return(true)
      sout = instance_double(Mixlib::ShellOut, run_command: true, error?: false, stdout: "4.6.5\n")
      allow(Mixlib::ShellOut).to receive(:new).with('defaults read /Applications/UTM.app/Contents/Info.plist CFBundleShortVersionString').and_return(sout)
      expect(provider_meta.ver_utm).to eq('4.6.5')
    end

    it 'falls back to utmctl when Info.plist defaults read fails with error' do
      allow(provider_meta).to receive(:macos?).and_return(true)
      allow(File).to receive(:exist?).with('/Applications/UTM.app/Contents/Info.plist').and_return(true)
      sout_plist = instance_double(Mixlib::ShellOut, run_command: true, error?: true, stdout: '')
      sout_cli = instance_double(Mixlib::ShellOut, run_command: true, error?: false, stdout: "4.6.1\n")
      allow(Mixlib::ShellOut).to receive(:new).with('defaults read /Applications/UTM.app/Contents/Info.plist CFBundleShortVersionString').and_return(sout_plist)
      allow(Mixlib::ShellOut).to receive(:new).with('utmctl --version').and_return(sout_cli)
      expect(provider_meta.ver_utm).to eq('4.6.1')
    end

    it 'falls back to utmctl when Info.plist defaults read returns empty stdout' do
      allow(provider_meta).to receive(:macos?).and_return(true)
      allow(File).to receive(:exist?).with('/Applications/UTM.app/Contents/Info.plist').and_return(true)
      sout_plist = instance_double(Mixlib::ShellOut, run_command: true, error?: false, stdout: " \n")
      sout_cli = instance_double(Mixlib::ShellOut, run_command: true, error?: false, stdout: "4.6.1\n")
      allow(Mixlib::ShellOut).to receive(:new).with('defaults read /Applications/UTM.app/Contents/Info.plist CFBundleShortVersionString').and_return(sout_plist)
      allow(Mixlib::ShellOut).to receive(:new).with('utmctl --version').and_return(sout_cli)
      expect(provider_meta.ver_utm).to eq('4.6.1')
    end

    it 'falls back to utmctl --version when Info.plist does not exist' do
      allow(provider_meta).to receive(:macos?).and_return(true)
      allow(File).to receive(:exist?).with('/Applications/UTM.app/Contents/Info.plist').and_return(false)
      sout = instance_double(Mixlib::ShellOut, run_command: true, error?: false, stdout: "4.6.0
")
      allow(Mixlib::ShellOut).to receive(:new).with('utmctl --version').and_return(sout)
      expect(provider_meta.ver_utm).to eq('4.6.0')
    end

    it 'falls back to utmctl version if utmctl --version errors' do
      allow(provider_meta).to receive(:macos?).and_return(true)
      allow(File).to receive(:exist?).with('/Applications/UTM.app/Contents/Info.plist').and_return(false)
      sout1 = instance_double(Mixlib::ShellOut, run_command: true, error?: true, stdout: '')
      sout2 = instance_double(Mixlib::ShellOut, run_command: true, error?: false, stdout: "4.5.0\n")
      allow(Mixlib::ShellOut).to receive(:new).with('utmctl --version').and_return(sout1)
      allow(Mixlib::ShellOut).to receive(:new).with('utmctl version').and_return(sout2)
      expect(provider_meta.ver_utm).to eq('4.5.0')
    end

    it 'falls back to utmctl version if utmctl --version returns empty stdout' do
      allow(provider_meta).to receive(:macos?).and_return(true)
      allow(File).to receive(:exist?).with('/Applications/UTM.app/Contents/Info.plist').and_return(false)
      sout1 = instance_double(Mixlib::ShellOut, run_command: true, error?: false, stdout: "   \n")
      sout2 = instance_double(Mixlib::ShellOut, run_command: true, error?: false, stdout: "4.5.0\n")
      allow(Mixlib::ShellOut).to receive(:new).with('utmctl --version').and_return(sout1)
      allow(Mixlib::ShellOut).to receive(:new).with('utmctl version').and_return(sout2)
      expect(provider_meta.ver_utm).to eq('4.5.0')
    end
  end

  describe '#ver_parallels' do
    it 'raises if not on macOS' do
      allow(provider_meta).to receive(:macos?).and_return(false)
      expect { provider_meta.ver_parallels }.to raise_error(/Platform is not macOS/)
    end

    it 'queries prlctl --version on macOS' do
      allow(provider_meta).to receive(:macos?).and_return(true)
      sout = instance_double(Mixlib::ShellOut, run_command: true, stdout: 'prlctl version 20.1.0')
      allow(Mixlib::ShellOut).to receive(:new).with('prlctl --version').and_return(sout)
      expect(provider_meta.ver_parallels).to eq('20.1.0')
    end
  end

  describe '#ver_vbox' do
    it 'queries VBoxManage --version' do
      sout = instance_double(Mixlib::ShellOut, run_command: true, stdout: '7.1.0r164728')
      allow(Mixlib::ShellOut).to receive(:new).with('VBoxManage --version').and_return(sout)
      expect(provider_meta.ver_vbox).to eq('7.1.0')
    end
  end

  describe '#ver_libvirt' do
    it 'queries libvirtd -V' do
      sout = instance_double(Mixlib::ShellOut, run_command: true, stdout: 'libvirtd (libvirt) 9.0.0')
      allow(Mixlib::ShellOut).to receive(:new).with('libvirtd -V').and_return(sout)
      expect(provider_meta.ver_libvirt).to eq('9.0.0')
    end
  end

  describe '#ver_qemu' do
    it 'queries qemu-system for base architecture' do
      sout = instance_double(Mixlib::ShellOut, run_command: true, stdout: 'QEMU emulator version 9.1.0 (v9.1.0)')
      allow(Mixlib::ShellOut).to receive(:new).with('qemu-system-aarch64 -version').and_return(sout)
      expect(provider_meta.ver_qemu).to eq('9.1.0')
    end
  end

  describe '#ver_hyperv' do
    it 'queries PowerShell for Hyper-V version' do
      sout = instance_double(Mixlib::ShellOut, run_command: true, stdout: '10.0 ')
      allow(Mixlib::ShellOut).to receive(:new).with(include('Get-VMHostSupportedVersion')).and_return(sout)
      expect(provider_meta.ver_hyperv).to eq('10.0 Gen 2')
    end
  end

  describe '#ver_vmware' do
    it 'queries vmware-vmx on macOS' do
      allow(provider_meta).to receive(:macos?).and_return(true)
      sout = instance_double(Mixlib::ShellOut, run_command: true, stderr: 'VMware Fusion version 13.5.0 build 22583790')
      allow(Mixlib::ShellOut).to receive(:new).with(include('vmware-vmx -v')).and_return(sout)
      expect(provider_meta.ver_vmware).to eq('22583790')
    end

    it 'queries vmware --version on non-macOS' do
      allow(provider_meta).to receive(:macos?).and_return(false)
      sout = instance_double(Mixlib::ShellOut, run_command: true, stdout: 'VMware Workstation 17.5.0')
      allow(Mixlib::ShellOut).to receive(:new).with('vmware --version').and_return(sout)
      expect(provider_meta.ver_vmware).to eq('17.5.0')
    end
  end
end
