# frozen_string_literal: true

source 'https://rubygems.org'

gemspec name: 'solargraph'

# Test fixture gems
gem 'gem-with-yard-macros', path: 'spec/fixtures/gem-with-yard-macros'

#
# RuboCop plugins must be installed for all CI Rubies — Solargraph diagnostics
# and formatting load this repo's .rubocop.yml which requires them.
#
# rubocop-yard >= 1.3 requires Ruby >= 3.3 (fixes YARD/CollectionStyle crashes
# with yard 0.9.44). Older Rubies keep 1.0.x.
#
# very specific RuboCop version patterns for CI stability - feel free to update
# in an isolated PR. even more specific on RuboCop itself, which is written into
# the _todo file.
#
gem 'rubocop', '~> 1.80.0.0'
gem 'rubocop-rake', '~> 0.7.1'
gem 'rubocop-rspec', '~> 3.6.0'
if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.3.0')
  gem 'rubocop-yard', '~> 1.3.0'
else
  gem 'rubocop-yard', '~> 1.0.0'
end

#
# Overcommit is lint-CI / local-hooks only. Optional group — skipped by default;
# linting CI opts in with BUNDLE_WITH=lint.
#
group :lint, optional: true do
  gem 'overcommit', '~> 0.71.0'
end

# Local gemfile for development tools, etc.
local_gemfile = File.expand_path('.Gemfile', __dir__)
instance_eval File.read local_gemfile if File.exist? local_gemfile
