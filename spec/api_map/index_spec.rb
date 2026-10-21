# frozen_string_literal: true

describe Solargraph::ApiMap::Index do
  subject(:output_pins) { described_class.new(input_pins).pins }

  describe '#map_overrides' do
    let(:foo_class) do
      Solargraph::Pin::Namespace.new(name: 'Foo')
    end

    let(:foo_initialize) do
      init = Solargraph::Pin::Method.new(name: 'initialize',
                                         scope: :instance,
                                         parameters: [],
                                         closure: foo_class)
      # no return type specified
      param = Solargraph::Pin::Parameter.new(name: 'bar',
                                             closure: init)
      init.parameters << param
      init
    end

    let(:foo_new) do
      init = Solargraph::Pin::Method.new(name: 'new',
                                         scope: :class,
                                         parameters: [],
                                         closure: foo_class)
      # no return type specified
      param = Solargraph::Pin::Parameter.new(name: 'bar',
                                             closure: init)
      init.parameters << param
      init
    end

    let(:foo_override) do
      Solargraph::Pin::Reference::Override.from_comment('Foo#initialize',
                                                        '@param [String] bar')
    end

    let(:input_pins) do
      [
        foo_initialize,
        foo_new,
        foo_override
      ]
    end

    it 'has a docstring to process on override' do
      expect(foo_override.docstring.tags).to be_empty
    end

    it 'overrides .new method' do
      method_pin = output_pins.find { |pin| pin.path == 'Foo.new' }
      first_parameter = method_pin.parameters.first
      expect(first_parameter.return_type.tag).to eq('String')
    end

    it 'overrides #initialize method in signature' do
      method_pin = output_pins.find { |pin| pin.path == 'Foo#initialize' }
      first_parameter = method_pin.parameters.first
      expect(first_parameter.return_type.tag).to eq('String')
    end
  end

  describe 'overriding yield tags' do
    let(:source) do
      Solargraph::Source.load_string(%(
        module Initializable
          def initializer(name, &blk); end
        end

        # @!override Initializable#initializer
        #   @yieldparam app [String]
        #   @yieldreturn [void]

        class Railtie
          extend Initializable

          initializer 'setup' do |app|
            app
          end
        end
      ), 'test.rb')
    end

    let(:api_map) { Solargraph::ApiMap.new.map(source) }

    it 'types the block parameters of an existing block signature' do
      expect(api_map.clip_at('test.rb', [13, 14]).infer.to_s).to eq('String')
    end

    it 'replaces the block signature of each signature' do
      method_pin = api_map.get_path_pins('Initializable#initializer').first
      blocks = method_pin.signatures.map(&:block)
      expect(blocks.map { |block| [block.parameters.map(&:return_type).map(&:to_s), block.return_type.to_s] })
        .to eq([[['String'], 'void']])
    end
  end
end
