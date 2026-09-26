# frozen_string_literal: true

#
# @file runner.rb
# @brief Packer build runner and orchestration engine for Bento
# @description
#   Parses template lists, runs packer initialization and plugin upgrades,
#   constructs parameterised packer build invocations, streams build output,
#   enforces legal and architecture prerequisites for macOS targets,
#   and writes build metadata records for completed boxes.
#

require 'English'
require 'bento/common'
require 'bento/buildmetadata'
require 'bento/providermetadata'
require 'bento/packerexec'
require 'mixlib/shellout'

#
# @class BuildRunner
# @description Manages Packer execution workflows across configured OS templates.
#
class BuildRunner
  include Common
  include PackerExec

  # @return [Array<String>] Template files to build.
  attr_reader :template_files
  # @return [Boolean] Whether in dry-run mode.
  attr_reader :dry_run
  # @return [Boolean] Whether debug mode is enabled.
  attr_reader :debug
  # @return [String, NilClass] Only filter for builder sources.
  attr_reader :only
  # @return [String, NilClass] Except filter for builder sources.
  attr_reader :except
  # @return [String, NilClass] Mirror URL override.
  attr_reader :mirror
  # @return [Boolean] Whether GUI mode is active (non-headless).
  attr_reader :headed
  # @return [Boolean] Whether to run builds sequentially.
  attr_reader :single
  # @return [Array<String>] Accumulated build error template names.
  attr_reader :errors
  # @return [String, NilClass] On-error Packer strategy (e.g. 'cleanup', 'abort', 'ask').
  attr_reader :on_error
  # @return [String, NilClass] Version string override.
  attr_reader :override_version
  # @return [String] Timestamp string for the current build session.
  attr_reader :build_timestamp
  # @return [Integer, NilClass] CPU core override.
  attr_reader :cpus
  # @return [Integer, NilClass] RAM memory override in MB.
  attr_reader :mem
  # @return [Boolean] Whether to generate metadata without executing Packer.
  attr_reader :metadata_only
  # @return [Array<String>, NilClass] Additional Packer variable overrides.
  attr_reader :vars
  # @return [Array<String>, NilClass] Additional Packer variable file paths.
  attr_reader :var_files
  # @return [String, NilClass] Last executed Packer command.
  attr_reader :pkr_cmd

  #
  # Initializes a new BuildRunner instance.
  #
  # @param [OpenStruct, Hash] opts Command-line flags and runtime options.
  #
  def initialize(opts)
    @template_files = opts.template_files
    @config = opts.config ||= false
    @dry_run = opts.dry_run
    @metadata_only = opts.metadata_only
    @debug = opts.debug
    @on_error = opts.on_error ||= nil
    @only = opts.only ||= nil
    @except = opts.except
    @mirror = opts.mirror
    @headed = opts.headed ||= false
    @single = opts.single ||= false
    @override_version = opts.override_version
    @build_timestamp = Time.now.gmtime.strftime('%Y%m%d%H%M%S')
    @cpus = opts.cpus
    @mem = opts.mem
    @vars = opts.vars&.split(',')
    @var_files = opts.var_files&.split(',')
    @errors = []
    @pkr_cmd = nil
  end

  #
  # Executes the Packer build process across all specified templates.
  # Enforces legal compliance for macOS guests prior to execution.
  #
  # @return [void]
  # @raise [RuntimeError] If any template build fails.
  #
  def start
    templates = template_files
    if templates.any? { |t| t.include?('macos') }
      verify_macos_build_host!
    end

    banner('Starting build for templates:')
    banner('Installing packer plugins') unless dry_run || metadata_only
    shellout("packer init -upgrade #{File.absolute_path("#{File.dirname(templates.first)}/../../packer_templates")}") unless dry_run || metadata_only
    templates.each { |t| puts "- #{t}" }
    time = Benchmark.measure do
      templates.each { |template| build(template) }
    end
    banner("Build finished in #{duration(time.real)}.")
    unless errors.empty?
      raise("Failed Builds:
#{errors.join("
")}
exited #{$CHILD_STATUS}")
    end
  end

  private

  #
  # Builds a single template target within its relative directory.
  #
  # @param [String] file Path to the template pkrvars file.
  # @return [void]
  #
  def build(file)
    bento_dir = Dir.pwd
    dir = File.dirname(file)
    template = File.basename(file)
    cmd = nil
    Dir.chdir dir
    for_packer_run_with(template) do |md_file, _var_file|
      cmd = Mixlib::ShellOut.new(packer_build_cmd(template, md_file.path).join(' '))
      cmd.live_stream = $stdout
      cmd.timeout = 28800
      @pkr_cmd = cmd.command
      banner("[#{template}] Building: '#{cmd.command}'")
      time = Benchmark.measure do
        cmd.run_command
      end
      if Dir.glob("../../builds/build_complete/#{template.split('-')[0...-1].join('-')}*-#{template.split('-').last}.*.box").empty?
        banner('Not writing metadata file since no boxes exist')
      else
        write_final_metadata(template, time.real.ceil)
      end
      banner("[#{template}] Finished building in #{duration(time.real)}.")
    end
    Dir.chdir(bento_dir)
    if cmd.error?
      cmd.stderr
      errors << template
    end
  end

  #
  # Constructs the Packer build command array with all configured options and flags.
  #
  # @param [String] template Base name of the template.
  # @param [String] _var_file Temporary variable file path.
  # @return [Array<String>] Command line arguments for Packer.
  #
  def packer_build_cmd(template, _var_file)
    pkrvars = "#{template}.pkrvars.hcl"
    cmd = %W(packer build -timestamp-ui -force -var-file=#{File.absolute_path(pkrvars)} #{File.absolute_path('../../packer_templates')})
    if vars
      vars.each do |var|
        cmd.insert(4, "-var #{var}")
      end
    end
    if var_files
      var_files.each do |var_file|
        cmd.insert(5, "-var-file=#{var_file}") if File.exist?(var_file)
      end
    end
    cmd.insert(4, "-only=#{only}") if only
    cmd.insert(4, "-except=#{except}") if except
    cmd.insert(4, "-var 'sources_enabled=#{only.split(',').inspect}'") if only
    cmd.insert(4, "-var cpus=#{cpus}") if cpus
    cmd.insert(4, "-var memory=#{mem}") if mem
    cmd.insert(4, '-var headless=false') if headed
    cmd.insert(2, '-parallel=false') if single
    cmd.insert(2, '-debug') if debug
    cmd.insert(2, "-on-error=#{on_error}") if on_error
    cmd.insert(0, 'echo') if dry_run || metadata_only
    cmd
  end

  #
  # Writes the final build metadata JSON file upon successful box creation.
  #
  # @param [String] template Base name of the template.
  # @param [Integer] buildtime Total elapsed build time in seconds.
  # @return [void]
  #
  def write_final_metadata(template, buildtime)
    md = BuildMetadata.new(template, build_timestamp, override_version, pkr_cmd).read
    path = File.join('../../builds/build_complete')
    filename = File.join(path, "#{md[:template]}._metadata.json")
    md[:providers] = ProviderMetadata.new(path, md[:template]).read
    md[:providers].each do |p|
      p[:build_time] = buildtime
      p[:build_cpus] = cpus if cpus
      p[:build_mem] = mem if mem
    end

    if dry_run
      banner("(Dry run) Metadata file would be written to #{filename} with content similar to:")
      puts JSON.pretty_generate(md)
    else
      File.binwrite(filename, JSON.pretty_generate(md))
    end
  end
end
