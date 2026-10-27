# frozen_string_literal: true

require 'rbs'

describe 'Solargraph::ComplexType::UniqueType::Intersection' do
  # Intersection is written against the Solargraph::Type contract and the
  # reduced type interface, and RBS `&` reaches it only once those land.
  before do
    pending 'https://github.com/castwide/solargraph/pull/1459 ' \
            'https://github.com/castwide/solargraph/pull/1460 ' \
            'https://github.com/castwide/solargraph/pull/1104'
  end

  # Loaded inside each example, not when this file loads: its superclass
  # Solargraph::Type exists only once castwide/solargraph#1459 is in.
  let(:described_class) { Solargraph::ComplexType::UniqueType::Intersection }
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

      expect(type.tags).to eq('[A, B] & C')
      expect(type.to_rbs).to eq('(::A | ::B) & ::C')
    end

    it 'keeps an intersection inside a union' do
      type = from_rbs('(A & B) | C')

      expect(type.items.map(&:class)).to eq([described_class, Solargraph::ComplexType::UniqueType])
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

    it 'does not parse & from a YARD tag' do
      expect(type('A & B').items.first).not_to be_a(described_class)
    end
  end

  context 'when checking conformance' do
    it 'conforms to each of its conjuncts' do
      expect(a_and_b.conforms_to?(api_map, type('::A'), :method_call)).to be(true)
      expect(a_and_b.conforms_to?(api_map, type('::B'), :method_call)).to be(true)
    end

    it 'does not conform to a type no conjunct conforms to' do
      expect(a_and_b.conforms_to?(api_map, type('::C'), :method_call)).to be(false)
    end

    it 'conforms to an identical intersection, in any conjunct order' do
      expect(a_and_b.conforms_to?(api_map, described_class.new([type('::B'), type('::A')]), :method_call)).to be(true)
    end

    it 'conforms to a narrower intersection' do
      all_three = described_class.new([type('::A'), type('::B'), type('::C')])

      expect(all_three.conforms_to?(api_map, a_and_b, :method_call)).to be(true)
    end

    it 'requires every expected conjunct to be covered' do
      expect(a_and_b.conforms_to?(api_map, described_class.new([type('::A'), type('::C')]), :method_call)).to be(false)
    end

    it 'is not satisfied by a single conjunct' do
      expect(type('::A').items.first.conforms_to?(api_map, a_and_b, :method_call)).to be(false)
    end

    it 'satisfies a duck type one conjunct provides' do
      expect(a_and_b.conforms_to?(api_map, type('#bar'), :method_call)).to be(true)
    end

    it 'conforms when any conjunct does under allow_any_match' do
      expect(a_and_b.conforms_to?(api_map, type('::A'), :method_call, [:allow_any_match])).to be(true)
    end

    it 'does not satisfy a duck type no conjunct provides' do
      expect(a_and_b.conforms_to?(api_map, type('#baz'), :method_call)).to be(false)
    end

    it 'conforms as a member of a union' do
      inferred = Solargraph::ComplexType.new([a_and_b])

      expect(inferred.conforms_to?(api_map, type('::A'), :method_call)).to be(true)
    end
  end

  context 'when answered as one member of a union' do
    it 'renders the whole intersection as its tag' do
      expect(a_and_b.to_s).to eq('A & B')
      expect(a_and_b.rooted_tags).to eq('::A & ::B')
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
  end

  context 'when asking about its conjuncts' do
    it 'is void or undefined only when every conjunct is' do
      a_and_untyped = described_class.new([type('::A'), type('undefined')])

      expect(described_class.new([type('::A'), Solargraph::ComplexType::VOID]).void?).to be(false)
      expect(a_and_untyped.undefined?).to be(false)
    end

    it 'is the nil type when one conjunct is nil' do
      a_and_nil = described_class.new([type('::A'), type('nil')])

      expect(a_and_nil.nil_type?).to be(true)
      expect(a_and_nil.nullable?).to be(false)
      expect(described_class.new([type('::A', 'nil'), type('::B', 'nil')]).nullable?).to be(true)
    end

    it 'is generic when one conjunct is' do
      generic = described_class.new([type('generic<T>'), type('::A')])

      expect(generic.any_generic?).to be(true)
      expect(a_and_b.any_generic?).to be(false)
    end

    it 'is rooted when every conjunct is' do
      expect(a_and_b).to be_all_rooted
    end

    it 'is selfy when one conjunct is' do
      expect(described_class.new([type('self'), type('::A')])).to be_selfy
    end

    it 'takes the variance the conjuncts agree on' do
      expect(a_and_b.erased_variance).to eq(:covariant)
    end
  end

  context 'when transforming' do
    it 'qualifies each conjunct' do
      intersection = described_class.new([type('A'), type('B')])

      expect(intersection.unalias_and_qualify(api_map).rooted_tags).to eq('::A & ::B')
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

    it 'has no parameters of its own to erase' do
      expect(a_and_b.erase_parameters).to equal(a_and_b)
    end

    it 'reduces Class conjunct by conjunct' do
      class_and_b = described_class.new([type('::Class<::A>'), type('::B')])

      expect(class_and_b.reduce_class_type.rooted_tags).to eq('::A & ::B')
    end

    it 'reduces Object conjunct by conjunct' do
      expect(a_and_b.reduce_object.rooted_tags).to eq('::A & ::B')
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
      combined = a_and_b.combine_via(described_class.new([type('::A'), type('::B')])) { |mine, _theirs| mine }

      expect(combined.rooted_tags).to eq('::A & ::B')
    end

    it 'qualifies each conjunct through a block' do
      qualified = described_class.new([type('A'), type('B')]).qualify_parts { |t| t.recreate(make_rooted: true) }

      expect(qualified.rooted_tags).to eq('::A & ::B')
    end

    it 'is unresolvable when a conjunct is' do
      expect(a_and_b.qualify_parts { nil }).to be_nil
    end

    it 'orders a nil conjunct last' do
      ordered = described_class.new([type('nil'), type('::A')]).order_nil_last

      expect(ordered.conjuncts.map(&:rooted_tags)).to eq(['::A', 'nil'])
    end
  end

  context 'when resolving methods' do
    it 'offers the methods of every conjunct' do
      names = a_and_b.candidate_methods_from(api_map, '', false).map(&:name)

      expect(names).to include('foo', 'bar')
    end

    it 'provides a duck method one conjunct defines' do
      expect(a_and_b.provides_duck_method?(api_map, 'foo')).to be(true)
      expect(a_and_b.provides_duck_method?(api_map, 'baz')).to be(false)
    end

    it 'finds a method on any conjunct' do
      expect(a_and_b.method_stack_pins('bar', api_map).map(&:path)).to eq(['B#bar'])
    end

    it 'finds no method no conjunct defines' do
      expect(a_and_b.method_stack_pins('baz', api_map)).to be_nil
    end
  end

  # Conjuncts here are real types given the helpers
  # https://github.com/castwide/solargraph/pull/1460 adds to ComplexType,
  # so these check Intersection's own delegation on master.
  context 'when delegating to its conjuncts' do
    # A fresh ComplexType, since ComplexType.parse returns shared
    # instances that must not carry these singleton methods.
    #
    # @param tag [String]
    # @param answers [Hash{Symbol => Object}] helper name => what it returns
    # @return [Solargraph::ComplexType]
    def conjunct tag, **answers
      Solargraph::ComplexType.new(type(tag).items).tap do |conjunct|
        answers.each { |name, answer| conjunct.define_singleton_method(name) { |*| answer } }
      end
    end

    # @param path [String]
    # @return [Solargraph::Pin::Method]
    def pin path
      namespace, name = path.split('#')
      Solargraph::Pin::Method.new(name: name, scope: :instance, closure: Solargraph::Pin::Namespace.new(name: namespace))
    end

    it 'gathers method pins from every conjunct, once each' do
      foo = pin('A#foo')
      intersection = described_class.new([conjunct('::A', method_stack_pins: [foo]),
                                          conjunct('::B', method_stack_pins: [foo, pin('B#foo')]),
                                          conjunct('::C', method_stack_pins: nil)])

      expect(intersection.method_stack_pins('foo', api_map).map(&:path)).to eq(['A#foo', 'B#foo'])
    end

    it 'has no method pins when no conjunct has any' do
      intersection = described_class.new([conjunct('::A', method_stack_pins: nil),
                                          conjunct('::B', method_stack_pins: [])])

      expect(intersection.method_stack_pins('foo', api_map)).to be_nil
    end

    it 'qualifies each conjunct through the block' do
      a = type('::A')

      expect(described_class.new([conjunct('A', qualify_parts: a)]).qualify_parts { |t| t }.conjuncts).to eq([a])
      expect(described_class.new([conjunct('A', qualify_parts: a), conjunct('B', qualify_parts: nil)])
               .qualify_parts { |t| t }).to be_nil
    end

    it 'orders nil conjuncts last' do
      nil_part = type('nil')
      a_part = type('::A')
      intersection = described_class.new([conjunct('nil', order_nil_last: nil_part),
                                          conjunct('::A', order_nil_last: a_part)])

      expect(intersection.order_nil_last.conjuncts).to eq([a_part, nil_part])
    end

    it 'rebuilds an intersection from the paired conjuncts' do
      paired = [type('::A').items.first, type('::B').items.first]
      allow(Solargraph::ComplexType::TypeMethods).to receive(:combine_members).and_return(paired)

      combined = a_and_b.combine_via(described_class.new([type('::A'), type('::B')])) { |mine, _theirs| mine }

      expect(combined.rooted_tags).to eq('::A & ::B')
    end
  end

  context 'with the Solargraph::Type contract' do
    # The methods castwide/solargraph#1231's Intersection implements,
    # less those whose body only raises.
    contract = %i[
      tags rooted_tags to_s to_rbs method_stack_pins any_generic? all_rooted? void? undefined? nil_type?
      nullable? selfy? eql? hash erased_variance conforms_to? conforms_to_unique? satisfied_by? qualify_parts
      candidate_methods_from provides_duck_method? resolve_generics_from_context resolve_generics transform
      unalias_and_qualify erase_parameters order_nil_last reduce_class_type reduce_object combine_via
      erased_version_of?
    ].freeze

    # Read the contract the way spec/type_contract_spec.rb does.
    #
    # @return [Array<Symbol>]
    def declared
      path = File.expand_path('../../lib/solargraph/type.rb', __dir__)
      Solargraph::SourceMap.load(path).pins
                           .select { |pin| pin.is_a?(Solargraph::Pin::Method) && pin.path.start_with?('Solargraph::Type#') }
                           .map { |pin| pin.name.to_sym }
    end

    it 'is a Solargraph::Type' do
      expect(described_class).to be < Solargraph::Type
    end

    it 'defines every contract method Solargraph::Type declares' do
      expect(contract - declared).to eq([])
      expect(contract.reject { |name| described_class.instance_method(name).owner == described_class }).to eq([])
    end

    it 'answers nothing public beyond the contract and Solargraph::Type' do
      extra = described_class.public_instance_methods - Solargraph::Type.public_instance_methods -
              Solargraph::Equality.public_instance_methods - contract - [:conjuncts]
      expect(extra).to eq([])
    end
  end
end
