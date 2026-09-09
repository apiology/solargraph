# frozen_string_literal: true

describe Solargraph::TypeChecker do
  context 'with level set to strong' do
    def type_checker code
      Solargraph::TypeChecker.load_string(code, 'test.rb', :strong)
    end

    it 'requires strict return tags for attributes when nil is involved' do
      checker = type_checker(%(
        class Foo
          # @param bar [String, nil]
          def initialize(bar = nil)
            @bar = bar
          end

          # The tag is [String] but @bar can be nil per the constructor
          #
          # @return [String]
          attr_reader :bar
        end
      ))
      expect(checker.problems).to be_one
      expect(checker.problems.first.message).to include('does not match inferred type')
    end

    it 'does not flag attributes whose declared type already allows nil' do
      checker = type_checker(%(
        class Foo
          # @param bar [String, nil]
          def initialize(bar = nil)
            @bar = bar
          end

          # @return [String, nil]
          attr_reader :bar
        end
      ))
      expect(checker.problems).to be_empty
    end

    it 'requires strict return tags when nil is involved and used second in a ternary' do
      checker = type_checker(%(
        class Foo
          # The tag is [String] but the inference is [String, nil]
          #
          # @return [String]
          def bar
            false ? 'bar' : nil
          end
        end
      ))
      expect(checker.problems).to be_one
      expect(checker.problems.first.message).to include('does not match inferred type')
    end

    it 'requires strict return tags when nil is involved and used first in a ternary' do
      checker = type_checker(%(
        class Foo
          # The tag is [String] but the inference is [String, nil]
          #
          # @return [String]
          def bar
            true ? nil : 'bar'
          end
        end
      ))
      expect(checker.problems).to be_one
      expect(checker.problems.first.message).to include('does not match inferred type')
    end

    it 'understands self type when passed as parameter' do
      checker = type_checker(%(
        class Location
          # @return [String]
          attr_reader :filename

          # @param other [self]
          # @return [-1, 0, 1, nil]
          def <=>(other)
            return nil unless other.is_a?(Location)

            filename <=> other.filename
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'does not misunderstand types during flow sensitive typing' do
      checker = type_checker(%(
        class A
          # @param b [Hash{String => String}]
          # @return [void]
          def a b
            c = b["123"]
            return if c.nil?
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'does not leak an unbound generic from an unmatched Hash#fetch overload' do
      checker = type_checker(%(
        class A
          # @param b [Hash{String => Integer}]
          # @return [Integer]
          def a b
            b.fetch('x')
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'infers nil as part of Hash#[] on a plainly-typed Hash' do
      checker = type_checker(%(
        class A
          # @param b [Hash{String => Integer}]
          # @return [Integer, nil]
          def a b
            b['x']
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'respects pin visibility in if/nil? pattern' do
      checker = type_checker(%(
        class Foo
          # Get the namespace's type (Class or Module).
          #
          # @param bar [Symbol, nil]
          # @return [Symbol, Integer]
          def foo bar
            return 123 if bar.nil?
            bar
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'accepts a non-nil @type on a local assigned from a bare accessor guarded by .nil?' do
      checker = type_checker(%(
        class Repro
          # @return [Array<Hash>, nil]
          attr_reader :steps

          # @return [Array<Hash>, nil]
          def unwrap
            return nil if steps.nil?

            # @type [Array<Hash>]
            steps_list = steps
            steps_list.each { |step| step }
            steps_list
          end
        end
      ))

      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'accepts a non-nil @type on a local assigned from a bare accessor guarded by a non-nil return' do
      checker = type_checker(%(
        class Repro
          # @return [Array<Hash>, nil]
          attr_reader :substeps

          # @return [Array]
          def extract
            return ['', nil] if substeps.nil?

            # @type [Array<Hash>]
            steps_list = substeps
            steps_list.each { |step| step }
            steps_list
          end
        end
      ))

      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'respects || overriding nilable types' do
      checker = type_checker(%(
        # @return [String]
        def global_config_path
          ENV['SOLARGRAPH_GLOBAL_CONFIG'] ||
              File.join(Dir.home, '.config', 'solargraph', 'config.yml')
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'does not leak nil from an earlier &. into an unrelated later call in the same chain' do
      checker = type_checker(%(
        class Repro
          # @param x [String, nil]
          # @return [Boolean]
          def process(x)
            x&.to_s == '1'
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'still flags a chain ending in a safe navigation call as nullable' do
      checker = type_checker(%(
        class Repro
          # @param x [String, nil]
          # @return [String]
          def process(x)
            x&.to_s
          end
        end
      ))
      expect(checker.problems.map(&:message)).not_to be_empty
    end

    it 'still flags nil leaking through a self-returning call after an earlier &.' do
      checker = type_checker(%(
        class Repro
          # @param x [String, nil]
          # @return [String]
          def process(x)
            x&.to_s.itself
          end
        end
      ))
      expect(checker.problems.map(&:message)).not_to be_empty
    end

    it 'does not flag a call after &. whose result on NilClass is a fixed non-nil type' do
      checker = type_checker(%(
        class Repro
          # @param x [String, nil]
          # @return [Integer]
          def process(x)
            x&.to_s.to_i
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'is able to probe type over an assignment' do
      checker = type_checker(%(
        # @return [String]
        def global_config_path
          out = 'foo'
          out
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'respects pin visibility in if/foo pattern' do
      checker = type_checker(%(
        class Foo
          # Get the namespace's type (Class or Module).
          #
          # @param bar [Symbol, nil]
          # @return [Symbol, Integer]
          def foo bar
            baz = bar
            return baz if baz
            123
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'handles a flow sensitive typing if correctly' do
      checker = type_checker(%(
        # @param a [String, nil]
        # @return [void]
        def foo a = nil
          b = a
          if b
            b.upcase
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'handles another flow sensitive typing if correctly' do
      checker = type_checker(%(
        class A
          # @param e [String]
          # @param f [String]
          # @return [void]
          def d(e, f:); end

          # @return [void]
          def a
            c = rand ? nil : "foo"
            if c
              d(c, f: c)
            end
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'respects pin visibility' do
      checker = type_checker(%(
        class Foo
          # Get the namespace's type (Class or Module).
          #
          # @param baz [Integer, nil]
          # @return [Integer, nil]
          def foo baz = 123
            return nil if baz.nil?
            baz
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'provides nil checking on calls from parameters without assignments' do
      checker = type_checker(%(
        # @param baz [String, nil]
        #
        # @return [String]
        def quux(baz)
          baz.upcase # ERROR: Unresolved call to upcase on String, nil
        end
      ))
      expect(checker.problems.map(&:message)).to eq(['#quux return type could not be inferred',
                                                     'Unresolved call to upcase on String, nil'])
    end

    it 'applies a yieldparam type declared on a block-form @overload' do
      checker = type_checker(%(
        # @overload build
        #   @return [String]
        # @overload build
        #   @yieldparam widget [String]
        #   @return [void]
        def build
          return 'hi' unless block_given?

          yield 'hi'
        end

        build do |w|
          w.upcase
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'does not complain on array dereference' do
      checker = type_checker(%(
        # @param idx [Integer] an index
        # @param arr [Array<Integer>] an array of integers
        #
        # @return [void]
        def foo(idx, arr)
          arr[idx]
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'understands local evaluation with ||= removes nil from lhs type' do
      checker = type_checker(%(
        class Foo
          def initialize
            @bar = nil
          end

          # @return [Integer]
          def bar
            @bar ||= 123
          end
        end
      ))

      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'complains on bad @type assignment' do
      checker = type_checker(%(
        # @type [Integer]
        c = Class.new
      ))
      expect(checker.problems.map(&:message))
        .to eq ['Declared type Integer does not match inferred type Class for variable c']
    end

    it 'does not complain on another variant of Class.new' do
      checker = type_checker(%(
        class Class
          # @return [self]
          def self.blah
            new
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'does not complain on indirect Class.new', skip: 'hangs in a loop currently' do
      checker = type_checker(%(
        class Foo < Class; end
        Foo.new
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'reports unneeded @sg-ignore tags' do
      checker = type_checker(%(
        class Foo
          # @sg-ignore
          # @return [void]
          def bar; end
        end
      ))
      expect(checker.problems.map(&:message)).to eq(['Unneeded @sg-ignore comment'])
    end

    it 'reports missing return tags' do
      checker = type_checker(%(
        class Foo
          def bar; end
        end
      ))
      expect(checker.problems).to be_one
      expect(checker.problems.first.message).to include('Missing @return tag')
    end

    it 'strips nil from an or-expression fallback in a conditional branch' do
      checker = type_checker(%(
        class Container
          # @param m [Module, nil]
          # @param expected [Module]
          # @return [Boolean]
          def check(m, expected)
            if m.nil?
              fallback
            else
              m <= expected || fallback
            end
          end

          # @return [Boolean]
          def fallback
            true
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'calls out keyword issues even when required arg count matches' do
      checker = type_checker(%(
        # @param a [String]
        # @param b [String]
        # @return [void]
        def foo(a = 'foo', b:); end

        # @return [void]
        def bar
         foo('baz')
        end
      ))
      expect(checker.problems.map(&:message)).to include('Call to #foo is missing keyword argument b')
    end

    it 'understands complex use of self' do
      checker = type_checker(%(
        class A
          # @param other [self]
          #
          # @return [void]
          def foo other; end

          # @param other [self]
          #
          # @return [void]
          def bar(other); end
        end

        class B < A
          def bar(other)
            foo(other)
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'reports a ** splat whose type records no keys as unverifiable, not missing' do
      checker = type_checker(%(
        # @param a [Integer]
        # @param b [Integer]
        # @return [void]
        def foo(a:, b:); end

        # @return [Hash{Symbol => Integer}]
        def make_args
          { a: 1, b: 2 }
        end

        # @return [void]
        def bar
          args = make_args
          foo(**args)
        end
      ))
      expect(checker.problems.map(&:message)).to eq(
        ['Cannot verify keyword arguments to #foo: the ** splat is Hash{Symbol => Integer}, which does not ' \
         'record its keys, so required keyword arguments a, b cannot be checked - give the splatted value a ' \
         'record type (e.g. Hash{:a => Object}) to check it']
      )
    end

    it 'names only the required keywords a ** splat has to supply' do
      checker = type_checker(%(
        # @param a [Integer]
        # @param b [Integer]
        # @return [void]
        def foo(a:, b:); end

        # @return [Hash{Symbol => Integer}]
        def make_args
          { b: 2 }
        end

        # @return [void]
        def bar
          args = make_args
          foo(a: 1, **args)
        end
      ))
      expect(checker.problems.map(&:message)).to eq(
        ['Cannot verify keyword arguments to #foo: the ** splat is Hash{Symbol => Integer}, which does not ' \
         'record its keys, so required keyword argument b cannot be checked - give the splatted value a ' \
         'record type (e.g. Hash{:b => Object}) to check it']
      )
    end

    it 'accepts required keywords supplied by a record-typed ** splat' do
      checker = type_checker(%(
        # @param a [Integer]
        # @param b [Integer]
        # @return [void]
        def foo(a:, b:); end

        # @return [Hash{:a => Integer} & Hash{:b => Integer}]
        def make_args
          { a: 1, b: 2 }
        end

        # @return [void]
        def bar
          args = make_args
          foo(**args)
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'accepts a record-typed ** splat that supplies what the literal keywords do not' do
      checker = type_checker(%(
        # @param a [Integer]
        # @param b [Integer]
        # @return [void]
        def foo(a:, b:); end

        # @return [Hash{:b => Integer}]
        def make_args
          { b: 2 }
        end

        # @return [void]
        def bar
          args = make_args
          foo(a: 1, **args)
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'reports a keyword a record-typed ** splat leaves out' do
      checker = type_checker(%(
        # @param a [Integer]
        # @param b [Integer]
        # @return [void]
        def foo(a:, b:); end

        # @return [Hash{:a => Integer}]
        def make_args
          { a: 1 }
        end

        # @return [void]
        def bar
          args = make_args
          foo(**args)
        end
      ))
      expect(checker.problems.map(&:message)).to eq(['Call to #foo is missing keyword argument b'])
    end

    it 'checks the value types a record-typed ** splat supplies' do
      checker = type_checker(%(
        # @param a [Integer]
        # @param b [Integer]
        # @return [void]
        def foo(a:, b:); end

        # @return [Hash{:a => String} & Hash{:b => Integer}]
        def make_args
          { a: 'x', b: 2 }
        end

        # @return [void]
        def bar
          args = make_args
          foo(**args)
        end
      ))
      expect(checker.problems.map(&:message)).to eq(
        ['Wrong argument type for #foo: a expected Integer, received String']
      )
    end

    it 'reports a keyword a record-typed ** splat supplies that the method does not accept' do
      checker = type_checker(%(
        # @param a [Integer]
        # @param b [Integer]
        # @return [void]
        def foo(a:, b:); end

        # @return [Hash{:a => Integer} & Hash{:b => Integer} & Hash{:c => Integer}]
        def make_args
          { a: 1, b: 2, c: 3 }
        end

        # @return [void]
        def bar
          args = make_args
          foo(**args)
        end
      ))
      expect(checker.problems.map(&:message)).to eq(['Unrecognized keyword argument c to #foo'])
    end

    it 'still reports a keyword left out of a splatted literal hash' do
      checker = type_checker(%(
        # @param a [Integer]
        # @param b [Integer]
        # @return [void]
        def foo(a:, b:); end

        # @return [void]
        def bar
          foo(**{ a: 1 })
        end
      ))
      expect(checker.problems.map(&:message)).to eq(['Missing keyword argument b to #foo'])
    end

    it 'does not invent a keyword named after the splatted variable' do
      checker = type_checker(%(
        class Base
          # @param name [String]
          # @param foo [Integer]
          # @return [void]
          def initialize(name:, foo: 1); end
        end

        class Sub < Base
          # @param name [String]
          # @param kwargs [Hash{Symbol => Object}]
          # @return [void]
          def initialize(name, **kwargs)
            super(name: name, **kwargs)
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'calls out type issues even when keyword issues are there' do
      pending('fixes to arg vs param checking algorithm')

      checker = type_checker(%(
        # @param a [String]
        # @param b [String]
        # @return [void]
        def foo(a = 'foo', b:); end

        # @return [void]
        def bar
         foo(123)
        end
      ))
      expect(checker.problems.map(&:message))
        .to include('Wrong argument type for #foo: a expected String, received 123')
    end

    it 'calls out keyword issues even when arg type issues are there' do
      checker = type_checker(%(
        # @param a [String]
        # @param b [String]
        # @return [void]
        def foo(a = 'foo', b:); end

        # @return [void]
        def bar
         foo(123)
        end
      ))
      expect(checker.problems.map(&:message)).to include('Call to #foo is missing keyword argument b')
    end

    it 'calls out missing args after a defaulted param' do
      checker = type_checker(%(
        # @param a [String]
        # @param b [String]
        # @return [void]
        def foo(a = 'foo', b); end

        # @return [void]
        def bar
         foo(123)
        end
      ))
      expect(checker.problems.map(&:message)).to include('Not enough arguments to #foo')
    end

    it 'reports missing param tags' do
      checker = type_checker(%(
        class Foo
          # @return [void]
          def bar baz
          end
        end
      ))
      expect(checker.problems).to be_one
      expect(checker.problems.first.message).to include('Missing @param tag')
    end

    it 'reports missing param and return tags on writers when instance variable type not defined' do
      checker = type_checker(%(
        class Foo
          attr_writer :bar
        end
      ))
      expect(checker.problems.map(&:message)).to include('Missing @param tag for value on Foo#bar=')
      expect(checker.problems.map(&:message)).to include('Missing @return tag for Foo#bar=')
    end

    it 'reports missing return tags on readers when instance variable type not defined' do
      checker = type_checker(%(
        class Foo
          attr_reader :bar
        end
      ))
      expect(checker.problems).to be_one
      expect(checker.problems.first.message).to include('Missing @return tag')
    end

    it 'ignores missing return tags on readers when instance variable type not defined' do
      checker = type_checker(%(
        class Foo
          # @param bar [String]
          def initialize(bar)
            @bar = bar
          end

          attr_reader :bar
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'ignores missing param and return tags on writers when instance variable type defined' do
      checker = type_checker(%(

        class Foo
          # @param bar [String]
          def initialize(bar)
            @bar = bar
          end

          attr_writer :bar
        end
        class Bar
          # @param baz [String]
          def initialize(baz)
            @baz = baz
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'reports missing kwoptarg param tags' do
      checker = type_checker(%(
        class Foo
          # @return [void]
          def bar(baz: 0); end
        end
      ))
      expect(checker.problems).to be_one
      expect(checker.problems.first.message).to include('Missing @param tag')
    end

    it 'ignores optional params' do
      checker = type_checker(%(
        class Foo
          # @return [void]
          def bar *args
          end
        end
      ))
      expect(checker.problems).to be_empty
    end

    it 'ignores optional keyword params' do
      checker = type_checker(%(
        class Foo
          # @return [void]
          def bar **opts
          end
        end
      ))
      expect(checker.problems).to be_empty
    end

    it 'ignores untagged block params' do
      checker = type_checker(%(
        class Foo
          # @return [void]
          def bar &block
          end
        end
      ))
      expect(checker.problems).to be_empty
    end

    it 'does not need fully specified container types' do
      checker = type_checker(%(
        class Foo
          # @param foo [Array<String>]
          # @return [void]
          def bar foo: []; end

          # @param bing [Array]
          # @return [void]
          def baz(bing)
            bar(foo: bing)
            generic_values = [1,2,3].map(&:to_s)
            bar(foo: generic_values)
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'treats a parameter type of undefined as not provided' do
      checker = type_checker(%(
        class Foo
          # @param foo [Array<String>]
          # @return [void]
          def bar foo: []; end

          # @param bing [Array<undefind>]
          # @return [void]
          def baz(bing)
            bar(foo: bing)
            generic_values = [1,2,3].map(&:to_s)
            bar(foo: generic_values)
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'ignores generic resolution failure with no generic tag' do
      checker = type_checker(%(
        class Foo
          # @param foo [Class<String>]
          # @return [void]
          def bar foo:; end

          # @param bing [Class<generic<T>>]
          # @return [void]
          def baz(bing)
            bar(foo: bing)
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'ignores undefined resolution failures' do
      checker = type_checker(%(
        class Foo
          # @generic T
          # @param klass [Class<undefined>>]
          # @return [Set<generic<T>>]
          def pins_by_class klass; [].to_set; end
        end
        class Bar
          # @return [Enumerable<Integer>]
          def block_pins
            foo = Foo.new
            foo.pins_by_class(Integer)
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'ignores generic resolution failures from current Solargraph limitation' do
      checker = type_checker(%(
        class Foo
          # @generic T
          # @param klass [Class<generic<T>>]
          # @return [Set<generic<T>>]
          def pins_by_class klass; [].to_set; end
        end
        class Bar
          # @return [Enumerable<Integer>]
          def block_pins
            foo = Foo.new
            foo.pins_by_class(Integer)
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'ignores unresolved method-scoped generics returned from a bare yield' do
      checker = type_checker(%(
        class Repro
          # @generic T
          # @yieldreturn [generic<T>]
          # @return [generic<T>]
          def call
            yield
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'ignores generic resolution failures with only one arg' do
      checker = type_checker(%(
        # @generic T
        # @param path [String]
        # @param klass [Class<generic<T>>]
        # @return [void]
        def code_object_at path, klass = Integer
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'does not complain on select { is_a? } pattern' do
      checker = type_checker(%(
        # @param arr [Enumerable<Object>}
        # @return [Enumerable<Integer>]
        def downcast_arr(arr)
          arr.select { |pin| pin.is_a?(Integer) }
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'narrows a literal-equality guard against a literal union member' do
      checker = type_checker(%(
        # @param sections [Array<String>, :not_specified]
        # @return [void]
        def not_equal_guard(sections)
          if sections != :not_specified
            sections.each { |s| puts s }
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'narrows a literal-equality guard against an integer literal' do
      checker = type_checker(%(
        # @param code [Integer, :not_specified]
        # @return [void]
        def eq_guard(code)
          if code == 1
            code.succ
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'narrows a literal-equality guard with the literal on the left' do
      checker = type_checker(%(
        # @param code [Integer, :not_specified]
        # @return [void]
        def eq_guard(code)
          if 1 == code
            code.succ
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'narrows a literal-equality guard against a string literal' do
      checker = type_checker(%(
        # @param status [String, :not_specified]
        # @return [void]
        def eq_guard(status)
          if status == 'ok'
            status.upcase
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'narrows a literal-equality guard against true/false literals' do
      checker = type_checker(%(
        # @param flag [Boolean, :not_specified]
        # @return [void]
        def eq_guard(flag)
          if flag == true
            flag.to_s
          end
          if flag == false
            flag.to_s
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'does not complain on adding nil to types via return value' do
      checker = type_checker(%(
        # @param bar [Integer]
        # @return [Integer, nil]
        def foo(bar)
          bar
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'does not complain on adding nil to types via select' do
      checker = type_checker(%(
        # @return [Float, nil]}
        def bar; rand; end

        # @param arr [Enumerable<Object>}
        # @return [Integer, nil]
        def downcast_arr(arr)
          # @type [Object, nil]
          foo = arr.select { |pin| pin.is_a?(Integer) && bar }.last
          foo
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'inherits param tags from superclass methods' do
      checker = type_checker(%(
        class Foo
          # @param arg [Integer]
          # @return [void]
          def meth arg
          end
        end

        class Bar < Foo
          def meth arg
          end
        end
      ))
      expect(checker.problems).to be_empty
    end

    it 'understands Open3 methods' do
      # https://github.com/castwide/solargraph/pull/1292#issuecomment-5279286724
      #
      # match_overload_type's loop stops at the first overload where
      # positional_arguments_match? returns true, and that check has a
      # pre-existing bypass (param.compatible_arg?(atype, api_map) ||
      # param.restarg?) accepting any argument type against a *rest
      # param regardless of fit. Open3.capture2e's first overload
      # ((*arg_0 Array[String], ...)) "matches" foo (a Hash) via that
      # bypass before the loop ever reaches the later, correct
      # (env Hash[...], *cmds, ...) overload, so it gets narrowed to
      # the wrong signature. Fixed for the keyword-matching half by
      # #1292's second commit, but the underlying restarg-leniency +
      # first-match-wins overload selection predates #1292 and is a
      # separate, larger fix.
      pending('restarg-leniency lets an earlier wrong overload win before a later correct one is tried - castwide/solargraph#1292')

      checker = type_checker(%(
        require 'open3'

        # @return [void]
        def run_command
          # @type [Hash{String => String}]
          foo = {'foo' => 'bar'}
          Open3.capture2e(foo, 'ls', chdir: '/tmp')
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    context 'with class name available in more than one gate' do
      let(:checker) do
        type_checker(%(
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
                  objects_by_class(Bar::Symbol)
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
        ))
      end

      it 'resolves class name correctly in generic resolution' do
        expect(checker.problems.map(&:message)).to be_empty
      end
    end

    it 'resolves a generic type variable against a union @param type' do
      checker = type_checker(%(
        # @generic A
        # @param arg [generic<A>, nil]
        # @return [generic<A>]
        def must_nilable(arg)
          raise if arg.nil?

          arg
        end

        # @param arg [String, nil]
        # @return [Integer]
        def via_nilable(arg) = must_nilable(arg).length
      ))
      # The remaining "Declared return type generic<A> does not match
      # inferred type generic<A>, nil for #must_nilable" problem is
      # caused by #1276 (`raise` does not narrow the type), which is
      # independent of the generic resolution behavior under test here.
      messages = checker.problems.map(&:message)
      expect(messages).not_to include('#via_nilable return type could not be inferred')
      expect(messages).not_to include('Unresolved call to length on String, nil')
    end

    # NOTE: this scenario doesn't distinguish fixed from unfixed
    # behavior - a union return type of the exact same shape as the
    # union @param type flattens/dedupes an incorrectly-too-wide
    # binding back down to the right answer by coincidence (the union
    # already contains 'nil' as a sibling member either way). It's
    # included as a no-regression check for union return types, not as
    # a regression test for #1298 itself.
    it 'resolves a generic type variable when both the @param and @return types are the same union' do
      checker = type_checker(%(
        # @generic A
        # @param arg [generic<A>, nil]
        # @return [generic<A>, nil]
        def maybe(arg)
          arg
        end

        # @param arg [String, nil]
        # @return [String, nil]
        def via(arg) = maybe(arg)
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'resolves a generic type variable against a union @param type with more than two members' do
      checker = type_checker(%(
        # @generic A
        # @param arg [generic<A>, nil, Symbol]
        # @return [generic<A>]
        def must_not_nil_or_symbol(arg)
          raise if arg.nil? || arg.is_a?(Symbol)

          arg
        end

        # @param arg [String, nil, Symbol]
        # @return [Integer]
        def via_triple(arg) = must_not_nil_or_symbol(arg).length
      ))
      # As with the two-member case above, the remaining "Declared
      # return type...does not match inferred type" problem is #1276
      # (`raise` does not narrow the type), independent of this test.
      messages = checker.problems.map(&:message)
      expect(messages).not_to include('#via_triple return type could not be inferred')
      expect(messages).not_to include('Unresolved call to length on String, nil, Symbol')
    end

    it 'resolves a generic type variable against a union @param type through two layers of generic methods' do
      checker = type_checker(%(
        # @generic A
        # @param arg [generic<A>, nil]
        # @return [generic<A>]
        def layer1(arg)
          raise if arg.nil?

          arg
        end

        # @generic A
        # @param arg [generic<A>, nil]
        # @return [generic<A>]
        def layer2(arg) = layer1(arg)

        # @param arg [String, nil]
        # @return [Integer]
        def via_layers(arg) = layer2(arg).length
      ))
      # As above, any "Declared return type...does not match inferred
      # type" problems here are #1276 (`raise` does not narrow the
      # type), independent of this test.
      messages = checker.problems.map(&:message)
      expect(messages).not_to include('#via_layers return type could not be inferred')
      expect(messages).not_to include('Unresolved call to length on String, nil')
    end

    it 'resolves constants inside modules inside classes' do
      checker = type_checker(%(
        class Bar
          module Foo
            CONSTANT = 'hi'
          end
        end

        class Bar
          include Foo

          # @return [String]
          def baz
            CONSTANT
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'handles "while foo" flow sensitive typing correctly' do
      checker = type_checker(%(
        # @param a [String, nil]
        # @return [void]
        def foo a = nil
          b = a
          while b
              b.upcase
              b = nil if rand > 0.5
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'does flow sensitive typing even inside a block' do
      checker = type_checker(%(
        class Quux
          # @param foo [String, nil]
          #
          # @return [void]
          def baz(foo)
            bar = foo
            [].each do
              bar.upcase unless bar.nil?
            end
          end
        end))

      expect(checker.problems.map(&:location).map(&:range).map(&:start)).to be_empty
    end

    it 'accepts ivar assignments and references with no intermediate calls as safe' do
      checker = type_checker(%(
        class Foo
          def initialize
            # @type [Integer, nil]
            @foo = nil
          end

          # @return [void]
          def twiddle
            @foo = nil if rand if rand > 0.5
          end

          # @return [Integer]
          def bar
            @foo = 123
            out = @foo.round
            twiddle
            out
          end
      ))

      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'resolves self correctly in chained method calls' do
      checker = type_checker(%(
        class Foo
          # @param other [self]
          #
          # @return [Symbol, nil]
          def bar(other)
            # @type [Symbol, nil]
            baz(other)
          end

          # @param other [self]
          #
          # @sg-ignore Missing @return tag
          # @return [undefined]
          def baz(other); end
        end
      ))

      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'knows that ivar references with intermediate calls are not safe' do
      checker = type_checker(%(
        class Foo
          def initialize
            # @type [Integer, nil]
            @foo = nil
          end

          # @return [void]
          def twiddle
            @foo = nil if rand if rand > 0.5
          end

          # @return [Integer]
          def bar
            @foo = 123
            twiddle
            @foo.round
          end
        end
      ))

      expect(checker.problems.map(&:message)).to eq(['Foo#bar return type could not be inferred',
                                                     'Unresolved call to round on Integer, nil'])
    end

    it 'performs simple flow-sensitive typing on lvars' do
      checker = type_checker(%(
        class Foo
          # @param bar [Integer, nil]
          # @return [::Boolean, ::Integer]
          def foo bar
            !bar || bar.abs
          end
        end
      ))

      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'performs simple flow-sensitive typing on ivars' do
      checker = type_checker(%(
        class Foo
          # @param bar [::Integer, nil]
          def initialize bar: nil
            @bar = bar
          end

          # @return [::Boolean, ::Integer]
          def foo
            !@bar || @bar.abs
          end
        end
      ))

      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'performs complex flow-sensitive typing on ivars' do
      checker = type_checker(%(
        class Foo
          # @param bar [::Array<Integer>, nil]
          def initialize bar: nil
            @bar = bar
          end

          def maybe_bar?
            return !@bar.empty? if defined?(@bar) && @bar
            false
          end
        end
      ))

      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'updates a parameter type after reassignment to a different non-literal type' do
      checker = type_checker(%(
        class Position
          # @return [Integer]
          def line
            1
          end
        end

        module PositionNormalizer
          # @param position [Position, Array(Integer, Integer)]
          # @return [Position]
          def self.normalize(position)
            Position.new
          end
        end

        # @param position [Position, Array(Integer, Integer)]
        # @return [Integer]
        def describe(position)
          position = PositionNormalizer.normalize(position)
          position.line
        end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'does not treat a parameter reassignment inside a block as guaranteed to have run' do
      checker = type_checker(%(
        class Position
          # @return [Integer]
          def line
            1
          end
        end

        module PositionNormalizer
          # @param position [Position, Array(Integer, Integer)]
          # @return [Position]
          def self.normalize(position)
            Position.new
          end
        end

        # @param position [Position, Array(Integer, Integer)]
        # @return [Integer]
        def describe(position)
          [1].each { position = PositionNormalizer.normalize(position) }
          position.line
        end
      ))
      expect(checker.problems.map(&:message)).to eq([
                                                      '#describe return type could not be inferred',
                                                      'Unresolved call to line on Position, Array(Integer, Integer)'
                                                    ])
    end

    it 'still treats a conditional reassignment as guaranteed to have run for a use site inside the same branch' do
      checker = type_checker(%(
        # @param str [String]
        # @param num [Integer]
        # @param flag [Boolean]
        # @return [void]
        def conditional_reassign(str, num, flag)
          local = num
          if flag
            local = str
            local.upcase
          end
        end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'narrows a variable assigned in the if condition' do
      checker = type_checker(%(
        # @param name [String]
        # @return [Integer]
        def limit_of(name)
          if (md = name.match(/\\[(.*)\\]/))
            md[1].to_i
          else
            0
          end
        end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'narrows a variable assigned in the right side of an && condition' do
      checker = type_checker(%(
        # @param name [String, nil]
        # @return [Integer]
        def limit_of(name)
          if !name.nil? && (md = name.match(/\\[(.*)\\]/))
            md[1].to_i
          else
            0
          end
        end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'does not narrow a variable assigned in the left side of an || condition' do
      checker = type_checker(%(
        # @param name [String]
        # @param fallback [Boolean]
        # @return [Integer]
        def limit_of(name, fallback)
          if (md = name.match(/\\[(.*)\\]/)) || fallback
            md[1].to_i
          else
            0
          end
        end
      ))
      expect(checker.problems.map(&:message)).to eq(['Unresolved call to []'])
    end

    it 'treats a variable assigned in the if condition as falsy in the else clause' do
      checker = type_checker(%(
        # @param name [String]
        # @return [Integer]
        def limit_of(name)
          if (md = name.match(/\\[(.*)\\]/))
            0
          else
            md[1].to_i
          end
        end
      ))
      # the falsy-only receiver renders as either `nil, false` or
      # `nil, Boolean` depending on literal handling; both mean narrowed
      expect(checker.problems.map(&:message))
        .to contain_exactly(a_string_matching(/\AUnresolved call to \[\] on nil, (false|Boolean)\z/))
    end

    it 'uses a branch-local reassignment at a use site later in the same branch' do
      checker = type_checker(%(
        # @param items [Array<String>, nil]
        # @return [void]
        def clean(items)
          if items.nil?
            items = fetch_items
            items.reject! { |i| i.empty? }
          end
        end

        # @return [Array<String>]
        def fetch_items; ['x']; end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'does not use a reassignment made in a nested branch that may not run' do
      checker = type_checker(%(
        # @param items [Array<String>, nil]
        # @param flag [Boolean]
        # @return [void]
        def clean(items, flag)
          if items.nil?
            if flag
              items = fetch_items
            end
            items.reject! { |i| i.empty? }
          end
        end

        # @return [Array<String>]
        def fetch_items; ['x']; end
      ))
      expect(checker.problems.map(&:message)).to eq(['Unresolved call to reject! on nil'])
    end

    it 'does not use a branch-local reassignment at a use site before it' do
      checker = type_checker(%(
        # @param items [Array<String>, nil]
        # @return [void]
        def clean(items)
          if items.nil?
            items.reject! { |i| i.empty? }
            items = fetch_items
          end
        end

        # @return [Array<String>]
        def fetch_items; ['x']; end
      ))
      expect(checker.problems.map(&:message)).to eq(['Unresolved call to reject! on nil'])
    end

    it 'accumulates every fact an or-guard asserts about the same value' do
      checker = type_checker(%(
        # @param name [String, Integer, nil]
        # @return [String]
        def f(name)
          a = lookup(name)
          a = 'd' if a.nil? || a.is_a?(Integer)
          a
        end

        # @param name [String, Integer, nil]
        # @return [String, Integer, nil]
        def lookup(name); end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'narrows a nil-guarded default behind an or-guard with three operands' do
      checker = type_checker(%(
        # @param name [String, nil]
        # @return [String]
        def f(name)
          a = lookup(name)
          a = 'd' if a.nil? || a.empty? || a == 'x'
          a
        end

        # @param name [String, nil]
        # @return [String, nil]
        def lookup(name); end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'narrows a nil-guarded default behind an or-guard with four operands' do
      checker = type_checker(%(
        # @param name [String, nil]
        # @return [String]
        def f(name)
          a = lookup(name)
          a = 'd' if a.nil? || a.empty? || a == 'x' || a == 'y'
          a
        end

        # @param name [String, nil]
        # @return [String, nil]
        def lookup(name); end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    # Soundness controls for the or-guard narrowing above. `¬(x || y)` implies
    # every operand is false, so the guard's false path may narrow any variable
    # it tests - but the guard's TRUE path only reassigns `a`, so nothing may be
    # concluded about a second variable the guard happens to mention.
    it 'does not narrow a second variable an or-guard tests but never reassigns' do
      checker = type_checker(%(
        # @param name [String, nil]
        # @return [String]
        def f(name)
          a = lookup(name)
          b = lookup(name)
          a = 'd' if a.nil? || b.nil?
          b
        end

        # @param name [String, nil]
        # @return [String, nil]
        def lookup(name); end
      ))
      expect(checker.problems.map(&:message))
        .to include(a_string_matching(/Declared return type ::String does not match/))
    end

    it 'does not narrow when the or-guard never tests the variable at all' do
      checker = type_checker(%(
        # @param name [String, nil]
        # @param flag [Boolean]
        # @return [String]
        def f(name, flag)
          a = lookup(name)
          a = 'd' if flag || name.nil?
          a
        end

        # @param name [String, nil]
        # @return [String, nil]
        def lookup(name); end
      ))
      expect(checker.problems.map(&:message))
        .to include(a_string_matching(/Declared return type ::String does not match/))
    end

    it 'applies a modifier-if guard after the variable was reassigned' do
      checker = type_checker(%(
        # @param name [String]
        # @return [Integer, nil]
        def find(name)
          got = lookup(name)
          return got.length if got

          got = lookup(name)
          got.length if got
        end

        # @param name [String]
        # @return [String, nil]
        def lookup(name); name; end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'applies a modifier-if guard after a reassignment whose block shadows the name' do
      checker = type_checker(%(
        # @param name [String]
        # @return [Integer, nil]
        def find(name)
          got = candidates.find { |got| got == name }
          return got.length if got

          got = candidates.find { |got| got != name }
          got.length if got
        end

        # @return [Array<String>]
        def candidates; []; end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'keeps a guard fact in force until the variable is reassigned' do
      checker = type_checker(%(
        # @param name [String]
        # @return [Integer, nil]
        def find(name)
          got = lookup(name)
          return got.length if got

          got.length
        end

        # @param name [String]
        # @return [String, nil]
        def lookup(name); name; end
      ))
      expect(checker.problems.map(&:message))
        .to contain_exactly(a_string_matching(/\AUnresolved call to length on nil, (false|Boolean)\z/))
    end

    it 'does not apply a guard fact past a reassignment that only runs in a branch' do
      checker = type_checker(%(
        # @param name [String]
        # @param flag [Boolean]
        # @return [Integer, nil]
        def find(name, flag)
          got = lookup(name)
          return got.length if got

          if flag
            got = lookup(name)
          end
          got.length
        end

        # @param name [String]
        # @return [String, nil]
        def lookup(name); name; end
      ))
      expect(checker.problems.map(&:message))
        .to contain_exactly(a_string_matching(/\AUnresolved call to length on nil, (false|Boolean)\z/))
    end

    it 'narrows a nil-guarded default after the modifier if' do
      checker = type_checker(%(
        # @param tasks [Array<String>, nil]
        # @return [void]
        def guarded_default(tasks)
          tasks = ['a'] if tasks.nil?
          tasks.each { |t| puts t }
        end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'narrows a nil-guarded default after a non-modifier if' do
      checker = type_checker(%(
        # @param tasks [Array<String>, nil]
        # @return [void]
        def guarded_default(tasks)
          if tasks.nil?
            tasks = ['a']
          end
          tasks.each { |t| puts t }
        end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'narrows a guarded default assigned in an unless modifier' do
      checker = type_checker(%(
        # @param tasks [Array<String>, nil]
        # @return [void]
        def guarded_default(tasks)
          tasks = ['a'] unless tasks
          tasks.each { |t| puts t }
        end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'narrows a guarded default assigned in an else clause' do
      checker = type_checker(%(
        # @param tasks [Array<String>, nil]
        # @return [void]
        def guarded_default(tasks)
          if !tasks.nil?
            puts 'have tasks'
          else
            tasks = ['a']
          end
          tasks.each { |t| puts t }
        end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'narrows only the reassigned variable when an or-condition guards it' do
      checker = type_checker(%(
        # @param xs [Array<String>, nil]
        # @param ys [Array<String>, nil]
        # @return [void]
        def or_guard(xs, ys)
          xs = ['a'] if xs.nil? || ys.nil?
          xs.each { |t| puts t }
          ys.each { |t| puts t }
        end
      ))
      expect(checker.problems.map(&:message)).to eq(['Unresolved call to each on Array<String>, nil'])
    end

    it 'keeps nil in the type when the guard tests something other than the variable' do
      checker = type_checker(%(
        # @param tasks [Array<String>, nil]
        # @param flag [Boolean]
        # @return [void]
        def unrelated_guard(tasks, flag)
          tasks = ['a'] if flag
          tasks.each { |t| puts t }
        end
      ))
      expect(checker.problems.map(&:message)).to eq(['Unresolved call to each on Array<String>, nil'])
    end

    it 'keeps nil in the type when the nil guard does not reassign the variable' do
      checker = type_checker(%(
        # @param tasks [Array<String>, nil]
        # @return [void]
        def no_reassignment(tasks)
          puts 'hi' if tasks.nil?
          tasks.each { |t| puts t }
        end
      ))
      expect(checker.problems.map(&:message)).to eq(['Unresolved call to each on Array<String>, nil'])
    end

    it 'keeps nil in the type when the guarded assignment is itself conditional' do
      checker = type_checker(%(
        # @param tasks [Array<String>, nil]
        # @param flag [Boolean]
        # @return [void]
        def nested_conditional_assign(tasks, flag)
          if tasks.nil?
            tasks = ['a'] if flag
          end
          tasks.each { |t| puts t }
        end
      ))
      expect(checker.problems.map(&:message)).to eq(['Unresolved call to each on Array<String>, nil'])
    end

    it 'does not let a loop-body reassignment override a reference textually before it' do
      checker = type_checker(%(
        # @param str [String]
        # @param num [Integer]
        # @param flag [Boolean]
        # @return [void]
        def loop_reassign(str, num, flag)
          local = num
          while flag
            local.abs
            local = str
          end
        end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'updates a local variable type after reassignment to a different literal type' do
      checker = type_checker(%(
        # @return [void]
        def run
          local = 5
          local = 'hello'
          local.upcase
          nil
        end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'updates an instance variable type after reassignment in the same method' do
      checker = type_checker(%(
        class Foo
          # @return [void]
          def run
            @ivar = 5
            @ivar = 'hello'
            @ivar.upcase
            nil
          end
        end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'resolves a self-referential reassignment against the pre-assignment type' do
      checker = type_checker(%(
        class Repro
          # @param x [String]
          # @return [Integer]
          def foo(x)
            x = x.length
          end
        end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'resolves an ivar type when it is assigned only in an ancestor class method' do
      checker = type_checker(%(
        class WidgetBase
          # @return [void]
          def run
            @name = 'set-in-run'
          end
        end

        class Widget < WidgetBase
          # @return [void]
          def test_no_block
            run
            puts @name.upcase
          end
        end
      ))

      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'resolves an ivar type when it is assigned and read within the same class' do
      checker = type_checker(%(
        class Widget
          # @return [void]
          def run
            @name = 'set-in-run'
          end

          # @return [void]
          def test_no_block
            run
            puts @name.upcase
          end
        end
      ))

      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'resolves an ivar type across files when it is assigned only in an ancestor class method' do
      base = Solargraph::Source.load_string(%(
        class WidgetBase
          # @return [void]
          def run
            @name = 'set-in-run'
          end
        end
      ), 'widget_base.rb')
      sub = Solargraph::Source.load_string(%(
        class Widget < WidgetBase
          # @return [void]
          def test_no_block
            run
            puts @name.upcase
          end
        end
      ), 'widget.rb')
      api_map = Solargraph::ApiMap.new
      api_map.catalog(Solargraph::Bench.new(source_maps: [
                                              Solargraph::SourceMap.map(base),
                                              Solargraph::SourceMap.map(sub)
                                            ]))
      checker = described_class.new('widget.rb', api_map: api_map, level: :strong)

      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'supports !@x.nil && @x.y' do
      checker = type_checker(%(
        class Bar
          # @param foo [String, nil]
          def initialize(foo)
            @foo = foo
          end

          def foo?
            !@foo.nil? && @foo.upcase == 'FOO'
          end
        end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'infers a Boolean return from !!(x.nil? || x < n) on a nilable param' do
      checker = type_checker(%(
        # @param val [Integer, nil]
        # @return [Boolean]
        def check?(val)
          !!(val.nil? || val < 5)
        end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'uses cast type instead of defined type' do
      checker = type_checker(%(
        # frozen_string_literal: true

        class Base; end

        class Subclass < Base
          # @return [String]
          attr_reader :bar
        end

        class Foo
          # @param bases [::Array<Base>]
          # @return [void]
          def baz(bases)
            # @param sub [Subclass]
            bases.each do |sub|
              puts sub.bar
            end
          end
        end
      ))

      # expect 'sub' to be treated as 'Subclass' inside the block, and
      # an error when trying to declare sub as Subclass
      expect(checker.problems.map(&:message)).not_to include('Unresolved call to bar on Base')
    end

    it 'resolves Hash#fetch on a literal-keyed Hash with no intersection involved' do
      checker = type_checker(%(
        class Repro
          # @param period [Hash{"Index" => Float}]
          # @return [void]
          def process(period)
            # @type [Float]
            index = period.fetch("Index")
          end
        end
    ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'always dispatches a same-class generic method through the first union member' do
      pending 'Call#inferred_pins binds a generic against the first union/intersection member only'
      checker = type_checker(%(
        class Repro
          # @param period [Hash{"Index" => Float}, Hash{"Triggers" => Array<Hash{"Name" => String}>}]
          # @return [void]
          def process(period)
            # @type [Float]
            index = period.fetch("Index")
          end
        end
    ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    context 'with intersection types' do
      it 'accepts an intersection-typed argument where any one conjunct is expected' do
        checker = type_checker(%(
          class Asana; class Resources; class Project; end; end; end
          class Mocha; class Mock; end; end

          class Consumer
            # @param project_obj [Asana::Resources::Project]
            # @return [void]
            def project_to_h(project_obj); end
          end

          class MockFactory
            # @sg-ignore Mocha::Mock configured with responds_like_instance_of
            #   duck-types as Asana::Resources::Project at every call site.
            # @return [Mocha::Mock & Asana::Resources::Project]
            def make_mock
              Mocha::Mock.new
            end
          end

          Consumer.new.project_to_h(MockFactory.new.make_mock)
      ))
        expect(checker.problems.map(&:message)).to be_empty
      end

      it 'still rejects a plain conjunct type that does not satisfy the expected type' do
        checker = type_checker(%(
          class Asana; class Resources; class Project; end; end; end
          class Mocha; class Mock; end; end

          class Consumer
            # @param project_obj [Asana::Resources::Project]
            # @return [void]
            def project_to_h(project_obj); end
          end

          Consumer.new.project_to_h(Mocha::Mock.new)
      ))
        expect(checker.problems.map(&:message))
          .to include('Wrong argument type for Consumer#project_to_h: project_obj expected Asana::Resources::Project, received Mocha::Mock')
      end

      it 'accepts an intersection-typed argument where the duck-typed conjunct is expected' do
        # Duck-typed subtyping needs *some* conjunct to satisfy it, not
        # specifically the first one that Intersection#namespace/#scope
        # delegate to.
        checker = type_checker(%(
          # @param callback [#quack]
          # @return [void]
          def notify(callback); end

          # @param x [String & #quack]
          # @return [void]
          def relay(x)
            notify(x)
          end
      ))
        expect(checker.problems.map(&:message)).to be_empty
      end

      it 'still rejects an intersection-typed argument when no conjunct satisfies the duck-typed expectation' do
        checker = type_checker(%(
          # @param callback [#quack]
          # @return [void]
          def notify(callback); end

          # @param x [String & Integer]
          # @return [void]
          def relay(x)
            notify(x)
          end
      ))
        expect(checker.problems.map(&:message))
          .to include('Wrong argument type for #notify: callback expected #quack, received String & Integer')
      end

      it 'dispatches generic methods per-conjunct when intersecting two instantiations of the same generic class' do
        # Both conjuncts resolve to a pin with the same path (Hash#fetch)
        # but different, already-resolved return types, so dispatch keys on
        # path *and* return type, then narrows to the conjunct whose key
        # matches the call's literal argument. Overload resolution can't
        # do that on its own, since it runs per conjunct and both
        # conjuncts yield a pin with the same path.
        checker = type_checker(%(
          class Repro
            # @param period [Hash{"Index" => Float} & Hash{"Triggers" => Array<Hash{"Name" => String}>}]
            # @return [void]
            def process(period)
              # @type [Float]
              index = period.fetch("Index")

              # @type [Array<Hash{"Name" => String}>]
              triggers = period.fetch("Triggers")
            end
          end
      ))
        expect(checker.problems.map(&:message)).to be_empty
      end

      it 'dispatches generic methods per-conjunct regardless of conjunct order' do
        checker = type_checker(%(
          class Repro
            # @param period [Hash{"Triggers" => Array<Hash{"Name" => String}>} & Hash{"Index" => Float}]
            # @return [void]
            def process(period)
              # @type [Array<Hash{"Name" => String}>]
              triggers = period.fetch("Triggers")

              # @type [Float]
              index = period.fetch("Index")
            end
          end
      ))
        expect(checker.problems.map(&:message)).to be_empty
      end

      it 'dispatches generic methods per-conjunct for symbol keys' do
        # Symbols already infer as literal types, so per-overload matching
        # rejects the non-matching conjunct on its own here - a pin whose
        # overloads all fail falls through to its declared return type
        # rather than being dropped, so only Call#argument_verified_conjuncts
        # actually removes it.
        checker = type_checker(%(
          class Repro
            # @param period [Hash{:Index => Float} & Hash{:Triggers => Array<Hash{:Name => String}>}]
            # @return [void]
            def process(period)
              # @type [Float]
              index = period.fetch(:Index)

              # @type [Array<Hash{:Name => String}>]
              triggers = period.fetch(:Triggers)
            end
          end
      ))
        expect(checker.problems.map(&:message)).to be_empty
      end

      it 'resolves a non-generic method shared by both conjuncts of a same-class intersection' do
        checker = type_checker(%(
          class Repro
            # @param period [Hash{"Index" => Float} & Hash{"Triggers" => Array<Hash{"Name" => String}>}]
            # @return [void]
            def process(period)
              # @type [Integer]
              n = period.size
            end
          end
      ))
        expect(checker.problems.map(&:message)).to be_empty
      end

      it 'resolves a call to a method defined on just one conjunct of an intersection-typed receiver' do
        # Method lookup gives an intersection's conjuncts "any one is
        # enough" semantics (A & B <: A, A & B <: B), unlike a union, where
        # every alternative has to define the method.
        checker = type_checker(%(
          class A
            # @return [void]
            def foo; end
          end

          class B
            # @return [void]
            def bar; end
          end

          class Factory
            # @sg-ignore A.new duck-types as A & B for this repro
            # @return [A & B]
            def make
              A.new
            end
          end

          Factory.new.make.foo
          Factory.new.make.bar
      ))
        expect(checker.problems.map(&:message)).to be_empty
      end

      it 'dispatches to the conjunct whose parameter type actually accepts the argument' do
        # Same problem as the Hash-record specs above, generalized:
        # narrowing an intersection's conjuncts by argument fit isn't
        # Hash-key-specific, it's ordinary overload matching applied
        # per conjunct instead of per signature.
        checker = type_checker(%(
          class A
            # @param x [String]
            # @return [Integer]
            def pick(x)
              1
            end
          end

          class B
            # @param x [Symbol]
            # @return [Float]
            def pick(x)
              1.0
            end
          end

          class Factory
            # @sg-ignore A.new duck-types as A & B for this repro
            # @return [A & B]
            def make
              A.new
            end
          end

          # @type [Integer]
          from_a = Factory.new.make.pick("hello")

          # @type [Float]
          from_b = Factory.new.make.pick(:hello)
      ))
        expect(checker.problems.map(&:message)).to be_empty
      end

      it 'resolves a call to a method inherited from a common ancestor of both conjuncts' do
        checker = type_checker(%(
          class A
            # @return [void]
            def foo; end
          end

          class B
            # @return [void]
            def bar; end
          end

          class Factory
            # @sg-ignore A.new duck-types as A & B for this repro
            # @return [A & B]
            def make
              A.new
            end
          end

          # @type [String]
          s = Factory.new.make.to_s
      ))
        expect(checker.problems.map(&:message)).to be_empty
      end

      it 'resolves a conjunct method on an intersection-typed local variable, not just a call chain' do
        checker = type_checker(%(
          class A
            # @return [void]
            def foo; end
          end

          class B
            # @return [void]
            def bar; end
          end

          # @sg-ignore A.new duck-types as A & B for this repro
          # @type [A & B]
          value = A.new

          value.foo
          value.bar
      ))
        expect(checker.problems.map(&:message)).to be_empty
      end

      it 'resolves conjunct methods on a three-way intersection' do
        checker = type_checker(%(
          class A
            # @return [void]
            def foo; end
          end

          class B
            # @return [void]
            def bar; end
          end

          class C
            # @return [void]
            def baz; end
          end

          class Factory
            # @sg-ignore A.new duck-types as A & B & C for this repro
            # @return [A & B & C]
            def make
              A.new
            end
          end

          Factory.new.make.foo
          Factory.new.make.bar
          Factory.new.make.baz
      ))
        expect(checker.problems.map(&:message)).to be_empty
      end

      it 'accepts a Hash literal that only sets some of a declared record type keys' do
        # A `# @type [Hash{:k1 => V1} & Hash{:k2 => V2} & ...]` on a local
        # variable declares the full eventual shape a Hash will grow into
        # via later `[]=` calls - see
        # lib/solargraph/language_server/message/base.rb#send_response,
        # which sets :jsonrpc and :id up front and adds :result/:error
        # afterward. The literal only has to satisfy the conjuncts for the
        # keys it already has.
        checker = type_checker(%(
          # @type [Hash{:jsonrpc => String} & Hash{:id => Integer} & Hash{:result => Hash | Array | nil} & Hash{:error => Hash}]
          response = {
            jsonrpc: '2.0',
            id: 5
          }
      ))
        expect(checker.problems.map(&:message)).to be_empty
      end

      it 'still rejects a Hash literal with the wrong value type for a key the declared record type does have' do
        checker = type_checker(%(
          # @type [Hash{:jsonrpc => String} & Hash{:id => Integer} & Hash{:result => Hash | Array | nil} & Hash{:error => Hash}]
          response = {
            jsonrpc: 5,
            id: 5
          }
      ))
        expect(checker.problems.map(&:message))
          .to include(a_string_including('does not match inferred type'))
      end
    end

    it "picks Hash#fetch's Hash::_Key-typed overload for a Symbol key instead of merging in the block form's generic" do
      # https://github.com/castwide/solargraph/issues/1227
      #
      # As of RBS 4.1.0, Hash#fetch's single-argument overload takes
      # its key as the ::Hash::_Key duck-type interface instead of the
      # generic K (see ruby/rbs core/hash.rbs). Solargraph couldn't
      # prove a Symbol argument satisfies that interface, so it fell
      # back to merging the return types of all of Hash#fetch's
      # overloads (including the unresolved block-form's `generic<X>`)
      # instead of picking the single-argument overload.
      checker = type_checker(%(
        class Foo; end

        class Holder
          # @return [Hash{Symbol => Class<Foo>}]
          def registry
            { x: Foo }
          end

          # @return [Foo]
          def use_it
            # @type [Class<Foo>]
            clazz = registry.fetch(:x)
            clazz.new
          end
        end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'resolves a repeated core-method call on a var reassigned mid-method after a reopened-class call' do
      # https://github.com/castwide/solargraph/pull/1288#issuecomment-5273022388
      #
      # Not currently known to be reachable on master: it depends on
      # flow-sensitive-typing pin combination behavior that only exists
      # once certain in-flight branches land (as of this writing,
      # https://github.com/castwide/solargraph/pull/1258 and
      # https://github.com/castwide/solargraph/pull/1282 - verified
      # neither reproduces it alone, only the two combined). Kept here
      # as a standing regression guard so that whatever combination of
      # future changes reintroduces the failure mode gets caught,
      # regardless of merge order.
      checker = type_checker(%(
        class String
          # @return [String]
          def depunctuate
            self
          end
        end

        # @param str [String]
        # @param other [String]
        # @return [String]
        def go(str, other)
          str = str.gsub(other.depunctuate, other)
          str = str.gsub(other, other)
          str.gsub(other, other)
        end
      ))
      expect(checker.problems.map(&:message)).to eq([])
    end

    it 'rebinds self to the new class in Class.new blocks' do
      checker = type_checker(%(
        # @return [void]
        def make_class
          Class.new do
            define_method(:foo) { nil }
          end
          nil
        end
      ))
      expect(checker.problems.map(&:message)).not_to include('Unresolved call to define_method')
    end

    it 'keeps the rebound self in blocks nested inside Class.new blocks' do
      checker = type_checker(%(
        # @param names [Array<Symbol>]
        # @return [void]
        def make_class(names)
          Class.new do
            names.each { |m| define_method(m) { nil } }
          end
          nil
        end
      ))
      expect(checker.problems.map(&:message)).not_to include('Unresolved call to define_method')
    end

    it 'keeps the rebound self in blocks nested inside class_eval blocks' do
      checker = type_checker(%(
        # @param names [Array<Symbol>]
        # @return [void]
        def decorate(names)
          String.class_eval do
            names.each { |m| define_method(m) { nil } }
          end
          nil
        end
      ))
      expect(checker.problems.map(&:message)).not_to include('Unresolved call to define_method')
    end

    # TypeChecker.load_string builds a bare ApiMap, so a gem's own pins -
    # Forwardable's def_delegators among them - are not available. Cataloging
    # a Bench with external_requires loads them.
    #
    # @param code [String]
    # @param requires [::Array<String>]
    # @return [Solargraph::TypeChecker]
    def type_checker_with_gems code, requires
      rules = Solargraph::TypeChecker::Rules.new(:strong, {})
      api_map = Solargraph::ApiMap.new(loose_unions: !rules.require_all_unique_types_support_call?)
      source = Solargraph::Source.load_string(code, 'test.rb')
      api_map.catalog Solargraph::Bench.new(source_maps: [Solargraph::SourceMap.map(source)],
                                            external_requires: requires)
      Solargraph::TypeChecker.new('test.rb', api_map: api_map, level: :strong, rules: rules)
    end

    it 'resolves methods delegated from an instance variable' do
      checker = type_checker_with_gems(%(
        require 'forwardable'

        class Records
          # @return [Integer]
          def size; 3; end
        end

        class Holder
          extend Forwardable

          def_delegators :@records, :size

          # @return [void]
          def initialize
            # @type [Records]
            @records = Records.new
          end

          # @return [Integer]
          def total
            size
          end
        end
      ), ['forwardable'])
      expect(checker.problems).to be_empty
    end

    it 'resolves methods delegated from a class variable' do
      checker = type_checker_with_gems(%(
        require 'forwardable'

        class Records
          # @return [Integer]
          def size; 3; end
        end

        class Holder
          extend Forwardable

          def_delegators :@@records, :size

          # @type [Records]
          @@records = Records.new

          # @return [Integer]
          def total
            size
          end
        end
      ), ['forwardable'])
      expect(checker.problems).to be_empty
    end

    it 'resolves methods delegated through another method' do
      checker = type_checker_with_gems(%(
        require 'forwardable'

        class Records
          # @return [String]
          def label; 'x'; end
        end

        class Holder
          extend Forwardable

          def_delegators :records, :label

          # @return [Records]
          def records
            Records.new
          end

          # @return [String]
          def name
            label
          end
        end
      ), ['forwardable'])
      expect(checker.problems).to be_empty
    end

    it 'takes the @!method tag for a delegation whose receiver does not resolve' do
      checker = type_checker_with_gems(%(
        require 'forwardable'

        class Context
        end

        class Holder
          extend Forwardable

          # @return [Context]
          def context
            Context.new
          end

          # @!method label
          #   @return [String]
          def_delegators :context, :label
        end
      ), ['forwardable'])
      expect(checker.problems).to be_empty
    end

    it 'reports the receiver, not the delegation, when neither declares a type' do
      checker = type_checker_with_gems(%(
        require 'forwardable'

        class Records
          # @return [String]
          def label; 'x'; end
        end

        class Holder
          extend Forwardable

          def records
            @records
          end

          def_delegators :records, :label
        end
      ), ['forwardable'])
      expect(checker.problems.map(&:message)).to contain_exactly('Missing @return tag for Holder#records')
    end

    it 'resolves a delegated method given an alias' do
      checker = type_checker_with_gems(%(
        require 'forwardable'

        class Records
          # @return [Integer]
          def size; 3; end
        end

        class Holder
          extend Forwardable

          def_delegator :@records, :size, :count

          # @return [void]
          def initialize
            # @type [Records]
            @records = Records.new
          end

          # @return [Integer]
          def total
            count
          end
        end
      ), ['forwardable'])
      expect(checker.problems).to be_empty
    end

    it 'passes arguments and blocks through a delegated method' do
      checker = type_checker_with_gems(%(
        require 'forwardable'

        class Records
          # @param n [Integer]
          # @return [String]
          def at(n); 'x'; end

          # @yieldparam item [String]
          # @return [Array<String>]
          def each_item(&blk); ['a'].each(&blk); end
        end

        class Holder
          extend Forwardable

          def_delegators :@records, :at, :each_item

          # @return [void]
          def initialize
            # @type [Records]
            @records = Records.new
          end

          # @return [String]
          def first_at
            at(0)
          end

          # @return [Array<String>]
          def items
            each_item { |item| item.upcase }
          end
        end
      ), ['forwardable'])
      expect(checker.problems).to be_empty
    end

    it 'does not delegate without extending Forwardable' do
      checker = type_checker_with_gems(%(
        require 'forwardable'

        class Records
          # @return [Integer]
          def size; 3; end
        end

        class Holder
          def_delegators :@records, :size

          # @return [void]
          def initialize
            # @type [Records]
            @records = Records.new
          end

          # @return [Integer]
          def total
            size
          end
        end
      ), ['forwardable'])
      expect(checker.problems.map(&:message)).to include('Unresolved call to size')
    end

    it 'does not report the statement that declares a delegation or an alias' do
      checker = type_checker_with_gems(%(
        require 'forwardable'

        class Widget
          extend Forwardable

          # @return [String]
          def name; 'x'; end

          alias_method :title, :name

          def_delegators :@parts, :size

          # @return [void]
          def initialize
            # @type [Array<String>]
            @parts = []
          end

          # @return [String]
          def label
            title
          end

          # @return [Integer]
          def count
            size
          end
        end
      ), ['forwardable'])
      expect(checker.problems).to be_empty
    end

    it 'still reports too few arguments through a Class<Foo<generic<T>>> receiver' do
      checker = type_checker(%(
        # @generic T
        class Box
          # @param a [generic<T>]
          # @return [void]
          def initialize(a); end
        end

        # @generic T
        # @param k [Class<Box<generic<T>>>]
        # @return [Box<generic<T>>]
        def build(k)
          k.new
        end
      ))
      expect(checker.problems.map(&:message)).to eq(['Not enough arguments to Box.new'])
    end

    it 'checks arity against the receiver class initialize, not Class#initialize' do
      checker = type_checker(%(
        # @generic T
        # @param k [Class<Array<generic<T>>>]
        # @return [Array<generic<T>>]
        def build(k)
          k.new(1, 2, 3, 4)
        end
      ))
      expect(checker.problems.map(&:message)).to eq(['Too many arguments to Array.new'])
    end

    it 'infers the return type of a call with a numbered block parameter' do
      checker = type_checker(%(
        # @param xs [Array<String>]
        # @param x [String]
        # @return [Boolean]
        def numbered(xs, x)
          xs.any? { x.include?(_1) }
        end
      ))
      expect(checker.problems).to be_empty
    end

    it 'infers the return type of a call with an explicit block parameter' do
      checker = type_checker(%(
        # @param xs [Array<String>]
        # @param x [String]
        # @return [Boolean]
        def explicit(xs, x)
          xs.any? { |s| x.include?(s) }
        end
      ))
      expect(checker.problems).to be_empty
    end

    it 'treats a numbered block as a block instead of a blockless call' do
      checker = type_checker(%(
        # @param xs [Array<String>]
        # @return [Array<String>]
        def numbered_map(xs)
          xs.map { _1.upcase }
        end
      ))
      expect(checker.problems).to be_empty
    end

    it 'infers the type of a numbered block parameter' do
      checker = type_checker(%(
        # @param xs [Array<String>]
        # @return [Array<String>]
        def numbered_map(xs)
          xs.map { _1.no_such_method }
        end
      ))
      expect(checker.problems.map(&:message)).to include('Unresolved call to no_such_method on String')
    end

    it 'infers the type of an implicit `it` block parameter' do
      checker = type_checker(%(
        # @param xs [Array<String>]
        # @return [Array<String>]
        def it_map(xs)
          xs.map { it.upcase }
        end
      ))
      expect(checker.problems).to be_empty
    end

    it 'catches a return tag that disagrees with an `it` block' do
      checker = type_checker(%(
        # @param xs [Array<String>]
        # @return [Array<Integer>]
        def it_mismatch(xs)
          xs.map { it }
        end
      ))
      expect(checker.problems.map(&:message))
        .to include('Declared return type ::Array<::Integer> does not match inferred type ::Array<::String> for #it_mismatch')
    end

    it 'catches a return tag that disagrees with an explicit block parameter' do
      checker = type_checker(%(
        # @param xs [Array<String>]
        # @return [Array<Integer>]
        def ex_mismatch(xs)
          xs.map { |s| s }
        end
      ))
      expect(checker.problems.map(&:message))
        .to include('Declared return type ::Array<::Integer> does not match inferred type ::Array<::String> for #ex_mismatch')
    end

    it 'accepts `it` used as an argument' do
      checker = type_checker(%(
        # @param xs [Array<String>]
        # @param x [String]
        # @return [Boolean]
        def with_it(xs, x)
          xs.any? { x.include?(it) }
        end
      ))
      expect(checker.problems).to be_empty
    end

    it 'lets a local variable named `it` take precedence over the implicit parameter' do
      checker = type_checker(%(
        # @return [Array<Integer>]
        def shadowed
          it = 5
          ['a'].map { it }
        end
      ))
      expect(checker.problems).to be_empty
    end

    it 'gives a nested block its own parameter alongside an outer `it`' do
      checker = type_checker(%(
        # @param xs [Array<Array<String>>]
        # @return [Array<Array<String>>]
        def nested(xs)
          xs.map { it.map { |s| s.upcase } }
        end
      ))
      expect(checker.problems).to be_empty
    end

    it 'does not invent a parameter for a block that takes none' do
      checker = type_checker(%(
        # @return [Array<Integer>]
        def plain
          [1].map { 5 }
        end
      ))
      expect(checker.problems).to be_empty
    end

    it 'infers String from a backtick command' do
      checker = type_checker(%(
        class Foo
          # @return [String]
          def bar
            `echo hi`.strip
          end
        end
      ))
      expect(checker.problems).to be_empty
    end

    it 'infers String from an interpolated backtick command' do
      checker = type_checker(%q(
        class Foo
          # @return [String]
          def bar
            cmd = 'echo hi'
            `#{cmd}`.strip
          end
        end
      ))
      expect(checker.problems).to be_empty
    end

    it 'resolves top-level methods inside blocks whose self was rebound' do
      checker = type_checker(%(
        # @param type [Class]
        # @return [Boolean]
        def skip_check?(type)
          !type.is_a?(Class)
        end

        # @param mock_sym [Symbol]
        # @param type [Class]
        # @return [void]
        def define_mock(mock_sym, type)
          Object.define_method(mock_sym.to_s) do
            [1].each do |_i|
              skip_check?(type)
            end
          end
          nil
        end
      ))
      expect(checker.problems.map(&:message)).not_to include('Unresolved call to skip_check?')
    end

    it 'resolves top-level methods from an ordinary instance method body' do
      checker = type_checker(%(
        # @return [String]
        def helper
          'x'
        end

        class Report
          # @return [String]
          def call_helper
            helper.upcase
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'resolves top-level methods in a class_eval block body' do
      checker = type_checker(%(
        # @return [String]
        def helper
          'x'
        end

        class Report; end

        Report.class_eval do
          helper.upcase
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'prefers a method on the binder over a top-level method of the same name' do
      checker = type_checker(%(
        # @return [String]
        def label
          'top'
        end

        class Report
          # @return [Integer]
          def label
            42
          end

          # @return [Integer]
          def from_binder
            label.abs
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'prefers a local variable over a top-level method of the same name' do
      checker = type_checker(%(
        # @return [Integer]
        def label
          42
        end

        class Report
          # @return [String]
          def from_local
            label = 'shadow'
            label.upcase
          end
        end
      ))
      expect(checker.problems.map(&:message)).to be_empty
    end

    it 'does not resolve a top-level method called with an explicit receiver' do
      # Top-level defs are private instance methods of Object at runtime, so
      # 'str'.helper raises NoMethodError. Receiverless resolution must not
      # make them reachable through a receiver.
      checker = type_checker(%(
        # @return [String]
        def helper
          'x'
        end

        # @return [Integer]
        def explicit_receiver
          'str'.helper
        end
      ))
      expect(checker.problems.map(&:message)).to include(match(/could not be inferred/))
      expect(checker.problems.map(&:message)).not_to include(match(/does not match inferred/))
    end
  end
end
