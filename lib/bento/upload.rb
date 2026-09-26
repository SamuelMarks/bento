# frozen_string_literal: true

#
# @file upload.rb
# @brief Vagrant Cloud upload orchestrator for Bento boxes
# @description
#   Parses build metadata files for completed and tested boxes, validates authentication
#   against Vagrant Cloud, enforces restrictions against uploading proprietary operating
#   systems (including macOS and Windows), publishes release artifacts, and manages slug aliases.
#

require 'bento/common'

#
# @class UploadRunner
# @description Coordinates publishing of tested Vagrant box images to Vagrant Cloud.
#
class UploadRunner
  include Common

  # @return [String, NilClass] Specific metadata file path to upload, if specified.
  attr_reader :md_json

  #
  # Initializes a new UploadRunner instance.
  #
  # @param [OpenStruct, Hash] opts Command line and configuration options.
  #
  def initialize(opts)
    @md_json = opts.md_json
  end

  #
  # Validates that the user is currently authenticated to Vagrant Cloud, issuing a warning if not.
  #
  # @return [void]
  #
  def error_unless_logged_in
    warn("You cannot upload files to vagrant cloud unless the vagrant CLI is logged in. Run 'vagrant cloud auth login' first.") unless logged_in?
  end

  #
  # Initiates the upload process for all qualified box metadata files.
  #
  # @return [void]
  #
  def start
    error_unless_logged_in

    banner('Starting uploads...')
    time = Benchmark.measure do
      files = md_json ? [md_json] : metadata_files(false, true)
      files.each do |md_file|
        upload_box(md_file)
      end
    end
    banner("Uploads finished in #{duration(time.real)}.")
  end

  #
  # Uploads all provider boxes defined in the given metadata file to Vagrant Cloud.
  # Rejects proprietary operating systems (such as macOS) to comply with distribution licenses.
  #
  # @param [String] md_file The path to the metadata file.
  # @return [void]
  # @raise [RuntimeError] If the architecture in the metadata is unrecognized.
  #
  def upload_box(md_file)
    md_data = box_metadata(md_file)
    if private_box?(md_data['box_basename'])
      warn("Refusing to upload proprietary / restricted OS box '#{md_data['box_basename']}' (matches proprietary list: macOS, Windows, SLES, Solaris, RHEL). Skipping!")
      return
    end

    bento_dir = Dir.pwd
    build_dir = File.join(bento_dir, 'builds')
    test_passed_dir = File.join(build_dir, 'testing_passed', md_data['arch'])
    uploaded_dir = File.join(build_dir, 'uploaded', md_data['arch'])
    arch = case md_data['arch']
           when 'x86_64', 'amd64'
             'amd64'
           when 'aarch64', 'arm64'
             'arm64'
           else
             raise "Unknown arch #{md_data.inspect}"
           end
    md_data['providers'].each do |provider|
      if File.exist?(File.join(test_passed_dir, provider['file']))
        puts ''
        banner("Uploading #{builds_yml['vagrant_cloud_account']}/#{md_data['box_basename']} version:#{md_data['version']} provider:#{provider['name']} arch:#{arch}...")
        upload_cmd = "vagrant cloud publish --architecture #{arch} #{default_arch(arch)} --no-direct-upload #{builds_yml['vagrant_cloud_account']}/#{md_data['box_basename']} #{md_data['version']} #{provider['name']} #{test_passed_dir}/#{provider['file']} --description '#{box_desc(md_data['box_basename'])}' --short-description '#{box_desc(md_data['box_basename'])}' --version-description '#{ver_desc(md_data)}' --force --release #{public_private_box(md_data['box_basename'])}"
        shellout(upload_cmd)

        slug_name = lookup_slug(md_data['name'])
        if slug_name
          puts ''
          banner("Uploading slug #{builds_yml['vagrant_cloud_account']}/#{slug_name} from #{md_data['box_basename']} version:#{md_data['version']} provider:#{provider['name']} arch:#{arch}...")
          upload_cmd = "vagrant cloud publish --architecture #{arch} --no-direct-upload #{builds_yml['vagrant_cloud_account']}/#{slug_name} #{md_data['version']} #{provider['name']} #{test_passed_dir}/#{provider['file']} --description '#{slug_desc(slug_name)}' --short-description '#{box_desc(slug_name)}' --version-description '#{ver_desc(md_data)}' --force --release  #{public_private_box(md_data['box_basename'])}"
          shellout(upload_cmd)
        end

        # move the box file to the completed directory
        FileUtils.mkdir_p(uploaded_dir) unless File.exist?(uploaded_dir)
        FileUtils.mv(File.join(test_passed_dir, provider['file']), File.join(uploaded_dir, provider['file']))
      else # box in metadata isn't on disk
        warn "The #{provider['name']} box defined in the metadata file #{md_file} does not exist at #{test_passed_dir}/#{provider['file']}. Skipping!"
      end
    end

    if Dir.glob("#{test_passed_dir}/#{@boxname}-#{md_data['arch']}.*.box").empty?
      # move the metadata file to the completed directory
      FileUtils.mkdir_p(uploaded_dir) unless File.exist?(uploaded_dir)
      FileUtils.mv(md_file, File.join(uploaded_dir, File.basename(md_file)))
    end
  end

  #
  # Resolves a box name to its corresponding versioned or 'latest' slug alias.
  #
  # @param [String] name Box name identifier.
  # @return [String, NilClass] Matching slug identifier, or nil if no slug configured.
  #
  def lookup_slug(name)
    builds_yml['slugs'].each do |slug|
      return slug if name.start_with?(slug)
      next unless slug.end_with?('latest')

      box_name = slug.split('-').first
      box_version = Dir.glob("os_pkrvars/#{box_name}/**/*.pkrvars.hcl").map do |boxes|
        File.basename(boxes).split('-')[1].to_i
      end
      latest = box_version.uniq.max { |a, b| a <=> b }
      return slug if name.start_with?("#{box_name}-#{latest}")
    end

    nil
  end

  #
  # Determines the publication visibility flag based on builds.yml public list.
  #
  # @param [String] name Box identifier.
  # @return [String] '--no-private' for public boxes, '--private' otherwise.
  #
  def public_private_box(name)
    builds_yml['public'].each do |public|
      return '--no-private' if name.start_with?(public)
    end
    '--private'
  end

  #
  # Determines whether the given architecture is marked as a default in builds.yml.
  #
  # @param [String] architecture Target CPU architecture (e.g. 'amd64', 'arm64').
  # @return [String] '--default-architecture' or '--no-default-architecture'.
  #
  def default_arch(architecture)
    builds_yml['default_architectures'].each do |arch|
      return '--default-architecture' if architecture.eql?(arch)
    end
    '--no-default-architecture'
  end

  #
  # Generates standard box description text for Vagrant Cloud.
  #
  # @param [String] name Box name identifier.
  # @return [String] Formatted description.
  #
  def box_desc(name)
    "Vanilla #{name.tr('-', ' ').capitalize} Vagrant box created with Bento by Progress Chef"
  end

  #
  # Generates standard slug alias description text for Vagrant Cloud.
  #
  # @param [String] name Slug name identifier.
  # @return [String] Formatted slug description.
  #
  def slug_desc(name)
    "Vanilla #{name.tr('-', ' ').capitalize} Vagrant box created with Bento by Progress Chef. This box will be updated with the latest releases of #{name.tr('-', ' ').capitalize} as they become available"
  end

  #
  # Generates version release description text capturing provider versions and tooling metadata.
  #
  # @param [Hash] md_data Box metadata hash.
  # @return [String] Release note description.
  #
  def ver_desc(md_data)
    tool_versions = md_data['providers'].map do |provider|
      if provider['name'] == 'vmware_desktop'
        if macos?
          "vmware-fusion: #{provider['version']}"
        else
          "vmware-workstation: #{provider['version']}"
        end
      else
        "#{provider['name']}: #{provider['version']}"
      end
    end
    tool_versions.sort!
    tool_versions << "packer: #{md_data['packer']}"

    "#{md_data['box_basename'].capitalize.tr('-', ' ')} Vagrant box version #{md_data['version']} created with Bento by Progress Chef. Built with: #{tool_versions.join(', ')} and tested with vagrant: #{md_data['vagrant']}"
  end
end
