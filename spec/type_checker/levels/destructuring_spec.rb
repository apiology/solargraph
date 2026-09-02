# frozen_string_literal: true

describe Solargraph::TypeChecker do
  context 'with level set to strong, destructuring' do
    def type_checker code
      Solargraph::TypeChecker.load_string(code, 'test.rb', :strong)
    end

    it 'destructures tuple elements onto flat block parameters' do
      checker = type_checker(%(
        class TupleBlocks
          # @return [Array<Array(String, Integer)>]
          def pairs
            [['a', 1]]
          end

          # @return [Array<String>]
          def flat_params
            pairs.map { |name, count| "\#{name.upcase} \#{count.succ}" }
          end
        end
      ))
      expect(checker.problems.map(&:message)).not_to include('Unresolved call to upcase')
      expect(checker.problems.map(&:message)).not_to include('Unresolved call to succ')
    end

    it 'projects Hash#each pair types onto block parameters' do
      checker = type_checker(%(
        class HashPairs
          # @return [Hash{Symbol => Array<String>}]
          def dict
            { a: ['x'] }
          end

          # @return [void]
          def each_pair
            dict.each { |key, vals| puts "\#{key.to_proc} \#{vals.length}" }
          end
        end
      ))
      expect(checker.problems.map(&:message)).not_to include('Unresolved call to to_proc')
      expect(checker.problems.map(&:message)).not_to include('Unresolved call to length')
    end

    it 'projects tuple element types into a destructured parameter group' do
      source = Solargraph::Source.load_string(%(
        class MlhsGroup
          # @return [Array<Array(String, Integer)>]
          def pairs
            [['a', 1]]
          end

          # @return [Hash{String => Integer}]
          def grouped
            pairs.each_with_object({}) do |(name, count), memo|
              memo[name.upcase] = count.succ
            end
          end
        end
      ), 'test.rb')
      api_map = Solargraph::ApiMap.new
      api_map.map source
      locals = api_map.source_map('test.rb').locals
      name_pin = locals.find { |l| l.name == 'name' }
      count_pin = locals.find { |l| l.name == 'count' }
      # without mlhs support the variables inside the group do not exist
      # as local pins at all
      expect(name_pin).not_to be_nil
      expect(count_pin).not_to be_nil
      expect(name_pin.typify(api_map).tag).to eq('String')
      expect(count_pin.typify(api_map).tag).to eq('Integer')
    end

    it 'creates locals for a nested destructured parameter group' do
      source = Solargraph::Source.load_string(%(
        class NestedMlhsGroup
          # @return [Array<Array((Array(String, Integer)), Symbol)>]
          def nested_pairs
            [[['a', 1], :x]]
          end

          # @return [void]
          def grouped
            nested_pairs.each do |((name, count), tag)|
              puts "\#{name} \#{count} \#{tag}"
            end
          end
        end
      ), 'test.rb')
      api_map = Solargraph::ApiMap.new
      api_map.map source
      locals = api_map.source_map('test.rb').locals
      # the recursive mlhs branch must create locals for the doubly-nested
      # group, not just the top-level one
      expect(locals.find { |l| l.name == 'name' }).not_to be_nil
      expect(locals.find { |l| l.name == 'count' }).not_to be_nil
      expect(locals.find { |l| l.name == 'tag' }).not_to be_nil
    end

    it 'keeps a union-typed pair element in one tuple position (Hash#each with union key)' do
      checker = type_checker(%(
        class UnionKeyDict
          # @return [Hash{String, Symbol => Integer}]
          def dict
            { 'a' => 1, b: 2 }
          end

          # @return [void]
          def each_pair
            dict.each { |key, count| puts "\#{key.to_s} \#{count.succ}" }
          end
        end
      ))
      expect(checker.problems).to be_empty
    end

    it 'keeps a nilable pair element in one tuple position' do
      source = Solargraph::Source.load_string(%(
        class NilableKeyDict
          # @return [Hash{String, nil => Array<String>}]
          def dict
            { 'a' => ['x'], nil => [] }
          end

          # @return [void]
          def each_pair
            dict.each do |section, tasks|
              puts tasks.length if section.nil?
            end
          end
        end
      ), 'test.rb')
      api_map = Solargraph::ApiMap.new
      api_map.map source
      locals = api_map.source_map('test.rb').locals
      section = locals.find { |l| l.name == 'section' }
      tasks = locals.find { |l| l.name == 'tasks' }
      expect(section.typify(api_map).to_s).to match(/\AString, (nil|NilClass)\z/)
      expect(tasks.typify(api_map).to_s).to eq('Array<String>')
    end

    it 'projects a union element through a destructured parameter group' do
      source = Solargraph::Source.load_string(%(
        class UnionMlhs
          # @return [Hash{String, Symbol => Integer}]
          def dict
            { 'a' => 1 }
          end

          # @return [Hash{String => Integer}]
          def grouped
            dict.each_with_object({}) do |(key, count), memo|
              memo[key.to_s] = count
            end
          end
        end
      ), 'test.rb')
      api_map = Solargraph::ApiMap.new
      api_map.map source
      locals = api_map.source_map('test.rb').locals
      key = locals.find { |l| l.name == 'key' }
      count = locals.find { |l| l.name == 'count' }
      expect(key.typify(api_map).to_s).to eq('String, Symbol')
      expect(count.typify(api_map).to_s).to eq('Integer')
    end

    it 'destructures a Hash#each pair across two plain block parameters' do
      checker = type_checker(%(
        class PlainHashEach
          # @return [Hash{String, Symbol => Array<Integer>}]
          def dict
            { 'a' => [1] }
          end

          # @return [void]
          def each_pair
            dict.each { |key, vals| puts "\#{key.to_s} \#{vals.length}" }
          end
        end
      ))
      expect(checker.problems).to be_empty
    end

    it 'destructures an Array of tuples across two plain block parameters' do
      checker = type_checker(%(
        class PlainTuplePair
          # @return [Array<Array(String, Integer)>]
          def pairs
            [['a', 1]]
          end

          # @return [Array<String>]
          def described
            pairs.map { |name, count| "\#{name.upcase} \#{count.succ}" }
          end
        end
      ))
      expect(checker.problems).to be_empty
    end

    it 'keeps a resolved position when a sibling position is an unbound generic' do
      # Bag is used unparameterized, so Elem never binds - the second
      # yielded position stays undefined while the first (a plain
      # String) still resolves. Since the positions genuinely
      # correspond one-to-one (per_position_yield_types? true) and at
      # least one resolved, typify_parameters must keep that partial
      # result instead of discarding it.
      checker = type_checker(%(
        # @generic Elem
        class Bag
          include Enumerable
          # @yieldparam [String]
          # @yieldparam [generic<Elem>]
          # @return [void]
          def each_pair; end
        end

        class Repro
          # @param bag [Bag]
          # @return [void]
          def call(bag)
            bag.each_pair { |label, item| label.upcase }
          end
        end
      ))
      expect(checker.problems.map(&:message)).not_to include('Unresolved call to upcase')
    end

    it 'leaves parameters undefined rather than assigning a whole auto-splatted value' do
      # A 4-parameter proc yields no per-position types; position 0 must
      # not be handed the whole yielded value (which produced bogus
      # "Wrong argument type ... received Array" errors)
      source = Solargraph::Source.load_string(%(
        class SplatFallback
          # @return [Proc]
          def on_retry
            proc { |exception, try, elapsed, next_int| [exception, try, elapsed, next_int] }
          end
        end
      ), 'test.rb')
      api_map = Solargraph::ApiMap.new
      api_map.map source
      locals = api_map.source_map('test.rb').locals
      %w[exception try elapsed next_int].each do |name|
        pin = locals.find { |l| l.name == name }
        expect(pin.typify(api_map)).to be_undefined
      end
    end

    it 'does not hand a non-matching-arity yielded value to the first parameter' do
      checker = type_checker(%(
        class ArityMismatch
          # @return [Array<Array<String, nil>>]
          def loose_pairs
            [['a', nil]]
          end

          # @return [Hash{String => String}]
          def collect
            # @type [Hash{String => String}]
            hash = {}
            loose_pairs.each { |key, value| hash[key] = value.to_s }
            hash
          end
        end
      ))
      # key must not be typed as the whole Array<String, nil>
      expect(checker.problems.map(&:message)).not_to(include(a_string_matching(/Wrong argument type.*key/)))
    end
  end
end
