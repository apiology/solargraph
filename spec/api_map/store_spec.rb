# frozen_string_literal: true

describe Solargraph::ApiMap::Store do
  it 'indexes multiple pinsets' do
    foo_pin = Solargraph::Pin::Namespace.new(name: 'Foo')
    bar_pin = Solargraph::Pin::Namespace.new(name: 'Bar')
    store = Solargraph::ApiMap::Store.new([foo_pin], [bar_pin])

    expect(store.get_path_pins('Foo')).to eq([foo_pin])
    expect(store.get_path_pins('Bar')).to eq([bar_pin])
  end

  it 'indexes empty pinsets' do
    foo_pin = Solargraph::Pin::Namespace.new(name: 'Foo')

    store = Solargraph::ApiMap::Store.new([], [foo_pin])
    expect(store.get_path_pins('Foo')).to eq([foo_pin])
  end

  it 'updates existing pinsets' do
    foo_pin = Solargraph::Pin::Namespace.new(name: 'Foo')
    bar_pin = Solargraph::Pin::Namespace.new(name: 'Bar')
    baz_pin = Solargraph::Pin::Namespace.new(name: 'Baz')
    store = Solargraph::ApiMap::Store.new([foo_pin], [bar_pin])
    store.update([foo_pin], [baz_pin])

    expect(store.get_path_pins('Foo')).to eq([foo_pin])
    expect(store.get_path_pins('Baz')).to eq([baz_pin])
    expect(store.get_path_pins('Bar')).to be_empty
  end

  it 'updates new pinsets' do
    foo_pin = Solargraph::Pin::Namespace.new(name: 'Foo')
    bar_pin = Solargraph::Pin::Namespace.new(name: 'Bar')
    store = Solargraph::ApiMap::Store.new([foo_pin])
    store.update([foo_pin], [bar_pin])

    expect(store.get_path_pins('Foo')).to eq([foo_pin])
    expect(store.get_path_pins('Bar')).to eq([bar_pin])
  end

  it 'updates empty stores' do
    foo_pin = Solargraph::Pin::Namespace.new(name: 'Foo')
    bar_pin = Solargraph::Pin::Namespace.new(name: 'Bar')
    store = Solargraph::ApiMap::Store.new
    store.update([foo_pin, bar_pin])

    expect(store.get_path_pins('Foo')).to eq([foo_pin])
    expect(store.get_path_pins('Bar')).to eq([bar_pin])
  end

  # @todo This will become #get_superclass
  describe '#get_superclass_pin' do
    it 'returns simple superclasses' do
      map = Solargraph::SourceMap.load_string(%(
        class Foo; end
        class Bar < Foo; end
      ), 'test.rb')
      store = Solargraph::ApiMap::Store.new(map.pins)
      ref = store.get_superclass_pin('Bar')
      expect(ref.name).to eq('Foo')
    end

    it 'returns Boolean superclass' do
      store = Solargraph::ApiMap::Store.new
      ref = store.get_superclass_pin('TrueClass')
      expect(ref.name).to eq('Boolean')
    end

    it 'maps core Errno classes' do
      map = Solargraph::RbsMap::CoreMap.new
      store = Solargraph::ApiMap::Store.new(map.pins)
      Errno.constants.each do |const|
        pin = store.get_path_pins("Errno::#{const}").first
        expect(pin).to be_a(Solargraph::Pin::Namespace)
        superclass = store.get_superclass_pin(pin.path)
        expect(superclass.name).to eq('::SystemCallError')
        expect(store.constants.dereference(superclass)).to eq('SystemCallError')
      end
    end
  end
end
