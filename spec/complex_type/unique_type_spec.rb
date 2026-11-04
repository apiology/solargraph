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

  describe '#==' do
    it 'treats single- and double-quoted string literals as the same type' do
      single = described_class.parse("'a'")
      double = described_class.parse('"a"')
      expect(single).to eq(double)
      expect(single.hash).to eq(double.hash)
    end

    it 'unescapes a single-quoted literal before comparing it' do
      expect(described_class.parse("'it\\'s'")).to eq(described_class.parse('"it\'s"'))
    end

    it 'distinguishes different string literals' do
      expect(described_class.parse("'a'")).not_to eq(described_class.parse('"b"'))
    end
  end
end
