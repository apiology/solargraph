# frozen_string_literal: true

require 'rbs'

describe Solargraph::ComplexType::UniqueType::Intersection do
  # Specs that need both the reduced type interface and the
  # Solargraph::Type contract, and RBS `&` reconnected to this class.
  pending_prs = 'https://github.com/apiology/solargraph/pull/345 https://github.com/castwide/solargraph/pull/1459'

  # @param rbs [String]
  # @return [Solargraph::ComplexType]
  def from_rbs rbs
    Solargraph::RbsTranslator.to_complex_type(RBS::Parser.parse_type(rbs))
  end

  # @param tags [Array<String>]
  # @return [Solargraph::ComplexType]
  def type *tags
    Solargraph::ComplexType.parse(*tags)
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

  let(:a_and_b) { described_class.new([type('::A'), type('::B')]) }

  context 'when translating RBS' do
    it 'builds an intersection from A & B' do
      pending pending_prs

      type = from_rbs('A & B')

      expect(type.items.length).to eq(1)
      expect(type.items.first).to be_a(described_class)
      expect(type.items.first.conjuncts.map(&:rooted_tags)).to eq(['::A', '::B'])
    end

    it 'round-trips A & B through #to_rbs' do
      pending pending_prs

      expect(from_rbs('A & B').to_rbs).to eq('::A & ::B')
    end

    it 'keeps a union conjunct of (A | B) & C grouped' do
      pending pending_prs

      type = from_rbs('(A | B) & C')

      expect(type.tags).to eq('[A, B] & C')
      expect(type.to_rbs).to eq('(::A | ::B) & ::C')
    end

    it 'keeps an intersection inside a union' do
      pending pending_prs

      type = from_rbs('(A & B) | C')

      expect(type.items.map(&:class)).to eq([described_class, Solargraph::ComplexType::UniqueType])
    end

    it 'keeps an intersection inside an optional' do
      pending pending_prs

      type = from_rbs('(A & B)?')

      expect(type.items.first).to be_a(described_class)
      expect(type).to be_nullable
    end

    it 'keeps an intersection as a type argument' do
      pending pending_prs

      type = from_rbs('Array[A & B]')

      expect(type.items.first.subtypes.first.items.first).to be_a(described_class)
    end

    it 'leaves an RBS union a union' do
      expect(from_rbs('A | B').items.map(&:class).uniq).to eq([Solargraph::ComplexType::UniqueType])
    end

    it 'does not parse & from a YARD tag' do
      expect(type('A & B').items.first).not_to be_a(described_class)
    end
  end

  context 'when checking conformance' do
    let(:inferred) { Solargraph::ComplexType.new([a_and_b]) }

    it 'conforms to each of its conjuncts' do
      expect(inferred.conforms_to?(api_map, type('::A'), :method_call)).to be(true)
      expect(inferred.conforms_to?(api_map, type('::B'), :method_call)).to be(true)
    end

    it 'does not conform to a type no conjunct conforms to' do
      expect(inferred.conforms_to?(api_map, type('::C'), :method_call)).to be(false)
    end

    it 'conforms to an identical intersection' do
      expect(inferred.conforms_to?(api_map, inferred, :method_call)).to be(true)
    end

    it 'conforms regardless of conjunct order' do
      b_and_a = Solargraph::ComplexType.new([described_class.new([type('::B'), type('::A')])])

      expect(b_and_a.conforms_to?(api_map, inferred, :method_call)).to be(true)
    end

    it 'conforms to a narrower intersection' do
      all_three = Solargraph::ComplexType.new([described_class.new([type('::A'), type('::B'), type('::C')])])

      expect(all_three.conforms_to?(api_map, inferred, :method_call)).to be(true)
    end

    it 'requires every expected conjunct to be covered' do
      a_and_c = Solargraph::ComplexType.new([described_class.new([type('::A'), type('::C')])])

      expect(inferred.conforms_to?(api_map, a_and_c, :method_call)).to be(false)
    end

    it 'is not satisfied by a single conjunct' do
      expect(type('::A').conforms_to?(api_map, inferred, :method_call)).to be(false)
    end

    it 'satisfies a duck type one conjunct provides' do
      expect(inferred.conforms_to?(api_map, type('#bar'), :method_call)).to be(true)
    end

    it 'conforms when any conjunct does under allow_any_match' do
      expect(inferred.conforms_to?(api_map, type('::A'), :method_call, [:allow_any_match])).to be(true)
    end

    it 'does not satisfy a duck type no conjunct provides' do
      expect(inferred.conforms_to?(api_map, type('#baz'), :method_call)).to be(false)
    end
  end

  context 'when answered as one member of a union' do
    it 'is its own only item' do
      expect(a_and_b.items).to eq([a_and_b])
      expect(a_and_b.unioned_items).to eq([a_and_b])
    end

    it 'renders the whole intersection as its tag' do
      expect(a_and_b.tag).to eq('A & B')
      expect(a_and_b.to_s).to eq('A & B')
      expect(a_and_b.rooted_tag).to eq('::A & ::B')
      expect(a_and_b.desc).to eq('::A & ::B')
      expect(a_and_b.to_rbs).to eq('::A & ::B')
    end

    it 'brackets a union conjunct' do
      expect(described_class.new([type('::A', '::B'), type('::C')]).rooted_tags).to eq('[::A, ::B] & ::C')
    end

    it 'is equal regardless of conjunct order' do
      b_and_a = described_class.new([type('::B'), type('::A')])

      expect(a_and_b).to eq(b_and_a)
      expect(a_and_b.hash).to eq(b_and_a.hash)
    end

    it 'is not a duck type' do
      expect(a_and_b.duck_type?).to be(false)
    end
  end

  context 'when asking about its conjuncts' do
    it 'is void or undefined only when every conjunct is' do
      a_and_untyped = described_class.new([type('::A'), type('undefined')])

      expect(described_class.new([type('::A'), Solargraph::ComplexType::VOID]).void?).to be(false)
      expect(a_and_untyped.undefined?).to be(false)
      expect(a_and_untyped.defined?).to be(true)
    end

    it 'is the nil type when one conjunct is nil' do
      a_and_nil = described_class.new([type('::A'), type('nil')])

      expect(a_and_nil.nil_type?).to be(true)
      expect(a_and_nil.nullable?).to be(false)
      expect(described_class.new([type('::A', 'nil'), type('::B', 'nil')]).nullable?).to be(true)
    end

    it 'is generic when one conjunct is' do
      generic = described_class.new([type('generic<T>'), type('::A')])

      expect(generic.generic?).to be(true)
      expect(generic.any_generic?).to be(true)
      expect(a_and_b.generic?).to be(false)
    end

    it 'is rooted when every conjunct is' do
      expect(a_and_b).to be_rooted
      expect(a_and_b).to be_all_rooted
    end

    it 'is selfy when one conjunct is' do
      expect(described_class.new([type('self'), type('::A')])).to be_selfy
    end

    it 'is literal when one conjunct is' do
      literal = described_class.new([type('1'), type('::Integer')])

      expect(literal.literal?).to eq(type('1').literal?)
      expect(a_and_b.literal?).to be(false)
    end

    it 'takes the variance the conjuncts agree on' do
      expect(a_and_b.erased_variance).to eq(:covariant)
    end
  end

  context 'when transforming' do
    it 'qualifies each conjunct' do
      intersection = described_class.new([type('A'), type('B')])

      expect(intersection.qualify(api_map).rooted_tags).to eq('::A & ::B')
      expect(intersection.unalias_and_qualify(api_map).rooted_tags).to eq('::A & ::B')
      expect(intersection.force_rooted.rooted_tags).to eq('::A & ::B')
    end

    it 'drops nil from each conjunct' do
      expect(described_class.new([type('::A', 'nil'), type('::B')]).without_nil.rooted_tags).to eq('::A & ::B')
      expect(described_class.new([type('::A'), type('nil')]).without_nil)
        .to be(Solargraph::ComplexType::UniqueType::UNDEFINED)
    end

    it 'excludes itself only as a whole' do
      expect(a_and_b.exclude(nil, api_map)).to eq(a_and_b)
      expect(a_and_b.exclude(Solargraph::ComplexType.new([a_and_b]), api_map)).to eq(Solargraph::ComplexType::UNDEFINED)
      expect(a_and_b.exclude(type('::A'), api_map).items).to eq([a_and_b])
    end

    it 'maps literals, aliases and self through each conjunct' do
      expect(a_and_b.downcast_to_literal_if_possible).to eq(a_and_b)
      expect(a_and_b.simplify_literals).to eq(a_and_b)
      expect(a_and_b.expand({ '::A' => type('::C') }).rooted_tags).to eq('::A & ::B')
      expect(described_class.new([type('self'), type('::B')]).self_to_type(type('::C')).rooted_tags)
        .to eq('::C & ::B')
    end

    it 'transforms each conjunct' do
      renamed = a_and_b.transform { |t| t.rooted_tag == '::A' ? type('::C').items.first : t }

      expect(renamed.rooted_tags).to eq('::C & ::B')
    end

    it 'resolves generics in each conjunct' do
      generic = described_class.new([type('generic<T>'), type('::A')])
      resolved = generic.resolve_generics_from_context(['T'], nil, resolved_generic_values: { 'T' => type('::B') })

      expect(resolved.rooted_tags).to eq('::B & ::A')
    end

    it 'resolves receiver generics in each conjunct' do
      resolved = a_and_b.resolve_generics(api_map.get_path_pins('A').first, type('::A'))

      expect(resolved).to eq(a_and_b)
    end

    it 'freezes without freezing its conjuncts' do
      expect(a_and_b.freeze).to be_frozen
      expect(a_and_b.conjuncts.first).not_to be_frozen
    end

    it 'reduces Class and Object conjunct by conjunct' do
      class_and_b = described_class.new([type('::Class<::A>'), type('::B')])

      expect(class_and_b.reduce_class_type.rooted_tags).to eq('::A & ::B')
      expect(a_and_b.reduce_object.items).to eq([a_and_b])
    end

    it 'is an erased version only of an intersection lining up one for one' do
      expect(a_and_b.erased_version_of?(described_class.new([type('::A'), type('::B')]))).to be(true)
      expect(a_and_b.erased_version_of?(type('::A'))).to be(false)
      expect(a_and_b.erased_version_of?(described_class.new([type('::A'), type('::B'), type('::C')]))).to be(false)
    end

    it 'pairs with a type that is not an intersection as a whole' do
      pairs = a_and_b.combine_via(type('::C')) { |mine, theirs| [mine, theirs] }

      expect(pairs).to eq([a_and_b, type('::C')])
    end

    it 'pairs with another intersection conjunct by conjunct' do
      pending pending_prs

      combined = a_and_b.combine_via(described_class.new([type('::A'), type('::B')])) { |mine, _theirs| mine }

      expect(combined.rooted_tags).to eq('::A & ::B')
    end

    it 'qualifies each conjunct through a block' do
      pending pending_prs

      qualified = described_class.new([type('A'), type('B')]).qualify_parts { |t| t.recreate(make_rooted: true) }

      expect(qualified.rooted_tags).to eq('::A & ::B')
    end

    it 'is unresolvable when a conjunct is' do
      pending pending_prs

      expect(a_and_b.qualify_parts { nil }).to be_nil
    end

    it 'orders a nil conjunct last' do
      pending pending_prs

      ordered = described_class.new([type('nil'), type('::A')]).order_nil_last

      expect(ordered.conjuncts.map(&:rooted_tags)).to eq(['::A', 'nil'])
    end
  end

  context 'when resolving methods' do
    it 'offers the methods of every conjunct' do
      names = a_and_b.candidate_methods_from(api_map, '', false).map(&:name)

      expect(names).to include('foo', 'bar')
    end

    it 'offers the methods of a plain conjunct' do
      names = type('::A').items.first.candidate_methods_from(api_map, '', false).map(&:name)

      expect(names).to include('foo')
    end

    it 'provides a duck method one conjunct defines' do
      expect(a_and_b.provides_duck_method?(api_map, 'foo')).to be(true)
      expect(a_and_b.provides_duck_method?(api_map, 'baz')).to be(false)
    end

    it 'finds a method on any conjunct' do
      pending pending_prs

      expect(a_and_b.method_stack_pins('bar', api_map).map(&:path)).to eq(['B#bar'])
    end

    it 'finds no method no conjunct defines' do
      pending pending_prs

      expect(a_and_b.method_stack_pins('baz', api_map)).to be_nil
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
      pending pending_prs

      expect(described_class).to be < Solargraph::Type
    end

    it 'defines every method the contract declares' do
      pending pending_prs

      fallback_owners = [Solargraph::Type, Object, Kernel, BasicObject]
      missing = contract.reject do |name|
        described_class.public_method_defined?(name) &&
          !fallback_owners.include?(described_class.instance_method(name).owner)
      end
      expect(missing).to eq([])
    end

    it 'declares every public method it shares with ComplexType and UniqueType' do
      pending pending_prs

      shared = [Solargraph::ComplexType, Solargraph::ComplexType::UniqueType, described_class]
               .map(&:public_instance_methods).reduce(:&) - Object.public_instance_methods
      expect(shared - contract).to eq([])
    end
  end
end
