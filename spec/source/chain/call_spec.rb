# frozen_string_literal: true

# Contributes a fixed set of pins to every source map, standing in for
# the pins a resolved `require` brings in from a gem or the stdlib.
# Specs assign #pins, register it, and unregister it again afterwards.
class RbsPinConvention < Solargraph::Convention::Base
  class << self
    # @return [Array<Solargraph::Pin::Base>]
    attr_accessor :pins
  end

  self.pins = []

  # @param _source_map [Solargraph::SourceMap]
  # @return [Solargraph::Environ]
  def local _source_map
    Solargraph::Environ.new(pins: self.class.pins)
  end
end

describe Solargraph::Source::Chain::Call do
  it 'recognizes core methods that return subtypes' do
    api_map = Solargraph::ApiMap.new
    source = Solargraph::Source.load_string(%(
      # @type [Array<String>]
      arr = []
      arr.first
    ))
    api_map.map source
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(3, 11))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map(nil).locals)
    expect(type.tag).to eq('String')
  end

  it 'recognizes core methods that return self' do
    api_map = Solargraph::ApiMap.new
    source = Solargraph::Source.load_string(%(
      arr = []
      arr.clone
    ))
    api_map.map source
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(2, 11))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map(nil).locals)
    expect(type.tag).to eq('Array')
  end

  it 'handles super calls to same method' do
    api_map = Solargraph::ApiMap.new
    source = Solargraph::Source.load_string(%(
      class Foo
        def my_method
          123
        end
      end
      class Bar < Foo
        def my_method
          456 + super
        end
      end
      Bar.new.my_method))
    api_map.map source
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(11, 14))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map(nil).locals)
    expect(type.tag).to eq('Integer')
  end

  it 'infers return types based on yield call and @yieldreturn' do
    api_map = Solargraph::ApiMap.new
    source = Solargraph::Source.load_string(%(
      class Foo
        # @yieldreturn [Integer]
        def my_method(&block)
          yield
        end
      end
      Foo.new.my_method))
    api_map.map source
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(7, 14))
    locals = api_map.source_map(nil).locals
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, locals)
    expect(type.tag).to eq('Integer')
  end

  it 'infers return types based only on yield call and @yieldreturn' do
    api_map = Solargraph::ApiMap.new
    source = Solargraph::Source.load_string(%(
      class Foo
        # @yieldreturn [Integer]
        def my_method(&block)
          yield
        end
      end
      Foo.new.my_method { "foo" }))
    api_map.map source
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(7, 32))
    locals = api_map.source_map(nil).locals
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, locals)
    expect(type.tag).to eq('Integer')
  end

  it 'adds virtual constructors for <Class>.new calls with conflicting return types' do
    api_map = Solargraph::ApiMap.new
    source = Solargraph::Source.load_string(%(
      class Foo
        # @return [String]
        def self.new; end
      end
      Foo.new
    ))
    api_map.map source
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(4, 11))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map(nil).locals)
    expect(type.tag).to eq('String')
  end

  it 'infers types from macros' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @!macro
        #   @return [$1]
        def self.bar; end
      end
      Foo.bar(String)
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map(source)
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(6, 10))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, [])
    expect(type.tag).to eq('String')
  end

  it 'falls through a non-macro directive that names no registered macro' do
    # @!visibility is a directive but not a macro, so `bar`'s pin has
    # macros: [] and directives: [VisibilityDirective] - this exercises
    # inferred_pins's directive branch, distinct from the macro branch
    # covered above. Since no macro is registered under that directive's
    # name, process_directive resolves nothing and falls through to
    # ordinary body-probing, which infers String from the method body.
    source = Solargraph::Source.load_string(%(
      # @!visibility public
      def bar
        "hi"
      end

      bar
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map(source)
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(6, 9))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.rooted_tags).to eq('"hi"')
  end

  it 'expands a named macro reached through a non-macro directive that shares its name' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @!macro mymacro
        #   @return [$1]
        def self.template; end

        # @!method mymacro
        def bar(arg); end
      end
      Foo.new.bar(String)
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map(source)
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(9, 17))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('String')
  end

  it 'infers generic types from Array#reverse' do
    source = Solargraph::Source.load_string(%(
      # @type [Array<String>]
      list = array_of_strings
      list.reverse
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(3, 11))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('Array<String>')
  end

  it 'infers constant return types via returns, ignoring blocks' do
    source = Solargraph::Source.load_string(%(
      def yielder(&blk)
        "foo"
      end

      yielder do
        123
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(7, 8))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.simple_tags).to eq('String')
  end

  it 'infers generic parameterized types through module inclusion' do
    source = Solargraph::Source.load_string(%(
      # @generic GenericTypeParam
      module Foo
        # @return [Array<generic<GenericTypeParam>>]
        def baz
        end
      end

      class Baz
        # @return [Baz<String>]
        def self.bar
        end

        include Foo
      end

      Baz.bar.baz
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(16, 15))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('Array<String>')
  end

  it 'infers generic parameterized types through module inclusion via RBS definition of module' do
    source = Solargraph::Source.load_string(%(
      foo = ['bar'].to_set

      foo
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(3, 9))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('Set<String>')
  end

  it 'infers generic-class method return values with self reference' do
    source = Solargraph::Source.load_string(%(
      # @generic GenericTypeParam
      module Foo
        # @return [Hash<generic<GenericTypeParam>, self>]
        def baz
        end
      end

      class Baz
        # @return [Baz<String>]
        def self.bar
        end

        include Foo
      end

      Baz.bar.baz
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(16, 15))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('Hash<String, Baz<String>>')
  end

  it 'infers generic-class method return values with self reference through RBS definition' do
    source = Solargraph::Source.load_string(%(
      a = ['bar']
      # @param item [String]
      foo = a.to_set.classify do |item|
       item.class
      end

      foo
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(3, 12))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('Array<String>')
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(3, 20))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('Set<String>')
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(4, 17))
    block_pin = api_map.source_map('test.rb').pins.find { |p| p.is_a?(Solargraph::Pin::Block) }
    type = chain.infer(api_map, block_pin, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('Class<String>')
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(7, 9))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('Hash{Class<String> => Set<String>}')
  end

  it 'infers method return types' do
    source = Solargraph::Source.load_string(%(
      def bar
        123
      end

      def baz
        bar
      end

      baz
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(9, 9))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.simple_tags).to eq('Integer')
  end

  it 'infers method return types based on method generic' do
    pending('deeper inference support')

    source = Solargraph::Source.load_string(%(
      class Foo
        # @Generic A
        # @param x [generic<A>]
        # @return [generic<A>]
        def bar(x); end
      end

      foo = Foo.new
      a = foo.bar("baz")
      a
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(10, 6))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('String')
  end

  it 'infers method return types with unused blocks' do
    source = Solargraph::Source.load_string(%(
      def bar
        123
      end

      def baz(&block)
        bar
      end

      baz { "foo" }
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(9, 9))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.simple_tags).to eq('Integer')
  end

  it 'infers generic types from @generic tag' do
    source = Solargraph::Source.load_string(%(
      # @generic GenericTypeParam
      class Foo
        # @return [Foo<String>]
        def self.bar
        end

        # @return [Array<generic<GenericTypeParam>>]
        def baz
        end
      end

      Foo.bar.baz
      Foo.bar.baz.first
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(12, 15))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('Array<String>')
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(13, 20))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('String')
  end

  it 'infers generic return types from @generic tag when method also takes an unused block param' do
    source = Solargraph::Source.load_string(%(
      class Foo
        def initialize; end
        def foo_method; 1; end
      end

      class Repro
        # @generic T
        # @param clazz [Class<generic<T>>]
        # @return [generic<T>]
        def create_object(clazz, &unused)
          clazz.new
        end
      end

      Repro.new.create_object(Foo)
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(15, 20))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('Foo')
  end

  it 'infers generic return types from block from yield being a return node' do
    pending('deeper inference support')

    source = Solargraph::Source.load_string(%(
      def yielder(&blk)
        yield
      end

      yielder do
        123
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(7, 9))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('Integer')
  end

  it 'infers types from union type' do
    source = Solargraph::Source.load_string(%(
      # @type [String, Float]
      list = string_or_float
      list.upcase
      list.ceil
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source

    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(3, 11))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('String')

    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(4, 11))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('Integer')
  end

  it 'infers generic types from union type' do
    source = Solargraph::Source.load_string(%(
      # @type [String, Array<Integer>]
      list = string_or_integer
      list.upcase
      list.each
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source

    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(3, 11))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('String')

    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(4, 11))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    # Array#each's enumerator overload is `() -> ::Enumerator[Elem, self]`, so
    # `self` resolves to the Array<Integer> arm that supplied the pin rather
    # than to the whole String, Array<Integer> union.
    expect(type.tag).to eq('Enumerator<Integer, Array<Integer>>')
  end

  it 'resolves an RBS self return type to the union arm that supplied the method' do
    source = Solargraph::Source.load_string(%(
      # @type [String, Symbol]
      name = string_or_symbol
      name.to_sym
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source

    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(3, 11))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    # String#to_sym is `-> Symbol`; Symbol#to_sym is `-> self`, which narrows
    # to Symbol rather than expanding to the String, Symbol receiver.
    expect(type.tag).to eq('Symbol')
  end

  it 'resolves a shared self-returning method separately for each union arm' do
    source = Solargraph::Source.load_string(%(
      # @type [String, Symbol]
      name = string_or_symbol
      name.itself
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source

    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(3, 11))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    # Kernel#itself is `-> self` and is the same pin for both arms, so the
    # result is the union of each arm's own self type.
    expect(type.rooted_tags).to eq('::String, ::Symbol')
  end

  it 'resolves a YARD @return [self] to the union arm that supplied the method' do
    source = Solargraph::Source.load_string(%(
      class Alpha
        # @return [Symbol]
        def to_thing; end
      end

      class Beta
        # @return [self]
        def to_thing; end
      end

      # @type [Alpha, Beta]
      thing = alpha_or_beta
      thing.to_thing
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source

    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(13, 14))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    # `self` in a YARD @return tag reaches the same resolution as an RBS `self`
    # return type, so Beta#to_thing narrows to Beta instead of expanding to the
    # whole Alpha, Beta receiver.
    expect(type.rooted_tags).to eq('::Symbol, ::Beta')
  end

  it 'distributes a YARD self nested in a generic across union arms' do
    source = Solargraph::Source.load_string(%(
      class Base
        # @return [Array<self>]
        def many; end
      end

      class Alpha < Base; end
      class Beta < Base; end

      # @type [Alpha, Beta]
      thing = alpha_or_beta
      thing.many
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source

    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(11, 14))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    # Base#many is one pin shared by both arms, so `self` inside the generic
    # resolves once per arm rather than collapsing to Array<Alpha, Beta>.
    expect(type.rooted_tags).to eq('::Array<::Alpha>, ::Array<::Beta>')
  end

  it 'allows calls off of nilable objects by default' do
    source = Solargraph::Source.load_string(%(
      # @type [String, nil]
      f = foo
      a = f.upcase
      a
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source

    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(4, 6))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('String')
  end

  it 'calculates class return type based on class generic' do
    source = Solargraph::Source.load_string(%(
      # @generic A
      class Foo
        # @return [generic<A>]
        def bar; end
      end

      # @type [Foo<String>]
      f = Foo.new
      a = f.bar
      a
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source

    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(10, 7))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('String')
  end

  it 'resolves same-class generics from a union independently of declaration order' do
    # https://github.com/castwide/solargraph/issues/1272
    ['Box<Integer>, Box<String>', 'Box<String>, Box<Integer>'].each do |union_tag|
      source = Solargraph::Source.load_string(%(
        # @generic T
        class Box
          # @return [generic<T>]
          def get; end
        end

        # @type [#{union_tag}]
        b = boxed
        c = b.get
        c
      ), 'test.rb')
      api_map = Solargraph::ApiMap.new
      api_map.map source

      chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(10, 7))
      type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
      expect(type.items.map(&:tag).sort).to eq(%w[Integer String])
    end
  end

  it 'denies calls off of nilable objects when loose union mode is off' do
    source = Solargraph::Source.load_string(%(
      # @type [String, nil]
      f = foo
      a = f.upcase
      a
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new(loose_unions: false)
    api_map.map source

    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(4, 6))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('undefined')
  end

  it 'denies calls on a two-class union when loose union mode is off and only one class defines the method' do
    pending 'strict union mode does not deny a call when only one of two plain classes defines it'
    source = Solargraph::Source.load_string(%(
      class A
        # @return [void]
        def foo; end
      end

      class B
      end

      # @type [A, B]
      x = make
      x.foo
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new(loose_unions: false)
    api_map.map source

    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(10, 8))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.tag).to eq('undefined')
  end

  it 'preserves unions in value position in Hash' do
    source = Solargraph::Source.load_string(%(
      # @param params [Hash{String => Array<undefined>, Hash{String => undefined}, String, Integer}]
      def foo(params)
        position = params['position']
        position
        col = position['character']
        col
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new
    api_map.map source

    foo_pin = api_map.source_map('test.rb').pins.find { |p| p.name == 'foo' }
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(4, 8))
    type = chain.infer(api_map, foo_pin, api_map.source_map('test.rb').locals)
    expect(type.rooted_tags).to eq('::Array, ::Hash{::String => undefined}, ::String, ::Integer, nil')
  end

  it 'preserves undefined and underdefined tyypes in resolution' do
    source = Solargraph::Source.load_string(%(
      # @param params [Hash{String => Array<undefined>, Hash{String => undefined}, String, Integer}]
      def foo(params)
        position = params['position']
        position
        col = position['character']
        col
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new
    api_map.map source

    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(6, 8))
    type = chain.infer(api_map, Solargraph::Pin::ROOT_PIN, api_map.source_map('test.rb').locals)
    expect(type.rooted_tags).to eq('undefined')
  end

  it 'does not infer undefined types when declared ones exist' do
    source = Solargraph::Source.load_string(%(
      # @return [Array<String>]
      def other; end
      def foo
        parts = [''] + other
        parts
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new
    api_map.map source

    foo_pin = api_map.source_map('test.rb').pins.find { |p| p.name == 'foo' }
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(5, 8))
    type = chain.infer(api_map, foo_pin, api_map.source_map('test.rb').locals)
    expect(type.rooted_tags).to eq('::Array<::String>')
  end

  it 'understands types in an Array#+ scenario' do
    source = Solargraph::Source.load_string(%(
      module A
        class B
          def c
            ([B.new] + [B.new]).each do |d|
              d
            end
          end
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new
    api_map.map source

    closure_pin = api_map.source_map('test.rb').pins.find do |p|
      p.is_a?(Solargraph::Pin::Block) && p.location.range.start.line == 4
    end

    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(5, 14))
    type = chain.infer(api_map, closure_pin, api_map.source_map('test.rb').locals)
    expect(type.tags).to eq('A::B')
  end

  it 'qualifies types in an Array#+ scenario' do
    source = Solargraph::Source.load_string(%(
      module A
        class B
          def c
            ([B.new] + [B.new]).each do |d|
              d
            end
          end
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new
    api_map.map source

    closure_pin = api_map.source_map('test.rb').pins.find do |p|
      p.is_a?(Solargraph::Pin::Block) && p.location.range.start.line == 4
    end

    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(5, 14))
    type = chain.infer(api_map, closure_pin, api_map.source_map('test.rb').locals)
    expect(type.rooted_tags).to eq('::A::B')
  end

  it 'handles subclass and superclass issues in Array#+' do
    source = Solargraph::Source.load_string(%(
      module A
        class B; end
        class C < B
          def c
            ([B.new] + [C.new]).each do |d|
              d
            end
          end
          def d
            ([C.new] + [B.new]).each do |d|
              d
            end
          end
       end
     end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source

    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(6, 14))
    closure_pin = api_map.source_map('test.rb').pins.find do |p|
      p.is_a?(Solargraph::Pin::Block) && p.location.range.start.line == 5
    end
    type = chain.infer(api_map, closure_pin, api_map.source_map('test.rb').locals)
    expect(type.rooted_tags).to eq('::A::B').or eq('::A::B, ::A::C').or eq('::A::C, ::A::B')

    closure_pin = api_map.source_map('test.rb').pins.find do |p|
      p.is_a?(Solargraph::Pin::Block) && p.location.range.start.line == 10
    end
    chain = Solargraph::Source::SourceChainer.chain(source, Solargraph::Position.new(11, 14))
    type = chain.infer(api_map, closure_pin, api_map.source_map('test.rb').locals)
    # valid options here:
    #   * emit type checker warning when adding [B.new] and type whole thing as '::A::B'
    #   * type whole thing as '::A::B, A::C'
    #   * type as undefined
    expect(type.rooted_tags).to eq('::A::B, ::A::C').or eq('::A::C, ::A::B').or be_undefined
    expect(type.rooted_tags).not_to eq('::A::C')
  end

  it 'qualifies types in a second Array#+' do
    source = Solargraph::Source.load_string(%(
      module A1
        class B1
          # @return [Array<A::D::E>]
          def foo; end
        end
      end
      module A
        module D
          class E; end
        end
        class B; end
        class C < B
          def e
            ([D::E.new] + [D::E.new]).each do |d|
              d
            end
          end
          def f
            de1 = [D::E.new]
            de2 = [D::E.new]
            (de1 + de2).each do |d|
              d
            end
          end
          # @return [Array<D::E>]
          attr_reader :g
          # @return [Array<D::E>]
          attr_reader :h
          def i
            de1 = [D::E.new]
            (g + de1).each do |d|
              d
            end
          end
          def j
            (g + h).each do |d|
              d
            end
          end
          def k
            arr1 = A1::B1.new.foo + h
            arr1
            arr1.each do |d1|
              d1
            end
          end
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source

    clip = api_map.clip_at('test.rb', [15, 14])
    expect(clip.infer.rooted_tags).to eq('::A::D::E')

    clip = api_map.clip_at('test.rb', [22, 14])
    expect(clip.infer.rooted_tags).to eq('::A::D::E')

    clip = api_map.clip_at('test.rb', [32, 14])
    expect(clip.infer.rooted_tags).to eq('::A::D::E')

    clip = api_map.clip_at('test.rb', [37, 14])
    expect(clip.infer.rooted_tags).to eq('::A::D::E')

    clip = api_map.clip_at('test.rb', [42, 12])
    expect(clip.infer.rooted_tags).to eq('::Array<::A::D::E>')
  end

  it 'correctly looks up civars' do
    source = Solargraph::Source.load_string(%(
      class Foo
        BAZ = /aaa/

        # @param comment [String]
        def bar(comment)
          b = ("foo" =~ BAZ)
          b
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source

    clip = api_map.clip_at('test.rb', [7, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')
  end

  it 'does not mis-parse generic methods with type constraints' do
    source = Solargraph::Source.load_string(%(
      def bl
        out = (Encoding.default_external = 'UTF-8')
        out
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source

    clip = api_map.clip_at('test.rb', [3, 8])
    expect(clip.infer.rooted_tags).to eq('"UTF-8"')
  end

  it 'sends proper gates in ProxyType' do
    source = Solargraph::Source.load_string(%(
      module Foo
        module Bar
          class Symbol
          end
        end
      end

      module Foo
        module Baz
          class Quux
            # @return [void]
            def foo
              s = objects_by_class(Bar::Symbol)
              s
            end

            # @generic T
            # @param klass [Class<generic<T>>]
            # @return [Set<generic<T>>]
            def objects_by_class klass
              # @type [Set<generic<T>>]
              s = Set.new
              s
            end
          end
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source

    clip = api_map.clip_at('test.rb', [14, 14])
    expect(clip.infer.rooted_tags).to eq('::Set<::Foo::Bar::Symbol>')
  end

  it 'accepts a word with no location, for external callers that omit it' do
    expect { described_class.new('foo') }.not_to raise_error
  end

  # Serves an RBS file's pins through the public Convention extension
  # point, standing in for the pins a resolved `require` contributes via
  # DocMap, so these specs exercise calls into a gem/stdlib method.
  shared_context 'with a Box declared in RBS' do
    # create a temporary directory with the scope of the spec
    around do |example|
      require 'tmpdir'
      Dir.mktmpdir('rspec-solargraph-') do |dir|
        @temp_dir = dir
        example.run
      end
    end

    attr_reader :temp_dir

    let(:conversions) do
      loader = RBS::EnvironmentLoader.new(core_root: nil, repository: RBS::Repository.new(no_stdlib: false))
      loader.add(path: Pathname(temp_dir))
      Solargraph::RbsMap::Conversions.new(loader: loader)
    end

    before do
      File.write(File.join(temp_dir, 'box.rbs'), rbs)
      RbsPinConvention.pins = conversions.pins
      Solargraph::Convention.register RbsPinConvention
    end

    after do
      Solargraph::Convention.unregister RbsPinConvention
      RbsPinConvention.pins = []
    end

    # @param code [String]
    # @param position [Array(Integer, Integer)]
    # @return [Solargraph::ComplexType]
    def infer_at code, position
      api_map = Solargraph::ApiMap.new
      source = Solargraph::Source.load_string(code, 'test.rb')
      source_map = Solargraph::SourceMap.map(source)
      api_map.catalog(Solargraph::Bench.new(source_maps: [source_map], live_map: source_map))
      api_map.clip_at('test.rb', position).infer
    end
  end

  context 'with an RBS-declared generic block-form overload accepting a kwrest parameter' do
    include_context 'with a Box declared in RBS'

    let(:rbs) do
      <<~RBS
        class Box
          def self.start: (Integer val, ?String opt1, ?String opt2) -> Box
                         | [T] (Integer val, ?String opt1, ?String opt2, **untyped opts) { (Integer v) -> T } -> T
        end
      RBS
    end

    it 'matches a trailing keyword argument to a kwrest parameter instead of the next positional parameter' do
      type = infer_at(%(
        Box.start(1, "x", foo: true) do |v|
          v
        end
      ), [2, 10])
      expect(type.rooted_tags).to eq('::Integer')
    end

    it 'still resolves the block-form overload when no keyword argument is passed' do
      type = infer_at(%(
        Box.start(1, "x") do |v|
          v
        end
      ), [2, 10])
      expect(type.rooted_tags).to eq('::Integer')
    end
  end

  context 'with overloads that differ only in which keyword(s) they accept' do
    include_context 'with a Box declared in RBS'

    let(:rbs) do
      <<~RBS
        class Box
          def self.add: (path: String) -> Integer
                       | (library: String, ?resolve_dependencies: untyped) -> String
        end
      RBS
    end

    it 'matches a call by the keyword it actually passes, not an earlier overload with an untyped keyword param' do
      code = %(
        Box.add(path: "x")
      )
      type = infer_at(code, [1, code.lines[1].chomp.length])
      expect(type.rooted_tags).to eq('::Integer')
    end
  end
end
