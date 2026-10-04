# frozen_string_literal: true

describe Solargraph::Equality do
  describe '#freeze' do
    it 'freezes the containers holding the instance state' do
      type = Solargraph::ComplexType.parse('String')
      type.freeze
      expect(type).to be_frozen
      expect(type.items).to be_frozen
    end

    it 'leaves ComplexType itself unfrozen, so autoloads under it still resolve' do
      Solargraph::ComplexType.parse('String').freeze
      expect(Solargraph::ComplexType).not_to be_frozen
      expect { Solargraph::ComplexType.const_get(:Conformance) }.not_to raise_error
    end

    it 'leaves Chain::Link itself unfrozen' do
      Solargraph::Source::Chain::Link.new('foo').freeze
      expect(Solargraph::Source::Chain::Link).not_to be_frozen
    end
  end

  describe '#hash' do
    it 'separates links of the same word but different classes' do
      link = Solargraph::Source::Chain::Link.new('foo')
      call = Solargraph::Source::Chain::Call.new('foo')
      expect(link.hash).not_to eq(call.hash)
    end
  end
end
