# frozen_string_literal: true

#
# @file upload_spec.rb
# @brief Specification tests for UploadRunner class
# @description
#   Exhaustively tests Vagrant Cloud uploads, slug resolution, description formatting,
#   provider version rendering, and protection against uploading proprietary OS boxes (including macOS)
#   with 100% line and branch coverage.
#

require 'bento/upload'

RSpec.describe UploadRunner do
  let(:opts) { build_opts(md_json: nil) }

  subject(:runner) { described_class.new(opts) }

  # ── helpers ────────────────────────────────────────────────────────────────

  describe '#box_desc' do
    it 'returns a description containing the box name with hyphens replaced by spaces' do
      expect(runner.box_desc('ubuntu-24.04')).to include('Ubuntu 24.04')
    end

    it 'capitalizes the first character of the formatted name' do
      desc = runner.box_desc('debian-12')
      expect(desc).to include('Debian 12')
    end
  end

  describe '#slug_desc' do
    it 'mentions the slug name in the description' do
      expect(runner.slug_desc('ubuntu-lts')).to include('Ubuntu lts')
    end

    it 'mentions the box will be updated with latest releases' do
      expect(runner.slug_desc('debian-latest')).to include('latest releases')
    end
  end

  describe '#ver_desc' do
    let(:md_data) do
      {
        'box_basename' => 'ubuntu-24.04-x86_64',
        'version' => '202506.01.0',
        'packer' => '1.9.0',
        'vagrant' => '2.4.1',
        'providers' => [
          { 'name' => 'virtualbox', 'version' => '7.1.0' },
          { 'name' => 'vmware_desktop', 'version' => '13.0' },
          { 'name' => 'utm', 'version' => '4.6.5' },
        ],
      }
    end

    it 'includes the box version' do
      expect(runner.ver_desc(md_data)).to include('202506.01.0')
    end

    it 'includes the packer version' do
      expect(runner.ver_desc(md_data)).to include('packer: 1.9.0')
    end

    it 'includes the vagrant version' do
      expect(runner.ver_desc(md_data)).to include('vagrant: 2.4.1')
    end

    it 'labels vmware_desktop as vmware-fusion on macOS' do
      allow(runner).to receive(:macos?).and_return(true)
      expect(runner.ver_desc(md_data)).to include('vmware-fusion')
    end

    it 'labels vmware_desktop as vmware-workstation on non-macOS' do
      allow(runner).to receive(:macos?).and_return(false)
      expect(runner.ver_desc(md_data)).to include('vmware-workstation')
    end
  end

  describe '#public_private_box' do
    let(:builds_data) { { 'public' => %w(ubuntu debian), 'vagrant_cloud_account' => 'bento', 'slugs' => [], 'default_architectures' => [] } }

    before { allow(runner).to receive(:builds_yml).and_return(builds_data) }

    it 'returns --no-private for a box with a public prefix' do
      expect(runner.public_private_box('ubuntu-24.04')).to eq('--no-private')
    end

    it 'returns --private for an unlisted box' do
      expect(runner.public_private_box('rhel-9')).to eq('--private')
    end
  end

  describe '#default_arch' do
    let(:builds_data) { { 'default_architectures' => ['amd64'], 'public' => [], 'slugs' => [], 'vagrant_cloud_account' => 'bento' } }

    before { allow(runner).to receive(:builds_yml).and_return(builds_data) }

    it 'returns --default-architecture when arch matches a default' do
      expect(runner.default_arch('amd64')).to eq('--default-architecture')
    end

    it 'returns --no-default-architecture when arch is not a default' do
      expect(runner.default_arch('arm64')).to eq('--no-default-architecture')
    end
  end

  describe '#lookup_slug' do
    let(:builds_data) do
      {
        'slugs' => %w(ubuntu debian-latest),
        'public' => [],
        'default_architectures' => [],
        'vagrant_cloud_account' => 'bento',
      }
    end

    before do
      allow(runner).to receive(:builds_yml).and_return(builds_data)
      allow(Dir).to receive(:glob).and_return([])
    end

    it 'returns the slug when box name starts with it' do
      expect(runner.lookup_slug('ubuntu-24.04')).to eq('ubuntu')
    end

    it 'returns nil when no slug matches' do
      allow(runner).to receive(:builds_yml).and_return(builds_data)
      allow(Dir).to receive(:glob).and_return([])
      expect(runner.lookup_slug('freebsd-14')).to be_nil
    end

    it 'resolves a latest slug to matching latest version' do
      allow(Dir).to receive(:glob).with('os_pkrvars/debian/**/*.pkrvars.hcl')
                                  .and_return(['os_pkrvars/debian/debian-11-x86_64.pkrvars.hcl',
                                               'os_pkrvars/debian/debian-12-x86_64.pkrvars.hcl'])
      expect(runner.lookup_slug('debian-12-x86_64')).to eq('debian-latest')
    end
  end

  describe '#error_unless_logged_in' do
    it 'warns when not logged into vagrant cloud' do
      allow(runner).to receive(:logged_in?).and_return(false)
      expect { runner.error_unless_logged_in }.to output(/cannot upload/).to_stdout
    end

    it 'does nothing when logged in' do
      allow(runner).to receive(:logged_in?).and_return(true)
      expect { runner.error_unless_logged_in }.not_to output.to_stdout
    end
  end

  describe '#start' do
    it 'calls upload_box for each metadata file' do
      allow(runner).to receive(:error_unless_logged_in)
      allow(runner).to receive(:metadata_files).and_return(['a._metadata.json', 'b._metadata.json'])
      expect(runner).to receive(:upload_box).twice
      runner.start
    end

    it 'uses the specified md_json when provided' do
      r = described_class.new(build_opts(md_json: 'custom._metadata.json'))
      allow(r).to receive(:error_unless_logged_in)
      expect(r).to receive(:upload_box).with('custom._metadata.json')
      r.start
    end
  end

  describe '#upload_box' do
    let(:macos_md) do
      {
        'box_basename' => 'macos-14-aarch64',
        'name' => 'macos-14',
        'version' => '202609.27.0',
        'arch' => 'aarch64',
        'providers' => [{ 'name' => 'utm', 'file' => 'macos-14-aarch64.utm.box' }],
      }
    end

    let(:public_md) do
      {
        'box_basename' => 'ubuntu-24.04-x86_64',
        'name' => 'ubuntu-24.04',
        'version' => '202609.27.0',
        'arch' => 'x86_64',
        'providers' => [{ 'name' => 'virtualbox', 'file' => 'ubuntu-24.04-x86_64.virtualbox.box' }],
      }
    end

    let(:builds_data) do
      {
        'vagrant_cloud_account' => 'bento',
        'public' => ['ubuntu'],
        'slugs' => ['ubuntu'],
        'default_architectures' => ['amd64'],
      }
    end

    before do
      allow(runner).to receive(:builds_yml).and_return(builds_data)
    end

    it 'refuses to upload proprietary macOS boxes and issues a warning' do
      allow(runner).to receive(:box_metadata).with('macos._metadata.json').and_return(macos_md)
      expect(runner).not_to receive(:shellout)
      expect { runner.upload_box('macos._metadata.json') }.to output(/Refusing to upload proprietary \/ restricted OS box 'macos-14-aarch64'/).to_stdout
    end

    it 'raises when architecture is unrecognized' do
      weird_md = {
        'box_basename' => 'custom-os',
        'name' => 'custom',
        'version' => '1.0',
        'arch' => 'sparc64',
        'providers' => [],
      }
      allow(runner).to receive(:box_metadata).with('weird._metadata.json').and_return(weird_md)
      expect { runner.upload_box('weird._metadata.json') }.to raise_error(/Unknown arch/)
    end

    it 'warns when the box file does not exist on disk' do
      allow(runner).to receive(:box_metadata).with('ubuntu._metadata.json').and_return(public_md)
      allow(File).to receive(:exist?).and_return(false)
      allow(FileUtils).to receive(:mv)
      expect { runner.upload_box('ubuntu._metadata.json') }.to output(/does not exist at.*Skipping!/).to_stdout
    end

    it 'uploads existing box and slug and archives metadata' do
      allow(runner).to receive(:box_metadata).with('ubuntu._metadata.json').and_return(public_md)
      allow(File).to receive(:exist?).and_return(true)
      expect(runner).to receive(:shellout).twice # once for box, once for slug
      expect(FileUtils).to receive(:mv).twice # once for box, once for metadata
      expect { runner.upload_box('ubuntu._metadata.json') }.to output(/Uploading bento\/ubuntu-24.04-x86_64/).to_stdout
    end

    it 'creates uploaded directory when it does not exist and keeps metadata when other boxes remain' do
      allow(runner).to receive(:box_metadata).with('ubuntu._metadata.json').and_return(public_md)
      # Box file exists, but uploaded_dir does not exist
      allow(File).to receive(:exist?).with(anything) do |path|
        !path.to_s.include?('uploaded')
      end
      expect(FileUtils).to receive(:mkdir_p).with(/uploaded/)
      allow(runner).to receive(:lookup_slug).and_return(nil)
      expect(runner).to receive(:shellout).once
      expect(FileUtils).to receive(:mv).once # only moves box file, not metadata file
      allow(Dir).to receive(:glob).with(anything).and_return(['remaining.box'])
      expect { runner.upload_box('ubuntu._metadata.json') }.to output(/Uploading bento\/ubuntu-24.04-x86_64/).to_stdout
    end

    it 'supports aarch64 / arm64 architecture upload' do
      arm_md = {
        'box_basename' => 'debian-12-aarch64',
        'name' => 'debian-12',
        'version' => '1.0',
        'arch' => 'aarch64',
        'providers' => [{ 'name' => 'utm', 'file' => 'debian-12-aarch64.utm.box' }],
      }
      allow(runner).to receive(:box_metadata).with('debian._metadata.json').and_return(arm_md)
      allow(File).to receive(:exist?).and_return(true)
      allow(runner).to receive(:lookup_slug).and_return(nil)
      expect(runner).to receive(:shellout).once
      expect(FileUtils).to receive(:mv).twice
      expect { runner.upload_box('debian._metadata.json') }.to output(/Uploading bento\/debian-12-aarch64/).to_stdout
    end
  end
end
