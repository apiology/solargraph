# frozen_string_literal: true

require 'tmpdir'

# RBS record types, e.g. `{ name: String, ?port: Integer }`, from RBS
# input through typechecking to RBS and YARD output. Solargraph types a
# record as a Hash of its key classes to the union of its field types;
# pending examples need per-key precision or other open PRs.
describe Solargraph::RbsTranslator do
  def type_checker code, level = :strong
    Solargraph::TypeChecker.load_string(code, 'test.rb', level)
  end

  def messages code, level = :strong
    type_checker(code, level).problems.map(&:message)
  end

  context 'when typechecking a record from an inline RBS return type' do
    it 'accepts the record where a matching Hash is expected' do
      expect(messages(%(
        class Server
          #: () -> { name: String, port: Integer }
          def config
            { name: 'web', port: 80 }
          end

          # @param settings [Hash{Symbol => String, Integer}]
          # @return [void]
          def apply(settings); end

          # @return [void]
          def run
            apply(config)
          end
        end
      ))).to be_empty
    end

    it 'accepts the record where a matching record is expected' do
      expect(messages(%(
        class Server
          #: () -> { name: String, port: Integer }
          def config
            { name: 'web', port: 80 }
          end

          #: ({ name: String, port: Integer }) -> void
          def apply(settings); end

          # @return [void]
          def run
            apply(config)
          end
        end
      ))).to be_empty
    end

    it 'rejects the record where a Hash with other key types is expected' do
      expect(messages(%(
        class Server
          #: () -> { name: String, port: Integer }
          def config
            { name: 'web', port: 80 }
          end

          # @param settings [Hash{String => String}]
          # @return [void]
          def apply(settings); end

          # @return [void]
          def run
            apply(config)
          end
        end
      )))
        .to eq(['Wrong argument type for Server#apply: settings expected Hash{String => String}, ' \
                'received Hash{Symbol => String, Integer}'])
    end

    it 'rejects the record at alpha level where a Hash of narrower values is expected' do
      # Strong level allows this downcast; alpha does not.
      expect(messages(%(
        class Server
          #: () -> { name: String, port: Integer }
          def config
            { name: 'web', port: 80 }
          end

          # @param settings [Hash{Symbol => String}]
          # @return [void]
          def apply(settings); end

          # @return [void]
          def run
            apply(config)
          end
        end
      ), :alpha))
        .to include('Wrong argument type for Server#apply: settings expected Hash{Symbol => String}, ' \
                    'received Hash{Symbol => String, Integer}')
    end

    it 'accepts a record without an optional field where the field is optional' do
      expect(messages(%(
        class Server
          #: () -> { name: String }
          def named
            { name: 'web' }
          end

          #: ({ name: String, ?port: Integer }) -> void
          def apply(settings); end

          # @return [void]
          def run
            apply(named)
          end
        end
      ))).to be_empty
    end

    it 'rejects a record without a required field where the field is required' do
      pending 'https://github.com/apiology/solargraph/pull/284'
      expect(messages(%(
        class Server
          #: () -> { name: String }
          def named
            { name: 'web' }
          end

          #: ({ name: String, port: Integer }) -> void
          def apply(settings); end

          # @return [void]
          def run
            apply(named)
          end
        end
      )))
        .to include(a_string_starting_with('Wrong argument type for Server#apply: settings expected'))
    end

    it 'rejects a string-keyed record where a record with another key is expected' do
      pending 'https://github.com/castwide/solargraph/pull/1451'
      expect(messages(%(
        class Server
          #: () -> { 'id' => Integer }
          def ids
            { 'id' => 1 }
          end

          #: ({ 'name' => Integer }) -> void
          def apply(settings); end

          # @return [void]
          def run
            apply(ids)
          end
        end
      )))
        .to include(a_string_starting_with('Wrong argument type for Server#apply: settings expected'))
    end

    it 'rejects a hash literal with a mismatched field returned where a record is declared' do
      pending 'https://github.com/castwide/solargraph/pull/1352'
      expect(messages(%(
        class Server
          #: () -> { name: String, port: Integer }
          def config
            { name: 'web', port: :http }
          end
        end
      ))).to include(a_string_starting_with('Declared return type'))
    end

    it 'accepts a matching hash literal at alpha level where a record is declared' do
      pending 'https://github.com/castwide/solargraph/pull/1352'
      expect(messages(%(
        class Server
          #: () -> { name: String, port: Integer }
          def config
            { name: 'web', port: 80 }
          end
        end
      ), :alpha)).to be_empty
    end
  end

  context 'when reading fields of a record' do
    it 'infers a value read from the record as the union of field types' do
      expect(messages(%(
        class Server
          #: () -> { name: String, port: Integer }
          def config
            { name: 'web', port: 80 }
          end

          #: () -> (String | Integer)?
          def name
            config[:name]
          end
        end
      ))).to be_empty
    end

    it 'types each required field by its own type' do
      pending 'https://github.com/castwide/solargraph/pull/1104 ' \
              'https://github.com/castwide/solargraph/pull/1459 ' \
              'https://github.com/castwide/solargraph/pull/1460 ' \
              'https://github.com/castwide/solargraph/pull/1451 ' \
              'https://github.com/castwide/solargraph/pull/1385'
      expect(messages(%(
        class Server
          #: () -> { name: String, port: Integer }
          def config
            { name: 'web', port: 80 }
          end

          #: () -> String
          def name
            config[:name]
          end

          #: () -> Integer
          def port
            config[:port]
          end
        end
      ))).to be_empty
    end

    it 'types an optional field by its own type or nil' do
      pending 'https://github.com/castwide/solargraph/pull/1104 ' \
              'https://github.com/castwide/solargraph/pull/1459 ' \
              'https://github.com/castwide/solargraph/pull/1460 ' \
              'https://github.com/castwide/solargraph/pull/1451 ' \
              'https://github.com/castwide/solargraph/pull/1385'
      expect(messages(%(
        class Server
          #: () -> { name: String, ?port: Integer }
          def options
            { name: 'web' }
          end

          #: () -> Integer?
          def port
            options[:port]
          end
        end
      ))).to be_empty
    end

    it 'types each field by its own type when fields are declared in any order' do
      pending 'https://github.com/castwide/solargraph/pull/1104 ' \
              'https://github.com/castwide/solargraph/pull/1459 ' \
              'https://github.com/castwide/solargraph/pull/1460 ' \
              'https://github.com/castwide/solargraph/pull/1451 ' \
              'https://github.com/castwide/solargraph/pull/1385'
      expect(messages(%(
        class Repro
          #: () -> { port: Integer, name: String }
          def record
            { port: 80, name: 'web' }
          end

          #: () -> String
          def name
            record[:name]
          end

          #: () -> Integer
          def port
            record[:port]
          end
        end
      ))).to be_empty
    end

    it 'types each field by its own type for string keys' do
      pending 'https://github.com/castwide/solargraph/pull/1104 ' \
              'https://github.com/castwide/solargraph/pull/1459 ' \
              'https://github.com/castwide/solargraph/pull/1460 ' \
              'https://github.com/castwide/solargraph/pull/1451 ' \
              'https://github.com/castwide/solargraph/pull/1385'
      expect(messages(%(
        class Repro
          #: () -> { 'name' => String, 'port' => Integer }
          def record
            { 'name' => 'web', 'port' => 80 }
          end

          #: () -> String
          def name
            record['name']
          end

          #: () -> Integer
          def port
            record['port']
          end
        end
      ))).to be_empty
    end

    it 'resolves a method the record has as a Hash' do
      expect(messages(%(
        class Repro
          #: () -> { name: String, port: Integer }
          def record
            { name: 'web', port: 80 }
          end

          #: () -> Integer
          def count
            record.size
          end
        end
      ))).to be_empty
    end
  end

  context 'with a record type in a .rbs file' do
    # The method pin Solargraph builds for `path` from the RBS source `rbs`
    def pin_from_rbs rbs, path
      Dir.mktmpdir('rspec-solargraph-') do |dir|
        File.write(File.join(dir, 'test.rbs'), rbs)
        loader = RBS::EnvironmentLoader.new(core_root: nil, repository: RBS::Repository.new(no_stdlib: false))
        loader.add(path: Pathname(dir))
        Solargraph::RbsMap::Conversions.new(loader: loader).pins.find { |pin| pin.path == path }
      end
    end

    it 'types the method as returning a Hash of Symbol to the field types' do
      pin = pin_from_rbs(<<~RBS, 'Server#config')
        class Server
          def config: () -> { name: String, ?port: Integer, nick: String }
        end
      RBS

      expect(pin.return_type.tag).to eq('Hash{Symbol => String, Integer}')
    end

    it 'types each kind of literal key by its class' do
      pin = pin_from_rbs(<<~RBS, 'Server#mixed')
        class Server
          def mixed: () -> { name: String, 'id' => Integer }
        end
      RBS

      expect(pin.return_type.tag).to eq('Hash{Symbol, String => String, Integer}')
    end

    it 'shows the record as a Hash in YARD output' do
      pin = pin_from_rbs(<<~RBS, 'Server#config')
        class Server
          def config: () -> { name: String, port: Integer }
        end
      RBS

      expect(pin.detail).to eq('=> Hash{Symbol => String, Integer}')
    end

    it 'prints the return type back as the same record' do
      pending 'https://github.com/castwide/solargraph/pull/1104 ' \
              'https://github.com/castwide/solargraph/pull/1459 ' \
              'https://github.com/castwide/solargraph/pull/1460'
      pin = pin_from_rbs(<<~RBS, 'Server#config')
        class Server
          def config: () -> { name: String, port: Integer }
        end
      RBS

      expect(pin.return_type.to_rbs).to eq('{ name: ::String, port: ::Integer }')
    end

    it 'prints optional fields back as optional' do
      pending 'https://github.com/castwide/solargraph/pull/1104 ' \
              'https://github.com/castwide/solargraph/pull/1459 ' \
              'https://github.com/castwide/solargraph/pull/1460'
      pin = pin_from_rbs(<<~RBS, 'Server#config')
        class Server
          def config: () -> { name: String, ?port: Integer, nick: String }
        end
      RBS

      expect(pin.return_type.to_rbs).to eq('{ name: ::String, ?port: ::Integer, nick: ::String }')
    end

    it 'prints string keys back as string keys' do
      pending 'https://github.com/castwide/solargraph/pull/1104 ' \
              'https://github.com/castwide/solargraph/pull/1459 ' \
              'https://github.com/castwide/solargraph/pull/1460'
      pin = pin_from_rbs(<<~RBS, 'Server#ids')
        class Server
          def ids: () -> { 'id' => Integer }
        end
      RBS

      expect(pin.return_type.to_rbs).to eq("{ 'id' => ::Integer }")
    end

    it 'prints the record in the method signature' do
      pending 'https://github.com/castwide/solargraph/pull/1104 ' \
              'https://github.com/castwide/solargraph/pull/1459 ' \
              'https://github.com/castwide/solargraph/pull/1460'
      pin = pin_from_rbs(<<~RBS, 'Server#config')
        class Server
          def config: () -> { name: String, port: Integer }
        end
      RBS

      expect(pin.to_rbs).to eq('def config: () -> { name: ::String, port: ::Integer }')
    end
  end

  context 'with an inline RBS record parameter' do
    it 'infers a field of the parameter inside the method' do
      pending 'https://github.com/castwide/solargraph/pull/1441'
      expect(messages(%(
        class Server
          #: ({ name: String, port: Integer }) -> (String | Integer)?
          def apply(opts)
            opts[:name]
          end
        end
      ))).to be_empty
    end

    it 'infers a field of the parameter by its own type' do
      pending 'https://github.com/castwide/solargraph/pull/1441 ' \
              'https://github.com/castwide/solargraph/pull/1104 ' \
              'https://github.com/castwide/solargraph/pull/1459 ' \
              'https://github.com/castwide/solargraph/pull/1460 ' \
              'https://github.com/castwide/solargraph/pull/1451 ' \
              'https://github.com/castwide/solargraph/pull/1385'
      expect(messages(%(
        class Server
          #: ({ name: String, port: Integer }) -> String
          def apply(opts)
            opts[:name]
          end
        end
      ))).to be_empty
    end

    it 'reports a caller passing a Hash with other key types' do
      expect(messages(%(
        class Server
          #: ({ name: String, port: Integer }) -> void
          def apply(opts); end

          # @param settings [Hash{String => String}]
          # @return [void]
          def run(settings)
            apply(settings)
          end
        end
      )))
        .to eq(['Wrong argument type for Server#apply: opts expected Hash{Symbol => String, Integer}, ' \
                'received Hash{String => String}'])
    end

    it 'returns a record to callers' do
      expect(messages(%(
        class Server
          #: ({ name: String, port: Integer }) -> { ok: bool }
          def apply(opts)
            { ok: true }
          end

          # @return [Boolean, nil]
          def run
            apply({ name: 'web', port: 80 })[:ok]
          end
        end
      ))).to be_empty
    end
  end

  context 'with an inline RBS record assertion on an assignment' do
    it 'infers a field of the asserted variable' do
      pending 'https://github.com/castwide/solargraph/pull/1444'
      expect(messages(%(
        class Server
          # @return [Hash]
          def load
            {}
          end

          #: () -> (String | Integer)?
          def name
            config = load #: { name: String, port: Integer }
            config[:name]
          end
        end
      ))).to be_empty
    end

    it 'infers a field of the asserted variable by its own type' do
      pending 'https://github.com/castwide/solargraph/pull/1444 ' \
              'https://github.com/castwide/solargraph/pull/1104 ' \
              'https://github.com/castwide/solargraph/pull/1459 ' \
              'https://github.com/castwide/solargraph/pull/1460 ' \
              'https://github.com/castwide/solargraph/pull/1451 ' \
              'https://github.com/castwide/solargraph/pull/1385'
      expect(messages(%(
        class Server
          # @return [Hash]
          def load
            {}
          end

          #: () -> String
          def name
            config = load #: { name: String, port: Integer }
            config[:name]
          end
        end
      ))).to be_empty
    end

    it 'reports a mismatched value assigned to the asserted variable' do
      pending 'https://github.com/castwide/solargraph/pull/1444'
      expect(messages(%(
        class Server
          # @return [void]
          def run
            config = 'web' #: { name: String, port: Integer }
          end
        end
      )))
        .to include(a_string_including('does not match inferred type'))
    end
  end
end
