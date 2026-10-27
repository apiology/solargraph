# frozen_string_literal: true

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
    def server body
      %(
        class Server
          #: () -> { name: String, port: Integer }
          def config
            { name: 'web', port: 80 }
          end

          #: () -> { name: String }
          def named
            { name: 'web' }
          end

          #: () -> { name: String, ?port: Integer }
          def options
            { name: 'web' }
          end

          #: () -> { 'id' => Integer }
          def ids
            { 'id' => 1 }
          end

          #{body}
        end
      )
    end

    it 'accepts the record where a matching Hash is expected' do
      expect(messages(server(%(
        # @param settings [Hash{Symbol => String, Integer}]
        # @return [void]
        def apply(settings); end

        # @return [void]
        def run
          apply(config)
        end
      )))).to be_empty
    end

    it 'accepts the record where a matching record is expected' do
      expect(messages(server(%(
        #: ({ name: String, port: Integer }) -> void
        def apply(settings); end

        # @return [void]
        def run
          apply(config)
        end
      )))).to be_empty
    end

    it 'rejects the record where a Hash with other key types is expected' do
      expect(messages(server(%(
        # @param settings [Hash{String => String}]
        # @return [void]
        def apply(settings); end

        # @return [void]
        def run
          apply(config)
        end
      ))))
        .to eq(['Wrong argument type for Server#apply: settings expected Hash{String => String}, ' \
                'received Hash{Symbol => String, Integer}'])
    end

    it 'rejects the record at alpha level where a Hash of narrower values is expected' do
      # Strong level allows this downcast; alpha does not.
      expect(messages(server(%(
        # @param settings [Hash{Symbol => String}]
        # @return [void]
        def apply(settings); end

        # @return [void]
        def run
          apply(config)
        end
      )), :alpha))
        .to include('Wrong argument type for Server#apply: settings expected Hash{Symbol => String}, ' \
                    'received Hash{Symbol => String, Integer}')
    end

    it 'accepts a record without an optional field where the field is optional' do
      expect(messages(server(%(
        #: ({ name: String, ?port: Integer }) -> void
        def apply(settings); end

        # @return [void]
        def run
          apply(named)
        end
      )))).to be_empty
    end

    it 'rejects a record without a required field where the field is required' do
      pending 'https://github.com/apiology/solargraph/pull/284'
      expect(messages(server(%(
        #: ({ name: String, port: Integer }) -> void
        def apply(settings); end

        # @return [void]
        def run
          apply(named)
        end
      ))))
        .to include(a_string_starting_with('Wrong argument type for Server#apply: settings expected'))
    end

    it 'rejects a string-keyed record where a record with another key is expected' do
      pending 'https://github.com/castwide/solargraph/pull/1451'
      expect(messages(server(%(
        #: ({ 'name' => Integer }) -> void
        def apply(settings); end

        # @return [void]
        def run
          apply(ids)
        end
      ))))
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
    def server body
      %(
        class Server
          #: () -> { name: String, port: Integer }
          def config
            { name: 'web', port: 80 }
          end

          #: () -> { name: String, ?port: Integer }
          def options
            { name: 'web' }
          end

          #{body}
        end
      )
    end

    it 'infers a value read from the record as the union of field types' do
      expect(messages(server(%(
        # @return [String, Integer, nil]
        def name
          config[:name]
        end
      )))).to be_empty
    end

    # Hash#[] adds nil for any Hash, and a record is still a Hash to
    # Solargraph, so the precise form of a required field read is
    # `String, nil`.
    it 'infers each field read with [] by its own type' do
      pending 'https://github.com/castwide/solargraph/pull/1451 ' \
              'https://github.com/apiology/solargraph/pull/284'
      expect(messages(server(%(
        # @return [void]
        def run
          # @type [String, nil]
          name = config[:name]

          # @type [Integer, nil]
          port = config[:port]
        end
      )))).to be_empty
    end

    it 'infers an optional field read with [] by its own type' do
      pending 'https://github.com/castwide/solargraph/pull/1451 ' \
              'https://github.com/apiology/solargraph/pull/284'
      expect(messages(server(%(
        # @return [void]
        def run
          # @type [Integer, nil]
          port = options[:port]
        end
      )))).to be_empty
    end
  end

  # Ported from castwide/solargraph#1231's intersection specs, with each
  # YARD intersection of literal-keyed Hashes written as an RBS record and
  # each expected type as an inline RBS return type.
  context 'when dispatching Hash methods per key' do
    # Typecheck problems from `readers`, methods reading the record that
    # a `record` method returns, typed `record_type` and built by `returning`.
    def problems_reading_record record_type:, returning:, readers:
      messages(%(
        class Repro
          #: () -> #{record_type}
          def record
            #{returning}
          end

          #{readers}
        end
      ))
    end

    it 'dispatches generic methods per key on a record with two literal keys' do
      pending 'https://github.com/castwide/solargraph/pull/1451 ' \
              'https://github.com/apiology/solargraph/pull/284 ' \
              'https://github.com/castwide/solargraph/pull/1266'
      problems = problems_reading_record(
        record_type: "{ 'Index' => Float, 'Triggers' => Array[{ 'Name' => String }] }",
        returning: "{ 'Index' => 1.0, 'Triggers' => [{ 'Name' => 'x' }] }",
        readers: %(
          #: () -> Float
          def index
            record.fetch('Index')
          end

          #: () -> Array[{ 'Name' => String }]
          def triggers
            record.fetch('Triggers')
          end
        )
      )
      expect(problems).to be_empty
    end

    it 'dispatches generic methods per key regardless of field order' do
      pending 'https://github.com/castwide/solargraph/pull/1451 ' \
              'https://github.com/apiology/solargraph/pull/284 ' \
              'https://github.com/castwide/solargraph/pull/1266'
      problems = problems_reading_record(
        record_type: "{ 'Triggers' => Array[{ 'Name' => String }], 'Index' => Float }",
        returning: "{ 'Triggers' => [{ 'Name' => 'x' }], 'Index' => 1.0 }",
        readers: %(
          #: () -> Array[{ 'Name' => String }]
          def triggers
            record.fetch('Triggers')
          end

          #: () -> Float
          def index
            record.fetch('Index')
          end
        )
      )
      expect(problems).to be_empty
    end

    it 'dispatches generic methods per key for symbol keys' do
      pending 'https://github.com/castwide/solargraph/pull/1451 ' \
              'https://github.com/apiology/solargraph/pull/284 ' \
              'https://github.com/castwide/solargraph/pull/1266'
      problems = problems_reading_record(
        record_type: '{ Index: Float, Triggers: Array[{ Name: String }] }',
        returning: "{ Index: 1.0, Triggers: [{ Name: 'x' }] }",
        readers: %(
          #: () -> Float
          def index
            record.fetch(:Index)
          end

          #: () -> Array[{ Name: String }]
          def triggers
            record.fetch(:Triggers)
          end
        )
      )
      expect(problems).to be_empty
    end

    it 'resolves a non-generic method on a record with two literal keys' do
      problems = problems_reading_record(
        record_type: "{ 'Index' => Float, 'Triggers' => Array[{ 'Name' => String }] }",
        returning: "{ 'Index' => 1.0, 'Triggers' => [{ 'Name' => 'x' }] }",
        readers: %(
          #: () -> Integer
          def count
            record.size
          end
        )
      )
      expect(problems).to be_empty
    end
  end

  context 'when rendering a record from an RBS file' do
    around do |example|
      require 'tmpdir'
      Dir.mktmpdir('rspec-solargraph-') do |dir|
        @temp_dir = dir
        example.run
      end
    end

    let(:conversions) do
      loader = RBS::EnvironmentLoader.new(core_root: nil, repository: RBS::Repository.new(no_stdlib: false))
      loader.add(path: Pathname(@temp_dir))
      Solargraph::RbsMap::Conversions.new(loader: loader)
    end

    before do
      File.write(File.join(@temp_dir, 'foo.rbs'), <<~RBS)
        class Foo
          def config: () -> { name: String, ?port: Integer, nick: String }
          def mixed: () -> { name: String, 'id' => Integer }
          def server: () -> { name: String, port: Integer }
          def ids: () -> { 'id' => Integer }
        end
      RBS
    end

    def method_pin name
      conversions.pins.find { |pin| pin.path == "Foo##{name}" }
    end

    it 'maps the fields to a Hash of Symbol to their value types' do
      expect(method_pin('config').return_type.tag).to eq('Hash{Symbol => String, Integer}')
    end

    it 'maps each kind of literal key to its class' do
      expect(method_pin('mixed').return_type.tag).to eq('Hash{Symbol, String => String, Integer}')
    end

    it 'degrades the record to a Hash in YARD output' do
      expect(method_pin('server').detail).to eq('=> Hash{Symbol => String, Integer}')
    end

    it 'renders the record back to RBS' do
      pending 'https://github.com/castwide/solargraph/pull/1451 ' \
              'https://github.com/apiology/solargraph/pull/284'
      expect(method_pin('server').return_type.to_rbs).to eq('{ name: ::String, port: ::Integer }')
    end

    it 'renders optional fields back to RBS' do
      pending 'https://github.com/castwide/solargraph/pull/1451 ' \
              'https://github.com/apiology/solargraph/pull/284'
      expect(method_pin('config').return_type.to_rbs).to eq('{ name: ::String, ?port: ::Integer, nick: ::String }')
    end

    it 'renders string keys back to RBS' do
      pending 'https://github.com/castwide/solargraph/pull/1451'
      expect(method_pin('ids').return_type.to_rbs).to eq("{ 'id' => ::Integer }")
    end

    it 'renders the record in the method signature' do
      pending 'https://github.com/castwide/solargraph/pull/1451 ' \
              'https://github.com/apiology/solargraph/pull/284'
      expect(method_pin('server').to_rbs).to eq('def server: () -> { name: ::String, port: ::Integer }')
    end
  end

  context 'with an inline RBS record parameter' do
    it 'infers a field of the parameter inside the method' do
      pending 'https://github.com/castwide/solargraph/pull/1441'
      expect(messages(%(
        class Server
          #: ({ name: String, port: Integer }) -> void
          def apply(opts)
            # @type [String, Integer, nil]
            name = opts[:name]
          end
        end
      ))).to be_empty
    end

    it 'infers a field of the parameter by its own type' do
      pending 'https://github.com/castwide/solargraph/pull/1441 ' \
              'https://github.com/castwide/solargraph/pull/1451 ' \
              'https://github.com/apiology/solargraph/pull/284'
      expect(messages(%(
        class Server
          #: ({ name: String, port: Integer }) -> void
          def apply(opts)
            # @type [String, nil]
            name = opts[:name]
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
    def assertion body
      %(
        class Server
          # @return [Hash]
          def load
            {}
          end

          #{body}
        end
      )
    end

    it 'infers a field of the asserted variable' do
      pending 'https://github.com/castwide/solargraph/pull/1444'
      expect(messages(assertion(%(
        # @return [String, Integer, nil]
        def name
          config = load #: { name: String, port: Integer }
          config[:name]
        end
      )))).to be_empty
    end

    it 'infers a field of the asserted variable by its own type' do
      pending 'https://github.com/castwide/solargraph/pull/1444 ' \
              'https://github.com/castwide/solargraph/pull/1451 ' \
              'https://github.com/apiology/solargraph/pull/284'
      expect(messages(assertion(%(
        # @return [String, nil]
        def name
          config = load #: { name: String, port: Integer }
          config[:name]
        end
      )))).to be_empty
    end

    it 'reports a mismatched value assigned to the asserted variable' do
      pending 'https://github.com/castwide/solargraph/pull/1444'
      expect(messages(assertion(%(
        # @return [void]
        def run
          config = 'web' #: { name: String, port: Integer }
        end
      ))))
        .to include(a_string_including('does not match inferred type'))
    end
  end
end
