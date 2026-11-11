# frozen_string_literal: true

require 'bundler/setup'
require 'tmpdir'
require 'webmock/rspec'
WebMock.disable_net_connect!(allow_localhost: true)
unless ENV['SIMPLECOV_DISABLED']
  # set up lcov reporting for undercover
  require 'simplecov'
  require 'undercover/simplecov_formatter'

  SimpleCov.start do
    cname = ENV.fetch('TEST_COVERAGE_COMMAND_NAME', 'ad-hoc')
    command_name cname
    new_dir = File.join('coverage', cname)
    coverage_dir new_dir

    add_filter(%r{^/spec/})
    add_filter('/Rakefile')
    # included via gemspec before we start, so can never be covered
    add_filter('lib/solargraph/version.rb')
    # off by default - feel free to set if you'd like undercover to
    # hold you to making a more thorough set of specs
    enable_coverage(:branch) if ENV['SOLARGRAPH_BRANCH_COVERAGE']
  end
end
RSpec.configure do |c|
  # Allow use of --only-failures with rspec, handy for local development
  c.example_status_persistence_file_path = 'rspec-examples.txt'
end
require 'solargraph'
# execute any logging blocks to make sure they don't blow up
Solargraph::Logging.logger.sev_threshold = Logger::DEBUG
# ...but still suppress logger output in specs (if possible)
if Solargraph::Logging.logger.respond_to?(:reopen) && !ENV.key?('SOLARGRAPH_LOG')
  Solargraph::Logging.logger.reopen(File::NULL)
end

# @param name [String]
# @param value [String]
def with_env_var name, value
  old_value = ENV.fetch(name, nil) # Store the old value
  ENV[name] = value # Set to new value

  begin
    yield # Execute the block
  ensure
    ENV[name] = old_value # Restore the old value
  end
end

# Run the block against a temporary copy of the current cache, so specs
# that delete cache entries cannot remove them from under other processes
# sharing the cache directory.
def with_private_cache &block
  Dir.mktmpdir do |dir|
    base = Solargraph::CacheDir.base_dir
    [Solargraph::CacheDir.work_dir, Solargraph::CacheDir.yard_dir].each do |src|
      next unless File.directory?(src)

      dest = File.join(dir, src.delete_prefix(base))
      FileUtils.mkdir_p File.dirname(dest)
      FileUtils.cp_r src, dest
    end
    with_env_var('SOLARGRAPH_CACHE', dir, &block)
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = 'tmp/rspec_status.txt'
end

def capture_stdout &block
  original_stdout = $stdout
  $stdout = StringIO.new
  begin
    block.call
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end

def capture_both &block
  original_stdout = $stdout
  original_stderr = $stderr
  stringio = StringIO.new
  $stdout = stringio
  $stderr = stringio
  begin
    block.call
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end
  stringio.string
end
