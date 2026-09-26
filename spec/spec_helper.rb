# frozen_string_literal: true

require 'coverage'
Coverage.start(lines: true, branches: true, methods: true)

require 'json'
require 'fileutils'
require 'tmpdir'
require 'ostruct'

# Add lib to load path
$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', 'lib')

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.warnings = true
  config.order = :random
  Kernel.srand config.seed

  config.after(:suite) do
    results = Coverage.result
    lib_results = results.select { |k, _| k.include?('/lib/bento') }
    lib_results.each do |file, cov|
      lines = cov[:lines]
      branches = cov[:branches]
      total_lines = lines.compact.size
      covered_lines = lines.compact.count { |c| c > 0 }
      line_pct = total_lines > 0 ? (covered_lines.to_f / total_lines * 100).round(2) : 100.0

      total_branches = 0
      covered_branches = 0
      branches&.each_value do |targets|
        targets.each_value do |count|
          total_branches += 1
          covered_branches += 1 if count > 0
        end
      end
      branch_pct = total_branches > 0 ? (covered_branches.to_f / total_branches * 100).round(2) : 100.0

      puts sprintf("Coverage for %-35s Line: %6.2f%% (%d/%d) | Branch: %6.2f%% (%d/%d)",
                   File.basename(file), line_pct, covered_lines, total_lines, branch_pct, covered_branches, total_branches)
      if branch_pct < 100.0 && (file.include?('providermetadata.rb') || file.include?('common.rb') || file.include?('upload.rb') || file.include?('vagrant_utm_macos_snapshot.rb'))
        branches&.each do |(type, id, line, col), targets|
          targets.each do |target, count|
            puts "  [Branch Miss] #{File.basename(file)}:#{line} target #{target}" if count == 0
          end
        end
      end
    end
  end
end

# Helper: build a minimal OpenStruct opts suitable for most runners
def build_opts(overrides = {})
  defaults = {
    debug: false,
    no_shared: false,
    provisioner: nil,
    regx: nil,
    md_json: nil,
    template_files: [],
    dry_run: false,
    metadata_only: false,
    on_error: nil,
    only: nil,
    except: nil,
    mirror: nil,
    headed: false,
    single: false,
    override_version: '202506.01.0',
    cpus: nil,
    mem: nil,
    vars: nil,
    var_files: nil,
    config: false,
  }
  OpenStruct.new(defaults.merge(overrides))
end
