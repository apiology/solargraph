# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = 'gem-with-concern'
  spec.version = '0.1.0'
  spec.authors = ['Solargraph']
  spec.email = ['admin@castwide.com']

  spec.summary = "Test fixture for Solargraph's YARD plugin support."
  spec.description = 'Provides a module written in the ActiveSupport::Concern style, whose ' \
                     'documentation differs depending on whether the activesupport-concern ' \
                     'YARD plugin is in use.'
  spec.homepage = 'https://github.com/castwide/solargraph'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.0.0'

  spec.files = Dir['lib/**/*.rb']
  spec.require_paths = ['lib']
end
