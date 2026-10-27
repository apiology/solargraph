# frozen_string_literal: true

require 'rbs'

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

    it 'conforms when any conjunct does under allow_any_match' do
      expect(a_and_b.conforms_to?(api_map, from_rbs('A'), :method_call, [:allow_any_match])).to be(true)
    end

    it 'does not satisfy a duck type no conjunct provides' do
      expect(a_and_b.conforms_to?(api_map, Solargraph::ComplexType.parse('#baz'), :method_call)).to be(false)
    end
  end

  context 'when answered as one member of a union' do
    let(:a_and_b) { from_rbs('A & B').items.first }

    it 'is its own only item' do
      expect(a_and_b.items).to eq([a_and_b])
      expect(a_and_b.to_a).to eq([a_and_b])
      expect(a_and_b.each.to_a).to eq([a_and_b])
      expect(a_and_b.each_unique_type.to_a).to eq([a_and_b])
      expect(a_and_b.map(&:tags)).to eq(['A & B'])
    end

    it 'yields itself to all? and any?' do
      expect(a_and_b.all? { |t| t.equal?(a_and_b) }).to be(true)
      expect(a_and_b.any? { |t| t.equal?(a_and_b) }).to be(true)
    end

    it 'renders the whole intersection as its tag' do
      expect(a_and_b.tag).to eq('A & B')
      expect(a_and_b.to_s).to eq('A & B')
      expect(a_and_b.rooted_tag).to eq('::A & ::B')
      expect(a_and_b.desc).to eq('::A & ::B')
    end

    it 'is equal regardless of conjunct order' do
      b_and_a = from_rbs('B & A').items.first

      expect(a_and_b).to eq(b_and_a)
      expect(a_and_b.hash).to eq(b_and_a.hash)
    end

    it 'is not a duck type' do
      expect(a_and_b.duck_type?).to be(false)
    end
  end

  context 'when asking about its conjuncts' do
    it 'is void or undefined only when every conjunct is' do
      a_and_void = described_class.new([from_rbs('A'), Solargraph::ComplexType::VOID])
      a_and_untyped = from_rbs('A & untyped').items.first

      expect(a_and_void.void?).to be(false)
      expect(a_and_untyped.undefined?).to be(false)
      expect(a_and_untyped.defined?).to be(true)
    end

    it 'is the nil type when one conjunct is nil' do
      expect(from_rbs('A & nil').items.first.nil_type?).to be(true)
      expect(from_rbs('A & nil').items.first.nullable?).to be(false)
      expect(from_rbs('(A | nil) & (B | nil)').items.first.nullable?).to be(true)
    end

    it 'is generic when one conjunct is' do
      generic = described_class.new(
        [Solargraph::ComplexType.parse('generic<T>'), from_rbs('A')]
      )

      expect(generic.generic?).to be(true)
      expect(generic.any_generic?).to be(true)
      expect(from_rbs('A & B').items.first.generic?).to be(false)
    end

    it 'is rooted when every conjunct is' do
      expect(from_rbs('A & B').items.first).to be_rooted
      expect(from_rbs('A & B').items.first).to be_all_rooted
    end

    it 'is selfy when one conjunct is' do
      expect(from_rbs('self & A').items.first).to be_selfy
    end

    it 'is literal when one conjunct is' do
      literal = described_class.new(
        [Solargraph::ComplexType.parse('1'), from_rbs('Integer')]
      )

      expect(literal.literal?).to eq(Solargraph::ComplexType.parse('1').literal?)
      expect(from_rbs('A & B').items.first.literal?).to be(false)
    end

    it 'takes the variance the conjuncts agree on' do
      expect(from_rbs('A & B').items.first.erased_variance).to eq(:covariant)
    end
  end

  context 'when transforming' do
    let(:a_and_b) { from_rbs('A & B').items.first }

    it 'qualifies each conjunct' do
      intersection = described_class.new(
        [Solargraph::ComplexType.parse('A'), Solargraph::ComplexType.parse('B')]
      )

      expect(intersection.qualify(api_map).rooted_tags).to eq('::A & ::B')
      expect(intersection.unalias_and_qualify(api_map).rooted_tags).to eq('::A & ::B')
      expect(intersection.force_rooted.rooted_tags).to eq('::A & ::B')
    end

    it 'drops nil from each conjunct' do
      expect(from_rbs('(A | nil) & B').items.first.without_nil.rooted_tags).to eq('::A & ::B')
      expect(from_rbs('A & nil').items.first.without_nil).to be(Solargraph::ComplexType::UniqueType::UNDEFINED)
    end

    it 'excludes itself only as a whole' do
      expect(a_and_b.exclude(nil, api_map)).to eq(a_and_b)
      expect(a_and_b.exclude(from_rbs('A & B'), api_map)).to eq(Solargraph::ComplexType::UNDEFINED)
      expect(a_and_b.exclude(from_rbs('A'), api_map).items).to eq([a_and_b])
    end

    it 'maps literals, aliases and self through each conjunct' do
      expect(a_and_b.downcast_to_literal_if_possible).to eq(a_and_b)
      expect(a_and_b.simplify_literals).to eq(a_and_b)
      expect(a_and_b.expand({ '::A' => from_rbs('C') }).rooted_tags).to eq('::A & ::B')
      expect(from_rbs('self & B').items.first.self_to_type(from_rbs('C')).rooted_tags).to eq('::C & ::B')
    end

    it 'transforms each conjunct' do
      renamed = a_and_b.transform { |t| t.rooted_tag == '::A' ? from_rbs('C').items.first : t }

      expect(renamed.rooted_tags).to eq('::C & ::B')
    end

    it 'resolves generics in each conjunct' do
      generic = described_class.new(
        [Solargraph::ComplexType.parse('generic<T>'), from_rbs('A')]
      )
      resolved = generic.resolve_generics_from_context(['T'], nil, resolved_generic_values: { 'T' => from_rbs('B') })

      expect(resolved.rooted_tags).to eq('::B & ::A')
    end

    it 'resolves receiver generics in each conjunct' do
      resolved = a_and_b.resolve_generics(api_map.get_path_pins('A').first, from_rbs('A'))

      expect(resolved).to eq(a_and_b)
    end

    it 'freezes without freezing its conjuncts' do
      expect(a_and_b.freeze).to be_frozen
      expect(a_and_b.conjuncts.first).not_to be_frozen
    end

    it 'has no parameters of its own to erase' do
      expect(a_and_b.erase_parameters).to equal(a_and_b)
    end

    it 'reduces Class and Object conjunct by conjunct' do
      class_and_b = described_class.new([Solargraph::ComplexType.parse('::Class<::A>'), from_rbs('B')])

      expect(class_and_b.reduce_class_type.rooted_tags).to eq('::A & ::B')
      expect(a_and_b.reduce_object.items).to eq([a_and_b])
    end

    it 'is an erased version only of an intersection lining up one for one' do
      expect(a_and_b.erased_version_of?(from_rbs('A & B').items.first)).to be(true)
      expect(a_and_b.erased_version_of?(from_rbs('A').items.first)).to be(false)
      expect(a_and_b.erased_version_of?(from_rbs('A & B & C').items.first)).to be(false)
    end
  end

  context 'when resolving methods' do
    let(:a_and_b) { from_rbs('A & B').items.first }

    it 'offers the methods of every conjunct' do
      names = a_and_b.candidate_methods_from(api_map, '', false).map(&:name)

      expect(names).to include('foo', 'bar')
    end

    it 'offers the methods of a plain conjunct' do
      names = from_rbs('A').items.first.candidate_methods_from(api_map, '', false).map(&:name)

      expect(names).to include('foo')
    end

    it 'provides a duck method one conjunct defines' do
      expect(a_and_b.provides_duck_method?(api_map, 'foo')).to be(true)
      expect(a_and_b.provides_duck_method?(api_map, 'baz')).to be(false)
    end
  end

  context 'with the Solargraph::Type contract' do
    # Read the contract the way spec/type_contract_spec.rb does.
    #
    # @return [Array<Symbol>]
    def contract
      path = File.expand_path('../../lib/solargraph/type.rb', __dir__)
      Solargraph::SourceMap.load(path).pins
                           .select { |pin| pin.is_a?(Solargraph::Pin::Method) && pin.path.start_with?('Solargraph::Type#') }
                           .map { |pin| pin.name.to_sym }
    end

    it 'is a Solargraph::Type' do
      pending 'https://github.com/castwide/solargraph/pull/1459'

      expect(described_class).to be < Solargraph::Type
    end

    it 'defines every method the contract declares' do
      pending 'https://github.com/castwide/solargraph/pull/1459'

      fallback_owners = [Solargraph::Type, Object, Kernel, BasicObject]
      missing = contract.reject do |name|
        described_class.public_method_defined?(name) &&
          !fallback_owners.include?(described_class.instance_method(name).owner)
      end
      expect(missing).to eq([])
    end

    it 'declares every public method it shares with ComplexType and UniqueType' do
      pending 'https://github.com/castwide/solargraph/pull/1459'

      shared = [Solargraph::ComplexType, Solargraph::ComplexType::UniqueType, described_class]
               .map(&:public_instance_methods).reduce(:&) - Object.public_instance_methods
      expect(shared - contract).to eq([])
    end
  end
end
