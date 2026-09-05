# frozen_string_literal: true

# @todo These tests depend on `Clip`, but we're putting the tests here to
#   avoid overloading clip_spec.rb.
describe Solargraph::Parser::FlowSensitiveTyping do
  it 'uses is_a? in a simple if() to refine types' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro < ReproBase; end
      # @param repr [ReproBase]
      def verify_repro(repr)
        if repr.is_a?(Repro)
          repr
        else
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.to_s).to eq('Repro')

    clip = api_map.clip_at('test.rb', [8, 10])
    expect(clip.infer.to_s).to eq('ReproBase')
  end

  it 'narrows to an intersection when is_a? checks an unrelated mix-in' do
    source = Solargraph::Source.load_string(%(
      module M; end
      class T; end
      # @param t [T]
      def verify(t)
        if t.is_a?(M)
          t
        else
          t
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.to_s).to eq('T & M')

    clip = api_map.clip_at('test.rb', [8, 10])
    expect(clip.infer.to_s).to eq('T')
  end

  it 'does not build a redundant intersection when the mix-in is already included' do
    source = Solargraph::Source.load_string(%(
      module M; end
      class T
        include M
      end
      # @param t [T]
      def verify(t)
        if t.is_a?(M)
          t
        else
          t
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 10])
    expect(clip.infer.to_s).to eq('T')

    clip = api_map.clip_at('test.rb', [9, 10])
    expect(clip.infer.to_s).to eq('T')
  end

  it 'uses is_a? in a simple if() with a union to refine types' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro1 < ReproBase; end
      class Repro2 < ReproBase; end
      # @param repr [Repro1, Repro2]
      def verify_repro(repr)
        if repr.is_a?(Repro1)
          repr
        else
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 10])
    expect(clip.infer.to_s).to eq('Repro1')

    clip = api_map.clip_at('test.rb', [9, 10])
    expect(clip.infer.to_s).to eq('Repro2')
  end

  it 'uses is_a? in a simple if() to refine types on a module-scoped class' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      module Foo
        class Repro < ReproBase; end
      end
      # @param repr [ReproBase]
      def verify_repro(repr)
        if repr.is_a?(Foo::Repro)
          repr
        else
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [8, 10])
    expect(clip.infer.to_s).to eq('Foo::Repro')

    clip = api_map.clip_at('test.rb', [10, 10])
    expect(clip.infer.to_s).to eq('ReproBase')
  end

  it 'uses is_a? in a simple if() to refine types on a double-module-scoped class' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      module Foo
        module Bar
          class Repro < ReproBase; end
        end
      end
      # @param repr [ReproBase]
      def verify_repro(repr)
        if repr.is_a?(Foo::Bar::Repro)
          repr
        else
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [10, 10])
    expect(clip.infer.to_s).to eq('Foo::Bar::Repro')

    clip = api_map.clip_at('test.rb', [12, 10])
    expect(clip.infer.to_s).to eq('ReproBase')
  end

  it 'uses is_a? in a simple if() to refine types on a root-scoped (::-prefixed) class' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      module Foo
        class Repro < ReproBase; end
      end
      # @param repr [ReproBase]
      def verify_repro(repr)
        if repr.is_a?(::Foo::Repro)
          repr
        else
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [8, 10])
    expect(clip.infer.to_s).to eq('Foo::Repro')

    clip = api_map.clip_at('test.rb', [10, 10])
    expect(clip.infer.to_s).to eq('ReproBase')
  end

  it 'uses is_a? with a ::-prefixed class combined via && in a guard clause to refine types' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro < ReproBase; end
      # @param repr [ReproBase]
      # @return [void]
      def verify_repro(repr)
        return unless repr.is_a?(::Repro) && repr.respond_to?(:foo)
        repr
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 8])
    expect(clip.infer.to_s).to eq('Repro')
  end

  it 'uses is_a? with a ::-prefixed class in an elsif to refine types in the branch body' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro1 < ReproBase; end
      class Repro2 < ReproBase; end
      # @param repr [ReproBase]
      def verify_repro(repr)
        if repr.is_a?(Repro1)
          repr
        elsif repr.is_a?(::Repro2) && repr.respond_to?(:foo)
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [9, 10])
    expect(clip.infer.to_s).to eq('Repro2')
  end

  it 'uses is_a? in a simple unless statement to refine types' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro < ReproBase; end
      # @param repr [ReproBase]
      def verify_repro(repr)
        unless repr.is_a?(Repro)
          repr
        else
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.to_s).to eq('ReproBase')

    clip = api_map.clip_at('test.rb', [8, 10])
    expect(clip.infer.to_s).to eq('Repro')
  end

  it 'uses is_a? in an if-then-else() to refine types' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro1 < ReproBase; end
      # @param repr [ReproBase]
      def verify_repro(repr)
        if repr.is_a?(Repro1)
          repr
        else
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.to_s).to eq('Repro1')

    clip = api_map.clip_at('test.rb', [8, 10])
    expect(clip.infer.to_s).to eq('ReproBase')
  end

  it 'uses is_a? in a if-then-elsif-else() to refine types' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro1 < ReproBase; end
      class Repro2 < ReproBase; end
      # @param repr [ReproBase]
      def verify_repro(repr)
        if repr.is_a?(Repro1)
          repr
        elsif repr.is_a?(Repro2)
          repr
        else
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 10])
    expect(clip.infer.to_s).to eq('Repro1')

    clip = api_map.clip_at('test.rb', [9, 10])
    expect(clip.infer.to_s).to eq('Repro2')

    clip = api_map.clip_at('test.rb', [11, 10])
    expect(clip.infer.to_s).to eq('ReproBase')
  end

  it 'narrows a case/when subject to the matched class inside each branch' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro1 < ReproBase; end
      class Repro2 < ReproBase; end
      # @param repr [ReproBase]
      def verify_repro(repr)
        case repr
        when Repro1
          repr
        when Repro2
          repr
        else
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [8, 10])
    expect(clip.infer.to_s).to eq('Repro1')

    clip = api_map.clip_at('test.rb', [10, 10])
    expect(clip.infer.to_s).to eq('Repro2')

    clip = api_map.clip_at('test.rb', [12, 10])
    expect(clip.infer.to_s).to eq('ReproBase')
  end

  it 'narrows a case/when subject to a union when a when clause has multiple values' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro1 < ReproBase; end
      class Repro2 < ReproBase; end
      class Repro3 < ReproBase; end
      # @param repr [ReproBase]
      def verify_repro(repr)
        case repr
        when Repro1, Repro2
          repr
        when Repro3
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [9, 10])
    expect(clip.infer.to_s).to eq('Repro1, Repro2')
  end

  it 'narrows a case/when subject to the matched class for an ivar subject' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro1 < ReproBase; end
      class Foo
        # @param repr [ReproBase]
        def initialize(repr)
          @repr = repr
        end

        # @return [void]
        def verify
          case @repr
          when Repro1
            @repr
          end
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [13, 12])
    expect(clip.infer.to_s).to eq('Repro1')
  end

  it 'does not narrow a case/when subject when a when clause value is not a simple constant' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro1 < ReproBase; end
      # @param repr [ReproBase]
      def verify_repro(repr)
        case repr
        when Repro1, some_dynamic_value
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 10])
    expect(clip.infer.to_s).to eq('ReproBase')
  end

  it 'uses is_a? in a "break unless" statement in an .each block to refine types' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro < ReproBase; end
      # @type [Array<ReproBase>]
      foo = bar
      foo.each do |value|
        break unless value.is_a? Repro
        value
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 8])
    expect(clip.infer.to_s).to eq('Repro')
  end

  it 'uses is_a? in a "break unless" statement in an until to refine types' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro < ReproBase; end
      # @type [ReproBase]
      value = bar
      until is_done()
        break unless value.is_a? Repro
        value
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 8])
    expect(clip.infer.to_s).to eq('Repro')
  end

  it 'uses is_a? in a "break unless" statement in a while to refine types' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro < ReproBase; end
      # @type [ReproBase]
      value = bar
      while !is_done()
        break unless value.is_a? Repro
        value
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 8])
    expect(clip.infer.to_s).to eq('Repro')
  end

  it 'uses unless is_a? in a ".each" block to refine types' do
    source = Solargraph::Source.load_string(%(
      # @type [Array<Numeric>]
      arr = [1, 2, 4, 4.5]
      arr
      arr.each do |value|
        value
        break unless value.is_a? Float

        value
      end
  ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [3, 6])
    expect(clip.infer.to_s).to eq('Array<Numeric>')

    clip = api_map.clip_at('test.rb', [5, 8])
    expect(clip.infer.to_s).to eq('Numeric')

    clip = api_map.clip_at('test.rb', [7, 8])
    expect(clip.infer.to_s).to eq('Float')
  end

  it 'uses varname in a simple if()' do
    source = Solargraph::Source.load_string(%(
      # @param repr [Integer, nil]
      # @param throw_the_dice [Boolean]
      def verify_repro(repr, throw_the_dice)
        repr
        if repr
          repr
        else
          repr
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer')

    clip = api_map.clip_at('test.rb', [8, 10])
    expect(clip.infer.rooted_tags).to eq('nil')
  end

  it 'uses varname in a "break unless" statement in a while to refine types' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro < ReproBase; end
      # @type [ReproBase, nil]
      value = bar
      while !is_done()
        break unless value
        value
      end
  ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 8])
    expect(clip.infer.to_s).to eq('ReproBase')
  end

  it 'uses varname in a "break if" statement in a while to refine types' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro < ReproBase; end
      # @type [ReproBase, nil]
      value = bar
      while !is_done()
        break if value.nil?
        value
      end
  ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 8])
    expect(clip.infer.to_s).to eq('ReproBase')
  end

  it 'understands compatible reassignments' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @return [Foo]
        def baz; end
      end
      bar = Foo.new
      bar
      bar = Foo.new
      bar
  ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [6, 6])
    expect(clip.infer.to_s).to eq('Foo')

    clip = api_map.clip_at('test.rb', [8, 6])
    expect(clip.infer.to_s).to eq('Foo')
  end

  it 'keeps a definite reassignment visible inside a subsequent if-guard' do
    source = Solargraph::Source.load_string(%(
      def m
        x = nil
        x = 1
        if x
          y = x * 2
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [5, 14])
    expect(clip.infer.rooted_tags).to eq('1')
  end

  it 'skips is_a? without a receiver' do
    source = Solargraph::Source.load_string(%(
    if is_a? Object
      x
    end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [2, 6])
    expect { clip.infer.to_s }.not_to raise_error
  end

  it 'handles is_a? with a receiver and no argument' do
    source = Solargraph::Source.load_string(%(
    r = '1'
    if r.is_a?
      x
    end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [3, 6])
    expect { clip.infer.to_s }.not_to raise_error
  end

  it 'uses nil? in a simple if() to refine nilness' do
    source = Solargraph::Source.load_string(%(
      # @param repr [Integer, nil]
      def verify_repro(repr)
        repr = 10 if floop
        repr
        if repr.nil?
          repr
        else
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.rooted_tags).to eq('nil')

    clip = api_map.clip_at('test.rb', [8, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer')
  end

  it 'uses nil? and && in a simple if() to refine nilness - nil? first' do
    source = Solargraph::Source.load_string(%(
      # @param repr [Integer, nil]
      # @param throw_the_dice [Boolean]
      def verify_repro(repr, throw_the_dice)
        repr
        if repr.nil? && throw_the_dice
          repr
        else
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.rooted_tags).to eq('nil')

    clip = api_map.clip_at('test.rb', [8, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')
  end

  it 'uses nil? and && in a simple if() to refine nilness - nil? second' do
    source = Solargraph::Source.load_string(%(
      # @param repr [Integer, nil]
      # @param throw_the_dice [Boolean]
      def verify_repro(repr, throw_the_dice)
        repr
        if throw_the_dice && repr.nil?
          repr
        else
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.rooted_tags).to eq('nil')

    clip = api_map.clip_at('test.rb', [8, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')
  end

  it 'uses nil? and || in a simple if() - nil? first' do
    source = Solargraph::Source.load_string(%(
      # @param repr [Integer, nil]
      # @param throw_the_dice [Boolean]
      def verify_repro(repr, throw_the_dice)
        repr
        if repr.nil? || throw_the_dice
          repr
        else
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at('test.rb', [8, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer')
  end

  it 'uses nil? and || in a simple if() - nil? second' do
    source = Solargraph::Source.load_string(%(
      # @param repr [Integer, nil]
      # @param throw_the_dice [Boolean]
      def verify_repro(repr, throw_the_dice)
        repr
        if throw_the_dice || repr.nil?
          repr
        else
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at('test.rb', [8, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer')
  end

  it 'uses varname and || in a simple if() - varname first' do
    source = Solargraph::Source.load_string(%(
      # @param repr [Integer, nil]
      # @param throw_the_dice [Boolean]
      def verify_repro(repr, throw_the_dice)
        repr
        if repr || throw_the_dice
          repr
        else
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at('test.rb', [8, 10])
    expect(clip.infer.rooted_tags).to eq('nil')
  end

  it 'uses varname and || in a simple if() - varname second' do
    source = Solargraph::Source.load_string(%(
      # @param repr [Integer, nil]
      # @param throw_the_dice [Boolean]
      def verify_repro(repr, throw_the_dice)
        repr
        if throw_the_dice || repr
          repr
        else
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at('test.rb', [8, 10])
    expect(clip.infer.rooted_tags).to eq('nil')
  end

  it 'uses .nil? and or in an unless' do
    source = Solargraph::Source.load_string(%(
      # @param repr [String, nil]
      # @param throw_the_dice [Boolean]
      def verify_repro(repr)
        repr unless repr.nil? || repr.downcase
        repr
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 33])
    expect(clip.infer.rooted_tags).to eq('::String')

    clip = api_map.clip_at('test.rb', [4, 8])
    expect(clip.infer.rooted_tags).to eq('::String')

    clip = api_map.clip_at('test.rb', [5, 8])
    expect(clip.infer.rooted_tags).to eq('::String, nil')
  end

  it 'uses varname and && in a simple if() - varname first' do
    source = Solargraph::Source.load_string(%(
      # @param repr [Integer, nil]
      # @param throw_the_dice [Boolean]
      def verify_repro(repr, throw_the_dice)
        repr
        if repr && throw_the_dice
          repr
        else
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer')

    clip = api_map.clip_at('test.rb', [8, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')
  end

  it 'uses varname and && in a simple if() - varname second' do
    source = Solargraph::Source.load_string(%(
      # @param repr [Integer, nil]
      # @param throw_the_dice [Boolean]
      def verify_repro(repr, throw_the_dice)
        repr
        if throw_the_dice && repr
          repr
        else
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer')

    clip = api_map.clip_at('test.rb', [8, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')
  end

  it 'uses variable in a simple if() to refine types' do
    source = Solargraph::Source.load_string(%(
      # @param repr [Integer, nil]
      def verify_repro(repr)
        repr = 10 if floop
        repr
        if repr
          repr
        else
          repr
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer')

    clip = api_map.clip_at('test.rb', [8, 10])
    expect(clip.infer.rooted_tags).to eq('nil')
  end

  it 'uses variable in a simple if() to refine types using nil checks' do
    source = Solargraph::Source.load_string(%(
      def verify_repro(repr = nil)
        repr = 10 if floop
        repr
        if repr
          repr
        else
          repr
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [3, 8])
    expect(clip.infer.rooted_tags).to eq('nil, 10')

    clip = api_map.clip_at('test.rb', [5, 10])
    expect(clip.infer.rooted_tags).to eq('10')

    clip = api_map.clip_at('test.rb', [7, 10])
    expect(clip.infer.rooted_tags).to eq('nil, false')
  end

  it 'uses .nil? in a return if() in an if to refine types using nil checks' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param baz [::Boolean, nil]
        # @return [void]
        def bar(baz: nil)
          if rand
            return if baz.nil?
            baz
          end
          baz
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')
  end

  # https://cse.buffalo.edu/~regan/cse305/RubyBNF.pdf
  # https://ruby-doc.org/docs/ruby-doc-bundle/Manual/man-1.4/syntax.html
  it 'uses .nil? in a return if() in a method to refine types using nil checks' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param baz [::Boolean, nil]
        # @return [void]
        def bar(baz: nil)
          return if baz.nil?
          baz
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean')
  end

  it 'uses .nil? in a raise if() in a method to refine types using nil checks' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param baz [::Boolean, nil]
        # @return [void]
        def bar(baz: nil)
          raise 'baz required' if baz.nil?
          baz
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean')
  end

  it 'uses is_a? in a return unless() at the top level of a file (no enclosing method) to refine types' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro < ReproBase; end
      # @type [ReproBase, nil]
      repr = Repro.new
      return unless repr.is_a?(Repro)
      repr
  ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [6, 6])
    expect(clip.infer.to_s).to eq('Repro')
  end

  it 'uses is_a? in a raise unless() at the top level of a class body (no enclosing method) to refine types' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro < ReproBase; end
      class Container
        # @type [ReproBase, nil]
        repr = Repro.new
        raise 'invalid' unless repr.is_a?(Repro)
        repr
      end
  ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 8])
    expect(clip.infer.to_s).to eq('Repro')
  end

  it 'uses .nil? in a raise if() to refine a type used as a call argument' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param baz [::Boolean, nil]
        # @return [void]
        def bar(baz: nil)
          raise 'baz required' if baz.nil?
          accepts_boolean(baz)
        end

        # @param b [::Boolean]
        # @return [void]
        def accepts_boolean(b); end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [6, 27])
    expect(clip.infer.rooted_tags).to eq('::Boolean')
  end

  it 'uses .nil? in a raise if() to refine a type used as a call receiver' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param baz [String, nil]
        # @return [void]
        def bar(baz: nil)
          raise 'baz required' if baz.nil?
          baz.length
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [6, 12])
    expect(clip.infer.rooted_tags).to eq('::String')
  end

  it 'uses .nil? in a raise if() with a multi-statement branch to refine types' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param baz [String, nil]
        # @return [void]
        def bar(baz: nil)
          if baz.nil?
            valid = %w[a b c]
            raise "baz required. Valid: \#{valid.inspect}"
          end
          baz.length
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [9, 12])
    expect(clip.infer.rooted_tags).to eq('::String')
  end

  it 'uses .nil? in a return if() in a block to refine types using nil checks' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param baz [::Boolean, nil]
        # @param arr [Array<Integer>]
        # @return [void]
        def bar(arr, baz: nil)
          baz
          arr.each do |item|
            return if baz.nil?
            baz
          end
          baz
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at('test.rb', [9, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at('test.rb', [11, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')
  end

  it 'uses is_a? in a raise if() in a method to refine types, excluding a parameterized member of the same class' do
    source = Solargraph::Source.load_string(%(
      module Repro
        # @param x [Symbol, Array<Symbol, Array>]
        # @return [Symbol, String]
        def self.as_simple_pred(x)
          raise 'no' if x.is_a?(Array)

          x
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 10])
    expect(clip.infer.rooted_tags).to eq('::Symbol')
  end

  it 'uses is_a? in a raise if() in a method to refine types, leaving an unparameterized member alone' do
    source = Solargraph::Source.load_string(%(
      module Repro
        # @param x [Symbol, Array]
        # @return [Symbol, String]
        def self.as_simple_pred(x)
          raise 'no' if x.is_a?(Array)

          x
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 10])
    expect(clip.infer.rooted_tags).to eq('::Symbol')
  end

  it 'uses is_a? in a raise if() to exclude a narrower parameterized member than the class it tests' do
    # excluding Array also excludes Array<Integer>: every Array<Integer>
    # is an Array, even though is_a?(Array) can't tell them apart.
    source = Solargraph::Source.load_string(%(
      module Repro
        # @param x [Symbol, Array<Integer>]
        # @return [Symbol]
        def self.as_simple_pred(x)
          raise 'no' if x.is_a?(Array)

          x
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 10])
    expect(clip.infer.rooted_tags).to eq('::Symbol')
  end

  it 'uses .nil? in a return if() in an unless to refine types using nil checks' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param baz [::Boolean, nil]
        # @return [void]
        def bar(baz: nil)
          baz
          unless rand
            return if baz.nil?
            baz
          end
          baz
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [5, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at('test.rb', [8, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at('test.rb', [10, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')
  end

  it 'uses .nil? in a return if() in a while to refine types using nil checks' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param baz [::Boolean, nil]
        # @return [void]
        def bar(baz: nil)
          while rand do
            return if baz.nil?
            baz
          end
          baz
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at('test.rb', [9, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')
  end

  it 'uses foo in a a while to refine types using nil checks' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param baz [::Boolean, nil]
        # @param other [::Boolean, nil]
        # @return [void]
        def bar(baz: nil, other: nil)
          baz
          while baz do
            baz
            baz = other
          end
          baz
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at('test.rb', [8, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at('test.rb', [11, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')
  end

  it 'uses .nil? in an until condition to refine types in the loop body' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param baz [::Boolean, nil]
        # @return [void]
        def bar(baz: nil)
          baz
          until baz.nil?
            baz
            break
          end
          baz
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [5, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at('test.rb', [7, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    # the body may run zero times and may break, so nothing is
    # asserted once the loop is over
    clip = api_map.clip_at('test.rb', [10, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')
  end

  it 'uses .nil? in an until condition to refine types in a loop body which reassigns the variable' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param baz [::Boolean, nil]
        # @param other [::Boolean, nil]
        # @return [void]
        def bar(baz: nil, other: nil)
          baz
          until baz.nil?
            baz
            baz = other
          end
          baz
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at('test.rb', [8, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at('test.rb', [11, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')
  end

  it 'does not use a post-condition until to refine types in the loop body' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param baz [::Boolean, nil]
        # @return [void]
        def bar(baz: nil)
          begin
            baz
          end until baz.nil?
          baz
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    # the body runs once before the condition is ever evaluated
    clip = api_map.clip_at('test.rb', [6, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at('test.rb', [8, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')
  end

  it 'uses .nil? in a return if() in an until to refine types using nil checks' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param baz [::Boolean, nil]
        # @return [void]
        def bar(baz: nil)
          until rand do
            return if baz.nil?
            baz
          end
          baz
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at('test.rb', [9, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')
  end

  it 'uses .nil? in a return if() in a switch/case/else to refine types using nil checks' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param baz [::Boolean, nil]
        # @return [void]
        def bar(baz: nil)
          case rand
          when 0..0.5
            return if baz.nil?
            baz
          else
            baz
          end
          baz
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [8, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at('test.rb', [10, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at('test.rb', [12, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')
  end

  it 'uses .nil? in a return if() in a ternary operator to refine types using nil checks' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param baz [::Boolean, nil]
        # @return [void]
        def bar(baz: nil)
          baz
          rand > 0.5 ? (return if baz.nil?; baz) : baz
          baz
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [5, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at('test.rb', [6, 44])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at('test.rb', [6, 51])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at('test.rb', [7, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')
  end

  it 'uses .nil? in a return if() in a begin/end to refine types using nil checks' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param baz [::Boolean, nil]
        # @return [void]
        def bar(baz: nil)
          baz
          begin
            return if baz.nil?
            baz
          end
          baz
        end
      end
        ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)

    clip = api_map.clip_at('test.rb', [5, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at('test.rb', [8, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at('test.rb', [10, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean')
  end

  it 'uses .nil? in a return if() in a ||= to refine types using nil checks' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param baz [::Boolean, nil]
        # @return [void]
        def bar(baz: nil)
          baz
          baz ||= begin
            return if baz.nil?
            baz
          end
          baz
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [5, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at('test.rb', [8, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at('test.rb', [10, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean')
  end

  it 'narrows a plain ||= assignment on an lvar to eliminate nil' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro < ReproBase; end
      # @param repr [Repro, nil]
      # @return [void]
      def verify_repro(repr)
        repr ||= Repro.new
        repr
      end
  ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 8])
    expect(clip.infer.to_s).to eq('Repro')
  end

  it 'narrows a ||= assignment on a keyword param to eliminate nil, with no nested nil check' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param baz [::Boolean, nil]
        # @return [void]
        def bar(baz: nil)
          baz
          baz ||= true
          baz
        end
      end
  ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [5, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at('test.rb', [7, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean')
  end

  it 'uses .nil? in a return if() in a try / rescue / ensure to refine types using nil checks' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param baz [::Boolean, nil]
        # @return [void]
        def bar(baz: nil)
          baz
          begin
            return if baz.nil?
            baz
          rescue StandardError
            baz
          ensure
            baz
          end
          baz
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [5, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at('test.rb', [8, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at('test.rb', [10, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    pending('better scoping of return if in begin/rescue/ensure')

    clip = api_map.clip_at('test.rb', [12, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at('test.rb', [14, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')
  end

  it 'provides a useful pin after a return if .nil?' do
    source = Solargraph::Source.load_string(%(
      class A
        # @param b [Hash{String => String}]
        # @return [void]
        def a b
          c = b["123"]
          c
          return c if c.nil?
          c
        end
      end
    ), 'test.rb')

    api_map = Solargraph::ApiMap.new.map(source)

    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.to_s).to eq('String, nil')

    clip = api_map.clip_at('test.rb', [7, 17])
    expect(clip.infer.to_s).to eq('nil')

    clip = api_map.clip_at('test.rb', [8, 10])
    expect(clip.infer.to_s).to eq('String')
  end

  it 'narrows a bare, implicit-self attr_reader-style accessor assigned into a fresh local variable' do
    source = Solargraph::Source.load_string(%(
      class Repro
        # @return [Array<Hash>, nil]
        attr_reader :steps

        def identify
          return nil if steps.nil?

          local = steps
          local.empty?
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [9, 15])
    expect(clip.infer.rooted_tags).to eq('::Array<::Hash>')
  end

  it 'narrows a bare, implicit-self attr_reader-style accessor assigned into a fresh local ' \
     'variable after a truthy guard' do
    source = Solargraph::Source.load_string(%(
      class Repro
        # @return [Array<Hash>, nil]
        attr_reader :steps

        def identify
          return nil unless steps

          local = steps
          local.empty?
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [9, 15])
    expect(clip.infer.rooted_tags).to eq('::Array<::Hash>')
  end

  it 'uses ! to detect nilness' do
    source = Solargraph::Source.load_string(%(
      class A
        # @param a [Integer, nil]
        # @return [Integer]
        def foo a
          return a unless !a
          123
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [5, 17])
    expect(clip.infer.to_s).to eq('Integer')
  end

  it 'supports !@x.nil && @x.y' do
    source = Solargraph::Source.load_string(%(
      class Bar
        # @param foo [String, nil]
        def initialize(foo)
          @foo = foo
        end

        def foo?
          out = !@foo.nil? && @foo.upcase == 'FOO'
          out
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [9, 10])
    expect(clip.infer.to_s).to eq('Boolean')
  end

  it 'uses is_a? with instance variables to refine types' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro < ReproBase; end
      class Example
        # @param value [ReproBase]
        def initialize(value)
          @value = value
        end

        def check
          if @value.is_a?(Repro)
            @value
          else
            @value
          end
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [11, 12])
    expect(clip.infer.to_s).to eq('Repro')

    clip = api_map.clip_at('test.rb', [13, 12])
    expect(clip.infer.to_s).to eq('ReproBase')
  end

  it 'narrows a repeated call to the same attr_reader-style accessor after a truthy guard' do
    source = Solargraph::Source.load_string(%(
      class Location
        # @return [String]
        def filename; end
      end

      class Pin
        # @return [Location, nil]
        attr_reader :location
      end

      # @param pin [Pin]
      def bundled_filename(pin)
        return nil unless pin.location
        pin.location
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [13, 32])
    expect(clip.infer.rooted_tags).to eq('::Location, nil')

    clip = api_map.clip_at('test.rb', [14, 14])
    expect(clip.infer.rooted_tags).to eq('::Location')
  end

  it 'narrows a repeated call to the same attr_reader-style accessor after a .nil? guard' do
    source = Solargraph::Source.load_string(%(
      class Location
        # @return [String]
        def filename; end
      end

      class Pin
        # @return [Location, nil]
        attr_reader :location
      end

      # @param pin [Pin]
      def bundled_filename(pin)
        return nil if pin.location.nil?
        pin.location.filename
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [14, 23])
    expect(clip.infer.rooted_tags).to eq('::String')
  end

  it 'narrows a bare, implicit-self attr_reader-style accessor after a .nil? guard' do
    source = Solargraph::Source.load_string(%(
      class Repro
        # @return [Array<Hash>, nil]
        attr_reader :steps

        def identify
          return nil if steps.nil?
          steps.empty?
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 15])
    expect(clip.infer.rooted_tags).to eq('::Array<::Hash>')
  end

  it 'narrows a bare, implicit-self attr_reader-style accessor after a truthy guard' do
    source = Solargraph::Source.load_string(%(
      class Repro
        # @return [Array<Hash>, nil]
        attr_reader :steps

        def identify
          return nil unless steps
          steps.empty?
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 15])
    expect(clip.infer.rooted_tags).to eq('::Array<::Hash>')
  end

  it 'narrows a repeated call to the same attr_reader-style accessor rooted in an ivar' do
    source = Solargraph::Source.load_string(%(
      class Location
        # @return [String]
        def filename; end
      end

      class Pin
        # @return [Location, nil]
        attr_reader :location
      end

      class Bundler
        # @param pin [Pin]
        def initialize(pin)
          @pin = pin
        end

        def bundled_filename
          return nil unless @pin.location
          @pin.location.filename
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [19, 26])
    expect(clip.infer.rooted_tags).to eq('::String')
  end

  it 'uses is_a? with a fully-qualified type name to refine types' do
    source = Solargraph::Source.load_string(%(
      # @param x [Object]
      def verify_repro(x)
        if x.is_a?(::Integer)
          x
        else
          x
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer')

    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Object')
  end

  it 'uses != against a literal symbol to refine types out of a union' do
    source = Solargraph::Source.load_string(%(
      # @param sections [Array<String>, :not_specified]
      def verify_repro(sections)
        if sections != :not_specified
          sections
        else
          sections
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 10])
    expect(clip.infer.to_s).to eq('Array<String>')

    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.to_s).to eq(':not_specified')
  end

  it 'uses == against a literal symbol to refine types down to a member of a union' do
    source = Solargraph::Source.load_string(%(
      # @param sections [Array<String>, :not_specified]
      def verify_repro(sections)
        if sections == :not_specified
          sections
        else
          sections
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 10])
    expect(clip.infer.to_s).to eq(':not_specified')

    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.to_s).to eq('Array<String>')
  end

  it 'uses unless with == against a literal symbol to refine types out of a union' do
    source = Solargraph::Source.load_string(%(
      # @param sections [Array<String>, :not_specified]
      def verify_repro(sections)
        unless sections == :not_specified
          sections
        else
          sections
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 10])
    expect(clip.infer.to_s).to eq('Array<String>')

    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.to_s).to eq(':not_specified')
  end

  it 'uses is_a? in an || to narrow to the union of both checked types' do
    source = Solargraph::Source.load_string(%(
      class Repro
        # @param e [Array<Symbol>, String]
        # @return [void]
        def eval_function_call(e); end

        # @param e [Array<Symbol>, String, Integer]
        # @return [void]
        def eval(e)
          if e.is_a?(Array) || e.is_a?(String)
            e
          end
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [10, 12])
    expect(clip.infer.to_s).to eq('Array<Symbol>, String')
  end

  it 'does not narrow via || when only one side of the check is is_a? (negative control)' do
    source = Solargraph::Source.load_string(%(
      class Repro
        # @param e [Array<Symbol>, String]
        # @return [void]
        def eval_function_call(e); end

        # @param e [Array<Symbol>, String, Integer]
        # @return [void]
        def eval(e)
          if e.is_a?(Array)
            e
          end
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [10, 12])
    expect(clip.infer.to_s).to eq('Array<Symbol>')
  end

  it 'does not invent a narrowing across || when the two is_a? checks test different variables (soundness control)' do
    source = Solargraph::Source.load_string(%(
      class Repro
        # @param x [Array<Symbol>, Integer]
        # @param y [String, Integer]
        # @return [void]
        def eval(x, y)
          if x.is_a?(Array) || y.is_a?(String)
            x
          end
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [7, 12])
    expect(clip.infer.to_s).to eq('Array<Symbol>, Integer')
  end

  it 'narrows an opaque receiver to a duck type from a respond_to? guard' do
    source = Solargraph::Source.load_string(%(
      # @param obj [Object]
      def duckish(obj)
        if obj.respond_to?(:fetch_thing)
          obj
        else
          obj
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 10])
    expect(clip.infer.to_s).to eq('#fetch_thing')

    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.to_s).to eq('Object')
  end

  it 'selects the union arms providing the method from a respond_to? guard' do
    source = Solargraph::Source.load_string(%(
      # @param data [Hash{String => Integer}, Array<Integer>]
      def pick(data)
        if data.respond_to?(:key?)
          data
        else
          data
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 10])
    expect(clip.infer.to_s).to eq('Hash{String => Integer}')

    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.to_s).to eq('Hash{String => Integer}, Array<Integer>')
  end

  it 'narrows through respond_to? combined with && in a guard' do
    source = Solargraph::Source.load_string(%(
      # @param data [Hash{String => Integer}, Array<Integer>]
      # @param subkey [String]
      # @return [Integer, nil]
      def flex(data, subkey)
        return data[subkey] if data.respond_to?(:key?) && data.key?(subkey)

        nil
      end
  ), 'test.rb')
    checker = Solargraph::TypeChecker.load_string(source.code, 'test.rb', :strong)
    expect(checker.problems.map(&:message)).to eq([])
  end

  it 'does not narrow from respond_to? with a non-literal argument' do
    source = Solargraph::Source.load_string(%(
      # @param obj [Object]
      # @param name [Symbol]
      def dynamic(obj, name)
        if obj.respond_to?(name)
          obj
        else
          obj
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [5, 10])
    expect(clip.infer.to_s).to eq('Object')
  end

  it 'uses instance_of? in a simple if() to refine a bare Object' do
    source = Solargraph::Source.load_string(%(
      # @param arg [Object]
      def convert(arg)
        if arg.instance_of?(Hash)
          arg
        else
          arg
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 10])
    expect(clip.infer.to_s).to eq('Hash')

    # the false path of instance_of? is not a sound exclusion - a
    # subclass instance fails instance_of?(Hash) while still being a
    # Hash - so the declared type is left alone there
    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.to_s).to eq('Object')
  end

  it 'uses instance_of? in a modifier-unless guard clause to refine the fall-through' do
    source = Solargraph::Source.load_string(%(
      # @param arg [Object]
      def convert(arg)
        return arg unless arg.instance_of? String

        arg
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [5, 8])
    expect(clip.infer.to_s).to eq('String')
  end

  it 'uses instance_of? in a modifier-if to refine within the guarded expression' do
    source = Solargraph::Source.load_string(%(
      # @param arg [Object]
      # @return [Object]
      def convert(arg)
        return arg.map { |item| item } if arg.instance_of? Array

        arg
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(Solargraph::TypeChecker.new('test.rb', api_map: api_map, level: :strong)
      .problems.map(&:message)).to eq([])
  end

  it 'uses instance_of? to select an arm of a union' do
    source = Solargraph::Source.load_string(%(
      class ReproBase; end
      class Repro < ReproBase; end
      # @param repr [ReproBase, String]
      def verify_repro(repr)
        if repr.instance_of?(ReproBase)
          repr
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.to_s).to eq('ReproBase')
  end

  it 'leaves the declared type in place when instance_of? has no static class name' do
    source = Solargraph::Source.load_string(%(
      # @param arg [String]
      # @param other [Object]
      def convert(arg, other)
        if arg.instance_of?(other.class)
          arg
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [5, 10])
    expect(clip.infer.to_s).to eq('String')
  end

  it 'does not narrow a different variable than the one guarded' do
    source = Solargraph::Source.load_string(%(
      # @param arg [Object]
      # @param other [Object]
      def convert(arg, other)
        if arg.instance_of?(String)
          other
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [5, 10])
    expect(clip.infer.to_s).to eq('Object')
  end

  it 'narrows a never-assigned ivar from an instance_variable_defined? guard' do
    source = Solargraph::Source.load_string(%(
      module LogMethod
        # @return [void]
        def log_something
          return unless instance_variable_defined?(:@logger) && @logger.respond_to?(:puts)
          @logger.puts('hi')
        end
      end
  ), 'test.rb')
    checker = Solargraph::TypeChecker.load_string(source.code, 'test.rb', :strong)
    expect(checker.problems.map(&:message)).to eq([])
  end

  it 'still reports an unguarded read of a never-assigned ivar as unresolved' do
    source = Solargraph::Source.load_string(%(
      module LogMethod
        # @return [void]
        def log_something
          return unless instance_variable_defined?(:@logger) && @logger.respond_to?(:puts)
          @logger.puts('hi')
        end

        # @return [void]
        def log_unguarded
          @logger.puts('unguarded')
        end
      end
  ), 'test.rb')
    checker = Solargraph::TypeChecker.load_string(source.code, 'test.rb', :strong)
    expect(checker.problems.map(&:message)).to eq(['Unresolved call to @logger'])
  end

  it 'narrows a never-assigned ivar from an instance_variable_defined? guard in a simple if()' do
    source = Solargraph::Source.load_string(%(
      def check
        if instance_variable_defined?(:@foo)
          @foo
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [3, 10])
    expect(clip.infer.to_s).to eq('Object')
  end

  it 'does not narrow instance_variable_defined? with a non-literal argument' do
    source = Solargraph::Source.load_string(%(
      def check(name)
        if instance_variable_defined?(name)
          @foo
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [3, 10])
    expect { clip.infer.to_s }.not_to raise_error
  end

  it 'does not narrow instance_variable_defined? with an explicit receiver' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param other [Object]
        # @return [void]
        def check(other)
          return unless other.instance_variable_defined?(:@bar)
          @bar.to_s
        end
      end
  ), 'test.rb')
    checker = Solargraph::TypeChecker.load_string(source.code, 'test.rb', :strong)
    expect(checker.problems.map(&:message)).to eq(['Unresolved call to @bar'])
  end

  it 'does not narrow a call to a different method than instance_variable_defined?' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @return [void]
        def check
          return unless instance_variable_get(:@bar)
          @bar.to_s
        end
      end
  ), 'test.rb')
    checker = Solargraph::TypeChecker.load_string(source.code, 'test.rb', :strong)
    expect(checker.problems.map(&:message)).to eq(['Unresolved call to @bar'])
  end

  it 'does not synthesize a pin when the instance_variable_defined? argument does not start with @' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @return [void]
        def check
          return unless instance_variable_defined?(:bar)
          @bar.to_s
        end
      end
  ), 'test.rb')
    checker = Solargraph::TypeChecker.load_string(source.code, 'test.rb', :strong)
    expect(checker.problems.map(&:message)).to eq(['Unresolved call to @bar'])
  end

  it 'narrows an existing ivar assignment to non-nil via instance_variable_defined?' do
    source = Solargraph::Source.load_string(%(
      class Foo
        # @param val [Integer, nil]
        def initialize(val)
          @bar = val
        end

        # @return [Integer]
        def check
          return 0 unless instance_variable_defined?(:@bar)
          @bar
        end
      end
  ), 'test.rb')
    checker = Solargraph::TypeChecker.load_string(source.code, 'test.rb', :strong)
    expect(checker.problems.map(&:message)).to eq([])
  end

  # The next two exercise defensive guards in
  # FlowSensitiveTyping#process_instance_variable_defined that no real
  # parsed source can reach through its only caller, #process_calls:
  # that caller already filters to :send nodes before calling it, and
  # #process_if/#process_while/etc. always hand it a closure built from
  # a Region (which defaults to an anonymous Pin::Namespace, never
  # nil). Calling the private method directly is the only way to cover
  # them.
  it 'does nothing when there is no enclosing closure' do
    node = Solargraph::Parser.parse('instance_variable_defined?(:@bar)', 'test.rb', 0)
    ivars = []
    typing = described_class.new([], ivars, nil, nil, nil)
    range = Solargraph::Range.from_node(node)
    typing.send(:process_instance_variable_defined, node, [range], [])
    expect(ivars).to eq([])
  end

  it 'ignores a non-send node' do
    node = Solargraph::Parser.parse('1', 'test.rb', 0)
    ivars = []
    typing = described_class.new([], ivars, nil, nil, nil)
    expect { typing.send(:process_instance_variable_defined, node, [], []) }.not_to raise_error
    expect(ivars).to eq([])
  end

  it 'uses kind_of? in a simple if() to refine types' do
    source = Solargraph::Source.load_string(%(
      # @param arg [String, Integer]
      def convert(arg)
        if arg.kind_of?(String)
          arg
        else
          arg
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 10])
    expect(clip.infer.to_s).to eq('String')

    clip = api_map.clip_at('test.rb', [6, 10])
    expect(clip.infer.to_s).to eq('Integer')
  end

  it 'uses kind_of? in a modifier-unless guard clause to refine the fall-through' do
    source = Solargraph::Source.load_string(%(
      # @param arg [Object]
      def convert(arg)
        return arg unless arg.kind_of? String

        arg
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [5, 8])
    expect(clip.infer.to_s).to eq('String')
  end

  it 'keeps the guarded arm on the false path of instance_of?, unlike is_a?' do
    # a Repro value declared as ReproBase fails instance_of?(ReproBase)
    # while still being a ReproBase, so the false path cannot exclude
    # the ReproBase arm the way is_a? can
    isa_source = %(
      class ReproBase; end
      class Repro < ReproBase; end
      # @param repr [ReproBase, String]
      def verify_repro(repr)
        if repr.%s(ReproBase)
          repr
        else
          repr
        end
      end
  )

    source = Solargraph::Source.load_string(format(isa_source, 'instance_of?'), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [6, 10]).infer.to_s).to eq('ReproBase')
    expect(api_map.clip_at('test.rb', [8, 10]).infer.to_s).to eq('ReproBase, String')

    %w[is_a? kind_of?].each do |method_name|
      source = Solargraph::Source.load_string(format(isa_source, method_name), 'test.rb')
      api_map = Solargraph::ApiMap.new.map(source)
      expect(api_map.clip_at('test.rb', [6, 10]).infer.to_s).to eq('ReproBase')
      expect(api_map.clip_at('test.rb', [8, 10]).infer.to_s).to eq('String')
    end
  end
end
