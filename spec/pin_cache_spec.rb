# frozen_string_literal: true

describe Solargraph::PinCache do
  describe '.possible_stdlibs' do
    it 'lists names from the stdlib directory without the .rb suffix' do
      allow(Dir).to receive(:glob).and_return(['/ruby/3.2.0/set.rb', '/ruby/3.2.0/json'])

      expect(described_class.possible_stdlibs).to eq(%w[json set])
    end

    it 'is tolerant of less usual Ruby installations' do
      stub_const('Gem::RUBYGEMS_DIR', nil)

      expect(described_class.possible_stdlibs).to eq([])
    end
  end

  describe '.suppress_yard_cache?' do
    let(:parser_gemspec) { Gem::Specification.new('parser', '3.3.7.1') }
    let(:other_gemspec) { Gem::Specification.new('backport', '1.2.0') }

    it 'suppresses YARD when the gem has resolved RBS collection types' do
      expect(described_class.suppress_yard_cache?(parser_gemspec,
                                                  Solargraph::RbsMap::CACHE_KEY_GEM_EXPORT)).to be true
    end

    it 'suppresses YARD for any resolved RBS source, including a collection digest' do
      expect(described_class.suppress_yard_cache?(parser_gemspec, 'abc123')).to be true
    end

    it 'builds YARD when the gem has no RBS types to fall back on' do
      expect(described_class.suppress_yard_cache?(parser_gemspec,
                                                  Solargraph::RbsMap::CACHE_KEY_UNRESOLVED)).to be false
    end

    it 'builds YARD for a gem outside the suppression list' do
      expect(described_class.suppress_yard_cache?(other_gemspec,
                                                  Solargraph::RbsMap::CACHE_KEY_GEM_EXPORT)).to be false
    end
  end
end
