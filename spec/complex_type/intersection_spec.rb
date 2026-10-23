# frozen_string_literal: true

describe Solargraph::ComplexType::UniqueType::Intersection do
  # @param rbs [String]
  # @return [Solargraph::ComplexType]
  def from_rbs rbs
    Solargraph::RbsTranslator.to_complex_type(RBS::Parser.parse_type(rbs))
  end

  let(:api_map) do
    source = Solargraph::Source.load_string(%(
      class A
        # @return [void]
        def foo; end
      end

      class B
        # @return [void]
        def bar; end
      end

      class C; end
    ), 'test.rb')
    Solargraph::ApiMap.new.tap { |map| map.map source }
  end

  context 'when translating RBS' do
    it 'builds an intersection from A & B' do
      type = from_rbs('A & B')

      expect(type.items.length).to eq(1)
      expect(type.items.first).to be_a(described_class)
      expect(type.items.first.conjuncts.map(&:rooted_tags)).to eq(['::A', '::B'])
    end

    it 'round-trips A & B through #to_rbs' do
      expect(from_rbs('A & B').to_rbs).to eq('::A & ::B')
    end

    it 'keeps a union conjunct of (A | B) & C grouped' do
      type = from_rbs('(A | B) & C')

      expect(type.items.first.conjuncts.first.items.map(&:rooted_tag)).to eq(['::A', '::B'])
      expect(type.tags).to eq('[A, B] & C')
      expect(type.to_rbs).to eq('(::A | ::B) & ::C')
    end

    it 'keeps an intersection inside a union' do
      type = from_rbs('(A & B) | C')

      expect(type.items.map(&:class)).to eq([described_class, Solargraph::ComplexType::UniqueType])
      expect(type.to_rbs).to eq('(::A & ::B | ::C)')
    end

    it 'keeps an intersection inside an optional' do
      type = from_rbs('(A & B)?')

      expect(type.items.first).to be_a(described_class)
      expect(type).to be_nullable
    end

    it 'keeps an intersection as a type argument' do
      type = from_rbs('Array[A & B]')

      expect(type.items.first.subtypes.first.items.first).to be_a(described_class)
    end

    it 'leaves an RBS union a union' do
      expect(from_rbs('A | B').items.map(&:class).uniq).to eq([Solargraph::ComplexType::UniqueType])
    end

    it 'does not parse & from a YARD tag' do
      expect(Solargraph::ComplexType.parse('A & B').items.first).not_to be_a(described_class)
    end
  end

  context 'when checking conformance' do
    let(:a_and_b) { from_rbs('A & B') }

    it 'conforms to each of its conjuncts' do
      expect(a_and_b.conforms_to?(api_map, from_rbs('A'), :method_call)).to be(true)
      expect(a_and_b.conforms_to?(api_map, from_rbs('B'), :method_call)).to be(true)
    end

    it 'does not conform to a type no conjunct conforms to' do
      expect(a_and_b.conforms_to?(api_map, from_rbs('C'), :method_call)).to be(false)
    end

    it 'conforms to an identical intersection' do
      expect(a_and_b.conforms_to?(api_map, from_rbs('A & B'), :method_call)).to be(true)
    end

    it 'conforms regardless of conjunct order' do
      expect(from_rbs('B & A').conforms_to?(api_map, a_and_b, :method_call)).to be(true)
    end

    it 'conforms to a narrower intersection' do
      expect(from_rbs('A & B & C').conforms_to?(api_map, a_and_b, :method_call)).to be(true)
    end

    it 'requires every expected conjunct to be covered' do
      expect(a_and_b.conforms_to?(api_map, from_rbs('A & C'), :method_call)).to be(false)
    end

    it 'is not satisfied by a single conjunct' do
      expect(from_rbs('A').conforms_to?(api_map, a_and_b, :method_call)).to be(false)
    end

    it 'satisfies a duck type one conjunct provides' do
      expect(a_and_b.conforms_to?(api_map, Solargraph::ComplexType.parse('#bar'), :method_call)).to be(true)
    end

    it 'does not satisfy a duck type no conjunct provides' do
      expect(a_and_b.conforms_to?(api_map, Solargraph::ComplexType.parse('#baz'), :method_call)).to be(false)
    end
  end
end
