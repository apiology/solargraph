# frozen_string_literal: true

describe Solargraph::ApiMap::Constants do
  describe '#resolve' do
    it 'returns an absolute constant for a relative constant' do
      source_map = Solargraph::SourceMap.load_string(%(
        module Foo
          module Bar
            Baz = 'baz'
          end
          module Quuz
            include Bar
          end
        end
      ), 'test.rb')
      store = Solargraph::ApiMap::Store.new(source_map.pins)
      constants = Solargraph::ApiMap::Constants.new(store)
      pin = source_map.first_pin('Foo::Quuz')
      resolved = constants.resolve('Bar', pin.gates)
      expect(resolved).to eq('Foo::Bar')
    end
  end

  describe '#dereference' do
    it 'returns fully qualified namespaces for includes' do
      source_map = Solargraph::SourceMap.load_string(%(
        module Foo
          module Bar
            Baz = 'baz'
          end
          module Quuz
            include Bar
          end
        end
      ), 'test.rb')
      store = Solargraph::ApiMap::Store.new(source_map.pins)
      constants = Solargraph::ApiMap::Constants.new(store)
      pin = source_map.pins_by_class(Solargraph::Pin::Reference::Include).first
      resolved = constants.dereference(pin)
      expect(resolved).to eq('Foo::Bar')
    end

    it 'returns fully qualified namespaces for superclasses' do
      source_map = Solargraph::SourceMap.load_string(%(
        class Foo; end
        class Bar < Foo; end
      ), 'test.rb')
      store = Solargraph::ApiMap::Store.new(source_map.pins)
      constants = Solargraph::ApiMap::Constants.new(store)
      pin = source_map.pins_by_class(Solargraph::Pin::Reference::Superclass).first
      resolved = constants.dereference(pin)
      expect(resolved).to eq('Foo')
    end
  end

  describe '#collect' do
    it 'finds constants from includes' do
      source_map = Solargraph::SourceMap.load_string(%(
        module Foo
          module Bar
            Baz = 'baz'
          end
          module Quuz
            include Bar
          end
        end
      ), 'test.rb')
      store = Solargraph::ApiMap::Store.new(source_map.pins)
      constants = Solargraph::ApiMap::Constants.new(store)
      collected = constants.collect('Foo::Quuz').map(&:path)
      expect(collected).to eq(['Foo::Bar::Baz'])
    end
  end
end
