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
  end
end
