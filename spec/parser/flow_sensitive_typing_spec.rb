# frozen_string_literal: true

require 'tempfile'

# @todo These tests depend on `Clip`, but we're putting the tests here to
#   avoid overloading clip_spec.rb.
describe Solargraph::Parser::FlowSensitiveTyping do
  # random temporary filename ending in '.rb' using tmpfile
  let(:filename) { Tempfile.new(['flow_sensitive_typing_spec', '.rb']).path }

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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [6, 10])
    expect(clip.infer.to_s).to eq('Repro')

    clip = api_map.clip_at(filename, [8, 10])
    expect(clip.infer.to_s).to eq('ReproBase')
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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [7, 10])
    expect(clip.infer.to_s).to eq('Repro1')

    clip = api_map.clip_at(filename, [9, 10])
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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [8, 10])
    expect(clip.infer.to_s).to eq('Foo::Repro')

    clip = api_map.clip_at(filename, [10, 10])
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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [10, 10])
    expect(clip.infer.to_s).to eq('Foo::Bar::Repro')

    clip = api_map.clip_at(filename, [12, 10])
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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [6, 10])
    expect(clip.infer.to_s).to eq('ReproBase')

    clip = api_map.clip_at(filename, [8, 10])
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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [6, 10])
    expect(clip.infer.to_s).to eq('Repro1')

    clip = api_map.clip_at(filename, [8, 10])
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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [7, 10])
    expect(clip.infer.to_s).to eq('Repro1')

    clip = api_map.clip_at(filename, [9, 10])
    expect(clip.infer.to_s).to eq('Repro2')

    clip = api_map.clip_at(filename, [11, 10])
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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [7, 8])
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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [7, 8])
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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [7, 8])
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
  ), filename)

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [3, 6])
    expect(clip.infer.to_s).to eq('Array<Numeric>')

    clip = api_map.clip_at(filename, [5, 8])
    expect(clip.infer.to_s).to eq('Numeric')

    clip = api_map.clip_at(filename, [7, 8])
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
    ), filename)

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at(filename, [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer')

    clip = api_map.clip_at(filename, [8, 10])
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
  ), filename)

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [7, 8])
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
  ), filename)

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [7, 8])
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
  ), filename)

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [6, 6])
    expect(clip.infer.to_s).to eq('Foo')

    clip = api_map.clip_at(filename, [8, 6])
    expect(clip.infer.to_s).to eq('Foo')
  end

  it 'skips is_a? without a receiver' do
    source = Solargraph::Source.load_string(%(
    if is_a? Object
      x
    end
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [2, 6])
    expect { clip.infer.to_s }.not_to raise_error
  end

  it 'handles is_a? with a receiver and no argument' do
    source = Solargraph::Source.load_string(%(
    r = '1'
    if r.is_a?
      x
    end
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [3, 6])
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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at(filename, [6, 10])
    expect(clip.infer.rooted_tags).to eq('nil')

    clip = api_map.clip_at(filename, [8, 10])
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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at(filename, [6, 10])
    expect(clip.infer.rooted_tags).to eq('nil')

    clip = api_map.clip_at(filename, [8, 10])
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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at(filename, [6, 10])
    expect(clip.infer.rooted_tags).to eq('nil')

    clip = api_map.clip_at(filename, [8, 10])
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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at(filename, [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at(filename, [8, 10])
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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at(filename, [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at(filename, [8, 10])
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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at(filename, [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at(filename, [8, 10])
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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at(filename, [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at(filename, [8, 10])
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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [4, 33])
    expect(clip.infer.rooted_tags).to eq('::String')

    clip = api_map.clip_at(filename, [4, 8])
    expect(clip.infer.rooted_tags).to eq('::String')

    clip = api_map.clip_at(filename, [5, 8])
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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at(filename, [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer')

    clip = api_map.clip_at(filename, [8, 10])
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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at(filename, [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer')

    clip = api_map.clip_at(filename, [8, 10])
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
    ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [4, 8])
    expect(clip.infer.rooted_tags).to eq('::Integer, nil')

    clip = api_map.clip_at(filename, [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer')

    clip = api_map.clip_at(filename, [8, 10])
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
    ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [3, 8])
    expect(clip.infer.rooted_tags).to eq('nil, ::Integer')

    clip = api_map.clip_at(filename, [5, 10])
    expect(clip.infer.rooted_tags).to eq('::Integer')

    clip = api_map.clip_at(filename, [7, 10])
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
    ), filename)

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [7, 12])
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
    ), filename)

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [6, 10])
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
    ), filename)

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at(filename, [9, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at(filename, [11, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')
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
    ), filename)

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [5, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at(filename, [8, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at(filename, [10, 10])
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
    ), filename)

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [7, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at(filename, [9, 10])
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
    ), filename)

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [6, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at(filename, [8, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at(filename, [11, 10])
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
    ), filename)

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [7, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at(filename, [9, 10])
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
    ), filename)

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [8, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at(filename, [10, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at(filename, [12, 10])
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
    ), filename)

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [5, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at(filename, [6, 44])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at(filename, [6, 51])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at(filename, [7, 10])
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
        ), filename)
    api_map = Solargraph::ApiMap.new.map(source)

    clip = api_map.clip_at(filename, [5, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at(filename, [8, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at(filename, [10, 10])
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
    ), filename)

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [5, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at(filename, [8, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at(filename, [10, 10])
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
    ), filename)

    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [5, 10])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at(filename, [8, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    clip = api_map.clip_at(filename, [10, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean')

    pending('better scoping of return if in begin/rescue/ensure')

    clip = api_map.clip_at(filename, [12, 12])
    expect(clip.infer.rooted_tags).to eq('::Boolean, nil')

    clip = api_map.clip_at(filename, [14, 10])
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
    ), filename)

    api_map = Solargraph::ApiMap.new.map(source)

    clip = api_map.clip_at(filename, [6, 10])
    expect(clip.infer.to_s).to eq('String, nil')

    clip = api_map.clip_at(filename, [7, 17])
    expect(clip.infer.to_s).to eq('nil')

    clip = api_map.clip_at(filename, [8, 10])
    expect(clip.infer.to_s).to eq('String')
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
  ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [5, 17])
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
    ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [9, 10])
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
    ), filename)
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at(filename, [11, 12])
    expect(clip.infer.to_s).to eq('Repro')

    clip = api_map.clip_at(filename, [13, 12])
    expect(clip.infer.to_s).to eq('ReproBase')
  end

  context 'with pattern matching' do
    let(:source) do
      Solargraph::Source.load_string(%(
class Foo; def foo_only; end; end
# @param x [Foo, Integer]
# @param t [Array<String>]
def m(x, t)
  case x
  in Foo => f
    f
    x
  in Integer
    x
  end
  t => [s, n]
  s
  n
  f
  x
end
      ), 'test.rb')
    end

    let(:api_map) { Solargraph::ApiMap.new.map(source) }

    it 'types a const capture' do
      expect(api_map.clip_at('test.rb', [7, 4]).infer.to_s).to eq('Foo, nil')
    end

    it 'narrows the subject in the matching clause' do
      expect(api_map.clip_at('test.rb', [8, 4]).infer.to_s).to eq('Foo')
    end

    it 'narrows the subject separately in the next clause' do
      expect(api_map.clip_at('test.rb', [10, 4]).infer.to_s).to eq('Integer')
    end

    it 'types array-index captures from a one-line => match' do
      expect(api_map.clip_at('test.rb', [13, 2]).infer.to_s).to eq('String')
      expect(api_map.clip_at('test.rb', [14, 2]).infer.to_s).to eq('String')
    end

    it 'keeps a capture visible after the case ends' do
      expect(api_map.clip_at('test.rb', [15, 2]).infer.to_s).to eq('Foo, nil')
    end

    it 'leaves the subject unnarrowed after the case ends' do
      expect(api_map.clip_at('test.rb', [16, 2]).infer.to_s).to eq('Foo, Integer')
    end
  end

  it 'narrows the subject to nil and to a union with nil' do
    source = Solargraph::Source.load_string(%(
      # @param x [String, Integer, nil]
      def m(x)
        case x
        in nil
          x
        in Integer | nil
          x
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [5, 10]).infer.to_s).to eq('nil')
    expect(api_map.clip_at('test.rb', [7, 10]).infer.to_s).to eq('Integer, nil')
  end

  it 'leaves the subject unnarrowed by a value constant pattern' do
    source = Solargraph::Source.load_string(%(
      class Foo
        PATTERN = /abc/

        # @param x [String, Integer]
        def m(x)
          case x
          in PATTERN => f
            x
            f
          end
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [8, 12]).infer.to_s).to eq('String, Integer')
    expect(api_map.clip_at('test.rb', [9, 12]).infer.to_s).to eq('String, Integer, nil')
  end

  it 'narrows captures of an `in` match to non-nil in its true branch' do
    source = Solargraph::Source.load_string(%(
      # @param x [Array<String>, Integer]
      def m(x)
        if x in [String => a]
          a
        elsif x in Integer => i
          i
        end
        a
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [4, 10]).infer.to_s).to eq('String')
    expect(api_map.clip_at('test.rb', [6, 10]).infer.to_s).to eq('Integer')
    expect(api_map.clip_at('test.rb', [8, 8]).infer.to_s).to eq('String, nil')
  end

  it 'lets a reassignment in the true branch replace a narrowed `in` capture' do
    pending 'https://github.com/castwide/solargraph/pull/1338'

    source = Solargraph::Source.load_string(%(
      # @param x [Integer, String]
      # @param y [String]
      def m(x, y)
        if x in Integer => i
          i = y
          i
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [6, 10]).infer.to_s).to eq('String')
  end

  it 'narrows captures of a parenthesized `in` on the right of && in its true branch' do
    source = Solargraph::Source.load_string(%(
      class Foo; end
      # @param a [Boolean]
      # @param x [Array<Object>]
      def m(a, x)
        if a && (x in [_, Foo => y])
          y
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [6, 10]).infer.to_s).to eq('Foo')
  end

  it 'types an alternative capture as the union' do
    source = Solargraph::Source.load_string(%(
      # @param x [String, Integer, Symbol]
      def m(x)
        case x
        in String | Integer => v
          v
          x
        else
          x
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [5, 10]).infer.to_s).to eq('String, Integer, nil')
    expect(api_map.clip_at('test.rb', [6, 10]).infer.to_s).to eq('String, Integer')
    expect(api_map.clip_at('test.rb', [8, 10]).infer.to_s).to eq('String, Integer, Symbol')
  end

  it 'types a bare capture as the subject' do
    source = Solargraph::Source.load_string(%(
      # @param x [String]
      def m(x)
        case x
        in y
          y
        end
        x => z
        z
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [5, 10]).infer.to_s).to eq('String, nil')
    expect(api_map.clip_at('test.rb', [8, 8]).infer.to_s).to eq('String')
  end

  it 'types array-index captures in a case clause' do
    pending 'Captures read by index or rest stay non-nil when the match can fail: BaseVariable cannot add nil to a mass assignment'

    source = Solargraph::Source.load_string(%(
      # @param t [Array<String>]
      def m(t)
        case t
        in [a, b]
          a
          b
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [5, 10]).infer.to_s).to eq('String, nil')
    expect(api_map.clip_at('test.rb', [6, 10]).infer.to_s).to eq('String, nil')
  end

  it 'types tuple-index captures by position' do
    source = Solargraph::Source.load_string(%(
      # @param t [Array(String, Integer)]
      def m(t)
        t => [s, n]
        n
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [4, 8]).infer.to_s).to eq('Integer')
  end

  it 'types captures from a one-line in match' do
    pending 'Captures read by index or rest stay non-nil when the match can fail: BaseVariable cannot add nil to a mass assignment'

    source = Solargraph::Source.load_string(%(
      # @param t [Array<String>]
      def m(t)
        if t in [a, Integer => b]
          a
          b
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [4, 10]).infer.to_s).to eq('String, nil')
    expect(api_map.clip_at('test.rb', [5, 10]).infer.to_s).to eq('Integer, nil')
  end

  it 'types a capture read in a guard' do
    source = Solargraph::Source.load_string(%(
      # @param x [String, Integer]
      def m(x)
        case x
        in String => s if s.empty?
          s
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [4, 26]).infer.to_s).to eq('String, nil')
  end

  it 'narrows an instance variable subject with a const_pattern' do
    source = Solargraph::Source.load_string(%(
      class Point; end
      class Example
        # @param value [Point, Integer]
        def initialize(value)
          @value = value
        end

        def check
          case @value
          in Point(x:)
            @value
          in Integer
            @value
          end
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [11, 12]).infer.to_s).to eq('Point')
    expect(api_map.clip_at('test.rb', [13, 12]).infer.to_s).to eq('Integer')
  end

  it 'maps a capture beside a pinned value' do
    source = Solargraph::Source.load_string(%(
      # @param x [Integer]
      def m(x)
        v = 1
        case x
        in ^v => w
          w
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [6, 10]).locals.map(&:name)).to include('w')
  end

  it 'types rest captures in array and find patterns as Array' do
    pending 'Captures read by index or rest stay non-nil when the match can fail: BaseVariable cannot add nil to a mass assignment'

    source = Solargraph::Source.load_string(%(
      # @param x [Object]
      def m(x)
        case x
        in [a, *rest]
          rest
        in [*, 1, *post]
          post
        end
        x in [*tail]
        tail
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [5, 10]).infer.to_s).to eq('Array, nil')
    expect(api_map.clip_at('test.rb', [7, 10]).infer.to_s).to eq('Array, nil')
    expect(api_map.clip_at('test.rb', [10, 8]).infer.to_s).to eq('Array, nil')
  end

  it 'types rest captures as the core Array inside a namespace with its own Array' do
    pending 'Captures read by index or rest stay non-nil when the match can fail: BaseVariable cannot add nil to a mass assignment'

    source = Solargraph::Source.load_string(%(
      module Foo
        class Array; end

        # @param x [Object]
        def self.m(x)
          x in [*rest]
          rest
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [7, 10]).infer.to_s).to eq('Array, nil')
  end

  it 'types rest captures with the element type of an Array subject' do
    pending 'Captures read by index or rest stay non-nil when the match can fail: BaseVariable cannot add nil to a mass assignment'

    source = Solargraph::Source.load_string(%(
      # @param t [Array<String>]
      def m(t)
        case t
        in [*all]
          all
        in [a, *tail]
          tail
        in [a, *middle, b]
          middle
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [5, 10]).infer.to_s).to eq('Array<String>, nil')
    expect(api_map.clip_at('test.rb', [7, 10]).infer.to_s).to eq('Array<String>, nil')
    expect(api_map.clip_at('test.rb', [9, 10]).infer.to_s).to eq('Array<String>, nil')
  end

  it 'types rest captures from a tuple subject as an Array of the remaining element types' do
    source = Solargraph::Source.load_string(%(
      # @param t [Array(String, Integer)]
      def m(t)
        t => [s, *rest]
        rest
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [4, 8]).infer.to_s).to eq('Array<Integer>')
  end

  it 'types index captures from the return type of the subject deconstruct method' do
    source = Solargraph::Source.load_string(%(
      class Pair
        # @return [Array<Symbol>]
        def deconstruct; end
      end

      # @param pair [Pair]
      def m(pair)
        pair => [a, b]
        a
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [9, 8]).infer.to_s).to eq('Symbol')
  end

  it 'does not read #deconstruct for a multiple assignment' do
    source = Solargraph::Source.load_string(%(
      class Pair
        # @return [Array<Symbol>]
        def deconstruct; end
      end

      # @param pair [Pair]
      def m(pair)
        a, b = pair
        a
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    # Multiple assignment destructures with #to_ary, which Pair lacks, not #deconstruct
    expect(api_map.clip_at('test.rb', [9, 8]).infer.to_s).to eq('undefined')
  end

  it 'does not narrow a subject that the pattern rebinds' do
    source = Solargraph::Source.load_string(%(
      class Pt
        # @return [Array<String>]
        def deconstruct; end
      end

      # @param x [Pt, Integer]
      def m(x)
        case x
        in Pt[x]
          x
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    # x is now the capture, not a Pt; the capture itself is not typed yet
    expect(api_map.clip_at('test.rb', [10, 10]).infer.to_s).not_to eq('Pt')
  end

  it 'types index and rest captures from every member of a union subject' do
    source = Solargraph::Source.load_string(%(
      class Box
        # @return [Array<Integer>]
        def deconstruct; end
      end

      class Untyped
        def deconstruct; end
      end

      # @param x [Array<String>, Box]
      # @param y [Array<String>, Untyped]
      def m(x, y)
        x => [a, *rest]
        a
        rest
        y => [b, *more]
        b
        more
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [14, 8]).infer.to_s).to eq('String, Integer')
    expect(api_map.clip_at('test.rb', [15, 8]).infer.to_s).to eq('Array<String, Integer>')
    expect(api_map.clip_at('test.rb', [17, 8]).infer.to_s).to eq('undefined')
    expect(api_map.clip_at('test.rb', [18, 8]).infer.to_s).to eq('Array')
  end

  it 'leaves index and rest captures unknown for a member with no visible deconstruct' do
    source = Solargraph::Source.load_string(%(
      class Base2; end

      # @param x [Array<String>, Base2]
      # @param y [Array<String>, nil]
      def m(x, y)
        x => [a, *rest]
        a
        rest
        y => [b, *more]
        b
        more
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    # A Base2 subclass may define #deconstruct; nil never does
    expect(api_map.clip_at('test.rb', [7, 8]).infer.to_s).to eq('undefined')
    expect(api_map.clip_at('test.rb', [8, 8]).infer.to_s).to eq('Array')
    expect(api_map.clip_at('test.rb', [10, 8]).infer.to_s).to eq('String')
    expect(api_map.clip_at('test.rb', [11, 8]).infer.to_s).to eq('Array<String>')
  end

  it 'types a multiple assignment from every member of a union' do
    source = Solargraph::Source.load_string(%(
      # @param x [Array<String>, Array<Integer>]
      def m(x)
        c, d = x
        c
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [4, 8]).infer.to_s).to eq('String, Integer')
  end

  it 'leaves a nested capture of a value constant pattern unknown' do
    source = Solargraph::Source.load_string(%(
      class Base
        PAT = /abc/
      end

      # @param x [Array<String>]
      def m(x)
        x => [Base::PAT => h]
        h
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [8, 8]).infer.to_s).to eq('undefined')
  end

  it 'types rest captures from the return type of the subject deconstruct method' do
    source = Solargraph::Source.load_string(%(
      class Pair
        # @return [Array<Symbol>]
        def deconstruct; end
      end

      # @param pair [Pair]
      def m(pair)
        pair => [:left, *rest]
        rest
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    expect(api_map.clip_at('test.rb', [9, 8]).infer.to_s).to eq('Array<Symbol>')
  end

  it 'narrows the other side of a self.class == other.class guard' do
    source = Solargraph::Source.load_string(%(
      class Repro
        # @param other [Object]
        def eql?(other)
          self.class == other.class &&
            name == other.name
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [5, 20])
    expect(clip.infer.to_s).to eq('Repro')
  end

  it 'narrows the other side of a self.class == other.class guard past a return-unless' do
    source = Solargraph::Source.load_string(%(
      class Repro
        # @param other [Object]
        def ==(other)
          return false unless self.class == other.class
          name == other.name
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [5, 18])
    expect(clip.infer.to_s).to eq('Repro')
  end

  it 'leaves the declared type in place without a self.class == other.class guard' do
    source = Solargraph::Source.load_string(%(
      class Repro
        # @param other [Object]
        def eql?(other)
          name == other.name
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [4, 18])
    expect(clip.infer.to_s).to eq('Object')
  end

  it 'does not narrow other via self.class == other.class in a class method' do
    source = Solargraph::Source.load_string(%(
      class Repro
        # @param other [Object]
        def self.same?(other)
          self.class == other.class &&
            name == other.name
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [5, 20])
    expect(clip.infer.to_s).to eq('Object')
  end

  it 'narrows the other side when self is the right-hand side of the class guard' do
    source = Solargraph::Source.load_string(%(
      class Repro
        # @param other [Object]
        def eql?(other)
          other.class == self.class &&
            name == other.name
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [5, 20])
    expect(clip.infer.to_s).to eq('Repro')
  end

  it 'narrows the argument of an instance_of?(other.class) guard' do
    source = Solargraph::Source.load_string(%(
      class Repro
        # @param other [Object]
        def eql?(other)
          instance_of?(other.class) &&
            name == other.name
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [5, 20])
    expect(clip.infer.to_s).to eq('Repro')
  end

  it 'narrows the argument of a self.instance_of?(other.class) guard' do
    source = Solargraph::Source.load_string(%(
      class Repro
        # @param other [Object]
        def eql?(other)
          self.instance_of?(other.class) &&
            name == other.name
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [5, 20])
    expect(clip.infer.to_s).to eq('Repro')
  end

  it 'does not narrow via other.instance_of?(foo.class)' do
    source = Solargraph::Source.load_string(%(
      class Repro
        # @param other [Object]
        # @param foo [Object]
        def eql?(other, foo)
          other.instance_of?(foo.class) &&
            name == other.name
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [6, 20])
    expect(clip.infer.to_s).to eq('Object')
  end

  it 'narrows the receiver of an other.instance_of?(self.class) guard' do
    source = Solargraph::Source.load_string(%(
      class Repro
        # @param other [Object]
        def eql?(other)
          other.instance_of?(self.class) &&
            name == other.name
        end
      end
  ), 'test.rb')
    api_map = Solargraph::ApiMap.new.map(source)
    clip = api_map.clip_at('test.rb', [5, 20])
    expect(clip.infer.to_s).to eq('Repro')
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

  context 'with a Hash key guard' do
    # @param code [String]
    # @param position [Array(Integer, Integer)]
    # @return [String]
    def infer_at code, position
      api_map = Solargraph::ApiMap.new.map(Solargraph::Source.load_string(code, 'test.rb'))
      api_map.clip_at('test.rb', position).infer.to_s
    end

    it 'drops nil from a lookup after return unless key?' do
      code = %(
        # @param h [Hash{String => Integer}]
        # @param k [String]
        def foo h, k
          return 0 unless h.key?(k)
          v = h[k]
          v
        end
      )
      expect(infer_at(code, [6, 10])).to eq('Integer')
    end

    it 'does not offer the narrowed lookup as a local variable completion' do
      code = %(
        # @param h [Hash{String => Integer}]
        # @param k [String]
        def foo h, k
          return 0 unless h.key?(k)
          h
        end
      )
      api_map = Solargraph::ApiMap.new.map(Solargraph::Source.load_string(code, 'test.rb'))
      names = api_map.clip_at('test.rb', [5, 11]).complete.pins.map(&:name)
      expect(names).to include('h')
      expect(names).not_to include('h[k]')
    end

    it 'keeps nil that the Hash values themselves allow' do
      code = %(
        # @param h [Hash{String => Integer, nil}]
        # @param k [String]
        def foo h, k
          w = h[k]
          return 0 unless h.key?(k)
          v = h[k]
          v
          w
        end
      )
      expect(infer_at(code, [7, 10])).to eq(infer_at(code, [8, 10]))
      expect(infer_at(code, [7, 10])).to end_with('nil')
    end

    it 'keeps nil on a lookup without a guard' do
      code = %(
        # @param h [Hash{String => Integer}]
        # @param k [String]
        def foo h, k
          v = h[k]
          v
        end
      )
      expect(infer_at(code, [5, 10])).to eq('Integer, nil')
    end

    it 'narrows only the then clause of if has_key?' do
      code = %(
        # @param h [Hash{String => Integer}]
        # @param k [String]
        def foo h, k
          if h.has_key?(k)
            a = h[k]
            a
          else
            b = h[k]
            b
          end
        end
      )
      expect(infer_at(code, [6, 12])).to eq('Integer')
      expect(infer_at(code, [9, 12])).to eq('Integer, nil')
    end

    it 'narrows the right side of member? &&' do
      code = %(
        # @param h [Hash{Symbol => String}]
        def foo h
          h.member?(:a) && (v = h[:a]) && v
        end
      )
      expect(infer_at(code, [3, 41])).to eq('String')
    end

    it 'does not narrow a lookup of a different key' do
      code = %(
        # @param h [Hash{String => Integer}]
        # @param k [String]
        # @param j [String]
        def foo h, k, j
          return 0 unless h.include?(k)
          v = h[j]
          v
        end
      )
      expect(infer_at(code, [7, 10])).to eq('Integer, nil')
    end

    it 'does not narrow Array#include?' do
      code = %(
        # @param a [Array<String>]
        # @param i [Integer]
        def foo a, i
          return 0 unless a.include?(i)
          v = a[i]
          v
        end
      )
      expect(infer_at(code, [6, 10])).to eq('String, nil')
    end

    it 'stops narrowing once the receiver is reassigned' do
      code = %(
        # @param h [Hash{String => Integer}]
        # @param g [Hash{String => Integer}]
        # @param k [String]
        def foo h, g, k
          return 0 unless h.key?(k)
          h = g
          v = h[k]
          v
        end
      )
      expect(infer_at(code, [8, 10])).to eq('Integer, nil')
    end

    it 'stops narrowing once the key is reassigned' do
      code = %(
        # @param h [Hash{String => Integer}]
        # @param k [String]
        # @param j [String]
        def foo h, k, j
          return 0 unless h.key?(k)
          k = j
          v = h[k]
          v
        end
      )
      expect(infer_at(code, [8, 10])).to eq('Integer, nil')
    end

    it 'stops narrowing once an attr_reader receiver is reassigned' do
      code = %(
        class Foo
          # @return [Hash{String => Integer}]
          attr_reader :table

          # @param k [String]
          def foo k
            return 0 unless table.key?(k)
            a = table[k]
            @table = {}
            b = table[k]
            a
            b
          end
        end
      )
      expect(infer_at(code, [11, 12])).to eq('Integer')
      expect(infer_at(code, [12, 12])).to eq('Integer, nil')
    end

    it 'stops narrowing once a key may have been removed' do
      code = %(
        # @param h [Hash{String => Integer}]
        # @param k [String]
        def foo h, k
          return 0 unless h.key?(k)
          a = h[k]
          h.delete(k)
          b = h[k]
          a
          b
        end
      )
      expect(infer_at(code, [8, 10])).to eq('Integer')
      expect(infer_at(code, [9, 10])).to eq('Integer, nil')
    end

    it 'stops narrowing once a key may have been removed through the ivar of an attr_reader' do
      code = %(
        class Foo
          # @return [Hash{String => Integer}]
          attr_reader :table

          # @param k [String]
          def foo k
            return 0 unless table.key?(k)
            a = table[k]
            @table.delete(k)
            b = table[k]
            a
            b
          end
        end
      )
      expect(infer_at(code, [11, 12])).to eq('Integer')
      expect(infer_at(code, [12, 12])).to eq('Integer, nil')
    end

    it 'stops narrowing once a key may have been removed through self' do
      code = %(
        class Foo
          # @return [Hash{String => Integer}]
          attr_reader :table

          # @param k [String]
          def foo k
            return 0 unless table.key?(k)
            self.table.delete(k)
            v = table[k]
            v
          end
        end
      )
      expect(infer_at(code, [10, 12])).to eq('Integer, nil')
    end

    it 'stops narrowing once a key may have been removed with &.' do
      code = %(
        # @param h [Hash{String => Integer}]
        # @param k [String]
        def foo h, k
          return 0 unless h.key?(k)
          h&.delete(k)
          v = h[k]
          v
        end
      )
      expect(infer_at(code, [7, 10])).to eq('Integer, nil')
    end

    it 'keeps narrowing after a key is removed from another Hash' do
      code = %(
        class Foo
          # @return [Hash{String => Integer}]
          attr_reader :table

          # @param k [String]
          # @param other [Hash{String => Integer}]
          def foo k, other
            return 0 unless table.key?(k)
            @other.delete(k)
            other&.delete(k)
            v = table[k]
            v
          end
        end
      )
      expect(infer_at(code, [12, 12])).to eq('Integer')
    end

    it 'stops narrowing once the key may have been changed in place' do
      code = %(
        # @param h [Hash{String => Integer}]
        # @param k [String]
        # @param j [String]
        def foo h, k, j
          return 0 unless h.key?(k) && h.key?(j)
          a = h[k]
          k << 'x'
          j.upcase!
          b = h[k]
          c = h[j]
          a
          b
          c
        end
      )
      expect(infer_at(code, [11, 10])).to eq('Integer')
      expect(infer_at(code, [12, 10])).to eq('Integer, nil')
      expect(infer_at(code, [13, 10])).to eq('Integer, nil')
    end

    it 'keeps narrowing after a call that copies the key' do
      code = %(
        # @param h [Hash{String => Integer}]
        # @param k [String]
        def foo h, k
          return 0 unless h.key?(k)
          k.upcase
          v = h[k]
          v
        end
      )
      expect(infer_at(code, [7, 10])).to eq('Integer')
    end

    it 'stops narrowing once the keys may have been rewritten' do
      code = %(
        # @param h [Hash{String => Integer}]
        # @param k [String]
        def foo h, k
          return 0 unless h.key?(k)
          h.transform_keys!(&:upcase)
          v = h[k]
          v
        end
      )
      expect(infer_at(code, [7, 10])).to eq('Integer, nil')
    end

    it 'narrows a lookup on an attr_reader but not on another method' do
      code = %(
        class Foo
          # @return [Hash{String => Integer}]
          attr_reader :table

          # @return [Hash{String => Integer}]
          def fresh_table
            {}
          end

          # @param k [String]
          def foo k
            return 0 unless table.key?(k) && fresh_table.key?(k)
            a = table[k]
            b = fresh_table[k]
            a
            b
          end
        end
      )
      expect(infer_at(code, [15, 12])).to eq('Integer')
      expect(infer_at(code, [16, 12])).to eq('Integer, nil')
    end

    it 'does not narrow a lookup by a block parameter that shadows the key' do
      code = %(
        # @param h [Hash{String => Integer}]
        # @param k [String]
        # @param keys [Array<String>]
        def foo h, k, keys
          return 0 unless h.key?(k)
          keys.each do |k|
            a = h[k]
            a
          end
          b = h[k]
          b
        end
      )
      expect(infer_at(code, [8, 12])).to eq('Integer, nil')
      expect(infer_at(code, [11, 10])).to eq('Integer')
    end

    it 'narrows a lookup by the guarded key inside a block' do
      code = %(
        # @param h [Hash{String => Integer}]
        # @param k [String]
        # @param keys [Array<String>]
        def foo h, k, keys
          return 0 unless h.key?(k)
          keys.each do |j|
            a = h[k]
            a
          end
        end
      )
      expect(infer_at(code, [8, 12])).to eq('Integer')
    end

    it 'does not narrow a lookup on a block parameter that shadows the Hash' do
      code = %(
        # @param h [Hash{String => Integer}]
        # @param k [String]
        # @param hashes [Array<Hash{String => Integer}>]
        def foo h, k, hashes
          return 0 unless h.key?(k)
          hashes.each do |h|
            a = h[k]
            a
          end
        end
      )
      expect(infer_at(code, [8, 12])).to eq('Integer, nil')
    end

    it 'does not narrow a key computed by a method call' do
      code = %(
        # @param h [Hash{String => Integer}]
        # @param k [Symbol]
        def foo h, k
          return 0 unless h.key?(k.to_s)
          v = h[k.to_s]
          v
        end
      )
      expect(infer_at(code, [6, 10])).to eq('Integer, nil')
    end

    it 'drops nil from a lookup after an ||= on it' do
      code = %(
        # @param h [Hash{String => Array<Integer>}]
        # @param k [String]
        def foo h, k
          h[k] ||= []
          v = h[k]
          v
        end
      )
      expect(infer_at(code, [6, 10])).to eq('Array<Integer>')
    end

    it 'does not narrow a lookup after an ||= inside an expression' do
      code = %(
        # @param h [Hash{String => Array<Integer>}]
        # @param k [String]
        def foo h, k
          bar && (h[k] ||= [])
          v = h[k]
          v
        end
      )
      expect(infer_at(code, [6, 10])).to eq('Array<Integer>, nil')
    end

    it 'ends the ||= fact at a write to the key' do
      code = %(
        # @param h [Hash{String => Array<Integer>}]
        # @param k [String]
        def foo h, k
          h[k] ||= []
          k = 'other'
          v = h[k]
          v
        end
      )
      expect(infer_at(code, [7, 10])).to eq('Array<Integer>, nil')
    end

    it 'narrows a class variable lookup after an ||= on it' do
      code = %(
        class Foo
          # @type [Hash{Symbol => Array<Integer>}]
          @@table = {}

          # @param k [Symbol]
          def self.foo k
            @@table[k] ||= []
            v = @@table[k]
            v
          end
        end
      )
      expect(infer_at(code, [9, 12])).to eq('Array<Integer>')
    end

    it 'still defines a guarded lookup as Hash#[]' do
      code = %(
        # @param h [Hash{String => Integer}]
        # @param k [String]
        def foo h, k
          return 0 unless h.key?(k)
          h[k]
        end
      )
      api_map = Solargraph::ApiMap.new.map(Solargraph::Source.load_string(code, 'test.rb'))
      expect(api_map.clip_at('test.rb', [5, 14]).define.map(&:path)).to eq(['Hash#[]'])
    end

    it 'still offers Hash#[] signatures in a guarded lookup' do
      code = %(
        # @param h [Hash{String => Integer}]
        # @param k [String]
        def foo h, k
          return 0 unless h.key?(k)
          h.[](k)
        end
      )
      api_map = Solargraph::ApiMap.new.map(Solargraph::Source.load_string(code, 'test.rb'))
      expect(api_map.clip_at('test.rb', [5, 15]).signify.map(&:path)).to eq(['Hash#[]'])
    end

    it 'does not add a local variable for the guarded lookup' do
      code = %(
        # @param h [Hash{String => Integer}]
        # @param k [String]
        def foo h, k
          return 0 unless h.key?(k)
          h[k]
        end
      )
      api_map = Solargraph::ApiMap.new.map(Solargraph::Source.load_string(code, 'test.rb'))
      names = api_map.source_map('test.rb').locals.grep(Solargraph::Pin::LocalVariable).map(&:name)
      expect(names.uniq).to contain_exactly('h', 'k')
    end

    it 'does not narrow a local that shadows a guarded attr_reader' do
      code = %(
        class Foo
          # @return [Hash{String => Integer}]
          attr_reader :table

          # @param k [String]
          # @param other [Hash{String => Integer}]
          def foo k, other
            return 0 unless table.key?(k)
            table = other
            v = table[k]
            v
          end
        end
      )
      expect(infer_at(code, [11, 12])).to eq('Integer, nil')
    end

    it 'narrows self.table after a table.key? guard' do
      code = %(
        class Foo
          # @return [Hash{String => Integer}]
          attr_reader :table

          # @param k [String]
          # @param other [Hash{String => Integer}]
          def foo k, other
            return 0 unless table.key?(k)
            a = self.table[k]
            table = other
            b = self.table[k]
            a
            b
          end
        end
      )
      expect(infer_at(code, [12, 12])).to eq('Integer')
      expect(infer_at(code, [13, 12])).to eq('Integer')
    end
  end

  describe '#parse_receiver_chain' do
    let(:typing) { described_class.new([], [], nil, nil) }

    # @param code [String]
    # @return [Array<String>, nil]
    def chain_of code
      typing.send(:parse_receiver_chain, Solargraph::Parser.parse(code))
    end

    it 'names a bare call' do
      expect(chain_of('foo')).to eq(['foo'])
    end

    it 'names a chain of argument-less calls on a variable' do
      expect(chain_of('@foo.bar.baz')).to eq(['@foo', 'bar', 'baz'])
    end

    it 'rejects a call with arguments' do
      expect(chain_of('foo.bar(1)')).to be_nil
    end

    it 'rejects a chain rooted at a call with arguments' do
      expect(chain_of('foo(1).bar')).to be_nil
    end
  end
end
