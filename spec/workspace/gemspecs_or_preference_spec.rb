# frozen_string_literal: true

describe Solargraph::Workspace::Gemspecs, '#gemspec_or_preference' do
  subject(:result) { gemspecs.send(:gemspec_or_preference, gemspec) }

  let(:gemspecs) { described_class.new(nil, preferences: preferences) }
  let(:gemspec) { Gem::Specification.new('rspec', '3.0.0') }

  context 'with no preference for the gem' do
    let(:preferences) { [] }

    it 'returns the original gemspec' do
      expect(result).to equal(gemspec)
    end
  end

  context 'with a preference matching the gemspec version' do
    let(:preferences) { [Gem::Specification.new('rspec', '3.0.0')] }

    it 'returns the original gemspec' do
      expect(result).to equal(gemspec)
    end
  end

  context 'with a preference for a different version' do
    let(:preferred) { Gem::Specification.new('rspec', '3.1.0') }
    let(:preferences) { [preferred] }

    it 'resolves the preferred version instead of raising' do
      expect { result }.not_to raise_error
    end
  end
end
