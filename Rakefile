# frozen_string_literal: true

require 'rake'
require 'bundler/gem_tasks'
require 'fileutils'
require 'open3'

desc 'Open a Pry session preloaded with this library'
task :console do
  sh 'pry -I lib -r solargraph.rb'
end

# `vernier` is an optional dependency typecheck needs; CI adds it before every run, so do the same locally:
#   echo "gem 'vernier', '>1.0', '<2'" >> .Gemfile && bundle install
desc 'Run the type checker'
task typecheck: [:typecheck_strong]

desc 'Run the type checker at typed level - return code issues provable without annotations being correct'
task :typecheck_typed do
  sh 'SOLARGRAPH_ASSERTS=on bundle exec solargraph typecheck --level typed'
end

desc 'Run the type checker at strict level - report issues using type annotations'
task :typecheck_strict do
  sh 'SOLARGRAPH_ASSERTS=on bundle exec solargraph typecheck --level strict'
end

desc 'Run the type checker at strong level - enforce that type annotations exist'
task :typecheck_strong do
  sh 'SOLARGRAPH_ASSERTS=on bundle exec solargraph typecheck --level strong'
end

desc 'Run the type checker at alpha level - run high-false-alarm checks'
task :typecheck_alpha do
  sh 'SOLARGRAPH_ASSERTS=on bundle exec solargraph typecheck --level alpha'
end

desc 'Run RSpec tests, starting with the ones that failed last time'
task spec: %i[spec_failed full_spec] do
  undercover
end

desc 'Run all RSpec tests'
task :full_spec do
  warn 'starting spec'
  # Build the pins the suite leans on hardest before forking. Four
  # workers racing to generate the same ones is what takes
  # rbs_map/conversions_spec from 17s to over four minutes.
  #
  # The specs cache any gem they need themselves, so this only saves
  # time. It only warns on a name it cannot find, so check for a
  # Caching line per gem when editing this list.
  #
  # The specs map gems both with no workspace and with the repo-root
  # one, so cache once after loading each.
  require 'solargraph'
  puts 'Caching core'
  Solargraph::Collection::Core.load
  ['', Dir.pwd].each do |directory|
    repo = Solargraph::Repo.new(Solargraph::Workspace.new(directory).directory_or_nil)
    metagems = %w[ast parser backport reverse_markdown yard kramdown-parser-gfm].filter_map do |name|
      repo.find_by_name(name) || warn("Gem #{name} not found")
    end
    metagems.each { |metagem| puts "Caching #{metagem.name} #{metagem.version}" }
    Solargraph::Collection::Gem.load_all metagems, out: $stdout
  end
  # Five files the balancer must not split, each over state that is one
  # copy for the whole run. library, external and yardoc uncache the
  # backport gem from the pin cache every worker shares; external and
  # repo delete and reinstall the same fixture Gemfile.lock under
  # spec/fixtures/external_bundled_gem, which is where the path gem
  # gem-with-yard-macros comes from. Apart, one worker destroys what
  # another is mid-way through reading.
  #
  # rubocop_helpers is here for an unrelated reason: it needs rubocop
  # unloaded, and RSpec requires every file in a group before running
  # any example, so protocol_spec's top-level `require 'rubocop'` has to
  # land in a different worker. --isolate is what keeps it out.
  sh 'TEST_COVERAGE_COMMAND_NAME=full-new bundle exec parallel_rspec --runtime-log spec/parallel_runtime_rspec.log ' \
     '--single "spec/(library|external|yardoc|repo)_spec\.rb|spec/diagnostics/rubocop_helpers_spec\.rb" --isolate ' \
     '--verbose-command spec/' #  --profile'
  # clear now-outdated coverage
  # @sg-ignore https://github.com/castwide/solargraph/issues/1255
  FileUtils.rm_rf('coverage/full')
  # move coverage/full-new to coverage/full on success so that we
  # always have the last successful run's coverage info
  unless ENV['SIMPLECOV_DISABLED']
    # @sg-ignore https://github.com/castwide/solargraph/issues/1255
    FileUtils.mv('coverage/full-new', 'coverage/full')
  end
end

# @sg-ignore #undercover return type could not be inferred
# @return [Process::Status]
def undercover
  simplecov_collate
  cmd = 'bundle exec undercover ' \
        '--simplecov coverage/combined/coverage.json ' \
        '--exclude-files "Rakefile,spec/*,spec/**/*,lib/solargraph/version.rb" ' \
        '--compare origin/master'
  output, status = Bundler.with_unbundled_env do
    Open3.capture2e(cmd)
  end
  puts output
  # @sg-ignore https://github.com/apiology/solargraph/pull/229
  $stdout.flush
  status
rescue StandardError => e
  warn "hit error: #{e.message}"
  # @sg-ignore https://github.com/apiology/solargraph/pull/176
  warn "Backtrace:\n#{e.backtrace.join("\n")}"
  warn "output: #{output}"
  puts 'Flushing'
  # @sg-ignore https://github.com/apiology/solargraph/pull/229
  $stdout.flush
  raise
end

desc 'Check PR coverage'
task :undercover do
  raise 'Undercover failed' unless undercover.success?
end

desc 'Branch-focused fast-feedback quality/spec/coverage checks'
task test: %i[overcommit spec typecheck] do
  # do these in order
  Rake::Task['typecheck_strict'].invoke
  Rake::Task['typecheck_strong'].invoke
  Rake::Task['typecheck_alpha'].invoke
end

desc 'Re-run failed specs.  Add --fail-fast in your .rspec-local file if desired.'
task :spec_failed do
  # allow user to check out any persistent failures while looking for
  # more in the whole test suite
  #
  # Note: prspec doesn't support --only-failures, so we have to use rspec directly here.
  sh 'TEST_COVERAGE_COMMAND_NAME=next-failure bundle exec rspec --only-failures || true'
end

desc 'Run undercover and show output without failing the task if it fails'
task :undercover_no_fail do
  undercover
rescue StandardError
  puts 'Undercover failed, but continuing with other tasks.'
end

# @return [void]
def simplecov_collate
  require 'simplecov'
  require 'simplecov-lcov'
  require 'undercover/simplecov_formatter'

  SimpleCov.collate(Dir['coverage/{next-failure,full,ad-hoc}/.resultset.json']) do
    cname = 'combined'
    command_name cname
    new_dir = File.join('coverage', cname)
    coverage_dir new_dir

    formatter \
      SimpleCov::Formatter::MultiFormatter
        .new([
               SimpleCov::Formatter::HTMLFormatter,
               SimpleCov::Formatter::Undercover,
               SimpleCov::Formatter::LcovFormatter
             ])
    SimpleCov::Formatter::LcovFormatter.config.report_with_single_file = true
  end
  puts 'Simplecov collated results into coverage/combined/.resultset.json'
rescue StandardError => e
  puts "Simplecov collate failed: #{e.message}"
ensure
  # @sg-ignore https://github.com/apiology/solargraph/pull/229
  $stdout.flush
end

desc 'Add incremental coverage for rapid iteration with undercover'
task :simplecov_collate do
  simplecov_collate
end

desc 'Show quality checks on this development branch so far, including any staged files'
task :overcommit do
  # OVERCOMMIT_DEBUG=1 will show more detail
  sh 'SOLARGRAPH_ASSERTS=on bundle exec overcommit --run --diff origin/master'
end
