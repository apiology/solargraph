# frozen_string_literal: true

describe Solargraph::ComplexType::UniqueType do
  describe '#any?' do
    let(:type) { described_class.parse('String') }

    it 'yields one and only one type, itself' do
      types_encountered = []
      type.any? { |t| types_encountered << t }
      expect(types_encountered).to eq([type])
    end
  end

  describe '#exclude' do
    let(:api_map) { Solargraph::ApiMap.new }

    it 'keeps itself when the excluded type does not include it' do
      type = described_class.parse('String')
      result = type.exclude(Solargraph::ComplexType.parse('Integer'), api_map)
      expect(result.to_s).to eq('String')
    end

    it 'returns undefined when the excluded type includes it' do
      type = described_class.parse('String')
      result = type.exclude(Solargraph::ComplexType.parse('String, nil'), api_map)
      expect(result).to be_undefined
    end
  end
end
