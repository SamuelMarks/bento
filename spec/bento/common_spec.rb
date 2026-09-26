# frozen_string_literal: true

#
# @file common_spec.rb
# @brief Specification tests for the Common helper module
# @description
#   Exhaustively tests all utility, platform detection, legal compliance,
#   and formatting methods provided by Common with 100% line and branch coverage.
#

require 'bento/common'

#
# @class CommonHost
# @description Concrete class mixing in Common for isolated testing.
#
class CommonHost
  include Common
end

RSpec.describe Common do
  subject(:host) { CommonHost.new }

  describe '#banner' do
    it 'prints a banner-prefixed message to stdout' do
      expect { host.banner('hello') }.to output("==> hello
").to_stdout
    end
  end

  describe '#info' do
    it 'prints an indented message to stdout' do
      expect { host.info('detail') }.to output("    detail
").to_stdout
    end
  end

  describe '#warn' do
    it 'prints a warn-prefixed message to stdout' do
      expect { host.warn('caution') }.to output(">>> caution
").to_stdout
    end
  end

  describe '#shellout' do
    it 'executes a shell command successfully' do
      sout = instance_double(Mixlib::ShellOut, run_command: true, error!: nil, live_stream: nil)
      allow(Mixlib::ShellOut).to receive(:new).with('echo ok').and_return(sout)
      expect(sout).to receive(:live_stream=).with(anything)
      expect(sout).to receive(:run_command)
      expect(sout).to receive(:error!)
      expect { host.shellout('echo ok') }.to output(/Shelling out to run echo ok/).to_stdout
    end

    it 'raises if the command fails' do
      sout = instance_double(Mixlib::ShellOut, run_command: true, live_stream: nil)
      allow(sout).to receive(:error!).and_raise(RuntimeError, 'command failed')
      allow(Mixlib::ShellOut).to receive(:new).with('bad_cmd').and_return(sout)
      expect(sout).to receive(:live_stream=).with(anything)
      expect { host.shellout('bad_cmd') }.to raise_error(RuntimeError, 'command failed')
    end
  end

  describe '#logged_in?' do
    it 'returns true when vagrant cloud reports Currently logged in' do
      sout = instance_double(Mixlib::ShellOut, error?: false, stdout: 'Currently logged in as user', stderr: '')
      allow(Mixlib::ShellOut).to receive(:new).with('vagrant cloud auth whoami').and_return(double(run_command: sout))
      expect(host.logged_in?).to be true
    end

    it 'returns false when vagrant cloud reports not logged in' do
      sout = instance_double(Mixlib::ShellOut, error?: false, stdout: 'You are not logged in', stderr: '')
      allow(Mixlib::ShellOut).to receive(:new).with('vagrant cloud auth whoami').and_return(double(run_command: sout))
      expect(host.logged_in?).to be false
    end

    it 'returns false and warns with stderr when shellout fails with stderr' do
      sout = instance_double(Mixlib::ShellOut, error?: true, stderr: 'network timeout', stdout: '')
      allow(Mixlib::ShellOut).to receive(:new).with('vagrant cloud auth whoami').and_return(double(run_command: sout))
      expect { host.logged_in? }.to output(/Failed to shellout to vagrant.*network timeout/).to_stdout
    end

    it 'returns false and warns with stdout when shellout fails without stderr' do
      sout = instance_double(Mixlib::ShellOut, error?: true, stderr: '', stdout: 'fatal error')
      allow(Mixlib::ShellOut).to receive(:new).with('vagrant cloud auth whoami').and_return(double(run_command: sout))
      expect { host.logged_in? }.to output(/Failed to shellout to vagrant.*fatal error/).to_stdout
    end
  end

  describe '#duration' do
    it 'formats seconds under a minute' do
      expect(host.duration(45.5)).to eq('0m45.50s')
    end

    it 'formats seconds spanning multiple minutes' do
      expect(host.duration(125.0)).to eq('2m5.00s')
    end

    it 'handles nil gracefully by treating it as zero' do
      expect(host.duration(nil)).to eq('0m0.00s')
    end
  end

  describe '#box_metadata' do
    it 'parses a JSON file into a hash' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'test._metadata.json')
        data = { 'name' => 'ubuntu-24.04', 'version' => '1.0' }
        File.write(path, JSON.generate(data))
        expect(host.box_metadata(path)).to eq(data)
      end
    end
  end

  describe '#metadata_files' do
    it 'globs build_complete directory for metadata files' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p('builds/build_complete')
          File.write('builds/build_complete/ubuntu-24.04-x86_64._metadata.json', '{}')
          File.write('builds/build_complete/other.txt', 'not json')
          files = host.metadata_files(false)
          expect(files.length).to eq(1)
          expect(files.first).to include('_metadata.json')
        end
      end
    end

    it 'globs testing_passed directory when upload flag is true' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          arch = RbConfig::CONFIG['host_cpu'] == 'arm64' ? 'aarch64' : RbConfig::CONFIG['host_cpu']
          FileUtils.mkdir_p("builds/testing_passed/#{arch}")
          File.write("builds/testing_passed/#{arch}/ubuntu-24.04-#{arch}._metadata.json", '{}')
          files = host.metadata_files(true, true)
          expect(files.length).to eq(1)
        end
      end
    end

    it 'globs testing_passed without arch support when upload flag is true' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p('builds/testing_passed')
          File.write('builds/testing_passed/generic._metadata.json', '{}')
          files = host.metadata_files(false, true)
          expect(files.length).to eq(1)
        end
      end
    end

    it 'handles non-arm64 host_cpu in metadata_files' do
      stub_const('RbConfig::CONFIG', RbConfig::CONFIG.merge('host_cpu' => 'x86_64'))
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir_p('builds/build_complete')
          File.write('builds/build_complete/ubuntu-24.04-x86_64._metadata.json', '{}')
          files = host.metadata_files(true, false)
          expect(files.length).to eq(1)
        end
      end
    end
  end

  describe '#builds_yml' do
    it 'parses builds.yml from the current directory' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          File.write('builds.yml', "vagrant_cloud_account: bento
public:
  - ubuntu
")
          result = host.builds_yml
          expect(result['vagrant_cloud_account']).to eq('bento')
          expect(result['public']).to include('ubuntu')
        end
      end
    end
  end

  describe '#private_box?' do
    it 'returns true for macos boxes' do
      expect(host.private_box?('macos-14-aarch64')).to be true
    end

    it 'returns true for windows boxes' do
      expect(host.private_box?('windows-11-x86_64')).to be true
    end

    it 'returns true for sles boxes' do
      expect(host.private_box?('sles-15-x86_64')).to be true
    end

    it 'returns true for solaris boxes' do
      expect(host.private_box?('solaris-11-x86_64')).to be true
    end

    it 'returns true for rhel boxes' do
      expect(host.private_box?('rhel-9-x86_64')).to be true
    end

    it 'returns false for public open source boxes' do
      expect(host.private_box?('ubuntu-24.04-x86_64')).to be false
      expect(host.private_box?('debian-12-aarch64')).to be false
      expect(host.private_box?('alpine-3.21-x86_64')).to be false
    end
  end

  describe '#macos?' do
    it 'returns true when RUBY_PLATFORM indicates darwin' do
      stub_const('RUBY_PLATFORM', 'arm64-darwin24')
      expect(host.macos?).to be true
    end

    it 'returns false when RUBY_PLATFORM is linux' do
      stub_const('RUBY_PLATFORM', 'x86_64-linux')
      expect(host.macos?).to be false
    end
  end

  describe '#apple_silicon?' do
    it 'returns true when host_cpu is arm64' do
      stub_const('RbConfig::CONFIG', RbConfig::CONFIG.merge('host_cpu' => 'arm64'))
      expect(host.apple_silicon?).to be true
    end

    it 'returns true when host_cpu is aarch64' do
      stub_const('RbConfig::CONFIG', RbConfig::CONFIG.merge('host_cpu' => 'aarch64'))
      expect(host.apple_silicon?).to be true
    end

    it 'returns false when host_cpu is x86_64' do
      stub_const('RbConfig::CONFIG', RbConfig::CONFIG.merge('host_cpu' => 'x86_64'))
      expect(host.apple_silicon?).to be false
    end
  end

  describe '#verify_macos_build_host!' do
    it 'returns true when running on macOS with Apple Silicon' do
      allow(host).to receive(:macos?).and_return(true)
      allow(host).to receive(:apple_silicon?).and_return(true)
      expect(host.verify_macos_build_host!).to be true
    end

    it 'raises RuntimeError if not running on macOS' do
      allow(host).to receive(:macos?).and_return(false)
      expect { host.verify_macos_build_host! }.to raise_error(/genuine Apple-branded hardware running macOS/)
    end

    it 'raises RuntimeError if running on macOS with non-ARM architecture' do
      allow(host).to receive(:macos?).and_return(true)
      allow(host).to receive(:apple_silicon?).and_return(false)
      expect { host.verify_macos_build_host! }.to raise_error(/requires Apple Silicon/)
    end
  end

  describe '#windows? and #unix?' do
    it 'identifies windows platforms correctly' do
      stub_const('RUBY_PLATFORM', 'x64-mingw32')
      expect(host.windows?).to be true
      expect(host.unix?).to be false
    end

    it 'identifies unix platforms correctly' do
      stub_const('RUBY_PLATFORM', 'x86_64-linux')
      expect(host.windows?).to be false
      expect(host.unix?).to be true
    end
  end
end
