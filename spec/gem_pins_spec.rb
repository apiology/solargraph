# frozen_string_literal: true

require 'tmpdir'

describe Solargraph::GemPins do
  let(:workspace) { Solargraph::Workspace.new(Dir.pwd) }
  let(:doc_map) { Solargraph::DocMap.new(requires, workspace, out: nil) }
  let(:pin) { doc_map.pins.find { |pin| pin.path == path } }

  before do
    doc_map.cache_all!(STDERR) # rubocop:disable Style/GlobalStdStream
  end

  context 'with a combined method pin' do
    let(:path) { 'RBS::EnvironmentLoader#core_root' }
    let(:requires) { ['rbs'] }

    it 'can merge YARD and RBS' do
      expect(pin.source).to eq(:combined)
    end

    it 'finds types from RBS' do
      expect(pin.return_type.to_s).to eq('Pathname, nil')
    end

    it 'finds locations from YARD' do
      expect(pin.location.filename).to end_with('environment_loader.rb')
    end
  end

  context 'with a YARD-only pin' do
    let(:requires) { ['rake'] }
    let(:path) { 'Rake::Task#prerequisites' }

    it 'found a pin' do
      expect(pin.source).not_to be_nil
    end

    it 'can merge YARD and RBS' do
      expect(pin.source).to eq(:yardoc)
    end

    it 'does not find types from YARD in this case' do
      expect(pin.return_type.to_s).to eq('undefined')
    end

    it 'finds locations from YARD' do
      expect(pin.location.filename).to end_with('task.rb')
    end
  end

  context 'with a gem method on a class core also defines' do
    # Empty, so that the outer before block does not memoize bigdecimal's pins
    # in DocMap before the uncache below can take effect.
    let(:requires) { [] }

    let(:bigdecimal_map) do
      gemspec = Gem::Specification.find_by_name('bigdecimal')
      # GemPins.combine only runs when the combined entry is absent, so a
      # stale one would leave this asserting on cached output.
      Solargraph::PinCache.uncache_gem(gemspec, out: nil)
      map = Solargraph::DocMap.new(['bigdecimal'], workspace, out: nil)
      map.cache_all!(nil)
      map
    end

    # ApiMap loads core too, so this is where bigdecimal's Integer#+ and core's
    # meet - the layer the signature goes missing at.
    #
    # @param map [Solargraph::DocMap]
    # @return [Array<Array<String>>] the parameter types of each signature
    def integer_plus_param_types map
      pin = Solargraph::ApiMap.new(pins: map.pins)
                              .get_method_stack('Integer', '+', scope: :instance).first
      param_types pin
    end

    # @param pin [Solargraph::Pin::Method]
    # @return [Array<Array<String>>]
    def param_types pin
      pin.signatures.map { |sig| sig.parameters.map { |param| param.return_type.to_s } }
    end

    it "offers the gem's signature alongside core's" do
      expect(integer_plus_param_types(bigdecimal_map)).to include(['BigDecimal'])
    end

    it "still offers core's own signatures" do
      expect(integer_plus_param_types(bigdecimal_map))
        .to include(['Integer'], ['Float'], ['Rational'], ['Complex'])
    end

    it "caches the gem's signature by itself, without core's" do
      gem_pin = bigdecimal_map.pins.find { |pin| pin.path == 'Integer#+' }
      expect(param_types(gem_pin)).to eq([['BigDecimal']])
    end

    it 'accepts an argument of the type the gem declares' do
      bigdecimal_map # rebuilds the combined entry, so the check below reads pins built here

      Dir.mktmpdir do |dir|
        filename = File.join(dir, 'main.rb')
        File.write filename, <<~RUBY
          require 'bigdecimal'

          # @param big [BigDecimal]
          # @return [void]
          def add_a_decimal(big)
            1 + big
          end
        RUBY

        api_map = Solargraph::ApiMap.load(dir)
        checker = Solargraph::TypeChecker.new(filename, api_map: api_map, level: :strong)
        expect(checker.problems.map(&:message)).to be_empty
      end
    end
  end

  describe '.combine_method_pins_by_path' do
    let(:requires) { [] }
    let(:closure) { Solargraph::Pin::Namespace.new(name: 'Foo') }

    it 'merges method pins sharing a path and passes everything else through' do
      constant = Solargraph::Pin::Constant.new(name: 'BAR', closure: closure)
      from_core = Solargraph::Pin::Method.new(name: 'baz', closure: closure, scope: :instance,
                                              comments: '@return [String]')
      from_gem = Solargraph::Pin::Method.new(name: 'baz', closure: closure, scope: :instance,
                                             comments: '@return [Integer]')
      elsewhere = Solargraph::Pin::Method.new(name: 'qux', closure: closure, scope: :instance,
                                              comments: '@return [Symbol]')

      out = described_class.combine_method_pins_by_path([from_core, from_gem, elsewhere, constant])

      expect(out.map(&:path)).to contain_exactly('Foo#baz', 'Foo#qux', 'Foo::BAR')
      expect(out.find { |pin| pin.path == 'Foo#baz' }.return_type.to_s).to eq('String, Integer')
    end
  end
end
