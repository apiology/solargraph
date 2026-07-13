# frozen_string_literal: true

source 'https://rubygems.org'

gemspec name: 'solargraph'

# Test fixture gems
gem 'gem-with-yard-macros', path: 'spec/fixtures/gem-with-yard-macros'

#
# Linting tools (RuboCop plugins / overcommit). Optional group — skipped by
# default; linting CI opts in with BUNDLE_WITH=lint. rubocop-yard >= 1.3
# requires Ruby >= 3.3.
#
# very specific RuboCop version patterns for CI stability - feel free to update
# in an isolated PR. even more specific on RuboCop itself, which is written into
# the _todo file.
#
group :lint, optional: true do
  gem 'overcommit', '~> 0.68.0'
  gem 'rubocop', '~> 1.80.0.0'
  gem 'rubocop-rake', '~> 0.7.1'
  gem 'rubocop-rspec', '~> 3.6.0'
  gem 'rubocop-yard', '~> 1.3.0'
end

# Local gemfile for development tools, etc.
local_gemfile = File.expand_path('.Gemfile', __dir__)
instance_eval File.read local_gemfile if File.exist? local_gemfile
