# frozen_string_literal: true

describe Solargraph::ComplexType do
  let(:api_map) do
    Solargraph::ApiMap.new
  end

  it 'validates simple core types' do
    exp = described_class.parse('String')
    inf = described_class.parse('String')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(true)
  end

  it 'invalidates simple core types' do
    exp = described_class.parse('String')
    inf = described_class.parse('Integer')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(false)
  end

  it 'allows subtype skew if told' do
    exp = described_class.parse('Array<Integer>')
    inf = described_class.parse('Array<String>')
    match = inf.conforms_to?(api_map, exp, :method_call, [:allow_subtype_skew])
    expect(match).to be(true)
  end

  it 'allows covariant behavior in parameters of Array' do
    exp = described_class.parse('Array<Object>')
    inf = described_class.parse('Array<Integer>')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(true)
  end

  it 'does not allow contravariant behavior in parameters of Array' do
    exp = described_class.parse('Array<Integer>')
    inf = described_class.parse('Array<Object>')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(false)
  end

  it 'allows covariant behavior in key types of Hash' do
    exp = described_class.parse('Hash{Object => String}')
    inf = described_class.parse('Hash{Integer => String}')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(true)
  end

  it 'accepts valid tuple conformance' do
    exp = described_class.parse('Array(Integer, Integer)')
    inf = described_class.parse('Array(Integer, Integer)')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(true)
  end

  it 'rejects invalid tuple conformance' do
    exp = described_class.parse('Array(Integer, Integer)')
    inf = described_class.parse('Array(Integer, String)')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(false)
  end

  it 'allows empty params when specified' do
    exp = described_class.parse('Array(Integer, Integer)')
    inf = described_class.parse('Array')
    match = inf.conforms_to?(api_map, exp, :method_call, [:allow_empty_params])
    expect(match).to be(true)
  end

  it 'validates expected superclasses' do
    source = Solargraph::Source.load_string(%(
      class Sup; end
      class Sub < Sup; end
    ))
    api_map.map source
    sup = described_class.parse('Sup')
    sub = described_class.parse('Sub')
    match = sub.conforms_to?(api_map, sup, :method_call)
    expect(match).to be(true)
  end

  it 'handles singleton types compared against their literals' do
    pending 'side of effect of inference changes'
    exp = Solargraph::ComplexType::UniqueType.new('nil', rooted: true)
    inf = Solargraph::ComplexType::UniqueType.new('NilClass', rooted: true)
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(true)
  end

  # it 'invalidates inferred superclasses (expected must be super)' do
  # # @todo This test might be invalid. There are use cases where inheritance
  # #   between inferred and expected classes should be acceptable in either
  # #   direction.
  # # source = Solargraph::Source.load_string(%(
  # #   class Sup; end
  # #   class Sub < Sup; end
  # # ))
  # # api_map.map source
  # # sup = described_class.parse('Sup')
  # # sub = described_class.parse('Sub')
  # # match = Solargraph::TypeChecker::Checks.types_match?(api_map, sub, sup)
  # # expect(match).to be(false)
  # end

  it 'fuzzy matches arrays with parameters' do
    exp = described_class.parse('Array')
    inf = described_class.parse('Array<String>')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(true)
  end

  it 'fuzzy matches sets with parameters' do
    source = Solargraph::Source.load_string("require 'set'")
    source_map = Solargraph::SourceMap.map(source)
    api_map.catalog Solargraph::Bench.new(source_maps: [source_map], external_requires: ['set'])
    exp = described_class.parse('Set')
    inf = described_class.parse('Set<String>')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(true)
  end

  it 'fuzzy matches hashes with parameters' do
    exp = described_class.parse('Hash{ Symbol => String}')
    inf = described_class.parse('Hash')
    match = inf.conforms_to?(api_map, exp, :method_call, [:allow_empty_params])
    expect(match).to be(true)
  end

  it 'reshapes a Hash into key/value pairs to conform to a lower-arity Enumerable ancestor' do
    exp = described_class.parse('Enumerable<Array(Symbol, String)>')
    inf = described_class.parse('Hash{Symbol => String}')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(true)
  end

  it 'reshapes any hash-shaped (parameters_type == :hash) type into pairs, not just Hash' do
    # YARD's `{K => V}` tag syntax produces parameters_type == :hash for
    # any class name, not just Hash - PairBag proves the reshape is
    # structural, not name-based.
    source = Solargraph::Source.load_string(%(
      class PairBag
        include Enumerable
      end
    ))
    api_map.map source
    exp = described_class.parse('Enumerable<Array(Symbol, String)>')
    inf = described_class.parse('PairBag{Symbol => String}')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(true)
  end

  it 'reshapes a :list-parameterized (ordinary <A, B> generic) 2-arity type into a tuple ' \
     'to conform to a lower-arity Enumerable ancestor' do
    # `Pair` uses ordinary `<A, B>` generic syntax (parameters_type ==
    # :list), not YARD's `{K => V}` hash tag - the same reshape must
    # apply to both param shapes.
    source = Solargraph::Source.load_string(%(
      # @generic A, B
      class Pair
        include Enumerable

        # @param a [generic<A>]
        # @param b [generic<B>]
        def initialize(a, b)
          @a = a
          @b = b
        end

        # @yieldparam [Array(generic<A>, generic<B>)]
        def each
          yield [@a, @b]
        end
      end
    ))
    api_map.map source
    exp = described_class.parse('Enumerable<Array(Symbol, String)>')
    inf = described_class.parse('Pair<Symbol, String>')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(true)
  end

  it 'does not reshape a 2-arity :list type that does not include Enumerable' do
    source = Solargraph::Source.load_string(%(
      # @generic A, B
      class NotEnumerablePair
        # @param a [generic<A>]
        # @param b [generic<B>]
        def initialize(a, b)
          @a = a
          @b = b
        end
      end
    ))
    api_map.map source
    exp = described_class.parse('Enumerable<Array(Symbol, String)>')
    inf = described_class.parse('NotEnumerablePair<Symbol, String>')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(false)
  end

  it 'reshapes a 3-arity :list type into a 3-tuple to conform to a lower-arity Enumerable ancestor' do
    source = Solargraph::Source.load_string(%(
      # @generic A, B, C
      class Triple
        include Enumerable

        # @param a [generic<A>]
        # @param b [generic<B>]
        # @param c [generic<C>]
        def initialize(a, b, c)
          @a = a
          @b = b
          @c = c
        end

        # @yieldparam [Array(generic<A>, generic<B>, generic<C>)]
        def each
          yield [@a, @b, @c]
        end
      end
    ))
    api_map.map source
    exp = described_class.parse('Enumerable<Array(Symbol, String, Integer)>')
    inf = described_class.parse('Triple<Symbol, String, Integer>')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(true)

    exp2 = described_class.parse('Enumerable<Array(Symbol, String)>')
    expect(inf.conforms_to?(api_map, exp2, :method_call)).to be(false)
  end

  it 'does not reshape a :list type into a tuple for a lower-arity ancestor whose own ' \
     'generic param is unrelated to the inferred type\'s params' do
    # Taggable's X has no relation to Pair's A/B (unlike Enumerable, RBS-
    # bound to Hash's K/V via `include Enumerable[[K, V]]`) - an arity
    # mismatch alone must not wrap [A, B] into a tuple and call it X.
    source = Solargraph::Source.load_string(%(
      # @generic X
      module Taggable
      end

      # @generic A, B
      class Pair
        include Taggable

        # @param a [generic<A>]
        # @param b [generic<B>]
        def initialize(a, b)
          @a = a
          @b = b
        end
      end
    ))
    api_map.map source
    exp = described_class.parse('Taggable<Array(Symbol, String)>')
    inf = described_class.parse('Pair<Symbol, String>')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(false)
  end

  it 'does not reshape a 3-arity :list type into a tuple for a 2-arity non-Enumerable ancestor' do
    source = Solargraph::Source.load_string(%(
      # @generic X, Y
      module Labeled
      end

      # @generic A, B, C
      class Triple2
        include Labeled

        # @param a [generic<A>]
        # @param b [generic<B>]
        # @param c [generic<C>]
        def initialize(a, b, c)
          @a = a
          @b = b
          @c = c
        end
      end
    ))
    api_map.map source
    exp = described_class.parse('Labeled<Array(Symbol, String, Integer), Integer>')
    inf = described_class.parse('Triple2<Symbol, String, Integer>')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(false)
  end

  it 'does not reshape a hash-shaped type into a tuple for a lower-arity, non-Enumerable ' \
     'ancestor whose own generic param is unrelated to the inferred type\'s key/value types' do
    pending 'pre-existing conflation in key_types_conform?/subtypes_conform?, not introduced ' \
            'by pair_shaped_viewed_as_pairs? - see comment below'
    # key_types_conform?/subtypes_conform? compares a hash-shaped inferred's
    # value type against a list-shaped expected's param positionally - the
    # same false positive reproduces with no pair-shaping logic involved.
    source = Solargraph::Source.load_string(%(
      # @generic X
      module Taggable
      end

      class PairBag2
        include Taggable
      end
    ))
    api_map.map source
    exp = described_class.parse('Taggable<String>')
    inf = described_class.parse('PairBag2{Symbol => String}')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(false)
  end

  it 'matches multiple types' do
    exp = described_class.parse('String, Integer')
    inf = described_class.parse('String, Integer')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(true)
  end

  it 'matches multiple types out of order' do
    exp = described_class.parse('String, Integer')
    inf = described_class.parse('Integer, String')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(true)
  end

  it 'invalidates inferred types missing from expected' do
    exp = described_class.parse('String')
    inf = described_class.parse('String, Integer')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(false)
  end

  it 'matches nil' do
    exp = described_class.parse('nil')
    inf = described_class.parse('nil')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(true)
  end

  it 'validates classes with expected superclasses' do
    exp = described_class.parse('Class<Object>')
    inf = described_class.parse('Class<String>')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(true)
  end

  it 'validates generic classes with expected Class' do
    inf = described_class.parse('Class<String>')
    exp = described_class.parse('Class')
    match = inf.conforms_to?(api_map, exp, :method_call)
    expect(match).to be(true)
  end

  context 'with invariant matching' do
    it 'rejects String matching an Object' do
      inf = described_class.parse('String')
      exp = described_class.parse('Object')
      match = inf.conforms_to?(api_map, exp, :method_call, variance: :invariant)
      expect(match).to be(false)
    end

    it 'rejects Object matching an String' do
      inf = described_class.parse('Object')
      exp = described_class.parse('String')
      match = inf.conforms_to?(api_map, exp, :method_call, variance: :invariant)
      expect(match).to be(false)
    end

    it 'accepts String matching a String' do
      inf = described_class.parse('String')
      exp = described_class.parse('String')
      match = inf.conforms_to?(api_map, exp, :method_call, variance: :invariant)
      expect(match).to be(true)
    end
  end

  context 'with contravariant matching' do
    it 'rejects String matching an Objet' do
      inf = described_class.parse('String')
      exp = described_class.parse('Object')
      match = inf.conforms_to?(api_map, exp, :method_call, variance: :contravariant)
      expect(match).to be(false)
    end

    it 'accepts Object matching an String' do
      inf = described_class.parse('Object')
      exp = described_class.parse('String')
      match = inf.conforms_to?(api_map, exp, :method_call, variance: :contravariant)
      expect(match).to be(true)
    end

    it 'accepts String matching a String' do
      inf = described_class.parse('String')
      exp = described_class.parse('String')
      match = inf.conforms_to?(api_map, exp, :method_call, variance: :contravariant)
      expect(match).to be(true)
    end
  end

  context 'with an inheritence relationship' do
    let(:source) do
      Solargraph::Source.load_string(%(
        class Sup; end
        class Sub < Sup; end
      ))
    end
    let(:sup) { described_class.parse('Sup') }
    let(:sub) { described_class.parse('Sub') }

    before do
      api_map.map source
    end

    it 'validates inheritance in one way' do
      match = sub.conforms_to?(api_map, sup, :method_call, [:allow_reverse_match])
      expect(match).to be(true)
    end

    it 'validates inheritance the other way' do
      match = sup.conforms_to?(api_map, sub, :method_call, [:allow_reverse_match])
      expect(match).to be(true)
    end
  end

  context 'with inheritance relationship in allow_reverse_match mode' do
    let(:api_map) { Solargraph::ApiMap.new }
    let(:sup) { described_class.parse('String') }
    let(:sub) { described_class.parse('Array') }

    it 'conforms one way' do
      match = sub.conforms_to?(api_map, sup, :method_call, [:allow_reverse_match])
      expect(match).to be(false)
    end

    it 'conforms the other way' do
      match = sup.conforms_to?(api_map, sub, :method_call, [:allow_reverse_match])
      expect(match).to be(false)
    end
  end
end
