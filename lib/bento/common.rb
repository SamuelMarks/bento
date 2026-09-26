# frozen_string_literal: true

#
# @file common.rb
# @brief Common shared utility methods and environment inspection helpers for Bento
# @description
#   Provides cross-cutting helper methods for console banner output, timing,
#   Vagrant Cloud authentication checks, metadata parsing, YAML configuration loading,
#   host platform inspection, and proprietary OS classification.
#

require 'benchmark'
require 'fileutils'
require 'json'
require 'tempfile'
require 'yaml'
require 'mixlib/shellout'

MEGABYTE = 1024.0 * 1024.0

#
# @module Common
# @description Shared helper module mixed into Bento runner, build, and metadata classes.
#
module Common
  #
  # Prints a banner-formatted notification message.
  #
  # @param [String] msg The text message to display.
  # @return [void]
  #
  def banner(msg)
    puts "==> #{msg}"
  end

  #
  # Prints an indented informational message.
  #
  # @param [String] msg The text message to display.
  # @return [void]
  #
  def info(msg)
    puts "    #{msg}"
  end

  #
  # Shells out to execute an external command with live streaming and error checking.
  #
  # @param [String] cmd Shell command string to execute.
  # @return [Mixlib::ShellOut] ShellOut execution instance.
  # @raise [Mixlib::ShellOut::ShellCommandFailed] If command returns non-zero.
  #
  def shellout(cmd)
    info "Shelling out to run #{cmd}"
    sout = Mixlib::ShellOut.new(cmd)
    sout.live_stream = $stdout
    sout.run_command
    sout.error! # fail hard if the cmd fails
  end

  #
  # Prints a warning message prefixed with '>>>'.
  #
  # @param [String] msg The warning text to display.
  # @return [void]
  #
  def warn(msg)
    puts ">>> #{msg}"
  end

  #
  # Shells out to vagrant CLI to check authentication status with Vagrant Cloud.
  #
  # @return [Boolean] True if currently authenticated, false otherwise.
  #
  def logged_in?
    # rubocop:disable Modernize/ShellOutHelper
    shellout = Mixlib::ShellOut.new('vagrant cloud auth whoami').run_command
    # rubocop:enable Modernize/ShellOutHelper

    if shellout.error?
      error_output = !shellout.stderr.empty? ? shellout.stderr : shellout.stdout
      warn("Failed to shellout to vagrant to check the login status. Error: #{error_output}")
      return false
    end

    return true if shellout.stdout.match?(/Currently logged in/)

    false
  end

  #
  # Formats elapsed time in seconds into minutes and hundredths of seconds.
  #
  # @param [Numeric, NilClass] total Total elapsed time in seconds.
  # @return [String] Formatted duration string (e.g., '2m5.00s').
  #
  def duration(total)
    total = 0 if total.nil?
    minutes = (total / 60).to_i
    seconds = (total - (minutes * 60))
    format('%dm%.2fs', minutes, seconds)
  end

  #
  # Parses a JSON box metadata file into a Ruby Hash.
  #
  # @param [String] metadata_file Path to the metadata JSON file.
  # @return [Hash] Parsed metadata contents.
  #
  def box_metadata(metadata_file)
    JSON.parse(File.read(metadata_file))
  end

  #
  # Discovers build metadata JSON files matching host architecture.
  #
  # @param [Boolean] arch_support Whether to scope file patterns by architecture suffix.
  # @param [Boolean] upload Whether to look in testing_passed directory rather than build_complete.
  # @return [Array<String>] List of matching metadata file paths.
  #
  def metadata_files(arch_support = false, upload = false)
    arch = if RbConfig::CONFIG['host_cpu'] == 'arm64'
             'aarch64'
           else
             RbConfig::CONFIG['host_cpu']
           end
    glob = if upload
             "builds/testing_passed/**/*#{"-#{arch}" if arch_support}._metadata.json"
           else
             "builds/build_complete/*#{"-#{arch}" if arch_support}._metadata.json"
           end
    @metadata_files ||= Dir.glob(glob)
  end

  #
  # Loads repository build configuration from builds.yml.
  #
  # @return [Hash] Parsed YAML configuration.
  #
  def builds_yml
    YAML.load_file('builds.yml')
  end

  #
  # Determines if a given box name belongs to a proprietary/restricted OS.
  #
  # @param [String] boxname Target box basename.
  # @return [Boolean] True if the OS is proprietary (e.g., macOS, Windows), false otherwise.
  #
  def private_box?(boxname)
    proprietary_os_list = %w(macos windows sles solaris rhel)
    proprietary_os_list.any? { |p| boxname.include?(p) }
  end

  #
  # Checks whether the current host platform is macOS (Darwin).
  #
  # @return [Boolean] True if running on macOS.
  #
  def macos?
    !!(RUBY_PLATFORM =~ /darwin/)
  end

  #
  # Checks whether the current host CPU is Apple Silicon / ARM64.
  #
  # @return [Boolean] True if running on an ARM64/Apple Silicon architecture.
  #
  def apple_silicon?
    host_cpu = RbConfig::CONFIG['host_cpu']
    host_cpu == 'arm64' || host_cpu == 'aarch64'
  end

  #
  # Enforces that macOS virtualization builds only execute on genuine Apple-branded hardware
  # running macOS on Apple Silicon architecture, as required by Apple SLA Section 2.B(iii).
  #
  # @return [Boolean] True if host meets all legal and hardware requirements.
  # @raise [RuntimeError] If host is not macOS or not running on Apple Silicon.
  #
  def verify_macos_build_host!
    unless macos?
      raise 'macOS virtualization builds legally and technically require genuine Apple-branded hardware running macOS.'
    end

    unless apple_silicon?
      raise 'Modern macOS virtualization in Bento requires Apple Silicon (aarch64 / arm64) hardware.'
    end

    true
  end

  #
  # Checks whether the current host platform is Unix-like (non-Windows).
  #
  # @return [Boolean] True if running on Unix-like platform.
  #
  def unix?
    !windows?
  end

  #
  # Checks whether the current host platform is Microsoft Windows.
  #
  # @return [Boolean] True if running on Windows.
  #
  def windows?
    !!(RUBY_PLATFORM =~ /mswin|mingw|windows/)
  end
end
