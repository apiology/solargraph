# frozen_string_literal: true

describe Solargraph::ApiMap::Store do
  it 'indexes multiple pinsets' do
    foo_pin = Solargraph::Pin::Namespace.new(name: 'Foo')
    bar_pin = Solargraph::Pin::Namespace.new(name: 'Bar')
    store = described_class.new([foo_pin], [bar_pin])

    expect(store.get_path_pins('Foo')).to eq([foo_pin])
    expect(store.get_path_pins('Bar')).to eq([bar_pin])
  end

  it 'indexes empty pinsets' do
    foo_pin = Solargraph::Pin::Namespace.new(name: 'Foo')

    store = described_class.new([], [foo_pin])
    expect(store.get_path_pins('Foo')).to eq([foo_pin])
  end

  it 'updates existing pinsets' do
    foo_pin = Solargraph::Pin::Namespace.new(name: 'Foo')
    bar_pin = Solargraph::Pin::Namespace.new(name: 'Bar')
    baz_pin = Solargraph::Pin::Namespace.new(name: 'Baz')
    store = described_class.new([foo_pin], [bar_pin])
    store.update([foo_pin], [baz_pin])

    expect(store.get_path_pins('Foo')).to eq([foo_pin])
    expect(store.get_path_pins('Baz')).to eq([baz_pin])
    expect(store.get_path_pins('Bar')).to be_empty
  end

  it 'updates new pinsets' do
    foo_pin = Solargraph::Pin::Namespace.new(name: 'Foo')
    bar_pin = Solargraph::Pin::Namespace.new(name: 'Bar')
    store = described_class.new([foo_pin])
    store.update([foo_pin], [bar_pin])

    expect(store.get_path_pins('Foo')).to eq([foo_pin])
    expect(store.get_path_pins('Bar')).to eq([bar_pin])
  end

  it 'updates empty stores' do
    foo_pin = Solargraph::Pin::Namespace.new(name: 'Foo')
    bar_pin = Solargraph::Pin::Namespace.new(name: 'Bar')
    store = described_class.new
    store.update([foo_pin, bar_pin])

    expect(store.get_path_pins('Foo')).to eq([foo_pin])
    expect(store.get_path_pins('Bar')).to eq([bar_pin])
  end

  # @todo This will become #get_superclass
  describe '#get_superclass' do
    it 'returns simple superclasses' do
      map = Solargraph::SourceMap.load_string(%(
        class Foo; end
        class Bar < Foo; end
      ), 'test.rb')
      store = described_class.new(map.pins)
      ref = store.get_superclass('Bar')
      expect(ref.name).to eq('Foo')
    end

    it 'returns Boolean superclass' do
      store = described_class.new
      ref = store.get_superclass('TrueClass')
      expect(ref.name).to eq('Boolean')
    end

    it 'prefers a reference with type arguments over an earlier one without' do
      sub = Solargraph::Pin::Namespace.new(name: 'Sub')
      plain = Solargraph::Pin::Reference::Superclass.new(name: 'Base', closure: sub)
      parameterized = Solargraph::Pin::Reference::Superclass.new(name: 'Base', closure: sub,
                                                                 generic_values: %w[T U])
      store = described_class.new([sub, plain, parameterized])
      expect(store.get_superclass('Sub').generic_values).to eq(%w[T U])
    end

    context 'with a class declared in Ruby source and in RBS' do
      around do |example|
        require 'tmpdir'
        Dir.mktmpdir('rspec-solargraph-') do |dir|
          @temp_dir = dir
          example.run
        end
      end

      let(:api_map) do
        File.write(File.join(@temp_dir, 'sub.rbs'), <<~RBS)
          class Base[V]
            def value: () -> V
          end

          class Sub[T] < Base[T]
          end

          class HSub[K, V] < Hash[K, V]
          end
        RBS
        source_pins = Solargraph::SourceMap.load_string(%(
          class Base; end
          class Sub < Base; end
          class HSub < Hash; end
        ), 'sub.rb').pins
        rbs_pins = Solargraph::RbsMap::Path.new(@temp_dir).pins
        Solargraph::ApiMap.new(pins: Solargraph::RbsMap::Helpers.combine(source_pins, rbs_pins))
      end

      it 'resolves an inherited method through the RBS type arguments' do
        pin = api_map.get_method_stack('Sub<Integer>', 'value').first
        expect(pin.return_type.to_s).to eq('Integer')
      end

      it 'resolves an inherited method through two RBS type arguments' do
        sub_pin = api_map.get_method_stack('HSub<String, Integer>', 'values').first
        hash_pin = api_map.get_method_stack('Hash<String, Integer>', 'values').first
        expect(sub_pin.return_type.to_s).to eq(hash_pin.return_type.to_s)
      end
    end
  end

  describe 'mixin references declared twice' do
    let(:klass) { Solargraph::Pin::Namespace.new(name: 'Klass') }

    # @param ref_class [Class<Solargraph::Pin::Reference>]
    # @param extra [Hash{Symbol => Object}]
    # @return [Array(Solargraph::Pin::Reference, Solargraph::Pin::Reference)]
    def plain_and_parameterized ref_class, **extra
      [ref_class.new(name: 'Box', closure: klass, **extra),
       ref_class.new(name: '::Box', closure: klass, generic_values: ['::String'], **extra)]
    end

    it 'keeps the include with type arguments' do
      refs = plain_and_parameterized(Solargraph::Pin::Reference::Include)
      store = described_class.new([klass, *refs])
      expect(store.get_includes('Klass')).to eq([refs.last])
    end

    it 'keeps the prepend with type arguments' do
      refs = plain_and_parameterized(Solargraph::Pin::Reference::Prepend)
      store = described_class.new([klass, *refs])
      expect(store.get_prepends('Klass')).to eq([refs.last])
    end

    it 'keeps the extend with type arguments' do
      refs = plain_and_parameterized(Solargraph::Pin::Reference::Extend)
      store = described_class.new([klass, *refs])
      expect(store.get_extends('Klass')).to eq([refs.last])
    end

    it 'keeps the included mixin with type arguments' do
      refs = plain_and_parameterized(Solargraph::Pin::Reference::IncludedMixin, keyword: :extend)
      store = described_class.new([klass, *refs])
      expect(store.get_included_mixins('Klass')).to eq([refs.last])
    end

    it 'keeps included mixins applied with different keywords' do
      inc = Solargraph::Pin::Reference::IncludedMixin.new(name: 'Box', closure: klass, keyword: :include)
      ext = Solargraph::Pin::Reference::IncludedMixin.new(name: 'Box', closure: klass, keyword: :extend)
      store = described_class.new([klass, inc, ext])
      expect(store.get_included_mixins('Klass')).to eq([inc, ext])
    end
  end
end
