# frozen_string_literal: true

describe Solargraph::ComplexType::UniqueType do
  describe '#rooted_tags' do
    it 'leaves a symbol literal alone, so the tag can be parsed back' do
      type = Solargraph::ComplexType.parse('Array<:Sym>').first.force_rooted
      expect(type.rooted_tags).to eq('::Array<:Sym>')
      expect(Solargraph::ComplexType.parse(type.rooted_tags).tags).to eq('Array<:Sym>')
    end

    it 'leaves a capitalized string literal alone when it is a hash key' do
      type = Solargraph::ComplexType.parse('Hash{"Index" => Float}').first.force_rooted
      expect(type.rooted_tags).to eq('::Hash{"Index" => ::Float}')
    end
  end

  describe '#any?' do
    let(:type) { described_class.parse('String') }

    it 'yields one and only one type, itself' do
      types_encountered = []
      type.any? { |t| types_encountered << t }
      expect(types_encountered).to eq([type])
    end
  end
end
