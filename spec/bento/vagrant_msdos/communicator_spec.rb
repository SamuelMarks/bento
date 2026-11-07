# frozen_string_literal: true

require 'spec_helper'
require 'bento/vagrant_msdos'

RSpec.describe Bento::VagrantMsdos::Communicator do
  subject(:communicator) { described_class.new(machine) }

  let(:msdos_cfg) { Bento::VagrantMsdos::Config.new }
  let(:vm_config) { double('vm_config', msdos: msdos_cfg) }
  let(:machine) { double('machine', config: vm_config) }
  let(:mock_socket) { double('socket', closed?: false, flush: nil, close: nil) }
  let(:crlf) { described_class::CRLF }
  let(:bs) { described_class::BS }

  before do
    allow(TCPSocket).to receive(:new).and_return(mock_socket)
    allow(SecureRandom).to receive(:hex).with(4).and_return('abcd1234')
  end

  describe '#msdos_config' do
    it 'finalizes and returns machine.config.msdos when present' do
      cfg = communicator.msdos_config
      expect(cfg.host).to eq('127.0.0.1')
      expect(cfg.port).to eq(2324)
    end

    it 'creates a finalized fallback Config when machine has no config.msdos' do
      bare_machine = double('bare_machine')
      comm = described_class.new(bare_machine)
      cfg = comm.msdos_config
      expect(cfg).to be_a(Bento::VagrantMsdos::Config)
      expect(cfg.port).to eq(2324)
    end
  end

  describe '.match?' do
    it 'returns true when the machine matches the DOS guest/communicator' do
      expect(described_class.match?(nil)).to be(false)
    end
  end

  describe '#execute and #sudo' do
    it 'frames commands, strips C:\> and C> prompts, yields stdout, and returns %ERRORLEVEL%' do
      allow(mock_socket).to receive(:write)
      response = [
        "C:#{bs}>ECHO ===START_ABCD1234===",
        '===START_ABCD1234===',
        'C>VER',
        'MS-DOS Version 4.00',
        "C:#{bs}>ECHO ===EXIT_ABCD1234:0===",
        '===EXIT_ABCD1234:0===',
      ].join(crlf)
      allow(mock_socket).to receive(:readpartial).and_return(response)

      yielded = []
      code = communicator.execute('VER') do |type, data|
        yielded << [type, data]
      end

      expect(code).to eq(0)
      expect(yielded).to eq([[:stdout, "MS-DOS Version 4.00\n"]])
      expect(communicator.sudo('VER')).to eq(0)
    end

    it 'handles unexpanded %ERRORLEVEL% from MS-DOS 1.25 / 2.0 COMMAND.COM' do
      allow(mock_socket).to receive(:write)
      ok_resp = "===START_ABCD1234===#{crlf}A>VER#{crlf}MS-DOS Version 1.25#{crlf}===EXIT_ABCD1234:%ERRORLEVEL%===#{crlf}"
      allow(mock_socket).to receive(:readpartial).and_return(ok_resp)
      expect(communicator.execute('VER')).to eq(0)

      err_resp = "===START_ABCD1234===#{crlf}Bad command or file name#{crlf}===EXIT_ABCD1234:%ERRORLEVEL%===#{crlf}"
      allow(mock_socket).to receive(:readpartial).and_return(err_resp)
      expect(communicator.execute('BADCMD', error_check: false)).to eq(1)
    end

    it 'raises CommunicatorError when exit code is non-zero and error_check is true' do
      allow(mock_socket).to receive(:write)
      response = "===START_ABCD1234===#{crlf}Bad command#{crlf}===EXIT_ABCD1234:3===#{crlf}"
      allow(mock_socket).to receive(:readpartial).and_return(response)

      expect do
        communicator.execute('BADCMD')
      end.to raise_error(Bento::VagrantMsdos::CommunicatorError, /ERRORLEVEL 3/)
    end

    it 'returns non-zero exit code without raising when error_check is false' do
      allow(mock_socket).to receive(:write)
      response = "===START_ABCD1234===#{crlf}===EXIT_ABCD1234:7===#{crlf}"
      allow(mock_socket).to receive(:readpartial).and_return(response)

      expect(communicator.execute('FAILCMD', error_check: false)).to eq(7)
    end

    it 'raises CommunicatorError on EOFError before exit marker arrives' do
      allow(mock_socket).to receive(:write)
      allow(mock_socket).to receive(:readpartial).and_raise(EOFError)

      expect do
        communicator.execute('VER')
      end.to raise_error(Bento::VagrantMsdos::CommunicatorError, /Connection closed/)
    end

    it 'supports UNIXSocket when transport is :unix_socket' do
      msdos_cfg.finalize!
      msdos_cfg.transport = :unix_socket
      msdos_cfg.serial_socket = '/tmp/test_msdos.sock'
      expect(UNIXSocket).to receive(:new).with('/tmp/test_msdos.sock').and_return(mock_socket)
      allow(mock_socket).to receive(:write)
      allow(mock_socket).to receive(:readpartial).and_return("===START_ABCD1234===#{crlf}===EXIT_ABCD1234:0===#{crlf}")

      expect(communicator.execute('VER')).to eq(0)
    end
  end

  describe '#ready? and #wait_for_ready' do
    it 'returns true when ping marker is echoed back' do
      allow(mock_socket).to receive(:write)
      allow(mock_socket).to receive(:readpartial).and_return(
        "===START_ABCD1234===#{crlf}===VAGRANT_PING===#{crlf}===EXIT_ABCD1234:0===#{crlf}"
      )
      expect(communicator.ready?).to be(true)
      expect(communicator.wait_for_ready(1)).to be(true)
    end

    it 'returns false when socket raises an exception or times out' do
      allow(mock_socket).to receive(:write).and_raise(Errno::ECONNREFUSED)
      expect(communicator.ready?).to be(false)
      expect(communicator.wait_for_ready(0.01)).to be(false)
    end
  end

  describe '#reset!' do
    it 'closes existing socket (or skips close if already closed) and opens a new socket' do
      allow(mock_socket).to receive(:write)
      allow(mock_socket).to receive(:readpartial).and_return("===START_ABCD1234===#{crlf}===EXIT_ABCD1234:0===#{crlf}")
      communicator.execute('VER')
      expect(mock_socket).to receive(:close)
      expect(communicator.reset!).to be_nil

      allow(mock_socket).to receive(:closed?).and_return(true)
      expect(communicator.reset!).to be_nil
    end
  end

  describe '#test' do
    it 'returns true on exit code 0 and false on non-zero or exception' do
      allow(communicator).to receive(:execute).and_return(0)
      expect(communicator.test('VER')).to be(true)

      allow(communicator).to receive(:execute).and_return(1)
      expect(communicator.test('FAIL')).to be(false)

      allow(communicator).to receive(:execute).and_raise(StandardError, 'boom')
      expect(communicator.test('ERR')).to be(false)
    end
  end

  describe '#align_mz_header_for_dos125 and #fast_upload_file!' do
    it 'aligns MZ headers to 32 paragraphs (512 bytes) and strips trailing debug info on MS-DOS 1.25' do
      non_mz = 'PLAIN_COM_BINARY_DATA'
      expect(communicator.align_mz_header_for_dos125(non_mz)).to eq(non_mz)

      msdos_cfg.dos_version = '1.25'
      msdos_cfg.finalize!
      expect(communicator.align_mz_header_for_dos125('SHORT')).to eq('SHORT')
      expect(communicator.align_mz_header_for_dos125('NO_MZ_HEADER_32_BYTES_LONG_12345')).to eq('NO_MZ_HEADER_32_BYTES_LONG_12345')

      # Already 32-paragraph aligned MZ with e_cblp == 0 (full 512-byte page) and trailing DWARF bytes
      aligned_hdr = 'MZ'.b + [0, 2, 0, 32].pack('v4') + ("\x00".b * 502)
      aligned_body = "\xB8\x00\x4C\xCD\x21".b + ("\x90".b * 507)
      aligned_exe = aligned_hdr + aligned_body + 'DWARF_TRAILING_BYTES'.b
      res_aligned = communicator.align_mz_header_for_dos125(aligned_exe)
      expect(res_aligned.bytesize).to eq(1024)
      expect(res_aligned[8, 2].unpack1('v')).to eq(32)

      # Unaligned MZ (e_cparhdr = 4 paragraphs = 64 bytes, e_cblp = 80, e_cp = 1) with trailing debug bytes
      unaligned_hdr = 'MZ'.b + [80, 1, 0, 4].pack('v4') + ("\x00".b * 54)
      code_body = "\xBA\x10\x00\xB4\x09\xCD\x21\xB8\x00\x4C\xCD\x21\x90\x90\x90\x90".b
      unaligned_exe = unaligned_hdr + code_body + 'EXTRA_DEBUG_DATA'.b
      res_padded = communicator.align_mz_header_for_dos125(unaligned_exe)
      expect(res_padded[8, 2].unpack1('v')).to eq(32)
      expect(res_padded.bytesize).to eq(512 + 16)
      expect(res_padded[512, 16]).to eq(code_body)
      expect(res_padded[2, 2].unpack1('v')).to eq(16)
      expect(res_padded[4, 2].unpack1('v')).to eq(2)

      # Already 32-paragraph aligned MZ with exact load_limit == bin.bytesize (no trailing bytes)
      exact_aligned = aligned_hdr + aligned_body
      expect(communicator.align_mz_header_for_dos125(exact_aligned).bytesize).to eq(1024)

      # Edge case: e_cp == 0 and old_hdr_bytes > bin.bytesize
      malformed_mz = 'MZ'.b + [0, 0, 0, 10].pack('v4') + ("\x00".b * 20)
      expect(communicator.align_mz_header_for_dos125(malformed_mz)).to eq(malformed_mz)
    end

    it 'raises CommunicatorError when source file does not exist' do
      expect do
        communicator.fast_upload_file!('/nonexistent/test.exe', "C:#{bs}TEST.EXE")
      end.to raise_error(Bento::VagrantMsdos::CommunicatorError, /does not exist/)
    end

    it 'streams Base64 payload to SERGET.COM in both hierarchical (v2.0/v4.0) and flat (v1.25) modes' do
      Dir.mktmpdir do |tmpdir|
        src = File.join(tmpdir, 'test.exe')
        File.binwrite(src, 'MZ_TEST_BINARY')

        allow(mock_socket).to receive(:write)
        chunks_v4 = ['wait...', "===SERGET_RDY===#{crlf}", 'writing...', "===EXIT_ABCD1234:0===#{crlf}"]
        allow(mock_socket).to receive(:readpartial) { chunks_v4.shift || '===EXIT_ABCD1234:0===' }
        expect(communicator.fast_upload_file!(src, "C:#{bs}TEMP#{bs}TEST.EXE")).to be(true)

        msdos_cfg.dos_version = '1.25'
        msdos_cfg.finalize!
        chunks_v1 = ["===SERGET_RDY===#{crlf}", "===EXIT_ABCD1234:0===#{crlf}"]
        allow(mock_socket).to receive(:readpartial) { chunks_v1.shift || '===EXIT_ABCD1234:0===' }
        expect(communicator.fast_upload_file!(src, "C:#{bs}TEST.EXE")).to be(true)
      end
    end
  end

  describe '#upload, #download, and #normalize_dos_path' do
    it 'raises CommunicatorError when source path does not exist' do
      expect do
        communicator.upload('/nonexistent/file/path.txt', "D:#{bs}TEST.TXT")
      end.to raise_error(Bento::VagrantMsdos::CommunicatorError, /does not exist/)
    end

    it 'uploads files and directories in both hierarchical (v2.0/v4.0) and flat (v1.25) modes' do
      Dir.mktmpdir do |tmpdir|
        sub = File.join(tmpdir, 'sub')
        FileUtils.mkdir_p(sub)
        single_file = File.join(tmpdir, 'hello.asm')
        File.write(single_file, 'MOV AX, 4C00H')
        File.write(File.join(sub, 'nested.inc'), ' NOP')

        executed_cmds = []
        allow(communicator).to receive(:execute) do |cmd, _opts|
          executed_cmds << cmd
          0
        end

        expect(communicator.upload(single_file, "D:#{bs}HELLO.ASM")).to be(true)
        expect(communicator.upload(tmpdir, '/vagrant')).to be(true)
        expect(communicator.upload(tmpdir, "D:#{bs}")).to be(true)
        expect(executed_cmds.join("\n")).to include("C:#{bs}BENTO#{bs}B64DEC.COM")
        expect(executed_cmds.join("\n")).to include("D:#{bs}sub")

        # Now test MS-DOS 1.25 flat mode (supports_subdirectories? == false)
        msdos_cfg.dos_version = '1.25'
        msdos_cfg.finalize!
        flat_cmds = []
        allow(communicator).to receive(:execute) do |cmd, _opts|
          flat_cmds << cmd
          0
        end
        expect(communicator.normalize_dos_path('/vagrant/sub/NESTED.INC')).to eq("D:#{bs}NESTED.INC")
        expect(communicator.upload(tmpdir, '/vagrant')).to be(true)
        expect(flat_cmds.join("\n")).to include("C:#{bs}B64DEC.COM")
        expect(flat_cmds.join("\n")).not_to include('MKDIR')
      end
    end

    it 'downloads a file with Base64 markers and without markers in both v4.0 and v1.25 modes' do
      Dir.mktmpdir do |tmpdir|
        dest1 = File.join(tmpdir, 'out1.bin')
        allow(communicator).to receive(:execute) do |_cmd, _opts, &blk|
          blk.call(:stdout, "===B64_START===
#{Base64.strict_encode64('MSDOS_BINARY_DATA')}
===B64_END===
")
          0
        end
        expect(communicator.download('/vagrant/OUT1.BIN', dest1)).to be(true)
        expect(File.binread(dest1)).to eq('MSDOS_BINARY_DATA')

        msdos_cfg.dos_version = '1.25'
        msdos_cfg.finalize!
        dest2 = File.join(tmpdir, 'out2.txt')
        allow(communicator).to receive(:execute) do |_cmd, _opts, &blk|
          blk.call(:stdout, "PLAIN_TEXT_OUTPUT\n")
          0
        end
        expect(communicator.download("D:#{bs}OUT2.TXT", dest2)).to be(true)
        expect(File.read(dest2)).to eq('PLAIN_TEXT_OUTPUT')
      end
    end
  end

  describe '#strip_telnet_iac' do
    it 'strips IAC DO_OPT/WILL/NEG_REFUSE triplets with and without socket, replies NEG_REFUSE/NEG_DENY, and unescapes double IAC' do
      reply_io = StringIO.new
      raw = [
        described_class::IAC, described_class::DO_OPT, 1,
        described_class::IAC, described_class::WILL, 3,
        described_class::IAC, described_class::NEG_REFUSE, 5,
        described_class::IAC, described_class::IAC
      ].pack('C*') + 'HELLO' + [described_class::IAC].pack('C*')

      cleaned = communicator.strip_telnet_iac(raw, reply_io)
      expect(cleaned.bytes).to include(255)
      expect(cleaned).to end_with('HELLO')
      expect(reply_io.string.bytes).to eq([
                                            described_class::IAC, described_class::NEG_REFUSE, 1,
                                            described_class::IAC, described_class::NEG_DENY, 3
                                          ])

      cleaned_no_sock = communicator.strip_telnet_iac(raw, nil)
      expect(cleaned_no_sock).to end_with('HELLO')
    end

    it 'handles multi-chunk socket reads and reset! when socket is nil' do
      expect(communicator.reset!).to be_nil
      allow(mock_socket).to receive(:write)
      chunks = [
        "Pre-start line#{crlf}===START_ABCD1234===#{crlf}",
        "Output line#{crlf}===EXIT_ABCD1234:0===#{crlf}Post-exit line#{crlf}",
      ]
      allow(mock_socket).to receive(:readpartial) { chunks.shift || raise(EOFError) }
      expect(communicator.execute('VER')).to eq(0)
    end

    it 'verifies 16-bit 8086 B64ENC.COM, B64DEC.COM, SERINIT.COM, and SHUTDOWN.COM machine code and round-trip binary SHA-256' do
      scripts_dir = File.expand_path('../../../packer_templates/scripts/msdos', __dir__)
      b64enc = File.binread(File.join(scripts_dir, 'B64ENC.COM'))
      b64dec = File.binread(File.join(scripts_dir, 'B64DEC.COM'))
      serinit = File.binread(File.join(scripts_dir, 'SERINIT.COM'))
      shutdown = File.binread(File.join(scripts_dir, 'SHUTDOWN.COM'))

      expect(b64enc.bytesize).to eq(460)
      expect(b64enc).to include('===B64_START===')
      expect(b64enc).to include('===B64_END===')
      expect(b64enc.getbyte(0x37)).to eq(0xEB)
      expect(b64enc[0x8D, 2]).to eq("\x8A\x1C".b)

      expect(b64dec.bytesize).to eq(459)
      expect(b64dec[0xA4, 2]).to eq("\xEB\x22".b)
      expect(b64dec[0xB2, 2]).to eq("\xEB\x14".b)
      expect(serinit.bytesize).to eq(224)
      expect(shutdown.bytesize).to eq(54)

      asm_dir = File.join(scripts_dir, 'asm')
      Dir.mktmpdir do |asm_tmp|
        {
          'serget_com.asm' => [248, '===SERGET_RDY==='],
          'echo_com.asm' => [105, '%ERRORLEVEL%'],
          'ver_com.asm' => [33, 'MS-DOS Version 1.25'],
          'io_msdos125.asm' => [4096, 'COMMAND COM'],
          'io_msdos20.asm' => [4096, 'COMMAND.COM'],
        }.each do |asm_file, (expected_len, marker)|
          out_bin = File.join(asm_tmp, "#{asm_file}.bin")
          expect(system('nasm', '-f', 'bin', File.join(asm_dir, asm_file), '-o', out_bin)).to be(true)
          raw_bin = File.binread(out_bin)
          expect(raw_bin.bytesize).to eq(expected_len)
          expect(raw_bin).to include(marker.b)
        end

        io125 = File.binread(File.join(asm_tmp, 'io_msdos125.asm.bin'))
        # Verify INT 21h entry point at 0x0484 handles AH=35h (preserving AX) and AH=5Bh, and dispatcher handles AH=26h
        expect(io125[0x0484, 3]).to eq("\x80\xFC\x35".b)
        expect(io125[0x0499, 3]).to eq("\x80\xFC\x5B".b)
        expect(io125[0x0760, 3]).to eq("\x80\xFC\x26".b)
      end

      Dir.mktmpdir do |tmpdir|
        src_com = File.join(tmpdir, 'TEST.COM')
        dst_com = File.join(tmpdir, 'DL.COM')
        File.binwrite(src_com, shutdown)
        orig_sha = Digest::SHA256.file(src_com).hexdigest

        guest_b64_lines = []
        allow(communicator).to receive(:execute) do |cmd, _opts, &blk|
          if cmd.start_with?('ECHO ') && cmd.include?('>>')
            guest_b64_lines << cmd.sub(/\AECHO /, '').sub(/>>.*\z/, '')
          elsif cmd.include?('B64ENC.COM') && blk
            blk.call(:stdout, "===B64_START===\r\n#{guest_b64_lines.join("\r\n")}\r\n===B64_END===\r\n")
          elsif cmd.end_with?('TEST.COM') && blk
            blk.call(:stdout, "MS-DOS Version 4.00\r\n")
          end
          0
        end

        expect(communicator.upload(src_com, "C:#{bs}TEMP#{bs}TEST.COM")).to be(true)
        exec_out = +''
        expect(communicator.execute("C:#{bs}TEMP#{bs}TEST.COM") { |_, d| exec_out << d }).to eq(0)
        expect(exec_out).to include('MS-DOS Version 4.00')
        expect(communicator.download("C:#{bs}TEMP#{bs}TEST.COM", dst_com)).to be(true)
        expect(Digest::SHA256.file(dst_com).hexdigest).to eq(orig_sha)
      end
    end
  end
end
