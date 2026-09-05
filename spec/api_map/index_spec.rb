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

    it 'resyncs #initialize comments to match its overridden docstring' do
      method_pin = output_pins.find { |pin| pin.path == 'Foo#initialize' }
      expect(method_pin.comments).to eq("#{method_pin.docstring.to_raw}\n")
    end

    it 'resyncs .new comments to match its overridden docstring' do
      method_pin = output_pins.find { |pin| pin.path == 'Foo.new' }
      expect(method_pin.comments).to eq("#{method_pin.docstring.to_raw}\n")
    end

    context 'when the override targets a pin class that is not a method' do
      let(:input_pins) do
        [foo_class,
         Solargraph::Pin::Constant.new(name: 'BAR', closure: foo_class),
         Solargraph::Pin::Reference::Override.from_comment('Foo::BAR', '@deprecated use something else')]
      end

      it 'applies the override instead of raising on a pin that cannot take new comments' do
        pending 'https://github.com/castwide/solargraph/pull/1104'
        constant_pin = output_pins.find { |pin| pin.path == 'Foo::BAR' }
        expect(constant_pin.docstring.tag(:deprecated)).not_to be_nil
      end
    end
  end
end
