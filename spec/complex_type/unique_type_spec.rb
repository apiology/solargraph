# frozen_string_literal: true

describe Solargraph::ComplexType::UniqueType do
  describe '::BOT' do
    it 'is a bot type' do
      expect(described_class::BOT.bot?).to be true
    end

    it 'is rooted' do
      expect(described_class::BOT.rooted?).to be true
    end

    it 'is equal to ComplexType::BOT.first' do
      expect(described_class::BOT).to eq(Solargraph::ComplexType::BOT.first)
    end
  end

  describe '.parse' do
    it 'raises for a substring whose delimiter is not {, ( or <' do
      expect do
        described_class.parse('Foo', '[bar]')
      end.to raise_error(Solargraph::ComplexTypeError, /Unrecognized parameter delimiter/)
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

  describe '#exclude' do
    let(:api_map) { Solargraph::ApiMap.new }

    let(:source) do
      Solargraph::Source.load_string(%(
        class Sup; end
        class Sub < Sup; end
        class Unrelated; end
      ))
    end

    before { api_map.map source }

    it 'returns self when exclude_types is nil' do
      type = described_class.parse('Sub')
      expect(type.exclude(nil, api_map)).to be(type)
    end

    it 'excludes a type that conforms to the excluded type' do
      type = described_class.parse('Sub')
      exclude_types = Solargraph::ComplexType.parse('Sup')
      result = type.exclude(exclude_types, api_map)
      expect(result.tags).to eq('undefined')
    end

    it 'keeps a type that does not conform to the excluded type' do
      type = described_class.parse('Unrelated')
      exclude_types = Solargraph::ComplexType.parse('Sup')
      result = type.exclude(exclude_types, api_map)
      expect(result.tags).to eq('Unrelated')
    end
  end

  describe '#key_type_tag?' do
    it 'matches a single literal key type' do
      type = Solargraph::ComplexType.parse('Hash{"Index" => Float}').first
      expect(type.key_type_tag?('"Index"')).to be(true)
      expect(type.key_type_tag?('"Other"')).to be(false)
    end

    it 'matches every member of a union key type, not just the first' do
      type = Solargraph::ComplexType.parse('Hash{"Index"|"Name" => Float}').first
      expect(type.key_type_tag?('"Index"')).to be(true)
      expect(type.key_type_tag?('"Name"')).to be(true)
      expect(type.key_type_tag?('"Other"')).to be(false)
    end
  end

  describe '#simplify_literals' do
    it 'leaves a nil literal as nil, not NilClass' do
      type = described_class.parse('nil')
      expect(type.simplify_literals.tag).to eq('nil')
    end
  end
end
