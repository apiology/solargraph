# frozen_string_literal: true

require 'open3'

describe Solargraph::Diagnostics::RubocopHelpers, order: :defined do
  context 'with custom version' do
    let(:custom_version) { '0.0.0' }

    # Kernel#require does nothing once another spec in this process has
    # loaded the real RuboCop, so load the custom version in a new process.
    let(:script) do
      <<~RUBY
        require 'solargraph'
        # Drop the hook Bundler uses to restore its cached specs, so the
        # custom gem path below is searched.
        Gem.post_reset_hooks.clear
        Gem.paths = { 'GEM_PATH' => [ARGV[0], *Gem.paths.path].join(Gem.path_separator) }
        Solargraph::Diagnostics::RubocopHelpers.require_rubocop(ARGV[1])
        print RuboCop::Version::STRING
      RUBY
    end

    it 'requires the specified version of rubocop' do
      custom_gem_path = File.absolute_path('spec/fixtures/rubocop-custom-version').gsub('\\', '/')
      output, error, status = Open3.capture3(RbConfig.ruby, '-Ilib', '-e', script, custom_gem_path, custom_version)
      expect(status).to be_success, error
      expect(output).to eq(custom_version)
    end
  end

  context 'with real version' do
    let(:default_version) { Gem::Specification.find_by_name('rubocop').full_gem_path[/[^-]+$/] }

    it 'requires the default version of rubocop' do
      input = nil
      described_class.require_rubocop(input)
      output = RuboCop::Version::STRING
      expect(output).to eq(default_version)
    end
  end

  it 'converts lower-case drive letters to upper-case' do
    input = 'c:/one/two'
    output = described_class.fix_drive_letter(input)
    expect(output).to eq('C:/one/two')
  end

  it 'ignores paths without drive letters' do
    input = 'one/two'
    output = described_class.fix_drive_letter(input)
    expect(output).to eq('one/two')
  end
end
