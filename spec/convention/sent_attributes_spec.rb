# frozen_string_literal: true

describe Solargraph::Convention::SentAttributes do
  # @param namespace [String]
  # @param code [String]
  # @return [Array<Solargraph::Pin::Method>]
  def method_pins_for namespace, code
    Solargraph::SourceMap.load_string(code).pins.select do |pin|
      pin.is_a?(Solargraph::Pin::Method) && pin.namespace == namespace
    end
  end

  # @param pins [Array<Solargraph::Pin::Method>]
  # @return [Array<Array(String, Symbol)>]
  def accessors pins
    pins.map { |pin| [pin.name, pin.context.scope] }.sort
  end

  it 'maps attributes declared with send' do
    pins = method_pins_for 'Foo', %(
      class Foo
        send(:attr_accessor, :bar)
        send(:attr_reader, :baz)
        send(:attr_writer, 'qux')
      end
    )
    expect(accessors(pins)).to eq([
                                    ['bar', :instance],
                                    ['bar=', :instance],
                                    ['baz', :instance],
                                    ['qux=', :instance]
                                  ])
  end

  it 'maps attributes declared with public_send on self' do
    pins = method_pins_for 'Foo', %(
      class Foo
        self.public_send(:attr_accessor, :bar)
        class << self
          send :attr_reader, :baz
        end
      end
    )
    expect(accessors(pins)).to eq([
                                    ['bar', :instance],
                                    ['bar=', :instance],
                                    ['baz', :class]
                                  ])
  end

  it 'types the writer parameter from the documented return type' do
    pins = method_pins_for 'Foo', %(
      class Foo
        # @return [String]
        send(:attr_accessor, :bar)
      end
    )
    writer = pins.find { |pin| pin.name == 'bar=' }
    expect(writer.parameters.map { |param| [param.name, param.return_type.tag] }).to eq([%w[value String]])
  end

  it 'keeps the visibility of attributes declared with send' do
    pins = method_pins_for 'Foo', %(
      class Foo
        private
        send(:attr_reader, :bar)
      end
    )
    expect(pins.map(&:visibility)).to eq([:private])
  end

  it 'maps attributes sent to a constant onto that namespace' do
    pins = method_pins_for 'Foo::Bar', %(
      Foo::Bar.send(:attr_accessor, :baz)
    )
    expect(pins.map(&:path)).to eq(['Foo::Bar#baz', 'Foo::Bar#baz='])
    expect(pins.map(&:visibility)).to eq(%i[public public])
  end

  it 'exposes attributes sent to a constant as methods of that class' do
    api_map = Solargraph::ApiMap.new
    api_map.map Solargraph::Source.load_string(%(
      module Foo
        class Bar; end
      end
      Foo::Bar.send(:attr_accessor, :baz)
    ), 'test.rb')
    methods = api_map.get_methods('Foo::Bar', scope: :instance)
    expect(methods.map(&:name)).to include('baz', 'baz=')
  end

  it 'ignores send calls that do not declare attributes' do
    pins = method_pins_for 'Foo', %(
      class Foo
        send(:define_method, :bar) { 1 }
        send(name, :baz)
        other.send(:attr_accessor, :qux)
      end
    )
    expect(pins.map(&:name)).not_to include('bar', 'baz', 'qux', 'qux=')
  end

  it 'skips attribute names that are not symbol or string literals' do
    pins = method_pins_for 'Foo', %(
      class Foo
        NAMES = %i[a b].freeze
        send(:attr_writer, *NAMES, name, 'baz')
      end
    )
    expect(accessors(pins)).to eq([['baz=', :instance]])
  end
end
